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

extension BackendClient: ProfileBackend {
    func profile(accessToken: String) async throws -> ServerProfile {
        let data = try await request("users/me", method: "GET", accessToken: accessToken)
        return try decodeProfile(from: data, path: "GET /users/me")
    }

    /// 30일이 안 지났으면 서버가 409로 거절한다. 화면은 그 전에
    /// `canChangeDisplayName`으로 이미 막고 있으므로 여기는 마지막 방어선이다.
    func setDisplayName(_ name: String, accessToken: String) async throws -> ServerProfile {
        struct Body: Encodable { let displayName: String }
        let data = try await request(
            "users/me/profile",
            method: "PATCH",
            body: try JSONEncoder.backend.encode(Body(displayName: name)),
            accessToken: accessToken
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
