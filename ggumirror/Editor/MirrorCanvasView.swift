//
//  MirrorCanvasView.swift
//  ggumirror
//
//  하나의 연속된 Master Canvas. Overview / Side Detail / Preview가 모두 이걸 그린다.
//  side별로 잘라 그리지 않기 때문에 모서리 장식과 획이 끊기지 않는다.
//

import SwiftUI

struct MirrorCanvasView: View {
    let design: MirrorDesign
    /// 그리는 중에만 쓰는 임시 획 목록. nil이면 design.strokes를 그린다.
    var strokesOverride: [DrawingStroke]?
    /// 손가락을 떼기 전의 진행 중인 획.
    var activeStroke: DrawingStroke?
    /// 편집 중임을 알려주는 밴드 경계선. Preview에서는 끈다.
    var showsBandGuides = false

    private var strokes: [DrawingStroke] {
        (strokesOverride ?? design.strokes).sorted { $0.zIndex < $1.zIndex }
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                MirrorPreview(style: design.style)

                // 획은 프레임 영역에만 남는다. 중앙 Mirror Area는 항상 비워둔다.
                Canvas { context, canvasSize in
                    for stroke in strokes {
                        StrokeRenderer.draw(stroke, in: context, size: canvasSize)
                    }
                    if let activeStroke {
                        StrokeRenderer.draw(activeStroke, in: context, size: canvasSize)
                    }
                }
                .clipShape(FrameMaskShape(insets: design.insets), style: FrameMaskShape.fillStyle)
                .allowsHitTesting(false)

                // Sticker / Text는 Phase 3-3에서 여기에 얹힌다.
                ForEach(design.objects) { object in
                    let frame = object.frame.rect(in: size)
                    Rectangle()
                        .fill(PaperTheme.ink.opacity(0.12))
                        .frame(width: frame.width, height: frame.height)
                        .rotationEffect(.degrees(object.rotation))
                        .opacity(object.opacity)
                        .position(x: frame.midX, y: frame.midY)
                        .zIndex(Double(object.zIndex))
                }

                if showsBandGuides {
                    bandGuides(in: size)
                }
            }
        }
        .aspectRatio(MirrorCanvas.aspectRatio, contentMode: .fit)
    }

    /// 네 밴드의 경계를 아주 옅은 점선으로만 보여준다.
    private func bandGuides(in size: CGSize) -> some View {
        ForEach(EditorSide.allCases) { side in
            SideBandShape(side: side, insets: design.insets)
                .stroke(
                    PaperTheme.ink.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
                .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
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
