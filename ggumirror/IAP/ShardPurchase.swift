//
//  ShardPurchase.swift
//  ggumirror
//
//  조각 IAP — **client는 지급하지 않는다.**
//
//  Apple 결제가 성공한 것과 조각이 늘어난 것은 **다른 단계**다. 조각은 서버가
//  Apple 서명을 검증한 뒤에만 늘어나고, 앱은 서버가 준 잔액을 옮겨 적기만 한다.
//  B-4 출석 · B-5 광고와 같은 규칙이다.
//
//  이 파일에는 **StoreKit이 들어오지 않는다.** 그래서 구매/복구 흐름 전체를
//  StoreKit 없이 시험할 수 있다 (B-5의 `GoogleAds.swift` 격리와 같은 방식).
//  실제 StoreKit 2 호출은 `StoreKitShardStore.swift` 하나뿐이다.
//

import Foundation

// MARK: - 상품

/// 판매하는 조각 묶음. **여기 숫자는 표시/정렬용이다.**
///
/// 실제 지급 수량의 authority는 **서버 catalog**다(backend `SHARD_PRODUCTS`).
/// 앱이 아는 값과 서버가 주는 값이 달라도 잔액은 서버 응답을 따른다.
nonisolated enum ShardProducts {
    /// App Store Connect에 만든 실제 identifier. 재사용할 수 없는 값이라 함부로 고치지 않는다.
    static let identifiers = [
        "com.mark77234.ggumirror.shards.10",
        "com.mark77234.ggumirror.shards.50",
        "com.mark77234.ggumirror.shards.100",
    ]

    /// 표시용 수량. 지급 수량이 아니다.
    static let displayAmounts: [String: Int] = [
        "com.mark77234.ggumirror.shards.10": 10,
        "com.mark77234.ggumirror.shards.50": 50,
        "com.mark77234.ggumirror.shards.100": 100,
    ]

    static func displayAmount(for identifier: String) -> Int? {
        displayAmounts[identifier]
    }
}

/// 화면에 뿌릴 상품 하나.
///
/// **가격은 문자열 그대로 StoreKit에서 받는다.** `₩1,100`을 코드에 적으면
/// 통화 · 지역 · 세금이 다른 곳에서 거짓말이 된다.
nonisolated struct ShardProductInfo: Sendable, Identifiable, Equatable {
    let id: String
    let displayName: String
    /// `Product.displayPrice`. 앱이 만들지 않는다.
    let displayPrice: String

    var shardAmount: Int? { ShardProducts.displayAmount(for: id) }
}

// MARK: - 거래

/// 서명 검증을 통과한 StoreKit transaction 하나. **StoreKit 타입을 밖으로 흘리지 않는다.**
nonisolated struct PurchasedTransaction: Sendable {
    let id: UInt64
    let productID: String
    /// 구매 때 실어 보낸 값. 서버가 이것으로 결제의 주인을 판단한다.
    let appAccountToken: UUID?
    /// `Transaction.jwsRepresentation`. **서버에 보내는 유일한 증거다.**
    ///
    /// 로그 · analytics · 로컬 저장에 넣지 않는다. 요청 본문에만 실린다.
    let signedPayload: String
    /// 실제 StoreKit transaction을 끝내는 손잡이.
    ///
    /// **서버가 지급을 확정한 뒤에만 부른다.** 먼저 부르면 응답을 잃었을 때
    /// StoreKit이 다시 주지 않아 사용자가 돈만 내고 조각을 잃는다.
    let finish: @Sendable () async -> Void
}

/// StoreKit이 전달하는 거래. 검증되지 않은 것도 온다.
nonisolated enum DeliveredTransaction: Sendable {
    case verified(PurchasedTransaction)
    /// 서명을 신뢰할 수 없다. **지급하지 않고 finish도 하지 않는다.**
    case unverified
}

/// `purchase()` 결과.
nonisolated enum PurchaseOutcome: Sendable {
    case purchased(PurchasedTransaction)
    /// 결제는 됐다는데 서명을 믿을 수 없다.
    case unverified
    /// 가족 승인 대기 등. 나중에 `Transaction.updates`로 온다.
    case pending
    /// 사용자가 닫았다. **오류가 아니다.**
    case cancelled
    /// 앞으로 생길 결과. 모르는 것은 성공으로 취급하지 않는다.
    case unknown
}

// MARK: - StoreKit 경계

/// StoreKit 2에 닿는 통로. 구현은 `StoreKitShardStore` 하나뿐이고 test는 가짜를 넣는다.
nonisolated protocol ShardStoreKit: Sendable {
    func products(for identifiers: [String]) async throws -> [ShardProductInfo]

    /// **`appAccountToken`은 필수 인자다.** 없이 구매할 수 있는 통로를 만들지 않는다 —
    /// 그러면 서버가 결제의 주인을 알 수 없다.
    func purchase(productID: String, appAccountToken: UUID) async throws -> PurchaseOutcome

    /// 아직 끝나지 않은 거래. 앱 재시작 · 응답 유실 복구가 쓴다.
    ///
    /// **`Transaction.currentEntitlements`를 쓰지 않는다** — 소모품은 거기 남지 않는다.
    func unfinished() async -> [DeliveredTransaction]

    /// StoreKit이 밀어주는 거래 흐름.
    func updates() -> AsyncStream<DeliveredTransaction>
}

// MARK: - 서버 통로

/// 조각 IAP 지급 결과. `credited`는 **이번 요청이 지급했는가**다.
nonisolated struct ShardPurchaseReceipt: Sendable, Decodable, Equatable {
    let credited: Bool
    let amount: Int
    /// **잔액의 authority.** 앱이 계산한 값이 아니다.
    let balance: Int
}

/// 조각 IAP를 서버에 제출하는 통로. 읽기 전용 `ShardBackend`와 나눠 둔다.
nonisolated protocol ShardPurchaseBackend: Sendable {
    func creditIAPShards(
        signedTransaction: String, accessToken: String
    ) async throws -> ShardPurchaseReceipt
}
