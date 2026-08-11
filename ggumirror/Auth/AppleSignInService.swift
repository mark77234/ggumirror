//
//  AppleSignInService.swift
//  ggumirror
//
//  AuthenticationServices와 닿는 유일한 경계.
//
//  `AuthSession`은 이 파일의 순수한 값(`AppleSignInOutcome` / `AppleCredentialState`)만 보고
//  framework를 직접 부르지 않는다 — 그래서 실제 Apple 인증 UI 없이 단위 테스트가 된다.
//  DI framework는 쓰지 않는다. protocol 하나면 충분하다.
//

import AuthenticationServices
import Foundation

// MARK: - credential 상태

/// `ASAuthorizationAppleIDProvider.CredentialState`를 우리가 다루는 4가지로만 줄인 것.
enum AppleCredentialState: Equatable {
    case authorized
    case revoked
    case notFound
    /// 앱이 다른 팀으로 이관됐다. 서버 마이그레이션 신호일 뿐이라
    /// 이 단계에서 로그인 상태나 로컬 콘텐츠를 파괴적으로 지우지 않는다.
    case transferred
    /// 네트워크 / 시스템 오류처럼 판단할 수 없는 경우. **지우지 않는다.**
    case unknown
}

protocol AppleCredentialChecking: Sendable {
    func state(for userID: String) async -> AppleCredentialState
}

/// MainActor에 묶이지 않는다 — 콜백이 어느 스레드로 오든 상관없고,
/// `AuthSession` 기본 인자로도 만들 수 있어야 한다.
nonisolated struct AppleIDCredentialChecker: AppleCredentialChecking {
    func state(for userID: String) async -> AppleCredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, error in
                if error != nil {
                    // 일시적인 실패다. 여기서 signedOut으로 떨어뜨리면
                    // 비행기 모드 한 번에 로그인이 풀린다.
                    continuation.resume(returning: .unknown)
                    return
                }
                continuation.resume(returning: AppleCredentialState(state))
            }
        }
    }
}

extension AppleCredentialState {
    init(_ state: ASAuthorizationAppleIDProvider.CredentialState) {
        self = switch state {
        case .authorized: .authorized
        case .revoked: .revoked
        case .notFound: .notFound
        case .transferred: .transferred
        @unknown default: .unknown
        }
    }
}

extension AuthSession {
    /// 다른 기기 / 설정에서 Apple 로그인을 해제하면 이 알림이 온다.
    /// 이름을 직접 적지 않고 framework 상수를 그대로 쓴다.
    static let credentialRevokedNotification = ASAuthorizationAppleIDProvider.credentialRevokedNotification
}

// MARK: - 로그인 결과 변환

extension AppleSignInOutcome {
    /// `SignInWithAppleButton`이 돌려주는 결과를 우리 값으로 바꾼다.
    /// 버튼이 내부적으로 `ASAuthorizationController`를 들고 있으므로 controller를 따로 만들지 않는다.
    init(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                self = .failed("로그인 정보를 읽지 못했어요.")
                return
            }
            self = .success(AppleSignInResult(credential))
        case .failure(let error):
            // 사용자가 그만둔 것은 오류가 아니다.
            if let error = error as? ASAuthorizationError, error.code == .canceled {
                self = .cancelled
            } else {
                self = .failed("지금은 로그인할 수 없어요. 잠시 뒤 다시 시도해 주세요.")
            }
        }
    }
}

extension AppleSignInResult {
    init(_ credential: ASAuthorizationAppleIDCredential) {
        self.init(
            userID: credential.user,
            displayName: credential.fullName.flatMap(Self.name),
            email: credential.email,
            identityToken: credential.identityToken,
            authorizationCode: credential.authorizationCode
        )
    }

    /// 한국어 이름은 성 + 이름 순서라 시스템 formatter를 그대로 쓴다.
    nonisolated private static func name(from components: PersonNameComponents) -> String? {
        let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        return formatted.isEmpty ? nil : formatted
    }
}
