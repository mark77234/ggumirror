//
//  DailyAttendanceTests.swift
//  ggumirrorTests
//
//  출석 조각은 **서버가 준다.**
//
//  여기서 지키는 것:
//  1. client가 잔액을 올리지 않는다 — 반영되는 숫자는 서버가 준 balance뿐이다
//  2. 실패하면 아무 일도 없었던 것이다 — 가짜 +1이 없다
//  3. 로그인 없이 서버를 부르지 않고, 로그인 벽도 세우지 않는다
//  4. 하루의 기준은 서버 날짜다 — client는 날짜를 계산조차 하지 않는다
//

import Foundation
import Testing
@testable import ggumirror

@MainActor
struct DailyAttendanceTests {

    private func session(expiresIn: TimeInterval = 3600) -> ServerSession {
        ServerSession(
            accessToken: "server-token",
            expiresAt: Date(timeIntervalSinceNow: expiresIn),
            userID: "internal-user-1"
        )
    }

    private func repoFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    private func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - 상태 조회

    @Test("로그인하면 서버에 출석 상태를 묻는다")
    func fetchesStatusWhenSignedIn() async {
        let backend = FakeShardBackend(balance: 3)
        let wallet = ShardWallet(backend: backend)

        await wallet.refresh(session: session())

        #expect(wallet.attendance == .available)
        #expect(backend.attendanceTokens == ["server-token"])
    }

    @Test("이미 받은 날이면 완료 상태로 보인다")
    func alreadyClaimedState() async {
        let backend = FakeShardBackend(balance: 1)
        backend.attendanceResult = .success(
            AttendanceStatus(attendanceDate: "2026-08-16", claimed: true)
        )
        let wallet = ShardWallet(backend: backend)

        await wallet.refresh(session: session())

        #expect(wallet.attendance == .claimed)
    }

    @Test("로그인 전에는 서버를 부르지 않는다")
    func signedOutNeverCallsServer() async {
        let backend = FakeShardBackend()
        let wallet = ShardWallet(backend: backend)

        await wallet.refresh(session: nil)
        await wallet.claimAttendance(session: nil)

        #expect(backend.attendanceTokens.isEmpty, "로그인 없이 서버를 불렀다")
        #expect(backend.claimCount == 0)
        #expect(wallet.attendance == .unknown)
        #expect(wallet.balance == 0)
    }

    @Test("만료된 세션으로는 출석하지 않는다")
    func expiredSessionCannotClaim() async {
        let backend = FakeShardBackend()
        let wallet = ShardWallet(backend: backend)

        await wallet.claimAttendance(session: session(expiresIn: -60))

        #expect(backend.claimCount == 0)
        #expect(wallet.balance == 0)
    }

    // MARK: - 출석

    @Test("출석하면 서버가 준 잔액이 그대로 반영된다")
    func claimReflectsServerBalance() async {
        let backend = FakeShardBackend(balance: 4)
        backend.claimResult = .success(
            AttendanceClaim(attendanceDate: "2026-08-16", claimed: true, reward: 1, balance: 5)
        )
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())
        #expect(wallet.balance == 4)

        await wallet.claimAttendance(session: session())

        // 4 + 1을 client가 계산한 것이 아니라 서버가 5라고 답한 것이다.
        #expect(wallet.balance == 5)
        #expect(wallet.attendance == .claimed)
    }

    @Test("서버가 다른 숫자를 주면 그것이 최종이다")
    func serverWinsEvenIfItDisagrees() async {
        let backend = FakeShardBackend(balance: 4)
        // 다른 기기에서 조각을 쓰고 출석까지 한 상태. 서버 말이 맞다.
        backend.claimResult = .success(
            AttendanceClaim(attendanceDate: "2026-08-16", claimed: false, reward: 0, balance: 2)
        )
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())

        await wallet.claimAttendance(session: session())

        #expect(wallet.balance == 2, "client가 자기 값을 우선했다")
    }

    @Test("이미 받은 날 다시 눌러도 조각이 늘지 않는다")
    func duplicateClaimDoesNotAdd() async {
        let backend = FakeShardBackend(balance: 0)
        backend.claimResult = .success(
            AttendanceClaim(attendanceDate: "2026-08-16", claimed: true, reward: 1, balance: 1)
        )
        let wallet = ShardWallet(backend: backend)

        await wallet.claimAttendance(session: session())
        #expect(wallet.balance == 1)

        // 서버는 두 번째 요청에 "오늘은 이미 받았다"고 답한다 — 오류가 아니다.
        backend.claimResult = .success(
            AttendanceClaim(attendanceDate: "2026-08-16", claimed: false, reward: 0, balance: 1)
        )
        await wallet.claimAttendance(session: session())

        #expect(wallet.balance == 1)
        #expect(wallet.attendance == .claimed)
    }

    @Test("응답을 못 받았다가 재시도하면 실제 잔액으로 복구된다")
    func retryAfterLostResponseRecovers() async {
        let backend = FakeShardBackend(balance: 0)
        // 서버는 성공했지만 응답이 client에 닿지 못했다.
        backend.claimResult = .failure(.unavailable)
        let wallet = ShardWallet(backend: backend)

        await wallet.claimAttendance(session: session())

        // 가짜로 올려두지 않는다.
        #expect(wallet.balance == 0)
        #expect(wallet.attendance == .unknown)

        // 다시 누르면 서버가 "이미 받았고 잔액은 1"이라고 답한다.
        backend.claimResult = .success(
            AttendanceClaim(attendanceDate: "2026-08-16", claimed: false, reward: 0, balance: 1)
        )
        await wallet.claimAttendance(session: session())

        #expect(wallet.balance == 1, "서버 잔액으로 복구되지 않았다")
        #expect(wallet.attendance == .claimed)
    }

    @Test("claimed=false + reward=0은 실패가 아니라 '이미 완료'다")
    func alreadyClaimedIsNotAFailure() async {
        let backend = FakeShardBackend(balance: 0)
        // 정상 HTTP 응답이고, 다만 오늘 몫은 이미 지급됐다는 뜻이다.
        backend.claimResult = .success(
            AttendanceClaim(attendanceDate: "2026-08-16", claimed: false, reward: 0, balance: 3)
        )
        let wallet = ShardWallet(backend: backend)

        await wallet.claimAttendance(session: session())

        // 완료 상태로 간다. 오류 화면으로 가지 않는다.
        #expect(wallet.attendance == .claimed)
        // 잔액은 서버가 말한 값이다 — 지급이 없었다고 0으로 되돌리지 않는다.
        #expect(wallet.balance == 3)
        #expect(wallet.isClaiming == false)

        // client에 출석 실패를 표시할 상태 자체가 없다 — 실패는 조용히 아무 일도 안 한 것이다.
        let source = codeOnly(try! repoFile("ggumirror/Shared/ShardWallet.swift"))
        for forbidden in ["attendanceError", "claimFailureMessage", "showsAttendanceError"] {
            #expect(!source.contains(forbidden))
        }
    }

    @Test("네트워크가 실패하면 가짜 +1이 없다")
    func networkFailureAddsNothing() async {
        let backend = FakeShardBackend(balance: 7)
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())

        backend.claimResult = .failure(.unavailable)
        await wallet.claimAttendance(session: session())

        #expect(wallet.balance == 7)
        #expect(wallet.attendance == .available, "실패했는데 받은 것처럼 보인다")
    }

    @Test("두 번 눌러도 요청은 한 번이다")
    func doubleTapSendsOneRequest() async {
        let backend = FakeShardBackend()
        backend.claimDelay = .milliseconds(60)
        let wallet = ShardWallet(backend: backend)

        // 첫 요청이 끝나기 전에 두 번째 tap이 들어온다.
        async let first: Void = wallet.claimAttendance(session: session())
        while !wallet.isClaiming { await Task.yield() }
        await wallet.claimAttendance(session: session())
        await first

        // presentation guard다 — 서버 쪽 보증은 원장의 idempotency가 따로 한다.
        #expect(backend.claimCount == 1)
        #expect(wallet.balance == 1)
    }

    // MARK: - 로그아웃 / 재로그인

    @Test("로그아웃하면 출석 상태도 지워진다")
    func logoutClearsAttendance() async {
        let backend = FakeShardBackend(balance: 5)
        backend.attendanceResult = .success(
            AttendanceStatus(attendanceDate: "2026-08-16", claimed: true)
        )
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())
        #expect(wallet.attendance == .claimed)

        await wallet.refresh(session: nil)

        // 다음 사람에게 남의 출석 상태를 보여주지 않는다.
        #expect(wallet.attendance == .unknown)
        #expect(wallet.balance == 0)
    }

    @Test("다시 로그인하면 서버에 다시 묻는다")
    func reloginRefetches() async {
        let backend = FakeShardBackend(balance: 5)
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())
        await wallet.refresh(session: nil)

        backend.attendanceResult = .success(
            AttendanceStatus(attendanceDate: "2026-08-17", claimed: false)
        )
        await wallet.refresh(session: session())

        #expect(wallet.attendance == .available)
        #expect(wallet.balance == 5)
        #expect(backend.attendanceTokens.count == 2)
    }

    // MARK: - 서버 응답 모양

    @Test("서버 응답 모양을 그대로 읽는다")
    func decodesServerShapes() throws {
        let status = try JSONDecoder.backend.decode(
            AttendanceStatus.self,
            from: Data(#"{"attendanceDate":"2026-08-16","claimed":false}"#.utf8)
        )
        #expect(status == AttendanceStatus(attendanceDate: "2026-08-16", claimed: false))

        let claim = try JSONDecoder.backend.decode(
            AttendanceClaim.self,
            from: Data(#"{"claimed":true,"reward":1,"balance":1,"attendanceDate":"2026-08-16"}"#.utf8)
        )
        #expect(claim == AttendanceClaim(
            attendanceDate: "2026-08-16", claimed: true, reward: 1, balance: 1
        ))
    }

    @Test("모양이 다르면 읽지 않는다")
    func rejectsUnknownShape() {
        #expect(throws: (any Error).self) {
            try JSONDecoder.backend.decode(
                AttendanceClaim.self, from: Data(#"{"claimed":true}"#.utf8)
            )
        }
    }

    // MARK: - client에 권위가 없다

    @Test("client가 날짜 · 금액 · 사용자를 정하지 않는다")
    func clientDecidesNothing() throws {
        let wallet = codeOnly(try repoFile("ggumirror/Shared/ShardWallet.swift"))
        let backend = codeOnly(try repoFile("ggumirror/Backend/BackendClient.swift"))

        // 잔액을 올리는 코드가 없다.
        for forbidden in ["balance +=", "balance -=", "balance = balance + ", "reward +"] {
            #expect(!wallet.contains(forbidden), "client가 잔액을 바꾸고 있다: \(forbidden)")
        }
        // 하루를 client가 계산하지 않는다 — 날짜 계산 도구를 쓰지 않는다.
        for forbidden in ["DateFormatter", "Calendar", "TimeZone", "UserDefaults", "Date()"] {
            #expect(!wallet.contains(forbidden), "client가 날짜를 판단하고 있다: \(forbidden)")
        }
        // 출석 요청에 body를 싣지 않는다.
        #expect(backend.contains(#"send("users/me/attendance", method: "POST", accessToken:"#))
        #expect(!backend.contains("AttendanceRequest"))
    }

    @Test("출석은 전용 통로 하나뿐이다")
    func onlyOneDedicatedRoute() throws {
        let backend = codeOnly(try repoFile("ggumirror/Backend/BackendClient.swift"))
        for forbidden in ["shards/credit", "shards/debit", "shards/add", "wallet/add", "wallet/set"] {
            #expect(!backend.contains(forbidden))
        }
        #expect(backend.contains("users/me/attendance"))
    }

    // MARK: - 화면

    @Test("로그인 안 했으면 기존 Apple 로그인으로 보낸다")
    func signedOutGoesToExistingAuthFlow() throws {
        let home = codeOnly(try repoFile("ggumirror/Home/HomeView.swift"))

        // 홈에 새 로그인 UI를 만들지 않았다 — 설정의 기존 흐름으로 간다.
        #expect(!home.contains("SignInWithAppleButton"))
        #expect(home.contains("NavigationLink(value: SettingsRoute.settings)"))
        #expect(home.contains("attendanceSignIn"))

        // 그 목적지에 실제 Apple 로그인 버튼이 있다.
        let account = try repoFile("ggumirror/Auth/AccountSection.swift")
        #expect(account.contains("SignInWithAppleButton"))
    }

    @Test("홈 CTA는 서버 상태만 보고 그린다")
    func homeUsesServerState() throws {
        let home = codeOnly(try repoFile("ggumirror/Home/HomeView.swift"))

        #expect(home.contains("shards.attendance == .claimed"))
        #expect(home.contains("await shards.claimAttendance(session: session.server)"))
        // 두 번 누르기 방지는 화면에도 둔다(보안 경계는 서버다).
        #expect(home.contains("shards.isClaiming"))
        #expect(home.contains("오늘 출석 완료"))
    }

    @Test("돌아올 때 상태를 다시 읽는다 — polling은 없다")
    func refreshesOnSceneActive() throws {
        let root = codeOnly(try repoFile("ggumirror/RootView.swift"))

        #expect(root.contains("onChange(of: scenePhase)"))
        #expect(root.contains("phase == .active"))
        // 주기적으로 두드리지 않는다.
        #expect(!root.contains("Timer"))
        #expect(!root.contains("Task.sleep"))
    }
}
