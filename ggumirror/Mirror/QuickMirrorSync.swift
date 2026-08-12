//
//  QuickMirrorSync.swift
//  ggumirror
//
//  현재 거울 → Quick Mirror preset **매핑과 등록**. **본앱 전용이다.**
//
//  거울 모델 전체를 extension에 공유하지 않는다. 여기서 작은 preset 하나로 줄여
//  `CameraCaptureIntent.updateAppContext(_:)`로 등록하고, extension은 그것만 읽는다.
//
//  이 기능은 부가기능이다 — 등록이 실패해도 거울 저장 · 사용자 콘텐츠 · 앱 동작에
//  아무 영향이 없다. 잠금화면이 이전 preset이나 기본값을 쓸 뿐이다.
//

import AppIntents
import Foundation
import SwiftUI

@MainActor
enum QuickMirrorSync {
    /// 현재 거울을 preset으로 줄인다.
    ///
    /// **표현할 수 있는 프레임 색은 장식이 있어도 그대로 지킨다.**
    /// 소프트 핑크 거울에 스티커를 얹어 두었다면 잠금화면도 소프트 핑크다 —
    /// 크림색으로 떨어지면 지금 쓰는 거울과 상관없는 디자인처럼 느껴진다.
    ///
    /// 프레임 색 자체를 표현할 수 없을 때만 기본값으로 간다.
    ///
    /// 어느 쪽이든 **장식은 그리지 않는다**: 사진 · 스티커 · 그림 · 텍스트 · 외부 디자인은
    /// 잠금화면에 나오지 않는다. 지킬 수 있는 부분(프레임 색)만 정확히 지키고,
    /// 나머지를 흉내 내지 않는다.
    static func preset(for mirror: MyMirror) -> QuickMirrorPresetID {
        basicPreset(matching: mirror.style.frame) ?? QuickMirrorPresetID.fallback
    }

    /// 프레임 색이 기본 거울 8종 중 하나와 같으면 그 preset.
    static func basicPreset(matching color: Color) -> QuickMirrorPresetID? {
        BasicMirror.allCases.first { $0.style.frame == color }.map(\.quickMirrorPreset)
    }

    /// 등록. 실패해도 조용히 넘어간다 — 거울 저장을 막지 않는다.
    static func update(for mirror: MyMirror) async {
        await update(preset: preset(for: mirror))
    }

    static func update(preset: QuickMirrorPresetID) async {
        do {
            try await QuickMirrorCaptureIntent.updateAppContext(
                QuickMirrorContext(presetID: preset)
            )
            QuickMirrorLog.event("context updated preset=\(preset.rawValue)")
        } catch {
            // 잠금화면 프레임이 이전 값으로 남을 뿐이다. 앱은 그대로 동작한다.
            QuickMirrorLog.event("context update failed")
        }
    }
}

// MARK: - 기본 거울 ↔ preset

extension BasicMirror {
    /// 상점 기본 거울과 preset은 **1:1이다.** 새 기본 거울이 생기면 여기서 컴파일이 막힌다.
    var quickMirrorPreset: QuickMirrorPresetID {
        switch self {
        case .white: .white
        case .black: .black
        case .cream: .cream
        case .softPink: .softPink
        case .lavender: .lavender
        case .sky: .sky
        case .mint: .mint
        case .gray: .gray
        }
    }
}
