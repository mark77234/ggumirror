//
//  QuickMirrorActivity.swift
//  ggumirror
//
//  Quick Mirror → 본앱 전환에 쓰는 activity.
//
//  **본앱 · Control widget · Capture extension이 함께 쓴다.**
//
//  activity type은 **Apple 공식 상수 `NSUserActivityTypeLockedCameraCapture`**다.
//  SDK 헤더가 이 값을 `openApplication(for:)`에 쓰라고 명시한다 —
//  "잠금화면 capture extension에서 앱을 열었는지"를 앱이 이 타입으로 판별한다.
//  커스텀 타입을 쓰면 시스템이 그 흐름으로 인정하지 않을 수 있다.
//

import Foundation
import LockedCameraCapture

nonisolated enum QuickMirrorActivity {
    static let openMirrorType = NSUserActivityTypeLockedCameraCapture

    /// 본앱은 이걸 받으면 **기존 Mirror 화면 그대로** 이어간다 —
    /// 홈이나 상점으로 끌고 가지 않는다.
    static func openMirror() -> NSUserActivity {
        let activity = NSUserActivity(activityType: openMirrorType)
        activity.title = "꾸미러 거울"
        // 사용자 정보를 담지 않는다. "거울을 열어라"는 사실만 있으면 된다.
        return activity
    }

    static func isOpenMirror(_ activity: NSUserActivity) -> Bool {
        activity.activityType == openMirrorType
    }
}
