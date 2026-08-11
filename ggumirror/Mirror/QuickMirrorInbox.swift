//
//  QuickMirrorInbox.swift
//  ggumirror
//
//  잠금화면 Quick Mirror가 찍은 사진을 **본앱이 공식 경로로 받는 곳**.
//
//  `LockedCameraCaptureManager`가 extension의 session content 폴더를 알려준다.
//  extension은 network도, App Group도, 우리 저장소도 쓸 수 없으므로 이게 유일한 통로다.
//
//  C-1A에서는 "받을 수 있다"까지만 한다 — 사진 앱 자동 저장이나 거울 목록 편입은 하지 않는다.
//  받은 파일을 함부로 지우지도 않는다(사용자 콘텐츠다).
//

import Foundation
import LockedCameraCapture

@Observable
@MainActor
final class QuickMirrorInbox {
    /// 지금 수거할 수 있는 Quick Mirror 사진들.
    private(set) var captures: [URL] = []

    /// 잠금화면에서 찍은 것이 있는지.
    var hasCaptures: Bool { !captures.isEmpty }

    /// 화면이 뜬 뒤에 부른다. Mirror 진입을 막지 않는다.
    func refresh() {
        captures = Self.collect(from: LockedCameraCaptureManager.shared.sessionContentURLs)
    }

    /// session content 폴더가 새로 생기면 알려준다.
    func watch() async {
        for await _ in LockedCameraCaptureManager.shared.sessionContentUpdates {
            refresh()
        }
    }

    /// 다 쓴 session content를 시스템에 반납한다.
    /// **사용자가 그 사진을 저장한 뒤에만** 부른다 — 먼저 부르면 사진이 사라진다.
    func release(_ sessionContentURL: URL) async {
        try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: sessionContentURL)
        refresh()
    }

    /// 폴더 목록에서 Quick Mirror 결과만 모은다. 순수 함수 — 테스트가 직접 부른다.
    nonisolated static func collect(from directories: [URL]) -> [URL] {
        directories.flatMap { QuickMirrorCaptureStore.captures(in: $0) }
    }
}
