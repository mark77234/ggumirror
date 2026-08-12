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
    }

    /// 로그아웃. **서버 지갑은 그대로 있고** 이 기기의 표시만 지운다.
    func clear() {
        balance = 0
        lifetimeEarned = 0
        lifetimeSpent = 0
    }
}

// MARK: - 서버 값

nonisolated struct ShardBalance: Decodable, Equatable, Sendable {
    let balance: Int
    let lifetimeEarned: Int
    let lifetimeSpent: Int
}

/// 조각을 **읽는** 통로만 있다. 더하거나 빼는 함수는 없다 —
/// 그런 것이 client에 있으면 서버가 client를 믿는 구조가 된다.
nonisolated protocol ShardBackend: Sendable {
    func shards(accessToken: String) async throws -> ShardBalance
}

// MARK: - 로그

nonisolated enum ShardLog {
    static func event(_ message: String) {
        #if DEBUG
        print("[Shards] \(message)")
        #endif
    }
}
