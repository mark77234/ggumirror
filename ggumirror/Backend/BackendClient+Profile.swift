//
//  BackendClient+Profile.swift
//  ggumirror
//
//  프로필 이름. **서버가 authority다** — 30일 규칙도 서버가 판단한다.
//

import Foundation

nonisolated protocol ProfileBackend: Sendable {
    func profile(accessToken: String) async throws -> ServerProfile
    func setDisplayName(_ name: String, accessToken: String) async throws -> ServerProfile
}

/// 이름을 바꾸지 못한 이유. **서버 문구를 그대로 옮기지 않는다** — 분류만 가져온다.
nonisolated enum DisplayNameFailure: Error, Equatable {
    /// 다른 사람이 이미 쓰고 있다.
    case taken
    /// 아직 30일이 지나지 않았다.
    case cooldown

    var message: String {
        switch self {
        case .taken: "이미 사용 중인 이름이에요."
        case .cooldown: "이름은 30일에 한 번 바꿀 수 있어요."
        }
    }

    /// 409 하나를 둘로 가른다. 서버가 준 분류 문구를 **판별에만** 쓴다.
    static func from(status: Int, data: Data) -> DisplayNameFailure? {
        guard status == 409 else { return nil }
        struct Envelope: Decodable { let detail: String }
        let detail = (try? JSONDecoder().decode(Envelope.self, from: data))?.detail ?? ""
        return detail.contains("사용 중") ? .taken : .cooldown
    }
}

extension BackendClient: ProfileBackend {
    func profile(accessToken: String) async throws -> ServerProfile {
        let data = try await request("users/me", method: "GET", accessToken: accessToken)
        return try decodeProfile(from: data, path: "GET /users/me")
    }

    /// 30일이 안 지났으면 서버가 409로 거절한다. 화면은 그 전에
    /// `canChangeDisplayName`으로 이미 막고 있으므로 여기는 마지막 방어선이다.
    ///
    /// **이름 겹침도 409다.** 둘을 한 오류로 뭉치면 "잠시 뒤 다시 시도해 주세요"가
    /// 나오는데, 이름이 겹친 사용자는 몇 번을 다시 시도해도 같은 답을 받는다.
    func setDisplayName(_ name: String, accessToken: String) async throws -> ServerProfile {
        struct Body: Encodable { let displayName: String }
        let data = try await request(
            "users/me/profile",
            method: "PATCH",
            body: try JSONEncoder.backend.encode(Body(displayName: name)),
            accessToken: accessToken,
            interpretFailure: { status, data in
                if let taken = DisplayNameFailure.from(status: status, data: data) {
                    return taken
                }
                return BackendError.unexpected(status: status)
            }
        )
        return try decodeProfile(from: data, path: "PATCH /users/me/profile")
    }

    private func decodeProfile(from data: Data, path: String) throws -> ServerProfile {
        do {
            return try JSONDecoder.backend.decode(ServerProfile.self, from: data)
        } catch {
            BackendLog.event("\(path) decode failure \(BackendLog.category(error))")
            throw BackendError.unexpected(status: 200)
        }
    }
}
