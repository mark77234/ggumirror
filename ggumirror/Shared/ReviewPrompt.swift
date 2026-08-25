//
//  ReviewPrompt.swift
//  ggumirror
//
//  Apple 공식 리뷰 요청. **별점 UI를 우리가 만들지 않는다.**
//
//  "5점 주세요" 같은 화면을 먼저 띄우고 좋은 답을 고른 사람만 App Store로 보내는 것은
//  dark pattern이고 Apple 정책 위반이다. 우리는 `RequestReviewAction`만 부른다.
//
//  **부른다고 창이 뜨는 것도 아니다.** 표시 여부와 빈도는 OS가 정한다. 그래서 앱은
//  "보여 줬다"를 기록하지 않고 **"요청을 시도했다"**만 기록한다 — 알 수 없는 것을
//  안다고 적으면 그 값에 기대는 다음 코드가 전부 틀린다.
//
//  묻는 시점도 중요하다. 실행 직후 · 로그인 직후 · 결제 직후 · 오류 직후에는 묻지 않는다.
//  **무언가를 성공적으로 끝낸 직후**에만 묻는다 — 지금은 거울 저장이다.
//

import Foundation
import SwiftUI

/// 리뷰를 물어도 되는지 판단하는 **순수 값**. 기기 없이 시험한다.
nonisolated struct ReviewPromptPolicy: Equatable {
    /// 앱을 처음 연 시각.
    var firstLaunchAt: Date?
    /// 앱을 연 횟수.
    var launchCount: Int
    /// 거울을 저장해 성공한 횟수.
    var successfulSaves: Int
    /// 마지막으로 **요청을 시도한** marketing version. 실제 표시 여부가 아니다.
    var lastRequestedVersion: String?

    /// 반복 사용자여야 한다 — 한 번 써 보고 나가는 사람에게 묻지 않는다.
    static let minimumLaunches = 3
    /// 성공 경험이 쌓여야 한다.
    static let minimumSaves = 3
    /// 설치 직후에 묻지 않는다.
    static let minimumAge: TimeInterval = 3 * 24 * 60 * 60

    /// 지금 물어봐도 되는가.
    ///
    /// - Parameter currentVersion: 지금 앱의 marketing version.
    ///   **같은 버전에서는 한 번만** 시도한다. OS도 자체 제한을 두지만
    ///   우리 쪽에서도 반복해서 부르지 않는다.
    func shouldRequest(now: Date, currentVersion: String) -> Bool {
        guard let firstLaunchAt else { return false }
        guard launchCount >= Self.minimumLaunches else { return false }
        guard successfulSaves >= Self.minimumSaves else { return false }
        guard now.timeIntervalSince(firstLaunchAt) >= Self.minimumAge else { return false }
        // 이 버전에서 이미 물어봤다.
        guard lastRequestedVersion != currentVersion else { return false }
        return true
    }
}

/// 정책 상태를 기기에 적어 둔다. **계정별이 아니다** — 앱을 어떻게 쓰는지에 대한 값이라
/// 서버에 보낼 이유가 없다(서버 collection을 만들면 비용만 는다).
@MainActor
@Observable
final class ReviewPromptTracker {
    private enum Key {
        static let firstLaunch = "reviewFirstLaunchAt"
        static let launches = "reviewLaunchCount"
        static let saves = "reviewSuccessfulSaves"
        static let lastVersion = "reviewLastRequestedVersion"
    }

    private let defaults: UserDefaults
    private let version: String

    init(defaults: UserDefaults = .standard, version: String = appVersion()) {
        self.defaults = defaults
        self.version = version
    }

    /// 지금 앱의 marketing version. 버전마다 한 번만 묻기 위한 값이다.
    nonisolated static func appVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var policy: ReviewPromptPolicy {
        ReviewPromptPolicy(
            firstLaunchAt: defaults.object(forKey: Key.firstLaunch) as? Date,
            launchCount: defaults.integer(forKey: Key.launches),
            successfulSaves: defaults.integer(forKey: Key.saves),
            lastRequestedVersion: defaults.string(forKey: Key.lastVersion)
        )
    }

    /// 앱을 열 때 한 번. 처음이면 시작 시각을 적는다.
    func recordLaunch(now: Date = Date()) {
        if defaults.object(forKey: Key.firstLaunch) == nil {
            defaults.set(now, forKey: Key.firstLaunch)
        }
        defaults.set(defaults.integer(forKey: Key.launches) + 1, forKey: Key.launches)
    }

    /// 거울을 저장해 성공했을 때.
    func recordSuccessfulSave() {
        defaults.set(defaults.integer(forKey: Key.saves) + 1, forKey: Key.saves)
    }

    /// 지금 물어봐도 되는가.
    func shouldRequest(now: Date = Date()) -> Bool {
        policy.shouldRequest(now: now, currentVersion: version)
    }

    /// **시도했다**고 적는다. 실제로 창이 떴는지는 알 수 없다.
    func recordRequestAttempt() {
        defaults.set(version, forKey: Key.lastVersion)
    }
}
