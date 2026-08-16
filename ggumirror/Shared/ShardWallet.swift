//
//  ShardWallet.swift
//  ggumirror
//
//  거울 조각 잔액. **서버가 정한 값을 보여주기만 한다.**
//
//  여기서 잔액을 더하거나 빼지 않는다. 앱 안에 `balance += 1` 같은 코드가 있으면
//  그 순간부터 화면의 숫자와 서버의 진실이 갈라지고, 광고 · 결제 · 구매가
//  전부 그 위에 쌓인다. 조각이 움직이는 곳은 서버의 원장 하나뿐이다.
//
//  로그인은 조각을 볼 때만 필요하다 — 거울 · 촬영 · 꾸미기는 로그인 없이 그대로 쓴다.
//

import Foundation

@Observable
@MainActor
final class ShardWallet {
    /// 앱이 쓰는 하나뿐인 지갑. 테스트는 가짜 backend로 자기 것을 만든다.
    static let live = ShardWallet()

    /// 마지막으로 서버에서 받은 잔액. 로그인 전에는 0이다.
    ///
    /// 화면이 덜 깜빡이도록 값을 들고 있을 뿐 **권위가 아니다.**
    /// 다른 기기에서 쓰거나 앱을 지웠다 깔아도 서버 값이 최종이다.
    private(set) var balance = 0
    private(set) var lifetimeEarned = 0
    private(set) var lifetimeSpent = 0
    private(set) var isLoading = false

    /// 오늘 출석 조각을 받을 수 있는지. **서버가 답한다.**
    ///
    /// 기기 날짜 · timezone · UserDefaults로 판단하지 않는다 — 하루의 기준은
    /// 서버 시계의 Asia/Seoul 날짜 하나뿐이다. 아직 물어보지 못했으면 `.unknown`이고,
    /// 그 상태에서 눌러도 안전하다(받을 수 있는지는 어차피 서버가 정한다).
    enum Attendance: Sendable { case unknown, available, claimed }

    private(set) var attendance: Attendance = .unknown

    /// 오늘 광고 보상을 몇 번 받았는지. **서버가 세는 값**이다 —
    /// 앱이 광고를 몇 번 봤는지 세지 않는다. 광고를 봤다고 보상이 확정되는 것도 아니다.
    private(set) var rewardedToday = 0
    private(set) var remainingAdsToday = 0
    private(set) var dailyAdLimit = 0
    /// 출석 요청 중. 버튼을 두 번 누르는 것을 막는 **표시용** 장치다 —
    /// 보안 경계가 아니다. 서버 API를 직접 반복 호출해도 +1은 정확히 한 번이다.
    private(set) var isClaiming = false

    private let backend: any ShardBackend

    init(backend: any ShardBackend = BackendClient()) {
        self.backend = backend
    }

    /// 서버에서 다시 받아온다. 로그인돼 있지 않으면 아무것도 하지 않고 0으로 둔다.
    func refresh(session: ServerSession?) async {
        guard let session, session.isValid() else {
            clear()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let wallet = try await backend.shards(accessToken: session.accessToken)
            balance = wallet.balance
            lifetimeEarned = wallet.lifetimeEarned
            lifetimeSpent = wallet.lifetimeSpent
        } catch {
            // 서버에 닿지 못했다. 마지막으로 본 값을 그대로 둔다 —
            // 임의로 0으로 만들면 "조각이 사라졌다"처럼 보인다.
            ShardLog.event("wallet refresh failed")
        }

        // 출석은 따로 묻는다. 한쪽이 실패해도 다른 쪽 표시를 잃지 않는다.
        do {
            attendance = try await backend.attendance(accessToken: session.accessToken).claimed
                ? .claimed
                : .available
        } catch {
            ShardLog.event("attendance refresh failed")
        }

        // 광고 보상 횟수도 서버가 답한다.
        do {
            let ads = try await backend.rewardedAds(accessToken: session.accessToken)
            rewardedToday = ads.rewardedToday
            remainingAdsToday = ads.remainingToday
            dailyAdLimit = ads.dailyLimit
        } catch {
            ShardLog.event("rewarded ads refresh failed")
        }
    }

    /// 오늘의 조각을 받는다. **여기서 잔액을 더하지 않는다** —
    /// 반영하는 것은 서버가 계산해서 돌려준 `balance`뿐이다.
    ///
    /// 이미 받은 날이면 서버가 `claimed=false, reward=0`과 **실제 잔액**을 돌려준다.
    /// 그래서 응답을 못 받아 다시 눌러도 잔액이 부풀지 않고 오히려 제자리를 찾는다.
    func claimAttendance(session: ServerSession?) async {
        guard let session, session.isValid() else { return }
        guard !isClaiming else { return }

        isClaiming = true
        defer { isClaiming = false }

        do {
            let result = try await backend.claimAttendance(accessToken: session.accessToken)
            balance = result.balance
            attendance = .claimed
        } catch {
            // 실패했으면 아무 일도 없었던 것이다. 가짜로 +1 하지 않는다.
            ShardLog.event("attendance claim failed")
        }
    }

    /// 로그아웃. **서버 지갑은 그대로 있고** 이 기기의 표시만 지운다.
    func clear() {
        balance = 0
        lifetimeEarned = 0
        lifetimeSpent = 0
        // 다음 사람의 출석 / 광고 상태를 물려주지 않는다. 다시 로그인하면 서버에 다시 묻는다.
        attendance = .unknown
        rewardedToday = 0
        remainingAdsToday = 0
        dailyAdLimit = 0
    }
}

// MARK: - 서버 값

nonisolated struct ShardBalance: Decodable, Equatable, Sendable {
    let balance: Int
    let lifetimeEarned: Int
    let lifetimeSpent: Int
}

/// `GET /users/me/attendance`. `attendanceDate`는 **서버가 정한 KST 날짜**다 —
/// 표시용 참고값이고, 하루가 바뀌었는지 client가 계산하지 않는다.
nonisolated struct AttendanceStatus: Decodable, Equatable, Sendable {
    let attendanceDate: String
    let claimed: Bool
}

/// `POST /users/me/attendance`. `claimed`는 **이번 호출이 지급했는가**이고,
/// `balance`는 언제나 서버 원장이 계산한 현재 잔액이다.
nonisolated struct AttendanceClaim: Decodable, Equatable, Sendable {
    let attendanceDate: String
    let claimed: Bool
    let reward: Int
    let balance: Int
}

/// 조각을 **읽는** 통로와, 이유가 정해진 **전용** 통로 하나뿐이다.
/// 금액 · 사용자 · 날짜를 client가 정하는 함수는 없다 —
/// 그런 것이 있으면 서버가 client를 믿는 구조가 된다.
nonisolated protocol ShardBackend: Sendable {
    func shards(accessToken: String) async throws -> ShardBalance
    func attendance(accessToken: String) async throws -> AttendanceStatus
    /// 보내는 값이 없다. 누구인지는 session, 며칠인지는 서버 시계, 얼마인지는 서버가 정한다.
    func claimAttendance(accessToken: String) async throws -> AttendanceClaim
    func rewardedAds(accessToken: String) async throws -> RewardedAdStatus
    /// 광고에 실어 보낼 opaque context. **조각을 지급하는 요청이 아니다.**
    func rewardedAdContext(accessToken: String) async throws -> String
}

/// `GET /users/me/rewarded-ads`. 오늘 몇 번 받았는지는 **서버가 센다.**
nonisolated struct RewardedAdStatus: Decodable, Equatable, Sendable {
    let rewardedToday: Int
    let remainingToday: Int
    let dailyLimit: Int
}

// MARK: - 로그

nonisolated enum ShardLog {
    static func event(_ message: String) {
        #if DEBUG
        print("[Shards] \(message)")
        #endif
    }
}
