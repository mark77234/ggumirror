//
//  NotificationPermission.swift
//  ggumirror
//
//  알림 권한. **거부한 사람을 다시 조르지 않는다.**
//
//  system API를 직접 부르는 곳을 여기 하나로 모은다 — 그래야 test가 실제
//  권한 창을 띄우지 않고 흐름을 확인할 수 있다.
//

import Foundation
import UIKit
import UserNotifications

/// 지금 알림을 보낼 수 있는가.
///
/// `UNAuthorizationStatus`를 그대로 쓰지 않는다 — system 열거형은 값이 늘어나고,
/// 화면이 알아야 하는 것은 **물어봐도 되는가 · 보낼 수 있는가** 둘뿐이다.
nonisolated enum NotificationPermission: Equatable, Sendable {
    /// 아직 물어본 적 없다. **여기서만 권한 창을 띄울 수 있다.**
    case notAsked
    /// 보낼 수 있다.
    case allowed
    /// 거부했다. **다시 물어도 창이 뜨지 않는다** — 설정 앱으로 보내야 한다.
    case denied

    /// 조용한 알림만 허용됐다(사용자가 따로 켠 경우). 보낼 수는 있다.
    case quiet

    var canSend: Bool { self == .allowed || self == .quiet }
    /// 시스템 창을 띄워도 되는가. **`denied`에서는 절대 아니다.**
    var canAsk: Bool { self == .notAsked }
}

/// system 알림 기능. test는 여기에 fake를 끼운다.
nonisolated protocol NotificationScheduling: Sendable {
    func permission() async -> NotificationPermission
    /// 권한을 묻는다. 이미 정해졌으면 창이 뜨지 않고 현재 상태가 돌아온다.
    func requestPermission() async -> NotificationPermission
    /// 예약된 우리 알림의 식별자.
    func pendingIdentifiers() async -> [String]
    func add(_ request: UNNotificationRequest) async throws
    /// **주어진 식별자만** 지운다. 전부 지우는 API를 쓰지 않는다.
    func remove(identifiers: [String]) async
    /// 원격 알림 등록을 요청한다(APNs token을 받기 위해).
    func registerForRemoteNotifications() async
}

nonisolated struct SystemNotificationScheduler: NotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notAsked
        case .denied: .denied
        case .authorized: .allowed
        case .provisional, .ephemeral: .quiet
        // 모르는 값이 생기면 **보낼 수 있다고 넘겨짚지 않는다.**
        @unknown default: .denied
        }
    }

    func requestPermission() async -> NotificationPermission {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await permission()
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func remove(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    @MainActor
    func registerForRemoteNotifications() async {
        UIApplication.shared.registerForRemoteNotifications()
    }
}
