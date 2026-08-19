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
        #expect(owned(id: "a", status: "published").statusLabel == "공개 중")
        #expect(owned(id: "a", status: "unlisted").statusLabel == "내림")
        #expect(owned(id: "a", status: "draft").statusLabel == "등록 준비")
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
