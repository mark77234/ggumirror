//
//  MirrorCanvasView.swift
//  ggumirror
//
//  하나의 연속된 Master Canvas. Overview / Side Detail / Preview가 모두 이걸 그린다.
//  뷰 크기는 항상 viewport 크기이고, 확대/이동은 그리는 좌표에만 반영한다.
//

import SwiftUI

struct MirrorCanvasView: View {
    let design: MirrorDesign
    /// nil이면 주어진 크기에 꽉 맞춘다. Side Detail은 zoom/pan이 반영된 변환을 넘긴다.
    var transform: MirrorViewTransform?
    /// 지우는 중 화면에서만 감출 획. 데이터는 건드리지 않는다.
    var hiddenStrokeIDs: Set<UUID> = []
    /// 손가락을 떼기 전의 진행 중인 획.
    var activeStroke: DrawingStroke?
    /// 편집 중임을 알려주는 밴드 경계선. Preview에서는 끈다.
    var showsBandGuides = false
    /// 아직 side를 고르지 않았을 때 밴드를 아주 옅게 강조한다.
    var highlightsBands = false

    var body: some View {
        Canvas { context, size in
            let placement = transform ?? .fitted(in: size)

            MirrorRenderer.draw(
                style: design.style,
                strokes: design.strokes,
                activeStroke: activeStroke,
                hiddenStrokeIDs: hiddenStrokeIDs,
                transform: placement,
                in: context,
                viewport: size
            )

            if highlightsBands {
                context.fill(
                    MirrorRenderer.framePath(insets: design.insets, transform: placement),
                    with: .color(PaperTheme.ink.opacity(0.05)),
                    style: FrameMaskShape.fillStyle
                )
            }

            if showsBandGuides {
                for side in EditorSide.allCases {
                    let path = SideBandShape(side: side, insets: design.insets)
                        .path(in: placement.canvasRect)
                    context.stroke(
                        path,
                        with: .color(PaperTheme.ink.opacity(0.35)),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                }
            }
        }
        .modifier(CanvasShapeModifier(isFitted: transform == nil))
    }
}

/// Overview / Preview처럼 캔버스 전체를 보여줄 때만 거울 모양으로 자르고 테두리를 그린다.
private struct CanvasShapeModifier: ViewModifier {
    let isFitted: Bool

    func body(content: Content) -> some View {
        if isFitted {
            let shape = UnevenRoundedRectangle.ink(19, 22, 23, 18)
            content
                .clipShape(shape)
                .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.8))
                .aspectRatio(MirrorCanvas.aspectRatio, contentMode: .fit)
        } else {
            content.clipped()
        }
    }
}

#Preview {
    MirrorCanvasView(
        design: MirrorDesign(mirror: MirrorLibrary().mirrors[3]),
        showsBandGuides: true
    )
    .padding(30)
    .paperBackground()
}
