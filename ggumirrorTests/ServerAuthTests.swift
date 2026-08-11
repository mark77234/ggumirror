//
//  ServerAuthTests.swift
//  ggumirrorTests
//
//  Apple 인증 → Backend 세션 → Keychain 흐름.
//
//  실제 network도, 실제 Apple UI도 쓰지 않는다 — `FakeAuthBackend`가 서버 경계를 대신한다.
//
//  여기서 지키는 것:
//  1. Apple UI 통과만으로 서버 로그인이 되지 않는다.
//  2. nonce는 시도마다 새로 만들고, 저장하지 않고, 한 번만 쓴다.
//  3. 서버가 안 되든 401이든, **사용자 콘텐츠를 지우지 않는다.**
//

import Foundation
import Testing
@testable import ggumirror

// MARK: - 서버 대역

/// 서버 응답을 원하는 대로 고정하는 가짜 Backend.
final class FakeAuthBackend: AuthBackend, @unchecked Sendable {
    enum Outcome {
        case success(ServerSession)
        case failure(BackendError)
    }

    var signInOutcome: Outcome
    var verifyOutcome: Outcome
    var logoutError: BackendError?

    /// 서버가 실제로 받은 값. nonce가 정말 전달되는지 확인하는 데 쓴다.
    private(set) var receivedIdentityTokens: [String] = []
    private(set) var receivedNonces: [String] = []
    private(set) var logoutCount = 0

    init(
        signInOutcome: Outcome = .success(
            ServerSession(
                accessToken: "server-token-1",
                expiresAt: Date(timeIntervalSinceNow: 30 * 86_400),
                userID: "internal-user-1"
            )
        )
    ) {
        self.signInOutcome = signInOutcome
        self.verifyOutcome = signInOutcome
    }

    func signIn(identityToken: String, nonce: String) async throws -> ServerSession {
        receivedIdentityTokens.append(identityToken)
        receivedNonces.append(nonce)
        switch signInOutcome {
        case .success(let session): return session
        case .failure(let error): throw error
        }
    }

    func verify(accessToken: String) async throws -> String {
        switch verifyOutcome {
        case .success(let session): return session.userID
        case .failure(let error): throw error
        }
    }

    func logout(accessToken: String) async throws {
        logoutCount += 1
        if let logoutError { throw logoutError }
    }
}

@MainActor
struct ServerAuthTests {

    // MARK: - 도구

    nonisolated private struct StubCredentials: AppleCredentialChecking {
        func state(for userID: String) async -> AppleCredentialState { .authorized }
    }

    private func makeSession(
        identity: AppleIdentity? = nil,
        stored: ServerSession? = nil,
        backend: FakeAuthBackend = FakeAuthBackend()
    ) -> (AuthSession, InMemoryIdentityStore, InMemoryServerSessionStore, FakeAuthBackend) {
        let identities = InMemoryIdentityStore(identity)
        let sessions = InMemoryServerSessionStore(stored)
        let auth = AuthSession(
            store: identities,
            sessions: sessions,
            credentials: StubCredentials(),
            backend: backend
        )
        return (auth, identities, sessions, backend)
    }

    private func appleResult(userID: String = "apple-user-1") -> AppleSignInResult {
        AppleSignInResult(
            userID: userID,
            displayName: "병찬",
            email: "mirror@example.com",
            identityToken: Data("apple.identity.token".utf8),
            authorizationCode: Data("apple-auth-code".utf8)
        )
    }

    /// 거울 하나 + 스티커 하나가 들어 있는 임시 저장소.
    private func withContent(
        _ body: (MirrorLibrary, StickerLibrary, MirrorStore, StickerProjectStore) async throws -> Void
    ) async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-b2b-\(UUID().uuidString)", directoryHint: .isDirectory)
        let mirrorStore = MirrorStore(root: root)
        let stickerStore = StickerProjectStore(root: root)
        defer {
            mirrorStore.flush()
            stickerStore.flush()
            try? FileManager().removeItem(at: root)
        }

        let mirrors = MirrorLibrary(store: mirrorStore, artworks: ImportedArtworkAssetStore())
        _ = mirrors.save(MirrorDesign.blank, name: "지켜야 하는 거울", context: .createNew)
        let stickers = StickerLibrary(store: stickerStore)
        _ = stickers.save(MirrorDesign.blankSticker(id: "s1", name: "내 스티커"), name: "내 스티커", context: .createNew)

        try await body(mirrors, stickers, mirrorStore, stickerStore)
    }

    private func signIn(_ auth: AuthSession, _ result: AppleSignInResult? = nil) async {
        _ = auth.beginSignIn()
        await auth.complete(.success(result ?? appleResult()))
    }

    // MARK: - nonce

    @Test("로그인 시도마다 nonce를 새로 만든다")
    func nonceGeneratedPerAttempt() {
        let (auth, _, _, _) = makeSession()
        let first = auth.beginSignIn()
        #expect(!first.isEmpty)
        // SHA-256 16진수 = 64자.
        #expect(first.count == 64)
        #expect(first.allSatisfy { $0.isHexDigit })
    }

    @Test("서로 다른 시도는 서로 다른 nonce를 쓴다")
    func attemptsUseDifferentNonces() {
        let (auth, _, _, _) = makeSession()
        let nonces = (0..<5).map { _ in auth.beginSignIn() }
        #expect(Set(nonces).count == 5)
    }

    @Test("Apple에 보내는 값은 원본이 아니라 SHA-256이다")
    func appleReceivesHashNotRawNonce() {
        let nonce = AppleNonce(raw: "abc")
        // "abc"의 SHA-256.
        #expect(nonce.hashedForApple == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(nonce.hashedForApple != nonce.raw)
    }

    @Test("취소하면 nonce를 버린다")
    func cancelDiscardsNonce() async {
        let (auth, _, _, backend) = makeSession()
        _ = auth.beginSignIn()
        await auth.complete(.cancelled)

        // 버려졌으므로 뒤늦게 온 credential로는 로그인되지 않는다.
        await auth.complete(.success(appleResult()))
        #expect(!auth.state.isSignedIn)
        #expect(backend.receivedNonces.isEmpty)
    }

    @Test("실패해도 nonce를 버린다")
    func failureDiscardsNonce() async {
        let (auth, _, _, backend) = makeSession()
        _ = auth.beginSignIn()
        await auth.complete(.failed("오류"))
        await auth.complete(.success(appleResult()))
        #expect(backend.receivedNonces.isEmpty)
    }

    @Test("성공하면 identityToken과 nonce 원본을 서버에 보낸다")
    func sendsTokenAndNonce() async {
        let (auth, _, _, backend) = makeSession()
        _ = auth.beginSignIn()
        await auth.complete(.success(appleResult()))

        #expect(backend.receivedIdentityTokens == ["apple.identity.token"])
        #expect(backend.receivedNonces.count == 1)
        #expect(!backend.receivedNonces[0].isEmpty)
    }

    @Test("nonce는 한 번만 쓰인다")
    func nonceIsSingleUse() async {
        let (auth, _, _, backend) = makeSession()
        await signIn(auth)
        // 두 번째 credential은 nonce 없이 왔다 — 서버로 가지 않는다.
        await auth.complete(.success(appleResult()))
        #expect(backend.receivedNonces.count == 1)
    }

    @Test("nonce는 어디에도 저장되지 않는다")
    func nonceNeverPersisted() async {
        let (auth, identities, sessions, backend) = makeSession()
        await signIn(auth)
        let raw = backend.receivedNonces[0]

        let identityJSON = try? JSONEncoder().encode(identities.load())
        let sessionJSON = try? JSONEncoder().encode(sessions.load())
        #expect(!(identityJSON.map { String(decoding: $0, as: UTF8.self).contains(raw) } ?? false))
        #expect(!(sessionJSON.map { String(decoding: $0, as: UTF8.self).contains(raw) } ?? false))
    }

    // MARK: - 서버 세션

    @Test("서버 인증이 끝나야 로그인이다")
    func serverAuthRequiredForSignedIn() async {
        let backend = FakeAuthBackend(signInOutcome: .failure(.unauthorized))
        let (auth, _, sessions, _) = makeSession(backend: backend)
        await signIn(auth)

        #expect(!auth.state.isSignedIn)
        #expect(auth.server == nil)
        #expect(sessions.load() == nil)
        #expect(auth.failureMessage != nil)
    }

    @Test("성공하면 서버 세션을 Keychain 저장소에 넣는다")
    func storesServerSession() async {
        let (auth, _, sessions, _) = makeSession()
        await signIn(auth)

        #expect(auth.state.isSignedIn)
        #expect(auth.server?.userID == "internal-user-1")
        #expect(sessions.load()?.accessToken == "server-token-1")
    }

    @Test("Apple token / authorizationCode / accessToken은 identity 저장소에 들어가지 않는다")
    func credentialsNotPersistedInIdentity() async throws {
        let (auth, identities, _, _) = makeSession()
        await signIn(auth)

        let json = String(decoding: try JSONEncoder().encode(identities.load()), as: UTF8.self)
        #expect(!json.contains("apple.identity.token"))
        #expect(!json.contains("apple-auth-code"))
        #expect(!json.contains("server-token-1"))
    }

    @Test("서버 세션 저장소에는 accessToken / 만료 / internal userID만 들어간다")
    func sessionStoresOnlyWhatItNeeds() async throws {
        let (auth, _, sessions, _) = makeSession()
        await signIn(auth)

        let json = String(decoding: try JSONEncoder().encode(sessions.load()), as: UTF8.self)
        #expect(json.contains("server-token-1"))
        #expect(!json.contains("apple.identity.token"))
        #expect(!json.contains("apple-auth-code"))
        // Apple 식별자도 서버 세션에 섞지 않는다.
        #expect(!json.contains("apple-user-1"))
    }

    // MARK: - 복원

    @Test("유효한 서버 세션이 있으면 로그인 상태로 복원된다")
    func validSessionRestores() {
        let (auth, _, _, _) = makeSession(
            identity: AppleIdentity(userID: "apple-user-1", displayName: "병찬"),
            stored: ServerSession(
                accessToken: "saved",
                expiresAt: Date(timeIntervalSinceNow: 3600),
                userID: "internal-user-1"
            )
        )
        #expect(auth.state.isSignedIn)
        #expect(auth.server?.accessToken == "saved")
    }

    @Test("만료된 세션은 로그인으로 복원하지 않는다")
    func expiredSessionDoesNotRestore() {
        let (auth, identities, _, _) = makeSession(
            identity: AppleIdentity(userID: "apple-user-1"),
            stored: ServerSession(
                accessToken: "old",
                expiresAt: Date(timeIntervalSinceNow: -60),
                userID: "internal-user-1"
            )
        )
        #expect(!auth.state.isSignedIn)
        #expect(auth.server == nil)
        // Apple identity는 남는다 — Apple이 이름 / 이메일을 다시 주지 않기 때문이다.
        #expect(identities.load()?.userID == "apple-user-1")
    }

    @Test("서버 세션이 없으면 Apple identity만으로 로그인하지 않는다")
    func identityWithoutSessionIsSignedOut() {
        let (auth, _, _, _) = makeSession(identity: AppleIdentity(userID: "apple-user-1"))
        #expect(!auth.state.isSignedIn)
    }

    @Test("서버가 세션을 거부하면 로그아웃 상태가 된다")
    func rejectedSessionSignsOut() async {
        let backend = FakeAuthBackend()
        backend.verifyOutcome = .failure(.unauthorized)
        let (auth, identities, sessions, _) = makeSession(
            identity: AppleIdentity(userID: "apple-user-1"),
            stored: ServerSession(
                accessToken: "saved",
                expiresAt: Date(timeIntervalSinceNow: 3600),
                userID: "internal-user-1"
            ),
            backend: backend
        )
        await auth.refreshServerSession()

        #expect(!auth.state.isSignedIn)
        #expect(sessions.load() == nil)
        #expect(identities.load() != nil)
    }

    @Test("서버가 안 될 때는 세션을 그대로 둔다")
    func unavailableServerKeepsSession() async {
        let backend = FakeAuthBackend()
        backend.verifyOutcome = .failure(.unavailable)
        let (auth, _, sessions, _) = makeSession(
            identity: AppleIdentity(userID: "apple-user-1"),
            stored: ServerSession(
                accessToken: "saved",
                expiresAt: Date(timeIntervalSinceNow: 3600),
                userID: "internal-user-1"
            ),
            backend: backend
        )
        await auth.refreshServerSession()

        #expect(auth.state.isSignedIn)
        #expect(sessions.load() != nil)
    }

    // MARK: - 서버 오류

    @Test("401이면 로그인되지 않고 이해 가능한 오류를 보여준다")
    func handlesUnauthorized() async {
        let (auth, _, _, _) = makeSession(backend: FakeAuthBackend(signInOutcome: .failure(.unauthorized)))
        await signIn(auth)
        #expect(auth.failureMessage == BackendError.unauthorized.message)
        #expect(!auth.state.isSignedIn)
    }

    @Test("503이면 잠시 뒤 다시 시도하라고 알린다")
    func handlesUnavailable() async {
        let (auth, _, _, _) = makeSession(backend: FakeAuthBackend(signInOutcome: .failure(.unavailable)))
        await signIn(auth)
        #expect(auth.failureMessage == BackendError.unavailable.message)
        #expect(BackendError.unavailable.isTemporary)
    }

    @Test("서버 주소가 없으면 서버 로그인만 실패한다")
    func handlesNotConfigured() async {
        let (auth, _, _, _) = makeSession(backend: FakeAuthBackend(signInOutcome: .failure(.notConfigured)))
        await signIn(auth)
        #expect(auth.failureMessage == BackendError.notConfigured.message)
        #expect(!auth.state.isSignedIn)
    }

    @Test("network 실패가 사용자 콘텐츠를 지우지 않는다")
    func networkFailureKeepsContent() async throws {
        try await withContent { mirrors, stickers, mirrorStore, stickerStore in
            let (auth, _, _, _) = makeSession(
                backend: FakeAuthBackend(signInOutcome: .failure(.unavailable))
            )
            await signIn(auth)

            #expect(!auth.state.isSignedIn)
            #expect(mirrors.mirrors.count == 1)
            #expect(stickers.projects.count == 1)

            // 파일에서 다시 읽어도 그대로다.
            mirrorStore.flush()
            stickerStore.flush()
            #expect(MirrorLibrary(store: mirrorStore).mirrors.count == 1)
            #expect(StickerLibrary(store: stickerStore).projects.count == 1)
        }
    }

    // MARK: - 로그아웃

    @Test("로그아웃하면 서버 세션과 Apple identity를 지운다")
    func logoutClearsBoth() async {
        let (auth, identities, sessions, backend) = makeSession()
        await signIn(auth)
        await auth.signOut()

        #expect(auth.server == nil)
        #expect(sessions.load() == nil)
        #expect(identities.load() == nil)
        #expect(auth.state == .signedOut)
        #expect(backend.logoutCount == 1)
    }

    @Test("서버에 알리지 못해도 로컬 로그아웃은 진행한다")
    func logoutSurvivesNetworkFailure() async {
        let backend = FakeAuthBackend()
        backend.logoutError = .unavailable
        let (auth, identities, sessions, _) = makeSession(backend: backend)
        await signIn(auth)
        await auth.signOut()

        #expect(auth.state == .signedOut)
        #expect(sessions.load() == nil)
        #expect(identities.load() == nil)
    }

    @Test("로그아웃이 거울 / 스티커 / 등록 준비를 지우지 않는다")
    func logoutPreservesContent() async throws {
        try await withContent { mirrors, stickers, mirrorStore, stickerStore in
            let mirrorID = try #require(mirrors.mirrors.first?.id)
            mirrors.savePublishDraft(MirrorPublishDraft(mirrorID: mirrorID, title: "제목"))
            let project = try #require(stickers.projects.first)
            stickers.saveDraft(StickerPublishDraft(stickerProjectID: project.id, title: "스티커 제목"))

            let (auth, _, _, _) = makeSession()
            await signIn(auth)
            await auth.signOut()

            #expect(auth.state == .signedOut)

            mirrorStore.flush()
            stickerStore.flush()
            let reloadedMirrors = MirrorLibrary(store: mirrorStore)
            #expect(reloadedMirrors.mirrors.count == 1)
            #expect(reloadedMirrors.publishDraft(for: mirrorID) != nil)
            let reloadedStickers = StickerLibrary(store: stickerStore)
            #expect(reloadedStickers.projects.count == 1)
            #expect(reloadedStickers.draft(for: project.id) != nil)
        }
    }

    // MARK: - Auth Gate

    @Test("서버 인증 전에는 pending action을 이어받지 못한다")
    func gateWaitsForServerAuth() async {
        let (auth, _, _, _) = makeSession(backend: FakeAuthBackend(signInOutcome: .failure(.unavailable)))
        #expect(!auth.requireSignIn(for: .publish(mirrorID: "m1")))
        await signIn(auth)

        #expect(!auth.state.isSignedIn)
        #expect(auth.takePendingAction() == nil)
        #expect(auth.pendingAction == .publish(mirrorID: "m1"))
    }

    @Test("서버 인증이 끝나면 pending action을 이어받는다")
    func gateReleasesAfterServerAuth() async {
        let (auth, _, _, _) = makeSession()
        #expect(!auth.requireSignIn(for: .purchase(templateID: "t1")))
        await signIn(auth)

        #expect(auth.takePendingAction() == .purchase(templateID: "t1"))
        #expect(auth.pendingAction == nil)
    }

    @Test("만료된 세션으로는 gate를 통과하지 못한다")
    func expiredSessionFailsGate() {
        let (auth, _, _, _) = makeSession(
            identity: AppleIdentity(userID: "apple-user-1"),
            stored: ServerSession(
                accessToken: "old",
                expiresAt: Date(timeIntervalSinceNow: -1),
                userID: "internal-user-1"
            )
        )
        #expect(!auth.requireSignIn(for: .shardTransaction))
    }

    // MARK: - 주소 / 응답 해석

    @Test("production은 배포된 HTTPS 주소다")
    func productionURLIsDeployedHTTPS() {
        // I-1에서 Cloud Run에 배포했다. release 빌드에서도 주소가 있다.
        #expect(BackendEnvironment.current != nil)
        #expect(BackendEnvironment.production.scheme == "https")
        // client에는 주소만 있다 — GCP project id / Firestore 이야기가 없다.
        let text = BackendEnvironment.production.absoluteString
        #expect(!text.contains("opicmobile"))
        #expect(!text.contains("firestore"))
    }

    @Test("서버 주소가 없으면 요청하지 않고 실패한다")
    func missingBaseURLFails() async {
        let client = BackendClient(baseURL: nil)
        await #expect(throws: BackendError.notConfigured) {
            try await client.signIn(identityToken: "t", nonce: "n")
        }
    }

    @Test("서버 응답을 그대로 해석한다")
    func decodesServerResponse() throws {
        let json = """
        {"accessToken":"abc","tokenType":"Bearer","expiresAt":"2026-09-10T11:22:33.123456Z","user":{"id":"u1"}}
        """
        // 서버는 session과 user를 함께 주지만, client가 저장하는 것은 세션 값뿐이다.
        struct Envelope: Decodable {
            let accessToken: String
            let expiresAt: Date
            let user: User
            struct User: Decodable { let id: String }
        }
        let decoded = try JSONDecoder.backend.decode(Envelope.self, from: Data(json.utf8))
        #expect(decoded.accessToken == "abc")
        #expect(decoded.user.id == "u1")
        #expect(decoded.expiresAt > Date(timeIntervalSince1970: 1_780_000_000))
    }

    @Test("소수점 초가 없는 시간도 읽는다")
    func decodesDateWithoutFraction() {
        #expect(BackendDate.parse("2026-09-10T11:22:33Z") != nil)
        #expect(BackendDate.parse("2026-09-10T11:22:33.5Z") != nil)
        #expect(BackendDate.parse("nope") == nil)
    }
}
