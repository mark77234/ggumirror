//
//  GuestShardPurchaseTests.swift
//  ggumirrorTests
//
//  **로그인 없이 조각을 산다** (App Store Review Guideline 5.1.1(v)).
//
//  조각은 소모품이고 계정에 묶인 물건이 아니다. 그래서 결제 앞에 로그인 관문을 두지 않는다.
//  대신 결제의 주인은 **서버가 발급한 신원**이 정한다 — client가 UUID를 만들어
//  "이게 내 지갑"이라고 말할 수 있으면 남의 지갑도 가리킬 수 있다.
//
//  여기서 고정하는 것:
//  1. 조각 상점 화면에 로그인 관문 · 로그인 문구가 없다.
//  2. 익명 세션은 **서버가** 준다. `UUID()`로 만들지 않는다.
//  3. 로그인하면 그 지갑을 계정이 이어받는다(합치기는 서버가 한다).
//  4. 판매자 · 신원 기능은 여전히 Apple 계정을 요구한다.
//  5. 3.1.1로 지운 소모품 "복원" 표현이 되살아나지 않았다.
//

import Foundation
import Testing
@testable import ggumirror

private func guestSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

private func guestCode(_ path: String) throws -> String {
    codeWithoutComments(try guestSource(path))
}

// MARK: - 화면: 로그인 관문이 없다

@Suite("조각 상점에는 로그인 관문이 없다")
struct GuestShardStoreUITests {

    @Test("상점 시트가 로그인을 요구하지 않는다")
    func sheetHasNoAuthGate() throws {
        let code = try guestCode("ggumirror/IAP/ShardStoreSheet.swift")
        for forbidden in ["requireSignIn", "onNeedsSignIn", "SignInWithAppleButton", "signedOutNotice"] {
            #expect(!code.contains(forbidden), "조각 구매 앞에 \(forbidden)이 남아 있다")
        }
        // 세션이 없으면 **막는 것이 아니라 받아 온다.**
        #expect(code.contains("auth.ensureServerSession()"))
        #expect(code.contains("controller.purchase("))
    }

    @Test("상점 시트 문구가 로그인을 요구하지 않는다")
    func sheetCopyDoesNotDemandSignIn() throws {
        let source = try guestSource("ggumirror/IAP/ShardStoreSheet.swift")
        for forbidden in ["로그인이 필요", "로그인해 주세요", "필수"] {
            #expect(!source.contains(forbidden), "\(forbidden) 문구가 남아 있다")
        }
    }

    @Test("controller도 로그인을 요구하지 않는다")
    func controllerHasNoAuthGate() throws {
        let source = try guestSource("ggumirror/IAP/ShardPurchaseController.swift")
        #expect(!source.contains("조각을 충전하려면 로그인이 필요해요"))
        #expect(!codeWithoutComments(source).contains("requireSignIn"))
        // appAccountToken은 여전히 **세션의 user id**다. 지역 UUID를 만들지 않는다.
        #expect(source.contains("UUID(uuidString: session.userID)"))
        #expect(!codeWithoutComments(source).contains("UUID()"))
    }

    @Test("세 진입점 모두 같은 시트를 로그인 없이 연다", arguments: [
        "ggumirror/Home/HomeView.swift",
        "ggumirror/Editor/StickerCreatorView.swift",
        "ggumirror/Store/StoreView.swift",
    ])
    func entryPointsPassAuthSession(path: String) throws {
        let code = try guestCode(path)
        #expect(code.contains("ShardStoreSheet("))
        #expect(code.contains("auth: session"))
    }

    /// Apple 심사 기기가 iPad Air 11"(M3)였다. **기기별로 다른 구매 화면이 없어야** 한다 —
    /// 갈라지는 순간 한쪽에만 로그인 관문이 남아도 테스트가 초록으로 통과한다.
    @Test("기기·크기별로 다른 조각 상점이 없다")
    func shardStoreHasNoDeviceVariant() throws {
        let code = try guestCode("ggumirror/IAP/ShardStoreSheet.swift")
        for branch in ["horizontalSizeClass", "UIDevice", "userInterfaceIdiom", "idiom"] {
            #expect(!code.contains(branch), "\(branch)로 구매 화면이 갈라진다")
        }
    }

    /// 3.1.1로 지운 것이 5.1.1을 고치면서 되살아나면 안 된다.
    @Test("소모품 복원 표현이 되살아나지 않았다")
    func noConsumableRestoreRegression() throws {
        for path in [
            "ggumirror/IAP/ShardStoreSheet.swift",
            "ggumirror/IAP/ShardPurchaseController.swift",
            "ggumirror/Auth/AccountSection.swift",
        ] {
            let source = try guestSource(path)
            for forbidden in [
                "구매 복원", "PurchaseRestore", "AppStore.sync",
                "restoreCompletedTransactions", "currentEntitlements",
            ] {
                #expect(!source.contains(forbidden), "\(path)에 \(forbidden)이 있다")
            }
        }
    }

    @Test("설정 문구가 '조각을 사려면 계정이 필요하다'고 말하지 않는다")
    func settingsCopyDoesNotRequireAccountForShards() throws {
        let source = try guestSource("ggumirror/Auth/AccountSection.swift")
        #expect(!source.contains("조각으로 구매할 때 계정이 필요해요"))
        #expect(source.contains("조각 충전"))
        // 계정이 필요한 것은 판매 쪽이라고 정확히 말한다.
        #expect(source.contains("팔거나"))
    }

    @Test("약관도 같은 것을 말한다")
    func termsMatchTheImplementation() throws {
        let terms = try guestSource("docs/legal/terms-of-service-ko.md")
        #expect(terms.contains("로그인이 필요하지 않습니다"))
        // 소모품이 복원된다고 쓰지 않는다 — 그런 기능이 없다.
        #expect(terms.contains("Apple의 구매 복원으로 되돌릴 수 없습니다"))
    }
}

// MARK: - 사는 쪽 / 파는 쪽

@Suite("사는 것은 익명으로, 파는 것은 계정으로")
struct GuestSpendVsSellerGateTests {

    /// 산 조각을 **쓸 수** 없으면 5.1.1을 고친 것이 아니다.
    /// 구매·받기·좋아요·보관 공간은 전부 `session.server`(익명 포함)를 본다.
    @Test("조각을 쓰는 자리는 익명 세션도 받는다", arguments: [
        "ggumirror/Store/TemplateDetailView.swift",
        "ggumirror/Store/StoreView.swift",
        "ggumirror/Store/StickerStoreView.swift",
    ])
    func spendingPathsAcceptGuests(path: String) throws {
        let code = try guestCode(path)
        #expect(code.contains("session: session.server") || code.contains("session.server != nil"))
    }

    @Test("판매자 · 신원 기능은 Apple 계정만 받는다", arguments: [
        "ggumirror/Store/PublishMirrorView.swift",
        "ggumirror/Store/PublishStickerView.swift",
        "ggumirror/Store/SellerNameSheet.swift",
        "ggumirror/Home/ProfileView.swift",
        "ggumirror/MyMirrors/MyMirrorsView.swift",
    ])
    func sellerPathsRequireAnAccount(path: String) throws {
        let code = try guestCode(path)
        #expect(code.contains("session.account"), "\(path)가 익명 세션도 판매자로 본다")
    }

    @Test("내 판매 탭과 계정 삭제는 계정을 요구한다")
    func mySalesAndDeletionRequireAnAccount() throws {
        let store = try guestCode("ggumirror/Store/StoreView.swift")
        #expect(store.contains("guard item != .mySales || session.account != nil"))
        let settings = try guestCode("ggumirror/Home/SettingsView.swift")
        #expect(settings.contains("if session.account != nil"))
    }

    /// 내 거울 서랍은 **계정마다** 따로다. 익명으로 조각을 샀다고 서랍이 바뀌면
    /// 로그아웃 상태에서 만든 거울이 사라진 것처럼 보인다.
    @Test("로컬 서랍은 계정 기준으로 연다")
    func libraryFollowsTheAccountNotTheGuest() throws {
        let code = try guestCode("ggumirror/RootView.swift")
        #expect(code.contains("MirrorLibraryOwner(userID: session.account?.userID)"))
        #expect(!code.contains("MirrorLibraryOwner(userID: server?.userID)"))
    }
}

// MARK: - 익명 세션은 서버가 발급한다

@MainActor
struct GuestSessionTests {

    private struct StubCredentials: AppleCredentialChecking {
        func state(for userID: String) async -> AppleCredentialState { .authorized }
    }

    private func make(
        stored: ServerSession? = nil,
        identity: AppleIdentity? = nil,
        backend: FakeAuthBackend = FakeAuthBackend()
    ) -> (AuthSession, InMemoryServerSessionStore, FakeAuthBackend) {
        let sessions = InMemoryServerSessionStore(stored)
        let auth = AuthSession(
            store: InMemoryIdentityStore(identity),
            sessions: sessions,
            credentials: StubCredentials(),
            backend: backend,
            lastActiveUser: LastActiveUser(
                defaults: UserDefaults(suiteName: "ggumirror.tests.\(UUID().uuidString)")!
            )
        )
        return (auth, sessions, backend)
    }

    private func guest(
        token: String = "guest-token-1",
        userID: String = "00000000-0000-0000-0000-0000000000AA",
        expiresIn: TimeInterval = 30 * 86_400
    ) -> ServerSession {
        ServerSession(
            accessToken: token, expiresAt: Date(timeIntervalSinceNow: expiresIn),
            userID: userID, isGuest: true
        )
    }

    @Test("세션이 없으면 서버에서 익명 신원을 받아 온다")
    func bootstrapAsksTheServer() async {
        let (auth, sessions, backend) = make()
        await auth.ensureServerSession()

        #expect(backend.guestRenewals == [nil])
        #expect(auth.server?.isGuest == true)
        // **로그인 상태가 아니다.** 판매자 자리는 여전히 비어 있다.
        #expect(!auth.state.isSignedIn)
        #expect(auth.account == nil)
        // 다음 실행에도 같은 지갑으로 돌아온다.
        #expect(sessions.load()?.accessToken == "guest-token-1")
    }

    @Test("이미 쓸 수 있는 세션이 있으면 다시 받지 않는다")
    func bootstrapIsIdempotent() async {
        let (auth, _, backend) = make(stored: guest())
        await auth.ensureServerSession()
        await auth.ensureServerSession()
        #expect(backend.guestRenewals.isEmpty)
        #expect(auth.server?.accessToken == "guest-token-1")
    }

    @Test("저장된 익명 세션을 다시 쓴다")
    func storedGuestSessionSurvivesRelaunch() {
        let (auth, _, _) = make(stored: guest(token: "old-guest"))
        #expect(auth.server?.accessToken == "old-guest")
        #expect(auth.account == nil)
    }

    /// 세션은 30일이고 지갑은 그 token으로만 닿는다. 만료되면 **돈 주고 산 조각**을 잃는다.
    @Test("만료가 가까우면 같은 지갑으로 연장한다")
    func expiringGuestSessionIsRenewed() async {
        let (auth, _, backend) = make(stored: guest(token: "old-guest", expiresIn: 3 * 86_400))
        await auth.ensureServerSession()
        // 옛 token을 함께 보낸다 — 서버가 같은 사용자에게 새 session을 준다.
        #expect(backend.guestRenewals == ["old-guest"])
        #expect(auth.server?.accessToken == "guest-token-1")
    }

    @Test("발급이 실패해도 조용히 넘어가고 다음에 다시 시도한다")
    func bootstrapFailureIsRecoverable() async {
        let backend = FakeAuthBackend()
        backend.guestOutcome = .failure(.unavailable)
        let (auth, sessions, _) = make(backend: backend)

        await auth.ensureServerSession()
        #expect(auth.server == nil)
        #expect(sessions.load() == nil)
        #expect(auth.failureMessage == nil, "익명 발급 실패로 로그인 오류를 띄우지 않는다")

        backend.guestOutcome = .success(guest())
        await auth.ensureServerSession()
        #expect(auth.server?.isGuest == true)
    }

    // MARK: - 로그인으로 넘기기

    @Test("로그인할 때 들고 있던 익명 token을 함께 보낸다")
    func signInCarriesTheGuestToken() async {
        let (auth, _, backend) = make(stored: guest(token: "guest-with-shards"))
        _ = auth.beginSignIn()
        await auth.complete(.success(appleResult()))

        // **client가 잔액을 옮기지 않는다.** 서버에 "이 지갑을 이어받아라"만 말한다.
        #expect(backend.receivedGuestTokens == ["guest-with-shards"])
        #expect(auth.state.isSignedIn)
        #expect(auth.account != nil)
        #expect(auth.server?.isGuest == false)
    }

    @Test("계정 세션은 익명 token을 보내지 않는다")
    func accountSessionDoesNotClaimAGuestWallet() async {
        let account = ServerSession(
            accessToken: "account-token", expiresAt: Date(timeIntervalSinceNow: 86_400),
            userID: "11111111-2222-4333-8444-555555555555"
        )
        let (auth, _, backend) = make(stored: account, identity: AppleIdentity(userID: "apple-user-1"))
        _ = auth.beginSignIn()
        await auth.complete(.success(appleResult()))
        #expect(backend.receivedGuestTokens == [nil])
    }

    @Test("로그인에 실패해도 익명 지갑을 잃지 않는다")
    func failedSignInKeepsTheGuestWallet() async {
        let backend = FakeAuthBackend(signInOutcome: .failure(.unavailable))
        let (auth, sessions, _) = make(stored: guest(token: "guest-with-shards"), backend: backend)
        _ = auth.beginSignIn()
        await auth.complete(.success(appleResult()))

        #expect(auth.server?.accessToken == "guest-with-shards")
        #expect(sessions.load()?.accessToken == "guest-with-shards")
    }

    @Test("로그아웃하면 다시 익명으로 돌아가 계속 살 수 있다")
    func signOutReturnsToAGuestSession() async {
        let account = ServerSession(
            accessToken: "account-token", expiresAt: Date(timeIntervalSinceNow: 86_400),
            userID: "11111111-2222-4333-8444-555555555555"
        )
        let (auth, _, _) = make(stored: account, identity: AppleIdentity(userID: "apple-user-1"))
        await auth.signOut()

        #expect(auth.server?.isGuest == true)
        #expect(auth.account == nil)
        #expect(!auth.state.isSignedIn)
    }

    private func appleResult() -> AppleSignInResult {
        AppleSignInResult(
            userID: "apple-user-1",
            displayName: "병찬",
            email: "mirror@example.com",
            identityToken: Data("apple.identity.token".utf8),
            authorizationCode: Data("apple-auth-code".utf8)
        )
    }
}
