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

    func session(isGuest: Bool = false) -> ServerSession {
        ServerSession(
            accessToken: accessToken, expiresAt: expiresAt, userID: user.id, isGuest: isGuest
        )
    }
}

// MARK: - Client

/// 테스트가 실제 network 없이 흐름을 확인할 수 있도록 protocol을 하나 둔다.
nonisolated protocol AuthBackend: Sendable {
    /// 로그인 없이 쓰는 익명 세션. **client가 user id를 만들지 않는다** — 서버가 발급한다.
    /// `renewing`에 아직 살아 있는 guest token을 주면 **같은 지갑**으로 연장된다.
    func startGuest(renewing: String?) async throws -> ServerSession
    func signIn(
        identityToken: String, nonce: String, displayName: String?, guestAccessToken: String?
    ) async throws -> ServerSession
    func verify(accessToken: String) async throws -> String
    func logout(accessToken: String) async throws
}

/// nonisolated — MainActor 밖에서도 만들고 쓸 수 있다.
nonisolated struct BackendClient: AuthBackend, ShardBackend, ShardPurchaseBackend {
    /// 기본값은 빌드 설정에서 온다(`AppConfig`). **여기에 주소를 적지 않는다.**
    /// 테스트는 원하는 주소를 넣어 쓴다.
    var baseURL: URL?
    var session: URLSession = .shared

    init(baseURL: URL? = AppConfig.backendBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: 로그인

    /// - Parameter displayName: Apple이 **최초 authorization에서만** 줄 수 있는 이름.
    ///   없으면 보내지 않는다 — 서버에서 optional이라 예전 모양 그대로 통한다.
    ///   이 값은 서명된 claim이 아니므로 서버도 신원 판단에 쓰지 않고, 아직 이름이
    ///   없을 때 첫 값을 채우는 데만 쓴다.
    /// 익명 세션 발급. **body가 없다** — 이름 · 이메일 · 어떤 개인정보도 보내지 않는다.
    ///
    /// - Parameter renewing: 아직 살아 있는 guest token. 있으면 서버가 **같은 사용자**에게
    ///   새 session을 준다 — 만료로 지갑을 잃지 않게.
    func startGuest(renewing: String? = nil) async throws -> ServerSession {
        let data = try await send("auth/guest", method: "POST", accessToken: renewing)
        do {
            let response = try JSONDecoder.backend.decode(AppleSignInResponse.self, from: data)
            BackendLog.event("POST /auth/guest decode success")
            return response.session(isGuest: true)
        } catch {
            BackendLog.event("POST /auth/guest decode failure \(BackendLog.category(error))")
            throw BackendError.unexpected(status: 200)
        }
    }

    /// - Parameter guestAccessToken: 아직 로그인 전에 쓰던 익명 세션. 있으면 함께 보낸다 —
    ///   서버가 그 지갑을 이 계정으로 넘긴다. **client가 잔액을 옮기지 않는다.**
    func signIn(
        identityToken: String, nonce: String, displayName: String? = nil,
        guestAccessToken: String? = nil
    ) async throws -> ServerSession {
        struct Body: Encodable {
            let identityToken: String
            let nonce: String
            /// `nil`이면 JSON에서 아예 빠진다(`JSONEncoder` 기본 동작).
            let displayName: String?
        }
        let data = try await send(
            "auth/apple",
            method: "POST",
            body: JSONEncoder.backend.encode(
                Body(identityToken: identityToken, nonce: nonce, displayName: displayName)
            ),
            accessToken: guestAccessToken
        )
        do {
            let response = try JSONDecoder.backend.decode(AppleSignInResponse.self, from: data)
            BackendLog.event("POST /auth/apple decode success")
            return response.session()
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

    // MARK: 조각

    /// 내 조각 잔액. **읽기뿐이다** — 잔액을 바꾸는 요청은 client에서 만들지 않는다.
    func shards(accessToken: String) async throws -> ShardBalance {
        let data = try await send("users/me/shards", method: "GET", accessToken: accessToken)
        do {
            return try JSONDecoder.backend.decode(ShardBalance.self, from: data)
        } catch {
            BackendLog.event("GET /users/me/shards decode failure \(BackendLog.category(error))")
            throw BackendError.unexpected(status: 200)
        }
    }

    // MARK: 출석

    /// 오늘 조각을 받을 수 있는지. 날짜 판단은 **서버**가 한다.
    func attendance(accessToken: String) async throws -> AttendanceStatus {
        let data = try await send("users/me/attendance", method: "GET", accessToken: accessToken)
        do {
            return try JSONDecoder.backend.decode(AttendanceStatus.self, from: data)
        } catch {
            BackendLog.event("GET /users/me/attendance decode failure \(BackendLog.category(error))")
            throw BackendError.unexpected(status: 200)
        }
    }

    /// 오늘의 조각 받기. **body를 보내지 않는다** —
    /// userId · date · amount · reason을 client가 정하는 자리를 만들지 않는다.
    func claimAttendance(accessToken: String) async throws -> AttendanceClaim {
        let data = try await send("users/me/attendance", method: "POST", accessToken: accessToken)
        do {
            return try JSONDecoder.backend.decode(AttendanceClaim.self, from: data)
        } catch {
            BackendLog.event("POST /users/me/attendance decode failure \(BackendLog.category(error))")
            throw BackendError.unexpected(status: 200)
        }
    }

    // MARK: 광고 보상

    /// 오늘 광고 보상을 몇 번 받았는지. **읽기뿐이다.**
    func rewardedAds(accessToken: String) async throws -> RewardedAdStatus {
        let data = try await send("users/me/rewarded-ads", method: "GET", accessToken: accessToken)
        do {
            return try JSONDecoder.backend.decode(RewardedAdStatus.self, from: data)
        } catch {
            BackendLog.event("GET /users/me/rewarded-ads decode failure \(BackendLog.category(error))")
            throw BackendError.unexpected(status: 200)
        }
    }

    /// 광고에 실어 보낼 opaque context를 받아온다.
    ///
    /// **조각을 지급하는 요청이 아니다.** 지급은 Google이 서명한 SSV callback이
    /// 서버에 도착했을 때만 일어난다. 여기서 받은 값은 "누구의 광고인지"를 가리킬 뿐이고,
    /// session token 대신 이것을 보내기 때문에 callback URL에 로그인 정보가 남지 않는다.
    func rewardedAdContext(accessToken: String) async throws -> String {
        struct Payload: Decodable { let context: String }
        let data = try await send(
            "users/me/rewarded-ads/context", method: "POST", accessToken: accessToken
        )
        do {
            return try JSONDecoder.backend.decode(Payload.self, from: data).context
        } catch {
            BackendLog.event("POST /users/me/rewarded-ads/context decode failure \(BackendLog.category(error))")
            throw BackendError.unexpected(status: 200)
        }
    }

    // MARK: AI 스티커

    /// AI 스티커를 지금 쓸 수 있는지와 몇 조각인지. **조각을 움직이지 않는 읽기다.**
    ///
    /// 가격을 client가 알고 있지 않다 — 서버가 말해 주는 값을 그대로 쓴다.
    func aiStickerConfig(accessToken: String) async throws -> AIStickerConfig {
        let data = try await send("ai/stickers/config", method: "GET", accessToken: accessToken)
        do {
            return try JSONDecoder.backend.decode(AIStickerConfig.self, from: data)
        } catch {
            BackendLog.event("GET /ai/stickers/config decode failure \(BackendLog.category(error))")
            throw BackendError.unexpected(status: 200)
        }
    }

    /// 스티커 생성을 **시작하거나 이어받는다.**
    ///
    /// `requestId`가 같으면 서버는 새로 만들지 않고 그 작업의 지금 상태를 돌려준다 —
    /// 응답을 잃었을 때 조각을 또 쓰지 않고 복구하는 유일한 방법이다.
    /// 이어받을 때는 `prompt`를 비워 보낸다(서버도 우리도 원문을 들고 있지 않다).
    ///
    /// **응답에 이미지가 없다.** 성공했으면 `aiStickerImage`로 따로 받는다 —
    /// 그래야 응답을 잃어도 그림이 사라지지 않는다.
    func generateAISticker(
        requestID: String, prompt: String, accessToken: String
    ) async throws -> AIGeneration {
        struct Body: Encodable {
            let requestId: String
            let prompt: String
        }
        let data = try await send(
            "ai/stickers",
            method: "POST",
            body: try JSONEncoder.backend.encode(Body(requestId: requestID, prompt: prompt)),
            accessToken: accessToken,
            interpretFailure: Self.aiFailure,
            // 그림 한 장에 수십 초가 걸린다. 기본 15초로는 **정상 생성도 끊긴다.**
            // 끊겨도 작업은 서버에 남아 있어 다시 확인할 수 있다.
            timeout: 200
        )
        return try Self.decodeGeneration(data, path: "POST /ai/stickers")
    }

    // MARK: 조각 IAP

    /// Apple이 서명한 결제를 조각으로 바꾼다.
    ///
    /// **보내는 것은 서명된 transaction 하나뿐이다** — 수량 · 가격 · productId · userId를
    /// 실을 자리가 없다. 지급 수량은 서버 catalog가 정하고, 결제의 주인은 서명 안의
    /// `appAccountToken`으로 서버가 판단한다.
    ///
    /// 같은 거래를 다시 보내도 지급은 한 번이다(서버 전역 멱등). 그때는 `credited=false`이고
    /// **실패가 아니다** — `balance`는 정상 현재 잔액이다.
    func creditIAPShards(
        signedTransaction: String, accessToken: String
    ) async throws -> ShardPurchaseReceipt {
        struct Body: Encodable {
            let signedTransaction: String
        }
        let data = try await send(
            "users/me/iap/shards",
            method: "POST",
            body: try JSONEncoder.backend.encode(Body(signedTransaction: signedTransaction)),
            accessToken: accessToken
        )
        do {
            return try JSONDecoder.backend.decode(ShardPurchaseReceipt.self, from: data)
        } catch {
            // 응답을 못 읽으면 **성공으로 보지 않는다** — 호출부가 finish하지 않게 던진다.
            // 새 case를 만들지 않고 기존 `unavailable`을 쓴다(재시도 가능한 실패다).
            throw BackendError.unavailable
        }
    }

    /// 작업 상태를 다시 묻는다. 앱을 껐다 켠 뒤의 복구가 쓴다.
    func aiStickerStatus(generationID: String, accessToken: String) async throws -> AIGeneration {
        let data = try await send(
            "ai/stickers/\(generationID)",
            method: "GET",
            accessToken: accessToken,
            interpretFailure: Self.aiFailure
        )
        return try Self.decodeGeneration(data, path: "GET /ai/stickers/{id}")
    }

    /// 결과 PNG. **Bearer로 우리 서버에서 직접 받는다** — signed URL을 쓰지 않는다.
    func aiStickerImage(generationID: String, accessToken: String) async throws -> Data {
        try await send(
            "ai/stickers/\(generationID)/image",
            method: "GET",
            accessToken: accessToken,
            interpretFailure: Self.aiFailure,
            timeout: 60
        )
    }

    private static func decodeGeneration(_ data: Data, path: String) throws -> AIGeneration {
        do {
            return try JSONDecoder.backend.decode(AIGeneration.self, from: data)
        } catch {
            BackendLog.event("\(path) decode failure \(BackendLog.category(error))")
            throw AIStickerFailure.failed
        }
    }

    /// 서버가 보낸 `reason`을 사용자가 할 수 있는 일로 옮긴다.
    /// **본문 문구를 그대로 믿지 않고** 우리가 아는 reason만 구분한다.
    static func aiFailure(status: Int, data: Data) -> Error {
        struct Envelope: Decodable {
            struct Detail: Decodable {
                let reason: String
                let message: String
            }
            let detail: Detail
        }
        guard status != 401, status != 403 else { return AIStickerFailure.notSignedIn }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return status >= 500 ? AIStickerFailure.unavailable : AIStickerFailure.failed
        }
        return switch envelope.detail.reason {
        case "insufficient_shards": AIStickerFailure.insufficientShards
        case "empty_prompt", "prompt_too_long", "invalid_request_id", "provider_rejected":
            AIStickerFailure.badPrompt(envelope.detail.message)
        case "not_configured", "provider_unavailable": AIStickerFailure.unavailable
        case "still_pending": AIStickerFailure.stillPending
        // 조각이 돌아온 실패다. "돌려드렸어요"까지 서버 문구를 그대로 쓴다.
        case "storage_failed", "interrupted": AIStickerFailure.refunded(envelope.detail.message)
        case "result_expired": AIStickerFailure.resultExpired
        default: AIStickerFailure.failed
        }
    }

    // MARK: 전송

    private func send(
        _ path: String,
        method: String,
        body: Data? = nil,
        /// query string. **path에 `?`를 직접 붙이지 않는다** — 아래에서 따로 붙인다.
        query: [URLQueryItem] = [],
        /// 본문 형식. 기본은 JSON이고, 상점 snapshot 업로드만 multipart를 쓴다.
        contentType: String = "application/json",
        accessToken: String? = nil,
        /// 2xx가 아닌 응답을 **본문까지 보고** 해석해야 하는 경로가 쓴다.
        /// 주지 않으면 기존과 똑같이 status만으로 판단한다.
        interpretFailure: ((Int, Data) -> Error)? = nil,
        /// 기본 15초. 조회 요청은 이보다 오래 걸릴 이유가 없다.
        timeout: TimeInterval = 15
    ) async throws -> Data {
        guard let baseURL else { throw BackendError.notConfigured }

        // **query를 path 문자열에 넣지 않는다.** `appending(path:)`는 `?`를 `%3F`로
        // 인코딩해서 query가 경로의 일부가 되어 버린다(B-7H에서 발견).
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url = url.appending(queryItems: query) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
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

        if (200..<300).contains(http.statusCode) { return data }
        // 본문까지 봐야 하는 경로(AI 스티커)는 자기가 해석한다. 나머지는 status만으로 판단한다.
        if let interpretFailure { throw interpretFailure(http.statusCode, data) }

        switch http.statusCode {
        case 401, 403: throw BackendError.unauthorized
        case 500..<600: throw BackendError.unavailable
        default: throw BackendError.unexpected(status: http.statusCode)
        }
    }
}

nonisolated extension BackendClient {
    /// 상점 확장(`BackendClient+Marketplace`)이 같은 transport를 쓰기 위한 창구.
    ///
    /// **`send`를 그대로 재사용한다** — Bearer 주입 · timeout · 로깅 규칙이 한 곳에만
    /// 있어야 화면마다 header를 조립하는 일이 생기지 않는다.
    func request(
        _ path: String,
        method: String,
        body: Data? = nil,
        query: [URLQueryItem] = [],
        contentType: String = "application/json",
        accessToken: String? = nil,
        interpretFailure: ((Int, Data) -> Error)? = nil,
        timeout: TimeInterval = 15
    ) async throws -> Data {
        try await send(
            path,
            method: method,
            body: body,
            query: query,
            contentType: contentType,
            accessToken: accessToken,
            interpretFailure: interpretFailure,
            timeout: timeout
        )
    }
}

/// URL 경로 조각으로 써도 되는가.
///
/// 경로를 벗어나게 만드는 문자를 거른다. **오류 타입은 호출부가 정한다** —
/// 상점과 catalog가 사용자에게 다른 말을 해야 하기 때문에 여기서 던지지 않는다.
nonisolated func isSafePathComponent(_ component: String) -> Bool {
    !component.isEmpty
        && !component.contains("/")
        && !component.contains("\\")
        && component != "."
        && component != ".."
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
