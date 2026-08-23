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
    /// **내가 올린 상품 전부** — `draft` · `published` · `unlisted`.
    ///
    /// 자기 상품 관리의 **authority**다. 앱이 기억해 둔 listing id는 편의(cache)일
    /// 뿐이고, 앱을 지웠거나 기기를 바꾸면 사라진다 — 그때도 관리가 되어야 한다.
    private(set) var myListings: [MarketplaceOwnedListing] = []

    private(set) var isLoading = false
    /// 마지막 실패. 화면이 그대로 보여 준다. **HTTP 오류를 성공처럼 삼키지 않는다.**
    var failure: MarketplaceFailure?

    /// 진행 중인 mutation. 같은 상품에 같은 동작을 두 번 보내지 않는다.
    private(set) var inFlight: Set<InFlight> = []

    /// 카드 대표 이미지. listing id → PNG bytes.
    private(set) var previews: [String: Data] = [:]
    private var previewTasks: Set<String> = []
    /// **판매자 전용** 미리보기. 공개 것과 섞지 않는다 — 공개는 `published`만
    /// 받을 수 있고 이쪽은 draft · unlisted도 받는다. 한 사전에 넣으면
    /// 어느 권한으로 받은 것인지 알 수 없다.
    private(set) var myPreviews: [String: Data] = [:]
    private var myPreviewTasks: Set<String> = []
    /// 미리보기를 받으려다 실패한 것. 자리표시자를 "받는 중"과 구분한다.
    private(set) var myPreviewFailures: Set<String> = []

    private let backend: any MarketplaceBackend

    init(backend: any MarketplaceBackend = BackendClient()) {
        self.backend = backend
    }

    /// 어떤 요청이 떠 있는지. 화면이 버튼을 잠그는 데 쓴다.
    enum InFlight: Hashable {
        case publish(String)
        case unpublish(String)
        case delete(String)
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

    /// **내가 올린 상품을 서버에서 다시 받는다.** 자기 상품 관리의 authority다.
    ///
    /// 로그인하지 않았으면 비운다 — 이전 사용자의 목록이 남으면 안 된다.
    func refreshMyListings(session: ServerSession?) async {
        guard let token = session?.accessToken else {
            myListings = []
            return
        }
        do {
            myListings = try await backend.myListings(accessToken: token)
            failure = nil
        } catch let error as MarketplaceFailure {
            failure = error
        } catch {
            failure = .network
        }
    }

    /// 지금 **판매 중**인 것만. `내 거울` 화면이 쓴다.
    ///
    /// `draft` · `deleted`는 빠진다 — 판매 중이 아니다.
    func selling(contentType: String) -> [MarketplaceOwnedListing] {
        myListings.filter { $0.contentType == contentType && $0.isPublished }
    }

    /// 이 local 콘텐츠(`MyMirror.id` / `StickerProject.id`)로 판매 중인 상품.
    ///
    /// **서버가 준 `sourceContentId`로만 맞춘다.** 제목으로 맞추지 않는다 —
    /// 같은 제목이 여러 개일 수 있다.
    func sellingListing(forContentID contentID: String, contentType: String)
        -> MarketplaceOwnedListing?
    {
        selling(contentType: contentType).first { $0.sourceContentId == contentID }
    }

    /// **삭제한다.** 되살릴 수 없다 — 화면이 먼저 확인을 받아야 한다.
    ///
    /// 서버는 실제로 지우지 않는다(이미 산 사람은 계속 받는다). 등록비도 돌아오지
    /// 않으므로 **앱이 잔액을 건드리지 않는다** — 서버 상태만 다시 받는다.
    @discardableResult
    func delete(listingID: String, session: ServerSession?) async -> MarketplaceOwnedListing? {
        guard let token = session?.accessToken else {
            failure = .notSignedIn
            return nil
        }
        guard !isBusy(.delete(listingID)) else { return nil }
        inFlight.insert(.delete(listingID))
        defer { inFlight.remove(.delete(listingID)) }

        do {
            let listing = try await backend.deleteListing(
                listingID: listingID, accessToken: token
            )
            // 공개 목록에서 사라진다.
            listings.removeAll { $0.id == listingID }
            failure = nil
            await refreshMyListings(session: session)
            return listing
        } catch let error as MarketplaceFailure {
            failure = error
            return nil
        } catch {
            failure = .network
            return nil
        }
    }

    /// 이 listing이 지금 어떤 상태인지. **서버 목록에서만** 답한다.
    ///
    /// 없으면 `nil`이다 — 앱이 기억해 둔 id가 서버에 없을 수도 있다(다른 계정으로
    /// 로그인했거나, 서버에서 사라진 경우). 그때 "있다"고 하지 않는다.
    func myListing(id: String) -> MarketplaceOwnedListing? {
        myListings.first { $0.id == id }
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

    /// 내 상품 미리보기를 한 번만 받아온다.
    ///
    /// 실패는 카드 하나의 자리표시자로 끝난다 — 목록을 깨뜨릴 이유가 아니다.
    func loadMyPreview(_ listingID: String, session: ServerSession?) async {
        guard let token = session?.accessToken else { return }
        guard myPreviews[listingID] == nil, !myPreviewTasks.contains(listingID) else { return }
        myPreviewTasks.insert(listingID)
        defer { myPreviewTasks.remove(listingID) }
        do {
            myPreviews[listingID] = try await backend.myListingPreview(
                listingID: listingID, accessToken: token
            )
            myPreviewFailures.remove(listingID)
        } catch {
            myPreviewFailures.insert(listingID)
        }
    }

    /// 이 상품의 미리보기를 받는 중인가. 자리표시자 문구를 가른다.
    func isLoadingMyPreview(_ listingID: String) -> Bool {
        myPreviewTasks.contains(listingID)
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
            // **publish를 보내기 전에** listing id를 남긴다.
            //
            // production에서 정확히 이 자리가 문제였다: listing이 만들어진 뒤
            // publish가 실패했고, id를 들고 있지 않아서 다시 시도할 때 앱이 snapshot과
            // listing을 **또** 만들었다. 같은 콘텐츠가 두 건이 되고 GCS object도 두 배가
            // 됐다. 실패가 반복되면 계속 쌓인다.
            //
            // 지금은 이 시점에 저장하므로, 앱이 죽어도 다음에 그 listing의 publish만
            // 다시 보낸다. 저장이 실패하면 publish를 보내지 않는다 — 보내고 나서
            // 응답을 잃으면 그 listing을 영원히 못 찾는다.
            guard onListingCreated?(draft.id) ?? true else {
                failure = .invalidPackage
                return nil
            }

            let result = try await backend.publish(listingID: draft.id, accessToken: token)
            // **서버가 말해 준 잔액만** 넣는다. 앱이 10을 빼지 않는다.
            wallet?.apply(balance: result.balance)
            failure = nil
            // 방금 올린 것이 판매자 목록에 보여야 한다. 서버가 authority다.
            await refreshMyListings(session: session)
            return result
        } catch let error as MarketplaceFailure {
            failure = error
            // publish가 실패했어도 **목록은 새로 받는다** — 서버에 draft가 남아 있고,
            // 그것이 "등록 미완료"로 보여야 사용자가 이어서 올릴 수 있다.
            await refreshMyListings(session: session)
            return nil
        } catch {
            failure = .network
            await refreshMyListings(session: session)
            return nil
        }
    }

    /// listing이 만들어진 직후, **publish를 보내기 전에** 불린다.
    ///
    /// 호출부가 id를 지역에 저장한다. `false`를 돌려주면 publish를 보내지 않는다 —
    /// 저장하지 못한 id로 publish를 보내면 실패했을 때 그 listing을 다시 찾을 수 없다.
    var onListingCreated: ((String) -> Bool)?

    /// 이미 서버에 있는 listing의 등록을 **이어서** 마친다.
    ///
    /// 새 snapshot도 새 listing도 만들지 않는다. 서버 상태를 authority로 보고 판단한다:
    ///
    /// | 서버 상태 | 하는 일 |
    /// |---|---|
    /// | `draft` | 그 listing의 publish만 다시 보낸다 |
    /// | `unlisted` | 같은 publish endpoint(다시 올리기). 추가 등록비 없음 |
    /// | `published` | 아무 것도 하지 않는다 — 이미 올라가 있다 |
    /// | 없음 | 지역 기억이 낡았다. 호출부가 새 등록을 시작해도 된다(`nil`) |
    ///
    /// **제목으로 맞추지 않는다** — 같은 제목이 여러 개일 수 있다.
    /// 등록비 판단은 서버가 `publishFeePaid`로 한다. 앱이 계산하지 않는다.
    func resumePublish(
        listingID: String, session: ServerSession?, wallet: ShardWallet? = nil
    ) async -> ResumeOutcome {
        guard session?.accessToken != nil else {
            failure = .notSignedIn
            return .needsSignIn
        }
        await refreshMyListings(session: session)
        guard let listing = myListing(id: listingID) else { return .missing }

        if listing.isPublished { return .alreadyPublished(listing) }

        guard let result = await republish(
            listingID: listingID, session: session, wallet: wallet
        ) else {
            return .failed(failure ?? .network)
        }
        return .published(result)
    }

    /// `resumePublish` 결과. 화면이 무엇을 말할지 정한다.
    enum ResumeOutcome {
        case published(MarketplacePublishResult)
        /// 이미 올라가 있었다. 추가 요청도 추가 등록비도 없다.
        case alreadyPublished(MarketplaceOwnedListing)
        /// 서버에 그 listing이 없다 — 지역 기억이 낡았다.
        case missing
        case needsSignIn
        case failed(MarketplaceFailure)
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
            // 상태가 `unlisted`로 바뀐 것을 서버에서 다시 받는다 — 앱이 추측하지 않는다.
            await refreshMyListings(session: session)
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
            await refreshMyListings(session: session)
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
