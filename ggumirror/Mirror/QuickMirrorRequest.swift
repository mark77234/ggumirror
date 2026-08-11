//
//  QuickMirrorRequest.swift
//  ggumirror
//
//  "지금 Mirror를 보여라"는 **아주 작은 신호** 하나.
//
//  잠금이 풀린 상태에서는 시스템이 capture extension 대신 **본앱**을 고를 수 있다.
//  그때 홈 / 설정 / 상점이 아니라 Mirror가 보여야 한다.
//
//  navigation architecture를 새로 만들지 않는다 — 앱은 원래 Mirror-first고,
//  이미 떠 있는 경우만 Mirror로 되돌리면 된다.
//
//  **본앱 · Control widget · Capture extension이 함께 쓴다**(intent가 세 target에 들어가므로).
//  extension에서는 아무 일도 하지 않는다 — 신호를 받을 화면이 없다.
//

import Foundation

@Observable
@MainActor
final class QuickMirrorRequest {
    static let shared = QuickMirrorRequest()

    /// Mirror를 보여달라는 요청이 들어온 횟수. 값 자체는 의미 없고 **변했다는 사실**만 쓴다.
    private(set) var token = 0

    private init() {}

    func showMirror() {
        token += 1
        QuickMirrorLog.event("show mirror requested")
    }
}

// MARK: - 로그

/// 실기기에서 control을 눌렀을 때 **어느 process까지 도달했는지** 보기 위한 것.
/// DEBUG 빌드에만 나오고, 사용자 데이터 · 경로 · token · 인증 정보는 절대 담지 않는다.
nonisolated enum QuickMirrorLog {
    static func event(_ message: String) {
        #if DEBUG
        print("[QuickMirror] \(message)")
        #endif
    }
}
