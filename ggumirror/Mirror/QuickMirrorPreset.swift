//
//  QuickMirrorPreset.swift
//  ggumirror
//
//  잠금화면 Quick Mirror가 그릴 **프레임 preset**.
//
//  **본앱과 Capture extension이 함께 쓴다.** extension은 App Group · network ·
//  MirrorStore에 접근할 수 없으므로, 넘길 수 있는 것은 `CameraCaptureIntent.AppContext`에
//  담기는 **아주 작은 값(JSON 4KB 이하)**뿐이다. 여기 있는 것이 전부 그 값이다.
//
//  preset을 새로 발명하지 않았다 — 상점의 **단색 기본 거울 8종**과 그대로 1:1이다.
//  사용자가 기본 거울을 쓰고 있으면 잠금화면에서도 같은 색 프레임이 보인다.
//
//  사진 · 스티커 · 그림 · 텍스트 · 외부 디자인이 든 거울은 이 통로로 재현할 수 없다.
//  **틀리게 반쯤 재현하지 않고** 기본 preset으로 떨어진다(C-1C에서 별도 설계).
//

import CoreGraphics
import SwiftUI

// MARK: - preset

nonisolated enum QuickMirrorPresetID: String, Codable, CaseIterable, Sendable {
    /// 프레임 없이 카메라만. 사용자가 만든 거울처럼 재현할 수 없을 때의 정직한 선택지다.
    case none
    // 아래 8개는 상점 "기본" 갈래의 단색 거울과 같은 이름·같은 색이다.
    case white
    case black
    case cream
    case softPink
    case lavender
    case sky
    case mint
    case gray

    /// 재현할 수 없는 거울을 만났을 때 쓰는 값.
    ///
    /// `none`(무프레임)이 아니라 크림색 프레임이다 — 잠금화면에서 control을 눌렀을 때
    /// "꾸미러답게" 보이는 것이 이 기능의 목적이고, 사용자가 고른 것을 틀리게 흉내 내는 것도 아니다.
    static let fallback: QuickMirrorPresetID = .cream

    /// 프레임 색. `none`은 색이 없다.
    ///
    /// 값은 `BasicMirror`(본앱 상점 기본 거울)와 **같아야 한다.**
    /// extension에 `MirrorLibrary`를 끌고 올 수 없어 숫자를 여기 한 번 더 적었고,
    /// 어긋나지 않도록 테스트가 두 곳을 비교한다.
    var frameColor: Color? {
        switch self {
        case .none: nil
        case .white: Color(red: 0.976, green: 0.973, blue: 0.965)
        case .black: Color(red: 0.145, green: 0.141, blue: 0.137)
        case .cream: Color(red: 0.965, green: 0.937, blue: 0.855)
        case .softPink: Color(red: 0.965, green: 0.886, blue: 0.886)
        case .lavender: Color(red: 0.898, green: 0.882, blue: 0.949)
        case .sky: Color(red: 0.855, green: 0.910, blue: 0.949)
        case .mint: Color(red: 0.855, green: 0.933, blue: 0.898)
        case .gray: Color(red: 0.878, green: 0.875, blue: 0.867)
        }
    }

    var drawsFrame: Bool { self != .none }
}

// MARK: - AppContext

/// `CameraCaptureIntent.AppContext`로 오가는 값. **이것만 오간다.**
///
/// 담지 않는 것: PNG · 사진 · 스티커 · 그림 좌표 · 텍스트 · 외부 디자인 ·
/// 거울 id · 사용자 정보 · 인증 정보 · 서버 정보. 4KB 제한과 무관하게 **수십 byte**다.
nonisolated struct QuickMirrorContext: Codable, Equatable, Sendable {
    /// 형식이 바뀌면 올린다. 모르는 버전이 오면 조용히 기본값으로 떨어진다.
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var presetID: QuickMirrorPresetID

    init(presetID: QuickMirrorPresetID, schemaVersion: Int = Self.currentSchemaVersion) {
        self.presetID = presetID
        self.schemaVersion = schemaVersion
    }

    /// 저장된 context에서 실제로 그릴 preset을 정한다.
    ///
    /// context가 없거나 · 못 읽거나 · 모르는 버전이면 **기본 preset**이다.
    /// 프레임을 못 그리는 것이 카메라를 못 띄우는 이유가 되면 안 된다.
    static func preset(from context: QuickMirrorContext?) -> QuickMirrorPresetID {
        guard let context else { return QuickMirrorPresetID.fallback }
        guard context.schemaVersion == currentSchemaVersion else { return QuickMirrorPresetID.fallback }
        return context.presetID
    }
}

// MARK: - 프레임 geometry

/// 프레임을 그리는 **단 하나의 정의.** 미리보기와 저장 결과가 같아야 하므로
/// 두 곳이 이 계산을 함께 쓴다 — 각자 따로 숫자를 쓰지 않는다.
///
/// 비율은 본앱 거울과 같다(Master 1080 × 2340 기준 좌우 108 / 위 180 / 아래 220,
/// 안쪽 모서리 반경 30). 잠금화면 화면비가 거울 비율과 거의 같아 그대로 쓴다.
nonisolated enum QuickMirrorFrame {
    /// `MirrorFrameInsets.standard` · `MirrorGeometry.innerCornerRadius`와 같은 값이다.
    /// (extension에 Editor 모델을 끌고 오지 않기 위해 숫자를 옮겨 적었고, 테스트가 비교한다.)
    static let insetLeft = 108.0 / 1080.0
    static let insetRight = 108.0 / 1080.0
    static let insetTop = 180.0 / 2340.0
    static let insetBottom = 220.0 / 2340.0
    static let cornerRadiusRatio = 30.0 / 1080.0

    /// 카메라가 보이는 안쪽 구멍. 나머지가 프레임이다.
    static func hole(in size: CGSize) -> CGRect {
        CGRect(
            x: size.width * insetLeft,
            y: size.height * insetTop,
            width: size.width * (1 - insetLeft - insetRight),
            height: size.height * (1 - insetTop - insetBottom)
        )
    }

    static func cornerRadius(in size: CGSize) -> CGFloat {
        size.width * cornerRadiusRatio
    }
}
