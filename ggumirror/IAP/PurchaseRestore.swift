//
//  PurchaseRestore.swift
//  ggumirror
//
//  `구매 복원`. **조각을 다시 지급하는 기능이 아니다.**
//
//  꾸미러의 조각은 consumable이다. 이미 쓴 소모품은 "복원"되지 않고, 그래서도 안 된다 —
//  복원할 때마다 조각이 늘어나면 결제 없이 조각을 만드는 길이 된다.
//  잔액의 authority는 **서버 원장** 하나다.
//
//  그러면 이 버튼은 무엇을 하는가:
//
//      1. Apple StoreKit 상태를 다시 맞춘다 (`AppStore.sync`)
//      2. 아직 끝내지 못한 결제를 서버에 다시 낸다 — 서버 멱등이라 지급은 한 번뿐이다
//      3. 서버가 authority인 값들을 다시 읽는다 (지갑 · 보관 칸 · 소유권 · 프로필)
//
//  즉 **되찾는 것은 잃어버린 결제이지 이미 받은 조각이 아니다.**
//
//  산 상품을 기기로 자동으로 내려받지도 않는다 — `내 거울에 추가`는 그대로 사용자가 누른다.
//  복원은 소유권과 화면 상태를 맞추는 일이지 라이브러리를 통째로 바꾸는 일이 아니다.
//

import Foundation
import StoreKit

nonisolated enum PurchaseRestoreState: Equatable {
    case idle
    case restoring
    case finished
    case failed

    /// 사용자에게 보여 줄 말. **"N조각을 복원했어요"라고 말하지 않는다** —
    /// 그런 일은 일어나지 않고, 그렇게 말하면 사용자가 조각이 늘기를 기대한다.
    var message: String? {
        switch self {
        case .idle, .restoring: nil
        case .finished: "구매 정보를 확인했어요."
        case .failed: "구매 정보를 확인하지 못했어요. 잠시 뒤 다시 시도해 주세요."
        }
    }
}

/// StoreKit 동기화 한 줄. test에서 갈아 끼우기 위해 분리한다 —
/// 실제 Apple 계정 동기화를 test에서 부를 수는 없다.
nonisolated protocol AppStoreSyncing: Sendable {
    func sync() async throws
}

nonisolated struct LiveAppStoreSync: AppStoreSyncing {
    func sync() async throws { try await AppStore.sync() }
}

@MainActor
enum PurchaseRestore {
    /// - Returns: 화면이 보여 줄 결과. **경제 값을 여기서 만들지 않는다.**
    static func run(
        session: ServerSession?,
        wallet: ShardWallet?,
        purchases: ShardPurchaseController?,
        marketplace: MarketplaceStore?,
        capacity: MirrorCapacityStore?,
        profile: ProfileSession?,
        storeKit: any AppStoreSyncing = LiveAppStoreSync()
    ) async -> PurchaseRestoreState {
        guard let session else { return .failed }

        // 1. Apple 쪽 상태를 맞춘다. 실패해도 나머지는 계속한다 —
        //    서버 상태를 다시 읽는 것만으로도 사용자가 얻는 것이 있다.
        var syncFailed = false
        do {
            try await storeKit.sync()
        } catch {
            syncFailed = true
        }

        // 2. 못 끝낸 결제를 다시 낸다. **서버가 멱등이라 지급은 한 번뿐이다** —
        //    이미 처리된 transaction을 열 번 보내도 조각은 늘지 않는다.
        if let wallet {
            await purchases?.recoverUnfinished(session: session, wallet: wallet)
        }

        // 3. 서버가 authority인 값들을 다시 읽기만 한다. 여기서 계산하지 않는다.
        await wallet?.refresh(session: session)
        await marketplace?.refreshMine(session: session)
        await profile?.refresh(session: session)

        return syncFailed ? .failed : .finished
    }
}
