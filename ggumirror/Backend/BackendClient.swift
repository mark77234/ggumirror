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

// MARK: - 주소

/// API 주소. 여러 파일에 흩뿌리지 않고 여기 한 곳에서만 정한다.
///
/// **가짜 production URL을 만들지 않는다.** Cloud Run 주소가 아직 없으므로
/// release 빌드에는 주소가 없고, 그 상태에서 서버 로그인은 "지금은 안 된다"로 실패한다.
/// 배포 Phase에서 `production`에 실제 주소를 넣으면 그때부터 동작한다.
nonisolated enum BackendEnvironment {
    /// 개발용. 시뮬레이터에서 로컬 서버(`uvicorn --port 8080`)에 붙는다.
    static let development = URL(string: "http://127.0.0.1:8080")!

    /// 아직 없다. 배포 Phase에서 채운다.
    static let production: URL? = nil

    static var current: URL? {
        #if DEBUG
        development
        #else
        production
        #endif
    }
}

// MARK: - 오류

nonisolated enum BackendError: Error, Equatable {
    /// 서버 주소가 아직 없다(release + 미배포).
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
            "서버 로그인은 아직 준비 중이에요. 꾸미기는 그대로 쓸 수 있어요."
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

// MARK: - Client

/// 테스트가 실제 network 없이 흐름을 확인할 수 있도록 protocol을 하나 둔다.
nonisolated protocol AuthBackend: Sendable {
    func signIn(identityToken: String, nonce: String) async throws -> ServerSession
    func verify(accessToken: String) async throws -> String
    func logout(accessToken: String) async throws
}

/// nonisolated — MainActor 밖에서도 만들고 쓸 수 있다.
nonisolated struct BackendClient: AuthBackend {
    var baseURL: URL?
    var session: URLSession = .shared

    init(baseURL: URL? = BackendEnvironment.current, session: URLSession = .shared) {
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
            return try JSONDecoder.backend.decode(ServerSession.self, from: data)
        } catch {
            // 200인데 우리가 모르는 모양이다. 로그인됐다고 하지 않는다.
            throw BackendError.unexpected(status: 200)
        }
    }

    /// 저장된 세션이 서버에서도 살아 있는지 확인한다. 살아 있으면 user id.
    func verify(accessToken: String) async throws -> String {
        struct Payload: Decodable { let id: String }
        let data = try await send("users/me", method: "GET", accessToken: accessToken)
        guard let payload = try? JSONDecoder.backend.decode(Payload.self, from: data) else {
            throw BackendError.unexpected(status: 200)
        }
        return payload.id
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // 네트워크 자체가 안 됐다. 서버가 거부한 것이 아니다.
            throw BackendError.unavailable
        }

        guard let http = response as? HTTPURLResponse else { throw BackendError.unavailable }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw BackendError.unauthorized
        case 500..<600: throw BackendError.unavailable
        default: throw BackendError.unexpected(status: http.statusCode)
        }
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
