//
//  SideDetailCanvas.swift
//  ggumirror
//
//  Side Detail은 같은 Master Canvas를 uniform scale + translation으로 확대해서 볼 뿐이다.
//  그리기 / 지우기는 화면 좌표를 역변환해 Master normalized 좌표로만 다룬다.
//  Pan / Zoom은 viewport state만 바꾸고 디자인 데이터는 건드리지 않는다.
//

import SwiftUI

/// 캔버스가 요청하는 편집. 배열 스냅샷을 통째로 넘기지 않아서
/// 오래된 design 복사본이 최신 획을 덮어쓰는 일이 생기지 않는다.
enum DrawingEdit {
    case add(DrawingStroke)
    case erase(removedIDs: Set<UUID>)
}

struct SideDetailCanvas: View {
    let design: MirrorDesign
    let side: EditorSide
    let tool: EditorTool
    let brush: EditorBrush
    let brushWidth: Double
    let brushColor: Color

    /// 이 side의 보기 상태. Editor session UI state이고 디자인 데이터가 아니다.
    @Binding var viewport: EditorViewportState
    @Binding var visibleRect: NormalizedRect
    /// 제스처가 끝났을 때만 확정한다. 그리는 동안에는 design을 건드리지 않는다.
    let onEdit: (DrawingEdit) -> Void

    /// 손가락을 떼기 전의 진행 중인 획. 여기만 자주 갱신된다.
    @State private var activeStroke: DrawingStroke?
    /// 지우는 동안 지워질 예정인 획.
    @State private var pendingErase: Set<UUID> = []
    /// 두 손가락 조작 시작 시점의 viewport.
    @State private var viewportAtGestureStart: EditorViewportState?

    /// 화면 기준 지우개 반경. Master 반경은 배율에 따라 환산된다.
    private let eraserScreenRadius: CGFloat = 22
    /// 너무 촘촘한 점은 버려 성능과 곡선 품질을 지킨다 (Master Canvas 픽셀 기준).
    private let minimumPointSpacing: Double = 6
    /// 이 개수 이상이면 제스처가 취소돼도 살릴 가치가 있는 획으로 본다.
    private let minimumCommittablePoints = 2

    var body: some View {
        GeometryReader { proxy in
            let transform = SideDetailTransform(
                side: side,
                insets: design.insets,
                viewport: proxy.size,
                state: viewport
            )

            ZStack {
                // 뷰는 항상 viewport 크기다. 확대/이동은 그리는 좌표에만 반영한다.
                MirrorCanvasView(
                    design: design,
                    transform: MirrorViewTransform(
                        canvasSize: transform.canvasSize,
                        offset: transform.offset
                    ),
                    hiddenStrokeIDs: pendingErase,
                    activeStroke: activeStroke,
                    showsBandGuides: true
                )
                .allowsHitTesting(false)

                EditorCanvasGestureOverlay(
                    onTouch: { handleTouch($0, transform: transform) },
                    onNavigate: { navigate($0, transform: transform, viewportSize: proxy.size) }
                )

                ScrollHandle(
                    side: side,
                    progress: verticalProgress(transform),
                    onDrag: { delta in movePan(byHandle: delta, viewportSize: proxy.size) }
                )
            }
            .onChange(of: transform.visibleRect, initial: true) { _, newValue in
                visibleRect = newValue
            }
            .onChange(of: tool) { _, _ in
                // 도구가 바뀌어도 이미 그린 획은 버리지 않는다.
                commitActiveWork()
            }
            .onChange(of: side) { _, _ in commitActiveWork() }
        }
        .padding(.vertical, 8)
    }

    // MARK: - 한 손가락

    private func handleTouch(_ phase: CanvasTouchPhase, transform: SideDetailTransform) {
        switch phase {
        case .began(let location), .moved(let location):
            let point = transform.masterPoint(from: location)
            switch tool {
            case .draw: extendStroke(to: point)
            case .erase: erase(at: point, transform: transform)
            }
        case .ended, .cancelled:
            // 취소여도 유효한 작업이면 저장한다. 사용자가 그린 선이 이유 없이 사라지지 않게.
            commitActiveWork()
        }
    }

    private func extendStroke(to point: NormalizedPoint) {
        // 중앙 Mirror Area에는 그리지 않는다. 두께는 design의 frameInsets에서 온다.
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
                // 배율과 무관하게 Master Canvas 기준 굵기를 그대로 저장한다.
                width: brushWidth,
                opacity: brush.opacity,
                zIndex: (design.strokes.map(\.zIndex).max() ?? 0) + 1
            )
        }
    }

    private func erase(at point: NormalizedPoint, transform: SideDetailTransform) {
        guard !design.insets.isInsideMirrorArea(point) else { return }
        // 화면 반경을 Master 반경으로 환산하므로 확대해도 체감 반경이 같다.
        let radius = transform.masterLength(fromScreen: eraserScreenRadius)
        let hits = design.strokes
            .filter { !pendingErase.contains($0.id) && $0.isHit(by: point, radius: radius) }
            .map(\.id)
        guard !hits.isEmpty else { return }
        pendingErase.formUnion(hits)
    }

    /// 진행 중이던 작업을 확정한다. 아직 아무것도 안 그린 제스처만 조용히 버린다.
    private func commitActiveWork() {
        if let stroke = activeStroke {
            if stroke.points.count >= minimumCommittablePoints || tool == .draw {
                onEdit(.add(stroke))
            }
            activeStroke = nil
        }
        if !pendingErase.isEmpty {
            onEdit(.erase(removedIDs: pendingErase))
            pendingErase = []
        }
    }

    // MARK: - Scroll Handle

    /// 현재 세로 위치(0 = 맨 위, 1 = 맨 아래). Mini Map과 같은 visibleRect에서 계산한다.
    private func verticalProgress(_ transform: SideDetailTransform) -> Double {
        let travel = 1 - transform.visibleRect.height
        guard travel > 0.0001 else { return 0 }
        return min(max(transform.visibleRect.y / travel, 0), 1)
    }

    /// Handle 드래그도 두 손가락 Pan과 같은 viewport state를 바꾼다.
    private func movePan(byHandle delta: CGFloat, viewportSize: CGSize) {
        var next = viewport
        next.pan.height -= delta
        let clamped = SideDetailTransform(
            side: side,
            insets: design.insets,
            viewport: viewportSize,
            state: next
        )
        viewport = EditorViewportState(zoom: clamped.appliedZoom, pan: clamped.appliedPan)
    }

    // MARK: - 두 손가락

    private func navigate(_ navigation: CanvasNavigation, transform: SideDetailTransform, viewportSize: CGSize) {
        guard !navigation.isEnded else {
            viewportAtGestureStart = nil
            return
        }
        if viewportAtGestureStart == nil {
            viewportAtGestureStart = viewport
            // 두 손가락이 시작되면 한 손가락 작업은 이미 확정된 상태여야 한다.
            commitActiveWork()
        }

        var next = viewport
        next.pan.width += navigation.translationDelta.width
        next.pan.height += navigation.translationDelta.height

        if navigation.scaleDelta != 1 {
            // 손가락 사이 지점이 그대로 있도록 배율 변경 후 위치를 보정한다.
            let anchor = transform.masterPoint(from: navigation.center)
            next.zoom = min(
                max(viewport.zoom * navigation.scaleDelta, EditorViewportState.zoomRange.lowerBound),
                EditorViewportState.zoomRange.upperBound
            )
            let zoomed = SideDetailTransform(
                side: side,
                insets: design.insets,
                viewport: viewportSize,
                state: next
            )
            let moved = zoomed.screenPoint(from: anchor)
            next.pan.width += navigation.center.x - moved.x
            next.pan.height += navigation.center.y - moved.y
        }

        // 배율이 바뀌면 pan 범위도 달라지므로 항상 다시 clamp된 값을 저장한다.
        let clamped = SideDetailTransform(
            side: side,
            insets: design.insets,
            viewport: viewportSize,
            state: next
        )
        viewport = EditorViewportState(zoom: clamped.appliedZoom, pan: clamped.appliedPan)
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
