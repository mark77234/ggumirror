//
//  BackendContractTests.swift
//  ggumirrorTests
//
//  **서버가 실제로 보내는 JSON**을 그대로 넣고 `BackendClient`를 통과시킨다.
//
//  기존 auth 테스트는 `FakeAuthBackend`가 `ServerSession`을 직접 돌려주는 구조라
//  HTTP 응답 decoding 경계를 한 번도 지나지 않았다. 그래서 서버가 `user.id`를 중첩해 보내는데
//  client가 flat `userId`를 기대하는 불일치를 잡지 못했고, 실기기에서 `decode failure`가 났다.
//  여기서 그 경계를 고정한다.
//

import Foundation
import Testing
@testable import ggumirror

// MARK: - HTTP 대역

/// 원하는 status / body를 그대로 돌려주는 URLProtocol. network를 쓰지 않는다.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var status = 200
        var body: Data = Data()
    }

    nonisolated(unsafe) static var next = Response()
    /// 요청이 실제로 왔는지 확인용. 값은 담지 않는다.
    nonisolated(unsafe) static var requestedPaths: [String] = []

    static func session() -> URLSession {
        next = Response()
        requestedPaths = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestedPaths.append(request.url?.path ?? "")
        let stub = Self.next
        let response = HTTPURLResponse(
            url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// stub이 전역 상태를 쓰므로 **직렬로** 돌린다. 병렬로 돌리면 서로의 응답을 덮는다.
@Suite(.serialized)
struct BackendContractTests {

    // MARK: - 도구

    private func client(status: Int = 200, json: String) -> BackendClient {
        let session = StubURLProtocol.session()
        StubURLProtocol.next = .init(status: status, body: Data(json.utf8))
        return BackendClient(baseURL: URL(string: "https://backend.test")!, session: session)
    }

    /// 서버가 실제로 보내는 성공 응답. Backend `SessionPayload`와 같은 모양이다.
    private func successJSON(
        accessToken: String = "test-token",
        tokenType: String = "Bearer",
        expiresAt: String = "2026-09-10T11:22:33.123456Z",
        userID: String = "internal-user-id"
    ) -> String {
        """
        {"accessToken":"\(accessToken)","tokenType":"\(tokenType)","expiresAt":"\(expiresAt)","user":{"id":"\(userID)"}}
        """
    }

    // MARK: - 성공 경로

    @Test("서버의 실제 성공 응답을 그대로 읽는다")
    func decodesRealSuccessResponse() async throws {
        let session = try await client(json: successJSON()).signIn(identityToken: "t", nonce: "n")

        #expect(session.accessToken == "test-token")
        #expect(session.expiresAt > Date(timeIntervalSince1970: 1_780_000_000))
    }

    @Test("userID는 중첩된 user.id에서 온다")
    func mapsNestedUserID() async throws {
        let session = try await client(json: successJSON(userID: "abc-123")).signIn(identityToken: "t", nonce: "n")
        #expect(session.userID == "abc-123")
    }

    @Test("소수점 초가 있는 시간을 읽는다")
    func decodesFractionalDate() async throws {
        let session = try await client(json: successJSON(expiresAt: "2026-09-10T11:22:33.123456Z"))
            .signIn(identityToken: "t", nonce: "n")
        #expect(session.isValid(at: Date(timeIntervalSince1970: 1_780_000_000)))
    }

    @Test("소수점 초가 없는 시간도 읽는다")
    func decodesPlainDate() async throws {
        let session = try await client(json: successJSON(expiresAt: "2026-09-10T11:22:33Z"))
            .signIn(identityToken: "t", nonce: "n")
        #expect(session.isValid(at: Date(timeIntervalSince1970: 1_780_000_000)))
    }

    @Test("실제로 /auth/apple을 호출한다")
    func callsAuthApple() async throws {
        _ = try await client(json: successJSON()).signIn(identityToken: "t", nonce: "n")
        #expect(StubURLProtocol.requestedPaths == ["/auth/apple"])
    }

    // MARK: - 깨진 응답 (전부 로그인 실패여야 한다)

    @Test("user 객체가 없으면 실패한다")
    func failsWithoutUser() async {
        let json = """
        {"accessToken":"t","tokenType":"Bearer","expiresAt":"2026-09-10T11:22:33Z"}
        """
        await #expect(throws: BackendError.unexpected(status: 200)) {
            try await client(json: json).signIn(identityToken: "t", nonce: "n")
        }
    }

    @Test("user.id가 없으면 실패한다")
    func failsWithoutUserID() async {
        let json = """
        {"accessToken":"t","tokenType":"Bearer","expiresAt":"2026-09-10T11:22:33Z","user":{}}
        """
        await #expect(throws: BackendError.unexpected(status: 200)) {
            try await client(json: json).signIn(identityToken: "t", nonce: "n")
        }
    }

    @Test("accessToken이 없으면 실패한다")
    func failsWithoutAccessToken() async {
        let json = """
        {"tokenType":"Bearer","expiresAt":"2026-09-10T11:22:33Z","user":{"id":"u"}}
        """
        await #expect(throws: BackendError.unexpected(status: 200)) {
            try await client(json: json).signIn(identityToken: "t", nonce: "n")
        }
    }

    @Test("시간이 망가졌으면 실패한다")
    func failsWithMalformedDate() async {
        await #expect(throws: BackendError.unexpected(status: 200)) {
            try await client(json: successJSON(expiresAt: "어제")).signIn(identityToken: "t", nonce: "n")
        }
    }

    @Test("client가 기대하던 예전 flat 모양은 이제 통하지 않는다")
    func rejectsOldFlatShape() async {
        // 이게 버그의 정체였다 — client가 이 모양을 기대했고 서버는 보내지 않았다.
        let json = """
        {"accessToken":"t","expiresAt":"2026-09-10T11:22:33Z","userId":"u"}
        """
        await #expect(throws: BackendError.unexpected(status: 200)) {
            try await client(json: json).signIn(identityToken: "t", nonce: "n")
        }
    }

    // MARK: - status 매핑 (기존 동작 유지)

    @Test("401 / 403은 unauthorized다")
    func mapsUnauthorized() async {
        for status in [401, 403] {
            await #expect(throws: BackendError.unauthorized) {
                try await client(status: status, json: "{}").signIn(identityToken: "t", nonce: "n")
            }
        }
    }

    @Test("5xx는 unavailable이다")
    func mapsServerError() async {
        for status in [500, 502, 503] {
            await #expect(throws: BackendError.unavailable) {
                try await client(status: status, json: "{}").signIn(identityToken: "t", nonce: "n")
            }
        }
    }

    @Test("그 밖의 status는 unexpected다")
    func mapsOther() async {
        await #expect(throws: BackendError.unexpected(status: 422)) {
            try await client(status: 422, json: "{}").signIn(identityToken: "t", nonce: "n")
        }
    }

    // MARK: - /users/me

    @Test("users/me도 실제 모양을 읽는다")
    func decodesUsersMe() async throws {
        let id = try await client(json: #"{"id":"internal-user-id"}"#).verify(accessToken: "token")
        #expect(id == "internal-user-id")
        #expect(StubURLProtocol.requestedPaths == ["/users/me"])
    }

    @Test("users/me가 깨졌으면 실패한다")
    func failsBrokenUsersMe() async {
        await #expect(throws: BackendError.unexpected(status: 200)) {
            try await client(json: #"{"nope":1}"#).verify(accessToken: "token")
        }
    }

    @Test("logout은 204를 성공으로 본다")
    func logoutSucceeds() async throws {
        try await client(status: 204, json: "").logout(accessToken: "token")
        #expect(StubURLProtocol.requestedPaths == ["/auth/logout"])
    }

    // MARK: - 로그

    @Test("decode 분류 로그에 값이 들어가지 않는다")
    func logCategoryHasNoValues() {
        // keyNotFound는 어떤 key가 비었는지까지만 알려준다. 값은 담지 않는다.
        let missing = DecodingError.keyNotFound(
            AnyKey(stringValue: "accessToken")!,
            .init(codingPath: [], debugDescription: "secret-token-value")
        )
        let text = BackendLog.category(missing)
        #expect(text.contains("keyNotFound"))
        #expect(text.contains("accessToken"))
        #expect(!text.contains("secret-token-value"))

        let corrupted = DecodingError.dataCorrupted(
            .init(codingPath: [AnyKey(stringValue: "expiresAt")!], debugDescription: "bad-value-here")
        )
        let corruptedText = BackendLog.category(corrupted)
        #expect(corruptedText.contains("dataCorrupted"))
        #expect(!corruptedText.contains("bad-value-here"))
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
        init?(intValue: Int) { self.intValue = intValue; stringValue = "\(intValue)" }
    }
}
