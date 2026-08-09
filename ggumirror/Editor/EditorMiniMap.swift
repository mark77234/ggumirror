//
//  EditorMiniMap.swift
//  ggumirror
//
//  Side Detail에서 지금 거울의 어느 부분을 보고 있는지 알려준다.
//

import SwiftUI

struct EditorMiniMap: View {
    let insets: MirrorFrameInsets
    let side: EditorSide
    /// 현재 보이는 영역 (Master Canvas 기준 0...1).
    let viewport: NormalizedRect

    var height: CGFloat = 56

    var body: some View {
        let width = height * MirrorCanvas.aspectRatio

        ZStack {
            // 전체 캔버스
            RoundedRectangle(cornerRadius: 5)
                .fill(PaperTheme.subtleSurface)

            // 중앙 Mirror Area
            let mirror = insets.mirrorArea.rect(in: CGSize(width: width, height: height))
            RoundedRectangle(cornerRadius: 2)
                .fill(MirrorRenderer.glass)
                .frame(width: mirror.width, height: mirror.height)
                .position(x: mirror.midX, y: mirror.midY)

            // 지금 편집 중인 side
            SideBandShape(side: side, insets: insets)
                .fill(PaperTheme.ink.opacity(0.75))
                .frame(width: width, height: height)

            // 현재 viewport
            let box = viewport.rect(in: CGSize(width: width, height: height))
            Rectangle()
                .stroke(PaperTheme.ink, lineWidth: 1.4)
                .frame(width: max(box.width, 3), height: max(box.height, 3))
                .position(x: box.midX, y: box.midY)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(PaperTheme.ink, lineWidth: 1.4)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(side.title) 밴드를 편집 중")
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(EditorSide.allCases) { side in
            EditorMiniMap(
                insets: .standard,
                side: side,
                viewport: side.boundingBox(with: .standard)
            )
        }
    }
    .padding(30)
    .paperBackground()
}
