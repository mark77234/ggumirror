//
//  StoreKitShardStore.swift
//  ggumirror
//
//  **StoreKit 2에 닿는 파일은 이것 하나다.** 나머지(`ShardPurchase` · Controller · 화면)는
//  protocol만 알고 StoreKit 타입을 모른다 — 그래서 구매 흐름 전체를 SDK 없이 시험한다.
//  B-5에서 광고 SDK를 `GoogleAds.swift` 하나에 가둔 것과 같은 방식이다.
//
//  RevenueCat 같은 third-party 구매 SDK를 쓰지 않는다. StoreKit 2만 쓴다.
//

import Foundation
import StoreKit

nonisolated struct StoreKitShardStore: ShardStoreKit {

    func products(for identifiers: [String]) async throws -> [ShardProductInfo] {
        try await Product.products(for: identifiers).map { product in
            ShardProductInfo(
                id: product.id,
                displayName: product.displayName,
                // **가격 문자열은 StoreKit이 만든다.** 앱이 통화를 조립하지 않는다.
                displayPrice: product.displayPrice
            )
        }
    }

    func purchase(productID: String, appAccountToken: UUID) async throws -> PurchaseOutcome {
        guard let product = try await Product.products(for: [productID]).first else {
            return .unknown
        }
        // 결제의 주인을 **서명 안에** 실어 보낸다. 서버가 이 값으로 지갑을 정한다.
        let result = try await product.purchase(options: [.appAccountToken(appAccountToken)])

        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                return .purchased(Self.mapped(transaction, jws: verification.jwsRepresentation))
            case .unverified:
                // 서명을 믿을 수 없다. finish하지 않고 그대로 남긴다.
                return .unverified
            }
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            // 앞으로 생길 결과를 성공으로 취급하지 않는다.
            return .unknown
        }
    }

    func unfinished() async -> [DeliveredTransaction] {
        // **`currentEntitlements`를 쓰지 않는다** — 소모품은 거기 남지 않는다.
        var delivered: [DeliveredTransaction] = []
        for await verification in Transaction.unfinished {
            delivered.append(Self.delivered(verification))
        }
        return delivered
    }

    func updates() -> AsyncStream<DeliveredTransaction> {
        AsyncStream { continuation in
            let task = Task {
                for await verification in Transaction.updates {
                    continuation.yield(Self.delivered(verification))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 변환

    private static func delivered(
        _ verification: VerificationResult<Transaction>
    ) -> DeliveredTransaction {
        switch verification {
        case .verified(let transaction):
            // 서버에 보낼 JWS는 **`VerificationResult`가 들고 있다** — transaction 자체가 아니다.
            .verified(mapped(transaction, jws: verification.jwsRepresentation))
        case .unverified:
            .unverified
        }
    }

    private static func mapped(_ transaction: Transaction, jws: String) -> PurchasedTransaction {
        PurchasedTransaction(
            id: transaction.id,
            productID: transaction.productID,
            appAccountToken: transaction.appAccountToken,
            // 서버에 보내는 유일한 증거. 로그에 남기지 않는다.
            signedPayload: jws,
            // **서버가 지급을 확정한 뒤에만** 불린다 (Controller가 지킨다).
            finish: { await transaction.finish() }
        )
    }
}
