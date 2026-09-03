//
//  AdminModerationTests.swift
//  ggumirrorTests
//
//  운영자 상점 관리.
//
//  지키는 것 둘: **권한을 앱이 정하지 않는다**, 그리고
//  **실패하면 화면이 거짓 상태를 보여주지 않는다.**
//

import Testing
import Foundation
@testable import ggumirror

private func source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

private func listing(
    _ id: String = "L1",
    moderation: String = "active",
    status: String = "published",
    reason: String? = nil,
    type: String = "mirror"
) -> AdminListing {
    let json = """
    {"id":"\(id)","contentType":"\(type)","title":"거울 \(id)","description":"",
     "priceShards":3,"status":"\(status)","moderationStatus":"\(moderation)",
     "moderationReason":\(reason.map { "\"\($0)\"" } ?? "null"),
     "downloadCount":7,"likeCount":2,
     "createdAt":"2026-08-01T00:00:00Z","publishedAt":"2026-08-01T00:00:00Z",
     "sellerDisplayName":"판매자"}
    """
    return try! JSONDecoder.backend.decode(AdminListing.self, from: Data(json.utf8))
}

private nonisolated final class FakeAdminBackend: AdminBackend, @unchecked Sendable {
    var admin = true
    var pages: [AdminListingPage] = []
    var failure: AdminFailure?
    var takedownCalls: [(String, AdminModerationReason)] = []
    var restoreCalls: [String] = []
    var listCalls: [(String?, String?)] = []
    /// 두 요청이 겹치는지 보기 위한 문. 열릴 때까지 조치가 끝나지 않는다.
    var gate: (@Sendable () async -> Void)?

    func isAdmin(accessToken: String) async throws -> Bool {
        if let failure { throw failure }
        return admin
    }

    func adminListings(
        contentType: String?, moderationStatus: String?, cursor: String?, accessToken: String
    ) async throws -> AdminListingPage {
        listCalls.append((contentType, moderationStatus))
        if let failure { throw failure }
        return pages.isEmpty ? AdminListingPage(listings: [], cursor: nil) : pages.removeFirst()
    }

    func adminPreview(listingID: String, accessToken: String) async throws -> Data { Data([1]) }

    func takedown(
        listingID: String, reason: AdminModerationReason, accessToken: String
    ) async throws -> AdminListing {
        takedownCalls.append((listingID, reason))
        // **첫 요청만 붙잡는다.** 둘 다 붙잡으면 문이 열리기를 서로 기다려서
        // 연타 방어가 사라졌을 때 test가 실패 대신 멈춘다.
        if takedownCalls.count == 1 { await gate?() }
        if let failure { throw failure }
        return listing(listingID, moderation: "removed", reason: reason.rawValue)
    }

    func restore(listingID: String, accessToken: String) async throws -> AdminListing {
        restoreCalls.append(listingID)
        if let failure { throw failure }
        return listing(listingID, moderation: "active")
    }
}

extension AdminListingPage {
    /// `AdminListing`은 Decodable뿐이라(서버가 authority다) JSON을 손으로 만든다.
    static func make(_ listings: [AdminListing], _ cursor: String?) -> AdminListingPage {
        let rows = listings.map { l in
            """
            {"id":"\(l.id)","contentType":"\(l.contentType)","title":"\(l.title)",
             "description":"","priceShards":\(l.priceShards),"status":"\(l.status)",
             "moderationStatus":"\(l.moderationStatus)","moderationReason":null,
             "downloadCount":\(l.downloadCount),"likeCount":\(l.likeCount),
             "createdAt":"2026-08-01T00:00:00Z","publishedAt":"2026-08-01T00:00:00Z",
             "sellerDisplayName":"판매자"}
            """
        }.joined(separator: ",")
        let json = "{\"listings\":[\(rows)],\"cursor\":\(cursor.map { "\"\($0)\"" } ?? "null")}"
        return try! JSONDecoder.backend.decode(AdminListingPage.self, from: Data(json.utf8))
    }
}

private func signedIn() -> ServerSession {
    ServerSession(accessToken: "t", expiresAt: .distantFuture, userID: "u1")
}

@Suite("운영자 목록")
@MainActor
struct AdminStoreTests {

    @Test("목록을 받아 온다")
    func loadsListings() async {
        let backend = FakeAdminBackend()
        backend.pages = [.make([listing("A"), listing("B")], nil)]
        let store = AdminStore(backend: backend)

        await store.reload(session: signedIn())

        #expect(store.listings.count == 2)
        #expect(!store.hasMore)
    }

    @Test("거울과 스티커를 한 화면에서 거른다")
    func filtersByContentType() async {
        let backend = FakeAdminBackend()
        backend.pages = [.make([], nil), .make([], nil)]
        let store = AdminStore(backend: backend)
        store.contentType = "sticker"

        await store.reload(session: signedIn())

        #expect(backend.listCalls.last?.0 == "sticker")
    }

    @Test("다음 장이 있으면 이어 받는다")
    func paginates() async {
        let backend = FakeAdminBackend()
        backend.pages = [.make([listing("A")], "A"), .make([listing("B")], nil)]
        let store = AdminStore(backend: backend)
        let session = signedIn()

        await store.reload(session: session)
        #expect(store.hasMore)
        await store.loadMore(session: session)

        #expect(store.listings.map(\.id) == ["A", "B"])
        #expect(!store.hasMore)
    }

    @Test("같은 상품을 두 번 넣지 않는다")
    func doesNotDuplicate() async {
        let backend = FakeAdminBackend()
        backend.pages = [.make([listing("A")], "A"), .make([listing("A"), listing("B")], nil)]
        let store = AdminStore(backend: backend)
        let session = signedIn()

        await store.reload(session: session)
        await store.loadMore(session: session)

        #expect(store.listings.map(\.id) == ["A", "B"])
    }

    @Test("받아 온 장 안에서 찾는다")
    func searchesTheLoadedPage() async {
        let backend = FakeAdminBackend()
        backend.pages = [.make([listing("A"), listing("B")], nil)]
        let store = AdminStore(backend: backend)
        await store.reload(session: signedIn())

        store.query = "거울 B"
        #expect(store.visible.map(\.id) == ["B"])
        store.query = "판매자"
        #expect(store.visible.count == 2)
    }

    @Test("로그인하지 않으면 서버를 부르지 않는다")
    func guestNeverCallsTheBackend() async {
        let backend = FakeAdminBackend()
        let store = AdminStore(backend: backend)

        await store.reload(session: nil)

        #expect(backend.listCalls.isEmpty)
    }
}

@Suite("운영자 조치")
@MainActor
struct AdminModerationActionTests {

    private func loaded(_ backend: FakeAdminBackend) async -> (AdminStore, ServerSession) {
        backend.pages = [.make([listing("A")], nil)]
        let store = AdminStore(backend: backend)
        let session = signedIn()
        await store.reload(session: session)
        return (store, session)
    }

    @Test("내리면 그 자리에서 상태가 바뀐다")
    func takedownUpdatesInPlace() async {
        let backend = FakeAdminBackend()
        let (store, session) = await loaded(backend)

        let ok = await store.takedown("A", reason: .spam, session: session)

        #expect(ok)
        #expect(store.listings[0].isRemoved)
        // 목록 전체를 다시 받지 않는다 — 조회는 처음 한 번뿐이다.
        #expect(backend.listCalls.count == 1)
    }

    @Test("사유를 그대로 보낸다")
    func sendsTheChosenReason() async {
        let backend = FakeAdminBackend()
        let (store, session) = await loaded(backend)

        _ = await store.takedown("A", reason: .copyright, session: session)

        #expect(backend.takedownCalls.map(\.1) == [.copyright])
    }

    @Test("실패하면 목록을 건드리지 않는다")
    func failureLeavesTheListAlone() async {
        let backend = FakeAdminBackend()
        let (store, session) = await loaded(backend)
        backend.failure = .cannotChange

        let ok = await store.takedown("A", reason: .spam, session: session)

        #expect(!ok)
        // **거짓 상태를 보여주지 않는다** — 서버가 거절했으면 화면도 그대로다.
        #expect(!store.listings[0].isRemoved)
        #expect(store.failure == .cannotChange)
    }

    @Test("처리 중에는 두 번째 요청을 만들지 않는다")
    func doubleTapIsBlocked() async {
        let backend = FakeAdminBackend()
        let (store, session) = await loaded(backend)

        let opened = AsyncGate()
        backend.gate = { await opened.wait() }

        async let first = store.takedown("A", reason: .spam, session: session)
        // 첫 요청이 서버에 닿을 때까지 기다린다.
        while backend.takedownCalls.isEmpty { await Task.yield() }
        let second = await store.takedown("A", reason: .spam, session: session)
        await opened.open()
        _ = await first

        #expect(!second)
        #expect(backend.takedownCalls.count == 1)
    }

    @Test("복구하면 다시 공개 상태가 된다")
    func restoreUpdatesInPlace() async {
        let backend = FakeAdminBackend()
        backend.pages = [.make([listing("A", moderation: "removed")], nil)]
        let store = AdminStore(backend: backend)
        let session = signedIn()
        await store.reload(session: session)

        let ok = await store.restore("A", session: session)

        #expect(ok)
        #expect(!store.listings[0].isRemoved)
        #expect(backend.restoreCalls == ["A"])
    }

    @Test("권한이 없으면 그렇게 말한다")
    func notAdminIsExplained() async {
        let backend = FakeAdminBackend()
        let (store, session) = await loaded(backend)
        backend.failure = .notAdmin

        _ = await store.takedown("A", reason: .spam, session: session)

        #expect(store.failure == .notAdmin)
        #expect(store.failure?.message == "권한이 없어요.")
    }
}

@Suite("권한은 서버가 정한다")
struct AdminAuthorityTests {

    @Test("앱이 자기 권한을 저장하지 않는다")
    func nothingPersistsTheAdminFlag() throws {
        for path in [
            "ggumirror/Home/SettingsView.swift",
            "ggumirror/Admin/AdminStoreView.swift",
            "ggumirror/Backend/BackendClient+Admin.swift",
        ] {
            let code = try source(path)
            // `UserDefaults`나 `@AppStorage`에 담기면 계정을 바꿔도 남는다.
            #expect(!code.contains("AppStorage(\"isAdmin"))
            #expect(!code.contains("UserDefaults"))
        }
    }

    @Test("이름이나 이메일로 판단하지 않는다")
    func neverInfersFromIdentity() throws {
        let settings = try source("ggumirror/Home/SettingsView.swift")
        let api = try source("ggumirror/Backend/BackendClient+Admin.swift")
        for guess in ["displayName ==", "email", "mark77234", "@naver", "sub =="] {
            #expect(!settings.contains(guess), "설정이 \(guess)로 권한을 추측한다")
            #expect(!api.contains(guess), "API가 \(guess)로 권한을 추측한다")
        }
    }

    @Test("서버에 물어본 답으로만 항목을 보인다")
    func rowFollowsTheServerAnswer() throws {
        let code = try source("ggumirror/Home/SettingsView.swift")
        #expect(code.contains("isAdmin == true"))
        #expect(code.contains("isAdmin(accessToken:"))
    }

    @Test("확인 전에는 항목이 없다")
    func hiddenUntilAnswered() throws {
        let code = try source("ggumirror/Home/SettingsView.swift")
        // `Bool?`이라 확인 전(`nil`)과 아님(`false`)이 모두 숨김이다.
        #expect(code.contains("isAdmin: Bool?"))
    }

    @Test("확인에 실패해도 설정이 깨지지 않는다")
    func failureDoesNotBreakSettings() throws {
        let code = try source("ggumirror/Home/SettingsView.swift")
        let start = try #require(code.range(of: "private func checkAdmin()")).upperBound
        let body = code[start...].prefix(400)
        // 던지지 않는다 — 대부분의 사용자에게 403이 정상 답이다.
        #expect(body.contains("try? await"))
        #expect(body.contains("?? false"))
    }

    @Test("client가 권한을 보내지 않는다")
    func clientSendsNoAuthorityClaim() throws {
        let api = try source("ggumirror/Backend/BackendClient+Admin.swift")
        for claim in ["isAdmin: true", "role", "sellerId", "sellerUserId", "balance"] {
            #expect(!api.contains(claim))
        }
        // 내리기 요청에 실리는 것은 사유 하나다.
        #expect(api.contains("struct Body: Encodable { let reason: String }"))
    }

    @Test("권한 없음과 로그인 필요를 구분한다")
    func forbiddenIsNotUnauthenticated() {
        #expect(AdminFailure.from(status: 401, data: Data()) == .notSignedIn)
        // 뭉치면 "다시 로그인하세요"라고 말하게 되고, 그래도 달라지지 않는다.
        #expect(AdminFailure.from(status: 403, data: Data()) == .notAdmin)
        #expect(AdminFailure.from(status: 409, data: Data()) == .cannotChange)
    }
}

@Suite("판매자가 보는 것")
struct SellerModerationViewTests {

    @Test("옛 응답에는 이 값이 없다")
    func legacyResponseDecodes() throws {
        let json = """
        {"id":"L","contentType":"mirror","title":"제목","description":"",
         "priceShards":0,"status":"published","downloadCount":0,"likeCount":0,
         "publishedAt":"2026-08-01T00:00:00Z"}
        """
        let listing = try JSONDecoder.backend.decode(
            MarketplaceOwnedListing.self, from: Data(json.utf8)
        )
        #expect(listing.moderationStatus == "active")
        #expect(!listing.isModerated)
    }

    @Test("판매 중지는 판매자 상태와 다른 축이다")
    func moderationIsSeparateFromStatus() {
        let listing = MarketplaceOwnedListing(
            id: "L", contentType: "mirror", title: "제목", description: "",
            priceShards: 0, status: "published", downloadCount: 0, likeCount: 0,
            publishedAt: .now, moderationStatus: "removed"
        )
        #expect(listing.isPublished)
        #expect(listing.isModerated)
    }

    @Test("다시 판매 버튼을 주지 않는다")
    func noRepublishButton() throws {
        let code = try source("ggumirror/Store/MyListingsSection.swift")
        #expect(code.contains("isUnlisted && !listing.isModerated"))
        #expect(code.contains("isDraft && !listing.isModerated"))
    }

    @Test("중지됐다고 알린다")
    func tellsTheSeller() throws {
        let code = try source("ggumirror/Store/MyListingsSection.swift")
        #expect(code.contains("운영자에 의해 판매가 중지되었어요."))
    }

    @Test("사유 분류를 판매자에게 주지 않는다")
    func noReasonForTheSeller() throws {
        let api = try source("ggumirror/Backend/MarketplaceAPI.swift")
        let start = try #require(api.range(of: "struct MarketplaceOwnedListing")).upperBound
        let end = try #require(
            api.range(of: "nonisolated extension MarketplaceOwnedListing", range: start..<api.endIndex)
        ).lowerBound
        #expect(!api[start..<end].contains("moderationReason"))
    }

    @Test("다시 올리기가 거절되면 다시 시도하라고 하지 않는다")
    func moderatedIsNotRetryable() {
        #expect(!MarketplaceFailure.moderated.isTemporary)
        #expect(MarketplaceFailure.moderated.message.contains("다시 올릴 수 없어요"))
        // `cannotPublish`와 뭉치지 않는다 — 뭉치면 계속 다시 시도하게 된다.
        #expect(MarketplaceFailure.moderated != MarketplaceFailure.cannotPublish)
    }
}

/// test 안에서만 쓰는 문. 두 요청이 정말 겹치는지 보려면 하나를 붙잡아 둬야 한다.
private actor AsyncGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        isOpen = true
        continuations.forEach { $0.resume() }
        continuations = []
    }
}
