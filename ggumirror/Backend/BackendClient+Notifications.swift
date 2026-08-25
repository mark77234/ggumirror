//
//  BackendClient+Notifications.swift
//  ggumirror
//
//  알림센터와 기기 등록. **token을 경로에 넣지 않는다** — URL은 접근 로그와
//  중계 구간에 그대로 남는다. 본문으로 보낸다.
//

import Foundation

// MARK: - 서버가 보내는 모양

nonisolated struct SaleNotification: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let type: String
    let listingId: String
    let contentType: String
    /// 팔린 그때의 제목. 판매자가 나중에 이름을 바꿔도 기록은 그때를 가리킨다.
    let title: String
    /// 이번 판매로 받은 조각. 무료 상품이면 0이다.
    let shardAmount: Int
    let createdAt: Date
    let read: Bool

    var isMirror: Bool { contentType == "mirror" }
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
