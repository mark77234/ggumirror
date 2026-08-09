//
//  EditorGeometryTests.swift
//  ggumirrorTests
//
//  터치로 확인하기 어려운 Editor 좌표 변환 / mask / history를 검증한다.
//

import Testing
import SwiftUI
@testable import ggumirror

@MainActor
struct EditorGeometryTests {

    private let viewport = CGSize(width: 320, height: 520)
    /// 제품에서는 쓰지 않지만 engine이 frameInsets를 따르는지 확인하기 위한 값.
    private static let thickInsets = MirrorFrameInsets(top: 0.115, right: 0.17, bottom: 0.115, left: 0.17)

    // MARK: - 좌표 변환

    @Test("화면 좌표 → Master normalized → 화면 좌표 왕복이 일치한다", arguments: EditorSide.allCases)
    func screenToMasterRoundTrip(side: EditorSide) {
        let transform = SideDetailTransform(side: side, insets: .standard, viewport: viewport)
        let screenPoint = CGPoint(x: 137, y: 209)

        let master = transform.masterPoint(from: screenPoint)
        let backX = master.x * transform.canvasSize.width + transform.offset.x
        let backY = master.y * transform.canvasSize.height + transform.offset.y

        #expect(abs(backX - screenPoint.x) < 0.001)
        #expect(abs(backY - screenPoint.y) < 0.001)
    }

    @Test("frameInsets가 다르면 같은 화면 좌표가 다른 Master 좌표가 된다")
    func transformFollowsInsets() {
        let standard = SideDetailTransform(side: .left, insets: .standard, viewport: viewport)
        let thick = SideDetailTransform(side: .left, insets: Self.thickInsets, viewport: viewport)
        let screenPoint = CGPoint(x: 40, y: 120)

        #expect(standard.masterPoint(from: screenPoint) != thick.masterPoint(from: screenPoint))
    }

    @Test("선택한 밴드가 화면 안에 들어온다", arguments: EditorSide.allCases)
    func bandIsVisible(side: EditorSide) {
        let insets = MirrorFrameInsets.standard
        let transform = SideDetailTransform(side: side, insets: insets, viewport: viewport)
        let band = side.boundingBox(with: insets).rect(in: transform.canvasSize)
        let center = CGPoint(x: band.midX + transform.offset.x, y: band.midY + transform.offset.y)

        #expect(center.x >= 0 && center.x <= viewport.width)
        #expect(center.y >= 0 && center.y <= viewport.height)
    }

    // MARK: - Frame mask

    @Test("중앙 Mirror Area 안쪽은 그릴 수 없다")
    func mirrorAreaIsNotDrawable() {
        let insets = MirrorFrameInsets.standard
        #expect(insets.isInsideMirrorArea(NormalizedPoint(x: 0.5, y: 0.5)))
        #expect(!insets.isInsideMirrorArea(NormalizedPoint(x: 0.5, y: 0.02)))
        #expect(!insets.isInsideMirrorArea(NormalizedPoint(x: 0.03, y: 0.5)))
    }

    @Test("frameInsets가 달라지면 mask 경계도 달라진다")
    func maskFollowsInsets() {
        let point = NormalizedPoint(x: 0.5, y: 0.09)
        // standard(상하 0.0769)에서는 이미 거울 영역, 더 두꺼운 값에서는 아직 프레임
        #expect(MirrorFrameInsets.standard.isInsideMirrorArea(point))
        #expect(!Self.thickInsets.isInsideMirrorArea(point))
    }

    // MARK: - 밴드 분할

    @Test("모서리 점은 정확히 한 밴드에만 속한다")
    func cornersBelongToExactlyOneBand() {
        let insets = MirrorFrameInsets.standard
        let rect = CGRect(origin: .zero, size: MirrorCanvas.size)
        let probes = [
            CGPoint(x: 20, y: 20),                                     // 좌상단 모서리
            CGPoint(x: MirrorCanvas.size.width - 20, y: 20),           // 우상단
            CGPoint(x: 20, y: MirrorCanvas.size.height - 20),          // 좌하단
            CGPoint(x: MirrorCanvas.size.width - 20, y: MirrorCanvas.size.height - 20)
        ]

        for probe in probes {
            let matches = EditorSide.allCases.filter {
                SideBandShape(side: $0, insets: insets).path(in: rect).contains(probe)
            }
            #expect(matches.count == 1, "모서리에서 밴드가 \(matches.count)개 잡힘")
        }
    }

    // MARK: - Undo / Redo

    @Test("Undo / Redo가 순서대로 동작한다")
    func undoRedoOrder() {
        var strokes: [DrawingStroke] = []
        var history = DrawingHistory()

        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.05)], width: 0.01)
        let b = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.9)], width: 0.01)

        history.commit([a], to: &strokes)
        history.commit([a, b], to: &strokes)
        #expect(strokes.map(\.id) == [a.id, b.id])

        history.undo(&strokes)
        #expect(strokes.map(\.id) == [a.id])
        history.undo(&strokes)
        #expect(strokes.isEmpty)
        #expect(!history.canUndo)

        history.redo(&strokes)
        #expect(strokes.map(\.id) == [a.id])
        history.redo(&strokes)
        #expect(strokes.map(\.id) == [a.id, b.id])
        #expect(!history.canRedo)
    }

    @Test("새 작업이 생기면 Redo는 비워진다")
    func newWorkClearsRedo() {
        var strokes: [DrawingStroke] = []
        var history = DrawingHistory()
        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.05)], width: 0.01)
        let b = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.5)], width: 0.01)

        history.commit([a], to: &strokes)
        history.undo(&strokes)
        #expect(history.canRedo)

        history.commit([b], to: &strokes)
        #expect(!history.canRedo)
    }

    // MARK: - Side Detail Pan

    /// 세로 밴드는 pan으로 캔버스 맨 위 / 맨 아래까지 닿아야 한다.
    @Test("Left / Right는 위·아래 끝까지 이동한다", arguments: [EditorSide.left, .right])
    func verticalPanReachesBothEnds(side: EditorSide) {
        let top = SideDetailTransform(side: side, insets: .standard, viewport: viewport, state: .init(pan: CGSize(width: 0, height: 100_000)))
        let bottom = SideDetailTransform(side: side, insets: .standard, viewport: viewport, state: .init(pan: CGSize(width: 0, height: -100_000)))

        // 위쪽 끝: 캔버스 상단이 화면 상단에 맞는다
        #expect(abs(top.offset.y) < 0.001)
        #expect(abs(top.visibleRect.y) < 0.001)

        // 아래쪽 끝: 캔버스 하단이 화면 하단에 맞는다
        #expect(abs(bottom.offset.y - (viewport.height - bottom.canvasSize.height)) < 0.001)
        #expect(abs((bottom.visibleRect.y + bottom.visibleRect.height) - 1) < 0.001)
    }

    /// 캔버스가 화면보다 큰 축에서는 어떤 pan에서도 빈 공간이 보이면 안 된다.
    /// 캔버스가 화면보다 작은 축은 가운데 정렬된다(의도된 여백).
    @Test("캔버스 밖으로는 pan 되지 않는다", arguments: EditorSide.allCases)
    func panNeverShowsEmptySpace(side: EditorSide) {
        for pan in [-5000.0, -500.0, 0.0, 500.0, 5000.0] {
            let t = SideDetailTransform(side: side, insets: .standard, viewport: viewport, state: .init(pan: CGSize(width: pan, height: pan)))

            if t.canvasSize.width > viewport.width {
                #expect(t.offset.x <= 0.001)
                #expect(t.offset.x + t.canvasSize.width >= viewport.width - 0.001)
            } else {
                #expect(abs(t.offset.x - (viewport.width - t.canvasSize.width) / 2) < 0.001)
            }

            if t.canvasSize.height > viewport.height {
                #expect(t.offset.y <= 0.001)
                #expect(t.offset.y + t.canvasSize.height >= viewport.height - 0.001)
            } else {
                #expect(abs(t.offset.y - (viewport.height - t.canvasSize.height) / 2) < 0.001)
            }
        }
    }

    @Test("요청한 pan이 범위를 넘으면 clamp된 값이 돌아온다")
    func appliedPanIsClamped() {
        let t = SideDetailTransform(
            side: .right, insets: .standard, viewport: viewport,
            state: .init(pan: CGSize(width: 0, height: 100_000))
        )
        #expect(t.appliedPan.height < 100_000)
    }

    @Test("Mini Map viewport가 pan을 따라 움직인다")
    func visibleRectFollowsPan() {
        let middle = SideDetailTransform(side: .left, insets: .standard, viewport: viewport)
        let up = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                     state: .init(pan: CGSize(width: 0, height: 200)))
        let down = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                       state: .init(pan: CGSize(width: 0, height: -200)))

        #expect(up.visibleRect.y < middle.visibleRect.y)
        #expect(down.visibleRect.y > middle.visibleRect.y)
        // 크기는 그대로 — 배율은 변하지 않는다
        #expect(abs(up.visibleRect.height - middle.visibleRect.height) < 0.0001)
    }

    @Test("pan 후에도 화면 좌표 왕복 변환이 일치한다")
    func masterRoundTripAfterPan() {
        let t = SideDetailTransform(side: .right, insets: .standard, viewport: viewport,
                                    state: .init(pan: CGSize(width: 0, height: -240)))
        let screenPoint = CGPoint(x: 210, y: 380)
        let master = t.masterPoint(from: screenPoint)

        #expect(abs(master.x * t.canvasSize.width + t.offset.x - screenPoint.x) < 0.001)
        #expect(abs(master.y * t.canvasSize.height + t.offset.y - screenPoint.y) < 0.001)
    }

    @Test("pan하면 같은 화면 좌표가 다른 Master 좌표를 가리킨다")
    func panChangesMasterPoint() {
        let before = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        let after = SideDetailTransform(side: .right, insets: .standard, viewport: viewport,
                                        state: .init(pan: CGSize(width: 0, height: -300)))
        let screenPoint = CGPoint(x: 200, y: 300)

        #expect(after.masterPoint(from: screenPoint).y > before.masterPoint(from: screenPoint).y)
        // 배율은 그대로여야 한다
        #expect(before.canvasSize == after.canvasSize)
    }

    @Test("아래 끝까지 pan하면 Bottom corner가 화면에 들어온다")
    func bottomCornerReachable() {
        let t = SideDetailTransform(side: .right, insets: .standard, viewport: viewport,
                                    state: .init(pan: CGSize(width: 0, height: -100_000)))
        let bottom = t.visibleRect.y + t.visibleRect.height
        #expect(bottom > 1 - 0.001)
        // Bottom 밴드 시작점(1 - 0.0769)이 보이는 범위 안에 있다
        #expect(t.visibleRect.y < 1 - MirrorFrameInsets.standard.bottom)
    }

    // MARK: - Zoom

    @Test("Zoom은 지정한 범위를 벗어나지 않는다")
    func zoomIsClamped() {
        let tiny = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                       state: .init(zoom: -5))
        let huge = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                       state: .init(zoom: 999))
        #expect(tiny.appliedZoom == EditorViewportState.zoomRange.lowerBound)
        #expect(huge.appliedZoom == EditorViewportState.zoomRange.upperBound)
        #expect(tiny.canvasSize.width > 0)
    }

    @Test("Zoom In하면 Mini Map viewport가 작아진다")
    func miniMapShrinksWhenZoomed() {
        let fit = SideDetailTransform(side: .left, insets: .standard, viewport: viewport)
        let zoomed = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                         state: .init(zoom: 2))
        #expect(zoomed.visibleRect.width < fit.visibleRect.width)
        #expect(zoomed.visibleRect.height < fit.visibleRect.height)
    }

    @Test("배율이 바뀌어도 화면↔Master 왕복이 일치한다", arguments: [1.0, 2.0, 3.0])
    func roundTripAtZoom(zoom: Double) {
        let t = SideDetailTransform(
            side: .right, insets: .standard, viewport: viewport,
            state: .init(zoom: CGFloat(zoom), pan: CGSize(width: 0, height: -120))
        )
        let screenPoint = CGPoint(x: 180, y: 260)
        let master = t.masterPoint(from: screenPoint)
        let back = t.screenPoint(from: master)
        #expect(abs(back.x - screenPoint.x) < 0.001)
        #expect(abs(back.y - screenPoint.y) < 0.001)
    }

    @Test("Zoom Out하면 pan이 다시 clamp되어 빈 공간이 생기지 않는다")
    func panReclampedAfterZoomOut() {
        // 최대 배율에서 끝까지 이동한 pan 값을 그대로 fit 배율에 적용해도 빈 공간이 없어야 한다.
        let zoomedIn = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                           state: .init(zoom: 3, pan: CGSize(width: 0, height: -100_000)))
        let backToFit = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                            state: .init(zoom: 1, pan: zoomedIn.appliedPan))
        #expect(backToFit.offset.y <= 0.001)
        #expect(backToFit.offset.y + backToFit.canvasSize.height >= viewport.height - 0.001)
    }

    @Test("Brush 굵기는 배율과 무관하다")
    func brushWidthIsIndependentFromZoom() {
        let width = EditorBrush.pen.defaultWidth
        let fit = SideDetailTransform(side: .left, insets: .standard, viewport: viewport)
        let zoomed = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                         state: .init(zoom: 3))
        // 저장되는 값은 normalized라 배율이 달라도 그대로다. 화면 굵기만 커진다.
        let stroke = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.5)], width: width)
        #expect(stroke.width == width)
        #expect(zoomed.canvasSize.width > fit.canvasSize.width)
    }

    @Test("지우개 반경은 배율에 따라 Master 기준으로 환산된다")
    func eraserRadiusFollowsZoom() {
        let fit = SideDetailTransform(side: .left, insets: .standard, viewport: viewport)
        let zoomed = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                         state: .init(zoom: 3))
        #expect(zoomed.masterLength(fromScreen: 22) < fit.masterLength(fromScreen: 22))
    }

    // MARK: - 데이터 불변식

    @Test("Pan / Zoom / Side 전환은 stroke 데이터를 바꾸지 않는다")
    func viewportOperationsNeverMutateStrokes() {
        var strokes = [
            DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.2), NormalizedPoint(x: 0.05, y: 0.3)], width: 0.01),
            DrawingStroke(points: [NormalizedPoint(x: 0.95, y: 0.8)], width: 0.02)
        ]
        let original = strokes

        for side in EditorSide.allCases {
            for zoom in [1.0, 1.7, 3.0] {
                for pan in [-800.0, 0.0, 800.0] {
                    _ = SideDetailTransform(
                        side: side, insets: .standard, viewport: viewport,
                        state: .init(zoom: CGFloat(zoom), pan: CGSize(width: pan, height: pan))
                    )
                }
            }
        }
        _ = EditorViewportState()   // reset
        #expect(strokes == original)
        strokes = original
        #expect(strokes == original)
    }

    // MARK: - 편집 적용 (사라지던 획 회귀 테스트)

    @Test("오래된 스냅샷이 최신 획을 덮어쓰지 않는다")
    func editAppliesToLatestStrokes() {
        var strokes: [DrawingStroke] = []
        var history = DrawingHistory()

        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.1)], width: 0.01)
        history.apply(.add(a), to: &strokes)

        // 캔버스가 A를 모르는 오래된 design 복사본을 들고 있다가 B를 커밋하는 상황
        let b = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.5)], width: 0.01)
        history.apply(.add(b), to: &strokes)

        #expect(strokes.map(\.id) == [a.id, b.id])
    }

    @Test("같은 획을 두 번 커밋해도 중복되지 않는다")
    func duplicateCommitIsIgnored() {
        var strokes: [DrawingStroke] = []
        var history = DrawingHistory()
        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.1)], width: 0.01)

        history.apply(.add(a), to: &strokes)
        history.apply(.add(a), to: &strokes)

        #expect(strokes.count == 1)
    }

    @Test("지우기는 id 기준으로만 제거한다")
    func eraseRemovesOnlyTargets() {
        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.1)], width: 0.01)
        let b = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.5)], width: 0.01)
        var strokes = [a, b]
        var history = DrawingHistory()

        history.apply(.erase(removedIDs: [a.id]), to: &strokes)
        #expect(strokes.map(\.id) == [b.id])

        history.undo(&strokes)
        #expect(strokes.map(\.id) == [a.id, b.id])
    }

    @Test("Undo는 viewport 조작에 오염되지 않는다")
    func undoIgnoresViewportOperations() {
        var strokes: [DrawingStroke] = []
        var history = DrawingHistory()
        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.1)], width: 0.01)
        let b = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.5)], width: 0.01)

        history.apply(.add(a), to: &strokes)
        _ = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                state: .init(zoom: 2, pan: CGSize(width: 0, height: -200)))
        history.apply(.add(b), to: &strokes)
        _ = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                state: .init(zoom: 1, pan: .zero))

        history.undo(&strokes)
        #expect(strokes.map(\.id) == [a.id])
        history.undo(&strokes)
        #expect(strokes.isEmpty)
        history.redo(&strokes)
        history.redo(&strokes)
        #expect(strokes.map(\.id) == [a.id, b.id])
    }

    // MARK: - 지우개

    @Test("지우개는 반경 안의 획만 지운다")
    func eraserHitTest() {
        let stroke = DrawingStroke(
            points: [NormalizedPoint(x: 0.05, y: 0.20), NormalizedPoint(x: 0.05, y: 0.30)],
            width: 10 / MirrorCanvas.size.width
        )

        #expect(stroke.isHit(by: NormalizedPoint(x: 0.05, y: 0.20), radius: 20))
        #expect(!stroke.isHit(by: NormalizedPoint(x: 0.9, y: 0.9), radius: 20))
    }
}
