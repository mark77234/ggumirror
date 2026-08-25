//
//  BackendClient+Admin.swift
//  ggumirror
//
//  운영자 API. **권한은 서버가 판단한다** — 이 파일 어디에도 "내가 운영자다"라고
//  적을 자리가 없다. 요청은 평범한 Bearer 하나뿐이고, 아니면 403이 온다.
//
//  화면이 메뉴를 숨기는 것은 편의일 뿐이다. 숨겨진 화면을 강제로 열어도
//  여기서 나가는 모든 요청이 서버에서 막힌다.
//

import Foundation

// MARK: - 서버가 보내는 모양

/// 운영 목록의 상품 하나.
///
/// **판매자 내부 id가 없다.** 서버가 보내지 않고, 화면에도 필요 없다 —
/// 보여 줄 것은 이름이다.
nonisolated struct AdminListing: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let contentType: String
    let title: String
    let description: String
    let priceShards: Int
    /// 판매자 축(`draft` · `published` · `unlisted` · `deleted`).
    let status: String
    /// 운영 축(`active` · `removed`). 두 축은 서로 독립이다.
    let moderationStatus: String
    let moderationReason: String?
    let downloadCount: Int
    let likeCount: Int
    let createdAt: Date
    let publishedAt: Date?
    let sellerDisplayName: String?

    var isRemoved: Bool { moderationStatus == "removed" }
    var isMirror: Bool { contentType == "mirror" }
    /// 판매자가 삭제했다. **되살릴 수 없다** — 서버가 409로 거절한다.
    var isDeletedBySeller: Bool { status == "deleted" }

    var sellerLabel: String { sellerDisplayName ?? "이름 없음" }

    var statusLabel: String {
        if isRemoved { return "내려감" }
        switch status {
        case "published": return "판매 중"
        case "unlisted": return "판매자가 내림"
        case "draft": return "등록 중"
        case "deleted": return "판매자가 삭제"
        default: return "알 수 없음"
        }
    }

    /// 서버 문자열을 한 곳에서만 해석한다. 모르는 값은 지어내지 않는다.
    var reasonLabel: String? {
        switch moderationReason {
        case "inappropriate_content": "부적절한 콘텐츠"
        case "spam": "스팸/도배"
        case "copyright": "권리 침해"
        case "other": "기타"
        default: nil
        }
    }
}

nonisolated struct AdminListingPage: Decodable, Sendable {
    let listings: [AdminListing]
    /// 있으면 다음 장이 남아 있다는 뜻이다.
    let cursor: String?
}

/// 내리는 이유. **분류를 화면이 늘리지 않는다** — 서버가 아는 값과 같아야 한다.
nonisolated enum AdminModerationReason: String, CaseIterable, Sendable {
    case inappropriate = "inappropriate_content"
    case spam
    case copyright
    case other

    var label: String {
        switch self {
        case .inappropriate: "부적절한 콘텐츠"
        case .spam: "스팸/도배"
        case .copyright: "권리 침해"
        case .other: "기타"
        }
    }
}

// MARK: - 실패

nonisolated enum AdminFailure: Error, Equatable, Sendable {
    /// 로그인이 필요하다(401).
    case notSignedIn
    /// **운영자가 아니다**(403). `notSignedIn`과 뭉치지 않는다 — 로그인은 됐고
    /// 권한이 없는 것이라, 다시 로그인하라고 하면 아무 소용이 없다.
    case notAdmin
    /// 없는 상품이다(404).
    case notFound
    /// 지금 상태에서는 할 수 없다(409) — 판매자가 삭제했거나 내려가 있지 않다.
    case cannotChange
    case network
    case server(status: Int)

    var message: String {
        switch self {
        case .notSignedIn: "로그인이 필요해요."
        case .notAdmin: "권한이 없어요."
        case .notFound: "상품을 찾지 못했어요."
        case .cannotChange: "지금은 이 상품의 상태를 바꿀 수 없어요."
        case .network: "지금은 서버에 연결할 수 없어요. 잠시 뒤 다시 시도해 주세요."
        case .server: "문제가 생겨 처리하지 못했어요. 잠시 뒤 다시 시도해 주세요."
        }
    }

    static func from(status: Int, data: Data) -> AdminFailure {
        switch status {
        case 401: .notSignedIn
        case 403: .notAdmin
        case 404: .notFound
        case 409: .cannotChange
        default: .server(status: status)
        }
    }
}

// MARK: - 호출

nonisolated protocol AdminBackend: Sendable {
    func isAdmin(accessToken: String) async throws -> Bool
    func adminListings(
        contentType: String?, moderationStatus: String?, cursor: String?, accessToken: String
    ) async throws -> AdminListingPage
    func adminPreview(listingID: String, accessToken: String) async throws -> Data
    func takedown(
        listingID: String, reason: AdminModerationReason, accessToken: String
    ) async throws -> AdminListing
    func restore(listingID: String, accessToken: String) async throws -> AdminListing
}

extension BackendClient: AdminBackend {

    /// 운영자인가. **403은 오류가 아니라 답이다** — 대부분의 사용자가 여기다.
    func isAdmin(accessToken: String) async throws -> Bool {
        do {
            _ = try await adminRequest("admin/me", method: "GET", accessToken: accessToken)
            return true
        } catch AdminFailure.notAdmin {
            return false
        }
    }

    func adminListings(
        contentType: String?, moderationStatus: String?, cursor: String?, accessToken: String
    ) async throws -> AdminListingPage {
        var query: [URLQueryItem] = []
        if let contentType { query.append(URLQueryItem(name: "contentType", value: contentType)) }
        if let moderationStatus {
            query.append(URLQueryItem(name: "moderationStatus", value: moderationStatus))
        }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let data = try await adminRequest(
            "admin/marketplace/listings", method: "GET", query: query, accessToken: accessToken
        )
        return try decodeAdmin(
            AdminListingPage.self, from: data, path: "GET /admin/marketplace/listings"
        )
    }

    /// 운영 미리보기. **내려간 상품도 보인다** — 안 보이면 되돌릴지 판단할 수 없다.
    func adminPreview(listingID: String, accessToken: String) async throws -> Data {
        try await adminRequest(
            "admin/marketplace/listings/\(try pathComponent(listingID))/preview",
            method: "GET", accessToken: accessToken, timeout: 30
        )
    }

    func takedown(
        listingID: String, reason: AdminModerationReason, accessToken: String
    ) async throws -> AdminListing {
        // **보내는 것은 사유 하나다.** 판매자 · 상태 · 잔액을 실을 자리가 없다.
        struct Body: Encodable { let reason: String }
        let data = try await adminRequest(
            "admin/marketplace/listings/\(try pathComponent(listingID))/takedown",
            method: "POST",
            body: try JSONEncoder.backend.encode(Body(reason: reason.rawValue)),
            accessToken: accessToken
        )
        return try decodeAdmin(AdminListing.self, from: data, path: "POST .../takedown")
    }

    func restore(listingID: String, accessToken: String) async throws -> AdminListing {
        let data = try await adminRequest(
            "admin/marketplace/listings/\(try pathComponent(listingID))/restore",
            method: "POST", accessToken: accessToken
        )
        return try decodeAdmin(AdminListing.self, from: data, path: "POST .../restore")
    }

    private func adminRequest(
        _ path: String,
        method: String,
        body: Data? = nil,
        query: [URLQueryItem] = [],
        accessToken: String,
        timeout: TimeInterval = 15
    ) async throws -> Data {
        do {
            return try await request(
                path,
                method: method,
                body: body,
                query: query,
                accessToken: accessToken,
                interpretFailure: AdminFailure.from,
                timeout: timeout
            )
        } catch let failure as AdminFailure {
            throw failure
        } catch {
            throw AdminFailure.network
        }
    }

    /// listing id를 경로에 넣기 전에 확인한다. 상점 쪽과 **같은 규칙**이지만
    /// 실패 타입이 달라 여기 하나 더 둔다 — 운영 화면이 상점 오류를 알 필요는 없다.
    private func pathComponent(_ component: String) throws -> String {
        guard isSafePathComponent(component) else { throw AdminFailure.notFound }
        return component
    }

    private func decodeAdmin<T: Decodable>(_ type: T.Type, from data: Data, path: String) throws -> T {
        do {
            return try JSONDecoder.backend.decode(T.self, from: data)
        } catch {
            BackendLog.event("\(path) decode failure \(BackendLog.category(error))")
            throw AdminFailure.server(status: 200)
        }
    }
}
