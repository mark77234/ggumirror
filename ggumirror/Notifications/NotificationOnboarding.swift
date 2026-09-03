//
//  NotificationOnboarding.swift
//  ggumirror
//
//  시스템 권한 창을 **설명 없이 먼저 띄우지 않는다.**
//
//  iOS는 알림 권한을 한 번만 물어본다. 거부하면 앱 안에서는 되돌릴 수 없고
//  설정 앱까지 가야 한다. 그래서 무엇을 받게 되는지 먼저 우리 화면으로 말하고,
//  받겠다고 한 사람에게만 시스템 창을 띄운다.
//
//  한 번 보여 준 뒤에는 다시 띄우지 않는다 — `notDetermined`라고 해서 켤 때마다
//  다시 묻는 것은 설명이 아니라 조르기다.
//

import Foundation

@MainActor
@Observable
final class NotificationOnboarding {
    /// 이미 보여 줬는가. 기기 설정이라 계정과 무관하다.
    private(set) var hasSeen: Bool
    /// 지금 화면에 떠 있는가.
    var isPresented = false

    static let preferenceKey = "hasSeenNotificationOnboarding"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasSeen = defaults.bool(forKey: Self.preferenceKey)
    }

    /// 지금 보여 줘도 되는가.
    ///
    /// **아직 한 번도 안 물어본 사람에게만** 보여 준다. 이미 허락했거나 거부한
    /// 사람에게 다시 설명할 것이 없다 — 거부한 사람은 설정에서 켠다.
    func shouldPresent(permission: NotificationPermission) -> Bool {
        !hasSeen && permission == .notAsked
    }

    /// 조건이 맞으면 띄운다. **한 번만** 기록한다.
    func presentIfNeeded(permission: NotificationPermission) {
        guard shouldPresent(permission: permission) else { return }
        isPresented = true
        markSeen()
    }

    /// 다시 띄우지 않는다. 사용자가 무엇을 골랐든 설명은 한 번이면 된다.
    func markSeen() {
        guard !hasSeen else { return }
        hasSeen = true
        defaults.set(true, forKey: Self.preferenceKey)
    }
}
