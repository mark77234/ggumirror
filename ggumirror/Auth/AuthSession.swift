//
//  AuthSession.swift
//  ggumirror
//
//  앱 전체에서 하나뿐인 로그인 상태.
//
//  꾸미러는 로그인 없이 쓰는 앱이다. 이 객체가 signedOut이어도
//  Mirror / Capture / Editor / My Mirrors / 상점 구경 / 등록 준비는 전부 그대로 동작한다.
//
//  **로그인 = Apple 인증 + 서버 세션.** Apple UI만 통과해도 signedIn이 아니다.
//  서버가 Apple token을 검증하고 세션을 내줘야 로그인이다.
//

import Foundation

@Observable
@MainActor
final class AuthSession {
    /// 앱이 쓰는 하나뿐인 세션. 테스트는 메모리 저장소로 자기 것을 만든다.
    static let live = AuthSession(
        store: KeychainIdentityStore(),
        sessions: KeychainServerSessionStore()
    )

    private(set) var state: AuthState
    /// 서버가 내준 세션. 이게 없으면 서버에 인증된 것이 아니다.
    private(set) var server: ServerSession?
    /// 로그인이 끝나면 이어서 할 일. 지금은 아무도 넣지 않는다(foundation).
    private(set) var pendingAction: AuthProtectedAction?
    /// 실제 오류일 때만 채운다. 취소는 오류가 아니라 항상 nil이다.
    var failureMessage: String?
    /// 서버와 이야기하는 중. 버튼을 두 번 누르는 것을 막는 데 쓴다.
    private(set) var isAuthenticating = false

    private let store: any AuthIdentityStoring
    private let sessions: any ServerSessionStoring
    /// 다음 cold launch가 어느 서랍을 먼저 열지. **credential이 아니다** —
    /// 세션은 여전히 Keychain에만 있다.
    private let lastActiveUser: LastActiveUser
    private let credentials: any AppleCredentialChecking
    private let backend: any AuthBackend
    private let nonces = AppleNonceBox()
    private var revocationWatcher: Task<Void, Never>?

    init(
        store: any AuthIdentityStoring,
        sessions: any ServerSessionStoring,
        credentials: any AppleCredentialChecking = AppleIDCredentialChecker(),
        backend: any AuthBackend = BackendClient(),
        lastActiveUser: LastActiveUser = .shared
    ) {
        self.store = store
        self.sessions = sessions
        self.credentials = credentials
        self.backend = backend
        self.lastActiveUser = lastActiveUser

        // 저장된 세션이 아직 유효할 때만 로그인 상태로 시작한다.
        // 서버 확인은 나중에 비동기로 한다 — 앱 시작은 언제나 Mirror가 먼저다.
        let saved = sessions.load()
        if let saved, saved.isValid(), let identity = store.load() {
            server = saved
            state = .signedIn(identity)
            // Keychain과 서랍 표시를 맞춰 둔다. 이미 같으면 같은 값을 다시 적을 뿐이다.
            lastActiveUser.remember(saved.userID)
        } else {
            // 만료된 세션은 로그인으로 인정하지 않는다.
            // Apple identity(이름 / 이메일)는 남겨둔다 — Apple이 다시 주지 않기 때문이다.
            server = nil
            state = .signedOut
        }
    }

    // MARK: - 로그인

    /// Apple 로그인 요청을 만들 때 부른다. `ASAuthorizationAppleIDRequest.nonce`에 넣을 값이다.
    ///
    /// 매번 새로 만든다. 원본은 이 객체 안에만 있고 Apple에는 해시만 간다.
    func beginSignIn() -> String {
        nonces.begin()
    }

    func complete(_ outcome: AppleSignInOutcome) async {
        switch outcome {
        case .success(let result):
            await signIn(with: result)
        case .cancelled:
            // 그만둔 것이다. nonce를 버리고, 경고도 띄우지 않고, 아무 데이터도 바꾸지 않는다.
            nonces.discard()
            pendingAction = nil
            AuthLog.state("sign-in cancelled")
        case .failed(let message):
            // 실패했다고 이미 로그인된 상태를 지우지 않는다.
            nonces.discard()
            failureMessage = message
            AuthLog.state("sign-in failed")
        }
    }

    private func signIn(with result: AppleSignInResult) async {
        // nonce는 한 번만 쓰인다. 꺼내는 순간 사라진다.
        guard let nonce = nonces.take() else {
            failureMessage = "로그인을 다시 시도해 주세요."
            AuthLog.state("sign-in without pending nonce")
            return
        }
        guard let identityToken = result.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
            failureMessage = "로그인 정보를 읽지 못했어요."
            AuthLog.state("sign-in without identity token")
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        let session: ServerSession
        do {
            // Apple이 이름을 준 **최초 로그인에서만** 값이 있다. 서버는 아직 이름이
            // 없을 때만 이것을 쓰고, 이미 사용자가 정한 이름은 덮지 않는다.
            session = try await backend.signIn(
                identityToken: identityToken, nonce: nonce.raw, displayName: result.displayName
            )
        } catch {
            // 서버가 거부했거나 닿지 못했다. **로그인 상태로 만들지 않는다.**
            // 거울 / 스티커 / 등록 준비는 하나도 건드리지 않는다.
            failureMessage = (error as? BackendError)?.message ?? BackendError.unavailable.message
            AuthLog.state("server sign-in failed — 로컬 콘텐츠는 그대로")
            return
        }

        // 같은 Apple 계정으로 다시 로그인한 경우, 예전에 받아둔 이름 / 이메일을 이어 쓴다.
        // Apple은 두 번째부터 이 값을 주지 않으므로 nil로 덮어쓰면 영영 사라진다.
        let previous = state.identity ?? store.load()
        let base = previous?.userID == result.userID ? previous! : AppleIdentity(userID: result.userID)
        let identity = base.merging(displayName: result.displayName, email: result.email)

        persist(identity)
        persist(session)
        // **여기서부터 이 기기의 마지막 사용자다.** 다음 cold launch가 이 서랍을 먼저 연다.
        lastActiveUser.remember(session.userID)
        server = session
        state = .signedIn(identity)
        failureMessage = nil
        AuthLog.state("signedIn (server session 발급)")
        // pendingAction은 그대로 둔다 — 부른 쪽이 take해서 이어서 진행한다.
    }

    // MARK: - 복원

    /// 저장된 identity가 아직 유효한지 Apple에 확인한다.
    /// Mirror 진입을 막지 않도록 화면이 뜬 뒤에 부른다.
    func refreshCredentialState() async {
        guard let identity = state.identity else { return }

        switch await credentials.state(for: identity.userID) {
        case .authorized:
            break
        case .revoked, .notFound:
            // Apple 쪽에서 연결이 끊겼다. **Auth만** 정리한다.
            AuthLog.state("credential revoked/notFound → signedOut")
            clearIdentity()
        case .transferred:
            // 앱 이관 신호다. 로그인 상태도 로컬 콘텐츠도 파괴적으로 건드리지 않는다.
            AuthLog.state("credential transferred — 상태 유지")
        case .unknown:
            // 네트워크 / 시스템 오류. 지우지 않는다.
            AuthLog.state("credential state unknown — 상태 유지")
        }
    }

    /// 저장된 서버 세션이 서버에서도 살아 있는지 확인한다. 화면이 뜬 뒤에 부른다.
    ///
    /// 서버가 안 될 때는 그대로 둔다 — 네트워크가 끊겼다고 로그아웃시키지 않는다.
    func refreshServerSession() async {
        guard let session = server else { return }

        if !session.isValid() {
            AuthLog.state("server session expired → signedOut")
            clearServerSession()
            return
        }

        do {
            _ = try await backend.verify(accessToken: session.accessToken)
        } catch BackendError.unauthorized {
            // 서버가 세션을 취소했다(다른 기기 로그아웃 등).
            AuthLog.state("server session rejected → signedOut")
            clearServerSession()
        } catch {
            AuthLog.state("server session 확인 실패 — 상태 유지")
        }
    }

    /// 다른 기기나 설정에서 Apple 로그인을 해제했을 때 알림이 온다.
    /// 이때도 지우는 것은 Auth뿐이다.
    func watchRevocation(
        notifications: NotificationCenter = .default
    ) {
        guard revocationWatcher == nil else { return }
        revocationWatcher = Task { [weak self] in
            let stream = notifications.notifications(named: AuthSession.credentialRevokedNotification)
            for await _ in stream {
                guard let self else { return }
                await MainActor.run {
                    guard self.state.isSignedIn else { return }
                    AuthLog.state("credential revoked notification → signedOut")
                    self.clearIdentity()
                }
            }
        }
    }

    // MARK: - 로그아웃

    /// 꾸미러의 로그아웃은 **이 기기의 로그인 상태를 끝내는 것**이다.
    ///
    /// 거울 / 현재 거울 / 스티커 / 사진 스티커 / 외부 디자인 / 등록 준비 / 받은 상점 거울은
    /// 로그인과 아무 상관이 없으므로 하나도 건드리지 않는다.
    /// Apple 계정 인증 자체를 취소(revoke)하지도 않는다 — 그건 사용자가 설정에서 할 일이다.
    ///
    /// 서버에 알리지 못해도 로컬 로그아웃은 그대로 진행한다 —
    /// 네트워크가 안 된다고 로그아웃을 막지 않는다. 남은 서버 세션은 만료로 정리된다.
    func signOut() async {
        if let session = server {
            try? await backend.logout(accessToken: session.accessToken)
        }
        clearServerSession()
        clearIdentity()
        AuthLog.state("signedOut")
    }

    private func clearIdentity() {
        store.delete()
        state = .signedOut
        pendingAction = nil
        failureMessage = nil
    }

    /// 서버 세션만 정리한다. Apple identity(이름 / 이메일)와 로컬 콘텐츠는 건드리지 않는다.
    ///
    /// **서랍 표시도 푼다.** 로그아웃한 사람의 거울이 다음 실행의 guest 화면에 뜨면 안 된다.
    /// 파일은 그대로 남으므로 다시 로그인하면 되돌아온다 — 지우는 것이 아니라 푸는 것이다.
    private func clearServerSession() {
        sessions.delete()
        lastActiveUser.forget()
        server = nil
        state = .signedOut
    }

    private func persist(_ identity: AppleIdentity) {
        do {
            try store.save(identity)
        } catch {
            // Keychain이 막혀도 앱이 죽지 않는다. 이번 실행 동안만 로그인 상태로 쓴다.
            AuthLog.state("identity 저장 실패 — 이번 실행에만 유지된다")
        }
    }

    private func persist(_ session: ServerSession) {
        do {
            try sessions.save(session)
        } catch {
            AuthLog.state("server session 저장 실패 — 이번 실행에만 유지된다")
        }
    }

    // MARK: - Auth Gate (foundation)

    /// 로그인이 필요한 동작을 하려 할 때 부른다.
    /// **서버 인증까지 끝난 상태**여야 true다. Apple 인증만으로는 통과하지 못한다.
    ///
    /// 이번 Phase에서는 실제 Publish / Purchase를 여기에 연결하지 않는다.
    @discardableResult
    func requireSignIn(for action: AuthProtectedAction) -> Bool {
        if state.isSignedIn, server?.isValid() == true { return true }
        pendingAction = action
        return false
    }

    /// 로그인 후 이어서 할 일을 꺼낸다. 한 번 꺼내면 사라진다.
    /// 서버 인증이 끝나지 않았으면 꺼내주지 않는다.
    func takePendingAction() -> AuthProtectedAction? {
        guard state.isSignedIn, server?.isValid() == true else { return nil }
        defer { pendingAction = nil }
        return pendingAction
    }

    func clearPendingAction() { pendingAction = nil }
}
