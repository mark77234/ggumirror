//
//  ShardPurchaseController.swift
//  ggumirror
//
//  구매 · 복구 흐름. **StoreKit도 URLSession도 여기서 직접 부르지 않는다** —
//  둘 다 protocol 뒤에 있어 흐름 전체를 SDK 없이 시험한다.
//
//  가장 중요한 규칙 하나: **`finish()`는 서버가 지급을 확정한 뒤에만 부른다.**
//  Apple 결제 성공은 조각을 뜻하지 않는다. 그 사이에서 앱이 죽거나 네트워크가 끊기면
//  거래를 미완료로 남겨 두어야 다음 실행에서 되찾을 수 있다.
//

import Foundation
import Observation

/// `Transaction.updates` listener Task의 **수명을 들고 있는 상자.**
///
/// `@MainActor` 저장 property는 nonisolated `deinit`에서 만질 수 없다. 그렇다고
/// "취소하지 않는다"로 두면 controller가 사라져도 listener Task가 남는다
/// (production은 process 수명 singleton이라 티가 안 나지만, test는 controller를 계속 만든다).
///
/// 그래서 **취소 책임만** 이 nonisolated 타입으로 떼어낸다. controller가 이걸 `let`으로
/// 들고 있으므로 controller가 해제되면 이 상자도 해제되고, 그 `deinit`이 Task를 끊는다.
/// `nonisolated(unsafe)` 같은 우회를 쓰지 않고 lock 하나로 끝낸다.
private nonisolated final class ListenerHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    /// **이미 돌고 있으면 새로 만들지 않는다** — listener는 정확히 하나다.
    /// 만들었으면 `true`.
    @discardableResult
    func start(_ make: () -> Task<Void, Never>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard task == nil else { return false }
        task = make()
        return true
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        task?.cancel()
        task = nil
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return task != nil
    }

    deinit { task?.cancel() }
}

@MainActor
@Observable
final class ShardPurchaseController {

    /// 화면이 보는 상태.
    enum Phase: Equatable {
        case idle
        /// 상품 목록을 받아오는 중.
        case loadingProducts
        /// Apple 결제창이 떠 있다.
        case purchasing(productID: String)
        /// **결제는 끝났고 서버 확인 중이다.** 여기서 "실패"라고 말하지 않는다.
        case confirming
        /// 가족 승인 대기 등. 승인되면 `Transaction.updates`로 온다.
        case awaitingApproval
    }

    private(set) var phase: Phase = .idle
    private(set) var products: [ShardProductInfo] = []
    /// 사람이 읽을 마지막 안내. 실패를 단정하지 않는 문구만 담는다.
    private(set) var notice: String?

    private let store: any ShardStoreKit
    private let backend: any ShardPurchaseBackend
    /// `Transaction.updates` listener의 수명. `let` + `Sendable`이라
    /// nonisolated `deinit`에서도 안전하게 만질 수 있다.
    private let listener = ListenerHandle()

    var isBusy: Bool { phase != .idle }
    var isConfigured: Bool { !products.isEmpty }

    init(store: any ShardStoreKit, backend: any ShardPurchaseBackend) {
        self.store = store
        self.backend = backend
    }

    /// controller가 사라지면 listener도 끊는다.
    ///
    /// `listener`는 `let`이고 `Sendable`이라 nonisolated `deinit`에서 접근할 수 있다 —
    /// 이것 때문에 취소 책임을 별도 상자로 뺐다.
    deinit { listener.cancel() }

    /// listener가 돌고 있는지. test가 수명을 확인한다.
    var isListening: Bool { listener.isRunning }

    // MARK: - 상품

    func loadProducts() async {
        guard products.isEmpty else { return }
        phase = .loadingProducts
        defer { if phase == .loadingProducts { phase = .idle } }
        do {
            let loaded = try await store.products(for: ShardProducts.identifiers)
            // App Store가 주는 순서를 믿지 않는다. 조각 수로 정렬한다.
            products = loaded.sorted { ($0.shardAmount ?? 0) < ($1.shardAmount ?? 0) }
        } catch {
            // 상품을 못 받아도 앱을 막지 않는다. CTA만 나오지 않는다.
            products = []
        }
    }

    // MARK: - 구매

    /// 조각을 산다. **로그인하지 않았으면 시작하지 않는다.**
    ///
    /// 서버 경제라 결제의 주인을 서명에 실어야 하고, 그 값이 로그인한 사용자의 UUID다.
    /// 임의의 로컬 UUID를 만들지 않는다 — 그러면 서버가 주인을 확인할 수 없다.
    func purchase(_ productID: String, session: ServerSession?, wallet: ShardWallet) async {
        guard !isBusy else { return }   // 버튼 연타로 두 번 사지 않는다
        guard let session, session.isValid() else {
            notice = "조각을 충전하려면 로그인이 필요해요."
            return
        }
        guard let token = UUID(uuidString: session.userID) else {
            // 서버 user id가 UUID가 아니면 결제를 주인에게 묶을 수 없다.
            notice = "지금은 충전할 수 없어요."
            return
        }

        phase = .purchasing(productID: productID)
        notice = nil
        let outcome: PurchaseOutcome
        do {
            outcome = try await store.purchase(productID: productID, appAccountToken: token)
        } catch {
            phase = .idle
            notice = "결제를 시작하지 못했어요. 잠시 뒤 다시 시도해 주세요."
            return
        }

        switch outcome {
        case .purchased(let transaction):
            phase = .confirming
            await submit(transaction, session: session, wallet: wallet)
            phase = .idle

        case .pending:
            // 승인 대기. 아직 아무것도 지급되지 않았다.
            phase = .awaitingApproval
            notice = "승인을 기다리고 있어요. 승인되면 조각이 들어와요."

        case .cancelled:
            // **오류가 아니다.** 아무 말도 하지 않는다.
            phase = .idle

        case .unverified:
            // 서명을 믿을 수 없다. 서버에 보내지 않고 finish도 하지 않는다.
            phase = .idle
            notice = "결제를 확인하지 못했어요."

        case .unknown:
            // 모르는 결과를 성공으로 취급하지 않는다.
            phase = .idle
            notice = "결제 상태를 확인하고 있어요."
        }
    }

    // MARK: - 복구

    /// `Transaction.updates`를 듣기 시작한다. 앱 수명 동안 **한 번만**.
    func startListening(session: @escaping @MainActor () -> ServerSession?, wallet: ShardWallet) {
        // 상자가 "이미 돌고 있음"을 판단한다 — 두 번 불러도 listener는 하나다.
        listener.start {
            Task { [weak self] in
                guard let stream = self?.store.updates() else { return }
                for await delivered in stream {
                    guard let self, !Task.isCancelled else { return }
                    // 세션이 없으면 **아무 사용자에게도 귀속하지 않는다.** 거래는 미완료로 남고
                    // 로그인 뒤 `recoverUnfinished()`가 가져간다.
                    await self.handle(delivered, session: session(), wallet: wallet)
                }
            }
        }
    }

    /// listener를 끊는다. 끊은 뒤 오는 거래는 처리하지 않는다.
    func stopListening() { listener.cancel() }

    /// 로그인 직후 미완료 거래를 쓸어 담는다.
    ///
    /// 앱 재시작 · 서버 timeout · 응답 유실 · 결제가 로그인보다 먼저 온 경우가 여기로 온다.
    /// 서버 전역 멱등(B-6A) 덕분에 몇 번 다시 보내도 지급은 딱 한 번이다.
    func recoverUnfinished(session: ServerSession?, wallet: ShardWallet) async {
        guard let session, session.isValid() else { return }
        for delivered in await store.unfinished() {
            await handle(delivered, session: session, wallet: wallet)
        }
    }

    private func handle(
        _ delivered: DeliveredTransaction, session: ServerSession?, wallet: ShardWallet
    ) async {
        switch delivered {
        case .unverified:
            // 지급도 finish도 하지 않는다. 남겨 두면 다음에 다시 볼 수 있다.
            return
        case .verified(let transaction):
            guard let session, session.isValid() else { return }
            await submit(transaction, session: session, wallet: wallet)
        }
    }

    // MARK: - 서버 제출

    /// 서명된 거래를 서버에 넘기고, **확정된 뒤에만** 거래를 끝낸다.
    private func submit(
        _ transaction: PurchasedTransaction, session: ServerSession, wallet: ShardWallet
    ) async {
        // client 쪽 fail safe. 진짜 관문은 서버의 `appAccountToken` 검증이다 —
        // 여기서 통과했다고 서버가 믿지 않고, 여기서 걸러도 서버 검사를 없애지 않는다.
        if let token = transaction.appAccountToken,
           token != UUID(uuidString: session.userID) {
            // 다른 사용자의 결제다. **finish하지 않는다** — 원래 주인이 되찾아야 한다.
            return
        }

        do {
            let receipt = try await backend.creditIAPShards(
                signedTransaction: transaction.signedPayload,
                accessToken: session.accessToken
            )
            // 잔액은 **서버가 준 값**이다. `wallet.balance += amount`를 하지 않는다.
            wallet.apply(balance: receipt.balance)
            // 여기까지 왔다는 것은 서버가 지급을 확정했다는 뜻이다.
            // `credited == false`도 확정이다 — 이미 처리된 같은 거래이므로 끝내도 된다.
            await transaction.finish()
            notice = receipt.credited ? "조각이 들어왔어요." : nil
        } catch {
            // **finish하지 않는다.** network 실패 · timeout · 5xx · 인증 실패 · 잘못된 응답
            // 전부 같은 처리다 — 거래를 미완료로 남겨 다음 기회에 되찾는다.
            notice = "구매를 확인하고 있어요. 잠시 뒤 자동으로 반영돼요."
        }
    }
}
