//
//  SideDetailCanvas.swift
//  ggumirror
//
//  Side Detail은 같은 Master Canvas를 uniform scale + translation으로 확대해서 볼 뿐이다.
//  그리기 / 지우기도 화면 좌표를 역변환해 Master normalized 좌표로만 다룬다.
//

import SwiftUI

struct SideDetailCanvas: View {
    let design: MirrorDesign
    let side: EditorSide
    let tool: EditorTool
    let brush: EditorBrush
    let brushWidth: Double
    let brushColor: Color

    @Binding var visibleRect: NormalizedRect
    /// 제스처가 끝났을 때만 확정한다. 그리는 동안에는 design을 건드리지 않는다.
    let onCommit: ([DrawingStroke]) -> Void

    /// 손가락을 떼기 전의 진행 중인 획. 여기만 자주 갱신된다.
    @State private var activeStroke: DrawingStroke?
    /// 지우는 동안의 임시 결과.
    @State private var erasedPreview: [DrawingStroke]?

    /// 화면 기준 지우개 반경.
    private let eraserScreenRadius: CGFloat = 22
    /// 너무 촘촘한 점은 버려 성능과 곡선 품질을 지킨다 (Master Canvas 픽셀 기준).
    private let minimumPointSpacing: Double = 6

    var body: some View {
        GeometryReader { proxy in
            let transform = SideDetailTransform(
                side: side,
                insets: design.insets,
                viewport: proxy.size
            )

            MirrorCanvasView(
                design: design,
                strokesOverride: erasedPreview,
                activeStroke: activeStroke,
                showsBandGuides: true
            )
            .frame(width: transform.canvasSize.width, height: transform.canvasSize.height)
            .offset(x: transform.offset.x, y: transform.offset.y)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(.rect)
            .gesture(drawGesture(transform))
            .onChange(of: proxy.size, initial: true) { _, _ in
                visibleRect = transform.visibleRect
            }
            .onChange(of: tool) { _, _ in cancelGesture() }
        }
        .padding(.vertical, 8)
    }

    private func drawGesture(_ transform: SideDetailTransform) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = transform.masterPoint(from: value.location)
                switch tool {
                case .draw: extendStroke(to: point)
                case .erase: erase(at: point, transform: transform)
                }
            }
            .onEnded { _ in finish() }
    }

    // MARK: - Draw

    private func extendStroke(to point: NormalizedPoint) {
        // 중앙 Mirror Area에는 그리지 않는다. 두께는 template의 frameInsets에서 온다.
        guard !design.insets.isInsideMirrorArea(point) else { return }

        if var stroke = activeStroke {
            guard let last = stroke.points.last,
                  last.masterDistance(to: point) >= minimumPointSpacing
            else { return }
            stroke.points.append(point)
            activeStroke = stroke
        } else {
            activeStroke = DrawingStroke(
                points: [point],
                brush: brush,
                color: brushColor,
                width: brushWidth,
                opacity: brush.opacity,
                zIndex: (design.strokes.map(\.zIndex).max() ?? 0) + 1
            )
        }
    }

    // MARK: - Erase

    private func erase(at point: NormalizedPoint, transform: SideDetailTransform) {
        guard !design.insets.isInsideMirrorArea(point) else { return }
        let radius = transform.masterLength(fromScreen: eraserScreenRadius)
        var working = erasedPreview ?? design.strokes
        working.removeAll { $0.isHit(by: point, radius: radius) }
        erasedPreview = working
    }

    // MARK: - Commit

    private func finish() {
        switch tool {
        case .draw:
            if let stroke = activeStroke {
                onCommit(design.strokes + [stroke])
            }
        case .erase:
            if let erasedPreview {
                onCommit(erasedPreview)
            }
        }
        cancelGesture()
    }

    private func cancelGesture() {
        activeStroke = nil
        erasedPreview = nil
    }
}

enum EditorTool: String, CaseIterable, Identifiable {
    case draw, erase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draw: "그리기"
        case .erase: "지우개"
        }
    }

    var icon: String {
        switch self {
        case .draw: "scribble"
        case .erase: "eraser"
        }
    }
}
