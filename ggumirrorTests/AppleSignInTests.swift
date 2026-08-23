//
//  AppleSignInTests.swift
//  ggumirrorTests
//
//  Apple 로그인 **foundation**. 서버 계정도 ledger도 아직 없다.
//
//  여기서 지키는 것은 두 가지다.
//  1. 로그인이 제대로 되고 복원되는가.
//  2. 로그인/로그아웃이 사용자 콘텐츠(거울 / 사진 / 외부 디자인 / 등록 준비)를
//     **절대 건드리지 않는가.** 이게 이 Phase의 진짜 위험이라 절반이 이 테스트다.
//
//  실제 Apple 인증 UI 없이 돌아간다 — `AppleSignInOutcome` / `AppleCredentialChecking`이
//  framework 경계를 대신하기 때문이다.
//

import Testing
import SwiftUI
import UIKit
@testable import ggumirror

@MainActor
struct AppleSignInTests {

    // MARK: - 도구

    /// credential state를 원하는 값으로 고정하는 가짜 확인기.
    nonisolated private struct StubCredentials: AppleCredentialChecking {
        let result: AppleCredentialState
        func state(for userID: String) async -> AppleCredentialState { result }
    }

    /// 테스트용 서버 세션. 실제 값은 서버가 정한다.
    static let validSession = ServerSession(
        accessToken: "test-access-token",
        expiresAt: Date(timeIntervalSinceNow: 3600),
        userID: "internal-user-1"
    )

    private func session(
        _ store: InMemoryIdentityStore? = nil,
        credentials: AppleCredentialState = .authorized,
        sessions: InMemoryServerSessionStore? = nil,
        backend: FakeAuthBackend = FakeAuthBackend()
    ) -> AuthSession {
        let identities = store ?? InMemoryIdentityStore()
        // 저장된 identity가 있으면 서버 세션도 있는 상태로 본다 —
        // 로그인이란 둘 다 있는 것이고, 이 helper를 쓰는 테스트가 보려는 상태가 그것이다.
        let saved = sessions ?? InMemoryServerSessionStore(
            identities.load() == nil ? nil : Self.validSession
        )
        return AuthSession(
            store: identities,
            sessions: saved,
            credentials: StubCredentials(result: credentials),
            backend: backend
        )
    }

    /// Apple 로그인 결과를 그대로 넘긴다. 실제 nonce 흐름을 거치도록 `beginSignIn`을 먼저 부른다.
    private func signIn(_ auth: AuthSession, _ result: AppleSignInResult) async {
        _ = auth.beginSignIn()
        await auth.complete(.success(result))
    }

    /// Apple이 처음 로그인에서만 주는 이름 / 이메일까지 담긴 결과.
    private func firstSignIn(
        userID: String = "apple-user-1",
        name: String? = "병찬",
        email: String? = "mirror@example.com"
    ) -> AppleSignInResult {
        AppleSignInResult(
            userID: userID,
            displayName: name,
            email: email,
            identityToken: Data("identity-token".utf8),
            authorizationCode: Data("auth-code".utf8)
        )
    }

    private func withStore(_ body: (MirrorStore) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-auth-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = MirrorStore(root: root)
        defer {
            store.flush()
            try? FileManager().removeItem(at: root)
        }
        try await body(store)
    }

    private func library(_ store: MirrorStore) -> MirrorLibrary {
        MirrorLibrary(store: store, assets: PhotoStickerAssetStore(), artworks: ImportedArtworkAssetStore())
    }

    private func testImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        return context.makeImage()!
    }

    // MARK: - 로그인

    @Test("저장된 identity가 없으면 signedOut으로 시작한다")
    func startsSignedOut() {
        #expect(session().state == .signedOut)
    }

    @Test("로그인에 성공하면 signedIn이 된다")
    func successfulSignInSignsIn() async {
        let auth = session()
        await signIn(auth, firstSignIn())
        #expect(auth.state.isSignedIn)
    }

    @Test("Apple user identifier를 저장한다")
    func persistsUserIdentifier() async {
        let store = InMemoryIdentityStore()
        let auth = session(store)
        await signIn(auth, firstSignIn(userID: "apple-user-42"))

        #expect(auth.state.identity?.userID == "apple-user-42")
        #expect(store.load()?.userID == "apple-user-42")
    }

    @Test("이름과 이메일을 저장한다")
    func persistsNameAndEmail() async {
        let store = InMemoryIdentityStore()
        let auth = session(store)
        await signIn(auth, firstSignIn())

        #expect(auth.state.identity?.displayName == "병찬")
        #expect(auth.state.identity?.email == "mirror@example.com")
        #expect(store.load()?.displayName == "병찬")
        #expect(store.load()?.email == "mirror@example.com")
    }

    @Test("다음 로그인에서 이름이 nil이어도 기존 이름을 지우지 않는다")
    func laterNilNameKeepsStoredName() async {
        let store = InMemoryIdentityStore()
        let auth = session(store)
        await signIn(auth, firstSignIn())

        // Apple은 두 번째 로그인부터 이름 / 이메일을 주지 않는다.
        await signIn(auth, firstSignIn(name: nil, email: nil))

        #expect(auth.state.identity?.displayName == "병찬")
        #expect(store.load()?.displayName == "병찬")
    }

    @Test("다음 로그인에서 이메일이 nil이어도 기존 이메일을 지우지 않는다")
    func laterNilEmailKeepsStoredEmail() async {
        let store = InMemoryIdentityStore()
        let auth = session(store)
        await signIn(auth, firstSignIn())
        await signIn(auth, firstSignIn(name: nil, email: nil))

        #expect(auth.state.identity?.email == "mirror@example.com")
        #expect(store.load()?.email == "mirror@example.com")
    }

    @Test("빈 문자열은 값이 있는 것으로 치지 않는다")
    func blankValuesDoNotOverwrite() async {
        let auth = session()
        await signIn(auth, firstSignIn())
        await signIn(auth, firstSignIn(name: "  ", email: ""))

        #expect(auth.state.identity?.displayName == "병찬")
        #expect(auth.state.identity?.email == "mirror@example.com")
    }

    @Test("새 값이 실제로 오면 갱신한다")
    func newValuesUpdate() async {
        let auth = session()
        await signIn(auth, firstSignIn())
        await signIn(auth, firstSignIn(name: "이병찬", email: nil))

        #expect(auth.state.identity?.displayName == "이병찬")
    }

    @Test("identityToken이 없으면 서버 인증을 하지 못하므로 로그인되지 않는다")
    func missingIdentityTokenDoesNotSignIn() async {
        let auth = session()
        await signIn(auth, AppleSignInResult(userID: "apple-user-1", displayName: "병찬"))

        #expect(!auth.state.isSignedIn)
        #expect(auth.failureMessage != nil)
    }

    @Test("이름이 없으면 일반 표현으로 보여준다")
    func fallsBackToGenericLabel() {
        let identity = AppleIdentity(userID: "apple-user-1")
        #expect(identity.accountLabel == "Apple 계정")
        #expect(AppleIdentity(userID: "x", displayName: "병찬").accountLabel == "병찬")
    }

    // MARK: - 복원

    @Test("저장된 identity가 있으면 signedIn으로 시작한다")
    func restoresStoredIdentity() {
        let store = InMemoryIdentityStore(AppleIdentity(userID: "apple-user-1", displayName: "병찬"))
        #expect(session(store).state.identity?.userID == "apple-user-1")
    }

    @Test("authorized면 로그인 상태를 유지한다")
    func authorizedRestoreKeepsSignedIn() async {
        let store = InMemoryIdentityStore(AppleIdentity(userID: "apple-user-1"))
        let auth = session(store, credentials: .authorized)

        await auth.refreshCredentialState()

        #expect(auth.state.isSignedIn)
        #expect(store.load() != nil)
    }

    @Test("revoked면 Auth identity를 지운다")
    func revokedRestoreClearsIdentity() async {
        let store = InMemoryIdentityStore(AppleIdentity(userID: "apple-user-1"))
        let auth = session(store, credentials: .revoked)

        await auth.refreshCredentialState()

        #expect(auth.state == .signedOut)
        #expect(store.load() == nil)
    }

    @Test("notFound면 Auth identity를 지운다")
    func notFoundRestoreClearsIdentity() async {
        let store = InMemoryIdentityStore(AppleIdentity(userID: "apple-user-1"))
        let auth = session(store, credentials: .notFound)

        await auth.refreshCredentialState()

        #expect(auth.state == .signedOut)
        #expect(store.load() == nil)
    }

    @Test("일시적인 오류로는 identity를 지우지 않는다")
    func transientRestoreErrorKeepsIdentity() async {
        for state in [AppleCredentialState.unknown, .transferred] {
            let store = InMemoryIdentityStore(AppleIdentity(userID: "apple-user-1", displayName: "병찬"))
            let auth = session(store, credentials: state)

            await auth.refreshCredentialState()

            #expect(auth.state.isSignedIn)
            #expect(store.load()?.displayName == "병찬")
        }
    }

    // MARK: - 취소 / 실패

    @Test("취소하면 signedOut 그대로다")
    func cancelPreservesSignedOut() async {
        let auth = session()
        await auth.complete(.cancelled)

        #expect(auth.state == .signedOut)
        #expect(auth.failureMessage == nil)   // 취소는 오류 알림을 띄우지 않는다
    }

    @Test("실패해도 이미 로그인된 identity를 지우지 않는다")
    func failureKeepsExistingIdentity() async {
        let store = InMemoryIdentityStore(AppleIdentity(userID: "apple-user-1", displayName: "병찬"))
        let auth = session(store)

        await auth.complete(.failed("네트워크 오류"))

        #expect(auth.state.isSignedIn)
        #expect(store.load()?.displayName == "병찬")
        #expect(auth.failureMessage == "네트워크 오류")
    }

    @Test("Keychain 저장이 실패해도 죽지 않는다")
    func keychainFailureDoesNotCrash() async {
        let store = InMemoryIdentityStore()
        store.failsToSave = true
        let auth = session(store)

        await signIn(auth, firstSignIn())

        // 디스크에는 못 적었지만 이번 실행 동안은 로그인 상태로 쓸 수 있다.
        #expect(auth.state.isSignedIn)
        #expect(store.load() == nil)
    }

    // MARK: - 로그아웃

    @Test("로그아웃하면 signedOut이 된다")
    func signOutSignsOut() async {
        let store = InMemoryIdentityStore(AppleIdentity(userID: "apple-user-1"))
        let auth = session(store)

        await auth.signOut()

        #expect(auth.state == .signedOut)
    }

    @Test("로그아웃은 Auth identity만 지운다")
    func signOutClearsOnlyAuthIdentity() async {
        let store = InMemoryIdentityStore(AppleIdentity(userID: "apple-user-1"))
        let auth = session(store)
        auth.requireSignIn(for: .shardTransaction)

        await auth.signOut()

        #expect(store.load() == nil)
        #expect(auth.pendingAction == nil)
        #expect(auth.failureMessage == nil)
    }

    // MARK: - 로컬 콘텐츠 보존 (이 Phase의 핵심)

    @Test("로그아웃해도 내 거울과 현재 거울이 그대로다")
    func signOutPreservesMirrorLibrary() async throws {
        try await withStore { store in
            let mirrors = library(store)
            let saved = mirrors.save(MirrorDesign.blank, name: "리본 거울", context: .createNew)
            guard case .created(let id, _) = saved else {
                Issue.record("거울을 만들지 못했다: \(saved)")
                return
            }

            let auth = session(InMemoryIdentityStore(AppleIdentity(userID: "apple-user-1")))
            await auth.signOut()

            #expect(mirrors.mirrors.count == 1)
            #expect(mirrors.currentID == id)
            #expect(mirrors.mirrors.first?.name == "리본 거울")

            // 파일에서 다시 읽어도 그대로다.
            store.flush()
            #expect(library(store).mirrors.count == 1)
        }
    }

    @Test("로그아웃해도 사진 스티커 / 외부 디자인 이미지가 남는다")
    func signOutPreservesAssets() async throws {
        try await withStore { store in
            let photos = PhotoStickerAssetStore()
            let artworks = ImportedArtworkAssetStore()
            photos.attach(store)
            artworks.attach(store)

            guard case .photo(let photoID, _) = photos.register(testImage()) else {
                Issue.record("사진 스티커를 만들지 못했다")
                return
            }
            let artworkID = artworks.register(testImage())
            store.flush()

            let auth = session(InMemoryIdentityStore(AppleIdentity(userID: "apple-user-1")))
            await auth.signOut()

            #expect(photos.image(for: photoID) != nil)
            #expect(artworks.image(for: artworkID) != nil)
            #expect(FileManager().fileExists(atPath: store.assetURL(photoID, kind: .photoSticker).path))
            #expect(FileManager().fileExists(
                atPath: store.assetURL(artworkID, kind: .importedArtwork).path
            ))
        }
    }

    @Test("로그아웃해도 등록 준비 정보가 남는다")
    func signOutPreservesPublishDraft() async throws {
        try await withStore { store in
            let mirrors = library(store)
            let saved = mirrors.save(MirrorDesign.blank, name: "리본 거울", context: .createNew)
            guard let mirrorID = saved.mirrorID else {
                Issue.record("거울을 만들지 못했다")
                return
            }
            mirrors.savePublishDraft(
                MirrorPublishDraft(mirrorID: mirrorID, title: "리본 거울", priceInShards: 12)
            )
            store.flush()

            let auth = session(InMemoryIdentityStore(AppleIdentity(userID: "apple-user-1")))
            await auth.signOut()

            #expect(mirrors.publishDraft(for: mirrorID)?.title == "리본 거울")
            #expect(library(store).publishDraft(for: mirrorID)?.priceInShards == 12)
        }
    }

    @Test("로그인해도 보관 슬롯이 늘거나 줄지 않는다")
    func signInDoesNotMutateSlots() async throws {
        try await withStore { store in
            let mirrors = library(store)
            _ = mirrors.save(MirrorDesign.blank, name: "거울 하나", context: .createNew)
            let usedBefore = mirrors.createdCount
            let capacityBefore = mirrors.mirrorCapacity

            let auth = session()
            await signIn(auth, firstSignIn())

            #expect(mirrors.createdCount == usedBefore)
            #expect(mirrors.mirrorCapacity == capacityBefore)
        }
    }

    // MARK: - 로그인 없이 되는 것

    @Test("로그아웃 상태에서도 상점 24장을 전부 볼 수 있다")
    func storeBrowsingWorksSignedOut() {
        let auth = session()
        #expect(auth.state == .signedOut)

        #expect(StoreCatalog.artworkTemplates.count == 24)
        #expect(StoreCatalog.samples.count > 24)
        // 무료 템플릿은 로그인 없이 지금처럼 받을 수 있다.
        #expect(StoreCatalog.samples.contains { $0.price == 0 })
    }

    @Test("로그아웃 상태에서도 등록 준비를 작성하고 저장할 수 있다")
    func publishDraftSaveWorksSignedOut() async throws {
        try await withStore { store in
            let mirrors = library(store)
            let saved = mirrors.save(MirrorDesign.blank, name: "내 거울", context: .createNew)
            guard let mirrorID = saved.mirrorID, let mirror = mirrors.mirrors.first else {
                Issue.record("거울을 만들지 못했다")
                return
            }

            let auth = session()
            #expect(auth.state == .signedOut)

            let draft = MirrorPublishDraft(mirrorID: mirrorID, title: "내 거울", priceInShards: 0)
            #expect(MirrorPublishValidator.issues(for: draft, mirror: mirror).isEmpty)

            mirrors.savePublishDraft(draft)
            #expect(mirrors.publishDraft(for: mirrorID) != nil)
        }
    }

    // MARK: - Auth Gate (foundation)

    @Test("로그아웃 상태에서 보호된 동작을 부르면 기억해 둔다")
    func gateStoresPendingAction() {
        let auth = session()

        #expect(auth.requireSignIn(for: .publish(mirrorID: "mirror-1")) == false)
        #expect(auth.pendingAction == .publish(mirrorID: "mirror-1"))
    }

    @Test("로그인에 성공하면 기억해 둔 동작을 이어서 꺼낼 수 있다")
    func gateReleasesPendingActionAfterSignIn() async {
        let auth = session()
        auth.requireSignIn(for: .purchase(templateID: "art-pink-ribbon"))

        await signIn(auth, firstSignIn())

        #expect(auth.state.isSignedIn)
        #expect(auth.takePendingAction() == .purchase(templateID: "art-pink-ribbon"))
        #expect(auth.pendingAction == nil)   // 한 번 꺼내면 사라진다
    }

    @Test("이미 로그인돼 있으면 기억하지 않고 바로 통과한다")
    func gatePassesWhenSignedIn() {
        let auth = session(InMemoryIdentityStore(AppleIdentity(userID: "apple-user-1")))

        #expect(auth.requireSignIn(for: .shardTransaction) == true)
        #expect(auth.pendingAction == nil)
    }

    @Test("취소하면 기억해 둔 동작도 지운다")
    func cancelClearsPendingAction() async {
        let auth = session()
        auth.requireSignIn(for: .shardTransaction)

        await auth.complete(.cancelled)

        #expect(auth.pendingAction == nil)
        #expect(auth.state == .signedOut)
    }

    // MARK: - 보안

    @Test("identityToken과 authorizationCode는 저장하지 않는다")
    func tokensAreNotPersisted() async throws {
        let store = InMemoryIdentityStore()
        let auth = session(store)
        await signIn(auth, firstSignIn())

        let identity = try #require(store.load())
        let encoded = try JSONEncoder().encode(identity)
        let json = String(decoding: encoded, as: UTF8.self)

        #expect(!json.contains("identity-token"))
        #expect(!json.contains("auth-code"))
        #expect(!json.lowercased().contains("token"))
        #expect(!json.lowercased().contains("authorizationcode"))
        // 저장 형식에는 세 칸뿐이다.
        let decoded = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(decoded.keys) == ["userID", "displayName", "email"])
    }
}
