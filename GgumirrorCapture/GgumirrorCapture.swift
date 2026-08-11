//
//  GgumirrorCapture.swift
//  GgumirrorCapture
//
//  Created by 이병찬 on 8/11/26.
//

import ExtensionKit
import Foundation
import LockedCameraCapture
import SwiftUI

@main
struct GgumirrorCapture: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            // 실기기에서 control을 눌렀을 때 **이 process까지 왔는지** 보기 위한 것.
            // 사용자 데이터 · 경로 · 인증 정보는 담지 않는다(DEBUG 전용).
            QuickMirrorLog.event("extension scene started")
            return GgumirrorCaptureViewFinder(session: session)
        }
    }
}
