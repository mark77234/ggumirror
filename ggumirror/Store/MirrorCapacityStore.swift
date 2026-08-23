//
//  MirrorCapacityStore.swift
//  ggumirror
//
//  거울을 몇 개까지 담을 수 있는가. **서버가 authority다.**
//
//  조각으로 산 칸은 서버 사용자 문서에 있다 — 이 기기의 저장 파일이 아니다.
//  앱을 지우거나 기기를 바꿔도 산 칸은 그대로 남는다.
//
//  **몇 개를 쓰고 있는지는 서버가 모른다.** 그건 기기의 사실(`MirrorLibrary` 개수)이고,
//  서버는 "몇 칸까지"만 안다. 둘을 합쳐 `보관 중 N / M`을 보여 준다.
//
//  `ShardWallet`과 같은 규칙이다 — client가 `balance -= 10` · `slots += 5`를 하지 않고
//  서버가 준 값을 옮겨 적기만 한다.
//

import Foundation

// MARK: - 서버 모양

/// 지금 파는 확장 상품. **가격을 앱에 적지 않는다** — 서버가 알려준 값을 그대로 보여 준다.
nonisolated struct MirrorSlotPack: Decodable, Hashable, Sendable {
    let id: String
    let costShards: Int
    let slotDelta: Int
}

/// `GET /users/me/mirror-capacity`.
nonisolated struct MirrorCapacityInfo: Decodable, Hashable, Sendable {
    let baseSlots: Int
    let purchasedSlots: Int
    let effectiveSlots: Int
    let pack: MirrorSlotPack
}

/// `POST /users/me/mirror-capacity/purchases`.
nonisolated struct MirrorCapacityPurchase: Decodable, Hashable, Sendable {
    let operationId: String
    let packId: String
    let chargedShards: Int
    let slotDelta: Int
    /// **이 요청이 실제로 경제를 움직였는가.** `false`는 실패가 아니다 —
    /// 같은 의도가 이미 처리된 것이고, 나머지 값은 그때 결과 그대로다.
    let applied: Bool
    let balance: Int
    let baseSlots: Int
    let purchasedSlots: Int
    let effectiveSlots: Int
}

nonisolated protocol MirrorCapacityBackend: Sendable {
    func mirrorCapacity(accessToken: String) async throws -> MirrorCapacityInfo
    func purchaseMirrorSlots(
        packId: String, operationId: String, accessToken: String
    ) async throws -> MirrorCapacityPurchase
}

// MARK: - 상태

@MainActor
@Observable
final class MirrorCapacityStore {
    /// 앱이 쓰는 하나. `ShardWallet.live` · `CatalogStats.live`와 같은 규칙이다.
    static let live = MirrorCapacityStore()

    /// 서버가 마지막으로 알려준 값. **없으면 아직 모르는 것이다.**
    ///
    /// 화면은 이것을 **UX cache**로만 쓴다 — authority는 언제나 서버 응답이고,
    /// 못 읽었을 때는 무료 기본값으로 남는다(예전 로컬 값을 되살리지 않는다).
    private(set) var info: MirrorCapacityInfo?

    /// 요청이 진행 중인가. 연타를 막는다.
    private(set) var isPurchasing = false
    private(set) var isLoading = false

    /// 마지막 실패 안내.
    private(set) var failure: String?

    /// **아직 응답을 받지 못한 구매 의도.**
    ///
    /// 응답을 잃었을 수 있다 — 서버는 이미 처리했는데 우리만 모르는 상태다.
    /// 그때 새 id로 다시 보내면 조각이 두 번 빠진다. 그래서 **같은 id로** 재시도한다.
    private(set) var pendingOperationID: String?

    private let backend: any MirrorCapacityBackend

    init(backend: any MirrorCapacityBackend = BackendClient()) {
        self.backend = backend
    }

    /// 지금 담을 수 있는 칸. 서버를 못 읽었으면 무료 기본값이다.
    var effectiveSlots: Int { info?.effectiveSlots ?? MirrorStoragePolicy.freeMirrorSlots }

    /// 확장 상품. 서버를 못 읽었으면 없다 — **가격을 지어내지 않는다.**
    var pack: MirrorSlotPack? { info?.pack }

    /// 살 수 있는가. 잔액 판단은 화면이 지갑과 함께 한다(최종 authority는 서버다).
    var canPurchase: Bool { pack != nil && !isPurchasing }

    // MARK: - 읽기

    /// 서버 값을 받아 라이브러리에 옮겨 적는다.
    ///
    /// **화면을 다시 그릴 때마다 부르지 않는다** — 세션 복구 · 내 거울 진입 ·
    /// 구매 성공 뒤에만 부른다.
    @discardableResult
    func refresh(session: ServerSession?, library: MirrorLibrary?) async -> Bool {
        guard let token = session?.accessToken else {
            // 로그인 전에는 서버 칸이 없다. 무료 기본값 그대로 둔다.
            return false
        }
        guard !isLoading else { return false }
        isLoading = true
        defer { isLoading = false }

        guard let found = try? await backend.mirrorCapacity(accessToken: token) else {
            // 못 읽었다고 예전 값을 지우지 않는다. 마지막으로 본 값을 그대로 둔다.
            return false
        }
        apply(found, to: library)
        return true
    }

    // MARK: - 구매

    nonisolated enum PurchaseOutcome: Equatable, Sendable {
        /// 이번 요청이 실제로 늘렸다.
        case purchased(MirrorCapacityPurchase)
        /// 같은 의도가 이미 처리돼 있었다. 실패가 아니다.
        case alreadyApplied(MirrorCapacityPurchase)
        case needsSignIn
        case insufficientShards
        case failed(String)
    }

    /// 확장 한 건.
    ///
    /// **client가 가격도 칸 수도 계산하지 않는다.** 보내는 것은 `packId`와
    /// 이 의도를 가리키는 `operationId`뿐이고, 결과는 서버가 준 값을 그대로 쓴다.
    ///
    /// 진행 중이면 아무 일도 하지 않는다 — 연타로 의도가 여러 개 생기면 안 된다.
    func purchase(
        session: ServerSession?, wallet: ShardWallet?, library: MirrorLibrary?
    ) async -> PurchaseOutcome {
        guard !isPurchasing else { return .failed("이미 처리 중이에요.") }
        guard let pack else { return .failed("보관 공간 상품을 불러오지 못했어요.") }
        guard let token = session?.accessToken else { return .needsSignIn }

        // **응답을 잃은 의도가 있으면 그 id로 다시 보낸다.** 새로 만들면 두 번 빠진다.
        let operationID = pendingOperationID ?? UUID().uuidString
        pendingOperationID = operationID
        isPurchasing = true
        defer { isPurchasing = false }
        failure = nil

        do {
            let result = try await backend.purchaseMirrorSlots(
                packId: pack.id, operationId: operationID, accessToken: token
            )
            // 여기까지 왔으면 서버 상태를 확실히 안다. 다음 구매는 새 의도다.
            pendingOperationID = nil
            apply(result, to: library, wallet: wallet)
            return result.applied ? .purchased(result) : .alreadyApplied(result)
        } catch BackendError.unexpected(status: 409) {
            // 서버가 거절했다 — 아무것도 바뀌지 않았다. 이 의도는 끝난 것으로 본다.
            pendingOperationID = nil
            failure = "조각이 부족해요."
            return .insufficientShards
        } catch {
            // **id를 지우지 않는다.** 서버가 이미 처리했는데 응답만 잃었을 수 있다.
            let message = "지금은 보관 공간을 늘리지 못했어요. 잠시 뒤 다시 시도해 주세요."
            failure = message
            return .failed(message)
        }
    }

    /// 로그아웃. 다음 사용자에게 물려주지 않는다.
    func clear(library: MirrorLibrary?) {
        info = nil
        pendingOperationID = nil
        failure = nil
        library?.applyServerCapacity(MirrorStoragePolicy.freeMirrorSlots)
    }

    // MARK: - 옮겨 적기

    private func apply(_ found: MirrorCapacityInfo, to library: MirrorLibrary?) {
        info = found
        library?.applyServerCapacity(found.effectiveSlots)
    }

    /// 구매 결과를 그대로 옮겨 적는다. **여기서 더하지 않는다.**
    private func apply(
        _ result: MirrorCapacityPurchase, to library: MirrorLibrary?, wallet: ShardWallet?
    ) {
        info = MirrorCapacityInfo(
            baseSlots: result.baseSlots,
            purchasedSlots: result.purchasedSlots,
            effectiveSlots: result.effectiveSlots,
            // 상품 정보는 바뀌지 않는다. 마지막으로 받은 것을 유지한다.
            pack: info?.pack ?? MirrorSlotPack(
                id: result.packId, costShards: result.chargedShards, slotDelta: result.slotDelta
            )
        )
        library?.applyServerCapacity(result.effectiveSlots)
        wallet?.apply(balance: result.balance)
    }
}
