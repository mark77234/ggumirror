//
//  AuthSession.swift
//  ggumirror
//
//  앱 전체에서 하나뿐인 로그인 상태.
//
//  꾸미러는 로그인 없이 쓰는 앱이다. 이 객체가 signedOut이어도
//  Mirror / Capture / Editor / My Mirrors / 상점 구경 / 등록 준비는 전부 그대로 동작한다.
//  로그인은 **앞으로** 필요해질 상점 등록 / 구매 / 조각 거래를 위한 계정 바탕일 뿐이다.
//
//  로그인 성공 ≠ 서버 계정 생성. 아직 Backend가 없다.
//

import Foundation

@Observable
@MainActor
final class AuthSession {
    /// 앱이 쓰는 하나뿐인 세션. 테스트는 메모리 저장소로 자기 것을 만든다.
    static let live = AuthSession(store: KeychainIdentityStore())

    private(set) var state: AuthState
    /// 로그인이 끝나면 이어서 할 일. 지금은 아무도 넣지 않는다(foundation).
    private(set) var pendingAction: AuthProtectedAction?
    /// 실제 오류일 때만 채운다. 취소는 오류가 아니라 항상 nil이다.
    var failureMessage: String?

    private let store: any AuthIdentityStoring
    private let credentials: any AppleCredentialChecking
    private var revocationWatcher: Task<Void, Never>?

    init(
        store: any AuthIdentityStoring,
        credentials: any AppleCredentialChecking = AppleIDCredentialChecker()
    ) {
        self.store = store
        self.credentials = credentials
        // 저장된 identity가 있으면 그대로 시작한다. Apple 확인은 나중에 비동기로 한다 —
        // 앱 시작은 언제나 Mirror가 먼저다.
        state = store.load().map(AuthState.signedIn) ?? .signedOut
    }

    // MARK: - 로그인

    func complete(_ outcome: AppleSignInOutcome) {
        switch outcome {
        case .success(let result):
            signIn(with: result)
        case .cancelled:
            // 그만둔 것이다. 경고를 띄우지 않고, 아무 데이터도 바꾸지 않는다.
            pendingAction = nil
            AuthLog.state("sign-in cancelled")
        case .failed(let message):
            // 실패했다고 이미 로그인된 identity를 지우지 않는다.
            failureMessage = message
            AuthLog.state("sign-in failed")
        }
    }

    private func signIn(with result: AppleSignInResult) {
        // 같은 Apple 계정으로 다시 로그인한 경우, 예전에 받아둔 이름 / 이메일을 이어 쓴다.
        // Apple은 두 번째부터 이 값을 주지 않으므로 nil로 덮어쓰면 영영 사라진다.
        let previous = state.identity ?? store.load()
        let base = previous?.userID == result.userID ? previous! : AppleIdentity(userID: result.userID)
        let identity = base.merging(displayName: result.displayName, email: result.email)

        persist(identity)
        state = .signedIn(identity)
        failureMessage = nil
        AuthLog.state("signedIn")
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
            // 실제 처리는 서버가 생긴 뒤 Backend Auth Phase에서 한다.
            AuthLog.state("credential transferred — 상태 유지")
        case .unknown:
            // 네트워크 / 시스템 오류. 지우지 않는다.
            AuthLog.state("credential state unknown — 상태 유지")
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
    /// 거울 / 현재 거울 / 사진 스티커 / 외부 디자인 / 등록 준비 / 받은 상점 거울은
    /// 로그인과 아무 상관이 없으므로 하나도 건드리지 않는다.
    /// Apple 계정 인증 자체를 취소(revoke)하지도 않는다 — 그건 사용자가 설정에서 할 일이다.
    func signOut() {
        clearIdentity()
        AuthLog.state("signedOut")
    }

    private func clearIdentity() {
        store.delete()
        state = .signedOut
        pendingAction = nil
        failureMessage = nil
    }

    private func persist(_ identity: AppleIdentity) {
        do {
            try store.save(identity)
        } catch {
            // Keychain이 막혀도 앱이 죽지 않는다. 이번 실행 동안만 로그인 상태로 쓴다.
            AuthLog.state("identity 저장 실패 — 이번 실행에만 유지된다")
        }
    }

    // MARK: - Auth Gate (foundation)

    /// 로그인이 필요한 동작을 하려 할 때 부른다.
    /// 이미 로그인돼 있으면 true, 아니면 그 동작을 기억해 두고 false.
    ///
    /// 이번 Phase에서는 실제 Publish / Purchase를 여기에 연결하지 않는다.
    @discardableResult
    func requireSignIn(for action: AuthProtectedAction) -> Bool {
        if state.isSignedIn { return true }
        pendingAction = action
        return false
    }

    /// 로그인 후 이어서 할 일을 꺼낸다. 한 번 꺼내면 사라진다.
    func takePendingAction() -> AuthProtectedAction? {
        defer { pendingAction = nil }
        return pendingAction
    }

    func clearPendingAction() { pendingAction = nil }
}
