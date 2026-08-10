//
//  EditorHaptics.swift
//  ggumirror
//
//  "잡고 움직이고 있다" 정도만 느끼게 하는 아주 약한 촉각 피드백.
//  드래그 프레임마다 울리면 시끄럽고 배터리도 낭비되므로 시간 + 이동 거리로 제한한다.
//

import UIKit

/// 언제 tick을 울릴지 결정하는 순수 로직. UIKit 없이 테스트할 수 있다.
struct HapticRateLimiter {
    /// 최소 간격(초).
    var minimumInterval: TimeInterval = 0.09
    /// 최소 이동 거리 (Master Canvas 픽셀).
    var minimumDistance: Double = 26

    private var lastTime: TimeInterval?
    private var lastPoint: NormalizedPoint?

    mutating func shouldFire(at point: NormalizedPoint, time: TimeInterval) -> Bool {
        defer {
            if lastTime == nil { lastTime = time; lastPoint = point }
        }
        guard let lastTime, let lastPoint else { return false }   // 첫 접촉은 울리지 않는다
        guard time - lastTime >= minimumInterval else { return false }
        guard lastPoint.masterDistance(to: point) >= minimumDistance else { return false }

        self.lastTime = time
        self.lastPoint = point
        return true
    }

    mutating func reset() {
        lastTime = nil
        lastPoint = nil
    }
}

@MainActor
enum EditorHaptics {
    private static let move = UIImpactFeedbackGenerator(style: .soft)
    private static let confirm = UISelectionFeedbackGenerator()

    static func prepare() {
        move.prepare()
        confirm.prepare()
    }

    /// 이동 중 아주 약한 tick. rate limiter를 통과했을 때만 부른다.
    static func movementTick() {
        move.impactOccurred(intensity: 0.35)
    }

    /// 배치를 마쳤을 때 한 번. 이동 tick보다 조금 더 또렷하다.
    static func placementConfirmed() {
        confirm.selectionChanged()
    }
}
