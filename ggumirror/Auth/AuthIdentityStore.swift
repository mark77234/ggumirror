//
//  AuthIdentityStore.swift
//  ggumirror
//
//  Apple identity를 Keychain에 적어두는 곳.
//
//  거울 저장소(`MirrorStore`)와 **완전히 분리**되어 있다.
//  Auth를 지워도 거울 / 사진 / 외부 디자인 / 등록 준비는 그대로 남고,
//  거울 파일이 깨져도 로그인 상태는 영향받지 않는다.
//
//  외부 Keychain 라이브러리를 쓰지 않는다. Security framework 최소 wrapper면 충분하다.
//

import Foundation
import Security

protocol AuthIdentityStoring {
    func load() -> AppleIdentity?
    func save(_ identity: AppleIdentity) throws
    func delete()
}

// MARK: - Keychain

struct KeychainIdentityStore: AuthIdentityStoring {
    /// 실패해도 앱이 죽지 않는다. 호출한 쪽이 이번 실행만 메모리로 버틸지 정한다.
    struct Failure: Error { let status: OSStatus }

    var service = "com.mark77234.ggumirror.auth"
    var account = "apple-identity"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> AppleIdentity? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(AppleIdentity.self, from: data)
    }

    func save(_ identity: AppleIdentity) throws {
        let data = try JSONEncoder().encode(identity)

        switch SecItemCopyMatching(baseQuery as CFDictionary, nil) {
        case errSecSuccess:
            let update = [kSecValueData as String: data]
            try check(SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary))
        case errSecItemNotFound:
            var insert = baseQuery
            insert[kSecValueData as String] = data
            // 기기를 한 번 연 뒤부터 읽을 수 있고, 다른 기기로 복원되지 않는다.
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try check(SecItemAdd(insert as CFDictionary, nil))
        case let status:
            throw Failure(status: status)
        }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private func check(_ status: OSStatus) throws {
        guard status != errSecSuccess else { return }
        throw Failure(status: status)
    }
}

// MARK: - 메모리

/// 미리보기와 단위 테스트용. 실제 Keychain을 건드리지 않는다.
final class InMemoryIdentityStore: AuthIdentityStoring {
    private var identity: AppleIdentity?
    /// true면 저장이 항상 실패한다 — Keychain이 막혔을 때를 흉내 낸다.
    var failsToSave = false

    init(_ identity: AppleIdentity? = nil) {
        self.identity = identity
    }

    struct Failure: Error {}

    func load() -> AppleIdentity? { identity }

    func save(_ identity: AppleIdentity) throws {
        if failsToSave { throw Failure() }
        self.identity = identity
    }

    func delete() { identity = nil }
}
