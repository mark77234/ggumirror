//
//  QuickMirrorFrameView.swift
//  ggumirror
//
//  잠금화면 Quick Mirror의 프레임 overlay.
//
//  **카메라 위 · 조작 버튼 아래**에 놓인다. 촬영 버튼과 "꾸미러 열기"를 가리지 않고,
//  터치를 먹지 않는다(`allowsHitTesting(false)`).
//
//  저장소 · 이미지 파일 · network · asset을 하나도 쓰지 않는다 —
//  SwiftUI Shape 하나로만 그린다. 그래서 잠금 상태에서도 즉시 뜬다.
//

import SwiftUI

struct QuickMirrorFrameView: View {
    let preset: QuickMirrorPresetID

    var body: some View {
        GeometryReader { proxy in
            if let color = preset.frameColor {
                // even-odd로 채워야 안쪽 구멍이 비워진다. 기본(non-zero)이면 전체가 칠해진다.
                QuickMirrorFrameShape(size: proxy.size)
                    .fill(color, style: FillStyle(eoFill: true))
                    // 구멍 경계에 아주 옅은 선. 카메라와 프레임이 붙어 보이지 않게만 한다.
                    .overlay(
                        QuickMirrorHoleShape(size: proxy.size)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }
        }
        .ignoresSafeArea()
        // 프레임은 장식이다. 촬영 / 앱 열기 조작을 절대 막지 않는다.
        .allowsHitTesting(false)
    }
}

// MARK: - Shape

/// 바깥 사각형에서 안쪽 둥근 구멍을 뺀 **프레임 밴드**.
nonisolated struct QuickMirrorFrameShape: Shape {
    let size: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addPath(QuickMirrorHoleShape(size: rect.size).path(in: rect))
        return path
    }

    /// 겹치는 부분을 비워 구멍을 만든다.
    var fillStyle: FillStyle { FillStyle(eoFill: true) }
}

nonisolated struct QuickMirrorHoleShape: Shape {
    let size: CGSize

    func path(in rect: CGRect) -> Path {
        Path(
            roundedRect: QuickMirrorFrame.hole(in: rect.size),
            cornerRadius: QuickMirrorFrame.cornerRadius(in: rect.size)
        )
    }
}
