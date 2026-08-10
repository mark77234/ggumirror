//
//  MirrorCanvasView.swift
//  ggumirror
//
//  하나의 연속된 Master Canvas. Editor / Preview가 모두 이걸 그린다.
//  뷰 크기는 항상 viewport 크기이고, 확대/이동은 그리는 좌표에만 반영한다.
//

import SwiftUI

struct MirrorCanvasView: View {
    let design: MirrorDesign
    /// nil이면 주어진 크기에 꽉 맞춘다. Editor는 zoom/pan이 반영된 변환을 넘긴다.
    var transform: MirrorViewTransform?
    /// 지우는 중 화면에서만 감출 획. 데이터는 건드리지 않는다.
    var hiddenStrokeIDs: Set<UUID> = []
    /// 손가락을 떼기 전의 진행 중인 획.
    var activeStroke: DrawingStroke?
    /// 카메라 영역을 무슨 색으로 채울지.
    /// 미리보기는 어두운 거울 면, Editor는 배경색(연속된 한 장처럼 보이게).
    var mirrorAreaFill: Color? = MirrorRenderer.glass
    /// 실제 거울에서 카메라가 보이는 영역 안내선. **Editor에서만** 켠다.
    /// 실제 Mirror / Capture / 미리보기에는 절대 나타나지 않는다.
    var showsCameraGuide = false

    var body: some View {
        Canvas { context, size in
            let placement = transform ?? .fitted(in: size)

            MirrorRenderer.draw(
                style: design.style,
                strokes: design.strokes,
                stickers: design.stickers,
                texts: design.texts,
                activeStroke: activeStroke,
                hiddenStrokeIDs: hiddenStrokeIDs,
                transform: placement,
                mirrorAreaFill: mirrorAreaFill,
                in: context,
                viewport: size
            )

            // 카메라 안내선. "여기가 카메라"라는 정보일 뿐, 꾸미면 안 된다는 뜻이 아니라
            // 아주 옅은 점선만 쓴다. 실제 거울과 같은 rounded geometry를 공유한다.
            if showsCameraGuide {
                context.stroke(
                    design.insets.mirrorAreaPath(in: placement.canvasRect),
                    with: .color(PaperTheme.secondaryInk.opacity(0.5)),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
            }
        }
        .modifier(CanvasShapeModifier(isFitted: transform == nil))
    }
}

/// Preview처럼 캔버스 전체를 보여줄 때만 거울 모양으로 자르고 테두리를 그린다.
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
    MirrorCanvasView(design: .blank, showsCameraGuide: true)
        .padding(30)
        .paperBackground()
}
