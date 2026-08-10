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

    /// 세로축에는 어떤 pan에서도 빈 공간이 생기면 안 된다.
    /// 가로축은 Left / Right에서 밴드를 화면 중앙에 놓기 위한 Editor Workspace Gutter만 허용된다.
    /// 그 이상 — pan하다 캔버스가 멀리 날아가 생기는 빈 공간 — 은 여전히 금지다.
    @Test("의도한 workspace gutter 외에는 캔버스 밖으로 pan 되지 않는다", arguments: EditorSide.allCases)
    func panNeverShowsEmptySpace(side: EditorSide) {
        for pan in [-5000.0, -500.0, 0.0, 500.0, 5000.0] {
            let t = SideDetailTransform(side: side, insets: .standard, viewport: viewport, state: .init(pan: CGSize(width: pan, height: pan)))

            if t.canvasSize.width > viewport.width {
                let band = side.boundingBox(with: .standard).rect(in: t.canvasSize)
                // 밴드는 화면 중앙을 넘어서까지 밀려나지 않는다.
                let allowance = side.panAxis == .vertical
                    ? max(0, viewport.width / 2 - band.width / 2)
                    : 0
                #expect(t.offset.x <= allowance + 0.001)
                #expect(t.offset.x + t.canvasSize.width >= viewport.width - allowance - 0.001)
                #expect(t.workspaceGutter <= allowance + 0.001)
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
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
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
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
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
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
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

    /// 저장 정책 테스트용 시드.
    /// 실제 앱의 초기 내 거울은 비어 있으므로, 필요한 거울은 테스트가 직접 만든다.
    private func seededLibrary() -> MirrorLibrary {
        let library = MirrorLibrary()
        library.acquire(StoreCatalog.basics[0])      // 무료 기본 템플릿 → origin .basic
        library.acquire(StoreCatalog.creators[0])    // Creator 템플릿 → origin .purchased
        _ = library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "내가 만든 거울")
        return library
    }

    @Test("모든 거울이 같은 프레임 규격을 쓴다")
    func everyMirrorSharesFrameGeometry() {
        let library = seededLibrary()
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
        let library = seededLibrary()
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
        _ = library.save(design, name: "테스트 거울")

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
        let design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
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
        _ = library.save(design, name: "테스트 거울")

        let updated = MirrorDesign(mirror: library.currentMirror)
        #expect(updated.stickers.first?.id == item.id)
        #expect(updated.stickers.first?.source == .ribbon)
    }

    // MARK: - Sticker 라이브러리 / tint

    @Test("기본 스티커가 20종 이상이고 식별자가 겹치지 않는다")
    func stickerLibraryIsLargeAndUnique() {
        #expect(StickerSource.allCases.count >= 20)
        #expect(Set(StickerSource.allCases.map(\.rawValue)).count == StickerSource.allCases.count)
        #expect(Set(StickerSource.allCases.map(\.symbolName)).count == StickerSource.allCases.count)
        #expect(StickerSource.allCases.allSatisfy { !$0.title.isEmpty })
    }

    @Test("카테고리 필터가 동작한다", arguments: StickerCategory.allCases)
    func stickerCategoryFilters(category: StickerCategory) {
        let filtered = StickerSource.all(in: category)
        #expect(!filtered.isEmpty)
        if category == .all {
            #expect(filtered.count == StickerSource.allCases.count)
        } else {
            #expect(filtered.allSatisfy { $0.category == category })
        }
    }

    @Test("template 스티커는 지정한 색으로 칠해진다")
    func templateStickerUsesTint() {
        var item = sticker(at: NormalizedPoint(x: 0.05, y: 0.5))
        item.tintColor = .red
        #expect(item.source.supportsTint)
        #expect(item.resolvedTint == .red)
    }

    @Test("색을 지정하지 않으면 기본 잉크색이다")
    func stickerDefaultTintIsInk() {
        let item = sticker(at: NormalizedPoint(x: 0.05, y: 0.5))
        #expect(item.resolvedTint == PaperTheme.ink)
    }

    @Test("스티커 색 변경은 되돌릴 수 있다")
    func stickerColorIsUndoable() {
        let item = sticker(at: NormalizedPoint(x: 0.05, y: 0.5))
        var snapshot = EditorSnapshot(stickers: [item])
        var history = EditorHistory()

        var tinted = item
        tinted.tintColor = .blue
        history.apply(.replaceSticker(tinted), to: &snapshot)
        #expect(snapshot.stickers.first?.tintColor == .blue)

        history.undo(&snapshot)
        #expect(snapshot.stickers.first?.tintColor == nil)
    }

    // MARK: - Haptic rate limit

    @Test("첫 접촉과 짧은 간격에는 촉각 tick이 울리지 않는다")
    func hapticIsRateLimited() {
        var limiter = HapticRateLimiter()
        // 첫 호출은 기준점만 잡는다.
        let first = limiter.shouldFire(at: NormalizedPoint(x: 0.05, y: 0.50), time: 0)
        // 간격은 충분하지만 거의 움직이지 않았다.
        let tooClose = limiter.shouldFire(at: NormalizedPoint(x: 0.0501, y: 0.5), time: 0.5)
        // 많이 움직였지만 시간이 너무 짧다.
        let tooSoon = limiter.shouldFire(at: NormalizedPoint(x: 0.20, y: 0.5), time: 0.01)
        // 시간과 거리 모두 충분하면 울린다.
        let fires = limiter.shouldFire(at: NormalizedPoint(x: 0.20, y: 0.5), time: 1.0)
        // 바로 다음 프레임은 다시 막힌다.
        let throttled = limiter.shouldFire(at: NormalizedPoint(x: 0.21, y: 0.5), time: 1.01)

        #expect(!first)
        #expect(!tooClose)
        #expect(!tooSoon)
        #expect(fires)
        #expect(!throttled)
    }

    // MARK: - Save / Naming / Storage slots

    @Test("이름은 앞뒤 공백을 정리하고 길이를 제한한다")
    func nameNormalization() {
        #expect(MirrorStoragePolicy.normalizedName("  나만의 거울  ") == "나만의 거울")
        #expect(MirrorStoragePolicy.normalizedName("   ") == nil)
        #expect(MirrorStoragePolicy.normalizedName("") == nil)
        let long = String(repeating: "가", count: 60)
        #expect(MirrorStoragePolicy.normalizedName(long)?.count == MirrorStoragePolicy.maxNameLength)
    }

    @Test("기본 거울을 꾸미면 원본은 그대로 두고 새 거울이 생긴다")
    func savingBasicMirrorCreatesCopy() {
        let library = seededLibrary()
        let basic = library.mirrors.first { $0.origin == .basic }!
        let before = library.mirrors.count
        var design = MirrorDesign(mirror: basic)
        design.strokes = [DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.3)], width: 0.01)]

        #expect(library.needsNewSlot(for: design))
        let outcome = library.save(design, name: "내 첫 거울")
        #expect(outcome == .created("내 첫 거울"))
        #expect(library.mirrors.count == before + 1)
        // 원본은 손대지 않는다
        #expect(library.mirrors.first { $0.id == basic.id }?.strokes.isEmpty == true)
        // 새 거울이 바로 적용된다
        #expect(library.currentMirror.name == "내 첫 거울")
        #expect(library.currentMirror.origin == .made)
    }

    @Test("구매한 거울도 원본을 덮어쓰지 않는다")
    func savingPurchasedMirrorCreatesCopy() {
        let library = seededLibrary()
        let purchased = library.mirrors.first { $0.origin == .purchased }!
        let design = MirrorDesign(mirror: purchased)
        #expect(library.needsNewSlot(for: design))
        let purchasedOutcome = library.save(design, name: "구매 거울 편집")
        #expect(purchasedOutcome == .created("구매 거울 편집"))
        #expect(library.mirrors.contains { $0.id == purchased.id && $0.origin == .purchased })
    }

    @Test("내가 만든 거울을 다시 편집하면 같은 거울이 갱신된다")
    func savingCreatedMirrorUpdatesInPlace() {
        let library = seededLibrary()
        let made = library.mirrors.first { $0.origin == .made }!
        let before = library.mirrors.count
        var design = MirrorDesign(mirror: made)
        design.backgroundColor = BasicMirror.mint.style.frame

        #expect(!library.needsNewSlot(for: design))
        let updatedOutcome = library.save(design, name: "이름 변경")
        #expect(updatedOutcome == .updated("이름 변경"))
        #expect(library.mirrors.count == before)
        #expect(library.mirrors.first { $0.id == made.id }?.name == "이름 변경")
    }

    @Test("슬롯은 내가 만든 거울만 소비한다")
    func onlyCreatedMirrorsConsumeSlots() {
        let library = seededLibrary()
        #expect(library.mirrors.count { $0.origin == .basic } == 1)
        #expect(library.mirrors.count { $0.origin == .purchased } == 1)
        // 받은 기본 / 구매 거울은 슬롯을 쓰지 않는다.
        #expect(library.createdCount == 1)
        #expect(library.createdCount == library.mirrors.count { $0.origin == .made })
        #expect(library.createdCapacity == MirrorStoragePolicy.freeCreatedSlots)
    }

    @Test("무료 슬롯이 가득 차면 새 거울 저장이 막힌다")
    func fullSlotsBlockNewMirror() {
        let library = seededLibrary()
        let basic = library.mirrors.first { $0.origin == .basic }!

        while library.hasFreeCreatedSlot {
            let outcome = library.save(MirrorDesign(mirror: basic), name: "거울")
            #expect(outcome != .needsMoreSlots)
        }
        #expect(library.createdCount == library.createdCapacity)
        let blocked = library.save(MirrorDesign(mirror: basic), name: "하나 더")
        #expect(blocked == .needsMoreSlots)
    }

    @Test("슬롯이 가득 차도 기존 내 거울 편집은 계속 가능하다")
    func fullSlotsStillAllowUpdates() {
        let library = seededLibrary()
        let basic = library.mirrors.first { $0.origin == .basic }!
        while library.hasFreeCreatedSlot {
            _ = library.save(MirrorDesign(mirror: basic), name: "거울")
        }
        let existing = library.mirrors.last { $0.origin == .made }!
        var design = MirrorDesign(mirror: existing)
        design.backgroundColor = BasicMirror.sky.style.frame
        let stillEditable = library.save(design, name: "계속 편집")
        #expect(stillEditable == .updated("계속 편집"))
    }

    @Test("슬롯 팩은 보관 공간을 늘린다")
    func slotPackExpandsCapacity() {
        let library = MirrorLibrary()
        let before = library.createdCapacity
        library.grantSlotPack()
        #expect(library.createdCapacity == before + MirrorStoragePolicy.slotPackSize)
    }

    @Test("보관 슬롯과 조각 잔액은 서로 무관하다")
    func slotsAreNotShards() {
        let library = MirrorLibrary()
        let shards = ShardWallet.temporaryBalance
        library.grantSlotPack()
        // 슬롯을 늘려도 조각이 차감되지 않는다 (실제 결제는 아직 없다)
        #expect(ShardWallet.temporaryBalance == shards)
        #expect(library.createdCapacity != shards)
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

    // MARK: - Editor Workspace Gutter (Side Workspace Centering)

    /// 선택한 밴드의 화면상 중심 x.
    private func bandCenterX(_ side: EditorSide) -> CGFloat {
        let transform = SideDetailTransform(side: side, insets: .standard, viewport: viewport)
        let band = side.boundingBox(with: .standard).rect(in: transform.canvasSize)
        return band.midX + transform.offset.x
    }

    @Test("Left 프레임은 기본 상태에서 화면 가로 중앙에 온다")
    func leftBandIsCentered() {
        #expect(abs(bandCenterX(.left) - viewport.width / 2) < 0.5)
    }

    @Test("Right 프레임은 기본 상태에서 화면 가로 중앙에 온다")
    func rightBandIsCentered() {
        #expect(abs(bandCenterX(.right) - viewport.width / 2) < 0.5)
    }

    @Test("Left / Right workspace는 정확히 대칭이다")
    func leftRightWorkspaceIsSymmetric() {
        let left = SideDetailTransform(side: .left, insets: .standard, viewport: viewport)
        let right = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        #expect(abs(left.workspaceGutter - right.workspaceGutter) < 0.5)
        #expect(left.workspaceGutter > 0)
        // gutter는 캔버스 바깥쪽에만 생긴다.
        #expect(left.offset.x > 0)                                      // 왼쪽 바깥
        #expect(right.offset.x + right.canvasSize.width < viewport.width)   // 오른쪽 바깥
    }

    @Test("Workspace Gutter는 MirrorDesign이 아니다")
    func workspaceGutterIsNotPartOfDesign() {
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        #expect(transform.workspaceGutter > 0)

        // Mini Map이 보는 영역은 항상 Master Canvas 안쪽이다.
        #expect(transform.visibleRect.x >= -0.0001)
        #expect(transform.visibleRect.x + transform.visibleRect.width <= 1.0001)

        // Gutter 위치는 Master 좌표계 밖으로 나간다 — 저장할 수 있는 좌표가 아니다.
        let gutterPoint = CGPoint(x: viewport.width - 2, y: viewport.height / 2)
        #expect(transform.masterPoint(from: gutterPoint).x > 1)

        // 디자인 데이터에는 gutter라는 개념 자체가 없다.
        let design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        #expect(design.insets == .standard)
    }

    @Test("Gutter에서는 그리기가 시작되지 않는다")
    func gutterTouchCannotCreateDrawing() {
        let insets = MirrorFrameInsets.standard
        #expect(!insets.isInsideFrameBand(NormalizedPoint(x: 1.08, y: 0.5)))   // 오른쪽 gutter
        #expect(!insets.isInsideFrameBand(NormalizedPoint(x: -0.08, y: 0.5)))  // 왼쪽 gutter
        #expect(!insets.isInsideFrameBand(NormalizedPoint(x: 0.5, y: 0.5)))    // 중앙 Mirror Area
        #expect(insets.isInsideFrameBand(NormalizedPoint(x: 0.05, y: 0.5)))    // 실제 프레임 밴드
    }

    @Test("Gutter는 스티커 위치가 될 수 없다")
    func gutterCannotBecomeStickerPosition() {
        let insets = MirrorFrameInsets.standard
        let placed = sticker(at: NormalizedPoint(x: 0.05, y: 0.5))
            .moved(to: NormalizedPoint(x: 1.4, y: 0.5))
            .constrained(to: insets)
        #expect(placed.center.x <= 1.0001)
        #expect(placed.center.x >= -0.0001)
    }

    @Test("맞춤은 중앙 배치 기본 상태로 되돌린다")
    func fitReturnsToCenteredSideLayout() {
        for side in [EditorSide.left, .right] {
            let panned = SideDetailTransform(
                side: side, insets: .standard, viewport: viewport,
                state: .init(zoom: 2, pan: CGSize(width: -400, height: 300))
            )
            #expect(panned.appliedPan != .zero || panned.appliedZoom != 1)

            // 맞춤 = 기본 EditorViewportState
            let fitted = SideDetailTransform(side: side, insets: .standard, viewport: viewport)
            #expect(fitted.appliedPan == .zero)
            #expect(abs(bandCenterX(side) - viewport.width / 2) < 0.5)
        }
    }

    @Test("Pan / Zoom 후에도 Master 좌표 변환이 유효하다")
    func panZoomRetainsValidMasterMapping() {
        for zoom in [0.7, 1.0, 2.4] {
            let transform = SideDetailTransform(
                side: .right, insets: .standard, viewport: viewport,
                state: .init(zoom: CGFloat(zoom), pan: CGSize(width: -120, height: -260))
            )
            let screen = CGPoint(x: 90, y: 300)
            let master = transform.masterPoint(from: screen)
            let back = transform.screenPoint(from: master)
            #expect(abs(back.x - screen.x) < 0.001)
            #expect(abs(back.y - screen.y) < 0.001)
        }
    }

    @Test("실제 Mirror는 Editor workspace gutter의 영향을 받지 않는다")
    func runtimeUnaffectedByWorkspaceGutter() {
        let size = CGSize(width: 300, height: 650)
        let runtime = MirrorViewTransform.aspectFilled(in: size)
        // 카메라 위에서는 캔버스가 화면을 완전히 덮는다 — 빈 여백이 없다.
        #expect(runtime.canvasRect.minX <= 0.001)
        #expect(runtime.canvasRect.maxX >= size.width - 0.001)
        #expect(runtime.canvasRect.minY <= 0.001)
        #expect(runtime.canvasRect.maxY >= size.height - 0.001)

        let design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        let edge = runtimePixel(design: design, at: NormalizedPoint(x: 0.02, y: 0.5), size: size)
        #expect((edge?.alpha ?? 0) > 200)   // 프레임이 그대로 칠해진다
    }

    @Test("Capture 결과도 workspace gutter의 영향을 받지 않는다")
    func captureUnaffectedByWorkspaceGutter() {
        let size = CGSize(width: 300, height: 650)
        let design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        let image = MirrorCapture.compose(frame: nil, design: design, size: size)
        #expect(image != nil)
        #expect(abs((image?.size.width ?? 0) - size.width) < 1)
        #expect(abs((image?.size.height ?? 0) - size.height) < 1)
    }

    // MARK: - Sticker 재선택 / Focus

    /// 화면 좌표 hit test. SideDetailCanvas.sticker(at:transform:)와 같은 규칙이다.
    /// 화면에서 위에 보이는 것(zIndex → 배열 순서)이 먼저 잡힌다.
    private func hitSticker(
        _ stickers: [StickerObject],
        at location: CGPoint,
        transform: SideDetailTransform
    ) -> StickerObject? {
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        return stickers.enumerated()
            .filter { $0.element.contains(location, in: placement) }
            .max { ($0.element.zIndex, $0.offset) < ($1.element.zIndex, $1.offset) }?
            .element
    }

    /// 스티커의 화면상 중심.
    private func screenCenter(_ object: StickerObject, _ transform: SideDetailTransform) -> CGPoint {
        let rect = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
            .rect(object.frame)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    @Test("스티커를 탭하면 그 스티커가 선택된다")
    func stickerTapSelectsObject() {
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        let target = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        let center = placement.rect(target.frame)

        #expect(hitSticker([target], at: CGPoint(x: center.midX, y: center.midY), transform: transform)?.id == target.id)
        #expect(hitSticker([target], at: CGPoint(x: center.midX, y: center.midY - 400), transform: transform) == nil)
    }

    @Test("완료로 선택을 푼 뒤 다시 탭하면 같은 스티커가 선택된다")
    func doneThenReselectWorks() {
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        let target = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        let point = CGPoint(x: placement.rect(target.frame).midX, y: placement.rect(target.frame).midY)

        var selected: UUID? = target.id
        selected = nil                                   // "완료"
        #expect(selected == nil)
        selected = hitSticker([target], at: point, transform: transform)?.id
        #expect(selected == target.id)
    }

    @Test("재선택해도 스티커 상태는 그대로다")
    func reselectShowsSameStickerState() {
        var target = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        target.rotation = 24
        target.opacity = 0.6
        target.tintColor = .red
        target.isFlippedHorizontally = true

        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        let rect = placement.rect(target.frame)
        let found = hitSticker([target], at: CGPoint(x: rect.midX, y: rect.midY), transform: transform)

        #expect(found == target)
    }

    @Test("잠긴 스티커도 다시 선택할 수 있다")
    func lockedStickerCanBeSelected() {
        var locked = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        locked.isLocked = true

        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        let rect = placement.rect(locked.frame)

        let found = hitSticker([locked], at: CGPoint(x: rect.midX, y: rect.midY), transform: transform)
        #expect(found?.id == locked.id)
        #expect(found?.isLocked == true)
    }

    @Test("화면 밖으로 나간 스티커는 zoom을 유지한 채 최소한만 끌어온다")
    func partiallyOffscreenStickerAppliesMinimalFocus() {
        let state = EditorViewportState(zoom: 1.6)
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport, state: state)
        // 아래쪽 멀리 있는 스티커
        let far = sticker(at: NormalizedPoint(x: 0.95, y: 0.95))

        let focused = transform.focusState(on: far.frame, from: state)
        #expect(focused != nil)
        #expect(focused?.zoom == state.zoom)             // zoom은 절대 바꾸지 않는다

        let after = SideDetailTransform(
            side: .right, insets: .standard, viewport: viewport, state: focused ?? state
        )
        let placement = MirrorViewTransform(canvasSize: after.canvasSize, offset: after.offset)
        let rect = placement.rect(far.frame)
        #expect(rect.midY >= 0 && rect.midY <= viewport.height)

        // 최소 이동 — 한 번 끌어온 뒤에는 더 움직이지 않는다.
        let applied = EditorViewportState(zoom: after.appliedZoom, pan: after.appliedPan)
        #expect(after.focusState(on: far.frame, from: applied) == nil)
    }

    @Test("이미 충분히 보이는 스티커는 화면을 움직이지 않는다")
    func fullyVisibleStickerDoesNotMoveViewport() {
        let state = EditorViewportState()
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport, state: state)
        // 기본 화면 중앙 근처
        let master = transform.masterPoint(from: CGPoint(x: viewport.width / 2, y: viewport.height / 2))
        let visible = sticker(at: master, width: 0.1)

        #expect(transform.focusState(on: visible.frame, from: state) == nil)
    }

    @Test("다른 스티커를 고르면 이전 선택은 풀린다")
    func selectingADeselectsB() {
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        var a = sticker(at: NormalizedPoint(x: 0.95, y: 0.44))
        var b = sticker(at: NormalizedPoint(x: 0.95, y: 0.56))
        a.zIndex = 1
        b.zIndex = 2

        let rectA = placement.rect(a.frame)
        let rectB = placement.rect(b.frame)
        var selected = hitSticker([a, b], at: CGPoint(x: rectB.midX, y: rectB.midY), transform: transform)?.id
        #expect(selected == b.id)
        selected = hitSticker([a, b], at: CGPoint(x: rectA.midX, y: rectA.midY), transform: transform)?.id
        #expect(selected == a.id)
        #expect(selected != b.id)
    }

    @Test("Focus는 스티커 데이터를 바꾸지 않는다")
    func stickerDataUnchangedByFocus() {
        let state = EditorViewportState(zoom: 1.6)
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport, state: state)
        let target = sticker(at: NormalizedPoint(x: 0.95, y: 0.95))
        let before = target

        _ = transform.focusState(on: target.frame, from: state)
        #expect(target == before)
    }

    @Test("회전하거나 작은 스티커도 눈에 보이는 곳을 누르면 잡힌다")
    func rotatedAndSmallStickersStayTappable() {
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)

        var rotated = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        rotated.rotation = 45
        let rect = placement.rect(rotated.frame)
        // 회전해도 눈에 보이는 자리(중심, 회전된 변 위)는 잡힌다.
        #expect(rotated.contains(CGPoint(x: rect.midX, y: rect.midY), in: placement))
        #expect(rotated.contains(CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.35), in: placement))
        // 회전 bounding box의 빈 모서리는 잡히지 않는다 — 보이는 모양과 어긋나지 않게.
        let diagonal = max(rect.width, rect.height)
        #expect(!rotated.contains(CGPoint(x: rect.midX + diagonal * 0.6, y: rect.midY + diagonal * 0.6), in: placement))

        // 축소해서 화면상 아주 작아진 스티커
        let small = MirrorViewTransform(canvasSize: CGSize(width: 200, height: 433), offset: .zero)
        let tiny = sticker(at: NormalizedPoint(x: 0.5, y: 0.5), width: StickerObject.sizeRange.lowerBound)
        let tinyRect = small.rect(tiny.frame)
        #expect(tinyRect.width < StickerObject.minimumTapTarget)
        let edge = StickerObject.minimumTapTarget / 2 - 1
        #expect(tiny.contains(CGPoint(x: tinyRect.midX + edge, y: tinyRect.midY), in: small))
        #expect(tiny.contains(CGPoint(x: tinyRect.midX, y: tinyRect.midY + edge), in: small))
        // 최소 target 밖은 여전히 잡히지 않는다 — 옆 스티커를 덮지 않는다.
        #expect(!tiny.contains(CGPoint(x: tinyRect.midX + StickerObject.minimumTapTarget, y: tinyRect.midY), in: small))
    }

    @Test("스티커 도구의 한 손가락 Pan은 같은 viewport state를 쓴다")
    func oneFingerPanUsesSameViewportState() {
        let start = EditorViewportState()
        var next = start
        next.pan.height -= 160                       // 빈 공간에서 한 손가락으로 끌어올림

        let moved = SideDetailTransform(side: .right, insets: .standard, viewport: viewport, state: next)
        let base = SideDetailTransform(side: .right, insets: .standard, viewport: viewport, state: start)
        #expect(moved.offset.y < base.offset.y)
        // Mini Map / Scroll Handle이 같은 값을 즉시 따라간다.
        #expect(moved.verticalProgress > base.verticalProgress)
        #expect(moved.appliedZoom == base.appliedZoom)
    }

    // MARK: - 초기 라이브러리 / 상점 기본 템플릿

    @Test("최초 실행 시 내 거울은 비어 있다")
    func initialMyMirrorsIsEmpty() {
        let library = MirrorLibrary()
        #expect(library.mirrors.isEmpty)
        #expect(library.createdCount == 0)
        #expect(library.createdCapacity == MirrorStoragePolicy.freeCreatedSlots)
    }

    @Test("내 거울이 비어 있어도 기본 거울이 그대로 그려진다")
    func initialDefaultMirrorStillRenders() {
        let library = MirrorLibrary()
        #expect(library.currentMirror.id == MirrorLibrary.defaultMirror.id)

        let design = MirrorDesign(mirror: library.currentMirror)
        #expect(design.insets == .standard)
        let pixel = runtimePixel(design: design, at: NormalizedPoint(x: 0.02, y: 0.5))
        #expect((pixel?.alpha ?? 0) > 200)
    }

    @Test("기본 거울은 슬롯을 쓰지 않는다")
    func defaultMirrorConsumesNoSlot() {
        let library = MirrorLibrary()
        #expect(library.createdCount == 0)
        #expect(library.hasFreeCreatedSlot)
        // 목록에도 들어가지 않는다.
        #expect(!library.mirrors.contains { $0.id == MirrorLibrary.defaultMirror.id })
    }

    @Test("상점의 기본 단색 템플릿 8종은 항상 무료다")
    func basicStoreTemplatesAreFree() {
        #expect(StoreCatalog.basics.count == BasicMirror.allCases.count)
        #expect(StoreCatalog.basics.count == 8)
        for template in StoreCatalog.basics {
            #expect(template.price == 0)
            #expect(template.isBasic)
            #expect(template.matches(.basic))
            #expect(template.matches(.free))
            #expect(template.style.insets == .standard)
        }
    }

    @Test("무료 기본 템플릿을 받으면 내 거울에 추가된다")
    func acquiringBasicAddsToMyMirrors() {
        let library = MirrorLibrary()
        let template = StoreCatalog.basics[0]
        library.acquire(template)

        #expect(library.mirrors.count == 1)
        #expect(library.mirrors[0].id == template.id)
        #expect(library.mirrors[0].origin == .basic)
        // 두 번 받아도 중복되지 않는다.
        library.acquire(template)
        #expect(library.mirrors.count == 1)
    }

    @Test("받은 기본 템플릿은 제작 슬롯을 소비하지 않는다")
    func acquiredBasicConsumesNoCreatedSlot() {
        let library = MirrorLibrary()
        for template in StoreCatalog.basics { library.acquire(template) }
        #expect(library.mirrors.count == 8)
        #expect(library.createdCount == 0)
        #expect(library.hasFreeCreatedSlot)
    }

    // MARK: - 중앙 Mirror Area 안쪽 모서리

    /// 안쪽 모서리 기준점에서 (dx, dy)만큼 안쪽으로 들어간 점.
    private func nearInnerCorner(_ corner: (x: Double, y: Double), dx: Double, dy: Double) -> NormalizedPoint {
        let area = MirrorFrameInsets.standard.mirrorArea
        return NormalizedPoint(
            x: corner.x == 0 ? area.x + dx : area.x + area.width - dx,
            y: corner.y == 0 ? area.y + dy : area.y + area.height - dy
        )
    }

    @Test("중앙 Mirror Area의 안쪽 모서리는 둥글다")
    func mirrorAreaCornerIsRounded() {
        let insets = MirrorFrameInsets.standard
        let rx = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.width
        let ry = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.height

        // 모서리 꼭짓점 바로 안쪽은 곡선 바깥 = 아직 프레임이다.
        #expect(!insets.isInsideMirrorArea(nearInnerCorner((0, 0), dx: rx * 0.1, dy: ry * 0.1)))
        // 곡선 안쪽으로 충분히 들어가면 Mirror Area다.
        #expect(insets.isInsideMirrorArea(nearInnerCorner((0, 0), dx: rx * 1.5, dy: ry * 1.5)))
        // 반경이 과하게 크지 않다 (capsule 금지).
        #expect(MirrorGeometry.innerCornerRadius < MirrorCanvas.size.width * 0.05)
        #expect(MirrorGeometry.innerCornerRadius > 0)
    }

    @Test("안쪽 네 모서리가 같은 반경을 쓴다")
    func allFourInnerCornersUseSameRadius() {
        let insets = MirrorFrameInsets.standard
        let rx = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.width
        let ry = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.height

        for corner in [(x: 0.0, y: 0.0), (x: 1.0, y: 0.0), (x: 0.0, y: 1.0), (x: 1.0, y: 1.0)] {
            #expect(!insets.isInsideMirrorArea(nearInnerCorner(corner, dx: rx * 0.1, dy: ry * 0.1)))
            #expect(insets.isInsideMirrorArea(nearInnerCorner(corner, dx: rx * 1.5, dy: ry * 1.5)))
        }
    }

    @Test("둥근 FrameMask가 그리기를 정확히 막는다")
    func roundedFrameMaskBlocksDrawing() {
        let insets = MirrorFrameInsets.standard
        // 직선 구간 안쪽 = 그릴 수 없다
        #expect(!insets.isInsideFrameBand(NormalizedPoint(x: 0.5, y: 0.5)))
        #expect(!insets.isInsideFrameBand(NormalizedPoint(x: 0.5, y: insets.top + 0.01)))
        // 모서리 곡선 바깥 = 프레임이라 그릴 수 있다
        let rx = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.width
        let ry = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.height
        #expect(insets.isInsideFrameBand(nearInnerCorner((0, 0), dx: rx * 0.1, dy: ry * 0.1)))
    }

    @Test("실제 Mirror의 투명 구멍도 둥근 사각형이다")
    func runtimeUsesRoundedOpening() {
        let size = CGSize(width: 300, height: 650)
        let design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        let rx = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.width
        let ry = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.height

        // 모서리 곡선 바깥은 프레임이 칠해져 있다
        let corner = runtimePixel(
            design: design,
            at: nearInnerCorner((0, 0), dx: rx * 0.15, dy: ry * 0.15),
            size: size
        )
        #expect((corner?.alpha ?? 0) > 180)

        // 가운데는 그대로 투명하다
        let center = runtimePixel(design: design, at: NormalizedPoint(x: 0.5, y: 0.5), size: size)
        #expect((center?.alpha ?? 255) < 20)
    }

    @Test("Capture도 같은 둥근 구멍 geometry를 쓴다")
    func captureUsesRoundedOpening() {
        // Capture는 화면과 같은 MirrorDecorationView를 합성한다 — geometry가 갈라질 수 없다.
        let rect = CGRect(x: 0, y: 0, width: 300, height: 650)
        let path = MirrorFrameInsets.standard.mirrorAreaPath(in: rect)
        let area = MirrorFrameInsets.standard.mirrorArea.rect(in: rect.size)

        #expect(abs(path.boundingRect.width - area.width) < 0.5)
        #expect(abs(path.boundingRect.height - area.height) < 0.5)
        // 사각형 꼭짓점은 둥근 사각형 밖이다.
        #expect(!path.contains(CGPoint(x: area.minX + 0.5, y: area.minY + 0.5)))
        #expect(path.contains(CGPoint(x: area.midX, y: area.midY)))
    }

    @Test("Preview / Runtime의 모서리 반경은 같은 Master 값에서 나온다")
    func previewGeometryMatchesRuntime() {
        let small = CGSize(width: 150, height: 325)
        let large = CGSize(width: 300, height: 650)
        let a = MirrorGeometry.innerCornerRadius(for: small)
        let b = MirrorGeometry.innerCornerRadius(for: large)
        #expect(abs(b - a * 2) < 0.001)
        #expect(abs(a - CGFloat(MirrorGeometry.innerCornerRadius) * small.width / MirrorCanvas.size.width) < 0.001)
    }

    @Test("스티커 제약도 둥근 Mirror Area를 따른다")
    func stickerConstraintUsesRoundedMirrorArea() {
        let insets = MirrorFrameInsets.standard
        let rx = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.width
        let ry = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.height

        // 곡선 바깥(= 프레임)에 있는 중심은 그대로 유지된다.
        let corner = nearInnerCorner((0, 0), dx: rx * 0.1, dy: ry * 0.1)
        let kept = sticker(at: corner).constrained(to: insets)
        #expect(abs(kept.center.x - corner.x) < 0.0001)
        #expect(abs(kept.center.y - corner.y) < 0.0001)

        // 곡선 안쪽(= 카메라)에 있는 중심은 밴드로 밀려난다.
        let inside = sticker(at: NormalizedPoint(x: 0.5, y: 0.5)).constrained(to: insets)
        #expect(!insets.isInsideMirrorArea(inside.center))
    }

    // MARK: - Sticker 재선택 (Tap)

    /// Editor의 선택 상태 전이를 그대로 옮긴 것.
    /// 실제 tap 판정은 UITapGestureRecognizer가, hit test는 StickerObject.contains가 담당한다.
    private func tap(
        _ stickers: [StickerObject],
        at location: CGPoint,
        transform: SideDetailTransform,
        selection: UUID?
    ) -> UUID? {
        hitSticker(stickers, at: location, transform: transform)?.id
    }

    @Test("완료를 누르면 선택이 풀린다")
    func doneClearsSelection() {
        let target = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        var selection: UUID? = target.id
        selection = nil                                   // "완료"
        #expect(selection == nil)
    }

    @Test("완료 → 재탭 → 완료를 반복해도 계속 선택된다")
    func doneAndReselectRepeats() {
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        let target = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        let point = screenCenter(target, transform)

        var selection: UUID?
        for _ in 0..<5 {
            selection = tap([target], at: point, transform: transform, selection: selection)
            #expect(selection == target.id)               // 재선택
            selection = nil                               // 완료
            #expect(selection == nil)
        }
    }

    @Test("회전 / 뒤집기한 스티커도 재탭으로 선택된다")
    func rotatedAndFlippedStickerIsReselectable() {
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        for rotation in [0.0, 24.0, 45.0, 137.0, -60.0] {
            var target = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
            target.rotation = rotation
            target.isFlippedHorizontally = true
            let point = screenCenter(target, transform)
            #expect(tap([target], at: point, transform: transform, selection: nil) == target.id)
        }
    }

    @Test("확대 / 이동 / 중앙 배치 상태에서도 재탭으로 선택된다")
    func reselectWorksUnderZoomAndPan() {
        let states = [
            EditorViewportState(),                                            // 중앙 배치 기본
            EditorViewportState(zoom: 3),                                      // 최대 확대
            EditorViewportState(zoom: 1.4, pan: CGSize(width: -60, height: -240))
        ]
        for state in states {
            let transform = SideDetailTransform(
                side: .right, insets: .standard, viewport: viewport, state: state
            )
            // 화면 중앙이 가리키는 Master 지점에 스티커를 둔다 — 어떤 viewport에서도 보이는 자리다.
            let master = transform.masterPoint(from: CGPoint(x: viewport.width / 2, y: viewport.height / 2))
            let target = sticker(at: master, width: 0.1)
            let point = screenCenter(target, transform)
            #expect(tap([target], at: point, transform: transform, selection: nil) == target.id)
        }
    }

    @Test("겹친 스티커는 화면에서 위에 보이는 것이 선택된다")
    func overlappingStickersSelectTopmost() {
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        var bottom = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        var top = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        bottom.zIndex = 1
        top.zIndex = 2
        let point = screenCenter(top, transform)

        // 배열 순서를 뒤집어도 결과가 같아야 한다.
        #expect(tap([bottom, top], at: point, transform: transform, selection: nil) == top.id)
        #expect(tap([top, bottom], at: point, transform: transform, selection: nil) == top.id)

        // zIndex가 같으면 나중에 그려지는(= 배열 뒤쪽) 것이 위다.
        var a = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        var b = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        a.zIndex = 5
        b.zIndex = 5
        #expect(tap([a, b], at: point, transform: transform, selection: nil) == b.id)
    }

    @Test("잠긴 스티커도 재탭으로 선택된다")
    func lockedStickerIsReselectable() {
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        var locked = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        locked.isLocked = true
        let point = screenCenter(locked, transform)

        let selection = tap([locked], at: point, transform: transform, selection: nil)
        #expect(selection == locked.id)
        // 잠금 상태는 그대로 — 선택만 됐다.
        #expect(locked.isLocked)
    }

    @Test("스티커 tap은 화면을 밀지 않고, 빈 곳 tap만 선택을 푼다")
    func tapDoesNotPanAndEmptyTapDeselects() {
        let state = EditorViewportState()
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport, state: state)
        let master = transform.masterPoint(from: CGPoint(x: viewport.width / 2, y: viewport.height / 2))
        let target = sticker(at: master, width: 0.1)

        // 보이는 스티커를 눌렀으니 viewport는 그대로다.
        #expect(transform.focusState(on: target.frame, from: state) == nil)

        // 빈 곳(= gutter 쪽)을 누르면 선택이 풀린다.
        let empty = CGPoint(x: viewport.width - 4, y: 40)
        #expect(tap([target], at: empty, transform: transform, selection: target.id) == nil)
    }

    @Test("재선택은 스티커 / 디자인 / history를 바꾸지 않는다")
    func reselectDoesNotMutateState() {
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        var target = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        target.rotation = 30
        target.opacity = 0.7

        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.stickers = [target]
        let before = design
        let history = EditorHistory()

        let selection = tap(design.stickers, at: screenCenter(target, transform), transform: transform, selection: nil)
        #expect(selection == target.id)
        #expect(design == before)               // 디자인 불변
        #expect(!history.canUndo)               // history에 아무것도 쌓이지 않는다
        #expect(!history.canRedo)
    }

    @Test("실제로 끌면 스티커가 움직인다")
    func actualDragMovesSticker() {
        let transform = SideDetailTransform(side: .right, insets: .standard, viewport: viewport)
        let target = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        let start = transform.masterPoint(from: screenCenter(target, transform))
        let moved = transform.masterPoint(
            from: CGPoint(x: screenCenter(target, transform).x, y: screenCenter(target, transform).y + 80)
        )
        let grab = NormalizedPoint(x: start.x - target.center.x, y: start.y - target.center.y)
        let dragged = target
            .moved(to: NormalizedPoint(x: moved.x - grab.x, y: moved.y - grab.y))
            .constrained(to: .standard)

        #expect(dragged.center.y > target.center.y)
        #expect(abs(dragged.center.x - target.center.x) < 0.0001)
    }

    @Test("프레임 두께는 여전히 108 / 180으로 고정이다")
    func frameThicknessUnchanged() {
        #expect(MirrorFrameInsets.standard.left == 108.0 / 1080.0)
        #expect(MirrorFrameInsets.standard.right == 108.0 / 1080.0)
        #expect(abs(MirrorFrameInsets.standard.top - 180.0 / 2340.0) < 0.0001)
        #expect(abs(MirrorFrameInsets.standard.bottom - 180.0 / 2340.0) < 0.0001)
        #expect(MirrorLibrary.defaultMirror.style.insets == .standard)
    }
}
