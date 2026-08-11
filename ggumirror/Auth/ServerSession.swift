//
//  ServerSession.swift
//  ggumirror
//
//  Backend가 발급한 세션. **Apple 로그인 성공과는 다른 것이다.**
//
//  Apple 인증이 됐다고 서버 계정이 생긴 것은 아니다. 이 값이 있어야 서버에 인증된 것이다.
//
//  거울 / 스티커 저장소와 완전히 분리돼 있다. 이 값을 지워도 콘텐츠는 그대로다.
//

import Foundation
import Security

/// 서버 세션. `accessToken`은 Keychain에만 둔다 — UserDefaults에 넣지 않는다.
nonisolated struct ServerSession: Equatable, Codable {
    let accessToken: String
    let expiresAt: Date
    /// 꾸미러 내부 user id(UUID). Apple 식별자가 아니다.
    let userID: String

    enum CodingKeys: String, CodingKey {
        case accessToken, expiresAt
        case userID = "userId"
    }

    func isValid(at moment: Date = Date()) -> Bool { expiresAt > moment }
}

// MARK: - 저장소

/// Apple identity 저장소(`AuthIdentityStoring`)와 **책임을 섞지 않는다.**
/// 서버 세션만 다룬다. 하나가 없어도 다른 하나는 멀쩡하다.
protocol ServerSessionStoring {
    func load() -> ServerSession?
    func save(_ session: ServerSession) throws
    func delete()
}

struct KeychainServerSessionStore: ServerSessionStoring {
    struct Failure: Error { let status: OSStatus }

    var service = "com.mark77234.ggumirror.auth"
    /// identity와 다른 account를 쓴다. 하나를 지워도 다른 하나가 사라지지 않는다.
    var account = "server-session"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> ServerSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder.backend.decode(ServerSession.self, from: data)
    }

    func save(_ session: ServerSession) throws {
        let data = try JSONEncoder.backend.encode(session)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        // 기기를 잠금 해제한 뒤에만 읽는다. 다른 기기로 옮겨지지 않는다.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            try check(SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary))
            return
        }
        try check(status)
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private func check(_ status: OSStatus) throws {
        guard status != errSecSuccess else { return }
        throw Failure(status: status)
    }
}

/// 미리보기 / 테스트용. 실제 Keychain을 건드리지 않는다.
final class InMemoryServerSessionStore: ServerSessionStoring {
    private(set) var session: ServerSession?
    /// true면 저장이 항상 실패한다 — Keychain이 막혔을 때를 흉내 낸다.
    var failsToSave = false

    init(_ session: ServerSession? = nil) {
        self.session = session
    }

    struct Failure: Error {}

    func load() -> ServerSession? { session }

    func save(_ session: ServerSession) throws {
        if failsToSave { throw Failure() }
        self.session = session
    }

    func delete() { session = nil }
}
