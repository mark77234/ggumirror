//
//  ShardPurchaseTests.swift
//  ggumirrorTests
//
//  조각 IAP (B-6C). **StoreKit 없이 구매/복구 흐름 전체를 시험한다** —
//  `ShardStoreKit` / `ShardPurchaseBackend`가 protocol이라 가짜를 넣을 수 있다.
//
//  가장 중요한 계약: **`finish()`는 서버가 지급을 확정한 뒤에만** 불린다.
//  그게 깨지면 사용자가 돈만 내고 조각을 잃는다.
//

import Foundation
import Testing
@testable import ggumirror

@MainActor
struct ShardPurchaseTests {

    static let userID = "063cd7cb-fd94-4055-b6d8-2e4866879ed9"
    static let otherUserID = "11111111-2222-4333-8444-555555555555"
    static let product10 = "com.mark77234.ggumirror.shards.10"

    // MARK: - 가짜

    /// finish가 불렸는지 세는 상자. transaction이 struct라 참조로 센다.
    final class FinishCounter: @unchecked Sendable {
        private(set) var count = 0
        func record() { count += 1 }
    }

    static func transaction(
        id: UInt64 = 1,
        productID: String = product10,
        token: UUID? = UUID(uuidString: userID),
        counter: FinishCounter
    ) -> PurchasedTransaction {
        PurchasedTransaction(
            id: id,
            productID: productID,
            appAccountToken: token,
            signedPayload: "signed-jws-\(id)",
            finish: { counter.record() }
        )
    }

    final class FakeStore: ShardStoreKit, @unchecked Sendable {
        var outcome: PurchaseOutcome = .cancelled
        var unfinishedTransactions: [DeliveredTransaction] = []
        var catalog: [ShardProductInfo] = []
        var purchaseError: Error?
        private(set) var purchaseCalls: [(String, UUID)] = []
        private let stream: AsyncStream<DeliveredTransaction>
        let continuation: AsyncStream<DeliveredTransaction>.Continuation

        init() {
            var made: AsyncStream<DeliveredTransaction>.Continuation!
            stream = AsyncStream { made = $0 }
            continuation = made
        }

        func products(for identifiers: [String]) async throws -> [ShardProductInfo] { catalog }

        func purchase(productID: String, appAccountToken: UUID) async throws -> PurchaseOutcome {
            purchaseCalls.append((productID, appAccountToken))
            if let purchaseError { throw purchaseError }
            return outcome
        }

        func unfinished() async -> [DeliveredTransaction] { unfinishedTransactions }

        private(set) var updatesCalls = 0
        func updates() -> AsyncStream<DeliveredTransaction> {
            updatesCalls += 1
            return stream
        }
    }

    enum FakeFailure: Error { case timeout, server, malformed }

    final class FakeBackend: ShardPurchaseBackend, @unchecked Sendable {
        var receipt = ShardPurchaseReceipt(credited: true, amount: 10, balance: 110)
        var failure: Error?
        private(set) var submitted: [String] = []

        func creditIAPShards(
            signedTransaction: String, accessToken: String
        ) async throws -> ShardPurchaseReceipt {
            submitted.append(signedTransaction)
            if let failure { throw failure }
            return receipt
        }
    }

    static func session(userID: String = userID) -> ServerSession {
        ServerSession(
            accessToken: "token", expiresAt: Date().addingTimeInterval(3600), userID: userID
        )
    }

    static func world() -> (ShardPurchaseController, FakeStore, FakeBackend, ShardWallet) {
        let store = FakeStore()
        let backend = FakeBackend()
        return (ShardPurchaseController(store: store, backend: backend), store, backend, ShardWallet())
    }

    // MARK: - 상품

    @Test("상품은 10 / 50 / 100 셋뿐이다")
    func productIdentifiers() {
        #expect(ShardProducts.identifiers.count == 3)
        #expect(ShardProducts.identifiers == [
            "com.mark77234.ggumirror.shards.10",
            "com.mark77234.ggumirror.shards.50",
            "com.mark77234.ggumirror.shards.100",
        ])
        #expect(ShardProducts.displayAmount(for: Self.product10) == 10)
        #expect(ShardProducts.displayAmount(for: "com.mark77234.ggumirror.shards.50") == 50)
        #expect(ShardProducts.displayAmount(for: "com.mark77234.ggumirror.shards.100") == 100)
        #expect(ShardProducts.displayAmount(for: "com.example.unknown") == nil)
    }

    @Test("상품은 조각 수 순서로 정렬된다")
    func productsAreSorted() async {
        let (controller, store, _, _) = Self.world()
        store.catalog = [
            ShardProductInfo(id: "com.mark77234.ggumirror.shards.100", displayName: "100", displayPrice: "₩16,000"),
            ShardProductInfo(id: Self.product10, displayName: "10", displayPrice: "₩1,900"),
        ]
        await controller.loadProducts()
        #expect(controller.products.map(\.shardAmount) == [10, 100])
    }

    @Test("가격은 StoreKit이 준 문자열을 그대로 쓴다")
    func priceComesFromStoreKit() async {
        let (controller, store, _, _) = Self.world()
        store.catalog = [
            ShardProductInfo(id: Self.product10, displayName: "조각 10개", displayPrice: "₩1,900")
        ]
        await controller.loadProducts()
        #expect(controller.products.first?.displayPrice == "₩1,900")
    }

    // MARK: - appAccountToken

    @Test("구매에 로그인한 사용자 UUID를 실어 보낸다")
    func purchaseCarriesAppAccountToken() async {
        let (controller, store, _, wallet) = Self.world()
        let counter = FinishCounter()
        store.outcome = .purchased(Self.transaction(counter: counter))

        await controller.purchase(Self.product10, session: Self.session(), wallet: wallet)

        #expect(store.purchaseCalls.count == 1)
        #expect(store.purchaseCalls.first?.1 == UUID(uuidString: Self.userID))
    }

    @Test("로그인하지 않으면 구매를 시작하지 않는다")
    func purchaseRequiresSignIn() async {
        let (controller, store, backend, wallet) = Self.world()

        await controller.purchase(Self.product10, session: nil, wallet: wallet)

        #expect(store.purchaseCalls.isEmpty)
        #expect(backend.submitted.isEmpty)
        #expect(wallet.balance == 0)
    }

    @Test("만료된 세션으로는 구매를 시작하지 않는다")
    func expiredSessionCannotPurchase() async {
        let (controller, store, _, wallet) = Self.world()
        let expired = ServerSession(
            accessToken: "t", expiresAt: Date().addingTimeInterval(-60), userID: Self.userID
        )
        await controller.purchase(Self.product10, session: expired, wallet: wallet)
        #expect(store.purchaseCalls.isEmpty)
    }

    // MARK: - 성공 경로

    @Test("검증된 구매는 서버에 제출되고, 잔액은 서버 값을 쓴다")
    func verifiedPurchaseSubmitsAndUsesServerBalance() async {
        let (controller, store, backend, wallet) = Self.world()
        let counter = FinishCounter()
        store.outcome = .purchased(Self.transaction(counter: counter))
        backend.receipt = ShardPurchaseReceipt(credited: true, amount: 10, balance: 107)

        await controller.purchase(Self.product10, session: Self.session(), wallet: wallet)

        #expect(backend.submitted == ["signed-jws-1"])
        // 서버가 준 값 그대로. `0 + 10`이 아니다.
        #expect(wallet.balance == 107)
        #expect(counter.count == 1)
        #expect(controller.phase == .idle)
    }

    @Test("서버 확정 뒤에만 finish한다")
    func finishOnlyAfterServerConfirms() async {
        let (controller, store, backend, wallet) = Self.world()
        let counter = FinishCounter()
        store.outcome = .purchased(Self.transaction(counter: counter))

        await controller.purchase(Self.product10, session: Self.session(), wallet: wallet)

        #expect(backend.submitted.count == 1)
        #expect(counter.count == 1)
    }

    @Test("중복(credited=false)도 잔액을 적용하고 finish한다")
    func duplicateStillFinishes() async {
        let (controller, store, backend, wallet) = Self.world()
        let counter = FinishCounter()
        store.outcome = .purchased(Self.transaction(counter: counter))
        // 이미 처리된 거래 — 실패가 아니다.
        backend.receipt = ShardPurchaseReceipt(credited: false, amount: 10, balance: 96)

        await controller.purchase(Self.product10, session: Self.session(), wallet: wallet)

        #expect(wallet.balance == 96)
        #expect(counter.count == 1, "중복도 서버가 확정한 것이므로 끝내야 한다")
    }

    // MARK: - finish 금지 경로

    @Test("서버 실패에서는 finish하지 않는다", arguments: [FakeFailure.timeout, .server, .malformed])
    func serverFailureNeverFinishes(failure: FakeFailure) async {
        let (controller, store, backend, wallet) = Self.world()
        let counter = FinishCounter()
        store.outcome = .purchased(Self.transaction(counter: counter))
        backend.failure = failure

        await controller.purchase(Self.product10, session: Self.session(), wallet: wallet)

        #expect(counter.count == 0, "결제는 됐는데 서버 확정 전에 끝내면 조각을 잃는다")
        #expect(wallet.balance == 0)
        // 실패라고 단정하지 않는다.
        #expect(controller.notice?.contains("확인하고 있어요") == true)
    }

    @Test("unverified는 서버에 보내지도, finish하지도 않는다")
    func unverifiedIsNeverSubmitted() async {
        let (controller, store, backend, wallet) = Self.world()
        store.outcome = .unverified

        await controller.purchase(Self.product10, session: Self.session(), wallet: wallet)

        #expect(backend.submitted.isEmpty)
        #expect(wallet.balance == 0)
    }

    @Test("취소는 오류가 아니고 아무것도 바꾸지 않는다")
    func cancellationChangesNothing() async {
        let (controller, store, backend, wallet) = Self.world()
        store.outcome = .cancelled

        await controller.purchase(Self.product10, session: Self.session(), wallet: wallet)

        #expect(backend.submitted.isEmpty)
        #expect(wallet.balance == 0)
        #expect(controller.notice == nil, "취소를 실패로 알리지 않는다")
        #expect(controller.phase == .idle)
    }

    @Test("pending은 승인 대기 상태이고 지급하지 않는다")
    func pendingDoesNotCredit() async {
        let (controller, store, backend, wallet) = Self.world()
        store.outcome = .pending

        await controller.purchase(Self.product10, session: Self.session(), wallet: wallet)

        #expect(backend.submitted.isEmpty)
        #expect(wallet.balance == 0)
        #expect(controller.phase == .awaitingApproval)
    }

    @Test("모르는 결과를 성공으로 취급하지 않는다")
    func unknownOutcomeIsNotSuccess() async {
        let (controller, store, backend, wallet) = Self.world()
        store.outcome = .unknown

        await controller.purchase(Self.product10, session: Self.session(), wallet: wallet)

        #expect(backend.submitted.isEmpty)
        #expect(wallet.balance == 0)
    }

    // MARK: - 복구

    @Test("미완료 거래를 로그인 뒤에 다시 제출한다")
    func unfinishedRecovery() async {
        let (controller, store, backend, wallet) = Self.world()
        let counter = FinishCounter()
        store.unfinishedTransactions = [.verified(Self.transaction(id: 7, counter: counter))]
        backend.receipt = ShardPurchaseReceipt(credited: true, amount: 50, balance: 150)

        await controller.recoverUnfinished(session: Self.session(), wallet: wallet)

        #expect(backend.submitted == ["signed-jws-7"])
        #expect(wallet.balance == 150)
        #expect(counter.count == 1)
    }

    @Test("세션이 없으면 복구를 시도하지 않는다")
    func recoveryNeedsSession() async {
        let (controller, store, backend, wallet) = Self.world()
        let counter = FinishCounter()
        store.unfinishedTransactions = [.verified(Self.transaction(counter: counter))]

        await controller.recoverUnfinished(session: nil, wallet: wallet)

        #expect(backend.submitted.isEmpty)
        #expect(counter.count == 0, "주인을 모르는 거래를 끝내지 않는다")
    }

    @Test("미완료 unverified는 건드리지 않는다")
    func unverifiedUnfinishedIsLeftAlone() async {
        let (controller, store, backend, wallet) = Self.world()
        store.unfinishedTransactions = [.unverified]

        await controller.recoverUnfinished(session: Self.session(), wallet: wallet)

        #expect(backend.submitted.isEmpty)
        #expect(wallet.balance == 0)
    }

    @Test("복구 재제출이 겹쳐도 서버 멱등에 맡긴다 — 잔액은 서버 값")
    func repeatedRecoveryIsIdempotentByServer() async {
        let (controller, store, backend, wallet) = Self.world()
        let counter = FinishCounter()
        store.unfinishedTransactions = [.verified(Self.transaction(id: 9, counter: counter))]

        await controller.recoverUnfinished(session: Self.session(), wallet: wallet)
        // 두 번째는 서버가 중복으로 판정한다.
        backend.receipt = ShardPurchaseReceipt(credited: false, amount: 10, balance: 110)
        await controller.recoverUnfinished(session: Self.session(), wallet: wallet)

        #expect(backend.submitted.count == 2, "client는 다시 보낼 수 있다")
        #expect(wallet.balance == 110, "잔액은 늘 서버 값이다")
    }

    // MARK: - 사용자 전환 안전

    @Test("다른 사용자의 거래는 제출하지도 finish하지도 않는다")
    func accountTokenMismatchIsSafe() async {
        let (controller, store, backend, wallet) = Self.world()
        let counter = FinishCounter()
        store.unfinishedTransactions = [
            .verified(Self.transaction(token: UUID(uuidString: Self.otherUserID), counter: counter))
        ]

        await controller.recoverUnfinished(session: Self.session(), wallet: wallet)

        #expect(backend.submitted.isEmpty)
        #expect(counter.count == 0, "원래 주인이 되찾아야 한다")
        #expect(wallet.balance == 0)
    }

    // MARK: - 동시성

    @Test("구매 중에는 두 번째 구매를 시작하지 않는다")
    func concurrentPurchaseIsBlocked() async {
        let (controller, store, _, wallet) = Self.world()
        let counter = FinishCounter()
        store.outcome = .pending   // phase를 .awaitingApproval에 묶어 둔다

        await controller.purchase(Self.product10, session: Self.session(), wallet: wallet)
        store.outcome = .purchased(Self.transaction(counter: counter))
        await controller.purchase(Self.product10, session: Self.session(), wallet: wallet)

        #expect(store.purchaseCalls.count == 1, "진행 중에는 다시 사지 않는다")
    }

    // MARK: - listener 수명

    @Test("startListening을 두 번 불러도 listener는 하나다")
    func listenerIsCreatedOnce() async {
        let (controller, store, _, wallet) = Self.world()

        controller.startListening(session: { Self.session() }, wallet: wallet)
        controller.startListening(session: { Self.session() }, wallet: wallet)
        controller.startListening(session: { Self.session() }, wallet: wallet)

        #expect(controller.isListening)
        // stream을 한 번만 집어 갔다 = Task가 하나만 만들어졌다.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.updatesCalls == 1)
    }

    @Test("취소 경로가 있고, 끊으면 listening이 멈춘다")
    func listenerCanBeCancelled() {
        let (controller, _, _, wallet) = Self.world()

        controller.startListening(session: { Self.session() }, wallet: wallet)
        #expect(controller.isListening)

        controller.stopListening()
        #expect(!controller.isListening)
    }

    @Test("끊은 뒤 도착한 거래는 처리하지 않는다")
    func cancelledListenerIgnoresNewTransactions() async {
        let (controller, store, backend, wallet) = Self.world()
        let counter = FinishCounter()
        controller.startListening(session: { Self.session() }, wallet: wallet)
        try? await Task.sleep(for: .milliseconds(50))

        controller.stopListening()
        store.continuation.yield(.verified(Self.transaction(counter: counter)))
        try? await Task.sleep(for: .milliseconds(100))

        #expect(backend.submitted.isEmpty, "끊긴 listener가 거래를 처리했다")
        #expect(counter.count == 0)
    }

    @Test("listening 중 도착한 거래는 서버로 간다")
    func listenerDeliversTransactions() async {
        let (controller, store, backend, wallet) = Self.world()
        let counter = FinishCounter()
        backend.receipt = ShardPurchaseReceipt(credited: true, amount: 10, balance: 60)

        controller.startListening(session: { Self.session() }, wallet: wallet)
        try? await Task.sleep(for: .milliseconds(50))
        store.continuation.yield(.verified(Self.transaction(counter: counter)))
        try? await Task.sleep(for: .milliseconds(150))

        #expect(backend.submitted == ["signed-jws-1"])
        #expect(wallet.balance == 60)
        #expect(counter.count == 1)
    }

    @Test("listener 취소는 위험한 우회 없이 구현한다")
    func listenerLifecycleHasNoUnsafeEscapeHatch() throws {
        let code = Self.codeOnly(try Self.repoFile("ggumirror/IAP/ShardPurchaseController.swift"))
        #expect(!code.contains("nonisolated(unsafe)"), "위험한 escape hatch를 썼다")
        // 취소 경로가 실제로 존재한다.
        #expect(code.contains("deinit"))
        #expect(code.contains("task?.cancel()"))
    }

    // MARK: - 구조 고정

    @Test("StoreKit에 닿는 파일은 하나뿐이다")
    func storeKitIsIsolatedToOneFile() throws {
        // SDK를 한 파일에 가두면 구매 흐름 전체를 StoreKit 없이 시험할 수 있다 (B-5와 같은 규칙).
        for path in [
            "ggumirror/IAP/ShardPurchase.swift",
            "ggumirror/IAP/ShardPurchaseController.swift",
        ] {
            let source = try Self.repoFile(path)
            #expect(!source.contains("import StoreKit"), "\(path)가 StoreKit을 직접 안다")
        }
        #expect(try Self.repoFile("ggumirror/IAP/StoreKitShardStore.swift").contains("import StoreKit"))
    }

    @Test("client가 잔액을 계산하지 않는다")
    func clientNeverComputesBalance() throws {
        let raw = try Self.repoFile("ggumirror/IAP/ShardPurchaseController.swift")
        let code = Self.codeOnly(raw)
        for banned in ["balance +=", "balance -=", "balance = balance", "setBalance"] {
            #expect(!code.contains(banned), "잔액을 client가 계산한다: \(banned)")
        }
        #expect(code.contains("wallet.apply(balance:"))
    }

    @Test("RevenueCat 같은 third-party 구매 SDK를 쓰지 않는다")
    func noThirdPartyPurchaseSDK() throws {
        for path in [
            "ggumirror/IAP/ShardPurchase.swift",
            "ggumirror/IAP/ShardPurchaseController.swift",
            "ggumirror/IAP/StoreKitShardStore.swift",
        ] {
            let code = Self.codeOnly(try Self.repoFile(path))
            for banned in ["RevenueCat", "Purchases.", "Adapty", "Qonversion"] {
                #expect(!code.contains(banned), "\(path): \(banned)")
            }
        }
    }

    @Test("consumable 복구에 currentEntitlements를 쓰지 않는다")
    func consumablesDoNotUseCurrentEntitlements() throws {
        // 소모품은 `currentEntitlements`에 남지 않는다 — 거기서 찾으면 복구가 조용히 실패한다.
        let code = Self.codeOnly(try Self.repoFile("ggumirror/IAP/StoreKitShardStore.swift"))
        #expect(!code.contains("currentEntitlements"))
        #expect(code.contains("Transaction.unfinished"))
        #expect(code.contains("Transaction.updates"))
    }

    @Test("가격을 코드에 적지 않는다")
    func noHardcodedPrices() throws {
        for path in [
            "ggumirror/IAP/ShardPurchase.swift",
            "ggumirror/IAP/ShardPurchaseController.swift",
            "ggumirror/IAP/StoreKitShardStore.swift",
        ] {
            let code = Self.codeOnly(try Self.repoFile(path))
            #expect(!code.contains("₩"), "\(path)에 통화 문자열이 있다")
            #expect(!code.contains("KRW"), "\(path)에 통화 코드가 있다")
        }
        #expect(try Self.repoFile("ggumirror/IAP/StoreKitShardStore.swift").contains("product.displayPrice"))
    }

    @Test("JWS를 로그 · 저장소에 남기지 않는다")
    func signedPayloadNeverLeaks() throws {
        for path in [
            "ggumirror/IAP/ShardPurchase.swift",
            "ggumirror/IAP/ShardPurchaseController.swift",
            "ggumirror/IAP/StoreKitShardStore.swift",
        ] {
            let code = Self.codeOnly(try Self.repoFile(path))
            for banned in ["print(", "UserDefaults", "Logger("] {
                #expect(!code.contains(banned), "\(path): \(banned)")
            }
        }
    }

    @Test("StoreKit Configuration은 세 상품을 locked ID로 갖는다")
    func storeKitConfigurationMatchesProductIDs() throws {
        let source = try Self.repoFile("ggumirror/Ggumirror.storekit")
        for identifier in ShardProducts.identifiers {
            #expect(source.contains(identifier), "\(identifier)가 .storekit에 없다")
        }
        // 셋 다 소모품이어야 한다.
        #expect(source.components(separatedBy: "\"Consumable\"").count - 1 == 3)
    }

    // MARK: - 도구

    /// 주석을 걷어낸 코드만. 설명문에 나온 단어를 위반으로 세지 않는다
    /// (기존 `ShardWalletTests` · `OwnContentExportTests`와 같은 구현).
    static func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    static func repoFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }
}
