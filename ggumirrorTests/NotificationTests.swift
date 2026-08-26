//
//  NotificationTests.swift
//  ggumirrorTests
//
//  매일 알림 · 기기 등록 · 알림센터.
//
//  지키는 것 셋: **거부한 사람을 다시 조르지 않는다**, **우리 알림만 지운다**,
//  **계정이 바뀌면 기기를 다시 묶는다.**
//

import Testing
import Foundation
import UserNotifications
@testable import ggumirror

private func source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

// MARK: - fake

private nonisolated final class FakeScheduler: NotificationScheduling, @unchecked Sendable {
    var current: NotificationPermission = .allowed
    var grantsWhenAsked: NotificationPermission = .allowed
    var askCount = 0
    var remoteRegistrations = 0
    /// 예약된 것 전부 — **우리 것이 아닌 것도 담는다.**
    var pending: [String: UNNotificationRequest] = [:]
    var removed: [[String]] = []

    func permission() async -> NotificationPermission { current }

    func requestPermission() async -> NotificationPermission {
        askCount += 1
        current = grantsWhenAsked
        return current
    }

    func pendingIdentifiers() async -> [String] { Array(pending.keys) }

    func add(_ request: UNNotificationRequest) async throws {
        // iOS와 같다 — 같은 식별자로 다시 넣으면 덮어쓴다.
        pending[request.identifier] = request
    }

    func remove(identifiers: [String]) async {
        removed.append(identifiers)
        identifiers.forEach { pending.removeValue(forKey: $0) }
    }

    func registerForRemoteNotifications() async { remoteRegistrations += 1 }

    var ourIdentifiers: [String] {
        pending.keys.filter { $0.hasPrefix(DailyReminder.identifierPrefix) }.sorted()
    }

    func body(of identifier: String) -> String? {
        pending[identifier]?.content.body
    }

    func fireDate(of identifier: String) -> DateComponents? {
        (pending[identifier]?.trigger as? UNCalendarNotificationTrigger)?.dateComponents
    }
}

private func defaults() -> UserDefaults {
    let suite = UserDefaults(suiteName: "reminder-\(UUID().uuidString)")!
    suite.removePersistentDomain(forName: "reminder")
    return suite
}

private var seoul: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
}

private func noon(_ day: Int = 10) -> Date {
    seoul.date(from: DateComponents(year: 2026, month: 8, day: day, hour: 12))!
}

@MainActor
private func scheduler(
    _ fake: FakeScheduler, on: Bool = true
) -> DailyReminderScheduler {
    let store = defaults()
    store.set(on, forKey: DailyReminderScheduler.preferenceKey)
    return DailyReminderScheduler(scheduler: fake, calendar: seoul, defaults: store)
}

// MARK: - 매일 알림

@Suite("매일 저녁 알림")
@MainActor
struct DailyReminderTests {

    @Test("허락했으면 다음 며칠치를 잡는다")
    func schedulesTheComingDays() async {
        let fake = FakeScheduler()
        await scheduler(fake).refresh(now: noon())
        #expect(fake.ourIdentifiers.count == DailyReminder.scheduledDays)
    }

    @Test("저녁 8시에 뜬다")
    func firesInTheEvening() async {
        let fake = FakeScheduler()
        await scheduler(fake).refresh(now: noon())

        for id in fake.ourIdentifiers {
            let components = fake.fireDate(of: id)
            #expect(components?.hour == 20)
            #expect(components?.minute == 0)
        }
    }

    @Test("이미 지난 시각을 예약하지 않는다")
    func neverSchedulesThePast() async {
        let fake = FakeScheduler()
        // 밤 10시 — 오늘 저녁 8시는 지났다.
        let late = seoul.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 22))!
        await scheduler(fake).refresh(now: late)

        // 예약했다면 iOS가 즉시 띄운다.
        #expect(!fake.ourIdentifiers.contains("\(DailyReminder.identifierPrefix)2026-8-10"))
        #expect(fake.ourIdentifiers.first == "\(DailyReminder.identifierPrefix)2026-8-11")
    }

    @Test("문구가 매일 같지 않다")
    func messagesRotate() async {
        let fake = FakeScheduler()
        await scheduler(fake).refresh(now: noon())

        let bodies = fake.ourIdentifiers.compactMap { fake.body(of: $0) }
        #expect(Set(bodies).count > 1, "매일 같은 말만 하면 며칠 만에 읽히지 않는다")
        #expect(bodies.allSatisfy { DailyReminder.messages.contains($0) })
    }

    @Test("같은 날 문구는 다시 예약해도 같다")
    func messageIsStableForADay() async {
        let fake = FakeScheduler()
        let store = scheduler(fake)
        await store.refresh(now: noon())
        let first = fake.body(of: fake.ourIdentifiers[0])

        await store.refresh(now: noon())
        #expect(fake.body(of: fake.ourIdentifiers[0]) == first)
    }

    @Test("앱을 여러 번 열어도 쌓이지 않는다")
    func relaunchDoesNotDuplicate() async {
        let fake = FakeScheduler()
        let store = scheduler(fake)
        for _ in 0..<5 { await store.refresh(now: noon()) }
        #expect(fake.ourIdentifiers.count == DailyReminder.scheduledDays)
    }

    @Test("우리 알림만 지운다")
    func removesOnlyOurOwn() async {
        let fake = FakeScheduler()
        // 다른 기능이 예약해 둔 것.
        let other = UNNotificationRequest(
            identifier: "someone-elses-reminder",
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        try? await fake.add(other)

        let store = scheduler(fake)
        await store.refresh(now: noon())
        await store.disable()

        #expect(fake.pending["someone-elses-reminder"] != nil)
        #expect(fake.ourIdentifiers.isEmpty)
        // 전부 지우는 API를 쓰지 않았다.
        #expect(fake.removed.allSatisfy { batch in
            batch.allSatisfy { $0.hasPrefix(DailyReminder.identifierPrefix) }
        })
    }

    @Test("끄면 예약이 사라진다")
    func offRemovesEverything() async {
        let fake = FakeScheduler()
        let store = scheduler(fake)
        await store.refresh(now: noon())
        await store.disable()

        #expect(!store.isOn)
        #expect(fake.ourIdentifiers.isEmpty)
    }

    @Test("켜면 다시 잡힌다")
    func onSchedulesAgain() async {
        let fake = FakeScheduler()
        let store = scheduler(fake, on: false)
        await store.enable(now: noon())

        #expect(store.isOn)
        #expect(fake.ourIdentifiers.count == DailyReminder.scheduledDays)
    }

    @Test("아직 안 물어봤으면 앱 시작에 창을 띄우지 않는다")
    func startupNeverPrompts() async {
        let fake = FakeScheduler()
        fake.current = .notAsked
        await scheduler(fake).refresh(now: noon())

        // **앱을 켜자마자 권한 창을 띄우지 않는다.**
        #expect(fake.askCount == 0)
        #expect(fake.ourIdentifiers.isEmpty)
    }

    @Test("사용자가 켤 때는 물어봐도 된다")
    func togglingAsks() async {
        let fake = FakeScheduler()
        fake.current = .notAsked
        let store = scheduler(fake, on: false)
        await store.enable(now: noon())

        #expect(fake.askCount == 1)
        #expect(fake.ourIdentifiers.count == DailyReminder.scheduledDays)
    }

    @Test("거부한 사람을 다시 조르지 않는다")
    func deniedIsNeverAskedAgain() async {
        let fake = FakeScheduler()
        fake.current = .denied
        let store = scheduler(fake, on: false)

        await store.enable(now: noon())
        await store.refresh(now: noon())

        // `canAsk`가 거짓이라 창이 뜨지 않는다 — 떠도 iOS가 무시한다.
        #expect(fake.askCount == 0)
        #expect(fake.ourIdentifiers.isEmpty)
    }

    @Test("거부 상태를 화면이 알 수 있다")
    func deniedIsVisible() async {
        let fake = FakeScheduler()
        fake.current = .denied
        let store = scheduler(fake)
        await store.refreshPermission()
        #expect(store.permission == .denied)
    }

    @Test("허락이 취소되면 예약을 거둔다")
    func revokedPermissionClearsSchedule() async {
        let fake = FakeScheduler()
        let store = scheduler(fake)
        await store.refresh(now: noon())
        #expect(!fake.ourIdentifiers.isEmpty)

        // 설정 앱에서 껐다.
        fake.current = .denied
        await store.refresh(now: noon())

        #expect(fake.ourIdentifiers.isEmpty)
    }

    @Test("권한 상태를 정확히 옮긴다")
    func permissionMeaning() {
        #expect(NotificationPermission.notAsked.canAsk)
        #expect(!NotificationPermission.denied.canAsk)
        #expect(!NotificationPermission.allowed.canAsk)
        #expect(NotificationPermission.allowed.canSend)
        #expect(NotificationPermission.quiet.canSend)
        #expect(!NotificationPermission.denied.canSend)
        #expect(!NotificationPermission.notAsked.canSend)
    }

    @Test("설정은 계정이 아니라 기기의 것이다")
    func preferenceIsDeviceLevel() throws {
        let code = try source("ggumirror/Notifications/DailyReminder.swift")
        // 계정별로 두면 로그아웃할 때 알림이 사라진다 — 이건 판매 소식이 아니라
        // 앱으로 다시 오라는 알림이다.
        #expect(code.contains("UserDefaults"))
        #expect(!code.contains("userID") && !code.contains("ServerSession"))
    }

    @Test("서버 일정이 없다")
    func noServerSchedule() throws {
        let code = try source("ggumirror/Notifications/DailyReminder.swift")
        for banned in ["BackendClient", "accessToken", "URLSession", "APNs"] {
            #expect(!code.contains(banned), "매일 알림이 서버를 부른다 (\(banned))")
        }
    }
}

// MARK: - 기기 등록

private nonisolated final class FakePushBackend: NotificationBackend, @unchecked Sendable {
    var registered: [(token: String, environment: PushEnvironment, accessToken: String)] = []
    var unregistered: [String] = []
    var failsRegistration = false
    var page = SaleNotificationPage(notifications: [], cursor: nil)
    var stats: [SaleStat] = []

    func notifications(cursor: String?, accessToken: String) async throws -> SaleNotificationPage {
        page
    }
    func saleStats(accessToken: String) async throws -> [SaleStat] { stats }

    // I-11에서 protocol이 넓어졌다. 이 fake는 설정을 다루지 않으므로 기본값만 준다.
    func notificationPreferences(accessToken: String) async throws -> NotificationPreferences {
        .fallback
    }

    func updateNotificationPreferences(
        salesEnabled: Bool?, digestFrequency: DigestFrequency?,
        recommendationEnabled: Bool?, accessToken: String
    ) async throws -> NotificationPreferences {
        .fallback
    }
    func markNotificationRead(id: String, accessToken: String) async throws -> SaleNotification {
        throw NotificationFailure.notFound
    }

    func registerPushDevice(
        token: String, environment: PushEnvironment, accessToken: String
    ) async throws {
        if failsRegistration { throw NotificationFailure.network }
        registered.append((token, environment, accessToken))
    }

    func unregisterPushDevice(
        token: String, environment: PushEnvironment, accessToken: String
    ) async throws {
        unregistered.append(token)
    }
}

private func serverSession(_ userID: String) -> ServerSession {
    ServerSession(accessToken: "t-\(userID)", expiresAt: .distantFuture, userID: userID)
}

private let rawToken = Data([0xa1, 0xb2, 0xc3, 0xd4])
private let rawTokenHex = "a1b2c3d4"

@Suite("기기 등록")
@MainActor
struct PushRegistrationTests {

    @Test("token과 로그인이 둘 다 있어야 등록한다")
    func needsBoth() async {
        let backend = FakePushBackend()
        let registration = PushRegistration(backend: backend, scheduler: FakeScheduler())

        await registration.received(deviceToken: rawToken)
        #expect(backend.registered.isEmpty)      // 아직 로그인 전이다

        await registration.accountChanged(to: serverSession("A"))
        #expect(backend.registered.map(\.token) == [rawTokenHex])
    }

    @Test("token이 나중에 와도 등록된다")
    func tokenArrivingLate() async {
        let backend = FakePushBackend()
        let registration = PushRegistration(backend: backend, scheduler: FakeScheduler())

        await registration.accountChanged(to: serverSession("A"))
        #expect(backend.registered.isEmpty)

        await registration.received(deviceToken: rawToken)
        #expect(backend.registered.count == 1)
    }

    @Test("같은 기기·같은 계정을 다시 보내지 않는다")
    func doesNotResend() async {
        let backend = FakePushBackend()
        let registration = PushRegistration(backend: backend, scheduler: FakeScheduler())
        await registration.received(deviceToken: rawToken)
        let session = serverSession("A")

        await registration.accountChanged(to: session)
        await registration.accountChanged(to: session)
        await registration.accountChanged(to: session)

        #expect(backend.registered.count == 1)
    }

    @Test("계정이 바뀌면 다시 묶는다")
    func rebindsOnAccountSwitch() async {
        let backend = FakePushBackend()
        let registration = PushRegistration(backend: backend, scheduler: FakeScheduler())
        await registration.received(deviceToken: rawToken)

        await registration.accountChanged(to: serverSession("A"))
        await registration.accountChanged(to: serverSession("B"))

        // **B로 다시 묶었다.** 안 그러면 A가 B의 판매 알림을 받는다.
        #expect(backend.registered.map(\.accessToken) == ["t-A", "t-B"])
    }

    @Test("로그아웃하면 기기를 떼어 낸다")
    func unbindsOnSignOut() async {
        let backend = FakePushBackend()
        let registration = PushRegistration(backend: backend, scheduler: FakeScheduler())
        await registration.received(deviceToken: rawToken)
        let session = serverSession("A")
        await registration.accountChanged(to: session)

        await registration.unbind(session: session)

        #expect(backend.unregistered == [rawTokenHex])
    }

    @Test("등록 실패가 앱을 막지 않는다")
    func failureIsSurvivable() async {
        let backend = FakePushBackend()
        backend.failsRegistration = true
        let registration = PushRegistration(backend: backend, scheduler: FakeScheduler())

        await registration.received(deviceToken: rawToken)
        await registration.accountChanged(to: serverSession("A"))
        // 던지지 않았다. 다음에 다시 시도할 수 있게 등록 기록도 남기지 않는다.
        #expect(backend.registered.isEmpty)

        backend.failsRegistration = false
        await registration.accountChanged(to: serverSession("B"))
        #expect(backend.registered.count == 1)
    }

    @Test("권한이 없으면 APNs 등록을 요청하지 않는다")
    func noRemoteRegistrationWithoutPermission() async {
        let fake = FakeScheduler()
        fake.current = .notAsked
        let registration = PushRegistration(backend: FakePushBackend(), scheduler: fake)

        await registration.startIfAllowed()

        #expect(fake.remoteRegistrations == 0)
        #expect(fake.askCount == 0)      // 여기서 창을 띄우지 않는다
    }

    @Test("허락했으면 APNs에 등록한다")
    func registersWhenAllowed() async {
        let fake = FakeScheduler()
        let registration = PushRegistration(backend: FakePushBackend(), scheduler: fake)
        await registration.startIfAllowed()
        #expect(fake.remoteRegistrations == 1)
    }

    @Test("token을 16진수 문자열로 옮긴다")
    func tokenIsHex() async {
        let backend = FakePushBackend()
        let registration = PushRegistration(backend: backend, scheduler: FakeScheduler())
        await registration.received(deviceToken: rawToken)
        await registration.accountChanged(to: serverSession("A"))
        #expect(backend.registered.first?.token == rawTokenHex)
    }

    @Test("token을 로그에 남기지 않는다")
    func tokenIsNeverLogged() throws {
        let code = try source("ggumirror/Notifications/PushRegistration.swift")
        // 로그 줄에 token 변수가 실리면 안 된다.
        #expect(!code.contains("BackendLog.event(\"push device register failed \\(token"))
        #expect(!code.contains("print("))
    }

    @Test("환경을 앱이 지어내지 않는다")
    func environmentComesFromTheBuild() throws {
        let code = try source("ggumirror/Backend/BackendClient+Notifications.swift")
        // 빌드 설정이 정한다 — 사용자가 고르거나 서버 응답으로 바뀌지 않는다.
        #expect(code.contains("#if DEBUG"))
        #expect(!code.contains("var environment: PushEnvironment ="))
    }

    @Test("token이 경로에 들어가지 않는다")
    func tokenIsNotInTheURL() throws {
        let code = try source("ggumirror/Backend/BackendClient+Notifications.swift")
        // URL은 접근 로그와 중계 구간에 그대로 남는다.
        #expect(!code.contains("push-devices/\\("))
        #expect(code.contains("struct _DeviceBody"))
    }
}

// MARK: - 알림센터

@Suite("알림센터")
@MainActor
struct NotificationCenterTests {

    private func page(_ ids: [String], cursor: String? = nil, read: Bool = false)
        -> SaleNotificationPage
    {
        let rows = ids.map { id in
            """
            {"id":"\(id)","type":"marketplace_sale","listingId":"L","contentType":"mirror",
             "title":"먹방거울","shardAmount":3,"createdAt":"2026-08-01T00:00:00Z",
             "read":\(read)}
            """
        }.joined(separator: ",")
        let json = """
        {"notifications":[\(rows)],"cursor":\(cursor.map { "\"\($0)\"" } ?? "null")}
        """
        return try! JSONDecoder.backend.decode(SaleNotificationPage.self, from: Data(json.utf8))
    }

    @Test("내 알림을 받아 온다")
    func loads() async {
        let backend = FakePushBackend()
        backend.page = page(["n1", "n2"])
        let store = NotificationSession(backend: backend)

        await store.reload(session: serverSession("A"))

        #expect(store.notifications.count == 2)
        #expect(store.unreadCount == 2)
    }

    @Test("로그인하지 않으면 서버를 부르지 않는다")
    func guestLoadsNothing() async {
        let backend = FakePushBackend()
        backend.page = page(["n1"])
        let store = NotificationSession(backend: backend)

        await store.reload(session: nil)

        #expect(store.notifications.isEmpty)
    }

    @Test("계정이 바뀌면 이전 계정의 알림이 남지 않는다")
    func accountSwitchClears() async {
        let backend = FakePushBackend()
        backend.page = page(["n1"])
        let store = NotificationSession(backend: backend)
        await store.reload(session: serverSession("A"))
        #expect(!store.notifications.isEmpty)

        // **A의 판매 소식이 B의 화면에 남으면 안 된다.**
        backend.page = page([])
        await store.reload(session: serverSession("B"))

        #expect(store.notifications.isEmpty)
    }

    @Test("로그아웃하면 비운다")
    func signOutClears() async {
        let backend = FakePushBackend()
        backend.page = page(["n1"])
        let store = NotificationSession(backend: backend)
        await store.reload(session: serverSession("A"))

        store.adopt(nil)

        #expect(store.notifications.isEmpty)
        #expect(store.stats.isEmpty)
    }

    @Test("다음 장을 이어 받는다")
    func paginates() async {
        let backend = FakePushBackend()
        backend.page = page(["n1"], cursor: "n1")
        let store = NotificationSession(backend: backend)
        let session = serverSession("A")
        await store.reload(session: session)
        #expect(store.hasMore)

        backend.page = page(["n2"])
        await store.loadMore(session: session)

        #expect(store.notifications.map(\.id) == ["n1", "n2"])
        #expect(!store.hasMore)
    }

    @Test("같은 알림을 두 번 넣지 않는다")
    func noDuplicates() async {
        let backend = FakePushBackend()
        backend.page = page(["n1"], cursor: "n1")
        let store = NotificationSession(backend: backend)
        let session = serverSession("A")
        await store.reload(session: session)

        backend.page = page(["n1", "n2"])
        await store.loadMore(session: session)

        #expect(store.notifications.map(\.id) == ["n1", "n2"])
    }

    @Test("판매 현황을 함께 받는다")
    func loadsSaleStats() async {
        let backend = FakePushBackend()
        backend.stats = [stat("L1", "먹방거울", 4), stat("L2", "하트", 2)]
        let store = NotificationSession(backend: backend)

        await store.reload(session: serverSession("A"))

        #expect(store.stats.map(\.saleCount) == [4, 2])
    }

    @Test("판매 현황은 알림 개수와 다른 값이다")
    func statsAreNotACountOfNotifications() async {
        let backend = FakePushBackend()
        // 알림은 한 장도 없는데 판매 횟수는 4다 — 서버가 세는 값이기 때문이다.
        backend.page = page([])
        backend.stats = [stat("L1", "먹방거울", 4)]
        let store = NotificationSession(backend: backend)

        await store.reload(session: serverSession("A"))

        #expect(store.notifications.isEmpty)
        #expect(store.stats.first?.saleCount == 4)
    }

    @Test("읽음은 실패하면 화면을 바꾸지 않는다")
    func failedReadKeepsTheRow() async {
        let backend = FakePushBackend()
        backend.page = page(["n1"])
        let store = NotificationSession(backend: backend)
        let session = serverSession("A")
        await store.reload(session: session)

        // fake의 `markNotificationRead`는 항상 던진다.
        await store.markRead("n1", session: session)

        #expect(store.notifications[0].read == false)
    }

    @Test("서버 오류를 그대로 보여주지 않는다")
    func failuresAreTranslated() {
        for failure in [
            NotificationFailure.notSignedIn, .notFound, .invalidRequest,
            .network, .server(status: 500),
        ] {
            let message = failure.message
            #expect(!message.isEmpty)
            for leak in ["500", "http", "apns", "token"] {
                #expect(!message.lowercased().contains(leak), "\(failure): \(message)")
            }
        }
    }

    @Test("403은 권한이 아니라 로그인 문제로 다룬다")
    func statusMapping() {
        #expect(NotificationFailure.from(status: 401, data: Data()) == .notSignedIn)
        #expect(NotificationFailure.from(status: 404, data: Data()) == .notFound)
        #expect(NotificationFailure.from(status: 422, data: Data()) == .invalidRequest)
    }

    private func stat(_ id: String, _ title: String, _ count: Int) -> SaleStat {
        let json = """
        {"listingId":"\(id)","contentType":"mirror","title":"\(title)",
         "saleCount":\(count),"priceShards":3}
        """
        return try! JSONDecoder.backend.decode(SaleStat.self, from: Data(json.utf8))
    }
}

// MARK: - 자리와 흐름

@Suite("알림 진입점")
struct NotificationEntryTests {

    @Test("설정에서 알림센터로 갈 수 있다")
    func settingsHasTheEntry() throws {
        let code = try source("ggumirror/Home/SettingsView.swift")
        #expect(code.contains("SettingsRoute.notificationCenter"))
        #expect(code.contains("매일 거울 소식 받기"))
    }

    @Test("거부한 사람에게 설정 앱으로 가는 길을 준다")
    func deniedGetsAWayOut() throws {
        let code = try source("ggumirror/Home/SettingsView.swift")
        #expect(code.contains("openSettingsURLString"))
        #expect(code.contains("permission == .denied"))
    }

    @Test("앱을 켜자마자 권한을 묻지 않는다")
    func launchNeverPrompts() throws {
        let code = try source("ggumirror/RootView.swift")
        // 시작 경로에는 `refresh`만 있다 — `enable`이 권한 창을 띄우는 쪽이다.
        #expect(code.contains("dailyReminder.refresh()"))
        #expect(!code.contains("dailyReminder.enable("))
    }

    @Test("거울을 한 번 만들어 본 뒤에 묻는다")
    func asksAfterTheFirstSave() throws {
        let code = try source("ggumirror/Editor/EditorView.swift")
        #expect(code.contains("askForNotificationsOnce"))
        // 리뷰 요청과 같은 저장에서 겹치지 않는다.
        let start = try #require(code.range(of: "private func recordSuccessfulSave()")).upperBound
        let body = code[start...].prefix(300)
        #expect(body.contains("guard reviewPrompt?.shouldRequest() == true else {"))
    }

    @Test("알림 탭은 알림센터로 간다")
    func tapOpensTheCenter() throws {
        let code = try source("ggumirror/Notifications/PushRegistration.swift")
        #expect(code.contains("openNotificationCenter"))
        // 새 deep link 체계를 만들지 않았다.
        #expect(!code.contains("URLComponents") && !code.contains("onOpenURL"))
    }

    @Test("계정이 바뀌면 기기를 다시 묶는다")
    func rootRebindsOnAccountChange() throws {
        let code = try source("ggumirror/RootView.swift")
        #expect(code.contains("pushRegistration.accountChanged(to: session.server)"))
        #expect(code.contains("onChange(of: session.server?.userID)"))
    }

    @Test("APNs 자격 증명이 앱에 없다")
    func noCredentialsInTheClient() throws {
        for path in [
            "ggumirror/Notifications/PushRegistration.swift",
            "ggumirror/Notifications/DailyReminder.swift",
            "ggumirror/Backend/BackendClient+Notifications.swift",
        ] {
            let code = try source(path)
            for banned in ["p8", "PRIVATE KEY", "teamId", "keyId", "APNS_"] {
                #expect(!code.contains(banned), "\(path): client에 \(banned)가 있다")
            }
        }
    }
}
