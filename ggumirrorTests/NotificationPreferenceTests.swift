//
//  NotificationPreferenceTests.swift
//  ggumirrorTests
//
//  I-11 · I-15. 무엇을 받을지 고르는 것과, 알림센터가 새 종류를 견디는 것.
//

import Testing
import Foundation
@testable import ggumirror

private func prefSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

private func session(_ id: String = "u1") -> ServerSession {
    ServerSession(accessToken: "t-\(id)", expiresAt: .distantFuture, userID: id)
}

private nonisolated final class FakePreferenceBackend: NotificationBackend, @unchecked Sendable {
    var stored = NotificationPreferences.fallback
    var failNextSave = false
    var saves = 0

    func notificationPreferences(accessToken: String) async throws -> NotificationPreferences {
        stored
    }

    func updateNotificationPreferences(
        salesEnabled: Bool?, digestFrequency: DigestFrequency?,
        recommendationEnabled: Bool?, accessToken: String
    ) async throws -> NotificationPreferences {
        saves += 1
        if failNextSave { throw NotificationFailure.network }
        // 보낸 값만 바뀐다 — 서버와 같은 규칙이다.
        stored = NotificationPreferences(
            salesEnabled: salesEnabled ?? stored.salesEnabled,
            mirrorDigestFrequency: digestFrequency ?? stored.mirrorDigestFrequency,
            recommendationEnabled: recommendationEnabled ?? stored.recommendationEnabled
        )
        return stored
    }

    func notifications(cursor: String?, accessToken: String) async throws -> SaleNotificationPage {
        SaleNotificationPage(notifications: [], cursor: nil)
    }
    func saleStats(accessToken: String) async throws -> [SaleStat] { [] }
    func markNotificationRead(id: String, accessToken: String) async throws -> SaleNotification {
        throw NotificationFailure.notFound
    }
    func registerPushDevice(token: String, environment: PushEnvironment, accessToken: String) async throws {}
    func unregisterPushDevice(token: String, environment: PushEnvironment, accessToken: String) async throws {}
}

@Suite("알림 설정")
@MainActor
struct NotificationPreferenceSessionTests {

    @Test("서버 문서가 없으면 판매만 켜져 있다")
    func defaultsMatchTheServer() {
        let fallback = NotificationPreferences.fallback
        #expect(fallback.salesEnabled)
        #expect(fallback.mirrorDigestFrequency == .off)
        #expect(!fallback.recommendationEnabled)
    }

    @Test("옛 응답에 값이 없어도 기본값으로 읽는다")
    func legacyResponseDecodes() throws {
        let decoded = try JSONDecoder.backend.decode(
            NotificationPreferences.self, from: Data("{}".utf8)
        )
        #expect(decoded.salesEnabled)
        #expect(decoded.mirrorDigestFrequency == .off)
    }

    @Test("모르는 주기는 끔이다")
    func unknownFrequencyIsOff() {
        #expect(DigestFrequency.of("hourly") == .off)
        #expect(DigestFrequency.of(nil) == .off)
        #expect(DigestFrequency.of("weekly") == .weekly)
    }

    @Test("판매 토글이 서버에 저장된다")
    func salesTogglePersists() async {
        let backend = FakePreferenceBackend()
        let store = NotificationPreferenceSession(backend: backend)

        await store.setSales(false, session: session())

        #expect(!store.preferences.salesEnabled)
        #expect(!backend.stored.salesEnabled)
    }

    @Test("주기를 고르면 저장된다")
    func digestSelectionPersists() async {
        let backend = FakePreferenceBackend()
        let store = NotificationPreferenceSession(backend: backend)

        await store.setDigest(.weekly, session: session())

        #expect(store.preferences.mirrorDigestFrequency == .weekly)
        // 다른 값은 건드리지 않는다.
        #expect(backend.stored.salesEnabled)
    }

    @Test("추천 토글이 서버에 저장된다")
    func recommendationTogglePersists() async {
        let backend = FakePreferenceBackend()
        let store = NotificationPreferenceSession(backend: backend)

        await store.setRecommendation(true, session: session())

        #expect(store.preferences.recommendationEnabled)
    }

    @Test("저장에 실패하면 되돌리고 알린다")
    func failureRollsBack() async {
        let backend = FakePreferenceBackend()
        let store = NotificationPreferenceSession(backend: backend)
        backend.failNextSave = true

        await store.setDigest(.daily, session: session())

        // 켜진 것처럼 두면 오지 않는 알림을 기다리게 된다.
        #expect(store.preferences.mirrorDigestFrequency == .off)
        #expect(store.failure != nil)
    }

    @Test("로그인하지 않으면 서버를 부르지 않는다")
    func guestNeverSaves() async {
        let backend = FakePreferenceBackend()
        let store = NotificationPreferenceSession(backend: backend)

        await store.setSales(false, session: nil)

        #expect(backend.saves == 0)
        #expect(store.failure != nil)
    }

    @Test("계정이 바뀌면 이전 설정이 남지 않는다")
    func accountSwitchClears() async {
        let backend = FakePreferenceBackend()
        backend.stored = NotificationPreferences(
            salesEnabled: false, mirrorDigestFrequency: .weekly, recommendationEnabled: true
        )
        let store = NotificationPreferenceSession(backend: backend)
        await store.refresh(session: session("A"))
        #expect(store.preferences.mirrorDigestFrequency == .weekly)

        backend.stored = .fallback
        await store.refresh(session: session("B"))

        #expect(store.preferences.mirrorDigestFrequency == .off)
        #expect(store.preferences.salesEnabled)
    }

    @Test("로그아웃하면 기본값으로 돌아간다")
    func signOutResets() async {
        let backend = FakePreferenceBackend()
        backend.stored = NotificationPreferences(
            salesEnabled: false, mirrorDigestFrequency: .daily, recommendationEnabled: true
        )
        let store = NotificationPreferenceSession(backend: backend)
        await store.refresh(session: session("A"))

        await store.refresh(session: nil)

        #expect(store.preferences == .fallback)
    }
}

@Suite("알림센터가 새 종류를 견딘다")
struct NotificationKindTests {

    private func decode(_ json: String) throws -> SaleNotification {
        try JSONDecoder.backend.decode(SaleNotification.self, from: Data(json.utf8))
    }

    @Test("옛 판매 알림이 그대로 읽힌다")
    func legacySaleDecodes() throws {
        let item = try decode("""
        {"id":"n1","type":"marketplace_sale","listingId":"L","contentType":"mirror",
         "title":"먹방거울","shardAmount":3,"createdAt":"2026-08-01T00:00:00Z","read":false}
        """)
        #expect(item.kind == .sale)
        #expect(item.displayTitle.contains("먹방거울"))
        #expect(item.displayBody.contains("3조각"))
    }

    @Test("모아 보기는 상품 없이 읽힌다")
    func digestDecodes() throws {
        let item = try decode("""
        {"id":"n2","type":"mirror_digest","headline":"새로운 거울이 올라왔어요 🪞",
         "body":"오늘 새 거울 7개를 구경해보세요.","createdAt":"2026-08-01T00:00:00Z","read":false}
        """)
        #expect(item.kind == .mirrorDigest)
        #expect(item.listingId.isEmpty)
        #expect(item.displayTitle == "새로운 거울이 올라왔어요 🪞")
    }

    @Test("모르는 종류가 목록을 깨뜨리지 않는다")
    func unknownKindStillDecodes() throws {
        let item = try decode("""
        {"id":"n3","type":"something_from_2030","createdAt":"2026-08-01T00:00:00Z","read":false}
        """)
        #expect(item.kind == .unknown)
        // raw 값을 사용자에게 보여 주지 않는다.
        #expect(!item.displayTitle.contains("2030"))
        #expect(!item.displayTitle.isEmpty)
        #expect(!item.displayBody.isEmpty)
    }

    @Test("섞인 페이지가 통째로 읽힌다")
    func mixedPageDecodes() throws {
        let page = try JSONDecoder.backend.decode(SaleNotificationPage.self, from: Data("""
        {"notifications":[
          {"id":"a","type":"marketplace_sale","listingId":"L","contentType":"mirror",
           "title":"거울","shardAmount":1,"createdAt":"2026-08-03T00:00:00Z","read":false},
          {"id":"b","type":"mirror_digest","headline":"새 거울","body":"7개",
           "createdAt":"2026-08-02T00:00:00Z","read":false},
          {"id":"c","type":"future_kind","createdAt":"2026-08-01T00:00:00Z","read":true}
        ],"cursor":"c"}
        """.utf8))

        // **하나가 모르는 종류라고 나머지를 잃지 않는다.**
        #expect(page.notifications.count == 3)
        #expect(page.notifications.map(\.kind) == [.sale, .mirrorDigest, .unknown])
        #expect(page.cursor == "c")
    }

    @Test("추천 소식은 알림센터에 오지 않는다")
    func recommendationIsPushOnly() throws {
        // 서버가 center event를 만들지 않는다(backend test가 고정). client는
        // 혹시 오더라도 안전하게 그린다.
        let item = try decode("""
        {"id":"n4","type":"recommendation","headline":"다시 둘러보세요",
         "body":"새 거울이 있어요","createdAt":"2026-08-01T00:00:00Z","read":false}
        """)
        #expect(item.kind == .recommendation)
        #expect(item.displayTitle == "다시 둘러보세요")
    }

    @Test("화면이 종류마다 분기하지 않는다")
    func viewDelegatesCopyToTheModel() throws {
        let view = try prefSource("ggumirror/Notifications/NotificationCenterView.swift")
        #expect(view.contains("item.displayTitle"))
        #expect(view.contains("item.displayBody"))
        // 모아 보기는 상품 하나가 아니라 상점으로 간다.
        #expect(view.contains("item.kind == .mirrorDigest"))
    }
}

@Suite("설정 화면")
struct NotificationSettingsUITests {

    @Test("세 가지를 따로 고를 수 있다")
    func threeControlsExist() throws {
        let settings = try prefSource("ggumirror/Home/SettingsView.swift")
        #expect(settings.contains("판매 알림"))
        #expect(settings.contains("새 거울 소식"))
        #expect(settings.contains("꾸미러 추천 소식"))
        #expect(settings.contains("DigestFrequency.allCases"))
    }

    @Test("OS 권한과 앱 설정을 섞지 않는다")
    func osPermissionIsSeparate() throws {
        let settings = try prefSource("ggumirror/Home/SettingsView.swift")
        // 권한이 꺼져 있으면 그 사실을 따로 보여 준다 — 토글을 몰래 끄지 않는다.
        #expect(settings.contains("permission == .denied"))
        #expect(settings.contains("openSettingsURLString"))
        let session = try prefSource("ggumirror/Notifications/NotificationPreferenceSession.swift")
        #expect(!session.contains("UNUserNotificationCenter"))
        #expect(!session.contains("permission"))
    }

    @Test("토글이 먹통처럼 느껴지지 않는다")
    func togglesAreOptimistic() throws {
        let session = try prefSource("ggumirror/Notifications/NotificationPreferenceSession.swift")
        // 화면을 먼저 바꾸고, 실패하면 되돌린다.
        #expect(session.contains("preferences = optimistic"))
        #expect(session.contains("preferences = previous"))
    }

    @Test("I-10 온보딩이 설정을 강제로 켜지 않는다")
    func onboardingDoesNotForceMarketingPreferences() throws {
        let root = try prefSource("ggumirror/RootView.swift")
        let sheet = try prefSource("ggumirror/Notifications/NotificationOnboardingSheet.swift")
        // 시스템 권한만 다룬다 — 종류별 설정은 사용자가 설정에서 고른다.
        for banned in ["setDigest", "setRecommendation", "recommendationEnabled"] {
            #expect(!sheet.contains(banned), "온보딩이 \(banned)를 건드린다")
            #expect(!root.contains(banned), "시작 경로가 \(banned)를 건드린다")
        }
    }
}
