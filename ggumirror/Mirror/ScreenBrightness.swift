//
//  ScreenBrightness.swift
//  ggumirror
//
//  Phase 1-3: Mirror의 "밝기"는 카메라 노출이 아니라 iPhone 화면 밝기다.
//  Mirror에 들어올 때 사용자의 원래 밝기를 기억했다가 나갈 때 되돌린다.
//

import SwiftUI

@Observable
@MainActor
final class ScreenBrightness {
    /// Mirror가 사용하는 밝기. 화면 밝기를 직접 되읽지 않고 이 값을 기준으로 유지한다.
    private(set) var level: CGFloat = 0.5

    /// Mirror에 들어오기 전 사용자의 밝기. nil이면 아직 Mirror가 화면을 넘겨받지 않은 상태.
    @ObservationIgnored private var userLevel: CGFloat?

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
    }

    /// Mirror 진입 / 포그라운드 복귀. 처음 한 번만 사용자의 밝기를 기억한다.
    func takeOver() {
        guard let screen else { return }
        if userLevel == nil {
            userLevel = screen.brightness
            level = screen.brightness
        }
        screen.brightness = level
    }

    func set(_ value: CGFloat) {
        level = min(max(value, 0), 1)
        screen?.brightness = level
    }

    /// 백그라운드로 갈 때. 기억한 값은 유지해서 복귀 시 다시 Mirror 밝기로 돌아온다.
    func restoreUserLevel() {
        guard let userLevel, let screen else { return }
        screen.brightness = userLevel
    }

    /// Mirror를 완전히 벗어날 때. 원래 밝기로 되돌리고 기억을 비운다.
    func release() {
        restoreUserLevel()
        userLevel = nil
    }
}
