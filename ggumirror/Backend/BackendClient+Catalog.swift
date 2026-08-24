//
//  BackendClient+Catalog.swift
//  ggumirror
//
//  내장 템플릿 통계 호출. `BackendClient.request`를 그대로 쓴다 —
//  Bearer 주입 · timeout · 로깅 규칙이 한 곳에만 있어야 한다.
//
//  Marketplace 확장과 같은 규칙이고, 두 domain을 섞지 않는다.
//

import Foundation

extension BackendClient: CatalogBackend {

    /// **공개다 — 로그인 없이 볼 수 있다.** 카드마다 부르지 않도록 한 번에 묻는다.
    func templateStats(ids: [String]) async throws -> [CatalogTemplateStat] {
        guard !ids.isEmpty else { return [] }
        // id는 우리 상수 목록이지만 그대로 붙이지 않는다.
        let joined = ids.joined(separator: ",")
        // **`?`를 path 문자열에 붙이지 않는다.** `send`가 `appending(path:)`로 URL을
        // 만들기 때문에 `?`가 `%3F`로 인코딩되어 query가 경로의 일부가 된다 —
        // 그러면 이 요청은 **언제나 404**이고 내장 템플릿 다운로드 수가 영영 뜨지 않는다.
        // 인코딩은 우리가 하지 않고 query builder에게 맡긴다.
        let data = try await request(
            "catalog/templates/stats", method: "GET",
            query: [URLQueryItem(name: "ids", value: joined)]
        )
        return try decodeCatalog(
            [CatalogTemplateStat].self, from: data, path: "GET /catalog/templates/stats"
        )
    }

    /// 내장 템플릿을 받았다고 기록한다. **body가 없다** —
    /// 수량 · userId를 실을 자리가 없고, 얼마나 오르는지는 서버가 정한다.
    func acquireTemplate(id: String, accessToken: String) async throws -> CatalogAcquisition {
        let data = try await request(
            "catalog/templates/\(try catalogPathComponent(id))/acquire",
            method: "POST",
            accessToken: accessToken
        )
        return try decodeCatalog(
            CatalogAcquisition.self, from: data,
            path: "POST /catalog/templates/{id}/acquire"
        )
    }

    /// 앱에 이미 있는 것을 한 번씩 따라잡는다. **서버가 멱등이다.**
    func reconcileTemplates(
        ids: [String], accessToken: String
    ) async throws -> [CatalogAcquisition] {
        struct Body: Encodable { let templateIds: [String] }
        let data = try await request(
            "catalog/templates/reconcile",
            method: "POST",
            body: try JSONEncoder.backend.encode(Body(templateIds: ids)),
            accessToken: accessToken,
            timeout: 30
        )
        return try decodeCatalog(
            [CatalogAcquisition].self, from: data,
            path: "POST /catalog/templates/reconcile"
        )
    }

    /// 우리 상수 목록에서 오는 값이지만 그대로 붙이지 않는다.
    private func catalogPathComponent(_ component: String) throws -> String {
        guard isSafePathComponent(component) else {
            throw BackendError.unexpected(status: 400)
        }
        return component
    }

    private func decodeCatalog<T: Decodable>(
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
