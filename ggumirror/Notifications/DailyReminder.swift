//
//  DailyReminder.swift
//  ggumirror
//
//  매일 저녁 알림. **서버가 관여하지 않는다.**
//
//  Cloud Scheduler도, 사용자 시간대 저장도, push provider도 없다 — 기기가 스스로
//  띄운다. 서버 비용이 0이고, 사용자가 어디에 있든 그 사람의 저녁 8시다.
//
//  문구를 돌리기 위해 며칠치를 각각 예약한다. `repeats: true` 하나로는 매일 같은
//  말만 나오는데, 같은 문장이 반복되면 며칠 만에 읽히지 않는 알림이 된다.
//

import Foundation
import UserNotifications

nonisolated enum DailyReminder {
    /// 우리 알림임을 알아보는 표시. **이 접두사가 붙은 것만 지운다** —
    /// `removeAllPendingNotificationRequests`를 쓰면 나중에 생길 다른 알림까지
    /// 함께 지운다.
    static let identifierPrefix = "daily-reminder-"

    /// 저녁 8시. 서버 시간대가 아니라 **기기의 달력**이다.
    static let hour = 20
    static let minute = 0

    /// 며칠치를 미리 잡아 둘 것인가.
    ///
    /// 7일이면 일주일 앱을 안 열어도 알림이 이어지고, iOS의 예약 한도(64개)에
    /// 한참 못 미친다. 더 길게 잡을 이유가 없다 — 어차피 앱을 열 때마다 다시 채운다.
    static let scheduledDays = 7

    /// 돌려 쓸 문구. **매일 같은 말을 하지 않는다.**
    ///
    /// 문구 관리 체계를 만들지 않는다 — 배열 하나면 충분하고, 늘리려면 여기에
    /// 한 줄 더한다.
    static let messages = [
        "오늘은 무슨 거울이 올라왔을까요?",
        "거울아 거울아, 오늘은 누가 제일 예쁘니?",
        "새로운 거울 구경하러 올래요?",
        "오늘의 거울을 한번 둘러보세요.",
        "내 거울을 새로운 느낌으로 바꿔볼까요?",
    ]

    static let title = "꾸미러"

    /// `n`일 뒤 알림의 식별자. **날짜에서 만든다.**
    ///
    /// 그래서 앱을 하루에 열 번 열어도 같은 날 알림이 열 개 쌓이지 않는다 —
    /// 같은 식별자로 다시 넣으면 iOS가 덮어쓴다.
    static func identifier(for day: DateComponents) -> String {
        "\(identifierPrefix)\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
    }

    /// 그 날짜에 쓸 문구. **날짜에서 고른다** — 무작위로 고르면 다시 예약할 때마다
    /// 문구가 바뀌어서, 같은 날 알림이 앱을 열 때마다 달라진다.
    static func message(for day: DateComponents) -> String {
        let ordinal = (day.year ?? 0) * 372 + (day.month ?? 0) * 31 + (day.day ?? 0)
        return messages[abs(ordinal) % messages.count]
    }
}

/// 매일 알림을 켜고 끄고 다시 채운다.
///
/// **계정과 무관하다.** 로그인하지 않아도 동작하고, 로그아웃해도 유지된다 —
/// 이건 앱으로 다시 오라는 알림이지 누구의 판매 소식이 아니다.
@MainActor
@Observable
final class DailyReminderScheduler {
    /// 사용자가 켜 두었는가. 기기 설정이라 계정별로 두지 않는다.
    var isOn: Bool {
        didSet {
            guard isOn != oldValue else { return }
            UserDefaults.standard.set(isOn, forKey: Self.preferenceKey)
        }
    }

    private(set) var permission: NotificationPermission = .notAsked

    static let preferenceKey = "dailyReminderOn"

    private let scheduler: any NotificationScheduling
    private let calendar: Calendar

    init(
        scheduler: any NotificationScheduling = SystemNotificationScheduler(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        self.scheduler = scheduler
        self.calendar = calendar
        // 값이 없으면 켠 것으로 시작한다. 실제로 알림이 가려면 권한이 따로 필요하다.
        self.isOn = defaults.object(forKey: Self.preferenceKey) as? Bool ?? true
    }

    func refreshPermission() async {
        permission = await scheduler.permission()
    }

    /// 앱을 열 때마다 부른다. **권한 창을 띄우지 않는다.**
    ///
    /// 시작하자마자 권한을 묻지 않는다 — 앱이 무엇인지 보기도 전에 창이 뜨면
    /// 대부분 거부하고, 거부는 되돌리기 어렵다.
    func refresh(now: Date = .now) async {
        permission = await scheduler.permission()
        guard isOn, permission.canSend else {
            await clear()
            return
        }
        await schedule(now: now)
    }

    /// 사용자가 켰다. **여기서는 권한을 물어도 된다** — 사용자가 방금 원한다고 말했다.
    func enable(now: Date = .now) async {
        isOn = true
        permission = await scheduler.permission()
        if permission.canAsk {
            permission = await scheduler.requestPermission()
        }
        guard permission.canSend else { return }
        await schedule(now: now)
    }

    func disable() async {
        isOn = false
        await clear()
    }

    /// 다음 며칠치를 채운다.
    ///
    /// 이미 있는 날은 같은 식별자로 덮여서 **중복이 쌓이지 않는다.** 지나간 날의
    /// 예약만 지운다 — 다른 종류의 알림은 건드리지 않는다.
    private func schedule(now: Date) async {
        let days = upcomingDays(from: now)
        let wanted = Set(days.map(DailyReminder.identifier(for:)))

        // **우리 접두사가 붙은 것 중** 더 이상 필요 없는 것만 지운다.
        let stale = await scheduler.pendingIdentifiers().filter {
            $0.hasPrefix(DailyReminder.identifierPrefix) && !wanted.contains($0)
        }
        if !stale.isEmpty {
            await scheduler.remove(identifiers: stale)
        }

        for day in days {
            let content = UNMutableNotificationContent()
            content.title = DailyReminder.title
            content.body = DailyReminder.message(for: day)
            content.sound = .default
            try? await scheduler.add(
                UNNotificationRequest(
                    identifier: DailyReminder.identifier(for: day),
                    content: content,
                    // 하루치씩이라 `repeats`가 아니다 — 그래야 날마다 다른 문구가 된다.
                    trigger: UNCalendarNotificationTrigger(dateMatching: day, repeats: false)
                )
            )
        }
    }

    /// 우리 알림만 지운다.
    private func clear() async {
        let ours = await scheduler.pendingIdentifiers().filter {
            $0.hasPrefix(DailyReminder.identifierPrefix)
        }
        guard !ours.isEmpty else { return }
        await scheduler.remove(identifiers: ours)
    }

    /// 오늘 저녁 8시가 아직 안 지났으면 오늘부터, 지났으면 내일부터.
    private func upcomingDays(from now: Date) -> [DateComponents] {
        var days: [DateComponents] = []
        var day = calendar.startOfDay(for: now)
        while days.count < DailyReminder.scheduledDays {
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = DailyReminder.hour
            components.minute = DailyReminder.minute
            // **이미 지난 시각을 예약하지 않는다** — iOS가 즉시 띄운다.
            if let fire = calendar.date(from: components), fire > now {
                days.append(components)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}
