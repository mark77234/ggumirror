//
//  ShardWalletTests.swift
//  ggumirrorTests
//
//  조각 잔액은 **서버가 정한다.**
//
//  여기서 지키는 것:
//  1. client에 잔액을 더하거나 빼는 통로가 없다
//  2. 로그인 전에는 0이고, 로그인하면 서버 값을 그대로 보여준다
//  3. 로그아웃은 화면만 지운다 — 서버 지갑과 로컬 콘텐츠는 그대로다
//

import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import ggumirror

/// 서버 응답을 원하는 대로 고정하는 가짜 backend.
final class FakeShardBackend: ShardBackend, @unchecked Sendable {
    var result: Result<ShardBalance, BackendError>
    private(set) var receivedTokens: [String] = []

    /// 출석. 서버가 하루의 진실을 쥐고 있으므로 test도 서버 응답만 바꾼다.
    var attendanceResult: Result<AttendanceStatus, BackendError> =
        .success(AttendanceStatus(attendanceDate: "2026-08-16", claimed: false))
    var claimResult: Result<AttendanceClaim, BackendError> =
        .success(AttendanceClaim(attendanceDate: "2026-08-16", claimed: true, reward: 1, balance: 1))
    private(set) var claimCount = 0
    private(set) var attendanceTokens: [String] = []
    /// claim이 이만큼 기다린 뒤에 응답한다. 두 번 누르기를 시험할 때만 쓴다.
    var claimDelay: Duration?

    init(balance: Int = 0, lifetimeEarned: Int = 0, lifetimeSpent: Int = 0) {
        result = .success(ShardBalance(
            balance: balance, lifetimeEarned: lifetimeEarned, lifetimeSpent: lifetimeSpent
        ))
    }

    func shards(accessToken: String) async throws -> ShardBalance {
        receivedTokens.append(accessToken)
        return try result.get()
    }

    func attendance(accessToken: String) async throws -> AttendanceStatus {
        attendanceTokens.append(accessToken)
        return try attendanceResult.get()
    }

    func claimAttendance(accessToken: String) async throws -> AttendanceClaim {
        claimCount += 1
        attendanceTokens.append(accessToken)
        if let claimDelay { try? await Task.sleep(for: claimDelay) }
        return try claimResult.get()
    }

    // MARK: 광고 보상 — 서버가 세는 값이다

    var rewardedAdsResult: Result<RewardedAdStatus, BackendError> =
        .success(RewardedAdStatus(rewardedToday: 0, remainingToday: 5, dailyLimit: 5))
    var contextResult: Result<String, BackendError> = .success("reward-context-1")
    private(set) var rewardedAdsFetchCount = 0
    private(set) var contextCount = 0
    /// SSV가 늦게 도착하는 상황: 지갑을 이만큼 더 읽은 뒤에야 보상이 반영된다.
    var rewardArrivesAfterFetches: Int?

    func rewardedAds(accessToken: String) async throws -> RewardedAdStatus {
        rewardedAdsFetchCount += 1
        if let arrival = rewardArrivesAfterFetches, rewardedAdsFetchCount > arrival {
            return RewardedAdStatus(rewardedToday: 1, remainingToday: 4, dailyLimit: 5)
        }
        return try rewardedAdsResult.get()
    }

    func rewardedAdContext(accessToken: String) async throws -> String {
        contextCount += 1
        return try contextResult.get()
    }
}

@MainActor
struct ShardWalletTests {

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

    // MARK: - 서버 값을 보여준다

    @Test("로그인하면 서버 잔액을 그대로 보여준다")
    func showsServerBalance() async {
        let backend = FakeShardBackend(balance: 12, lifetimeEarned: 30, lifetimeSpent: 18)
        let wallet = ShardWallet(backend: backend)

        await wallet.refresh(session: session())

        #expect(wallet.balance == 12)
        #expect(wallet.lifetimeEarned == 30)
        #expect(wallet.lifetimeSpent == 18)
        #expect(backend.receivedTokens == ["server-token"])
    }

    @Test("로그인 전에는 0이고 서버를 부르지 않는다")
    func signedOutIsZero() async {
        let backend = FakeShardBackend(balance: 99)
        let wallet = ShardWallet(backend: backend)

        await wallet.refresh(session: nil)

        #expect(wallet.balance == 0)
        #expect(backend.receivedTokens.isEmpty, "로그인 없이 서버를 불렀다")
    }

    @Test("만료된 세션으로는 서버를 부르지 않는다")
    func expiredSessionIsZero() async {
        let backend = FakeShardBackend(balance: 99)
        let wallet = ShardWallet(backend: backend)

        await wallet.refresh(session: session(expiresIn: -60))

        #expect(wallet.balance == 0)
        #expect(backend.receivedTokens.isEmpty)
    }

    @Test("서버가 새 잔액을 주면 그것이 최종이다 — server wins")
    func serverWins() async {
        let backend = FakeShardBackend(balance: 50)
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())
        #expect(wallet.balance == 50)

        // 다른 기기에서 조각을 썼다.
        backend.result = .success(ShardBalance(balance: 30, lifetimeEarned: 50, lifetimeSpent: 20))
        await wallet.refresh(session: session())

        #expect(wallet.balance == 30, "서버 값이 최종이어야 한다")
    }

    @Test("서버에 닿지 못하면 마지막 값을 유지한다")
    func keepsLastValueOnFailure() async {
        let backend = FakeShardBackend(balance: 7)
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())

        backend.result = .failure(.unavailable)
        await wallet.refresh(session: session())

        // 조각이 사라진 것처럼 보이면 안 된다.
        #expect(wallet.balance == 7)
    }

    // MARK: - 로그아웃 / 재로그인

    @Test("로그아웃은 화면만 지운다")
    func logoutClearsDisplayOnly() async {
        let backend = FakeShardBackend(balance: 25)
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())
        #expect(wallet.balance == 25)

        await wallet.refresh(session: nil)
        #expect(wallet.balance == 0)

        // 서버 지갑은 그대로다 — 다시 로그인하면 돌아온다.
        await wallet.refresh(session: session())
        #expect(wallet.balance == 25)
    }

    // MARK: - client에 권위가 없다

    @Test("client에 잔액을 바꾸는 통로가 없다")
    func clientCannotMutateBalance() throws {
        let source = codeOnly(try repoFile("ggumirror/Shared/ShardWallet.swift"))

        // 잔액을 더하거나 빼는 코드가 없다.
        for forbidden in ["balance +=", "balance -=", "balance = balance", "func credit", "func debit",
                          "func add", "func spend", "func grant"] {
            #expect(!source.contains(forbidden), "client가 잔액을 바꾸고 있다: \(forbidden)")
        }
        // 밖에서 balance를 대입할 수 없다.
        #expect(source.contains("private(set) var balance"))
    }

    @Test("backend에도 조각을 바꾸는 요청이 없다")
    func noShardMutationRequest() throws {
        let source = codeOnly(try repoFile("ggumirror/Backend/BackendClient.swift"))
        #expect(source.contains("users/me/shards"))
        // 읽기(GET)뿐이다.
        for forbidden in ["shards/credit", "shards/debit", "shards/add", "wallet/add", "wallet/set"] {
            #expect(!source.contains(forbidden))
        }

        let protocolSource = codeOnly(try repoFile("ggumirror/Shared/ShardWallet.swift"))
        #expect(protocolSource.contains("func shards(accessToken: String) async throws -> ShardBalance"))
        // protocol에 쓰기 연산 자체가 없다.
        #expect(!protocolSource.contains("func credit"))
        #expect(!protocolSource.contains("func debit"))
    }

    @Test("임시 하드코딩 잔액이 사라졌다")
    func temporaryBalanceIsGone() throws {
        for path in ["ggumirror/Shared/InkComponents.swift",
                     "ggumirror/Home/HomeView.swift",
                     "ggumirror/Store/StoreView.swift"] {
            #expect(!(try repoFile(path)).contains("temporaryBalance"))
        }
    }

    // MARK: - 잔액 표시 — 0은 "무료"가 아니다

    @Test("홈은 서버 잔액을 쓰고, 0을 무료라고 하지 않는다")
    func homeShowsBalanceNotFree() throws {
        let home = codeOnly(try repoFile("ggumirror/Home/HomeView.swift"))

        // 잔액은 서버가 준 값이다.
        #expect(home.contains("amount: shards.balance"))
        #expect(!home.contains("temporaryBalance"))
        // 가격이 아니라 잔액이므로 "무료" 변환을 끈다.
        #expect(home.contains("treatsZeroAsFree: false"), "홈 잔액 0이 아직 무료로 표시된다")
        // 홈 화면 자체에 "무료" 문구가 없다.
        #expect(!home.contains("무료"))

        // 상점 잔액 표시도 숫자다.
        let store = codeOnly(try repoFile("ggumirror/Store/StoreView.swift"))
        #expect(store.contains(#"Text("\(shards.balance) 조각")"#))
    }

    @Test("잔액 0과 가격 0은 다르게 보인다")
    func zeroBalanceRendersDifferentlyFromFreePrice() throws {
        let balance = try #require(render(ShardAmount(amount: 0, treatsZeroAsFree: false)))
        let price = try #require(render(ShardAmount(amount: 0)))
        // 가격 0은 "무료", 잔액 0은 "0" — 그려진 결과가 같으면 안 된다.
        #expect(balance != price)

        // 잔액 0과 잔액 12도 서로 다르다(숫자가 실제로 그려진다).
        let twelve = try #require(render(ShardAmount(amount: 12, treatsZeroAsFree: false)))
        #expect(balance != twelve)
    }

    @Test("상점의 실제 무료 상품 표시는 그대로다")
    func freeStoreItemsKeepTheirLabel() throws {
        // 기본값이 가격 규칙이므로 상점 호출부는 손대지 않았다.
        let components = codeOnly(try repoFile("ggumirror/Shared/InkComponents.swift"))
        #expect(components.contains("var treatsZeroAsFree = true"))
        // 단위를 붙일지는 호출부가 정한다. 무료 문구는 그대로다.
        #expect(components.contains(#"Text(isFree ? "무료" : ("#))
        #expect(components.contains(#"amount) 조각"#))

        let store = codeOnly(try repoFile("ggumirror/Store/StoreView.swift"))
        #expect(store.contains("ShardAmount(amount: template.price)"))
        #expect(!store.contains("template.price, treatsZeroAsFree"))

        // 무료 갈래 · 무료로 받기 문구도 그대로 있다.
        #expect(try repoFile("ggumirror/Store/StoreCatalog.swift").contains(#"case free = "무료""#))
        #expect(try repoFile("ggumirror/Store/TemplateDetailView.swift").contains(#""무료로 받기""#))

        // 무료 템플릿은 여전히 0 조각이고 8종이다.
        #expect(StoreCatalog.samples.contains { $0.price == 0 })
        #expect(StoreCatalog.basics.allSatisfy { $0.price == 0 })
    }

    private func render(_ view: some View) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: 90, height: 30))
        renderer.scale = 1
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return nil }
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &data, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(data)
    }

    @Test("서버 응답 모양을 그대로 읽는다")
    func decodesServerShape() throws {
        let json = #"{"balance":12,"lifetimeEarned":30,"lifetimeSpent":18}"#
        let balance = try JSONDecoder.backend.decode(ShardBalance.self, from: Data(json.utf8))
        #expect(balance == ShardBalance(balance: 12, lifetimeEarned: 30, lifetimeSpent: 18))
    }

    @Test("모양이 다르면 읽지 않는다")
    func rejectsUnknownShape() {
        let json = #"{"shards":12}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder.backend.decode(ShardBalance.self, from: Data(json.utf8))
        }
    }

    // MARK: - 로그인 없이 쓰는 기능

    @Test("조각 때문에 로그인 벽을 세우지 않는다")
    func noLoginWall() throws {
        let root = codeOnly(try repoFile("ggumirror/RootView.swift"))
        // 첫 화면은 여전히 Mirror다.
        #expect(root.contains("@State private var screen: Screen = .mirror"))
        // 지갑 갱신이 화면을 막지 않는다(실패해도 그냥 지나간다).
        #expect(root.contains("await shards.refresh(session: session.server)"))
    }
}
