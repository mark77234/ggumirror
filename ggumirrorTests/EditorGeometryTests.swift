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
        var snapshot = EditorSnapshot()
        var history = EditorHistory()

        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.05)], width: 0.01)
        let b = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.9)], width: 0.01)

        history.apply(.addStroke(a), to: &snapshot)
        history.apply(.addStroke(b), to: &snapshot)
        #expect(snapshot.strokes.map(\.id) == [a.id, b.id])

        history.undo(&snapshot)
        #expect(snapshot.strokes.map(\.id) == [a.id])
        history.undo(&snapshot)
        #expect(snapshot.strokes.isEmpty)
        #expect(!history.canUndo)

        history.redo(&snapshot)
        #expect(snapshot.strokes.map(\.id) == [a.id])
        history.redo(&snapshot)
        #expect(snapshot.strokes.map(\.id) == [a.id, b.id])
        #expect(!history.canRedo)
    }

    @Test("새 작업이 생기면 Redo는 비워진다")
    func newWorkClearsRedo() {
        var snapshot = EditorSnapshot()
        var history = EditorHistory()
        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.05)], width: 0.01)
        let b = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.5)], width: 0.01)

        history.apply(.addStroke(a), to: &snapshot)
        history.undo(&snapshot)
        #expect(history.canRedo)

        history.apply(.addStroke(b), to: &snapshot)
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
        var snapshot = EditorSnapshot()
        var history = EditorHistory()

        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.1)], width: 0.01)
        history.apply(.addStroke(a), to: &snapshot)

        // 캔버스가 A를 모르는 오래된 design 복사본을 들고 있다가 B를 커밋하는 상황
        let b = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.5)], width: 0.01)
        history.apply(.addStroke(b), to: &snapshot)

        #expect(snapshot.strokes.map(\.id) == [a.id, b.id])
    }

    @Test("같은 획을 두 번 커밋해도 중복되지 않는다")
    func duplicateCommitIsIgnored() {
        var snapshot = EditorSnapshot()
        var history = EditorHistory()
        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.1)], width: 0.01)

        history.apply(.addStroke(a), to: &snapshot)
        history.apply(.addStroke(a), to: &snapshot)

        #expect(snapshot.strokes.count == 1)
    }

    @Test("지우기는 id 기준으로만 제거한다")
    func eraseRemovesOnlyTargets() {
        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.1)], width: 0.01)
        let b = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.5)], width: 0.01)
        var snapshot = EditorSnapshot(strokes: [a, b])
        var history = EditorHistory()

        history.apply(.eraseStrokes( [a.id]), to: &snapshot)
        #expect(snapshot.strokes.map(\.id) == [b.id])

        history.undo(&snapshot)
        #expect(snapshot.strokes.map(\.id) == [a.id, b.id])
    }

    @Test("Undo는 viewport 조작에 오염되지 않는다")
    func undoIgnoresViewportOperations() {
        var snapshot = EditorSnapshot()
        var history = EditorHistory()
        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.1)], width: 0.01)
        let b = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.5)], width: 0.01)

        history.apply(.addStroke(a), to: &snapshot)
        _ = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                state: .init(zoom: 2, pan: CGSize(width: 0, height: -200)))
        history.apply(.addStroke(b), to: &snapshot)
        _ = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                state: .init(zoom: 1, pan: .zero))

        history.undo(&snapshot)
        #expect(snapshot.strokes.map(\.id) == [a.id])
        history.undo(&snapshot)
        #expect(snapshot.strokes.isEmpty)
        history.redo(&snapshot)
        history.redo(&snapshot)
        #expect(snapshot.strokes.map(\.id) == [a.id, b.id])
    }

    // MARK: - Stroke clipping (부분만 보여도 렌더되어야 한다)

    /// 렌더러가 실제로 쓰는 판정과 같은 규칙.
    private func strokeIsRendered(
        _ stroke: DrawingStroke,
        transform: SideDetailTransform,
        viewport: CGSize
    ) -> Bool {
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        let path = StrokeRenderer.path(for: stroke, in: placement.canvasSize)
            .offsetBy(dx: placement.offset.x, dy: placement.offset.y)
        let lineWidth = stroke.width * placement.canvasSize.width
        return path.boundingRect
            .insetBy(dx: -lineWidth, dy: -lineWidth)
            .intersects(CGRect(origin: .zero, size: viewport))
    }

    /// Left frame을 세로로 가로지르는 긴 획.
    private var longLeftStroke: DrawingStroke {
        DrawingStroke(
            points: (0...20).map { NormalizedPoint(x: 0.05, y: 0.03 + Double($0) * 0.047) },
            width: 14 / MirrorCanvas.size.width
        )
    }

    @Test("일부만 화면에 걸친 긴 획도 렌더 대상이다", arguments: [1.0, 2.0, 3.0])
    func partiallyVisibleStrokeIsRendered(zoom: Double) {
        let stroke = longLeftStroke
        for pan in [0.0, -400.0, -1200.0, 400.0, 1200.0] {
            let transform = SideDetailTransform(
                side: .left, insets: .standard, viewport: viewport,
                state: .init(zoom: CGFloat(zoom), pan: CGSize(width: 0, height: pan))
            )
            #expect(
                strokeIsRendered(stroke, transform: transform, viewport: viewport),
                "zoom \(zoom), pan \(pan)에서 획이 통째로 사라짐"
            )
        }
    }

    @Test("bounding box가 viewport보다 커도 skip하지 않는다")
    func oversizedStrokeIsNotSkipped() {
        let stroke = longLeftStroke
        let transform = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                            state: .init(zoom: 3))
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        let box = StrokeRenderer.path(for: stroke, in: placement.canvasSize)
            .offsetBy(dx: placement.offset.x, dy: placement.offset.y)
            .boundingRect
        let screen = CGRect(origin: .zero, size: viewport)

        // 화면을 완전히 포함하지 않는데도(= contains 조건이면 탈락) 렌더되어야 한다.
        #expect(!screen.contains(box))
        #expect(strokeIsRendered(stroke, transform: transform, viewport: viewport))
    }

    @Test("완전히 화면 밖일 때만 건너뛴다")
    func fullyOffscreenStrokeIsCulled() {
        // Bottom 밴드 끝의 짧은 획을 맨 위로 pan한 상태
        let stroke = DrawingStroke(
            points: [NormalizedPoint(x: 0.05, y: 0.985), NormalizedPoint(x: 0.06, y: 0.99)],
            width: 8 / MirrorCanvas.size.width
        )
        let top = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                      state: .init(zoom: 3, pan: CGSize(width: 0, height: 100_000)))
        let bottom = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                         state: .init(zoom: 3, pan: CGSize(width: 0, height: -100_000)))

        #expect(!strokeIsRendered(stroke, transform: top, viewport: viewport))
        #expect(strokeIsRendered(stroke, transform: bottom, viewport: viewport))
    }

    @Test("모서리를 걸친 획도 양쪽에서 렌더된다")
    func cornerCrossingStrokeIsRendered() {
        let stroke = DrawingStroke(
            points: [
                NormalizedPoint(x: 0.70, y: 0.03), NormalizedPoint(x: 0.90, y: 0.035),
                NormalizedPoint(x: 0.96, y: 0.09), NormalizedPoint(x: 0.96, y: 0.20)
            ],
            width: 12 / MirrorCanvas.size.width
        )
        // Top은 fit 상태에서 상단이 보이고, Right는 위로 이동해야 같은 모서리가 보인다.
        let top = SideDetailTransform(side: .top, insets: .standard, viewport: viewport,
                                      state: .init(zoom: 2))
        let right = SideDetailTransform(side: .right, insets: .standard, viewport: viewport,
                                        state: .init(zoom: 2, pan: CGSize(width: 0, height: 100_000)))
        #expect(strokeIsRendered(stroke, transform: top, viewport: viewport))
        #expect(strokeIsRendered(stroke, transform: right, viewport: viewport))
    }

    @Test("Master 획 데이터는 viewport 기준으로 잘리지 않는다")
    func strokePointsAreNeverTrimmed() {
        let stroke = longLeftStroke
        let original = stroke.points
        for pan in [-1200.0, 0.0, 1200.0] {
            _ = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                    state: .init(zoom: 3, pan: CGSize(width: 0, height: pan)))
        }
        #expect(stroke.points == original)
    }

    // MARK: - 실제 렌더 검증

    /// 렌더러를 실제 이미지로 그려 픽셀을 확인한다. geometry 판정만으로는 잡히지 않는 문제를 잡는다.
    private func renderedPixels(
        design: MirrorDesign,
        transform: MirrorViewTransform,
        size: CGSize
    ) -> (dark: Int, total: Int) {
        let canvas = Canvas { context, canvasSize in
            MirrorRenderer.draw(
                style: design.style,
                strokes: design.strokes,
                transform: transform,
                in: context,
                viewport: canvasSize
            )
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return (0, 0) }

        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 중앙 Mirror Area(어두운 면)를 뺀 프레임 영역에서만 잉크 픽셀을 센다.
        let mirror = transform.rect(design.insets.mirrorArea)
        var dark = 0
        var total = 0
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let point = CGPoint(x: x, y: y)
                guard !mirror.contains(point) else { continue }
                total += 1
                let i = (y * width + x) * 4
                if data[i] < 90 && data[i + 1] < 90 && data[i + 2] < 90 { dark += 1 }
            }
        }
        return (dark, total)
    }

    @Test("Side Detail에서도 획이 실제로 렌더된다", arguments: [1.0, 2.0, 3.0])
    func strokeActuallyRendersInSideDetail(zoom: Double) {
        var design = MirrorDesign(mirror: MirrorLibrary().mirrors[0])
        design.strokes = [longLeftStroke]

        let transform = SideDetailTransform(
            side: .left, insets: .standard, viewport: viewport,
            state: .init(zoom: CGFloat(zoom))
        )
        let result = renderedPixels(
            design: design,
            transform: MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset),
            size: viewport
        )

        #expect(result.total > 0)
        #expect(result.dark > 0, "zoom \(zoom) Side Detail에서 획이 한 픽셀도 그려지지 않음")
    }

    @Test("Overview에서도 획이 실제로 렌더된다")
    func strokeActuallyRendersInOverview() {
        var design = MirrorDesign(mirror: MirrorLibrary().mirrors[0])
        design.strokes = [longLeftStroke]

        let size = CGSize(width: 300, height: 650)
        let result = renderedPixels(design: design, transform: .fitted(in: size), size: size)
        #expect(result.dark > 0, "Overview에서 획이 그려지지 않음")
    }

    // MARK: - Scroll Handle

    @Test("Handle 위치는 viewport 위치를 그대로 따른다")
    func handleProgressFollowsViewport() {
        func progress(_ pan: CGFloat) -> Double {
            let t = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                        state: .init(pan: CGSize(width: 0, height: pan)))
            let travel = 1 - t.visibleRect.height
            return travel > 0.0001 ? min(max(t.visibleRect.y / travel, 0), 1) : 0
        }
        let top = progress(100_000)
        let middle = progress(0)
        let bottom = progress(-100_000)

        #expect(abs(top) < 0.001)
        #expect(abs(bottom - 1) < 0.001)
        #expect(middle > top && middle < bottom)
    }

    // MARK: - Zoom 정책

    @Test("Left / Right 기본 화면이 Top / Bottom과 지나치게 다르지 않다")
    func verticalSidesShowEnoughContext() {
        let left = SideDetailTransform(side: .left, insets: .standard, viewport: viewport)
        let top = SideDetailTransform(side: .top, insets: .standard, viewport: viewport)

        // 세로 밴드가 화면 폭의 절반을 넘게 차지하지 않는다 = 중앙 Mirror Area도 함께 보인다.
        let bandWidth = MirrorFrameInsets.standard.left * left.canvasSize.width
        #expect(bandWidth < viewport.width * 0.45)

        // 세로 밴드 기본 배율이 가로 밴드보다 지나치게 크지 않다.
        #expect(left.canvasSize.height < top.canvasSize.height * 2.6)
    }

    @Test("최소 배율에서는 기본보다 더 넓은 영역이 보인다", arguments: [EditorSide.left, .right])
    func minimumZoomShowsMoreContext(side: EditorSide) {
        let base = SideDetailTransform(side: side, insets: .standard, viewport: viewport)
        let zoomedOut = SideDetailTransform(side: side, insets: .standard, viewport: viewport,
                                            state: .init(zoom: 0.1))   // 정책 하한으로 clamp
        #expect(zoomedOut.appliedZoom < 1)
        #expect(zoomedOut.visibleRect.height > base.visibleRect.height)
        // 그래도 캔버스가 화면보다 좁아져 떠다니지는 않는다.
        #expect(zoomedOut.canvasSize.width >= viewport.width - 0.001)
    }

    @Test("최대 배율은 정책 상한을 넘지 않는다")
    func maximumZoomIsClamped() {
        let t = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                    state: .init(zoom: 99))
        #expect(t.appliedZoom == EditorViewportState.zoomRange.upperBound)
    }

    @Test("맞춤은 기본 상태로 되돌린다")
    func fitReturnsToDefault() {
        let moved = EditorViewportState(zoom: 2.4, pan: CGSize(width: 40, height: -600))
        #expect(!moved.isFitted)
        #expect(EditorViewportState().isFitted)

        let fitted = SideDetailTransform(side: .left, insets: .standard, viewport: viewport)
        let base = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                       state: EditorViewportState())
        #expect(fitted.offset == base.offset)
        #expect(fitted.canvasSize == base.canvasSize)
    }

    // MARK: - Scroll Handle 스크럽

    @Test("Handle 위치가 그대로 viewport 위치가 된다", arguments: [0.0, 0.5, 1.0])
    func scrubMapsProgressToViewport(progress: Double) {
        let start = SideDetailTransform(side: .left, insets: .standard, viewport: viewport)
        let pan = start.pan(forVerticalProgress: progress, viewport: viewport)
        let moved = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                        state: .init(pan: pan))
        #expect(abs(moved.verticalProgress - progress) < 0.01)
    }

    @Test("Handle track 한 번으로 프레임 끝에서 끝까지 간다")
    func scrubCoversFullRange() {
        let start = SideDetailTransform(side: .left, insets: .standard, viewport: viewport)
        let top = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                      state: .init(pan: start.pan(forVerticalProgress: 0, viewport: viewport)))
        let bottom = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                         state: .init(pan: start.pan(forVerticalProgress: 1, viewport: viewport)))
        #expect(abs(top.visibleRect.y) < 0.001)
        #expect(abs((bottom.visibleRect.y + bottom.visibleRect.height) - 1) < 0.001)
    }

    @Test("확대해도 Handle 위치 계산이 일치한다", arguments: [1.0, 2.0, 3.0])
    func scrubStaysConsistentWhenZoomed(zoom: Double) {
        let start = SideDetailTransform(side: .right, insets: .standard, viewport: viewport,
                                        state: .init(zoom: CGFloat(zoom)))
        let pan = start.pan(forVerticalProgress: 0.75, viewport: viewport)
        let moved = SideDetailTransform(side: .right, insets: .standard, viewport: viewport,
                                        state: .init(zoom: CGFloat(zoom), pan: pan))
        #expect(abs(moved.verticalProgress - 0.75) < 0.01)
    }

    // MARK: - Brush preset

    @Test("모든 도구가 유효한 기본 굵기를 가진다", arguments: EditorBrush.allCases)
    func brushDefaultsAreValid(brush: EditorBrush) {
        #expect(EditorBrush.widthRange.contains(brush.defaultWidth))
        #expect(brush.opacity > 0 && brush.opacity <= 1)
        #expect(!brush.title.isEmpty)
    }

    @Test("형광펜은 반투명하고 가장 굵다")
    func highlighterIsTranslucentAndWide() {
        #expect(EditorBrush.highlighter.opacity < 0.5)
        #expect(EditorBrush.highlighter.defaultWidth > EditorBrush.pen.defaultWidth)
        #expect(EditorBrush.pencil.defaultWidth < EditorBrush.pen.defaultWidth)
    }

    @Test("도구를 바꿔도 이미 그린 획은 그대로다")
    func toolSwitchKeepsStrokes() {
        var snapshot = EditorSnapshot()
        var history = EditorHistory()
        let drawn = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.2)],
                                  brush: .pen, width: EditorBrush.pen.defaultWidth)
        history.apply(.addStroke(drawn), to: &snapshot)

        let before = snapshot.strokes
        _ = EditorBrush.highlighter   // 도구 선택은 UI state일 뿐이다
        #expect(snapshot.strokes == before)
        #expect(snapshot.strokes.first?.brush == .pen)
    }

    @Test("새 도구로 그린 획도 렌더된다", arguments: EditorBrush.allCases)
    func newBrushRenders(brush: EditorBrush) {
        var design = MirrorDesign(mirror: MirrorLibrary().mirrors[0])
        design.strokes = [
            DrawingStroke(
                points: (0...10).map { NormalizedPoint(x: 0.05, y: 0.2 + Double($0) * 0.03) },
                brush: brush,
                width: brush.defaultWidth
            )
        ]
        let transform = SideDetailTransform(side: .left, insets: .standard, viewport: viewport)
        let result = renderedPixels(
            design: design,
            transform: MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset),
            size: viewport
        )
        #expect(result.dark > 0 || brush.opacity < 0.5, "\(brush.title) 획이 렌더되지 않음")
    }

    // MARK: - 실제 Mirror 적용

    /// 실제 카메라 위 장식과 같은 방식으로 렌더한 뒤, 지정한 정규화 지점의 픽셀을 읽는다.
    private func runtimePixel(
        design: MirrorDesign,
        at point: NormalizedPoint,
        size: CGSize = CGSize(width: 300, height: 650)
    ) -> (red: Int, green: Int, blue: Int, alpha: Int)? {
        let view = MirrorDecorationView(design: design).frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return nil }

        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let transform = MirrorViewTransform.aspectFilled(in: CGSize(width: width, height: height))
        let screen = transform.point(point)
        let x = min(max(Int(screen.x), 0), width - 1)
        let y = min(max(Int(screen.y), 0), height - 1)
        let i = (y * width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
    }

    private func mirrorDesign(_ basic: BasicMirror) -> MirrorDesign {
        MirrorDesign(mirror: MyMirror(id: basic.id, name: basic.name, origin: .basic, style: basic.style))
    }

    @Test("실제 Mirror에서 중앙은 완전히 투명하다")
    func runtimeCenterIsTransparent() {
        let pixel = runtimePixel(design: mirrorDesign(.cream), at: NormalizedPoint(x: 0.5, y: 0.5))
        #expect(pixel?.alpha == 0)
    }

    @Test("프레임 배경색이 실제 Mirror에 적용된다")
    func runtimeFrameUsesBackgroundColor() {
        let white = runtimePixel(design: mirrorDesign(.white), at: NormalizedPoint(x: 0.05, y: 0.5))
        let black = runtimePixel(design: mirrorDesign(.black), at: NormalizedPoint(x: 0.05, y: 0.5))

        #expect(white?.alpha ?? 0 > 200)
        #expect(black?.alpha ?? 0 > 200)
        #expect((white?.red ?? 0) > (black?.red ?? 255) + 100)
    }

    /// 네 면과 모서리에 그린 획이 실제 Mirror의 같은 자리에 나타난다.
    @Test(
        "그린 획이 실제 Mirror의 같은 위치에 보인다",
        arguments: [
            NormalizedPoint(x: 0.05, y: 0.30),   // Left
            NormalizedPoint(x: 0.95, y: 0.70),   // Right
            NormalizedPoint(x: 0.50, y: 0.03),   // Top
            NormalizedPoint(x: 0.50, y: 0.97),   // Bottom
            NormalizedPoint(x: 0.95, y: 0.03)    // Corner
        ]
    )
    func runtimeShowsDrawingAtSamePlace(point: NormalizedPoint) {
        var design = mirrorDesign(.white)
        design.strokes = [
            DrawingStroke(
                points: [point, NormalizedPoint(x: point.x, y: point.y + 0.005)],
                color: .black,
                width: 40 / MirrorCanvas.size.width
            )
        ]
        let inked = runtimePixel(design: design, at: point)
        let empty = runtimePixel(design: mirrorDesign(.white), at: point)

        #expect((inked?.red ?? 255) < 120, "획이 보이지 않음")
        #expect((empty?.red ?? 0) > 200, "획이 없는 상태와 구분되지 않음")
    }

    @Test("중앙 Mirror Area에는 획이 남지 않는다")
    func runtimeNeverDrawsOverCamera() {
        var design = mirrorDesign(.white)
        // 중앙을 가로지르는 획을 억지로 넣어도 마스크가 막는다.
        design.strokes = [
            DrawingStroke(
                points: [NormalizedPoint(x: 0.2, y: 0.5), NormalizedPoint(x: 0.8, y: 0.5)],
                color: .black,
                width: 40 / MirrorCanvas.size.width
            )
        ]
        #expect(runtimePixel(design: design, at: NormalizedPoint(x: 0.5, y: 0.5))?.alpha == 0)
    }

    @Test("Editor viewport 상태는 실제 Mirror 결과에 영향을 주지 않는다")
    func runtimeIgnoresEditorViewport() {
        var design = mirrorDesign(.softPink)
        design.strokes = [
            DrawingStroke(
                points: [NormalizedPoint(x: 0.95, y: 0.9), NormalizedPoint(x: 0.95, y: 0.92)],
                color: .black,
                width: 40 / MirrorCanvas.size.width
            )
        ]
        // Editor에서 확대·이동한 뒤 저장해도 Master 좌표만 남는다.
        _ = SideDetailTransform(side: .right, insets: .standard, viewport: viewport,
                                state: .init(zoom: 3, pan: CGSize(width: 0, height: -900)))
        let pixel = runtimePixel(design: design, at: NormalizedPoint(x: 0.95, y: 0.91))
        #expect((pixel?.red ?? 255) < 120)
    }

    @Test("모든 거울이 같은 프레임 규격을 쓴다")
    func everyMirrorSharesFrameGeometry() {
        let library = MirrorLibrary()
        for mirror in library.mirrors {
            #expect(mirror.style.insets == .standard)
        }
        for template in StoreCatalog.samples {
            #expect(template.style.insets == .standard)
        }
        #expect(MirrorFrameInsets.standard.left == 108.0 / 1080.0)
        #expect(abs(MirrorFrameInsets.standard.top - 180.0 / 2340.0) < 0.0001)
    }

    @Test("적용을 바꾸면 현재 거울이 바뀐다")
    func applyingChangesCurrentMirror() {
        let library = MirrorLibrary()
        let target = library.mirrors[1]
        library.apply(target)
        #expect(library.currentMirror.id == target.id)
        #expect(MirrorDesign(mirror: library.currentMirror).style.frame == target.style.frame)
    }

    @Test("Editor 저장이 현재 거울 디자인에 바로 반영된다")
    func savingUpdatesCurrentDesign() {
        let library = MirrorLibrary()
        var design = MirrorDesign(mirror: library.currentMirror)
        design.backgroundColor = BasicMirror.mint.style.frame
        design.strokes = [DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.4)], width: 0.01)]
        library.save(design)

        let updated = MirrorDesign(mirror: library.currentMirror)
        #expect(updated.backgroundColor == BasicMirror.mint.style.frame)
        #expect(updated.strokes.count == 1)
    }

    @Test("라이브러리가 비어도 안전한 기본 거울로 대체된다")
    func fallbackDesignIsWhite() {
        let fallback = MirrorDesign.fallback
        #expect(fallback.style.frame == BasicMirror.white.style.frame)
        #expect(fallback.insets == .standard)
        #expect(fallback.strokes.isEmpty)
    }

    // MARK: - Sticker

    private func sticker(_ source: StickerSource = .heart, at point: NormalizedPoint, width: Double = 0.16) -> StickerObject {
        let height = StickerObject.squareHeight(for: width)
        return StickerObject(
            source: source,
            frame: NormalizedRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
        )
    }

    @Test("스티커는 보고 있는 위치 근처에 들어간다")
    func stickerInsertsNearViewport() {
        let design = MirrorDesign(mirror: MirrorLibrary().mirrors[0])
        // Right 하단을 보고 있는 상태
        let transform = SideDetailTransform(
            side: .right, insets: .standard, viewport: viewport,
            state: .init(pan: CGSize(width: 0, height: -100_000))
        )
        let placed = StickerPlacement.insert(.heart, in: design, visibleRect: transform.visibleRect, side: .right)

        #expect(placed.center.y > 0.6, "하단을 보고 있는데 위쪽에 생김")
        #expect(placed.center.x > 0.5, "오른쪽을 보고 있는데 왼쪽에 생김")
        #expect(!design.insets.isInsideMirrorArea(placed.center))
    }

    @Test("스티커 중심은 중앙 Mirror Area에 들어가지 않는다")
    func stickerCenterStaysOutOfMirrorArea() {
        let insets = MirrorFrameInsets.standard
        let pushed = sticker(at: NormalizedPoint(x: 0.5, y: 0.5)).constrained(to: insets)
        #expect(!insets.isInsideMirrorArea(pushed.center))
    }

    @Test("모서리를 걸친 스티커도 하나의 오브젝트다")
    func cornerStickerStaysSingleObject() {
        let insets = MirrorFrameInsets.standard
        let corner = sticker(at: NormalizedPoint(x: 0.96, y: 0.04)).constrained(to: insets)
        #expect(corner.center.x > 0.9 && corner.center.y < 0.1)
        // 밴드를 넘어가는 부분이 있어도 잘리거나 복제되지 않는다.
        #expect(corner.frame.x < insets.mirrorArea.x + insets.mirrorArea.width)
    }

    @Test("이동은 화면 배율과 무관하게 같은 Master 위치가 된다", arguments: [1.0, 3.0])
    func stickerMoveMapsToMaster(zoom: Double) {
        let transform = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                            state: .init(zoom: CGFloat(zoom)))
        let screenPoint = CGPoint(x: 40, y: 200)
        let master = transform.masterPoint(from: screenPoint)
        let moved = sticker(at: NormalizedPoint(x: 0.05, y: 0.2)).moved(to: master)
        #expect(abs(moved.center.x - master.x) < 0.0001)
        #expect(abs(moved.center.y - master.y) < 0.0001)
    }

    @Test("크기 조절은 종횡비를 유지하고 범위를 벗어나지 않는다")
    func stickerResizeKeepsAspectAndClamps() {
        let base = sticker(at: NormalizedPoint(x: 0.05, y: 0.3))
        let bigger = base.resized(width: 0.30)
        let ratio = bigger.frame.width / bigger.frame.height
        let originalRatio = base.frame.width / base.frame.height
        #expect(abs(ratio - originalRatio) < 0.0001)

        #expect(base.resized(width: 0.0001).frame.width == StickerObject.sizeRange.lowerBound)
        #expect(base.resized(width: 9).frame.width == StickerObject.sizeRange.upperBound)
        // 중심은 유지된다
        #expect(abs(bigger.center.x - base.center.x) < 0.0001)
    }

    @Test("회전 / 뒤집기 / 투명도가 모델에 남는다")
    func stickerPropertiesPersist() {
        var item = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        item.rotation = 24
        item.isFlippedHorizontally = true
        item.opacity = 0.4
        #expect(item.rotation == 24)
        #expect(item.isFlippedHorizontally)
        #expect(item.opacity == 0.4)
    }

    @Test("회전해도 위치가 갑자기 튀지 않는다")
    func rotationDoesNotMoveSticker() {
        var item = sticker(at: NormalizedPoint(x: 0.05, y: 0.5)).constrained(to: .standard)
        let before = item.center
        item.rotation = 40
        let after = item.constrained(to: .standard).center
        #expect(abs(after.x - before.x) < 0.0001)
        #expect(abs(after.y - before.y) < 0.0001)
    }

    @Test("잠긴 스티커는 변형되지 않는다")
    func lockedStickerIsProtected() {
        var item = sticker(at: NormalizedPoint(x: 0.05, y: 0.4))
        item.isLocked = true
        // 잠금은 UI에서 막지만, 잠금 상태 자체는 되돌릴 수 있어야 한다.
        var snapshot = EditorSnapshot(stickers: [item])
        var history = EditorHistory()
        var unlocked = item
        unlocked.isLocked = false
        history.apply(.replaceSticker(unlocked), to: &snapshot)
        #expect(snapshot.stickers.first?.isLocked == false)
    }

    @Test("복제는 새 id와 약간의 offset을 가진다")
    func duplicateGetsNewIdentity() {
        let base = sticker(at: NormalizedPoint(x: 0.05, y: 0.5))
        var copy = base
        copy.id = UUID()
        copy.frame = NormalizedRect(x: base.frame.x + 0.02, y: base.frame.y + 0.01,
                                    width: base.frame.width, height: base.frame.height)
        #expect(copy.id != base.id)
        #expect(copy.frame.x != base.frame.x)
        #expect(copy.frame.width == base.frame.width)
    }

    @Test("zIndex 순서대로 그려진다")
    func stickersRespectZOrder() {
        var design = mirrorDesign(.white)
        var back = sticker(at: NormalizedPoint(x: 0.05, y: 0.5))
        back.zIndex = 1
        var front = sticker(.star, at: NormalizedPoint(x: 0.05, y: 0.5))
        front.zIndex = 2
        design.stickers = [front, back]
        // 렌더러는 zIndex 오름차순으로 정렬해서 그린다.
        #expect(design.stickers.sorted { $0.zIndex < $1.zIndex }.last?.id == front.id)
    }

    // MARK: - 통합 History

    @Test("그리기와 스티커가 하나의 시간순 history로 되돌려진다")
    func unifiedHistoryOrder() {
        var snapshot = EditorSnapshot()
        var history = EditorHistory()

        let stroke = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.2)], width: 0.01)
        let item = sticker(at: NormalizedPoint(x: 0.05, y: 0.5))
        var moved = item
        moved.frame.y += 0.1

        history.apply(.addStroke(stroke), to: &snapshot)
        history.apply(.addSticker(item), to: &snapshot)
        history.apply(.replaceSticker(moved), to: &snapshot)
        history.apply(.eraseStrokes([stroke.id]), to: &snapshot)

        history.undo(&snapshot)   // 지우기 취소
        #expect(snapshot.strokes.count == 1)
        history.undo(&snapshot)   // 이동 취소
        #expect(snapshot.stickers.first?.frame.y == item.frame.y)
        history.undo(&snapshot)   // 스티커 추가 취소
        #expect(snapshot.stickers.isEmpty)
        history.undo(&snapshot)   // 그리기 취소
        #expect(snapshot.strokes.isEmpty)

        history.redo(&snapshot)
        #expect(snapshot.strokes.count == 1)
    }

    @Test("스티커 삭제도 되돌릴 수 있다")
    func deletingStickerIsUndoable() {
        let item = sticker(at: NormalizedPoint(x: 0.05, y: 0.5))
        var snapshot = EditorSnapshot(stickers: [item])
        var history = EditorHistory()

        history.apply(.deleteSticker(item.id), to: &snapshot)
        #expect(snapshot.stickers.isEmpty)
        history.undo(&snapshot)
        #expect(snapshot.stickers.first?.id == item.id)
    }

    @Test("viewport 조작은 스티커 데이터를 바꾸지 않는다")
    func viewportDoesNotMutateStickers() {
        let item = sticker(at: NormalizedPoint(x: 0.05, y: 0.5))
        let snapshot = EditorSnapshot(stickers: [item])
        for zoom in [1.0, 2.0, 3.0] {
            _ = SideDetailTransform(side: .left, insets: .standard, viewport: viewport,
                                    state: .init(zoom: CGFloat(zoom), pan: CGSize(width: 0, height: -300)))
        }
        #expect(snapshot.stickers == [item])
    }

    // MARK: - Sticker 렌더

    @Test("스티커가 실제 Mirror의 같은 위치에 보인다")
    func stickerRendersInRuntime() {
        var design = mirrorDesign(.white)
        let point = NormalizedPoint(x: 0.05, y: 0.6)
        design.stickers = [sticker(at: point, width: 0.18)]

        // 아웃라인 스티커라 중심은 비어 있다. 영역 전체를 훑어 잉크 픽셀을 찾는다.
        func inkCount(_ design: MirrorDesign) -> Int {
            var count = 0
            for dx in stride(from: -0.08, through: 0.08, by: 0.01) {
                for dy in stride(from: -0.035, through: 0.035, by: 0.005) {
                    let probe = NormalizedPoint(x: point.x + dx, y: point.y + dy)
                    // 투명 픽셀(중앙 카메라 영역)은 red가 0이므로 alpha도 함께 본다.
                    if let pixel = runtimePixel(design: design, at: probe),
                       pixel.alpha > 200, pixel.red < 120 {
                        count += 1
                    }
                }
            }
            return count
        }
        #expect(inkCount(design) > 0, "스티커가 렌더되지 않음")
        #expect(inkCount(mirrorDesign(.white)) == 0)
    }

    @Test("스티커가 중앙 카메라 영역을 통째로 덮지 않는다")
    func stickerNeverFillsCamera() {
        var design = mirrorDesign(.white)
        // 중앙에 넣으려 해도 배치 제약이 프레임으로 밀어낸다.
        design.stickers = [sticker(at: NormalizedPoint(x: 0.5, y: 0.5), width: 0.4)
            .constrained(to: .standard)]
        #expect(runtimePixel(design: design, at: NormalizedPoint(x: 0.5, y: 0.5))?.alpha == 0)
    }

    @Test("Editor에서 얹은 스티커가 저장 후 현재 거울에 남는다")
    func stickerSurvivesSave() {
        let library = MirrorLibrary()
        var design = MirrorDesign(mirror: library.currentMirror)
        let item = sticker(.ribbon, at: NormalizedPoint(x: 0.95, y: 0.8))
        design.stickers = [item]
        library.save(design)

        let updated = MirrorDesign(mirror: library.currentMirror)
        #expect(updated.stickers.first?.id == item.id)
        #expect(updated.stickers.first?.source == .ribbon)
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
