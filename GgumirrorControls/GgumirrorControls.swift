//
//  GgumirrorControls.swift
//  GgumirrorControls
//
//  잠금화면 / 제어 센터에 놓는 **꾸미러 거울** control.
//
//  이 control은 `QuickMirrorCaptureIntent`(CameraCaptureIntent)를 실행하고,
//  시스템이 그걸 보고 Quick Mirror capture extension을 띄운다.
//  URL scheme으로 앱을 여는 우회로를 쓰지 않는다.
//
//  **사용자가 잠금화면 사용자화에서 직접 추가한다.**
//  앱이 기존 카메라 버튼을 강제로 바꾸는 API는 없고, 그렇게 하지도 않는다.
//

import AppIntents
import SwiftUI
import WidgetKit

@main
struct GgumirrorControlsBundle: WidgetBundle {
    var body: some Widget {
        QuickMirrorControl()
    }
}

struct QuickMirrorControl: ControlWidget {
    /// 한번 정하면 바꾸지 않는다 — 바꾸면 사용자가 배치한 control이 사라진다.
    static let kind = "com.mark77234.ggumirror.quick-mirror"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: QuickMirrorCaptureIntent()) {
                // `person.crop.artframe` = 사람 + 액자. 꾸민 거울의 의미에 가장 가깝다.
                // (`mirror.side.*`는 자동차 사이드미러라 뜻이 다르다.
                //  SF Symbols 카탈로그에서 실제 존재와 iOS 15.0+ 가용성을 확인했다.)
                // 꾸미러 브랜드 mark를 Custom Symbol Image로 쓰는 것은 후속 디자인 작업이다 —
                // app icon PNG를 그대로 control 아이콘에 넣지 않는다.
                Label("꾸미러 거울", systemImage: "person.crop.artframe")
            }
        }
        .displayName("꾸미러 거울")
        .description("잠금화면에서 바로 거울을 봐요.")
    }
}
