//
//  PushRegistration.swift
//  ggumirror
//
//  APNs token을 받아 서버에 묶는다.
//
//  **raw token을 로그에 남기지 않는다.** 그것은 이 기기로 알림을 보낼 수 있는
//  열쇠다 — 찍히면 로그를 보는 모든 곳에 열쇠가 있는 것이다.
//
//  계정이 바뀌면 다시 묶는다. 안 그러면 로그아웃한 사람에게 **다음 사람의 판매
//  알림이 간다** — 같은 기기, 같은 token이기 때문이다.
//

import Foundation
import UIKit
import UserNotifications

/// 기기 token을 받아서 들고 있고, 계정이 정해지면 서버에 묶는다.
///
/// token이 먼저 올 수도 있고 로그인이 먼저일 수도 있다. 둘 다 갖춰졌을 때
/// 등록하고, 그 전에는 기다린다.
@MainActor
@Observable
final class PushRegistration {
    /// 마지막으로 등록한 (token, 계정). **같은 조합을 다시 보내지 않는다.**
    private var registered: (token: String, userID: String)?
    private var deviceToken: String?
    /// 지금 로그인한 사람. **둘 다 기억해야 한다** — token은 로그인보다 늦게
    /// 올 때가 많고(APNs 왕복이 있다), 그때 세션을 모르면 영영 등록되지 않는다.
    private var session: ServerSession?

    private let backend: any NotificationBackend
    private let scheduler: any NotificationScheduling

    init(
        backend: any NotificationBackend = BackendClient(),
        scheduler: any NotificationScheduling = SystemNotificationScheduler()
    ) {
        self.backend = backend
        self.scheduler = scheduler
    }

    /// 권한이 있으면 APNs 등록을 요청한다. **권한 창을 띄우지 않는다.**
    func startIfAllowed() async {
        guard await scheduler.permission().canSend else { return }
        await scheduler.registerForRemoteNotifications()
    }

    /// iOS가 token을 줬다. 아직 로그인 전일 수 있다.
    func received(deviceToken token: Data) async {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        await syncIfPossible(session: session)
    }

    /// 로그인 상태가 바뀌었다. **계정이 바뀌면 다시 묶는다.**
    func accountChanged(to session: ServerSession?) async {
        let previous = self.session
        self.session = session
        guard let session else {
            // 로그아웃이다. 마지막 세션으로 떼어 낸다 — 지금은 토큰이 없다.
            await unbind(session: previous)
            return
        }
        guard registered?.userID != session.userID else { return }
        registered = nil
        await syncIfPossible(session: session)
    }

    private func syncIfPossible(session: ServerSession? = nil) async {
        guard let token = deviceToken, let session else { return }
        // 같은 기기·같은 계정이면 다시 보내지 않는다.
        guard registered?.token != token || registered?.userID != session.userID else { return }
        do {
            try await backend.registerPushDevice(
                token: token, environment: .current, accessToken: session.accessToken
            )
            registered = (token, session.userID)
        } catch {
            // **등록 실패가 앱을 막지 않는다.** 알림이 조금 늦게 붙을 뿐이다.
            BackendLog.event("push device register failed \(BackendLog.category(error))")
        }
    }

    /// 로그아웃. 실패해도 로그아웃을 막지 않는다.
    func unbind(session: ServerSession? = nil) async {
        defer { registered = nil }
        let session = session ?? self.session
        guard let token = deviceToken, let session else { return }
        try? await backend.unregisterPushDevice(
            token: token, environment: .current, accessToken: session.accessToken
        )
    }
}

/// iOS가 token과 탭을 넘겨주는 유일한 통로.
///
/// SwiftUI에는 이 callback이 없어서 delegate 하나를 둔다. **여기서 하는 일은
/// 넘겨주는 것뿐이다** — 판단은 `PushRegistration`이 한다.
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// 앱이 뜬 뒤에 꽂힌다.
    @MainActor static var registration: PushRegistration?
    /// 알림을 탭했다. 화면이 이것을 보고 알림센터를 연다 —
    /// deep link 체계를 새로 만들지 않는다.
    @MainActor static var openNotificationCenter: (() -> Void)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await Self.registration?.received(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // **앱을 막지 않는다.** 시뮬레이터·기내 모드에서 흔한 일이다.
        BackendLog.event("push device registration failed")
    }

    /// 앱을 보고 있을 때도 알림을 띄운다 — 판매 소식은 그때도 보고 싶다.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { Self.openNotificationCenter?() }
    }
}
