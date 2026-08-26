//
//  BackendClient+Notifications.swift
//  ggumirror
//
//  알림센터와 기기 등록. **token을 경로에 넣지 않는다** — URL은 접근 로그와
//  중계 구간에 그대로 남는다. 본문으로 보낸다.
//

import Foundation

// MARK: - 서버가 보내는 모양

/// 알림의 종류. **모르는 값 하나가 목록 전체를 깨뜨리지 않는다.**
nonisolated enum NotificationKind: String, Decodable, Sendable {
    case sale = "marketplace_sale"
    case mirrorDigest = "mirror_digest"
    case recommendation
    /// 이 앱이 모르는 종류. 서버가 나중에 새 종류를 보내도 여기로 온다.
    case unknown

    static func of(_ raw: String?) -> NotificationKind {
        guard let raw, let known = NotificationKind(rawValue: raw) else { return .unknown }
        return known
    }
}

nonisolated struct SaleNotification: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let type: String
    /// **판매 알림에만 있다.** 모아 보기는 상품 하나에 매이지 않는다.
    let listingId: String
    let contentType: String
    /// 팔린 그때의 제목. 판매자가 나중에 이름을 바꿔도 기록은 그때를 가리킨다.
    let title: String
    /// 이번 판매로 받은 조각. 무료 상품이면 0이다.
    let shardAmount: Int
    /// 종류와 무관한 문구. 판매 알림에는 없고(옛 문서에도 없다) 그때는
    /// 화면이 상품 이름과 조각으로 문장을 만든다.
    let headline: String
    let body: String
    let createdAt: Date
    let read: Bool

    var isMirror: Bool { contentType == "mirror" }
    /// **모르는 종류가 와도 목록이 살아 있다.**
    var kind: NotificationKind { NotificationKind.of(type) }

    private enum CodingKeys: String, CodingKey {
        case id, type, listingId, contentType, title, shardAmount
        case headline, body, createdAt, read
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        // **열거형으로 받지 않는다.** 새 종류가 오면 decode가 통째로 실패한다.
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        // 옛 판매 문서에는 새 field가 없고, 모아 보기에는 판매 field가 없다.
        listingId = try c.decodeIfPresent(String.self, forKey: .listingId) ?? ""
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        shardAmount = try c.decodeIfPresent(Int.self, forKey: .shardAmount) ?? 0
        headline = try c.decodeIfPresent(String.self, forKey: .headline) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        read = try c.decodeIfPresent(Bool.self, forKey: .read) ?? false
    }

    init(
        id: String, type: String, listingId: String = "", contentType: String = "",
        title: String = "", shardAmount: Int = 0, headline: String = "", body: String = "",
        createdAt: Date, read: Bool = false
    ) {
        self.id = id; self.type = type; self.listingId = listingId
        self.contentType = contentType; self.title = title; self.shardAmount = shardAmount
        self.headline = headline; self.body = body
        self.createdAt = createdAt; self.read = read
    }

    /// 화면에 보여 줄 제목. **종류마다 다르다.**
    var displayTitle: String {
        switch kind {
        case .sale: "\(title)이 판매됐어요"
        case .mirrorDigest, .recommendation: headline.isEmpty ? "새로운 소식" : headline
        // 모르는 종류는 일반 알림으로 보여 준다. **raw 값을 노출하지 않는다.**
        case .unknown: headline.isEmpty ? "알림" : headline
        }
    }

    var displayBody: String {
        switch kind {
        case .sale: shardAmount > 0 ? "+\(shardAmount)조각" : "누군가 받아 갔어요"
        default: body.isEmpty ? "새로운 소식이 있어요." : body
        }
    }
}

nonisolated struct SaleNotificationPage: Decodable, Sendable {
    let notifications: [SaleNotification]
    /// 있으면 다음 장이 남아 있다는 뜻이다.
    let cursor: String?
}

/// 상품 하나가 몇 번 팔렸는가. **총계다** — 알림을 몇 장 불러왔는지와 무관하다.
nonisolated struct SaleStat: Decodable, Hashable, Identifiable, Sendable {
    let listingId: String
    let contentType: String
    let title: String
    let saleCount: Int
    let priceShards: Int

    var id: String { listingId }
    var isMirror: Bool { contentType == "mirror" }
}

/// 새 거울 소식을 얼마나 자주 받을까. **서버 값과 같은 문자열이다.**
nonisolated enum DigestFrequency: String, CaseIterable, Decodable, Sendable {
    case off
    case daily
    case weekly

    var label: String {
        switch self {
        case .off: "받지 않기"
        case .daily: "매일"
        case .weekly: "매주"
        }
    }

    /// 모르는 값은 **끔**이다. 알 수 없을 때 더 보내는 쪽으로 기울지 않는다.
    static func of(_ raw: String?) -> DigestFrequency {
        guard let raw, let known = DigestFrequency(rawValue: raw) else { return .off }
        return known
    }
}

/// 알림 설정. **OS 권한과 다른 것이다** — 이건 "무엇을 받을까"다.
nonisolated struct NotificationPreferences: Decodable, Equatable, Sendable {
    var salesEnabled: Bool
    var mirrorDigestFrequency: DigestFrequency
    var recommendationEnabled: Bool

    /// 서버에 문서가 없을 때의 값. **판매는 켜짐, 나머지는 꺼짐.**
    static let fallback = NotificationPreferences(
        salesEnabled: true, mirrorDigestFrequency: .off, recommendationEnabled: false
    )

    private enum CodingKeys: String, CodingKey {
        case salesEnabled, mirrorDigestFrequency, recommendationEnabled
    }

    init(salesEnabled: Bool, mirrorDigestFrequency: DigestFrequency, recommendationEnabled: Bool) {
        self.salesEnabled = salesEnabled
        self.mirrorDigestFrequency = mirrorDigestFrequency
        self.recommendationEnabled = recommendationEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        salesEnabled = try c.decodeIfPresent(Bool.self, forKey: .salesEnabled) ?? true
        mirrorDigestFrequency = DigestFrequency.of(
            try c.decodeIfPresent(String.self, forKey: .mirrorDigestFrequency)
        )
        recommendationEnabled =
            try c.decodeIfPresent(Bool.self, forKey: .recommendationEnabled) ?? false
    }
}

/// 어느 APNs로 보낼지. **앱이 지어내는 값이 아니다** — 빌드가 정한다.
nonisolated enum PushEnvironment: String, Sendable {
    case sandbox
    case production

    /// Debug 빌드와 TestFlight/App Store 빌드의 APNs가 다르다.
    ///
    /// 여기를 틀리면 알림이 조용히 사라진다 — 잘못된 환경으로 보낸 요청은
    /// `BadDeviceToken`이 되고, 사용자에게는 그냥 안 오는 것처럼 보인다.
    static var current: PushEnvironment {
        #if DEBUG
        .sandbox
        #else
        // TestFlight도 App Store와 같은 production APNs를 쓴다.
        .production
        #endif
    }
}

// MARK: - 실패

nonisolated enum NotificationFailure: Error, Equatable, Sendable {
    case notSignedIn
    case notFound
    /// 우리가 보낸 값이 서버 규칙에 맞지 않다. **사용자 잘못이 아니다.**
    case invalidRequest
    case network
    case server(status: Int)

    var message: String {
        switch self {
        case .notSignedIn: "로그인이 필요해요."
        case .notFound: "알림을 찾지 못했어요."
        case .invalidRequest, .server: "문제가 생겨 처리하지 못했어요. 잠시 뒤 다시 시도해 주세요."
        case .network: "지금은 서버에 연결할 수 없어요. 잠시 뒤 다시 시도해 주세요."
        }
    }

    static func from(status: Int, data: Data) -> NotificationFailure {
        switch status {
        case 401, 403: .notSignedIn
        case 404: .notFound
        case 400, 422: .invalidRequest
        default: .server(status: status)
        }
    }
}

// MARK: - 호출

nonisolated protocol NotificationBackend: Sendable {
    func notificationPreferences(accessToken: String) async throws -> NotificationPreferences
    /// **보낸 값만 바뀐다.** 토글 하나를 바꿀 때 나머지를 함께 보내지 않는다.
    func updateNotificationPreferences(
        salesEnabled: Bool?, digestFrequency: DigestFrequency?,
        recommendationEnabled: Bool?, accessToken: String
    ) async throws -> NotificationPreferences
    func notifications(cursor: String?, accessToken: String) async throws -> SaleNotificationPage
    func saleStats(accessToken: String) async throws -> [SaleStat]
    func markNotificationRead(id: String, accessToken: String) async throws -> SaleNotification
    func registerPushDevice(
        token: String, environment: PushEnvironment, accessToken: String
    ) async throws
    func unregisterPushDevice(
        token: String, environment: PushEnvironment, accessToken: String
    ) async throws
}

extension BackendClient: NotificationBackend {
    func notificationPreferences(accessToken: String) async throws -> NotificationPreferences {
        let data = try await notificationRequest(
            "users/me/notification-preferences", method: "GET", accessToken: accessToken
        )
        return try decodeNotification(
            NotificationPreferences.self, from: data,
            path: "GET /users/me/notification-preferences"
        )
    }

    func updateNotificationPreferences(
        salesEnabled: Bool?, digestFrequency: DigestFrequency?,
        recommendationEnabled: Bool?, accessToken: String
    ) async throws -> NotificationPreferences {
        struct Body: Encodable {
            let salesEnabled: Bool?
            let mirrorDigestFrequency: String?
            let recommendationEnabled: Bool?
        }
        let data = try await notificationRequest(
            "users/me/notification-preferences",
            method: "PATCH",
            body: try JSONEncoder.backend.encode(Body(
                salesEnabled: salesEnabled,
                mirrorDigestFrequency: digestFrequency?.rawValue,
                recommendationEnabled: recommendationEnabled
            )),
            accessToken: accessToken
        )
        return try decodeNotification(
            NotificationPreferences.self, from: data,
            path: "PATCH /users/me/notification-preferences"
        )
    }

    func notifications(cursor: String?, accessToken: String) async throws -> SaleNotificationPage {
        var query: [URLQueryItem] = []
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let data = try await notificationRequest(
            "users/me/notifications", method: "GET", query: query, accessToken: accessToken
        )
        return try decodeNotification(
            SaleNotificationPage.self, from: data, path: "GET /users/me/notifications"
        )
    }

    func saleStats(accessToken: String) async throws -> [SaleStat] {
        let data = try await notificationRequest(
            "users/me/sale-stats", method: "GET", accessToken: accessToken
        )
        return try decodeNotification([SaleStat].self, from: data, path: "GET /users/me/sale-stats")
    }

    func markNotificationRead(id: String, accessToken: String) async throws -> SaleNotification {
        guard isSafePathComponent(id) else { throw NotificationFailure.notFound }
        let data = try await notificationRequest(
            "users/me/notifications/\(id)/read", method: "PATCH", accessToken: accessToken
        )
        return try decodeNotification(
            SaleNotification.self, from: data, path: "PATCH .../read"
        )
    }

    func registerPushDevice(
        token: String, environment: PushEnvironment, accessToken: String
    ) async throws {
        _ = try await notificationRequest(
            "users/me/push-devices",
            method: "PUT",
            body: try JSONEncoder.backend.encode(_DeviceBody(token: token, environment: environment.rawValue)),
            accessToken: accessToken
        )
    }

    func unregisterPushDevice(
        token: String, environment: PushEnvironment, accessToken: String
    ) async throws {
        _ = try await notificationRequest(
            "users/me/push-devices",
            method: "DELETE",
            body: try JSONEncoder.backend.encode(_DeviceBody(token: token, environment: environment.rawValue)),
            accessToken: accessToken
        )
    }

    private func notificationRequest(
        _ path: String,
        method: String,
        body: Data? = nil,
        query: [URLQueryItem] = [],
        accessToken: String
    ) async throws -> Data {
        do {
            return try await request(
                path,
                method: method,
                body: body,
                query: query,
                accessToken: accessToken,
                interpretFailure: NotificationFailure.from
            )
        } catch let failure as NotificationFailure {
            throw failure
        } catch {
            throw NotificationFailure.network
        }
    }

    private func decodeNotification<T: Decodable>(
        _ type: T.Type, from data: Data, path: String
    ) throws -> T {
        do {
            return try JSONDecoder.backend.decode(T.self, from: data)
        } catch {
            BackendLog.event("\(path) decode failure \(BackendLog.category(error))")
            throw NotificationFailure.server(status: 200)
        }
    }
}

/// **token은 본문으로만 나간다.** 경로에 넣으면 URL 로그에 그대로 남는다.
private nonisolated struct _DeviceBody: Encodable {
    let token: String
    let environment: String
}
