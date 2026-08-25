//
//  BackendClient+AIMirror.swift
//  ggumirror
//
//  AI 거울 생성. **client는 provider도 model도 모른다** —
//  아는 주소는 꾸미러 backend 하나뿐이고, API key는 서버에만 있다.
//

import Foundation

nonisolated struct AIMirrorConfig: Decodable, Equatable, Sendable {
    let available: Bool
    let dailyLimit: Int
    let remaining: Int
}

nonisolated enum AIMirrorFailure: Error, Equatable {
    case notSignedIn
    case quotaExceeded
    case safetyRejected
    case unavailable
    case network

    var message: String {
        switch self {
        case .notSignedIn: "로그인이 필요해요."
        case .quotaExceeded: "오늘 만들 수 있는 AI 거울을 모두 사용했어요. 내일 다시 만들어 주세요."
        case .safetyRejected: "이 내용으로는 거울을 만들기 어려워요. 다른 표현으로 다시 시도해 주세요."
        case .unavailable: "지금은 AI 거울을 만들 수 없어요. 잠시 뒤 다시 시도해 주세요."
        case .network: "서버에 연결하지 못했어요. 잠시 뒤 다시 시도해 주세요."
        }
    }
}

nonisolated protocol AIMirrorBackend: Sendable {
    func aiMirrorConfig(accessToken: String) async throws -> AIMirrorConfig
    /// - Returns: 거울 그림 PNG bytes.
    func generateAIMirror(prompt: String, accessToken: String) async throws -> Data
}

extension BackendClient: AIMirrorBackend {
    func aiMirrorConfig(accessToken: String) async throws -> AIMirrorConfig {
        let data = try await request("ai/mirrors/config", method: "GET", accessToken: accessToken)
        do {
            return try JSONDecoder.backend.decode(AIMirrorConfig.self, from: data)
        } catch {
            BackendLog.event("GET /ai/mirrors/config decode failure")
            throw AIMirrorFailure.unavailable
        }
    }

    func generateAIMirror(prompt: String, accessToken: String) async throws -> Data {
        struct Body: Encodable { let prompt: String }
        do {
            // **긴 요청이다.** 이미지 생성은 몇십 초가 걸릴 수 있다.
            return try await request(
                "ai/mirrors/generate",
                method: "POST",
                body: try JSONEncoder.backend.encode(Body(prompt: prompt)),
                accessToken: accessToken,
                interpretFailure: { status, _ in
                    switch status {
                    case 401: AIMirrorFailure.notSignedIn
                    case 429: AIMirrorFailure.quotaExceeded
                    // 서버가 provider 거절을 이 코드로 준다. 내부 문구를 그대로 보여 주지 않는다.
                    case 422: AIMirrorFailure.safetyRejected
                    default: AIMirrorFailure.unavailable
                    }
                },
                timeout: 200
            )
        } catch let failure as AIMirrorFailure {
            throw failure
        } catch {
            throw AIMirrorFailure.network
        }
    }
}
