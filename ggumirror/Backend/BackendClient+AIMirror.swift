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
    /// 한 장에 몇 조각인가. **서버가 정한다** — 앱에 숫자를 적지 않는다.
    /// 옛 서버 응답에는 없다. 그때는 0이고 화면이 값을 숨긴다.
    let price: Int

    private enum CodingKeys: String, CodingKey {
        case available, price
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available = try c.decode(Bool.self, forKey: .available)
        price = try c.decodeIfPresent(Int.self, forKey: .price) ?? 0
    }

    init(available: Bool, price: Int) {
        self.available = available
        self.price = price
    }
}

nonisolated enum AIMirrorFailure: Error, Equatable {
    case notSignedIn
    /// 조각이 모자라다. **서버가 provider를 부르기 전에 거절한 것이다** —
    /// 요금이 발생하지 않았다.
    case insufficientShards
    case safetyRejected
    case unavailable
    case network

    var message: String {
        switch self {
        case .notSignedIn: "로그인이 필요해요."
        case .insufficientShards: "조각이 부족해요."
        case .safetyRejected: "이 내용으로는 거울을 만들기 어려워요. 다른 표현으로 다시 시도해 주세요."
        case .unavailable: "지금은 AI 거울을 만들 수 없어요. 잠시 뒤 다시 시도해 주세요."
        case .network: "서버에 연결하지 못했어요. 잠시 뒤 다시 시도해 주세요."
        }
    }
}

nonisolated protocol AIMirrorBackend: Sendable {
    func aiMirrorConfig(accessToken: String) async throws -> AIMirrorConfig
    /// - Returns: 거울 그림 PNG bytes.
    func generateAIMirror(
        prompt: String, requestID: String, accessToken: String
    ) async throws -> Data
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

    func generateAIMirror(
        prompt: String, requestID: String, accessToken: String
    ) async throws -> Data {
        // **보내는 것은 프롬프트와 멱등 키뿐이다.** 값도 모델도 실을 자리가 없다.
        //
        // `requestId`가 같으면 서버가 조각을 다시 빼지 않는다 — 응답을 잃었을 때
        // 다시 부를 수 있는 유일한 안전장치다.
        struct Body: Encodable { let prompt: String; let requestId: String }
        do {
            // **긴 요청이다.** 이미지 생성은 몇십 초가 걸릴 수 있다.
            return try await request(
                "ai/mirrors/generate",
                method: "POST",
                body: try JSONEncoder.backend.encode(Body(prompt: prompt, requestId: requestID)),
                accessToken: accessToken,
                interpretFailure: { status, _ in
                    switch status {
                    case 401: AIMirrorFailure.notSignedIn
                    // 서버가 조각을 세고 거절했다. **provider는 부르지 않았다.**
                    case 409: AIMirrorFailure.insufficientShards
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
