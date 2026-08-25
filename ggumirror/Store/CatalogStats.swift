//
//  CatalogStats.swift
//  ggumirror
//
//  내장 템플릿이 몇 명에게 받아졌는지. **서버가 센다.**
//
//  지금까지 이 숫자는 하드코딩 `0`이었다 — 받아도 오르지 않았고, 그래서 "아무도 안
//  받았다"는 거짓말이었다. 이제 서버가 authority다.
//
//  Marketplace 상품(`MarketplaceListing.downloadCount`)과 **경로가 다르다.**
//  저쪽은 소유권 기반이고 이쪽은 획득 기록 기반이다. 두 숫자를 섞지 않는다.
//
//  획득은 로그인 없이도 된다(내장 템플릿은 그대로 받을 수 있다). 그래서 로그아웃
//  상태에서 받은 것은 **나중에 로그인했을 때 맞춰 본다** — 그 한 번이 서버에 반영된다.
//

import Foundation

// MARK: - 서버 모양

/// `GET /catalog/templates/stats` 항목. **누가 받았는지는 들어 있지 않다.**
nonisolated struct CatalogTemplateStat: Decodable, Hashable, Sendable {
    let templateId: String
    let downloadCount: Int
}

/// `POST /catalog/templates/{id}/acquire` · `reconcile` 응답.
nonisolated struct CatalogAcquisition: Decodable, Hashable, Sendable {
    let templateId: String
    /// **이 요청이 처음 기록했는가.** `false`는 실패가 아니다 — 이미 받은 것이다.
    let firstAcquisition: Bool
    let downloadCount: Int
}

nonisolated protocol CatalogBackend: Sendable {
    /// **공개다.** 카드마다 부르지 않도록 한 번에 묻는다.
    func templateStats(ids: [String]) async throws -> [CatalogTemplateStat]
    func acquireTemplate(id: String, accessToken: String) async throws -> CatalogAcquisition
    /// 앱에 이미 있는 것을 한 번씩 따라잡는다. **몇 번을 불러도 결과가 같다.**
    func reconcileTemplates(
        ids: [String], accessToken: String
    ) async throws -> [CatalogAcquisition]
    /// 조각을 내고 산다. **가격을 보내지 않는다** — 서버 표가 값을 정한다.
    func purchaseTemplate(id: String, accessToken: String) async throws -> CatalogAcquisition
    /// 내가 가진 내장 템플릿 id.
    func ownedTemplateIDs(accessToken: String) async throws -> [String]
}

// MARK: - 상태

@MainActor
@Observable
final class CatalogStats {
    /// 앱이 쓰는 하나. `ShardWallet.live`와 같은 규칙이다.
    static let live = CatalogStats()

    /// templateId → 서버가 센 값. **여기 없으면 아직 모르는 것이고 `0`이 아니다.**
    private(set) var counts: [String: Int] = [:]

    private let backend: any CatalogBackend
    private var isLoading = false
    /// 맞춰 보기가 겹치지 않게 한다. 서버가 멱등이어도 같은 요청을 여러 번 보내지 않는다.
    private var isReconciling = false
    /// 이 세션에서 이미 맞춰 본 사용자. 화면을 다시 그릴 때마다 부르지 않는다.
    private var reconciledUserIDs: Set<String> = []

    init(backend: any CatalogBackend = BackendClient()) {
        self.backend = backend
    }

    /// 이 템플릿의 다운로드 수. **모르면 `nil`이다** — 화면이 `0`을 지어내지 않도록.
    func downloadCount(_ templateID: String) -> Int? { counts[templateID] }

    /// 내장 목록 전체의 수를 **한 번에** 받아온다.
    ///
    /// 카드마다 요청을 만들지 않는다. 실패는 조용히 둔다 — 숫자가 안 보일 뿐이고
    /// 상점을 못 여는 이유가 아니다.
    func refresh(templateIDs: [String] = StoreCatalog.samples.map(\.id)) async {
        guard !isLoading, !templateIDs.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        guard let found = try? await backend.templateStats(ids: templateIDs) else { return }
        for stat in found {
            counts[stat.templateId] = stat.downloadCount
        }
    }

    /// 내장 템플릿을 받았다고 서버에 남긴다.
    ///
    /// **로컬 획득이 성공한 뒤에만** 부른다 — 저장이 실패했는데 수만 오르면 안 된다.
    /// 이 요청이 실패해도 로컬 획득을 되돌리지 않는다. 다음 맞춰 보기가 되찾는다.
    func recordAcquisition(_ templateID: String, session: ServerSession?) async {
        guard let token = session?.accessToken else {
            // 로그인 전에 받은 것은 나중에 맞춰 본다.
            return
        }
        guard let result = try? await backend.acquireTemplate(
            id: templateID, accessToken: token
        ) else { return }
        counts[result.templateId] = result.downloadCount
    }

    /// 서버가 아는 **내가 가진** 내장 템플릿. 로그아웃하면 비운다.
    private(set) var owned: Set<String> = []

    func refreshOwned(session: ServerSession?) async {
        guard let token = session?.accessToken else {
            // 로그아웃은 비우는 것이다 — A가 산 것이 B에게 보이면 안 된다.
            owned = []
            return
        }
        if let ids = try? await backend.ownedTemplateIDs(accessToken: token) {
            owned = Set(ids)
        }
    }

    /// 이 템플릿을 이미 가지고 있는가(서버 기준).
    func isOwned(_ templateID: String) -> Bool { owned.contains(templateID) }

    /// 내장 템플릿을 산다. **조각은 서버가 옮긴다** — 여기서 잔액을 계산하지 않는다.
    ///
    /// - Returns: 실패 이유. 성공이면 `nil`.
    func purchase(_ templateID: String, session: ServerSession?) async -> String? {
        guard let token = session?.accessToken else { return "로그인이 필요해요." }
        do {
            let result = try await backend.purchaseTemplate(id: templateID, accessToken: token)
            counts[result.templateId] = result.downloadCount
            owned.insert(result.templateId)
            return nil
        } catch let error as BackendError {
            return error.message
        } catch {
            return BackendError.unavailable.message
        }
    }

    /// 앱에 이미 있는 내장 템플릿을 한 번씩 따라잡는다.
    ///
    /// 예전 버전에서 받은 것과 로그아웃 상태에서 받은 것이 여기서 반영된다.
    /// **서버가 멱등이라** 여러 번 불러도 수가 부풀지 않지만, 같은 세션에서
    /// 같은 사용자로 반복 호출하지도 않는다.
    func reconcile(ownedTemplateIDs: [String], session: ServerSession?) async {
        guard let token = session?.accessToken, let userID = session?.userID else { return }
        guard !isReconciling, !reconciledUserIDs.contains(userID) else { return }

        // **안정적 id만 보낸다.** 제목이나 임의 문자열을 보내지 않는다.
        let known = Set(StoreCatalog.samples.map(\.id))
        let wanted = Array(Set(ownedTemplateIDs).intersection(known)).sorted()
        guard !wanted.isEmpty else {
            reconciledUserIDs.insert(userID)
            return
        }

        isReconciling = true
        defer { isReconciling = false }
        guard let results = try? await backend.reconcileTemplates(
            ids: wanted, accessToken: token
        ) else { return }

        for result in results {
            counts[result.templateId] = result.downloadCount
        }
        reconciledUserIDs.insert(userID)
    }

    /// 로그아웃. 다음 사용자에게 맞춰 본 기록을 물려주지 않는다.
    func clear() {
        owned = []
        reconciledUserIDs.removeAll()
    }
}

// MARK: - 내가 가진 내장 템플릿

nonisolated extension StoreCatalog {
    /// 이 거울들 중 **내장 템플릿에서 받은 것**의 stable id.
    ///
    /// `MirrorLibrary.acquire`가 `MyMirror.id = template.id`로 저장하므로 그대로 맞는다.
    /// **제목으로 찾지 않는다** — 사용자가 이름을 바꿨을 수도 있고 같은 이름이 여럿일 수 있다.
    static func ownedTemplateIDs(in mirrors: [MyMirror]) -> [String] {
        let known = Set(samples.map(\.id))
        return mirrors.map(\.id).filter(known.contains)
    }
}
