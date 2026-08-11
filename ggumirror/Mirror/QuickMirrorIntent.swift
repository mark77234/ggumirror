//
//  QuickMirrorIntent.swift
//  ggumirror
//
//  잠금화면 control이 실행하는 것. **본앱과 Control widget이 함께 쓴다.**
//
//  `CameraCaptureIntent`는 시스템이 Quick Mirror capture extension을 띄우는 공식 통로다.
//  URL scheme 같은 우회로를 쓰지 않는다.
//
//  `AppContext`는 두지 않았다(`Never`). C-1A에서 extension에 넘길 상태가 없다 —
//  거울 장식은 C-1B의 일이고, 4KB 통로에 사용자 asset을 담지 않는다.
//
//  **Apple 요구사항: 이 파일은 세 target 모두에 들어가야 한다** —
//  본앱 · Control widget · Capture extension. 하나라도 빠지면 control이 목록에는 보이지만
//  실행되지 않는다(직접 겪었다). 파일 하나를 target membership으로 공유한다 — 복사하지 않는다.
//

import AppIntents

nonisolated struct QuickMirrorCaptureIntent: CameraCaptureIntent {
    typealias AppContext = Never

    static let title: LocalizedStringResource = "꾸미러 거울"
    static let description = IntentDescription("잠금화면에서 바로 거울을 봐요.")

    func perform() async throws -> some IntentResult {
        // 잠긴 상태면 시스템이 capture extension을 띄우고 이 코드는 돌지 않는다.
        // 잠금이 풀려 시스템이 **본앱**을 고른 경우에만 여기로 온다 —
        // 그때 홈/설정/상점이 아니라 Mirror가 보여야 한다.
        QuickMirrorLog.event("intent perform (app process)")
        await MainActor.run { QuickMirrorRequest.shared.showMirror() }
        return .result()
    }
}
