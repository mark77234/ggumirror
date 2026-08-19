//
//  MarketplaceStore.swift
//  ggumirror
//
//  상점 서버 상태 하나. `ShardWallet`과 같은 규칙이다 —
//  `@Observable` + protocol backend + `session`을 받아서 token을 안에서만 꺼낸다.
//
//  서버가 authority다:
//    - 등록비 차감 · 구매 이동 · 소유권 · downloadCount · likeCount는 **서버 결과로만** 반영한다
//    - 성공 응답 전에 잔액이나 숫자를 미리 바꾸지 않는다
//    - 앱이 "두 번째 등록이니 무료"를 스스로 계산하지 않는다
//
//  진행 중인 요청은 다시 보내지 않는다(§21) — 등록비와 구매는 연타로 두 번 나가면
//  사용자가 조각을 두 번 잃는다. 서버 멱등성이 있어도 앱이 먼저 막는다.
//

import Foundation
import SwiftUI

// MARK: - 상점

@MainActor
@Observable
final class MarketplaceStore {
    /// 앱이 쓰는 하나. `ShardWallet.live`와 같은 규칙이다.
    static let live = MarketplaceStore()

    /// 공개 목록. 서버가 준 것만 들어온다 — 상품이 없으면 비어 있다.
    private(set) var listings: [MarketplaceListing] = []
    /// 내가 좋아요한 상품. 공개 DTO에 `likedByMe`가 없으므로 따로 받아 합친다.
    private(set) var likedListingIDs: Set<String> = []
    /// 내가 산 상품.
    private(set) var purchasedListingIDs: Set<String> = []

    private(set) var isLoading = false
    /// 마지막 실패. 화면이 그대로 보여 준다. **HTTP 오류를 성공처럼 삼키지 않는다.**
    var failure: MarketplaceFailure?

    /// 진행 중인 mutation. 같은 상품에 같은 동작을 두 번 보내지 않는다.
    private(set) var inFlight: Set<InFlight> = []

    /// 카드 대표 이미지. listing id → PNG bytes.
    private(set) var previews: [String: Data] = [:]
    private var previewTasks: Set<String> = []

    private let backend: any MarketplaceBackend

    init(backend: any MarketplaceBackend = BackendClient()) {
        self.backend = backend
    }

    /// 어떤 요청이 떠 있는지. 화면이 버튼을 잠그는 데 쓴다.
    enum InFlight: Hashable {
        case publish(String)
        case unpublish(String)
        case purchase(String)
        case like(String)
        case snapshot
    }

    func isBusy(_ work: InFlight) -> Bool { inFlight.contains(work) }

    // MARK: - 공개 조회

    /// 목록을 받아온다. **로그인 없이도 된다.**
    ///
    /// 정렬은 서버에도 있지만 화면이 이미 `StoreSort`를 쓰고 있어 그 규칙을 그대로 둔다 —
    /// 두 곳이 다른 순서를 내면 사용자가 목록이 흔들리는 것으로 본다.
    func refresh(contentType: String?, sort: StoreSort, session: ServerSession? = nil) async {
        isLoading = true
        defer { isLoading = false }
        do {
            listings = try await backend.listings(contentType: contentType, sort: sort.serverValue)
            failure = nil
        } catch let error as MarketplaceFailure {
            failure = error
            return
        } catch {
            failure = .network
            return
        }
        // 로그인했다면 내 좋아요/구매를 합친다. 실패해도 목록은 그대로 보여 준다 —
        // 하트가 비는 것이 상점이 통째로 안 보이는 것보다 낫다.
        await refreshMine(session: session)
    }

    /// 내 좋아요 · 구매 목록. 로그인하지 않았으면 비운다.
    func refreshMine(session: ServerSession?) async {
        guard let token = session?.accessToken else {
            likedListingIDs = []
            purchasedListingIDs = []
            return
        }
        if let ids = try? await backend.likedListingIDs(accessToken: token) {
            likedListingIDs = Set(ids)
        }
        if let purchases = try? await backend.purchases(accessToken: token) {
            purchasedListingIDs = Set(purchases.map(\.listingId))
        }
    }

    /// 카드 대표 이미지를 한 번만 받아온다. 같은 상품에 요청을 겹치지 않는다.
    func loadPreview(_ listingID: String) async {
        guard previews[listingID] == nil, !previewTasks.contains(listingID) else { return }
        previewTasks.insert(listingID)
        defer { previewTasks.remove(listingID) }
        // 실패는 조용히 둔다 — 카드에 자리표시자가 남는다. 목록을 깨뜨릴 이유가 아니다.
        if let data = try? await backend.preview(listingID: listingID) {
            previews[listingID] = data
        }
    }

    // MARK: - 등록

    /// 꾸러미를 올리고 초안을 만든 뒤 게시까지. **등록비는 서버가 차감한다.**
    ///
    /// 세 단계가 하나의 사용자 동작이라 여기서 묶는다. 중간에 실패하면 그 자리에서
    /// 멈춘다 — snapshot만 남는 것은 안전하다(어떤 listing도 참조하지 않는다).
    ///
    /// 성공하면 서버가 말해 준 잔액을 지갑에 반영한다.
    @discardableResult
    func publish(
        package: SnapshotPackage,
        title: String,
        description: String,
        priceShards: Int,
        session: ServerSession?,
        wallet: ShardWallet? = nil
    ) async -> MarketplacePublishResult? {
        guard let token = session?.accessToken else {
            failure = .notSignedIn
            return nil
        }
        guard !isBusy(.snapshot) else { return nil }
        inFlight.insert(.snapshot)
        defer { inFlight.remove(.snapshot) }

        do {
            let snapshot = try await backend.createSnapshot(
                contentType: package.contentType,
                manifest: package.manifest,
                preview: package.preview,
                assets: package.assets,
                accessToken: token
            )
            let draft = try await backend.createDraft(
                MarketplaceDraftRequest(
                    contentType: package.contentType,
                    title: title,
                    description: description,
                    priceShards: priceShards,
                    snapshotId: snapshot.snapshotId
                ),
                accessToken: token
            )
            let result = try await backend.publish(listingID: draft.id, accessToken: token)
            // **서버가 말해 준 잔액만** 넣는다. 앱이 10을 빼지 않는다.
            wallet?.apply(balance: result.balance)
            failure = nil
            return result
        } catch let error as MarketplaceFailure {
            failure = error
            return nil
        } catch {
            failure = .network
            return nil
        }
    }

    /// 상점에서 내린다. **snapshot을 지우지 않는다** — 산 사람이 계속 받아야 한다.
    @discardableResult
    func unpublish(listingID: String, session: ServerSession?) async -> MarketplaceOwnedListing? {
        guard let token = session?.accessToken else {
            failure = .notSignedIn
            return nil
        }
        guard !isBusy(.unpublish(listingID)) else { return nil }
        inFlight.insert(.unpublish(listingID))
        defer { inFlight.remove(.unpublish(listingID)) }

        do {
            let listing = try await backend.unpublish(listingID: listingID, accessToken: token)
            // 공개 목록에서 사라진다.
            listings.removeAll { $0.id == listingID }
            failure = nil
            return listing
        } catch let error as MarketplaceFailure {
            failure = error
            return nil
        } catch {
            failure = .network
            return nil
        }
    }

    /// 다시 올린다. **추가 등록비가 없다** — `feeCharged=false`를 서버가 알려 준다.
    @discardableResult
    func republish(
        listingID: String, session: ServerSession?, wallet: ShardWallet? = nil
    ) async -> MarketplacePublishResult? {
        guard let token = session?.accessToken else {
            failure = .notSignedIn
            return nil
        }
        guard !isBusy(.publish(listingID)) else { return nil }
        inFlight.insert(.publish(listingID))
        defer { inFlight.remove(.publish(listingID)) }

        do {
            let result = try await backend.publish(listingID: listingID, accessToken: token)
            wallet?.apply(balance: result.balance)
            failure = nil
            return result
        } catch let error as MarketplaceFailure {
            failure = error
            return nil
        } catch {
            failure = .network
            return nil
        }
    }

    // MARK: - 구매

    /// 산다. **body를 보내지 않는다** — 가격 · 이동 · 소유권 · 카운터는 서버 transaction이다.
    ///
    /// 이미 산 상품이면 `alreadyOwned=true`로 돌아오고 **실패가 아니다.**
    @discardableResult
    func purchase(
        listingID: String, session: ServerSession?, wallet: ShardWallet? = nil
    ) async -> MarketplacePurchaseResult? {
        guard let token = session?.accessToken else {
            failure = .notSignedIn
            return nil
        }
        guard !isBusy(.purchase(listingID)) else { return nil }
        inFlight.insert(.purchase(listingID))
        defer { inFlight.remove(.purchase(listingID)) }

        do {
            let result = try await backend.purchase(listingID: listingID, accessToken: token)
            purchasedListingIDs.insert(result.listingId)
            // 서버가 센 값으로 카드를 맞춘다. 앱이 +1 하지 않는다.
            apply(downloadCount: result.downloadCount, to: listingID)
            wallet?.apply(balance: result.balance)
            failure = nil
            return result
        } catch let error as MarketplaceFailure {
            failure = error
            return nil
        } catch {
            failure = .network
            return nil
        }
    }

    // MARK: - 좋아요

    /// 좋아요를 켜거나 끈다. **조각을 움직이지 않는다.**
    ///
    /// 반복 요청은 `changed=false`로 조용히 끝난다. 자기 상품이면 서버가 거절한다.
    func toggleLike(listingID: String, session: ServerSession?) async {
        guard let token = session?.accessToken else {
            failure = .notSignedIn
            return
        }
        guard !isBusy(.like(listingID)) else { return }
        inFlight.insert(.like(listingID))
        defer { inFlight.remove(.like(listingID)) }

        let wasLiked = likedListingIDs.contains(listingID)
        do {
            let result = wasLiked
                ? try await backend.unlike(listingID: listingID, accessToken: token)
                : try await backend.like(listingID: listingID, accessToken: token)
            // **서버 결과로만** 반영한다.
            if result.liked { likedListingIDs.insert(result.listingId) }
            else { likedListingIDs.remove(result.listingId) }
            apply(likeCount: result.likeCount, to: result.listingId)
            failure = nil
        } catch let error as MarketplaceFailure {
            failure = error
        } catch {
            failure = .network
        }
    }

    // MARK: - 내부

    private func apply(downloadCount: Int, to listingID: String) {
        guard let index = listings.firstIndex(where: { $0.id == listingID }) else { return }
        listings[index] = listings[index].replacing(downloadCount: downloadCount)
    }

    private func apply(likeCount: Int, to listingID: String) {
        guard let index = listings.firstIndex(where: { $0.id == listingID }) else { return }
        listings[index] = listings[index].replacing(likeCount: likeCount)
    }
}

// MARK: - 서버 값 갱신

nonisolated extension MarketplaceListing {
    /// 서버가 센 값 하나만 바꾼 사본. `let`을 유지하기 위한 것이고
    /// **앱이 스스로 숫자를 올리는 자리가 아니다.**
    func replacing(downloadCount: Int? = nil, likeCount: Int? = nil) -> MarketplaceListing {
        MarketplaceListing(
            id: id,
            contentType: contentType,
            title: title,
            description: description,
            priceShards: priceShards,
            downloadCount: downloadCount ?? self.downloadCount,
            likeCount: likeCount ?? self.likeCount,
            publishedAt: publishedAt
        )
    }
}

// MARK: - 정렬 이름

nonisolated extension StoreSort {
    /// 서버 `sort` query 값. 화면 열거형과 서버 문자열을 한 곳에서만 잇는다.
    var serverValue: String {
        switch self {
        case .latest: "latest"
        case .popular: "popular"
        case .likes: "likes"
        }
    }
}

// MARK: - 정렬 대상

/// 상점 정렬이 보는 네 값. **`MirrorTemplate`(내장 목록)과 `MarketplaceListing`
/// (서버 상품)이 같은 규칙으로 정렬돼야** 사용자가 두 목록에서 다른 순서를 보지 않는다.
///
/// 구현이 둘 있어서 만든 것이다 — 하나였다면 만들지 않았다.
nonisolated protocol StoreSortable {
    var likeCount: Int { get }
    var downloadCount: Int { get }
    /// 처음 올라온 시각. 없으면 가장 뒤로 간다.
    var uploadedAtKey: Date { get }
    /// 마지막 tie-breaker. 값이 모두 같아도 순서가 흔들리지 않게 한다.
    var sortIdentity: String { get }
}

extension MirrorTemplate: StoreSortable {
    var sortIdentity: String { id }
}

extension MarketplaceListing: StoreSortable {
    /// 서버 `publishedAt` 그대로다. **DTO를 왜곡하지 않는다** —
    /// `uploadedAt`은 화면 쪽 이름일 뿐이고 값은 처음 올라온 시각이다.
    var uploadedAtKey: Date { publishedAt }
    var sortIdentity: String { id }
}
