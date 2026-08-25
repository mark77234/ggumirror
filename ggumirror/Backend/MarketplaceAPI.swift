//
//  MarketplaceAPI.swift
//  ggumirror
//
//  상점 서버와 주고받는 모양. **서버의 wire format 그대로**다.
//
//  화면이 쓰는 `MirrorTemplate`과 모양이 다르다 — 억지로 같은 타입으로 만들지 않고
//  경계에서 옮긴다(`MarketplaceListing.template`). `AppleSignInResponse`와 같은 규칙이고,
//  거기서 둘을 합치려다 실기기 decode 실패가 났던 전례가 있다.
//
//  서버가 주지 않는 것을 요구하지 않는다: `sellerUserId` · `snapshotId` ·
//  bucket · object key는 공개 응답에 **없다.**
//

import Foundation

// MARK: - 공개 목록

/// `GET /marketplace/listings` · `GET /marketplace/listings/{id}` 응답 하나.
///
/// 판매자 **신원**과 저장 위치는 서버가 공개하지 않는다 — 나오는 것은 이름뿐이다.
nonisolated struct MarketplaceListing: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let contentType: String
    let title: String
    let description: String
    let priceShards: Int
    let downloadCount: Int
    let likeCount: Int
    /// 상점에 **처음** 올라온 시각. 다시 올려도 바뀌지 않는다(서버 authority).
    let publishedAt: Date
    /// 판매자가 정한 이름. **없을 수 있다** — 아직 이름을 정하지 않은 판매자와
    /// 1.0.7 시절에 올라온 상품이 그렇다. 가짜 이름을 지어내지 않는다.
    /// `decodeIfPresent`가 아니라 optional이라 예전 응답도 그대로 읽힌다.
    let sellerDisplayName: String?
}

/// 판매자 자신이 보는 모양. `status`와 `publishedAt: nil`이 더 있다.
nonisolated struct MarketplaceOwnedListing: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let contentType: String
    let title: String
    let description: String
    let priceShards: Int
    /// `draft` · `published` · `unlisted`. 서버 문자열을 그대로 둔다 —
    /// 모르는 값이 오면 열거형 decode가 실패해서 화면이 통째로 비는 편보다 낫다.
    let status: String
    let downloadCount: Int
    let likeCount: Int
    /// 아직 올린 적이 없으면 `nil`이다. **`Date.now`로 채우지 않는다.**
    let publishedAt: Date?
    /// 이 상품이 어느 **내 콘텐츠**에서 나왔는지 — `MyMirror.id` / `StickerProject.id`.
    ///
    /// "내 거울 → 판매 중"에서 자기 상품을 찾는 데 쓴다. 제목으로 맞추지 않는다.
    /// 옛 snapshot이라 서버가 알 수 없으면 빈 문자열이다.
    let sourceContentId: String

    private enum CodingKeys: String, CodingKey {
        case id, contentType, title, description, priceShards, status
        case downloadCount, likeCount, publishedAt, sourceContentId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        contentType = try c.decode(String.self, forKey: .contentType)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decode(String.self, forKey: .description)
        priceShards = try c.decode(Int.self, forKey: .priceShards)
        status = try c.decode(String.self, forKey: .status)
        downloadCount = try c.decode(Int.self, forKey: .downloadCount)
        likeCount = try c.decode(Int.self, forKey: .likeCount)
        publishedAt = try c.decodeIfPresent(Date.self, forKey: .publishedAt)
        // 옛 서버 응답에는 없다. 없다고 목록 전체가 깨지면 안 된다.
        sourceContentId = try c.decodeIfPresent(String.self, forKey: .sourceContentId) ?? ""
    }

    init(
        id: String, contentType: String, title: String, description: String,
        priceShards: Int, status: String, downloadCount: Int, likeCount: Int,
        publishedAt: Date?, sourceContentId: String = ""
    ) {
        self.id = id; self.contentType = contentType; self.title = title
        self.description = description; self.priceShards = priceShards
        self.status = status; self.downloadCount = downloadCount
        self.likeCount = likeCount; self.publishedAt = publishedAt
        self.sourceContentId = sourceContentId
    }
}

nonisolated extension MarketplaceOwnedListing {
    /// 서버 `status` 문자열을 한 곳에서만 해석한다.
    ///
    /// 열거형으로 decode하지 않는 이유: 모르는 값이 오면 목록이 통째로 비는 것보다
    /// 그 상품만 "알 수 없음"으로 남는 편이 낫다.
    var isPublished: Bool { status == "published" }
    var isUnlisted: Bool { status == "unlisted" }
    var isDraft: Bool { status == "draft" }
    /// **끝 상태.** 판매자가 삭제했고 되살아나지 않는다.
    var isDeleted: Bool { status == "deleted" }

    /// 판매자에게 보일 상태 문구.
    ///
    /// `draft`를 "등록 준비"라고 했는데, **등록 도중 실패해 남은 것도 같은 상태**다
    /// (production에서 실제로 그랬다 — snapshot과 listing은 만들어졌고 publish만
    /// 실패했다). "준비"라고 하면 사용자가 자기가 안 올린 줄 안다.
    /// "등록 미완료"는 두 경우 모두 맞고, 이어서 올려야 한다는 것도 전한다.
    var statusLabel: String {
        switch status {
        case "published": "판매 중"
        case "unlisted": "판매 중지"
        case "draft": "등록 미완료"
        case "deleted": "삭제됨"
        default: "알 수 없음"
        }
    }
}

// MARK: - 등록

/// `POST /marketplace/snapshots` 응답. `snapshotId` · checksum은 **서버가 만든다.**
nonisolated struct MarketplaceSnapshot: Decodable, Hashable, Sendable {
    let snapshotId: String
    let contentType: String
    let assetCount: Int
    let totalBytes: Int
    let manifestChecksum: String
}

/// `POST /marketplace/listings` 요청. `snapshotId`는 서버가 만들어 준 값이다.
nonisolated struct MarketplaceDraftRequest: Encodable, Sendable {
    let contentType: String
    let title: String
    let description: String
    let priceShards: Int
    let snapshotId: String
}

/// `POST /marketplace/listings/{id}/publish` 응답.
///
/// **등록비 차감은 서버가 판단한다.** 다시 올릴 때는 `feeCharged=false`이고,
/// 앱이 "두 번째니까 무료"를 스스로 계산하지 않는다.
nonisolated struct MarketplacePublishResult: Decodable, Sendable {
    let published: Bool
    let feeCharged: Bool
    let feeShards: Int
    /// 차감 후 잔액. 서버가 말해 주는 값이다.
    let balance: Int
    let listing: MarketplaceOwnedListing
}

// MARK: - 구매

/// `POST /marketplace/listings/{id}/purchase` 응답.
///
/// 같은 상품을 다시 사면 `purchased=false` · `alreadyOwned=true`이고 **실패가 아니다** —
/// `balance`는 정상 현재 잔액이고 조각은 한 번만 빠졌다.
nonisolated struct MarketplacePurchaseResult: Decodable, Sendable {
    let purchased: Bool
    let alreadyOwned: Bool
    let pricePaid: Int
    let balance: Int
    let downloadCount: Int
    let listingId: String
    let acquiredAt: Date
}

/// `GET /users/me/marketplace/purchases` 항목.
nonisolated struct MarketplacePurchase: Decodable, Hashable, Sendable {
    let listingId: String
    let pricePaid: Int
    let acquiredAt: Date
    /// 판매자가 내린 뒤라면 `nil`이다 — 소유권은 남아 있고 공개 정보만 사라진다.
    let listing: MarketplaceListing?
}

// MARK: - 좋아요

/// `PUT` / `DELETE /marketplace/listings/{id}/like` 응답.
///
/// 반복 요청은 `changed=false`로 조용히 끝난다. HTTP 오류가 아니다.
nonisolated struct MarketplaceLikeResult: Decodable, Sendable {
    let listingId: String
    let liked: Bool
    let changed: Bool
    let likeCount: Int
}

// MARK: - 내려받은 템플릿

/// `GET /marketplace/listings/{id}/template` + 참조 asset들.
///
/// **manifest는 client의 기존 Codable 그대로**다. 별도 Marketplace 모델을 만들지 않는다.
nonisolated struct MarketplaceTemplate: Sendable {
    let manifest: Data
    /// assetID → PNG bytes. manifest가 참조하는 것과 정확히 같은 집합이다.
    let assets: [UUID: Data]
}

// MARK: - 오류

/// 서버가 실제로 내는 실패만 구분한다. **없는 code를 상상해서 넣지 않는다.**
///
/// 서버는 `{"detail": "<문구>"}`로 보낸다(FastAPI). 문구를 사용자에게 그대로 옮기지 않고
/// 우리가 아는 것만 분류한다 — 서버 문구가 바뀌어도 앱이 이상한 말을 하지 않는다.
nonisolated enum MarketplaceFailure: Error, Equatable, Sendable {
    /// 로그인이 필요하다(401 · 403).
    case notSignedIn
    /// 조각이 부족하다(409 `not enough shards`).
    case insufficientShards
    /// 자기 상품은 살 수 없다(400).
    case selfPurchase
    /// 자기 상품에는 좋아요할 수 없다(400).
    case selfLike
    /// 없거나, 내려갔거나, **볼 권한이 없다.**
    ///
    /// 서버는 권한 없는 template 요청에도 404를 준다 — 존재 여부 자체를 알려주지 않는다.
    /// 그것이 안전한 쪽이라 client도 하나로 다룬다.
    case notFound
    /// 지금 상태에서는 올릴 수 없다(409 `listing cannot be published`).
    case cannotPublish
    /// 우리가 만든 package가 서버 규칙에 맞지 않다(400 · 413).
    /// **사용자 잘못이 아니라 앱 잘못이다.**
    case invalidPackage
    /// 서버 저장소가 준비되지 않았다(503). 잠시 뒤 다시.
    case storageUnavailable
    /// 네트워크가 안 됐다. 서버가 거부한 것이 아니다.
    case network
    /// 그 밖의 응답.
    case server(status: Int)

    var message: String {
        switch self {
        case .notSignedIn: "로그인이 필요해요."
        case .insufficientShards: "조각이 부족해요."
        case .selfPurchase: "내가 올린 상품은 살 수 없어요."
        case .selfLike: "내가 올린 상품에는 좋아요를 누를 수 없어요."
        case .notFound: "상품을 찾지 못했어요."
        case .cannotPublish: "지금은 상점에 올릴 수 없어요."
        case .invalidPackage: "상점에 올릴 준비를 마치지 못했어요."
        case .storageUnavailable, .network: "지금은 서버에 연결할 수 없어요. 잠시 뒤 다시 시도해 주세요."
        // **연결은 됐고 서버가 처리하지 못한 것이다.** 둘을 같은 말로 뭉개면
        // 사용자도 우리도 어디를 봐야 할지 모른다 — 유료 구매 500이 그랬다.
        case .server: "문제가 생겨 처리하지 못했어요. 잠시 뒤 다시 시도해 주세요."
        }
    }

    /// 잠시 뒤 다시 시도하면 될 성질인가.
    var isTemporary: Bool {
        switch self {
        case .network, .storageUnavailable, .server: true
        case .notSignedIn, .insufficientShards, .selfPurchase, .selfLike,
             .notFound, .cannotPublish, .invalidPackage: false
        }
    }

    /// status + `detail`을 우리가 아는 실패로 옮긴다.
    ///
    /// `detail` 문구는 **분류에만** 쓰고 사용자에게 그대로 보여주지 않는다.
    static func from(status: Int, data: Data) -> MarketplaceFailure {
        if status == 401 || status == 403 { return .notSignedIn }

        struct Envelope: Decodable { let detail: String }
        let detail = (try? JSONDecoder().decode(Envelope.self, from: data))?.detail ?? ""

        switch (status, detail) {
        case (409, "not enough shards"): return .insufficientShards
        case (409, "listing cannot be published"): return .cannotPublish
        case (400, "cannot buy your own listing"): return .selfPurchase
        case (400, "cannot like your own listing"): return .selfLike
        case (503, _): return .storageUnavailable
        case (404, _): return .notFound
        case (400, _), (413, _), (422, _): return .invalidPackage
        default:
            return status >= 500 ? .server(status: status) : .server(status: status)
        }
    }
}

// MARK: - Backend 표면

/// 테스트가 실제 network 없이 흐름을 확인할 수 있도록 protocol을 둔다.
/// `AuthBackend` · `ShardBackend`와 같은 규칙이다.
nonisolated protocol MarketplaceBackend: Sendable {
    // 공개 — 로그인 없이 볼 수 있다(Core Product Policy).
    func listings(contentType: String?, sort: String) async throws -> [MarketplaceListing]
    func listing(id: String) async throws -> MarketplaceListing
    func preview(listingID: String) async throws -> Data

    // 인증 필요.
    func createSnapshot(
        contentType: String, manifest: Data, preview: Data, assets: [UUID: Data],
        accessToken: String
    ) async throws -> MarketplaceSnapshot
    func createDraft(
        _ request: MarketplaceDraftRequest, accessToken: String
    ) async throws -> MarketplaceOwnedListing
    func publish(listingID: String, accessToken: String) async throws -> MarketplacePublishResult
    func unpublish(listingID: String, accessToken: String) async throws -> MarketplaceOwnedListing
    func purchase(listingID: String, accessToken: String) async throws -> MarketplacePurchaseResult
    func purchases(accessToken: String) async throws -> [MarketplacePurchase]
    /// **내가 올린 것 전부** — `draft` · `published` · `unlisted`.
    ///
    /// 공개 목록과 다른 것이다. 판매자가 자기 상품을 다시 찾는 **authority**다 —
    /// 앱이 기억해 둔 id에 의존하면 앱을 지웠거나 기기를 바꾼 뒤 관리가 끊긴다.
    func myListings(accessToken: String) async throws -> [MarketplaceOwnedListing]
    /// **내가 올린 상품의 미리보기.** `draft` · `published` · `unlisted` 모두.
    ///
    /// 공개 미리보기(`preview`)는 `published`만이다 — 판매자 관리 화면에서만
    /// 아직 올리지 않은 것과 내린 것의 생김새가 필요하다.
    func myListingPreview(listingID: String, accessToken: String) async throws -> Data
    /// 상품을 **삭제한다.** 끝 상태이고 되살릴 수 없다.
    ///
    /// 서버는 실제로 지우지 않는다 — 이미 산 사람은 계속 받는다.
    /// 등록비도 돌아오지 않는다.
    func deleteListing(listingID: String, accessToken: String) async throws -> MarketplaceOwnedListing
    func like(listingID: String, accessToken: String) async throws -> MarketplaceLikeResult
    func unlike(listingID: String, accessToken: String) async throws -> MarketplaceLikeResult
    func likedListingIDs(accessToken: String) async throws -> [String]
    func templateManifest(listingID: String, accessToken: String) async throws -> Data
    func templateAsset(
        listingID: String, assetID: UUID, accessToken: String
    ) async throws -> Data
}
