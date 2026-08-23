//
//  BackendClient+Marketplace.swift
//  ggumirror
//
//  상점 API 호출. `BackendClient.request`를 그대로 쓴다 —
//  Bearer 주입 · timeout · 로깅 규칙이 한 곳에만 있어야 한다.
//
//  실패 해석은 전부 `MarketplaceFailure.from`으로 모은다. 화면이 status code를
//  직접 보지 않는다.
//
//  로그에는 method · route · status만 남는다(`BackendLog`). token · manifest ·
//  이미지 바이트는 찍지 않는다.
//

import Foundation

// MARK: - 호출

extension BackendClient: MarketplaceBackend {

    // MARK: 공개 조회

    /// **로그인 없이** 볼 수 있다. 상품이 없으면 빈 배열이다 — 가짜 상품을 만들지 않는다.
    func listings(contentType: String?, sort: String) async throws -> [MarketplaceListing] {
        // **`?`를 path에 넣지 않는다** — `appending(path:)`가 `%3F`로 인코딩해서
        // query가 경로의 일부가 된다(B-7H에서 발견).
        var query = [URLQueryItem(name: "sort", value: sort)]
        if let contentType { query.append(URLQueryItem(name: "contentType", value: contentType)) }
        let data = try await marketplaceRequest(
            "marketplace/listings", method: "GET", query: query
        )
        return try decodeMarketplace([MarketplaceListing].self, from: data, path: "GET /marketplace/listings")
    }

    func listing(id: String) async throws -> MarketplaceListing {
        let data = try await marketplaceRequest("marketplace/listings/\(try pathComponent(id))", method: "GET")
        return try decodeMarketplace(
            MarketplaceListing.self, from: data, path: "GET /marketplace/listings/{id}"
        )
    }

    /// 카드에 보여 줄 대표 이미지. **published만 공개**이고 signed URL을 쓰지 않는다.
    func preview(listingID: String) async throws -> Data {
        try await marketplaceRequest(
            "marketplace/listings/\(try pathComponent(listingID))/preview", method: "GET", timeout: 30
        )
    }

    // MARK: 등록

    /// snapshot 업로드. `snapshotId` · checksum · 저장 위치는 **서버가 정한다.**
    ///
    /// asset 파일 이름은 `<assetID>.png`다 — 서버가 확장자를 떼고 UUID인지 검사한다.
    /// 경로를 담을 자리가 없다.
    func createSnapshot(
        contentType: String, manifest: Data, preview: Data, assets: [UUID: Data],
        accessToken: String
    ) async throws -> MarketplaceSnapshot {
        var form = MultipartForm()
        form.addField(name: "contentType", value: contentType)
        form.addFile(name: "manifest", filename: "manifest.json", mime: "application/json", data: manifest)
        form.addFile(name: "preview", filename: "preview.png", mime: "image/png", data: preview)
        // 순서를 고정한다 — 같은 package가 항상 같은 바이트로 나가면 재현이 쉽다.
        for id in assets.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            form.addFile(
                name: "assets",
                filename: "\(id.uuidString).png",
                mime: "image/png",
                data: assets[id] ?? Data()
            )
        }
        let data = try await marketplaceRequest(
            "marketplace/snapshots",
            method: "POST",
            body: form.finished(),
            contentType: form.contentType,
            accessToken: accessToken,
            // 이미지 몇 장이 올라간다. 조회 기본값(15초)으로는 정상 업로드도 끊긴다.
            timeout: 120
        )
        return try decodeMarketplace(
            MarketplaceSnapshot.self, from: data, path: "POST /marketplace/snapshots"
        )
    }

    func createDraft(
        _ request: MarketplaceDraftRequest, accessToken: String
    ) async throws -> MarketplaceOwnedListing {
        let data = try await marketplaceRequest(
            "marketplace/listings",
            method: "POST",
            body: try JSONEncoder.backend.encode(request),
            accessToken: accessToken
        )
        return try decodeMarketplace(
            MarketplaceOwnedListing.self, from: data, path: "POST /marketplace/listings"
        )
    }

    /// **body를 보내지 않는다** — 등록비 · 판매자 · 상태를 client가 정하는 자리가 없다.
    func publish(listingID: String, accessToken: String) async throws -> MarketplacePublishResult {
        let data = try await marketplaceRequest(
            "marketplace/listings/\(try pathComponent(listingID))/publish",
            method: "POST",
            accessToken: accessToken
        )
        return try decodeMarketplace(
            MarketplacePublishResult.self, from: data, path: "POST /marketplace/listings/{id}/publish"
        )
    }

    func unpublish(listingID: String, accessToken: String) async throws -> MarketplaceOwnedListing {
        let data = try await marketplaceRequest(
            "marketplace/listings/\(try pathComponent(listingID))/unpublish",
            method: "POST",
            accessToken: accessToken
        )
        return try decodeMarketplace(
            MarketplaceOwnedListing.self, from: data,
            path: "POST /marketplace/listings/{id}/unpublish"
        )
    }

    // MARK: 구매

    /// **body를 보내지 않는다** — 가격은 서버 listing이 authority다.
    func purchase(listingID: String, accessToken: String) async throws -> MarketplacePurchaseResult {
        let data = try await marketplaceRequest(
            "marketplace/listings/\(try pathComponent(listingID))/purchase",
            method: "POST",
            accessToken: accessToken
        )
        return try decodeMarketplace(
            MarketplacePurchaseResult.self, from: data,
            path: "POST /marketplace/listings/{id}/purchase"
        )
    }

    func purchases(accessToken: String) async throws -> [MarketplacePurchase] {
        let data = try await marketplaceRequest(
            "users/me/marketplace/purchases", method: "GET", accessToken: accessToken
        )
        return try decodeMarketplace(
            [MarketplacePurchase].self, from: data, path: "GET /users/me/marketplace/purchases"
        )
    }

    /// 내가 올린 것 전부. **서버가 판매자를 session으로 판단한다** —
    /// userId를 보내는 자리가 없다.
    func myListings(accessToken: String) async throws -> [MarketplaceOwnedListing] {
        let data = try await marketplaceRequest(
            "users/me/marketplace/listings", method: "GET", accessToken: accessToken
        )
        return try decodeMarketplace(
            [MarketplaceOwnedListing].self, from: data,
            path: "GET /users/me/marketplace/listings"
        )
    }

    /// 판매자 전용 미리보기. draft · unlisted도 온다.
    func myListingPreview(listingID: String, accessToken: String) async throws -> Data {
        try await marketplaceRequest(
            "users/me/marketplace/listings/\(try pathComponent(listingID))/preview",
            method: "GET",
            accessToken: accessToken,
            timeout: 30
        )
    }

    /// 상품 삭제. **되살릴 수 없다** — 화면이 먼저 확인을 받는다.
    func deleteListing(
        listingID: String, accessToken: String
    ) async throws -> MarketplaceOwnedListing {
        let data = try await marketplaceRequest(
            "users/me/marketplace/listings/\(try pathComponent(listingID))",
            method: "DELETE",
            accessToken: accessToken
        )
        return try decodeMarketplace(
            MarketplaceOwnedListing.self, from: data,
            path: "DELETE /users/me/marketplace/listings/{id}"
        )
    }

    // MARK: 좋아요

    func like(listingID: String, accessToken: String) async throws -> MarketplaceLikeResult {
        try await likeRequest(listingID: listingID, method: "PUT", accessToken: accessToken)
    }

    func unlike(listingID: String, accessToken: String) async throws -> MarketplaceLikeResult {
        try await likeRequest(listingID: listingID, method: "DELETE", accessToken: accessToken)
    }

    private func likeRequest(
        listingID: String, method: String, accessToken: String
    ) async throws -> MarketplaceLikeResult {
        let data = try await marketplaceRequest(
            "marketplace/listings/\(try pathComponent(listingID))/like",
            method: method,
            accessToken: accessToken
        )
        return try decodeMarketplace(
            MarketplaceLikeResult.self, from: data, path: "\(method) /marketplace/listings/{id}/like"
        )
    }

    /// 내가 좋아요한 상품 id. 공개 목록과 합쳐서 하트를 채운다 —
    /// 공개 DTO에 `likedByMe`를 넣기 위해 optional auth를 만들지 않았다(서버 결정).
    func likedListingIDs(accessToken: String) async throws -> [String] {
        let data = try await marketplaceRequest(
            "users/me/marketplace/likes", method: "GET", accessToken: accessToken
        )
        return try decodeMarketplace(
            [String].self, from: data, path: "GET /users/me/marketplace/likes"
        )
    }

    // MARK: 원본 템플릿

    /// **판매자 또는 구매자만.** 권한이 없으면 서버가 404를 준다(존재 여부를 알려주지 않는다).
    ///
    /// `published`를 요구하지 않는다 — 판매자가 내려도 산 사람은 계속 받는다.
    func templateManifest(listingID: String, accessToken: String) async throws -> Data {
        try await marketplaceRequest(
            "marketplace/listings/\(try pathComponent(listingID))/template",
            method: "GET",
            accessToken: accessToken,
            timeout: 30
        )
    }

    func templateAsset(
        listingID: String, assetID: UUID, accessToken: String
    ) async throws -> Data {
        try await marketplaceRequest(
            "marketplace/listings/\(try pathComponent(listingID))/template/assets/\(assetID.uuidString)",
            method: "GET",
            accessToken: accessToken,
            timeout: 60
        )
    }

    // MARK: 공통

    /// 상점 요청은 전부 여기를 지난다 — 실패 해석이 한 곳에만 있다.
    private func marketplaceRequest(
        _ path: String,
        method: String,
        body: Data? = nil,
        query: [URLQueryItem] = [],
        contentType: String = "application/json",
        accessToken: String? = nil,
        timeout: TimeInterval = 15
    ) async throws -> Data {
        do {
            return try await request(
                path,
                method: method,
                body: body,
                query: query,
                contentType: contentType,
                accessToken: accessToken,
                interpretFailure: MarketplaceFailure.from,
                timeout: timeout
            )
        } catch let failure as MarketplaceFailure {
            throw failure
        } catch {
            // `send`가 network / non-HTTP 실패에 내는 것은 `BackendError`다.
            // 상점 화면이 두 오류 타입을 알지 않도록 여기서 옮긴다.
            throw MarketplaceFailure.network
        }
    }

    private func decodeMarketplace<T: Decodable>(
        _ type: T.Type, from data: Data, path: String
    ) throws -> T {
        do {
            return try JSONDecoder.backend.decode(type, from: data)
        } catch {
            // 200인데 우리가 모르는 모양이다. **성공으로 보지 않는다.**
            BackendLog.event("\(path) decode failure \(BackendLog.category(error))")
            throw MarketplaceFailure.server(status: 200)
        }
    }

    /// 경로 한 칸에 넣기 전 확인.
    ///
    /// **미리 percent-encoding하지 않는다.** `URL.appending(path:)`가 이미 인코딩하므로
    /// 두 번 하면 `-`가 `%2D`를 거쳐 `%252D`가 되고, 서버는 그런 id를 찾지 못한다.
    /// production에서 publish가 정확히 이 이유로 404였다(B-7H에서 발견).
    ///
    /// 다만 `appending(path:)`는 `/`를 **구분자로 그대로 두고** `..`도 해석하지 않으므로
    /// 그 둘만 막는다. listing id · assetId는 서버가 만든 UUID라 정상 경로에서는 없는
    /// 문자이고, 있으면 우리가 아는 id가 아니라 요청을 만들지 않는다.
    private func pathComponent(_ component: String) throws -> String {
        guard !component.isEmpty,
              !component.contains("/"),
              !component.contains("\\"),
              component != ".",
              component != ".."
        else { throw MarketplaceFailure.notFound }
        return component
    }
}

// MARK: - multipart

/// `multipart/form-data` 본문을 만든다.
///
/// 직접 만드는 이유: 이 앱은 networking 라이브러리를 넣지 않는다(`BackendClient` 규칙).
/// 경계 문자열은 UUID라 사용자 데이터와 겹치지 않는다.
nonisolated struct MultipartForm {
    private let boundary = "ggumirror-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(name: String, filename: String, mime: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    /// 닫는 경계까지 붙인 최종 본문. 한 번만 부른다.
    func finished() -> Data {
        var closed = body
        closed.append(Data("--\(boundary)--\r\n".utf8))
        return closed
    }

    private mutating func append(_ text: String) {
        body.append(Data(text.utf8))
    }
}
