//
//  BackendClient.swift
//  ggumirror
//
//  꾸미러 Backend와 이야기하는 유일한 곳. URLSession만 쓴다 — networking 라이브러리를 넣지 않는다.
//
//  Apple credential은 여기까지만 온다. `identityToken`과 nonce 원본은 요청 본문으로만 쓰이고
//  저장되지도, 로그에 찍히지도 않는다.
//

import Foundation

// MARK: - 오류

nonisolated enum BackendError: Error, Equatable {
    /// 주소 없이 client를 만든 경우. 정상 앱에서는 일어나지 않는다(`AppConfig`가 항상 준다).
    case notConfigured
    /// Apple credential이 거부됐거나 세션이 유효하지 않다.
    case unauthorized
    /// 서버 / 네트워크가 일시적으로 안 된다. **사용자 콘텐츠를 지우는 이유가 될 수 없다.**
    case unavailable
    /// 그 밖의 응답. 상세를 사용자에게 그대로 보여주지 않는다.
    case unexpected(status: Int)

    /// 사용자에게 보여줄 말. 서버 내부 사정을 옮기지 않는다.
    var message: String {
        switch self {
        case .notConfigured:
            "서버에 연결할 수 없어요. 앱을 다시 시작해 주세요."
        case .unauthorized:
            "로그인 정보를 확인하지 못했어요. 다시 시도해 주세요."
        case .unavailable:
            "지금은 서버에 연결할 수 없어요. 잠시 뒤 다시 시도해 주세요."
        case .unexpected:
            "로그인을 마치지 못했어요. 잠시 뒤 다시 시도해 주세요."
        }
    }

    /// 잠시 뒤 다시 시도하면 될 성질의 실패인가.
    var isTemporary: Bool {
        switch self {
        case .unavailable, .unexpected: true
        case .notConfigured, .unauthorized: false
        }
    }
}

// MARK: - 서버가 실제로 보내는 모양

/// `POST /auth/apple` 성공 응답. **서버의 wire format 그대로**다.
///
/// `ServerSession`은 Keychain에 넣는 우리 모델이라 모양이 다르다(`userId` flat).
/// 서버가 `user` 객체 안에 id를 담아 보내므로, 둘을 억지로 같게 만들지 않고 여기서 옮긴다.
/// 이 둘을 같은 타입으로 쓰려다 실기기에서 `decode failure`가 났다.
private nonisolated struct AppleSignInResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresAt: Date
    let user: User

    struct User: Decodable {
        let id: String
    }

    var session: ServerSession {
        ServerSession(accessToken: accessToken, expiresAt: expiresAt, userID: user.id)
    }
}

// MARK: - Client

/// 테스트가 실제 network 없이 흐름을 확인할 수 있도록 protocol을 하나 둔다.
nonisolated protocol AuthBackend: Sendable {
    func signIn(identityToken: String, nonce: String) async throws -> ServerSession
    func verify(accessToken: String) async throws -> String
    func logout(accessToken: String) async throws
}

/// nonisolated — MainActor 밖에서도 만들고 쓸 수 있다.
nonisolated struct BackendClient: AuthBackend {
    /// 기본값은 빌드 설정에서 온다(`AppConfig`). **여기에 주소를 적지 않는다.**
    /// 테스트는 원하는 주소를 넣어 쓴다.
    var baseURL: URL?
    var session: URLSession = .shared

    init(baseURL: URL? = AppConfig.backendBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: 로그인

    func signIn(identityToken: String, nonce: String) async throws -> ServerSession {
        struct Body: Encodable {
            let identityToken: String
            let nonce: String
        }
        let data = try await send(
            "auth/apple",
            method: "POST",
            body: JSONEncoder.backend.encode(Body(identityToken: identityToken, nonce: nonce))
        )
        do {
            let response = try JSONDecoder.backend.decode(AppleSignInResponse.self, from: data)
            BackendLog.event("POST /auth/apple decode success")
            return response.session
        } catch {
            // 200인데 우리가 모르는 모양이다. **로그인됐다고 하지 않는다.**
            BackendLog.event("POST /auth/apple decode failure \(BackendLog.category(error))")
            throw BackendError.unexpected(status: 200)
        }
    }

    /// 저장된 세션이 서버에서도 살아 있는지 확인한다. 살아 있으면 user id.
    func verify(accessToken: String) async throws -> String {
        struct Payload: Decodable { let id: String }
        let data = try await send("users/me", method: "GET", accessToken: accessToken)
        do {
            return try JSONDecoder.backend.decode(Payload.self, from: data).id
        } catch {
            BackendLog.event("GET /users/me decode failure \(BackendLog.category(error))")
            throw BackendError.unexpected(status: 200)
        }
    }

    func logout(accessToken: String) async throws {
        _ = try await send("auth/logout", method: "POST", accessToken: accessToken)
    }

    // MARK: 전송

    private func send(
        _ path: String,
        method: String,
        body: Data? = nil,
        accessToken: String? = nil
    ) async throws -> Data {
        guard let baseURL else { throw BackendError.notConfigured }

        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken {
            // 이 header는 어디에도 기록하지 않는다.
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        BackendLog.event("\(method) /\(path) started")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // 네트워크 자체가 안 됐다. 서버가 거부한 것이 아니다.
            BackendLog.event("\(method) /\(path) network failure")
            throw BackendError.unavailable
        }

        guard let http = response as? HTTPURLResponse else {
            BackendLog.event("\(method) /\(path) not an HTTP response")
            throw BackendError.unavailable
        }
        BackendLog.event("\(method) /\(path) status=\(http.statusCode)")

        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw BackendError.unauthorized
        case 500..<600: throw BackendError.unavailable
        default: throw BackendError.unexpected(status: http.statusCode)
        }
    }
}

// MARK: - 로그

/// **분류와 status만** 남긴다. 요청/응답 본문 · token · nonce · 식별자 · 이메일은 절대 찍지 않는다.
/// `AuthLog`와 같은 규칙이고 DEBUG 빌드에만 나온다.
nonisolated enum BackendLog {
    static func event(_ message: String) {
        #if DEBUG
        print("[Backend] \(message)")
        #endif
    }

    /// decode 실패의 **종류만**. 어떤 key가 비었는지까지는 담지만
    /// 값(본문 · token · 식별자)은 절대 담지 않는다.
    static func category(_ error: any Error) -> String {
        guard let error = error as? DecodingError else { return "type=unknown" }
        return switch error {
        case .keyNotFound(let key, _): "type=keyNotFound key=\(key.stringValue)"
        case .typeMismatch(_, let context): "type=typeMismatch at=\(path(context))"
        case .valueNotFound(_, let context): "type=valueNotFound at=\(path(context))"
        case .dataCorrupted(let context): "type=dataCorrupted at=\(path(context))"
        @unknown default: "type=unknown"
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let keys = context.codingPath.map(\.stringValue)
        return keys.isEmpty ? "root" : keys.joined(separator: ".")
    }
}

// MARK: - JSON

nonisolated extension JSONDecoder {
    /// 서버는 camelCase + ISO8601로 보낸다. `.iso8601`은 소수점 초에서 깨지므로 직접 읽는다.
    static var backend: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let raw = try container.singleValueContainer().decode(String.self)
            guard let date = BackendDate.parse(raw) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: container.codingPath, debugDescription: "bad date")
                )
            }
            return date
        }
        return decoder
    }
}

nonisolated extension JSONEncoder {
    static var backend: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

nonisolated enum BackendDate {
    /// 소수점 초가 있든 없든, `Z`든 `+00:00`이든 읽는다.
    static func parse(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
