//
//  AppleIdentity.swift
//  ggumirror
//
//  Apple 로그인으로 알게 된 계정 정보. **이건 서버 계정이 아니다.**
//  로그인에 성공해도 Backend User는 만들어지지 않는다 — 그건 다음 Phase다.
//
//  꾸미러는 로그인 없이 쓰는 앱이다. 여기 있는 것들은
//  거울 / 사진 / 등록 준비 같은 사용자 콘텐츠와 완전히 분리되어 있고,
//  로그인 상태가 바뀐다고 그 데이터를 건드리지 않는다.
//

import Foundation

// MARK: - Identity

/// 기기에 저장하는 Apple 계정 정보. **token은 여기 들어오지 않는다.**
struct AppleIdentity: Equatable, Codable {
    /// `ASAuthorizationAppleIDCredential.user`. 불투명한 식별자로만 다룬다 —
    /// 이메일을 대신 쓰지 않고, 로그에 그대로 찍지 않는다.
    let userID: String
    var displayName: String?
    var email: String?

    init(userID: String, displayName: String? = nil, email: String? = nil) {
        self.userID = userID
        self.displayName = Self.meaningful(displayName)
        self.email = Self.meaningful(email)
    }

    /// Apple은 **첫 로그인에서만** 이름 / 이메일을 준다. 두 번째부터는 nil이다.
    /// 그래서 새 값이 실제로 있을 때만 갱신하고, nil로는 절대 덮어쓰지 않는다.
    func merging(displayName newName: String?, email newEmail: String?) -> AppleIdentity {
        var merged = self
        if let name = Self.meaningful(newName) { merged.displayName = name }
        if let email = Self.meaningful(newEmail) { merged.email = email }
        return merged
    }

    /// 이름이 없으면 화면에 보여줄 일반 표현으로 떨어진다.
    var accountLabel: String { displayName ?? "Apple 계정" }

    private static func meaningful(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

// MARK: - 상태

enum AuthState: Equatable {
    case signedOut
    case signedIn(AppleIdentity)

    var identity: AppleIdentity? {
        if case .signedIn(let identity) = self { return identity }
        return nil
    }

    var isSignedIn: Bool { identity != nil }
}

// MARK: - 로그인 결과

/// 인증 직후에만 잠깐 존재하는 값. **저장하지 않는다.**
///
/// `identityToken` / `authorizationCode`는 서버가 Apple에 확인할 때 쓰는 재료라
/// 지금은 받을 수만 있고 아무 데도 보내지 않는다 — 디스크에도, 로그에도 남기지 않는다.
/// Backend Auth Phase가 이 값을 그대로 서버 flow에 넘긴다.
struct AppleSignInResult {
    let userID: String
    let displayName: String?
    let email: String?
    let identityToken: Data?
    let authorizationCode: Data?

    init(
        userID: String,
        displayName: String? = nil,
        email: String? = nil,
        identityToken: Data? = nil,
        authorizationCode: Data? = nil
    ) {
        self.userID = userID
        self.displayName = displayName
        self.email = email
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
    }

    /// 저장할 형태로만 꺼낸다. token은 따라오지 않는다.
    var identity: AppleIdentity {
        AppleIdentity(userID: userID, displayName: displayName, email: email)
    }
}

/// 인증 UI가 끝난 결과. 취소는 오류가 아니다.
enum AppleSignInOutcome {
    case success(AppleSignInResult)
    case cancelled
    case failed(String)
}

// MARK: - Auth Gate

/// 로그인이 필요한 동작. 지금은 **아무 곳에도 연결하지 않는다** —
/// 로그인 후 이어서 할 일을 기억할 그릇만 미리 만들어 둔다.
/// 실제 Publish / Purchase는 Backend Phase에서 붙인다.
enum AuthProtectedAction: Equatable {
    case publish(mirrorID: String)
    case purchase(templateID: String)
    case shardTransaction
}

// MARK: - 로그

/// 민감한 값은 절대 찍지 않는다 — 식별자 / 이메일 / token 전부.
/// 남기는 것은 상태 전이뿐이다.
enum AuthLog {
    static func state(_ message: String) {
        #if DEBUG
        print("[Auth] \(message)")
        #endif
    }
}
