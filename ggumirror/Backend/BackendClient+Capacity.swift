//
//  BackendClient+Capacity.swift
//  ggumirror
//
//  거울 보관 공간 호출. `BackendClient.request`를 그대로 쓴다 —
//  Bearer 주입 · timeout · 로깅 규칙이 한 곳에만 있어야 한다.
//
//  **가격과 칸 수를 보내는 자리가 없다.** body에 들어가는 것은 `packId`와
//  `operationId` 둘뿐이고, 얼마인지는 서버가 정한다.
//

import Foundation

extension BackendClient: MirrorCapacityBackend {

    func mirrorCapacity(accessToken: String) async throws -> MirrorCapacityInfo {
        let data = try await request(
            "users/me/mirror-capacity", method: "GET", accessToken: accessToken
        )
        return try decodeCapacity(
            MirrorCapacityInfo.self, from: data, path: "GET /users/me/mirror-capacity"
        )
    }

    /// - Parameter operationId: **이 구매 의도 하나**를 가리키는 UUID.
    ///   재시도에는 같은 값을 보낸다 — 새로 만들면 조각이 두 번 빠진다.
    func purchaseMirrorSlots(
        packId: String, operationId: String, accessToken: String
    ) async throws -> MirrorCapacityPurchase {
        struct Body: Encodable {
            let packId: String
            let operationId: String
        }
        let data = try await request(
            "users/me/mirror-capacity/purchases",
            method: "POST",
            body: try JSONEncoder.backend.encode(
                Body(packId: packId, operationId: operationId)
            ),
            accessToken: accessToken
        )
        return try decodeCapacity(
            MirrorCapacityPurchase.self, from: data,
            path: "POST /users/me/mirror-capacity/purchases"
        )
    }

    private func decodeCapacity<T: Decodable>(
        _ type: T.Type, from data: Data, path: String
    ) throws -> T {
        do {
            return try JSONDecoder.backend.decode(type, from: data)
        } catch {
            // 200인데 우리가 모르는 모양이다. **성공으로 보지 않는다.**
            BackendLog.event("\(path) decode failure \(BackendLog.category(error))")
            throw BackendError.unexpected(status: 200)
        }
    }
}
