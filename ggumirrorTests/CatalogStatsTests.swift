//
//  CatalogStatsTests.swift
//  ggumirrorTests
//
//  내장 템플릿 다운로드 수. **실제 production을 부르지 않는다** — 전부 fake다.
//
//  보는 것:
//    1. 서버 값을 받기 전에 **거짓 0을 보여주지 않는가**
//    2. 실제 0을 받으면 0을 보여주는가
//    3. 이전 다운로드를 **stable id로** 찾는가 (제목 아님)
//    4. 맞춰 보기를 반복해도 수가 부풀지 않는가
//

import Foundation
import SwiftUI
import Testing
@testable import ggumirror

private let MINT = "art-mint-flower"

/// 주석을 걷어낸 소스.
///
/// 소스 검사에서 **설명 문구를 잡는 일이 반복됐다** — "상점에서 내리기를 쓰지
/// 않는다"라고 적어 두면 그 주석 자체가 금지어로 걸린다. 규칙을 확인할 때는
/// 코드만 본다.
func codeWithoutComments(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            guard let comment = line.range(of: "//") else { return String(line) }
            return String(line[..<comment.lowerBound])
        }
        .joined(separator: "\n")
}


private final class FakeCatalogBackend: CatalogBackend, @unchecked Sendable {
    var stats: [String: Int] = [:]
    var failure: Error?
    var calls: [String] = []
    var purchased: Set<String> = []
    var sawToken = false
    /// 서버 쪽 기록. 멱등을 실제로 흉내 낸다.
    var recorded: Set<String> = []

    private func check() throws { if let failure { throw failure } }

    func templateStats(ids: [String]) async throws -> [CatalogTemplateStat] {
        calls.append("stats(\(ids.count))")
        try check()
        return ids.map { CatalogTemplateStat(templateId: $0, downloadCount: stats[$0] ?? 0) }
    }

    func acquireTemplate(id: String, accessToken: String) async throws -> CatalogAcquisition {
        calls.append("acquire(\(id))")
        sawToken = !accessToken.isEmpty
        try check()
        let isNew = recorded.insert(id).inserted
        if isNew { stats[id] = (stats[id] ?? 0) + 1 }
        return CatalogAcquisition(
            templateId: id, firstAcquisition: isNew, downloadCount: stats[id] ?? 0
        )
    }

    func reconcileTemplates(
        ids: [String], accessToken: String
    ) async throws -> [CatalogAcquisition] {
        calls.append("reconcile(\(ids.joined(separator: ",")))")
        sawToken = !accessToken.isEmpty
        try check()
        return try await ids.asyncMap { try await acquireTemplate(id: $0, accessToken: accessToken) }
    }

    /// 유료 구매. **가격을 받지 않는다** — 서버 표가 값을 정한다.
    func purchaseTemplate(id: String, accessToken: String) async throws -> CatalogAcquisition {
        calls.append("purchase(\(id))")
        sawToken = !accessToken.isEmpty
        try check()
        purchased.insert(id)
        return try await acquireTemplate(id: id, accessToken: accessToken)
    }

    func ownedTemplateIDs(accessToken: String) async throws -> [String] {
        calls.append("owned")
        sawToken = !accessToken.isEmpty
        try check()
        return purchased.sorted()
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        for item in self { out.append(try await transform(item)) }
        return out
    }
}

private func session(_ userID: String = "user-1") -> ServerSession {
    ServerSession(accessToken: "test-token", expiresAt: .distantFuture, userID: userID)
}

@MainActor
@Suite("내장 템플릿 통계")
struct CatalogStatsTests {

    private func stats(_ backend: FakeCatalogBackend) -> CatalogStats {
        CatalogStats(backend: backend)
    }

    @Test("서버 값을 받기 전에는 숫자를 모른다 — 거짓 0이 없다")
    func unknownBeforeLoad() {
        let subject = stats(FakeCatalogBackend())

        // **nil이다.** 0이면 "아무도 안 받았다"는 거짓말이 된다.
        #expect(subject.downloadCount(MINT) == nil)
    }

    @Test("실제 0을 받으면 0을 보여 준다")
    func realZeroIsShown() async {
        let backend = FakeCatalogBackend()
        let subject = stats(backend)

        await subject.refresh(templateIDs: [MINT])

        #expect(subject.downloadCount(MINT) == 0)
    }

    @Test("서버가 센 값을 그대로 보여 준다")
    func showsServerCount() async {
        let backend = FakeCatalogBackend()
        backend.stats = [MINT: 7]
        let subject = stats(backend)

        await subject.refresh(templateIDs: [MINT])

        #expect(subject.downloadCount(MINT) == 7)
    }

    @Test("카드마다 부르지 않고 한 번에 묻는다")
    func batchesInOneRequest() async {
        let backend = FakeCatalogBackend()
        let subject = stats(backend)

        await subject.refresh(templateIDs: StoreCatalog.samples.map(\.id))

        #expect(backend.calls.count == 1)
        #expect(backend.calls.first == "stats(\(StoreCatalog.samples.count))")
    }

    @Test("조회는 로그인 없이 된다")
    func statsNeedNoLogin() async {
        let backend = FakeCatalogBackend()
        let subject = stats(backend)

        await subject.refresh(templateIDs: [MINT])

        #expect(!backend.sawToken)
        #expect(subject.downloadCount(MINT) == 0)
    }

    @Test("조회 실패는 조용히 둔다 — 상점을 막지 않는다")
    func failureIsQuiet() async {
        let backend = FakeCatalogBackend()
        backend.failure = BackendError.unavailable
        let subject = stats(backend)

        await subject.refresh(templateIDs: [MINT])

        // 숫자가 안 보일 뿐이다. 가짜 0을 넣지 않는다.
        #expect(subject.downloadCount(MINT) == nil)
    }

    // MARK: - 획득

    @Test("획득하면 서버에 기록하고 수를 갱신한다")
    func acquireRecordsAndRefreshes() async {
        let backend = FakeCatalogBackend()
        let subject = stats(backend)

        await subject.recordAcquisition(MINT, session: session())

        #expect(backend.calls.contains("acquire(\(MINT))"))
        #expect(subject.downloadCount(MINT) == 1)
        #expect(backend.sawToken)
    }

    @Test("같은 사용자가 다시 받아도 수가 오르지 않는다")
    func repeatAcquireDoesNotInflate() async {
        let backend = FakeCatalogBackend()
        let subject = stats(backend)

        await subject.recordAcquisition(MINT, session: session())
        await subject.recordAcquisition(MINT, session: session())
        await subject.recordAcquisition(MINT, session: session())

        #expect(subject.downloadCount(MINT) == 1)
    }

    @Test("로그인 전이면 서버를 부르지 않는다")
    func anonymousAcquireIsDeferred() async {
        let backend = FakeCatalogBackend()
        let subject = stats(backend)

        await subject.recordAcquisition(MINT, session: nil)

        // 나중에 맞춰 본다 — 여기서 실패로 만들지 않는다.
        #expect(backend.calls.isEmpty)
    }

    @Test("획득 기록이 실패해도 던지지 않는다 — 로컬 획득을 되돌리지 않는다")
    func acquireFailureIsNotFatal() async {
        let backend = FakeCatalogBackend()
        backend.failure = BackendError.unavailable
        let subject = stats(backend)

        await subject.recordAcquisition(MINT, session: session())

        #expect(subject.downloadCount(MINT) == nil)
    }

    // MARK: - 맞춰 보기

    @Test("이전에 받은 것을 한 번 반영한다")
    func reconcileRecordsPreviousDownloads() async {
        let backend = FakeCatalogBackend()
        let subject = stats(backend)

        await subject.reconcile(ownedTemplateIDs: [MINT], session: session())

        #expect(subject.downloadCount(MINT) == 1)
        #expect(backend.calls.contains("reconcile(\(MINT))"))
    }

    @Test("실패한 획득을 맞춰 보기가 되찾는다")
    func reconcileRecoversFailedAcquire() async {
        let backend = FakeCatalogBackend()
        backend.failure = BackendError.unavailable
        let subject = stats(backend)
        await subject.recordAcquisition(MINT, session: session())
        #expect(subject.downloadCount(MINT) == nil)

        backend.failure = nil
        await subject.reconcile(ownedTemplateIDs: [MINT], session: session())

        #expect(subject.downloadCount(MINT) == 1)
    }

    @Test("같은 세션에서 반복해도 한 번만 부른다")
    func reconcileRunsOncePerUser() async {
        let backend = FakeCatalogBackend()
        let subject = stats(backend)

        await subject.reconcile(ownedTemplateIDs: [MINT], session: session())
        await subject.reconcile(ownedTemplateIDs: [MINT], session: session())
        await subject.reconcile(ownedTemplateIDs: [MINT], session: session())

        #expect(backend.calls.filter { $0.hasPrefix("reconcile") }.count == 1)
        #expect(subject.downloadCount(MINT) == 1)
    }

    @Test("여러 번 맞춰 봐도 수가 부풀지 않는다")
    func reconcileIsIdempotent() async {
        let backend = FakeCatalogBackend()
        let subject = stats(backend)

        for index in 0..<5 {
            // 사용자를 바꿔 세션 guard를 우회해도 서버가 멱등이다.
            await subject.reconcile(ownedTemplateIDs: [MINT], session: session("user-\(index)"))
        }

        // fake 서버는 (template) 단위로 기록한다 — 같은 template은 한 번만 센다.
        #expect(subject.downloadCount(MINT) == 1)
    }

    @Test("로그인 전에는 맞춰 보지 않는다")
    func reconcileNeedsSignIn() async {
        let backend = FakeCatalogBackend()
        let subject = stats(backend)

        await subject.reconcile(ownedTemplateIDs: [MINT], session: nil)

        #expect(backend.calls.isEmpty)
    }

    @Test("모르는 id는 보내지 않는다")
    func reconcileSendsOnlyKnownIDs() async {
        let backend = FakeCatalogBackend()
        let subject = stats(backend)

        await subject.reconcile(
            ownedTemplateIDs: [MINT, "내가-만든-거울", "민트 플라워", "random-uuid"],
            session: session()
        )

        #expect(backend.calls.contains("reconcile(\(MINT))"))
        #expect(!backend.calls.contains { $0.contains("민트 플라워") })
    }

    @Test("보낼 것이 없으면 부르지 않는다")
    func reconcileWithNothingOwned() async {
        let backend = FakeCatalogBackend()
        let subject = stats(backend)

        await subject.reconcile(ownedTemplateIDs: ["내가-만든-거울"], session: session())

        #expect(backend.calls.isEmpty)
    }

    @Test("로그아웃하면 맞춰 본 기록을 물려주지 않는다")
    func clearForgetsReconciliation() async {
        let backend = FakeCatalogBackend()
        let subject = stats(backend)
        await subject.reconcile(ownedTemplateIDs: [MINT], session: session())

        subject.clear()
        await subject.reconcile(ownedTemplateIDs: [MINT], session: session())

        #expect(backend.calls.filter { $0.hasPrefix("reconcile") }.count == 2)
    }
}

// MARK: - 내가 가진 내장 템플릿

@Suite("이전 다운로드 찾기")
struct OwnedTemplateDetectionTests {

    private func mirror(id: String, name: String) -> MyMirror {
        MyMirror(id: id, name: name, origin: .purchased, style: MirrorStyle(frame: .white))
    }

    @Test("민트 플라워의 안정적 id")
    func mintFlowerStableID() throws {
        let found = try #require(StoreCatalog.samples.first { $0.name == "민트 플라워" })
        #expect(found.id == MINT)
    }

    @Test("local MyMirror.id로 이전 다운로드를 찾는다")
    func findsPreviousDownloadByID() {
        let library = [
            mirror(id: MINT, name: "민트 플라워"),
            mirror(id: "art-pink-ribbon", name: "핑크 리본"),
        ]

        let found = StoreCatalog.ownedTemplateIDs(in: library)

        #expect(Set(found) == [MINT, "art-pink-ribbon"])
    }

    @Test("사용자가 이름을 바꿔도 찾는다 — 제목을 보지 않는다")
    func nameChangeDoesNotBreakDetection() {
        let library = [mirror(id: MINT, name: "내가 바꾼 이름")]

        #expect(StoreCatalog.ownedTemplateIDs(in: library) == [MINT])
    }

    @Test("이름만 같고 id가 다르면 찾지 않는다")
    func titleAloneIsNotEnough() {
        let library = [mirror(id: "my-own-mirror", name: "민트 플라워")]

        #expect(StoreCatalog.ownedTemplateIDs(in: library).isEmpty)
    }

    @Test("내가 만든 거울은 내장 템플릿이 아니다")
    func userMadeMirrorsAreNotTemplates() {
        let library = [
            mirror(id: UUID().uuidString, name: "내 거울"),
            mirror(id: "some-listing-id", name: "산 거울"),
        ]

        #expect(StoreCatalog.ownedTemplateIDs(in: library).isEmpty)
    }

    @Test("기본 거울도 내장 템플릿이다")
    func basicMirrorsCount() {
        let anyBasic = StoreCatalog.basics[0].id
        let library = [mirror(id: anyBasic, name: "화이트")]

        #expect(StoreCatalog.ownedTemplateIDs(in: library) == [anyBasic])
    }
}

// MARK: - 규칙

@Suite("통계 표시 규칙")
struct CatalogDisplayRuleTests {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "ggumirror")
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    @Test("카드가 서버 값을 쓴다 — 하드코딩 숫자가 없다")
    func cardUsesServerValue() throws {
        let code = try source("Store/StoreView.swift")
        #expect(code.contains("catalogStats.downloadCount(template.id)"))
        // 모르면 안 보여 준다 — 판단은 공통 카드가 한다.
        #expect(try source("Store/StoreMirrorCard.swift")
            .contains("if let downloadCount = model.downloadCount"))
        // 옛 하드코딩 경로가 남아 있지 않다.
        #expect(!code.contains("Label(\"\\(template.downloadCount)\""))
    }

    @Test("상세도 같은 규칙을 쓴다")
    func detailUsesServerValue() throws {
        let code = try source("Store/TemplateDetailView.swift")
        #expect(code.contains("catalogStats.downloadCount(template.id)"))
        #expect(!code.contains("다운로드 \\(template.downloadCount)"))
    }

    @Test("로컬 획득이 성공한 뒤에 서버에 기록한다")
    func recordsAfterLocalAcquire() throws {
        let code = try source("Store/TemplateDetailView.swift")
        let acquire = try #require(code.range(of: "library.acquire(template)"))
        let record = try #require(code.range(of: "catalogStats.recordAcquisition"))
        #expect(acquire.lowerBound < record.lowerBound, "서버 기록이 로컬 저장보다 먼저다")
    }

    @Test("client가 수를 직접 계산하지 않는다")
    func clientNeverComputesCounts() throws {
        for path in ["Store/CatalogStats.swift", "Store/StoreView.swift"] {
            let code = try source(path)
            for banned in ["downloadCount +", "downloadCount +=", "count += 1"] {
                #expect(!code.contains(banned), "\(path): 앱이 수를 올린다")
            }
        }
    }

    @Test("맞춰 보기가 안정적 id만 보낸다")
    func reconcileUsesStableIDs() throws {
        let code = codeWithoutComments(try source("Store/CatalogStats.swift"))
        #expect(code.contains("StoreCatalog.samples.map(\\.id)"))
        // 제목을 쓰지 않는다.
        #expect(!code.contains(".name"))
        #expect(!code.contains("title"))
    }

    @Test("catalog가 Marketplace 경로를 섞지 않는다")
    func catalogIsSeparateFromMarketplace() throws {
        let code = codeWithoutComments(try source("Store/CatalogStats.swift"))
        for banned in ["MarketplaceListing", "listingId", "ownership", "priceShards"] {
            #expect(!code.contains(banned), "Marketplace 경로가 섞였다")
        }
    }

    @Test("token을 로그하지 않는다")
    func neverLogsTokens() throws {
        for path in ["Store/CatalogStats.swift", "Backend/BackendClient+Catalog.swift"] {
            let code = try source(path)
            for banned in ["print(", "UIPasteboard", "UserDefaults", "#if DEBUG"] {
                #expect(!code.contains(banned), "\(path): \(banned)")
            }
        }
    }
}

// MARK: - 이전 판매 중지 (legacy unlisted)

@Suite("이전 판매 중지")
struct RetiredListingsTests {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "ggumirror")
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    @Test("내 판매에 이전 판매 중지 구획이 있다")
    func sectionExists() throws {
        let code = codeWithoutComments(try source("Store/MySalesSection.swift"))
        #expect(code.contains("\"이전 판매 중지\""))
        #expect(code.contains("filter(\\.isUnlisted)"))
    }

    @Test("세 구획이 상태별로 나뉜다")
    func threeSections() throws {
        let code = codeWithoutComments(try source("Store/MySalesSection.swift"))
        #expect(code.contains("filter(\\.isPublished)"))
        #expect(code.contains("filter(\\.isDraft)"))
        #expect(code.contains("filter(\\.isUnlisted)"))
        // deleted는 어디에도 없다.
        #expect(!code.contains("filter(\\.isDeleted)"))
    }

    @Test("이전 판매 중지에는 삭제만 있고 다시 판매가 없다")
    func onlyDeleteForRetired() throws {
        let code = codeWithoutComments(try source("Store/MySalesSection.swift"))
        let start = try #require(code.range(of: "if listing.isUnlisted {"))
        let block = String(code[start.upperBound...].prefix(240))
        #expect(block.contains("pendingDelete"))
        #expect(!block.contains("다시 판매"))
        #expect(!block.contains("republish"))
    }

    @Test("삭제 문구가 종류별 등록비를 말한다")
    func deleteCopyMentionsFee() {
        let mirror = MarketplaceOwnedListing(
            id: "a", contentType: "mirror", title: "t", description: "", priceShards: 0,
            status: "unlisted", downloadCount: 0, likeCount: 0, publishedAt: nil
        )
        let sticker = MarketplaceOwnedListing(
            id: "b", contentType: "sticker", title: "t", description: "", priceShards: 0,
            status: "unlisted", downloadCount: 0, likeCount: 0, publishedAt: nil
        )
        #expect(mirror.publishFeeShards == MirrorPublishPolicy.feeInShards)
        #expect(sticker.publishFeeShards == StickerPublishPolicy.feeInShards)
    }

    @Test("삭제는 기존 soft-delete endpoint를 쓴다")
    func usesExistingDeleteEndpoint() throws {
        let code = try source("Backend/BackendClient+Marketplace.swift")
        #expect(code.contains("users/me/marketplace/listings/"))
        #expect(code.contains("method: \"DELETE\""))
    }

    @Test("deleted 상태가 판매 중에 들어가지 않는다")
    func deletedIsNotSelling() {
        let deleted = MarketplaceOwnedListing(
            id: "a", contentType: "mirror", title: "t", description: "", priceShards: 0,
            status: "deleted", downloadCount: 0, likeCount: 0, publishedAt: nil
        )
        #expect(deleted.isDeleted)
        #expect(!deleted.isPublished)
        #expect(!deleted.isUnlisted)
        #expect(!deleted.isDraft)
    }
}
