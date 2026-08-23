//
//  MarketplaceTests.swift
//  ggumirrorTests
//
//  상점 연결. **실제 production을 부르지 않는다** — 전부 fake backend다.
//
//  보는 것 넷:
//    1. 서버 DTO를 우리가 제대로 읽는가
//    2. 정렬이 내장 목록과 같은 규칙인가
//    3. manifest 참조 asset을 정확히 모으는가 (빠짐 / 남음 모두 실패)
//    4. 조각을 앱이 직접 바꾸지 않는가
//

import Foundation
import SwiftUI
import Testing
@testable import ggumirror

// MARK: - fake backend

/// 실제 network 없이 흐름만 본다. `ShardBackend` fake와 같은 규칙이다.
private final class FakeMarketplaceBackend: MarketplaceBackend, @unchecked Sendable {
    var listingsResult: [MarketplaceListing] = []
    var previewResult = Data()
    var snapshotResult = MarketplaceSnapshot(
        snapshotId: "snap-1", contentType: "mirror",
        assetCount: 0, totalBytes: 1, manifestChecksum: "abc"
    )
    var draftResult = MarketplaceOwnedListing(
        id: "listing-1", contentType: "mirror", title: "제목", description: "",
        priceShards: 0, status: "draft", downloadCount: 0, likeCount: 0, publishedAt: nil
    )
    var publishResult: MarketplacePublishResult?
    var purchaseResult: MarketplacePurchaseResult?
    var likeResult: MarketplaceLikeResult?
    var manifestResult = Data()
    var assetResults: [UUID: Data] = [:]
    var failure: MarketplaceFailure?

    /// 무엇이 몇 번 불렸는지. 연타 보호를 확인하는 데 쓴다.
    var calls: [String] = []
    /// 업로드한 asset 이름. exact-set을 확인한다.
    var uploadedAssetIDs: Set<UUID> = []
    /// 마지막으로 보낸 manifest bytes.
    var uploadedManifest: Data?
    /// Bearer로 넘어온 token. **값 자체를 로그하지 않는다** — 존재만 확인한다.
    var sawToken = false

    private func check() throws { if let failure { throw failure } }

    func listings(contentType: String?, sort: String) async throws -> [MarketplaceListing] {
        calls.append("listings(\(contentType ?? "-"),\(sort))")
        try check()
        return listingsResult
    }
    func listing(id: String) async throws -> MarketplaceListing {
        calls.append("listing")
        try check()
        guard let found = listingsResult.first(where: { $0.id == id }) else {
            throw MarketplaceFailure.notFound
        }
        return found
    }
    func preview(listingID: String) async throws -> Data {
        calls.append("preview(\(listingID))")
        try check()
        return previewResult
    }
    func createSnapshot(
        contentType: String, manifest: Data, preview: Data, assets: [UUID: Data],
        accessToken: String
    ) async throws -> MarketplaceSnapshot {
        calls.append("createSnapshot(\(contentType))")
        sawToken = !accessToken.isEmpty
        uploadedAssetIDs = Set(assets.keys)
        uploadedManifest = manifest
        try check()
        return snapshotResult
    }
    func createDraft(
        _ request: MarketplaceDraftRequest, accessToken: String
    ) async throws -> MarketplaceOwnedListing {
        calls.append("createDraft(\(request.priceShards))")
        try check()
        return draftResult
    }
    func publish(listingID: String, accessToken: String) async throws -> MarketplacePublishResult {
        calls.append("publish(\(listingID))")
        try check()
        guard let publishResult else { throw MarketplaceFailure.cannotPublish }
        return publishResult
    }
    func unpublish(listingID: String, accessToken: String) async throws -> MarketplaceOwnedListing {
        calls.append("unpublish(\(listingID))")
        try check()
        return draftResult
    }
    func purchase(
        listingID: String, accessToken: String
    ) async throws -> MarketplacePurchaseResult {
        calls.append("purchase(\(listingID))")
        try check()
        guard let purchaseResult else { throw MarketplaceFailure.notFound }
        return purchaseResult
    }
    func purchases(accessToken: String) async throws -> [MarketplacePurchase] {
        calls.append("purchases")
        try check()
        return []
    }
    var myListingsResult: [MarketplaceOwnedListing] = []
    var deleteResult: MarketplaceOwnedListing?
    /// 켜면 응답이 잠깐 늦는다. **연타를 시험하려면 실제로 멈춰야** 한다 —
    /// 즉시 반환하면 첫 호출이 끝난 뒤에 둘째가 시작해서 겹치지 않는다.
    var slowDelete = false
    func deleteListing(
        listingID: String, accessToken: String
    ) async throws -> MarketplaceOwnedListing {
        calls.append("deleteListing(\(listingID))")
        if slowDelete { try? await Task.sleep(for: .milliseconds(80)) }
        sawToken = !accessToken.isEmpty
        try check()
        return deleteResult ?? MarketplaceOwnedListing(
            id: listingID, contentType: "mirror", title: "t", description: "",
            priceShards: 0, status: "deleted", downloadCount: 0, likeCount: 0,
            publishedAt: nil
        )
    }

    var myPreviewResult = Data()
    func myListingPreview(listingID: String, accessToken: String) async throws -> Data {
        calls.append("myListingPreview(\(listingID))")
        sawToken = !accessToken.isEmpty
        try check()
        return myPreviewResult
    }
    func myListings(accessToken: String) async throws -> [MarketplaceOwnedListing] {
        calls.append("myListings")
        sawToken = !accessToken.isEmpty
        try check()
        return myListingsResult
    }
    func like(listingID: String, accessToken: String) async throws -> MarketplaceLikeResult {
        calls.append("like(\(listingID))")
        try check()
        guard let likeResult else { throw MarketplaceFailure.notFound }
        return likeResult
    }
    func unlike(listingID: String, accessToken: String) async throws -> MarketplaceLikeResult {
        calls.append("unlike(\(listingID))")
        try check()
        guard let likeResult else { throw MarketplaceFailure.notFound }
        return likeResult
    }
    func likedListingIDs(accessToken: String) async throws -> [String] {
        calls.append("likedListingIDs")
        try check()
        return []
    }
    func templateManifest(listingID: String, accessToken: String) async throws -> Data {
        calls.append("templateManifest(\(listingID))")
        try check()
        return manifestResult
    }
    func templateAsset(
        listingID: String, assetID: UUID, accessToken: String
    ) async throws -> Data {
        calls.append("templateAsset(\(assetID.uuidString))")
        try check()
        guard let data = assetResults[assetID] else { throw MarketplaceFailure.notFound }
        return data
    }
}

private func session() -> ServerSession {
    ServerSession(accessToken: "test-token", expiresAt: .distantFuture, userID: "user-1")
}

private func listing(
    id: String,
    contentType: String = "mirror",
    price: Int = 10,
    downloads: Int = 0,
    likes: Int = 0,
    published: Date = Date(timeIntervalSince1970: 1_000)
) -> MarketplaceListing {
    MarketplaceListing(
        id: id, contentType: contentType, title: "상품 \(id)", description: "설명",
        priceShards: price, downloadCount: downloads, likeCount: likes, publishedAt: published
    )
}

// MARK: - DTO

@Suite("상점 DTO")
struct MarketplaceDTOTests {

    @Test("공개 목록을 서버 wire format 그대로 읽는다")
    func decodesPublicListing() throws {
        let json = """
        [{"id":"abc","contentType":"mirror","title":"내 거울","description":"설명",
          "priceShards":30,"downloadCount":4,"likeCount":2,
          "publishedAt":"2026-08-19T10:00:12.551858Z"}]
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.backend.decode([MarketplaceListing].self, from: json)

        #expect(decoded.count == 1)
        #expect(decoded[0].id == "abc")
        #expect(decoded[0].contentType == "mirror")
        #expect(decoded[0].priceShards == 30)
        #expect(decoded[0].downloadCount == 4)
        #expect(decoded[0].likeCount == 2)
    }

    @Test("소수점 초가 없는 날짜도 읽는다")
    func decodesDateWithoutFraction() throws {
        let json = """
        {"id":"a","contentType":"sticker","title":"t","description":"",
         "priceShards":0,"downloadCount":0,"likeCount":0,
         "publishedAt":"2026-08-19T10:00:12Z"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.backend.decode(MarketplaceListing.self, from: json)
        #expect(decoded.publishedAt.timeIntervalSince1970 > 0)
    }

    @Test("publishedAt이 정렬용 uploadedAt으로 그대로 쓰인다")
    func publishedAtIsTheSortKey() {
        let when = Date(timeIntervalSince1970: 12_345)
        #expect(listing(id: "a", published: when).uploadedAtKey == when)
    }

    @Test("판매자 listing은 publishedAt이 nil일 수 있다")
    func ownedListingAllowsNilPublishedAt() throws {
        let json = """
        {"id":"a","contentType":"mirror","title":"t","description":"","priceShards":0,
         "status":"draft","downloadCount":0,"likeCount":0,"publishedAt":null}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.backend.decode(MarketplaceOwnedListing.self, from: json)
        #expect(decoded.publishedAt == nil)
        #expect(decoded.status == "draft")
    }

    @Test("구매 응답의 alreadyOwned를 읽는다")
    func decodesPurchase() throws {
        let json = """
        {"purchased":false,"alreadyOwned":true,"pricePaid":0,"balance":140,
         "downloadCount":1,"listingId":"abc","acquiredAt":"2026-08-19T10:00:12Z"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.backend.decode(MarketplacePurchaseResult.self, from: json)
        #expect(decoded.alreadyOwned)
        #expect(!decoded.purchased)
        #expect(decoded.balance == 140)
    }

    @Test("정렬 이름이 서버 query 값과 같다")
    func sortNamesMatchServer() {
        #expect(StoreSort.latest.serverValue == "latest")
        #expect(StoreSort.popular.serverValue == "popular")
        #expect(StoreSort.likes.serverValue == "likes")
    }
}

// MARK: - 오류 분류

@Suite("상점 오류 분류")
struct MarketplaceFailureTests {

    private func detail(_ text: String) -> Data {
        try! JSONEncoder().encode(["detail": text])
    }

    @Test("서버가 실제로 내는 실패만 구분한다")
    func classifiesRealFailures() {
        #expect(MarketplaceFailure.from(status: 401, data: Data()) == .notSignedIn)
        #expect(MarketplaceFailure.from(status: 403, data: Data()) == .notSignedIn)
        #expect(
            MarketplaceFailure.from(status: 409, data: detail("not enough shards"))
                == .insufficientShards
        )
        #expect(
            MarketplaceFailure.from(status: 409, data: detail("listing cannot be published"))
                == .cannotPublish
        )
        #expect(
            MarketplaceFailure.from(status: 400, data: detail("cannot buy your own listing"))
                == .selfPurchase
        )
        #expect(
            MarketplaceFailure.from(status: 400, data: detail("cannot like your own listing"))
                == .selfLike
        )
        #expect(MarketplaceFailure.from(status: 404, data: detail("template not found")) == .notFound)
        #expect(
            MarketplaceFailure.from(status: 503, data: detail("storage unavailable"))
                == .storageUnavailable
        )
        #expect(
            MarketplaceFailure.from(status: 400, data: detail("package is not valid"))
                == .invalidPackage
        )
        #expect(
            MarketplaceFailure.from(status: 413, data: detail("package is too large"))
                == .invalidPackage
        )
    }

    @Test("권한 없는 template 요청은 404다 — 존재 여부를 알려주지 않는다")
    func forbiddenTemplateLooksMissing() {
        // 서버가 403이 아니라 404를 준다(B-7F). client도 하나로 다룬다.
        #expect(MarketplaceFailure.from(status: 404, data: detail("template not found")) == .notFound)
    }

    @Test("사용자 문구에 서버 내부 사정을 옮기지 않는다")
    func messagesDoNotLeakServerText() {
        let leaky = MarketplaceFailure.from(status: 400, data: detail("package is not valid"))
        #expect(!leaky.message.contains("package"))
        #expect(!leaky.message.contains("valid"))
    }

    @Test("다시 시도할 수 있는 실패를 구분한다")
    func temporaryFailures() {
        #expect(MarketplaceFailure.network.isTemporary)
        #expect(MarketplaceFailure.storageUnavailable.isTemporary)
        #expect(!MarketplaceFailure.insufficientShards.isTemporary)
        #expect(!MarketplaceFailure.selfPurchase.isTemporary)
    }
}

// MARK: - 정렬

@Suite("상점 정렬 계약")
struct MarketplaceSortTests {

    @Test("최신 순은 publishedAt 내림차순")
    func latest() {
        let items = [
            listing(id: "old", published: Date(timeIntervalSince1970: 100)),
            listing(id: "new", published: Date(timeIntervalSince1970: 900)),
        ]
        #expect(StoreSort.latest.ordered(items).map(\.id) == ["new", "old"])
    }

    @Test("인기 순은 다운로드 수만 본다 — 좋아요를 섞지 않는다")
    func popularIsDownloadsOnly() {
        let items = [
            listing(id: "manyLikes", downloads: 1, likes: 99),
            listing(id: "manyDownloads", downloads: 5, likes: 0),
        ]
        #expect(StoreSort.popular.ordered(items).map(\.id) == ["manyDownloads", "manyLikes"])
    }

    @Test("좋아요 순은 좋아요 → 다운로드 → 날짜 순서로 푼다")
    func likesTieBreakers() {
        let items = [
            listing(id: "a", downloads: 1, likes: 5, published: Date(timeIntervalSince1970: 100)),
            listing(id: "b", downloads: 9, likes: 5, published: Date(timeIntervalSince1970: 100)),
            listing(id: "c", downloads: 9, likes: 5, published: Date(timeIntervalSince1970: 900)),
            listing(id: "d", downloads: 0, likes: 7),
        ]
        #expect(StoreSort.likes.ordered(items).map(\.id) == ["d", "c", "b", "a"])
    }

    @Test("값이 모두 같으면 id로 안정화된다 — 순서가 흔들리지 않는다")
    func deterministicTieBreak() {
        let same = Date(timeIntervalSince1970: 500)
        let items = [
            listing(id: "z", downloads: 3, likes: 3, published: same),
            listing(id: "a", downloads: 3, likes: 3, published: same),
        ]
        for sort in StoreSort.allCases {
            #expect(sort.ordered(items).map(\.id) == ["a", "z"], "\(sort)")
        }
    }

    @Test("내장 목록과 서버 상품이 같은 규칙을 쓴다")
    func sameRuleForBothLists() {
        // 같은 비교 논리를 두 번 쓰지 않는다는 것을 형태로 고정한다.
        let templates = StoreSort.popular.sorted(StoreCatalog.samples)
        let generic = StoreSort.popular.ordered(StoreCatalog.samples)
        #expect(templates.map(\.id) == generic.map(\.id))
    }
}

// MARK: - 참조 asset 추출

@Suite("꾸러미 asset 참조")
struct SnapshotAssetReferenceTests {

    private let photoAsset = UUID(uuidString: "A0000001-0000-4000-A000-000000000001")!
    private let artworkAsset = UUID(uuidString: "B0000002-0000-4000-A000-000000000002")!
    private let finalAsset = UUID(uuidString: "C0000003-0000-4000-A000-000000000003")!

    private func mirror(stickers: [StickerObject] = [], artworks: [ImportedArtworkObject] = [])
        -> MyMirror
    {
        MyMirror(
            id: "m", name: "거울", origin: .made, style: MirrorStyle(frame: .white),
            stickers: stickers, importedArtworks: artworks
        )
    }

    private func photoSticker(_ id: UUID) -> StickerObject {
        StickerObject(
            source: .photo(assetID: id, aspectRatio: 1),
            frame: NormalizedRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        )
    }

    @Test("사진 스티커 assetID를 모은다")
    func collectsPhotoSticker() {
        let result = SnapshotAssetReferences.mirror(mirror(stickers: [photoSticker(photoAsset)]))
        #expect(result.photos == [photoAsset])
        #expect(result.artworks.isEmpty)
    }

    @Test("외부 디자인 assetID를 모은다")
    func collectsImportedArtwork() {
        let result = SnapshotAssetReferences.mirror(
            mirror(artworks: [ImportedArtworkObject(assetID: artworkAsset)])
        )
        #expect(result.artworks == [artworkAsset])
        #expect(result.photos.isEmpty)
    }

    @Test("사진이 아닌 스티커는 asset을 참조하지 않는다")
    func builtInStickersReferenceNothing() {
        let builtIn = StickerObject(
            source: .builtIn(.heart),
            frame: NormalizedRect(x: 0.3, y: 0.3, width: 0.1, height: 0.1)
        )
        let doodle = StickerObject(
            source: .doodle(.heart),
            frame: NormalizedRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)
        )
        let result = SnapshotAssetReferences.mirror(mirror(stickers: [builtIn, doodle]))
        #expect(result.photos.isEmpty)
        #expect(result.artworks.isEmpty)
    }

    @Test("오브젝트 자기 id는 asset이 아니다")
    func objectIDsAreNotAssets() {
        let sticker = photoSticker(photoAsset)
        let result = SnapshotAssetReferences.mirror(mirror(stickers: [sticker]))
        #expect(!result.photos.contains(sticker.id))
        #expect(result.photos == [photoAsset])
    }

    @Test("같은 사진을 두 군데서 참조해도 하나다")
    func repeatedReferenceCollapses() {
        let result = SnapshotAssetReferences.mirror(
            mirror(stickers: [photoSticker(photoAsset), photoSticker(photoAsset)])
        )
        #expect(result.photos == [photoAsset])
    }

    @Test("스티커는 finalAssetID와 design 안쪽을 모은다")
    func collectsStickerReferences() {
        var design = MirrorDesign.blankSticker(id: "s", name: "스티커")
        design.stickers = [photoSticker(photoAsset)]
        design.importedArtworks = [ImportedArtworkObject(assetID: artworkAsset)]
        let project = StickerProject(
            id: "s", name: "스티커", design: design, finalAssetID: finalAsset
        )

        let result = SnapshotAssetReferences.sticker(project)

        #expect(result.finalAsset == finalAsset)
        #expect(result.photos == [photoAsset])
        #expect(result.artworks == [artworkAsset])
    }

    @Test("finalAssetID가 없으면 만들어내지 않는다")
    func absentFinalAssetStaysAbsent() {
        let project = StickerProject(
            id: "s", name: "스티커",
            design: MirrorDesign.blankSticker(id: "s", name: "스티커"),
            finalAssetID: nil
        )
        #expect(SnapshotAssetReferences.sticker(project).finalAsset == nil)
    }

    @Test("generationIDs는 asset이 아니다 — 올리지 않는다")
    func generationIDsAreNotAssets() {
        let project = StickerProject(
            id: "s", name: "스티커",
            design: MirrorDesign.blankSticker(id: "s", name: "스티커"),
            finalAssetID: finalAsset,
            origin: .aiGenerated,
            generationIDs: ["gen-1", "gen-2"]
        )
        let result = SnapshotAssetReferences.sticker(project)
        #expect(result.photos.isEmpty)
        #expect(result.artworks.isEmpty)
        #expect(result.finalAsset == finalAsset)
    }
}

// MARK: - 꾸러미 만들기

@MainActor
@Suite("꾸러미 만들기")
struct SnapshotPackagerTests {

    private let missingAsset = UUID(uuidString: "D0000004-0000-4000-A000-000000000004")!

    private func mirror(stickers: [StickerObject] = []) -> MyMirror {
        MyMirror(
            id: "m", name: "거울", origin: .made,
            style: MirrorStyle(frame: .white), stickers: stickers
        )
    }

    @Test("asset 없는 거울은 그대로 꾸러미가 된다")
    func packagesAssetFreeMirror() throws {
        let package = try SnapshotPackager.package(mirror())

        #expect(package.contentType == "mirror")
        #expect(package.assets.isEmpty)
        #expect(!package.manifest.isEmpty)
        #expect(!package.preview.isEmpty)
    }

    @Test("manifest는 MyMirror Codable 그대로다 — 새 schema를 만들지 않는다")
    func manifestIsTheClientCodable() throws {
        let package = try SnapshotPackager.package(mirror())
        let decoded = try JSONDecoder.marketplace.decode(MyMirror.self, from: package.manifest)

        #expect(decoded.id == "m")
        #expect(decoded.name == "거울")

        // 서버가 요구하는 최소 구조가 들어 있다.
        let object = try #require(
            try JSONSerialization.jsonObject(with: package.manifest) as? [String: Any]
        )
        for key in ["id", "name", "style", "strokes", "stickers", "texts", "importedArtworks"] {
            #expect(object[key] != nil, "\(key)가 없다")
        }
        // 서버가 발명했던 필드는 없다.
        #expect(object["assetIds"] == nil)
    }

    @Test("대표 이미지는 PNG다")
    func previewIsPNG() throws {
        let package = try SnapshotPackager.package(mirror())
        let magic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(package.preview.prefix(8)) == magic)
    }

    @Test("manifest에 경로가 들어가지 않는다")
    func manifestHasNoPaths() throws {
        let package = try SnapshotPackager.package(mirror())
        let text = try #require(String(data: package.manifest, encoding: .utf8))
        for banned in ["/Users/", "file://", "http://", "https://", "../", ".png"] {
            #expect(!text.contains(banned), "\(banned)가 들어갔다")
        }
    }

    @Test("이미지가 없으면 보내기 전에 실패한다 — 반쪽 꾸러미를 올리지 않는다")
    func missingLocalAssetFailsBeforeUpload() {
        let sticker = StickerObject(
            source: .photo(assetID: missingAsset, aspectRatio: 1),
            frame: NormalizedRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        )
        // 저장소도 캐시도 없으므로 이 사진을 찾을 수 없다.
        #expect(throws: SnapshotPackagingFailure.missingAsset(missingAsset)) {
            try SnapshotPackager.package(
                mirror(stickers: [sticker]),
                store: nil,
                photos: PhotoStickerAssetStore(),
                artworks: ImportedArtworkAssetStore()
            )
        }
    }

    @Test("같은 문서는 같은 바이트로 나간다 — checksum이 흔들리지 않는다")
    func manifestBytesAreStable() throws {
        let subject = mirror()
        let first = try SnapshotPackager.package(subject).manifest
        let second = try SnapshotPackager.package(subject).manifest
        #expect(first == second)
    }
}

// MARK: - 상점 상태

@MainActor
@Suite("상점 상태")
struct MarketplaceStoreTests {

    private func store(_ backend: FakeMarketplaceBackend) -> MarketplaceStore {
        MarketplaceStore(backend: backend)
    }

    @Test("공개 목록은 로그인 없이 받아온다")
    func browsesWithoutAuth() async {
        let backend = FakeMarketplaceBackend()
        backend.listingsResult = [listing(id: "a")]
        let subject = store(backend)

        await subject.refresh(contentType: "mirror", sort: .latest, session: nil)

        #expect(subject.listings.map(\.id) == ["a"])
        #expect(subject.failure == nil)
        // 로그인하지 않았으면 내 좋아요/구매를 묻지 않는다.
        #expect(!backend.calls.contains("likedListingIDs"))
    }

    @Test("상품이 없으면 빈 목록이다 — 가짜 상품을 만들지 않는다")
    func emptyStaysEmpty() async {
        let backend = FakeMarketplaceBackend()
        let subject = store(backend)

        await subject.refresh(contentType: "mirror", sort: .latest)

        #expect(subject.listings.isEmpty)
    }

    @Test("실패를 성공처럼 삼키지 않는다")
    func surfacesFailure() async {
        let backend = FakeMarketplaceBackend()
        backend.failure = .storageUnavailable
        let subject = store(backend)

        await subject.refresh(contentType: "mirror", sort: .latest)

        #expect(subject.failure == .storageUnavailable)
        #expect(subject.listings.isEmpty)
    }

    @Test("대표 이미지는 같은 상품에 한 번만 받는다")
    func previewLoadsOnce() async {
        let backend = FakeMarketplaceBackend()
        backend.previewResult = Data([0x89, 0x50])
        let subject = store(backend)

        await subject.loadPreview("a")
        await subject.loadPreview("a")

        #expect(subject.previews["a"] == Data([0x89, 0x50]))
        #expect(backend.calls.filter { $0 == "preview(a)" }.count == 1)
    }

    @Test("로그인 없이 등록하면 서버를 부르지 않는다")
    func publishRequiresSignIn() async {
        let backend = FakeMarketplaceBackend()
        let subject = store(backend)
        let package = SnapshotPackage(
            manifest: Data("{}".utf8), preview: Data([0x89]), assets: [:], contentType: "mirror"
        )

        let result = await subject.publish(
            package: package, title: "제목", description: "", priceShards: 0, session: nil
        )

        #expect(result == nil)
        #expect(subject.failure == .notSignedIn)
        #expect(backend.calls.isEmpty)
    }

    @Test("등록 결과의 잔액을 지갑에 넣는다 — 앱이 10을 빼지 않는다")
    func walletFollowsServerBalance() async {
        let backend = FakeMarketplaceBackend()
        backend.publishResult = MarketplacePublishResult(
            published: true, feeCharged: true, feeShards: 10, balance: 142,
            listing: backend.draftResult
        )
        let subject = store(backend)
        let wallet = ShardWallet(backend: FakeShardBackendForMarketplace())
        wallet.apply(balance: 152)
        let package = SnapshotPackage(
            manifest: Data("{}".utf8), preview: Data([0x89]), assets: [:], contentType: "mirror"
        )

        let result = await subject.publish(
            package: package, title: "제목", description: "", priceShards: 0,
            session: session(), wallet: wallet
        )

        #expect(result?.feeCharged == true)
        #expect(result?.feeShards == 10)
        // 서버가 말해 준 값 그대로다. 152 - 10을 앱이 계산한 것이 아니다.
        #expect(wallet.balance == 142)
    }

    @Test("등록비 차감 여부를 앱이 판단하지 않는다")
    func republishFeeComesFromServer() async {
        let backend = FakeMarketplaceBackend()
        backend.publishResult = MarketplacePublishResult(
            published: true, feeCharged: false, feeShards: 10, balance: 142,
            listing: backend.draftResult
        )
        let subject = store(backend)

        let result = await subject.republish(listingID: "listing-1", session: session())

        #expect(result?.feeCharged == false)
    }

    @Test("구매는 서버가 센 값만 반영한다")
    func purchaseUsesServerNumbers() async {
        let backend = FakeMarketplaceBackend()
        backend.listingsResult = [listing(id: "a", downloads: 0)]
        backend.purchaseResult = MarketplacePurchaseResult(
            purchased: true, alreadyOwned: false, pricePaid: 10, balance: 90,
            downloadCount: 1, listingId: "a", acquiredAt: Date()
        )
        let subject = store(backend)
        await subject.refresh(contentType: "mirror", sort: .latest)
        let wallet = ShardWallet(backend: FakeShardBackendForMarketplace())
        wallet.apply(balance: 100)

        let result = await subject.purchase(listingID: "a", session: session(), wallet: wallet)

        #expect(result?.purchased == true)
        #expect(wallet.balance == 90)
        #expect(subject.listings[0].downloadCount == 1)
        #expect(subject.purchasedListingIDs.contains("a"))
    }

    @Test("이미 산 상품은 실패가 아니다")
    func alreadyOwnedIsNotAFailure() async {
        let backend = FakeMarketplaceBackend()
        backend.purchaseResult = MarketplacePurchaseResult(
            purchased: false, alreadyOwned: true, pricePaid: 0, balance: 90,
            downloadCount: 1, listingId: "a", acquiredAt: Date()
        )
        let subject = store(backend)

        let result = await subject.purchase(listingID: "a", session: session())

        #expect(result?.alreadyOwned == true)
        #expect(subject.failure == nil)
    }

    @Test("조각이 부족하면 그렇게 말한다")
    func insufficientShardsSurfaces() async {
        let backend = FakeMarketplaceBackend()
        backend.failure = .insufficientShards
        let subject = store(backend)

        let result = await subject.purchase(listingID: "a", session: session())

        #expect(result == nil)
        #expect(subject.failure == .insufficientShards)
    }

    @Test("자기 상품 구매 거절을 그대로 보여 준다")
    func selfPurchaseSurfaces() async {
        let backend = FakeMarketplaceBackend()
        backend.failure = .selfPurchase
        let subject = store(backend)

        _ = await subject.purchase(listingID: "a", session: session())

        #expect(subject.failure == .selfPurchase)
    }

    @Test("좋아요는 서버 결과로만 반영한다")
    func likeFollowsServer() async {
        let backend = FakeMarketplaceBackend()
        backend.listingsResult = [listing(id: "a", likes: 0)]
        backend.likeResult = MarketplaceLikeResult(
            listingId: "a", liked: true, changed: true, likeCount: 1
        )
        let subject = store(backend)
        await subject.refresh(contentType: "mirror", sort: .latest)

        await subject.toggleLike(listingID: "a", session: session())

        #expect(subject.likedListingIDs.contains("a"))
        #expect(subject.listings[0].likeCount == 1)
    }

    @Test("좋아요 취소도 서버 결과를 따른다")
    func unlikeFollowsServer() async {
        let backend = FakeMarketplaceBackend()
        backend.listingsResult = [listing(id: "a", likes: 1)]
        backend.likeResult = MarketplaceLikeResult(
            listingId: "a", liked: true, changed: true, likeCount: 1
        )
        let subject = store(backend)
        await subject.refresh(contentType: "mirror", sort: .latest)
        await subject.toggleLike(listingID: "a", session: session())

        backend.likeResult = MarketplaceLikeResult(
            listingId: "a", liked: false, changed: true, likeCount: 0
        )
        await subject.toggleLike(listingID: "a", session: session())

        #expect(!subject.likedListingIDs.contains("a"))
        #expect(subject.listings[0].likeCount == 0)
        #expect(backend.calls.contains("unlike(a)"))
    }

    @Test("자기 상품 좋아요 거절을 그대로 보여 준다")
    func selfLikeSurfaces() async {
        let backend = FakeMarketplaceBackend()
        backend.failure = .selfLike
        let subject = store(backend)

        await subject.toggleLike(listingID: "a", session: session())

        #expect(subject.failure == .selfLike)
    }

    @Test("좋아요는 조각을 움직이지 않는다")
    func likeDoesNotTouchShards() async {
        let backend = FakeMarketplaceBackend()
        backend.likeResult = MarketplaceLikeResult(
            listingId: "a", liked: true, changed: true, likeCount: 1
        )
        let subject = store(backend)
        let wallet = ShardWallet(backend: FakeShardBackendForMarketplace())
        wallet.apply(balance: 100)

        await subject.toggleLike(listingID: "a", session: session())

        #expect(wallet.balance == 100)
    }

    @Test("내리면 공개 목록에서 사라진다")
    func unpublishRemovesFromBrowse() async {
        let backend = FakeMarketplaceBackend()
        backend.listingsResult = [listing(id: "a")]
        let subject = store(backend)
        await subject.refresh(contentType: "mirror", sort: .latest)

        _ = await subject.unpublish(listingID: "a", session: session())

        #expect(subject.listings.isEmpty)
    }

    @Test("Bearer token은 API client가 넣는다 — 화면이 조립하지 않는다")
    func tokenGoesThroughTheClient() async {
        let backend = FakeMarketplaceBackend()
        let subject = store(backend)
        let package = SnapshotPackage(
            manifest: Data("{}".utf8), preview: Data([0x89]), assets: [:], contentType: "mirror"
        )
        backend.publishResult = MarketplacePublishResult(
            published: true, feeCharged: true, feeShards: 10, balance: 1,
            listing: backend.draftResult
        )

        _ = await subject.publish(
            package: package, title: "t", description: "", priceShards: 0, session: session()
        )

        #expect(backend.sawToken)
    }
}

// MARK: - 소스 규칙

@Suite("상점 보안 규칙")
struct MarketplaceSecurityTests {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ggumirrorTests
            .deletingLastPathComponent()   // ggumirror(repo)
            .appending(path: "ggumirror")
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    private var marketplaceSources: [String] {
        [
            "Backend/MarketplaceAPI.swift",
            "Backend/BackendClient+Marketplace.swift",
            "Store/MarketplaceStore.swift",
            "Store/MarketplaceImport.swift",
            "Store/SnapshotPackaging.swift",
            "Store/MarketplaceGallery.swift",
        ]
    }

    @Test("token을 로그하지 않는다")
    func neverLogsTokens() throws {
        for path in marketplaceSources {
            let code = try source(path)
            for line in code.split(separator: "\n") {
                let text = String(line)
                guard text.contains("print(") || text.contains("BackendLog.event") else { continue }
                for banned in ["accessToken", "Authorization", "Bearer", "token)"] {
                    #expect(!text.contains(banned), "token을 로그하는 줄이 있다")
                }
            }
        }
    }

    @Test("manifest 내용이나 이미지 바이트를 로그하지 않는다")
    func neverLogsPayloads() throws {
        for path in marketplaceSources {
            let code = try source(path)
            for line in code.split(separator: "\n") {
                let text = String(line)
                guard text.contains("print(") || text.contains("BackendLog.event") else { continue }
                for banned in ["manifest", "preview", "assets", "base64"] {
                    #expect(!text.contains(banned), "본문을 로그하는 줄이 있다")
                }
            }
        }
    }

    @Test("token을 UserDefaults에 넣지 않는다")
    func neverPersistsTokenOutsideKeychain() throws {
        for path in marketplaceSources {
            let code = try source(path)
            #expect(!code.contains("UserDefaults"), "\(path)에 UserDefaults가 있다")
            #expect(!code.contains("UIPasteboard"), "\(path)에 UIPasteboard가 있다")
        }
    }

    @Test("signed URL을 만들거나 기대하지 않는다")
    func noSignedURLs() throws {
        for path in marketplaceSources {
            let code = try source(path)
            for banned in ["signedURL", "signed_url", "X-Goog", "storage.googleapis.com", "gs://"] {
                #expect(!code.contains(banned), "\(path): \(banned)")
            }
        }
    }

    @Test("조각 잔액을 앱이 직접 계산하지 않는다")
    func noClientSideShardArithmetic() throws {
        // `apply(balance:)`는 서버가 준 값을 넣는 창구다. 산술이 붙으면 안 된다.
        for path in marketplaceSources {
            let code = try source(path)
            for banned in [
                "apply(balance: wallet.balance",
                "balance -", "balance +",
                "feeInShards)", "- MirrorPublishPolicy", "- StickerPublishPolicy",
            ] {
                #expect(!code.contains(banned), "\(path): \(banned)")
            }
        }
    }

    @Test("generic shard mutation endpoint를 부르지 않는다")
    func noGenericShardMutation() throws {
        for path in marketplaceSources {
            let code = try source(path)
            for banned in ["users/me/shards\", method: \"POST", "shards/adjust", "shards/credit", "shards/debit"] {
                #expect(!code.contains(banned), "\(path): \(banned)")
            }
        }
    }

    @Test("DEBUG에도 token 노출 장치가 없다")
    func noDebugTokenExport() throws {
        for path in marketplaceSources {
            let code = try source(path)
            #expect(!code.contains("#if DEBUG"), "\(path)에 DEBUG 분기가 있다")
        }
    }
}

// MARK: - 지갑 fake

/// 상점 test가 쓰는 최소 지갑 backend. 조각을 실제로 움직이지 않는다.
private struct FakeShardBackendForMarketplace: ShardBackend {
    func shards(accessToken: String) async throws -> ShardBalance {
        ShardBalance(balance: 0, lifetimeEarned: 0, lifetimeSpent: 0)
    }
    func attendance(accessToken: String) async throws -> AttendanceStatus {
        throw BackendError.unavailable
    }
    func claimAttendance(accessToken: String) async throws -> AttendanceClaim {
        throw BackendError.unavailable
    }
    func rewardedAds(accessToken: String) async throws -> RewardedAdStatus {
        throw BackendError.unavailable
    }
    func rewardedAdContext(accessToken: String) async throws -> String {
        throw BackendError.unavailable
    }
}


// MARK: - 판매자 자기 목록 (B-7G.1)
//
// 서버가 authority다. 앱이 기억해 둔 listing id는 힌트일 뿐이라 앱을 지웠거나
// 기기를 바꾸면 사라진다 — 그때도 자기 상품을 내릴 수 있어야 한다.

private func owned(
    id: String,
    contentType: String = "mirror",
    status: String,
    price: Int = 10,
    downloads: Int = 0,
    likes: Int = 0,
    publishedAt: Date? = Date(timeIntervalSince1970: 1_000)
) -> MarketplaceOwnedListing {
    MarketplaceOwnedListing(
        id: id, contentType: contentType, title: "내 상품 \(id)", description: "설명",
        priceShards: price, status: status,
        downloadCount: downloads, likeCount: likes, publishedAt: publishedAt
    )
}

@Suite("판매자 목록 DTO")
struct MyListingsDTOTests {

    @Test("서버 wire format 그대로 읽는다")
    func decodesMyListings() throws {
        let json = """
        [{"id":"a","contentType":"mirror","title":"내 거울","description":"",
          "priceShards":30,"status":"draft","downloadCount":0,"likeCount":0,
          "publishedAt":null},
         {"id":"b","contentType":"sticker","title":"내 스티커","description":"",
          "priceShards":0,"status":"unlisted","downloadCount":3,"likeCount":1,
          "publishedAt":"2026-08-19T10:00:12Z"}]
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.backend.decode([MarketplaceOwnedListing].self, from: json)

        #expect(decoded.count == 2)
        #expect(decoded[0].status == "draft")
        #expect(decoded[0].publishedAt == nil)
        #expect(decoded[1].status == "unlisted")
        #expect(decoded[1].publishedAt != nil)
    }

    @Test("세 상태를 구분한다")
    func mapsThreeStates() {
        #expect(owned(id: "a", status: "draft").isDraft)
        #expect(owned(id: "a", status: "published").isPublished)
        #expect(owned(id: "a", status: "unlisted").isUnlisted)
        // 서로 배타적이다.
        #expect(!owned(id: "a", status: "draft").isPublished)
        #expect(!owned(id: "a", status: "unlisted").isPublished)
    }

    @Test("모르는 상태에서도 목록이 깨지지 않는다")
    func unknownStatusIsTolerated() throws {
        let json = """
        [{"id":"a","contentType":"mirror","title":"t","description":"","priceShards":0,
          "status":"archived","downloadCount":0,"likeCount":0,"publishedAt":null}]
        """.data(using: .utf8)!

        // 열거형으로 decode하면 여기서 던져 목록이 통째로 빈다.
        let decoded = try JSONDecoder.backend.decode([MarketplaceOwnedListing].self, from: json)

        #expect(decoded.count == 1)
        #expect(decoded[0].statusLabel == "알 수 없음")
        #expect(!decoded[0].isPublished)
        #expect(!decoded[0].isDraft)
        #expect(!decoded[0].isUnlisted)
    }

    @Test("상태 이름이 한국어로 나온다")
    func statusLabels() {
        // "공개 중" → "판매 중"으로 바꿨다. 상점 IA가 `판매 중` / `등록 미완료`로
        // 나뉘므로 카드 문구도 같은 말을 써야 한다.
        #expect(owned(id: "a", status: "published").statusLabel == "판매 중")
        #expect(owned(id: "a", status: "unlisted").statusLabel == "판매 중지")
        // "등록 준비"는 등록 도중 실패해 남은 draft에도 붙어서 사용자가 자기가
        // 안 올린 줄 알았다. 두 경우 모두 맞는 문구로 바꿨다.
        #expect(owned(id: "a", status: "draft").statusLabel == "등록 미완료")
        #expect(owned(id: "a", status: "deleted", publishedAt: nil).statusLabel == "삭제됨")
    }
}

@MainActor
@Suite("판매자 목록 authority")
struct MyListingsStoreTests {

    private func store(_ backend: FakeMarketplaceBackend) -> MarketplaceStore {
        MarketplaceStore(backend: backend)
    }

    @Test("로그인했으면 서버에서 받아온다")
    func fetchesWhenSignedIn() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [
            owned(id: "a", status: "draft", publishedAt: nil),
            owned(id: "b", status: "published"),
            owned(id: "c", status: "unlisted"),
        ]
        let subject = store(backend)

        await subject.refreshMyListings(session: session())

        #expect(subject.myListings.map(\.id) == ["a", "b", "c"])
        #expect(backend.sawToken)
    }

    @Test("로그인하지 않았으면 비운다 — 이전 사용자 목록이 남지 않는다")
    func clearsWhenSignedOut() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [owned(id: "a", status: "published")]
        let subject = store(backend)
        await subject.refreshMyListings(session: session())
        #expect(!subject.myListings.isEmpty)

        await subject.refreshMyListings(session: nil)

        #expect(subject.myListings.isEmpty)
        // 서버를 부르지도 않는다.
        #expect(backend.calls.filter { $0 == "myListings" }.count == 1)
    }

    @Test("올린 것이 없으면 빈 목록이다")
    func emptyStaysEmpty() async {
        let backend = FakeMarketplaceBackend()
        let subject = store(backend)

        await subject.refreshMyListings(session: session())

        #expect(subject.myListings.isEmpty)
    }

    @Test("id로 서버 상태를 찾는다")
    func findsByID() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [owned(id: "a", status: "unlisted")]
        let subject = store(backend)
        await subject.refreshMyListings(session: session())

        #expect(subject.myListing(id: "a")?.isUnlisted == true)
    }

    @Test("서버에 없는 id를 '있다'고 하지 않는다")
    func missingIDIsNil() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [owned(id: "a", status: "published")]
        let subject = store(backend)
        await subject.refreshMyListings(session: session())

        // 앱이 기억해 둔 id가 다른 계정 것이거나 서버에서 사라졌을 수 있다.
        #expect(subject.myListing(id: "stale") == nil)
    }

    @Test("다른 판매자 상품은 내 목록에 들어오지 않는다")
    func onlyServerResultBecomesMine() async {
        let backend = FakeMarketplaceBackend()
        // 서버가 준 것만 들어온다. 공개 목록에 남의 상품이 있어도 섞이지 않는다.
        backend.listingsResult = [listing(id: "theirs")]
        backend.myListingsResult = [owned(id: "mine", status: "published")]
        let subject = store(backend)

        await subject.refresh(contentType: "mirror", sort: .latest, session: session())
        await subject.refreshMyListings(session: session())

        #expect(subject.myListings.map(\.id) == ["mine"])
        #expect(!subject.myListings.contains { $0.id == "theirs" })
    }

    @Test("등록 성공 후 판매자 목록을 다시 받는다")
    func publishRefreshesMyListings() async {
        let backend = FakeMarketplaceBackend()
        backend.publishResult = MarketplacePublishResult(
            published: true, feeCharged: true, feeShards: 10, balance: 90,
            listing: owned(id: "listing-1", status: "published")
        )
        backend.myListingsResult = [owned(id: "listing-1", status: "published")]
        let subject = store(backend)
        let package = SnapshotPackage(
            manifest: Data("{}".utf8), preview: Data([0x89]), assets: [:], contentType: "mirror"
        )

        _ = await subject.publish(
            package: package, title: "t", description: "", priceShards: 0, session: session()
        )

        #expect(backend.calls.contains("myListings"))
        #expect(subject.myListings.map(\.id) == ["listing-1"])
    }

    @Test("내린 뒤 판매자 목록과 공개 목록을 모두 갱신한다")
    func unpublishRefreshesBoth() async {
        let backend = FakeMarketplaceBackend()
        backend.listingsResult = [listing(id: "a")]
        backend.myListingsResult = [owned(id: "a", status: "published")]
        let subject = store(backend)
        await subject.refresh(contentType: "mirror", sort: .latest, session: session())

        // 내리면 서버는 unlisted를 준다.
        backend.myListingsResult = [owned(id: "a", status: "unlisted")]
        _ = await subject.unpublish(listingID: "a", session: session())

        // 공개 목록에서 사라진다.
        #expect(subject.listings.isEmpty)
        // 판매자 목록에는 남고 상태가 바뀐다.
        #expect(subject.myListing(id: "a")?.isUnlisted == true)
    }

    @Test("다시 올린 뒤에도 판매자 목록을 갱신한다")
    func republishRefreshesMyListings() async {
        let backend = FakeMarketplaceBackend()
        backend.publishResult = MarketplacePublishResult(
            published: true, feeCharged: false, feeShards: 10, balance: 90,
            listing: owned(id: "a", status: "published")
        )
        backend.myListingsResult = [owned(id: "a", status: "published")]
        let subject = store(backend)

        let result = await subject.republish(listingID: "a", session: session())

        // 추가 등록비 없음 — 서버가 알려 준다.
        #expect(result?.feeCharged == false)
        #expect(backend.calls.contains("myListings"))
        #expect(subject.myListing(id: "a")?.isPublished == true)
    }

    @Test("local id가 없어도 서버 목록으로 관리할 수 있다")
    func managementWorksWithoutLocalID() async {
        let backend = FakeMarketplaceBackend()
        // 앱은 이 상품의 id를 기억하고 있지 않다(앱 재설치 · 기기 변경).
        backend.myListingsResult = [
            owned(id: "forgotten", status: "published"),
            owned(id: "forgotten-2", status: "unlisted"),
        ]
        let subject = store(backend)

        await subject.refreshMyListings(session: session())

        // 서버 목록만으로 내릴/올릴 대상을 전부 찾을 수 있다.
        #expect(subject.myListings.count == 2)
        #expect(subject.myListings.filter(\.isPublished).map(\.id) == ["forgotten"])
        #expect(subject.myListings.filter(\.isUnlisted).map(\.id) == ["forgotten-2"])
    }

    @Test("판매자 목록 조회는 조각을 움직이지 않는다")
    func fetchDoesNotTouchShards() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [owned(id: "a", status: "published")]
        let subject = store(backend)
        let wallet = ShardWallet(backend: FakeShardBackendForMarketplace())
        wallet.apply(balance: 100)

        await subject.refreshMyListings(session: session())

        #expect(wallet.balance == 100)
    }

    @Test("실패를 성공처럼 삼키지 않는다")
    func surfacesFailure() async {
        let backend = FakeMarketplaceBackend()
        backend.failure = .notSignedIn
        let subject = store(backend)

        await subject.refreshMyListings(session: session())

        #expect(subject.failure == .notSignedIn)
    }
}

@Suite("판매자 목록 규칙")
struct MyListingsRuleTests {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "ggumirror")
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    @Test("userId를 요청에 싣지 않는다 — 서버가 session으로 판단한다")
    func neverSendsUserID() throws {
        let code = try source("Backend/BackendClient+Marketplace.swift")
        let body = code[code.range(of: "func myListings")!.lowerBound...]
        let method = String(body.prefix(400))
        assert(method.contains("users/me/marketplace/listings"))
        #expect(!method.contains("userID"))
        #expect(!method.contains("userId"))
        #expect(!method.contains("sellerUserId"))
    }

    @Test("관리 기능이 local listingID에만 의존하지 않는다")
    func managementDoesNotDependOnLocalIDOnly() throws {
        // 관리 구획은 서버 목록만 읽는다 — **로컬 draft를 아예 모른다.**
        //
        // `listingID:`는 `store.unpublish(listingID:)`의 인자 이름이라 나온다.
        // 그건 의존이 아니므로 **읽는 자리**만 본다.
        let section = try source("Store/MyListingsSection.swift")
        #expect(section.contains("store.myListings"))
        for banned in ["draft.listingID", "PublishDraft", "publishDraft", "savePublishDraft"] {
            #expect(!section.contains(banned), "로컬 draft에 의존한다")
        }
    }

    @Test("등록 시트도 서버 상태를 확인한 뒤에만 관리 UI를 낸다")
    func publishSheetsResolveThroughTheServer() throws {
        for path in ["Store/PublishMirrorView.swift", "Store/PublishStickerView.swift"] {
            let code = try source(path)
            // 힌트 id를 서버 목록으로 조회한다.
            #expect(code.contains("marketplace.myListing(id:"), "서버 조회가 없다")
            // 서버 상태로 버튼을 정한다.
            #expect(code.contains("listing.isPublished"), "서버 상태를 안 본다")
            #expect(code.contains("listing.isUnlisted"), "서버 상태를 안 본다")
        }
    }

    @Test("판매자 목록 파일에도 token 노출이 없다")
    func noTokenExposure() throws {
        let section = try source("Store/MyListingsSection.swift")
        for banned in ["accessToken", "UIPasteboard", "UserDefaults", "#if DEBUG", "print("] {
            #expect(!section.contains(banned), "\(banned)가 있다")
        }
    }
}


// MARK: - 실제 URL 구성 (B-7H에서 발견한 버그)
//
// fake backend는 URL을 만들지 않는다. 그래서 B-7G test 146개가 모두 통과하는 동안
// **production에서는 per-listing endpoint 전부가 404였다** —
// `-`를 미리 percent-encoding해서 `appending(path:)`가 그것을 다시 인코딩했고
// `698fee25%252D862e…`가 나갔다.
//
// 여기서는 실제 `BackendClient`를 `StubURLProtocol`로 돌려 **나가는 경로를 본다.**

@Suite(.serialized)
struct MarketplaceURLTests {

    private func client(status: Int = 200, json: String = "{}") -> BackendClient {
        let session = StubURLProtocol.session()
        StubURLProtocol.next = .init(status: status, body: Data(json.utf8))
        return BackendClient(baseURL: URL(string: "https://backend.test")!, session: session)
    }

    private let listingID = "698fee25-862e-4e08-be7a-d8a213ff7c84"

    @Test("listing id의 하이픈을 이중 인코딩하지 않는다")
    func doesNotDoubleEncodeHyphens() async throws {
        let subject = client(status: 200, json: publishJSON)

        _ = try? await subject.publish(listingID: listingID, accessToken: "t")

        let path = try #require(StubURLProtocol.requestedPaths.last)
        #expect(path == "/marketplace/listings/\(listingID)/publish")
        // 이중 인코딩의 흔적이 없어야 한다.
        #expect(!path.contains("%252D"))
        #expect(!path.contains("%2D"))
        #expect(!path.contains("%25"))
    }

    @Test("per-listing endpoint 전부가 원본 id를 그대로 보낸다")
    func everyListingPathKeepsTheRawID() async throws {
        let cases: [(String, (BackendClient) async throws -> Void)] = [
            ("preview", { _ = try await $0.preview(listingID: self.listingID) }),
            ("publish", { _ = try await $0.publish(listingID: self.listingID, accessToken: "t") }),
            ("unpublish", { _ = try await $0.unpublish(listingID: self.listingID, accessToken: "t") }),
            ("purchase", { _ = try await $0.purchase(listingID: self.listingID, accessToken: "t") }),
            ("like", { _ = try await $0.like(listingID: self.listingID, accessToken: "t") }),
            ("unlike", { _ = try await $0.unlike(listingID: self.listingID, accessToken: "t") }),
            ("template", { _ = try await $0.templateManifest(listingID: self.listingID, accessToken: "t") }),
            ("asset", {
                _ = try await $0.templateAsset(
                    listingID: self.listingID,
                    assetID: UUID(uuidString: "30204745-4090-457B-BB4E-4A4AD61C4827")!,
                    accessToken: "t"
                )
            }),
        ]

        for (name, call) in cases {
            let subject = client(status: 200, json: publishJSON)
            _ = try? await call(subject)
            let path = try #require(StubURLProtocol.requestedPaths.last, "\(name): 요청이 없다")
            #expect(path.contains(listingID), "\(name): id가 변형됐다 — \(path)")
            #expect(!path.contains("%"), "\(name): 인코딩이 섞였다 — \(path)")
        }
    }

    @Test("asset UUID도 그대로 나간다")
    func assetUUIDIsNotEncoded() async throws {
        let asset = UUID(uuidString: "30204745-4090-457B-BB4E-4A4AD61C4827")!
        let subject = client()

        _ = try? await subject.templateAsset(
            listingID: listingID, assetID: asset, accessToken: "t"
        )

        let path = try #require(StubURLProtocol.requestedPaths.last)
        #expect(path.hasSuffix("/template/assets/\(asset.uuidString)"))
    }

    @Test("query가 path에 섞이지 않는다")
    func browseQueryIsRealQuery() async throws {
        let subject = client(status: 200, json: "[]")

        _ = try? await subject.listings(contentType: "mirror", sort: "latest")

        let path = try #require(StubURLProtocol.requestedPaths.last)
        let query = try #require(StubURLProtocol.requestedQueries.last)

        // path에는 query가 없다. `?`를 path 문자열에 넣으면 `%3F`가 되어 여기 섞인다.
        #expect(path == "/marketplace/listings")
        #expect(!path.contains("%3F"))
        #expect(!path.contains("sort"))
        // query로 제대로 나간다.
        #expect(query.contains("sort=latest"))
        #expect(query.contains("contentType=mirror"))
    }

    @Test("contentType이 없으면 sort만 붙는다")
    func browseWithoutContentType() async throws {
        let subject = client(status: 200, json: "[]")

        _ = try? await subject.listings(contentType: nil, sort: "popular")

        #expect(StubURLProtocol.requestedPaths.last == "/marketplace/listings")
        let query = try #require(StubURLProtocol.requestedQueries.last)
        #expect(query == "sort=popular")
    }

    @Test("판매자 목록 경로에 id가 들어가지 않는다 — 서버가 session으로 판단한다")
    func myListingsPath() async throws {
        let subject = client(status: 200, json: "[]")

        _ = try? await subject.myListings(accessToken: "t")

        #expect(StubURLProtocol.requestedPaths.last == "/users/me/marketplace/listings")
    }

    @Test("경로를 벗어나는 id로는 요청을 만들지 않는다")
    func pathTraversalIsRefused() async throws {
        for poison in ["../../admin", "a/b", "", "..", "."] {
            let subject = client()
            var refused = false
            do {
                _ = try await subject.publish(listingID: poison, accessToken: "t")
            } catch let failure as MarketplaceFailure {
                refused = failure == .notFound
            } catch {
                refused = false
            }
            #expect(refused, "거절되지 않았다: \(poison)")
            // 네트워크로 나가지도 않는다.
            #expect(StubURLProtocol.requestedPaths.isEmpty, "요청이 나갔다: \(poison)")
        }
    }

    @Test("snapshot 업로드는 multipart로 나간다")
    func snapshotUsesMultipart() async throws {
        let subject = client(status: 201, json: snapshotJSON)

        _ = try? await subject.createSnapshot(
            contentType: "mirror",
            manifest: Data("{}".utf8),
            preview: Data([0x89]),
            assets: [:],
            accessToken: "t"
        )

        #expect(StubURLProtocol.requestedPaths.last == "/marketplace/snapshots")
    }

    private var publishJSON: String {
        """
        {"published":true,"feeCharged":true,"feeShards":10,"balance":142,
         "listing":{"id":"698fee25-862e-4e08-be7a-d8a213ff7c84","contentType":"mirror",
         "title":"t","description":"","priceShards":1,"status":"published",
         "downloadCount":0,"likeCount":0,"publishedAt":"2026-08-19T14:33:27Z"}}
        """
    }

    private var snapshotJSON: String {
        """
        {"snapshotId":"1d0553c5-d530-45e1-ad8f-83a98154b8e8","contentType":"mirror",
         "assetCount":0,"totalBytes":2,"manifestChecksum":"abc"}
        """
    }
}


// MARK: - 상점 scroll 계층 (B-7H UI hotfix)
//
// 상단 제어부(제목 · 잔액 · 거울/스티커 · 갈래 · 꼬리표 · 정렬)가 고정돼 있어서
// 실제 상품이 보이는 세로 공간이 너무 좁았다. 전부 상품과 같은 scroll content로
// 옮겼고, 여기서 그 계층을 고정한다.
//
// **디자인은 바꾸지 않았다** — scroll 구조만 옮겼다.

@Suite("상점 scroll 계층")
struct StoreScrollHierarchyTests {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "ggumirror")
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    /// 주석을 걷어낸 코드. 설명에 적은 단어를 잡지 않는다.
    private func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    @Test("상점 화면의 세로 scroll은 하나뿐이다")
    func exactlyOneScrollView() throws {
        let store = codeOnly(try source("Store/StoreView.swift"))
        #expect(store.components(separatedBy: "ScrollView {").count - 1 == 1)

        // 안쪽 화면이 또 감싸면 중첩되고 상단이 따라 올라가지 않는다.
        let sticker = codeOnly(try source("Store/StickerStoreView.swift"))
        #expect(!sticker.contains("ScrollView {"), "스티커 상점이 자기 scroll을 갖는다")
    }

    @Test("상단 제어부가 scroll content 안에 있다")
    func controlsScrollWithContent() throws {
        let code = codeOnly(try source("Store/StoreView.swift"))
        let body = try #require(code.range(of: "var body: some View {"))
        let scroll = try #require(code.range(of: "ScrollView {"))
        // scroll이 body 안에서 시작한다.
        #expect(scroll.lowerBound > body.lowerBound)

        // header · sectionSwitch · filters가 scroll보다 뒤에 온다(= 안에 있다).
        for element in ["header", "sectionSwitch", "filters"] {
            let use = try #require(
                code.range(of: element, range: scroll.upperBound..<code.endIndex),
                "\(element)가 scroll 안에 없다"
            )
            #expect(use.lowerBound > scroll.lowerBound)
        }
    }

    @Test("상품 부분은 자기 scroll을 갖지 않는다")
    func productContentHasNoOwnScroll() throws {
        let code = codeOnly(try source("Store/StoreView.swift"))
        let start = try #require(code.range(of: "private var mirrorContent: some View {"))
        let body = String(code[start.upperBound...].prefix(1200))
        #expect(!body.contains("ScrollView"), "상품 부분이 또 감싼다")
    }

    @Test("UI-P2의 tab bar 여백이 유지된다")
    func tabBarClearanceSurvives() throws {
        let code = try source("Store/StoreView.swift")
        #expect(code.contains("InkTabBar.reservedHeight"))
        #expect(code.contains("contentMargins(.bottom"))
        #expect(code.contains("for: .scrollContent"))
        // scroll이 하나이므로 여백도 한 곳에서만 준다.
        #expect(code.components(separatedBy: "contentMargins(.bottom").count - 1 == 1)
    }

    @Test("공개 거울 탭은 사용자 상품 → 내장 목록 순서다")
    func publicMirrorOrder() throws {
        // **판매자 관리는 여기 없다** — `내 판매` 탭으로 갔다(Marketplace UX hardening).
        // 공개 목록에 draft가 섞이면 무엇이 실제로 팔리는지 알 수 없었다.
        let code = codeOnly(try source("Store/StoreView.swift"))
        let start = try #require(code.range(of: "private var mirrorContent: some View {"))
        let body = String(code[start.upperBound...])

        #expect(!body.contains("MyListingsSection"), "공개 목록에 판매자 관리가 섞였다")

        let others = try #require(body.range(of: "MarketplaceSection"))
        let builtIn = try #require(body.range(of: "LazyVGrid"))
        #expect(others.lowerBound < builtIn.lowerBound, "사용자 상품이 내장 목록보다 뒤에 있다")
    }

    @Test("제어부 순서가 요구대로다")
    func controlOrder() throws {
        let code = codeOnly(try source("Store/StoreView.swift"))
        let body = try #require(code.range(of: "var body: some View {"))
        let region = String(code[body.upperBound...].prefix(1600))

        let order = ["header", "sectionSwitch", "filters", "mirrorContent"]
        var previous = region.startIndex
        for element in order {
            let found = try #require(
                region.range(of: element, range: previous..<region.endIndex),
                "\(element)가 순서에 없다"
            )
            previous = found.upperBound
        }
    }

    @Test("갈래 · 꼬리표 · 정렬이 한 묶음으로 함께 스크롤된다")
    func filtersAreOneGroup() throws {
        let code = codeOnly(try source("Store/StoreView.swift"))
        let start = try #require(code.range(of: "private var filters: some View {"))
        let body = String(code[start.upperBound...].prefix(600))
        #expect(body.contains("StorePriceFilter.allCases"))
        #expect(body.contains("StoreSort.allCases"))
    }

    @Test("판매자 목록 authority는 계속 서버다")
    func serverStaysTheAuthority() throws {
        let section = try source("Store/MyListingsSection.swift")
        #expect(section.contains("store.myListings"))
        // 로컬 draft로 되돌아가지 않았다.
        for banned in ["draft.listingID", "PublishDraft", "savePublishDraft"] {
            #expect(!section.contains(banned), "로컬 draft에 의존한다")
        }
        // 세 상태 전부 여기서 다룬다.
        for state in ["isPublished", "isUnlisted", "isDraft"] {
            #expect(section.contains(state), "\(state)를 다루지 않는다")
        }
    }

    @Test("디자인 토큰을 바꾸지 않았다")
    func designUnchanged() throws {
        let code = try source("Store/StoreView.swift")
        // 기존 Clean Pen Sketch 요소가 그대로다.
        for token in ["InkFont.pageTitle", "PaperTheme.ink", "UnevenRoundedRectangle.ink",
                      "InkPressStyle()", "InkFilterBar"] {
            #expect(code.contains(token), "\(token)이 사라졌다")
        }
        // 새 디자인 시스템을 들이지 않았다.
        for banned in [".background(Color.", "LinearGradient", "Material.", ".ultraThinMaterial"] {
            #expect(!code.contains(banned), "새 디자인 요소가 들어왔다: \(banned)")
        }
    }
}


// MARK: - 등록 복구 (B-7H hotfix)
//
// production에서 실제로 일어난 것: snapshot과 listing은 만들어졌고 publish만 404였다.
// 앱이 listing id를 들고 있지 않아서 다시 시도할 때 snapshot과 listing을 **또** 만들었고
// 같은 콘텐츠가 두 건, GCS object는 두 배가 됐다. 실패가 반복되면 계속 쌓인다.
//
// 여기서 보는 것: 재시도가 **publish만** 보내는가.

@MainActor
@Suite("등록 복구")
struct PublishRecoveryTests {

    private func store(_ backend: FakeMarketplaceBackend) -> MarketplaceStore {
        MarketplaceStore(backend: backend)
    }

    private var package: SnapshotPackage {
        SnapshotPackage(
            manifest: Data("{}".utf8), preview: Data([0x89]), assets: [:], contentType: "mirror"
        )
    }

    private func publishResult(
        fee: Bool, balance: Int = 90, status: String = "published"
    ) -> MarketplacePublishResult {
        MarketplacePublishResult(
            published: true, feeCharged: fee, feeShards: 10, balance: balance,
            listing: owned(id: "listing-1", status: status)
        )
    }

    // MARK: 정상

    @Test("정상 등록은 snapshot → listing → publish 순서다")
    func happyPath() async {
        let backend = FakeMarketplaceBackend()
        backend.publishResult = publishResult(fee: true)
        let subject = store(backend)

        let result = await subject.publish(
            package: package, title: "t", description: "", priceShards: 1, session: session()
        )

        #expect(result?.feeCharged == true)
        let order = backend.calls.filter { !$0.hasPrefix("myListings") }
        #expect(order == ["createSnapshot(mirror)", "createDraft(1)", "publish(listing-1)"])
    }

    // MARK: publish 실패

    @Test("publish가 실패해도 listing id는 저장된다")
    func idIsPersistedBeforePublish() async {
        let backend = FakeMarketplaceBackend()
        // publishResult가 nil이면 fake가 cannotPublish를 던진다.
        let subject = store(backend)
        var persisted: String?
        subject.onListingCreated = { persisted = $0; return true }

        let result = await subject.publish(
            package: package, title: "t", description: "", priceShards: 1, session: session()
        )

        #expect(result == nil)
        // **가장 중요** — 실패했지만 id는 남았다.
        #expect(persisted == "listing-1")
    }

    @Test("저장이 실패하면 publish를 보내지 않는다")
    func noPublishWhenPersistenceFails() async {
        let backend = FakeMarketplaceBackend()
        backend.publishResult = publishResult(fee: true)
        let subject = store(backend)
        subject.onListingCreated = { _ in false }   // 저장 실패

        let result = await subject.publish(
            package: package, title: "t", description: "", priceShards: 1, session: session()
        )

        #expect(result == nil)
        // 못 찾는 listing을 만들지 않는다 — publish를 아예 보내지 않았다.
        #expect(!backend.calls.contains { $0.hasPrefix("publish(") })
    }

    @Test("publish 실패 후에도 판매자 목록을 새로 받는다")
    func failureStillRefreshesMyListings() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [owned(id: "listing-1", status: "draft", publishedAt: nil)]
        let subject = store(backend)

        _ = await subject.publish(
            package: package, title: "t", description: "", priceShards: 1, session: session()
        )

        // 서버에 남은 draft가 "등록 미완료"로 보여야 이어서 올릴 수 있다.
        #expect(backend.calls.contains("myListings"))
        #expect(subject.myListing(id: "listing-1")?.isDraft == true)
    }

    // MARK: 재시도

    @Test("draft 재시도는 publish만 보낸다 — snapshot도 listing도 새로 만들지 않는다")
    func draftRetryPublishesOnly() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [owned(id: "listing-1", status: "draft", publishedAt: nil)]
        backend.publishResult = publishResult(fee: true)
        let subject = store(backend)

        let outcome = await subject.resumePublish(listingID: "listing-1", session: session())

        guard case .published(let result) = outcome else {
            #expect(Bool(false), "published가 아니다: \(outcome)")
            return
        }
        #expect(result.feeCharged == true)
        // **핵심** — 새로 만든 것이 없다.
        #expect(!backend.calls.contains("createSnapshot(mirror)"))
        #expect(!backend.calls.contains { $0.hasPrefix("createDraft") })
        #expect(backend.calls.filter { $0 == "publish(listing-1)" }.count == 1)
    }

    @Test("이미 published면 아무 요청도 더 보내지 않는다")
    func publishedRetryIsANoOp() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [owned(id: "listing-1", status: "published")]
        let subject = store(backend)

        let outcome = await subject.resumePublish(listingID: "listing-1", session: session())

        guard case .alreadyPublished = outcome else {
            #expect(Bool(false), "alreadyPublished가 아니다: \(outcome)")
            return
        }
        #expect(!backend.calls.contains { $0.hasPrefix("publish(") })
        #expect(!backend.calls.contains("createSnapshot(mirror)"))
        #expect(!backend.calls.contains { $0.hasPrefix("createDraft") })
    }

    @Test("unlisted 재시도는 다시 올리기이고 추가 등록비가 없다")
    func unlistedRetryRepublishes() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [owned(id: "listing-1", status: "unlisted")]
        backend.publishResult = publishResult(fee: false)
        let subject = store(backend)

        let outcome = await subject.resumePublish(listingID: "listing-1", session: session())

        guard case .published(let result) = outcome else {
            #expect(Bool(false), "published가 아니다: \(outcome)")
            return
        }
        // 서버가 추가 등록비 없음을 알려 준다.
        #expect(result.feeCharged == false)
        #expect(!backend.calls.contains("createSnapshot(mirror)"))
        #expect(!backend.calls.contains { $0.hasPrefix("createDraft") })
    }

    @Test("서버에 없는 id는 낡은 기억으로 다룬다")
    func staleCacheIsReported() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = []
        let subject = store(backend)

        let outcome = await subject.resumePublish(listingID: "gone", session: session())

        guard case .missing = outcome else {
            #expect(Bool(false), "missing이 아니다: \(outcome)")
            return
        }
        // 없다고 해서 몰래 새로 만들지 않는다 — 호출부가 결정한다.
        #expect(!backend.calls.contains("createSnapshot(mirror)"))
    }

    @Test("로그인하지 않으면 서버를 부르지 않는다")
    func resumeNeedsSignIn() async {
        let backend = FakeMarketplaceBackend()
        let subject = store(backend)

        let outcome = await subject.resumePublish(listingID: "listing-1", session: nil)

        guard case .needsSignIn = outcome else {
            #expect(Bool(false), "needsSignIn이 아니다: \(outcome)")
            return
        }
        #expect(backend.calls.isEmpty)
    }

    @Test("제목이 같은 두 listing을 제목으로 맞추지 않는다")
    func neverMatchesByTitle() async {
        let backend = FakeMarketplaceBackend()
        // production 그대로 — 같은 제목의 draft와 published가 함께 있다.
        backend.myListingsResult = [
            MarketplaceOwnedListing(
                id: "old-draft", contentType: "mirror", title: "테스트", description: "",
                priceShards: 1, status: "draft", downloadCount: 0, likeCount: 0, publishedAt: nil
            ),
            MarketplaceOwnedListing(
                id: "new-live", contentType: "mirror", title: "테스트", description: "",
                priceShards: 1, status: "published", downloadCount: 0, likeCount: 0,
                publishedAt: Date(timeIntervalSince1970: 1_000)
            ),
        ]
        let subject = store(backend)
        await subject.refreshMyListings(session: session())

        // id로만 찾는다. 제목이 같아도 서로 섞이지 않는다.
        #expect(subject.myListing(id: "old-draft")?.isDraft == true)
        #expect(subject.myListing(id: "new-live")?.isPublished == true)
    }

    @Test("복구가 조각을 직접 건드리지 않는다")
    func recoveryNeverTouchesShardsDirectly() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [owned(id: "listing-1", status: "draft", publishedAt: nil)]
        backend.publishResult = publishResult(fee: true, balance: 132)
        let subject = store(backend)
        let wallet = ShardWallet(backend: FakeShardBackendForMarketplace())
        wallet.apply(balance: 142)

        _ = await subject.resumePublish(listingID: "listing-1", session: session(), wallet: wallet)

        // 서버가 말해 준 값 그대로다. 142 - 10을 앱이 계산한 것이 아니다.
        #expect(wallet.balance == 132)
    }
}

// MARK: - 판매자 미리보기 (B-7H hotfix)

@MainActor
@Suite("판매자 미리보기")
struct SellerPreviewTests {

    private func store(_ backend: FakeMarketplaceBackend) -> MarketplaceStore {
        MarketplaceStore(backend: backend)
    }

    @Test("draft · published · unlisted 모두 미리보기를 받는다")
    func loadsEveryState() async {
        for state in ["draft", "published", "unlisted"] {
            let backend = FakeMarketplaceBackend()
            backend.myPreviewResult = Data([0x89, 0x50, 0x4E, 0x47])
            backend.myListingsResult = [
                owned(id: "a", status: state, publishedAt: state == "draft" ? nil : Date())
            ]
            let subject = store(backend)

            await subject.loadMyPreview("a", session: session())

            #expect(subject.myPreviews["a"] == Data([0x89, 0x50, 0x4E, 0x47]), "\(state) 상태에서 미리보기가 없다")
            #expect(backend.calls.contains("myListingPreview(a)"), "\(state) 상태에서 요청이 없다")
        }
    }

    @Test("판매자 전용 endpoint를 쓴다 — 공개 미리보기가 아니다")
    func usesTheSellerEndpoint() async {
        let backend = FakeMarketplaceBackend()
        backend.myPreviewResult = Data([0x89])
        let subject = store(backend)

        await subject.loadMyPreview("a", session: session())

        #expect(backend.calls.contains("myListingPreview(a)"))
        // 공개 미리보기를 부르지 않는다(그건 published만 준다).
        #expect(!backend.calls.contains("preview(a)"))
    }

    @Test("같은 상품에 요청을 겹치지 않는다")
    func loadsOnce() async {
        let backend = FakeMarketplaceBackend()
        backend.myPreviewResult = Data([0x89])
        let subject = store(backend)

        await subject.loadMyPreview("a", session: session())
        await subject.loadMyPreview("a", session: session())

        #expect(backend.calls.filter { $0 == "myListingPreview(a)" }.count == 1)
    }

    @Test("로그인하지 않으면 부르지 않는다")
    func needsSignIn() async {
        let backend = FakeMarketplaceBackend()
        let subject = store(backend)

        await subject.loadMyPreview("a", session: nil)

        #expect(backend.calls.isEmpty)
        #expect(subject.myPreviews.isEmpty)
    }

    @Test("실패는 실패로 남는다 — 가짜 그림을 만들지 않는다")
    func failureIsRecorded() async {
        let backend = FakeMarketplaceBackend()
        backend.failure = .notFound
        let subject = store(backend)

        await subject.loadMyPreview("a", session: session())

        #expect(subject.myPreviews["a"] == nil)
        #expect(subject.myPreviewFailures.contains("a"))
    }

    @Test("공개 미리보기 캐시와 섞이지 않는다")
    func separateFromPublicCache() async {
        let backend = FakeMarketplaceBackend()
        backend.previewResult = Data([0x01])
        backend.myPreviewResult = Data([0x02])
        let subject = store(backend)

        await subject.loadPreview("a")
        await subject.loadMyPreview("a", session: session())

        #expect(subject.previews["a"] == Data([0x01]))
        #expect(subject.myPreviews["a"] == Data([0x02]))
    }
}

@Suite("판매자 미리보기 UI 규칙")
struct SellerPreviewUITests {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "ggumirror")
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    @Test("카드에 미리보기 renderer가 있다")
    func cardRendersPreview() throws {
        let code = try source("Store/MyListingsSection.swift")
        #expect(code.contains("store.myPreviews[listing.id]"))
        #expect(code.contains("Image(uiImage:"))
        #expect(code.contains("loadMyPreview"))
    }

    @Test("받는 중 · 실패 자리표시자가 구분된다")
    func placeholdersAreDistinct() throws {
        let code = try source("Store/MyListingsSection.swift")
        #expect(code.contains("myPreviewFailures"))
        #expect(code.contains("미리보기를 불러오지 못했어요"))
    }

    @Test("draft 문구가 '등록 미완료'다")
    func draftWording() throws {
        #expect(owned(id: "a", status: "draft").statusLabel == "등록 미완료")
        #expect(owned(id: "a", status: "published").statusLabel == "판매 중")
        #expect(owned(id: "a", status: "unlisted").statusLabel == "판매 중지")
        // 오해를 부르던 옛 문구가 남아 있지 않다.
        #expect(owned(id: "a", status: "draft").statusLabel != "등록 준비")
    }

    @Test("draft CTA가 복구 경로를 쓴다")
    func draftUsesResume() throws {
        let code = try source("Store/MyListingsSection.swift")
        #expect(code.contains("await resume(listing)"))
        #expect(code.contains("store.resumePublish("))
    }

    @Test("등록 시트가 publish 전에 id를 저장한다")
    func sheetsPersistBeforePublish() throws {
        for path in ["Store/PublishMirrorView.swift", "Store/PublishStickerView.swift"] {
            let code = try source(path)
            let hook = try #require(code.range(of: "onListingCreated"), "저장 hook이 없다")
            let publish = try #require(code.range(of: "await marketplace.publish("), "publish가 없다")
            // hook 설정이 publish 호출보다 먼저 온다.
            #expect(hook.lowerBound < publish.lowerBound, "\(path): 저장이 publish보다 뒤다")
        }
    }

    @Test("client가 조각을 직접 계산하지 않는다")
    func noClientSideShardMath() throws {
        for path in ["Store/MyListingsSection.swift", "Store/MarketplaceStore.swift"] {
            let code = try source(path)
            for banned in ["balance -", "balance +", "feeInShards)"] {
                #expect(!code.contains(banned), "\(path): \(banned)")
            }
        }
    }

    @Test("판매자 미리보기에 signed URL이 없다")
    func noSignedURL() throws {
        for path in ["Store/MyListingsSection.swift", "Backend/BackendClient+Marketplace.swift"] {
            let code = try source(path)
            for banned in ["signedURL", "X-Goog", "storage.googleapis.com", "gs://"] {
                #expect(!code.contains(banned), "\(path): \(banned)")
            }
        }
    }
}


// MARK: - 삭제 · 판매 중 연결 · 좋아요 (Marketplace UX hardening)

@MainActor
@Suite("상점 삭제")
struct MarketplaceDeleteTests {

    private func store(_ backend: FakeMarketplaceBackend) -> MarketplaceStore {
        MarketplaceStore(backend: backend)
    }

    @Test("삭제하면 공개 목록에서 사라지고 판매자 목록을 다시 받는다")
    func deleteRemovesAndRefreshes() async {
        let backend = FakeMarketplaceBackend()
        backend.listingsResult = [listing(id: "a")]
        backend.myListingsResult = [owned(id: "a", status: "published")]
        let subject = store(backend)
        await subject.refresh(contentType: "mirror", sort: .latest, session: session())

        backend.myListingsResult = [owned(id: "a", status: "deleted", publishedAt: nil)]
        let result = await subject.delete(listingID: "a", session: session())

        #expect(result?.isDeleted == true)
        #expect(subject.listings.isEmpty)
        #expect(backend.calls.contains("myListings"))
    }

    @Test("삭제는 조각을 건드리지 않는다 — 환불이 없다")
    func deleteTouchesNoShards() async {
        let backend = FakeMarketplaceBackend()
        let subject = store(backend)
        let wallet = ShardWallet(backend: FakeShardBackendForMarketplace())
        wallet.apply(balance: 142)

        _ = await subject.delete(listingID: "a", session: session())

        #expect(wallet.balance == 142)
    }

    @Test("로그인 없이 삭제하면 서버를 부르지 않는다")
    func deleteNeedsSignIn() async {
        let backend = FakeMarketplaceBackend()
        let subject = store(backend)

        let result = await subject.delete(listingID: "a", session: nil)

        #expect(result == nil)
        #expect(subject.failure == .notSignedIn)
        #expect(backend.calls.isEmpty)
    }

    @Test("연타해도 요청은 한 번이다")
    func deleteIsGuardedAgainstDoubleTap() async {
        let backend = FakeMarketplaceBackend()
        backend.slowDelete = true
        let subject = store(backend)

        async let first = subject.delete(listingID: "a", session: session())
        async let second = subject.delete(listingID: "a", session: session())
        _ = await (first, second)

        #expect(backend.calls.filter { $0 == "deleteListing(a)" }.count == 1)
    }

    @Test("deleted는 판매 중 목록에 없다")
    func deletedIsNotSelling() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [
            owned(id: "live", status: "published"),
            owned(id: "gone", status: "deleted", publishedAt: nil),
            owned(id: "wip", status: "draft", publishedAt: nil),
        ]
        let subject = store(backend)
        await subject.refreshMyListings(session: session())

        #expect(subject.selling(contentType: "mirror").map(\.id) == ["live"])
    }

    @Test("삭제 문구가 되살릴 수 있는 것처럼 말하지 않는다")
    func deleteCopyIsFinal() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "ggumirror")
        let code = codeWithoutComments(try String(
            contentsOf: root.appending(path: "Store/MySalesSection.swift"), encoding: .utf8
        ))
        // 새 UI는 "내리기"를 쓰지 않는다.
        #expect(!code.contains("상점에서 내리기"))
        #expect(code.contains("\"삭제\""))
        // 확인 문구에 환불 없음과 기존 구매자 보존이 들어 있다.
        #expect(code.contains("환불되지 않아요"))
        #expect(code.contains("이미 받은 사용자는 계속 사용할 수 있어요"))
        // 등록비 숫자를 화면에 적지 않는다 — 정책 상수를 읽는다.
        #expect(code.contains("publishFeeShards"))
        #expect(!code.contains("10조각은 환불"))
    }

    @Test("등록비 안내가 종류별 정책 상수에서 온다")
    func feeCopyComesFromPolicy() {
        #expect(owned(id: "a", contentType: "mirror", status: "published").publishFeeShards
            == MirrorPublishPolicy.feeInShards)
        #expect(owned(id: "a", contentType: "sticker", status: "published").publishFeeShards
            == StickerPublishPolicy.feeInShards)
    }

    @Test("삭제된 상태 문구")
    func deletedLabel() {
        #expect(owned(id: "a", status: "deleted", publishedAt: nil).statusLabel == "삭제됨")
        #expect(owned(id: "a", status: "published").statusLabel == "판매 중")
    }
}

@MainActor
@Suite("판매 중 연결")
struct SellingMappingTests {

    private func store(_ backend: FakeMarketplaceBackend) -> MarketplaceStore {
        MarketplaceStore(backend: backend)
    }

    private func owned(
        id: String, source: String, status: String = "published"
    ) -> MarketplaceOwnedListing {
        MarketplaceOwnedListing(
            id: id, contentType: "mirror", title: "제목", description: "",
            priceShards: 1, status: status, downloadCount: 0, likeCount: 0,
            publishedAt: status == "draft" ? nil : Date(), sourceContentId: source
        )
    }

    @Test("sourceContentId로 local 거울과 잇는다")
    func mapsBySourceContentID() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [owned(id: "listing-1", source: "art-mint-flower")]
        let subject = store(backend)
        await subject.refreshMyListings(session: session())

        let found = subject.sellingListing(
            forContentID: "art-mint-flower", contentType: "mirror"
        )

        #expect(found?.id == "listing-1")
    }

    @Test("제목으로 맞추지 않는다")
    func neverMatchesByTitle() async {
        let backend = FakeMarketplaceBackend()
        // 제목이 같고 출처가 다른 두 상품.
        backend.myListingsResult = [
            owned(id: "l1", source: "mirror-a"),
            owned(id: "l2", source: "mirror-b"),
        ]
        let subject = store(backend)
        await subject.refreshMyListings(session: session())

        #expect(subject.sellingListing(forContentID: "mirror-a", contentType: "mirror")?.id == "l1")
        #expect(subject.sellingListing(forContentID: "mirror-b", contentType: "mirror")?.id == "l2")
        #expect(subject.sellingListing(forContentID: "제목", contentType: "mirror") == nil)
    }

    @Test("draft는 판매 중이 아니다")
    func draftIsNotSelling() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [owned(id: "l1", source: "mirror-a", status: "draft")]
        let subject = store(backend)
        await subject.refreshMyListings(session: session())

        #expect(subject.sellingListing(forContentID: "mirror-a", contentType: "mirror") == nil)
    }

    @Test("deleted도 판매 중이 아니다")
    func deletedIsNotSelling() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [owned(id: "l1", source: "mirror-a", status: "deleted")]
        let subject = store(backend)
        await subject.refreshMyListings(session: session())

        #expect(subject.sellingListing(forContentID: "mirror-a", contentType: "mirror") == nil)
    }

    @Test("종류가 다르면 잇지 않는다")
    func contentTypeMustMatch() async {
        let backend = FakeMarketplaceBackend()
        backend.myListingsResult = [owned(id: "l1", source: "same-id")]
        let subject = store(backend)
        await subject.refreshMyListings(session: session())

        #expect(subject.sellingListing(forContentID: "same-id", contentType: "sticker") == nil)
    }

    @Test("옛 서버 응답에 sourceContentId가 없어도 목록이 깨지지 않는다")
    func decodesWithoutSourceContentID() throws {
        let json = """
        [{"id":"a","contentType":"mirror","title":"t","description":"","priceShards":0,
          "status":"published","downloadCount":0,"likeCount":0,
          "publishedAt":"2026-08-19T10:00:12Z"}]
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.backend.decode([MarketplaceOwnedListing].self, from: json)

        #expect(decoded.count == 1)
        #expect(decoded[0].sourceContentId == "")
    }

    @Test("서버가 준 sourceContentId를 읽는다")
    func decodesSourceContentID() throws {
        let json = """
        {"id":"a","contentType":"mirror","title":"t","description":"","priceShards":0,
         "status":"published","downloadCount":0,"likeCount":0,
         "publishedAt":"2026-08-19T10:00:12Z","sourceContentId":"art-mint-flower"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.backend.decode(MarketplaceOwnedListing.self, from: json)

        #expect(decoded.sourceContentId == "art-mint-flower")
    }
}

@Suite("상점 IA · 통계 표시")
struct StoreIAHardeningTests {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "ggumirror")
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    @Test("상점에 내 판매 탭이 있다")
    func mySalesTabExists() {
        #expect(StoreSection.allCases.map(\.rawValue) == ["거울", "스티커", "내 판매"])
    }

    @Test("공개 거울 탭에 판매자 관리 UI가 없다")
    func publicMirrorHasNoSellerUI() throws {
        let code = try source("Store/StoreView.swift")
        let start = try #require(code.range(of: "private var mirrorContent: some View {"))
        let body = String(code[start.upperBound...].prefix(1400))
        #expect(!body.contains("MyListingsSection"), "공개 목록에 판매자 관리가 섞였다")
        #expect(!body.contains("MySalesSection"))
    }

    @Test("공개 스티커 탭에도 판매자 관리 UI가 없다")
    func publicStickerHasNoSellerUI() throws {
        let code = try source("Store/StickerStoreView.swift")
        #expect(!code.contains("MyListingsSection"))
    }

    @Test("내 판매는 판매 중과 등록 미완료를 나눈다")
    func mySalesSeparatesStates() throws {
        let code = try source("Store/MySalesSection.swift")
        #expect(code.contains("\"판매 중\""))
        #expect(code.contains("\"등록 미완료\""))
        #expect(code.contains("filter(\\.isPublished)"))
        #expect(code.contains("filter(\\.isDraft)"))
        // 서버가 authority다.
        #expect(code.contains("refreshMyListings"))
    }

    @Test("scroll 계층이 유지된다")
    func scrollHierarchyIntact() throws {
        let code = try source("Store/StoreView.swift")
        let stripped = code.split(separator: "\n").map { line -> String in
            guard let c = line.range(of: "//") else { return String(line) }
            return String(line[..<c.lowerBound])
        }.joined(separator: "\n")
        #expect(stripped.components(separatedBy: "ScrollView {").count - 1 == 1)
        #expect(code.contains("InkTabBar.reservedHeight"))
        // 내 판매도 같은 scroll 안에 있다.
        #expect(!(try source("Store/MySalesSection.swift")).contains("ScrollView"))
    }

    @Test("내장 카드는 서버가 센 값만 보여 준다")
    func builtInCountsComeFromTheServer() throws {
        // 이제 서버가 센다(catalog domain). 받기 전에는 숫자를 보여 주지 않고,
        // 하드코딩 값을 쓰지 않는다.
        let store = try source("Store/StoreView.swift")
        #expect(store.contains("catalogStats.downloadCount(template.id)"))
        #expect(store.contains("if let downloadCount"))

        let detail = try source("Store/TemplateDetailView.swift")
        #expect(detail.contains("catalogStats.downloadCount(template.id)"))

        // 옛 하드코딩 경로가 남아 있지 않다.
        for code in [store, detail] {
            #expect(!code.contains("Label(\"\\(template.downloadCount)\""))
        }
    }

    @Test("Marketplace 상품은 서버 값을 그대로 보여 준다")
    func marketplaceCountsAreServerValues() throws {
        let code = try source("Store/MarketplaceGallery.swift")
        #expect(code.contains("listing.downloadCount"))
        #expect(code.contains("listing.likeCount"))
        // 앱이 세지 않는다.
        for banned in ["downloadCount +", "likeCount +", "downloadCount +=", "likeCount +="] {
            #expect(!code.contains(banned), "앱이 counter를 올린다")
        }
    }

    @Test("공개 카드에 좋아요 하트가 있다")
    func publicCardHasHeart() throws {
        let code = try source("Store/MarketplaceGallery.swift")
        #expect(code.contains("onToggleLike"))
        #expect(code.contains("heart.fill"))
        // 손가락이 닿는 자리를 확보한다.
        #expect(code.contains("minWidth: 44, minHeight: 44"))
    }

    @Test("자기 상품에는 하트를 누를 수 없다")
    func ownListingHeartIsNotTappable() throws {
        let code = try source("Store/MarketplaceGallery.swift")
        #expect(code.contains("isMine"))
        // 실패할 CTA를 보여 주지 않는다.
        #expect(code.contains("내 상품이라 누를 수 없어요"))
    }

    @Test("좋아요 상태는 서버 목록에서 온다")
    func likedStateIsServerAuthoritative() throws {
        let gallery = try source("Store/MarketplaceGallery.swift")
        #expect(gallery.contains("store.likedListingIDs.contains"))
        let store = try source("Store/MarketplaceStore.swift")
        // 서버에서 받아 채운다 — 로컬에서만 만들지 않는다.
        #expect(store.contains("backend.likedListingIDs(accessToken:"))
    }

    @Test("내 거울 판매 중이 서버 목록을 쓴다")
    func sellingFilterUsesServer() throws {
        let code = try source("MyMirrors/MyMirrorsView.swift")
        #expect(code.contains("marketplace.selling(contentType:"))
        #expect(code.contains("sourceContentId"))
        // 제목 매칭이 없다.
        #expect(!code.contains("$0.name == "))
        #expect(!code.contains("title =="))
    }
}
