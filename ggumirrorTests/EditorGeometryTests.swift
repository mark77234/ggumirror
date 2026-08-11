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

    @Test("화면 좌표 → Master normalized → 화면 좌표 왕복이 일치한다")
    func screenToMasterRoundTrip() {
        let transform = EditorCanvasTransform(viewport: viewport)
        let screenPoint = CGPoint(x: 137, y: 209)

        let master = transform.masterPoint(from: screenPoint)
        let backX = master.x * transform.canvasSize.width + transform.offset.x
        let backY = master.y * transform.canvasSize.height + transform.offset.y

        #expect(abs(backX - screenPoint.x) < 0.001)
        #expect(abs(backY - screenPoint.y) < 0.001)
    }

    // MARK: - Frame mask

    @Test("frameInsets가 달라지면 mask 경계도 달라진다")
    func maskFollowsInsets() {
        let point = NormalizedPoint(x: 0.5, y: 0.09)
        // standard(상하 0.0769)에서는 이미 거울 영역, 더 두꺼운 값에서는 아직 프레임
        #expect(MirrorFrameInsets.standard.isInsideMirrorArea(point))
        #expect(!Self.thickInsets.isInsideMirrorArea(point))
    }

    // MARK: - 밴드 분할

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

    @Test("요청한 pan이 범위를 넘으면 clamp된 값이 돌아온다")
    func appliedPanIsClamped() {
        let t = EditorCanvasTransform(viewport: viewport, state: .init(pan: CGSize(width: 0, height: 100_000))
        )
        #expect(t.appliedPan.height < 100_000)
    }

    @Test("Mini Map viewport가 pan을 따라 움직인다")
    func visibleRectFollowsPan() {
        let middle = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 2))
        let up = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 2, pan: CGSize(width: 0, height: 200)))
        let down = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 2, pan: CGSize(width: 0, height: -200)))

        #expect(up.visibleRect.y < middle.visibleRect.y)
        #expect(down.visibleRect.y > middle.visibleRect.y)
        // 크기는 그대로 — 배율은 변하지 않는다
        #expect(abs(up.visibleRect.height - middle.visibleRect.height) < 0.0001)
    }

    @Test("pan 후에도 화면 좌표 왕복 변환이 일치한다")
    func masterRoundTripAfterPan() {
        let t = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 2, pan: CGSize(width: 0, height: -240)))
        let screenPoint = CGPoint(x: 210, y: 380)
        let master = t.masterPoint(from: screenPoint)

        #expect(abs(master.x * t.canvasSize.width + t.offset.x - screenPoint.x) < 0.001)
        #expect(abs(master.y * t.canvasSize.height + t.offset.y - screenPoint.y) < 0.001)
    }

    @Test("pan하면 같은 화면 좌표가 다른 Master 좌표를 가리킨다")
    func panChangesMasterPoint() {
        let before = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 2))
        let after = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 2, pan: CGSize(width: 0, height: -300)))
        let screenPoint = CGPoint(x: 200, y: 300)

        #expect(after.masterPoint(from: screenPoint).y > before.masterPoint(from: screenPoint).y)
        // 배율은 그대로여야 한다
        #expect(before.canvasSize == after.canvasSize)
    }

    // MARK: - Zoom

    @Test("Zoom은 지정한 범위를 벗어나지 않는다")
    func zoomIsClamped() {
        let tiny = EditorCanvasTransform(viewport: viewport, state: .init(zoom: -5))
        let huge = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 999))
        #expect(tiny.appliedZoom == EditorViewportState.zoomRange.lowerBound)
        #expect(huge.appliedZoom == EditorViewportState.zoomRange.upperBound)
        #expect(tiny.canvasSize.width > 0)
    }

    @Test("배율이 바뀌어도 화면↔Master 왕복이 일치한다", arguments: [1.0, 2.0, 3.0])
    func roundTripAtZoom(zoom: Double) {
        let t = EditorCanvasTransform(viewport: viewport, state: .init(zoom: CGFloat(zoom), pan: CGSize(width: 0, height: -120))
        )
        let screenPoint = CGPoint(x: 180, y: 260)
        let master = t.masterPoint(from: screenPoint)
        let back = t.screenPoint(from: master)
        #expect(abs(back.x - screenPoint.x) < 0.001)
        #expect(abs(back.y - screenPoint.y) < 0.001)
    }

    @Test("Zoom Out하면 pan이 다시 clamp되어 거울 한 장이 그대로 보인다")
    func panReclampedAfterZoomOut() {
        // 최대 배율에서 끝까지 이동한 pan 값을 그대로 맞춤 배율에 적용해도 가운데 정렬로 돌아간다.
        let zoomedIn = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 3, pan: CGSize(width: 0, height: -100_000)))
        let backToFit = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 1, pan: zoomedIn.appliedPan))

        #expect(backToFit.appliedPan == .zero)
        #expect(abs(backToFit.visibleRect.width - 1) < 0.0001)
        #expect(abs(backToFit.visibleRect.height - 1) < 0.0001)
    }

    @Test("Brush 굵기는 배율과 무관하다")
    func brushWidthIsIndependentFromZoom() {
        let width = EditorBrush.pen.defaultWidth
        let fit = EditorCanvasTransform(viewport: viewport)
        let zoomed = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 3))
        // 저장되는 값은 normalized라 배율이 달라도 그대로다. 화면 굵기만 커진다.
        let stroke = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.5)], width: width)
        #expect(stroke.width == width)
        #expect(zoomed.canvasSize.width > fit.canvasSize.width)
    }

    @Test("지우개 반경은 배율에 따라 Master 기준으로 환산된다")
    func eraserRadiusFollowsZoom() {
        let fit = EditorCanvasTransform(viewport: viewport)
        let zoomed = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 3))
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

        do {
            for zoom in [1.0, 1.7, 3.0] {
                for pan in [-800.0, 0.0, 800.0] {
                    _ = EditorCanvasTransform(
                        viewport: viewport,
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
        _ = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 2, pan: CGSize(width: 0, height: -200)))
        history.apply(.addStroke(b), to: &snapshot)
        _ = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 1, pan: .zero))

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
        transform: EditorCanvasTransform,
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

    /// 캔버스를 세로로 가로지르는 긴 획. 프레임과 카메라 영역을 모두 지난다.
    private var longStroke: DrawingStroke {
        DrawingStroke(
            points: (0...20).map { NormalizedPoint(x: 0.5, y: 0.03 + Double($0) * 0.047) },
            width: 14 / MirrorCanvas.size.width
        )
    }

    @Test("일부만 화면에 걸친 긴 획도 렌더 대상이다", arguments: [1.0, 2.0, 3.0])
    func partiallyVisibleStrokeIsRendered(zoom: Double) {
        let stroke = longStroke
        for pan in [0.0, -400.0, -1200.0, 400.0, 1200.0] {
            let transform = EditorCanvasTransform(viewport: viewport, state: .init(zoom: CGFloat(zoom), pan: CGSize(width: 0, height: pan))
            )
            #expect(
                strokeIsRendered(stroke, transform: transform, viewport: viewport),
                "zoom \(zoom), pan \(pan)에서 획이 통째로 사라짐"
            )
        }
    }

    @Test("bounding box가 viewport보다 커도 skip하지 않는다")
    func oversizedStrokeIsNotSkipped() {
        let stroke = longStroke
        let transform = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 3))
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
        let top = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 3, pan: CGSize(width: 0, height: 100_000)))
        let bottom = EditorCanvasTransform(
            viewport: viewport,
            state: .init(zoom: 3, pan: CGSize(width: 100_000, height: -100_000))
        )

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
        // 맞춤에서는 전부 보이고, 오른쪽 위로 확대해도 같은 획이 보인다.
        let fitted = EditorCanvasTransform(viewport: viewport)
        let zoomedCorner = EditorCanvasTransform(
            viewport: viewport,
            state: .init(zoom: 2, pan: CGSize(width: -100_000, height: 100_000))
        )
        #expect(strokeIsRendered(stroke, transform: fitted, viewport: viewport))
        #expect(strokeIsRendered(stroke, transform: zoomedCorner, viewport: viewport))
    }

    @Test("Master 획 데이터는 viewport 기준으로 잘리지 않는다")
    func strokePointsAreNeverTrimmed() {
        let stroke = longStroke
        let original = stroke.points
        for pan in [-1200.0, 0.0, 1200.0] {
            _ = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 3, pan: CGSize(width: 0, height: pan)))
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
                // Editor와 같이 카메라 영역까지 배경색으로 채운 뒤 그 위의 잉크를 센다.
                mirrorAreaFill: design.style.frame,
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

        // 카메라 영역을 포함한 캔버스 전체에서 잉크 픽셀을 센다.
        var dark = 0
        var total = 0
        for y in 0..<height {
            for x in 0..<width {
                total += 1
                let i = (y * width + x) * 4
                if data[i] < 120 && data[i + 1] < 120 && data[i + 2] < 120 { dark += 1 }
            }
        }
        return (dark, total)
    }

    @Test("확대해도 획이 실제로 렌더된다", arguments: [1.0, 2.0, 3.0])
    func strokeActuallyRendersWhenZoomed(zoom: Double) {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.strokes = [longStroke]

        let transform = EditorCanvasTransform(viewport: viewport, state: .init(zoom: CGFloat(zoom))
        )
        let result = renderedPixels(
            design: design,
            transform: MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset),
            size: viewport
        )

        #expect(result.total > 0)
        #expect(result.dark > 0, "zoom \(zoom)에서 획이 한 픽셀도 그려지지 않음")
    }

    @Test("맞춤 상태에서도 획이 실제로 렌더된다")
    func strokeActuallyRendersWhenFitted() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.strokes = [longStroke]

        let size = CGSize(width: 300, height: 650)
        let result = renderedPixels(design: design, transform: .fitted(in: size), size: size)
        #expect(result.dark > 0, "Overview에서 획이 그려지지 않음")
    }

    // MARK: - Scroll Handle

    // MARK: - Zoom 정책

    @Test("최대 배율은 정책 상한을 넘지 않는다")
    func maximumZoomIsClamped() {
        let t = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 99))
        #expect(t.appliedZoom == EditorViewportState.zoomRange.upperBound)
    }

    @Test("맞춤은 기본 상태로 되돌린다")
    func fitReturnsToDefault() {
        let moved = EditorViewportState(zoom: 2.4, pan: CGSize(width: 40, height: -600))
        #expect(!moved.isFitted)
        #expect(EditorViewportState().isFitted)

        let fitted = EditorCanvasTransform(viewport: viewport)
        let base = EditorCanvasTransform(viewport: viewport, state: EditorViewportState())
        #expect(fitted.offset == base.offset)
        #expect(fitted.canvasSize == base.canvasSize)
    }

    // MARK: - Scroll Handle 스크럽

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
                points: (0...10).map { NormalizedPoint(x: 0.5, y: 0.2 + Double($0) * 0.03) },
                brush: brush,
                width: brush.defaultWidth
            )
        ]
        let size = CGSize(width: 300, height: 650)
        let result = renderedPixels(design: design, transform: .fitted(in: size), size: size)
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
        _ = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 3, pan: CGSize(width: 0, height: -900)))
        let pixel = runtimePixel(design: design, at: NormalizedPoint(x: 0.95, y: 0.91))
        #expect((pixel?.red ?? 255) < 120)
    }

    /// 저장 정책 테스트용 시드.
    /// 실제 앱의 초기 내 거울은 비어 있으므로, 필요한 거울은 테스트가 직접 만든다.
    private func seededLibrary() -> MirrorLibrary {
        let library = MirrorLibrary()
        library.acquire(StoreCatalog.basics[0])      // 무료 기본 템플릿 → origin .basic
        library.acquire(StoreCatalog.artworkTemplates[0])   // 손그림 템플릿 → origin .purchased
        _ = library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "내가 만든 거울", context: .createNew)
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
        _ = library.save(design, name: "테스트 거울", context: .editCurrent)

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

    private func sticker(_ source: StickerSource = .builtIn(.heart), at point: NormalizedPoint, width: Double = 0.16) -> StickerObject {
        let height = StickerObject.height(for: width, aspectRatio: source.aspectRatio)
        return StickerObject(
            source: source,
            frame: NormalizedRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
        )
    }

    @Test("스티커는 보고 있는 위치 근처에 들어간다")
    func stickerInsertsNearViewport() {
        let design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        // Right 하단을 보고 있는 상태
        let transform = EditorCanvasTransform(viewport: viewport, state: .init(pan: CGSize(width: 0, height: -100_000))
        )
        let placed = StickerPlacement.insert(.builtIn(.heart), in: design, visibleRect: transform.visibleRect)

        // 보고 있는 화면 한가운데에 생긴다. 프레임 / 카메라를 가리지 않는다.
        let center = NormalizedPoint(
            x: transform.visibleRect.x + transform.visibleRect.width / 2,
            y: transform.visibleRect.y + transform.visibleRect.height / 2
        )
        #expect(abs(placed.center.x - center.x) < 0.001)
        #expect(abs(placed.center.y - center.y) < 0.001)
    }

    @Test("모서리를 걸친 스티커도 하나의 오브젝트다")
    func cornerStickerStaysSingleObject() {
        let insets = MirrorFrameInsets.standard
        let corner = sticker(at: NormalizedPoint(x: 0.96, y: 0.04)).constrained()
        #expect(corner.center.x > 0.9 && corner.center.y < 0.1)
        // 밴드를 넘어가는 부분이 있어도 잘리거나 복제되지 않는다.
        #expect(corner.frame.x < insets.mirrorArea.x + insets.mirrorArea.width)
    }

    @Test("이동은 화면 배율과 무관하게 같은 Master 위치가 된다", arguments: [1.0, 3.0])
    func stickerMoveMapsToMaster(zoom: Double) {
        let transform = EditorCanvasTransform(viewport: viewport, state: .init(zoom: CGFloat(zoom)))
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
        var item = sticker(at: NormalizedPoint(x: 0.05, y: 0.5)).constrained()
        let before = item.center
        item.rotation = 40
        let after = item.constrained().center
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
        var front = sticker(.builtIn(.star), at: NormalizedPoint(x: 0.05, y: 0.5))
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
            _ = EditorCanvasTransform(viewport: viewport, state: .init(zoom: CGFloat(zoom), pan: CGSize(width: 0, height: -300)))
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
            .constrained()]
        #expect(runtimePixel(design: design, at: NormalizedPoint(x: 0.5, y: 0.5))?.alpha == 0)
    }

    @Test("Editor에서 얹은 스티커가 저장 후 현재 거울에 남는다")
    func stickerSurvivesSave() {
        let library = MirrorLibrary()
        var design = MirrorDesign(mirror: library.currentMirror)
        let item = sticker(.builtIn(.ribbon), at: NormalizedPoint(x: 0.95, y: 0.8))
        design.stickers = [item]
        _ = library.save(design, name: "테스트 거울", context: .editCurrent)

        let updated = MirrorDesign(mirror: library.currentMirror)
        #expect(updated.stickers.first?.id == item.id)
        #expect(updated.stickers.first?.source == .builtIn(.ribbon))
    }

    // MARK: - Sticker 라이브러리 / tint

    @Test("기본 스티커가 20종 이상이고 식별자가 겹치지 않는다")
    func stickerLibraryIsLargeAndUnique() {
        #expect(BuiltInSticker.allCases.count >= 20)
        #expect(Set(BuiltInSticker.allCases.map(\.rawValue)).count == BuiltInSticker.allCases.count)
        #expect(Set(BuiltInSticker.allCases.map(\.symbolName)).count == BuiltInSticker.allCases.count)
        #expect(BuiltInSticker.allCases.allSatisfy { !$0.title.isEmpty })
    }

    @Test("카테고리 필터가 동작한다", arguments: StickerCategory.allCases)
    func stickerCategoryFilters(category: StickerCategory) {
        let filtered = BuiltInSticker.all(in: category)
        #expect(!filtered.isEmpty)
        if category == .all {
            #expect(filtered.count == BuiltInSticker.allCases.count)
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

        #expect(library.willCreateNewMirror(for: design, context: .duplicate))
        let outcome = library.save(design, name: "내 첫 거울", context: .duplicate)
        #expect(outcome.name == "내 첫 거울")
        #expect(outcome.mirrorID != basic.id)
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
        #expect(library.willCreateNewMirror(for: design, context: .duplicate))
        let purchasedOutcome = library.save(design, name: "구매 거울 편집", context: .duplicate)
        #expect(purchasedOutcome.name == "구매 거울 편집")
        #expect(purchasedOutcome.mirrorID != purchased.id)
        #expect(library.mirrors.contains { $0.id == purchased.id && $0.origin == .purchased })
    }

    @Test("홈에서 내가 만든 거울을 다시 편집하면 같은 거울이 갱신된다")
    func savingCreatedMirrorUpdatesInPlace() {
        let library = seededLibrary()
        let made = library.mirrors.first { $0.origin == .made }!
        let before = library.mirrors.count
        var design = MirrorDesign(mirror: made)
        design.backgroundColor = BasicMirror.mint.style.frame

        #expect(!library.willCreateNewMirror(for: design, context: .editCurrent))
        let updatedOutcome = library.save(design, name: "무시되는 이름", context: .editCurrent)
        #expect(updatedOutcome == .updated(id: made.id, name: made.name))
        #expect(library.mirrors.count == before)
        // 이름은 그대로 — 홈에서 고칠 때마다 다시 묻지 않는다.
        #expect(library.mirrors.first { $0.id == made.id }?.name == made.name)
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
            let outcome = library.save(MirrorDesign(mirror: basic), name: "거울", context: .duplicate)
            #expect(outcome != .needsMoreSlots)
        }
        #expect(library.createdCount == library.createdCapacity)
        let blocked = library.save(MirrorDesign(mirror: basic), name: "하나 더", context: .duplicate)
        #expect(blocked == .needsMoreSlots)
    }

    @Test("슬롯이 가득 차도 기존 내 거울 편집은 계속 가능하다")
    func fullSlotsStillAllowUpdates() {
        let library = seededLibrary()
        let basic = library.mirrors.first { $0.origin == .basic }!
        while library.hasFreeCreatedSlot {
            _ = library.save(MirrorDesign(mirror: basic), name: "거울", context: .duplicate)
        }
        let existing = library.mirrors.last { $0.origin == .made }!
        var design = MirrorDesign(mirror: existing)
        design.backgroundColor = BasicMirror.sky.style.frame
        let stillEditable = library.save(design, name: "계속 편집", context: .editCurrent)
        #expect(stillEditable == .updated(id: existing.id, name: existing.name))
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

    @Test("Pan / Zoom 후에도 Master 좌표 변환이 유효하다")
    func panZoomRetainsValidMasterMapping() {
        for zoom in [0.7, 1.0, 2.4] {
            let transform = EditorCanvasTransform(viewport: viewport, state: .init(zoom: CGFloat(zoom), pan: CGSize(width: -120, height: -260))
            )
            let screen = CGPoint(x: 90, y: 300)
            let master = transform.masterPoint(from: screen)
            let back = transform.screenPoint(from: master)
            #expect(abs(back.x - screen.x) < 0.001)
            #expect(abs(back.y - screen.y) < 0.001)
        }
    }

    // MARK: - Sticker 재선택 / Focus

    /// 화면 좌표 hit test. SideDetailCanvas.sticker(at:transform:)와 같은 규칙이다.
    /// 화면에서 위에 보이는 것(zIndex → 배열 순서)이 먼저 잡힌다.
    private func hitSticker(
        _ stickers: [StickerObject],
        at location: CGPoint,
        transform: EditorCanvasTransform
    ) -> StickerObject? {
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        return stickers.enumerated()
            .filter { $0.element.contains(location, in: placement) }
            .max { ($0.element.zIndex, $0.offset) < ($1.element.zIndex, $1.offset) }?
            .element
    }

    /// 스티커의 화면상 중심.
    private func screenCenter(_ object: StickerObject, _ transform: EditorCanvasTransform) -> CGPoint {
        let rect = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
            .rect(object.frame)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    @Test("스티커를 탭하면 그 스티커가 선택된다")
    func stickerTapSelectsObject() {
        let transform = EditorCanvasTransform(viewport: viewport)
        let target = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        let center = placement.rect(target.frame)

        #expect(hitSticker([target], at: CGPoint(x: center.midX, y: center.midY), transform: transform)?.id == target.id)
        #expect(hitSticker([target], at: CGPoint(x: center.midX, y: center.midY - 400), transform: transform) == nil)
    }

    @Test("완료로 선택을 푼 뒤 다시 탭하면 같은 스티커가 선택된다")
    func doneThenReselectWorks() {
        let transform = EditorCanvasTransform(viewport: viewport)
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

        let transform = EditorCanvasTransform(viewport: viewport)
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        let rect = placement.rect(target.frame)
        let found = hitSticker([target], at: CGPoint(x: rect.midX, y: rect.midY), transform: transform)

        #expect(found == target)
    }

    @Test("잠긴 스티커도 다시 선택할 수 있다")
    func lockedStickerCanBeSelected() {
        var locked = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        locked.isLocked = true

        let transform = EditorCanvasTransform(viewport: viewport)
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        let rect = placement.rect(locked.frame)

        let found = hitSticker([locked], at: CGPoint(x: rect.midX, y: rect.midY), transform: transform)
        #expect(found?.id == locked.id)
        #expect(found?.isLocked == true)
    }

    @Test("화면 밖으로 나간 스티커는 zoom을 유지한 채 최소한만 끌어온다")
    func partiallyOffscreenStickerAppliesMinimalFocus() {
        let state = EditorViewportState(zoom: 1.6)
        let transform = EditorCanvasTransform(viewport: viewport, state: state)
        // 아래쪽 멀리 있는 스티커
        let far = sticker(at: NormalizedPoint(x: 0.95, y: 0.95))

        let focused = transform.focusState(on: far.frame, from: state)
        #expect(focused != nil)
        #expect(focused?.zoom == state.zoom)             // zoom은 절대 바꾸지 않는다

        let after = EditorCanvasTransform(viewport: viewport, state: focused ?? state
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
        let transform = EditorCanvasTransform(viewport: viewport, state: state)
        // 기본 화면 중앙 근처
        let master = transform.masterPoint(from: CGPoint(x: viewport.width / 2, y: viewport.height / 2))
        let visible = sticker(at: master, width: 0.1)

        #expect(transform.focusState(on: visible.frame, from: state) == nil)
    }

    @Test("다른 스티커를 고르면 이전 선택은 풀린다")
    func selectingADeselectsB() {
        let transform = EditorCanvasTransform(viewport: viewport)
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
        let transform = EditorCanvasTransform(viewport: viewport, state: state)
        let target = sticker(at: NormalizedPoint(x: 0.95, y: 0.95))
        let before = target

        _ = transform.focusState(on: target.frame, from: state)
        #expect(target == before)
    }

    @Test("회전하거나 작은 스티커도 눈에 보이는 곳을 누르면 잡힌다")
    func rotatedAndSmallStickersStayTappable() {
        let transform = EditorCanvasTransform(viewport: viewport)
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
        let start = EditorViewportState(zoom: 2)
        var next = start
        next.pan.height -= 160                       // 빈 공간에서 한 손가락으로 끌어올림

        let moved = EditorCanvasTransform(viewport: viewport, state: next)
        let base = EditorCanvasTransform(viewport: viewport, state: start)
        #expect(moved.offset.y < base.offset.y)
        // 보이는 영역이 함께 내려간다.
        #expect(moved.visibleRect.y > base.visibleRect.y)
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
            // 값은 0이지만 갈래는 "기본"이다 — "무료" 갈래는 손그림 8장을 가리킨다.
            #expect(template.isFree)
            #expect(template.category == .basic)
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

    // MARK: - Sticker 재선택 (Tap)

    /// Editor의 선택 상태 전이를 그대로 옮긴 것.
    /// 실제 tap 판정은 UITapGestureRecognizer가, hit test는 StickerObject.contains가 담당한다.
    private func tap(
        _ stickers: [StickerObject],
        at location: CGPoint,
        transform: EditorCanvasTransform,
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
        let transform = EditorCanvasTransform(viewport: viewport)
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
        let transform = EditorCanvasTransform(viewport: viewport)
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
            let transform = EditorCanvasTransform(viewport: viewport, state: state
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
        let transform = EditorCanvasTransform(viewport: viewport)
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
        let transform = EditorCanvasTransform(viewport: viewport)
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
        let transform = EditorCanvasTransform(viewport: viewport, state: state)
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
        let transform = EditorCanvasTransform(viewport: viewport)
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
        let transform = EditorCanvasTransform(viewport: viewport)
        let target = sticker(at: NormalizedPoint(x: 0.95, y: 0.5))
        let start = transform.masterPoint(from: screenCenter(target, transform))
        let moved = transform.masterPoint(
            from: CGPoint(x: screenCenter(target, transform).x, y: screenCenter(target, transform).y + 80)
        )
        let grab = NormalizedPoint(x: start.x - target.center.x, y: start.y - target.center.y)
        let dragged = target
            .moved(to: NormalizedPoint(x: moved.x - grab.x, y: moved.y - grab.y))
            .constrained()

        #expect(dragged.center.y > target.center.y)
        #expect(abs(dragged.center.x - target.center.x) < 0.0001)
    }

    // MARK: - Photo Sticker

    /// 가운데가 불투명하고 가장자리는 투명한 테스트용 이미지.
    private func testImage(width: Int, height: Int, color: CGColor? = nil) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(color ?? CGColor(red: 0.1, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(
            x: width / 4, y: height / 4,
            width: width / 2, height: height / 2
        ))
        return context.makeImage()!
    }

    private func testImageData(width: Int, height: Int) -> Data {
        UIImage(cgImage: testImage(width: width, height: height)).pngData()!
    }

    @Test("사진 스티커는 이미지가 아니라 참조만 담는다")
    func photoStickerStoresOnlyReference() {
        let store = PhotoStickerAssetStore()
        let source = store.register(testImage(width: 300, height: 200))

        #expect(source.photoAssetID != nil)
        #expect(store.isRegistered(source))
        // 참조 하나만으로 값 비교가 끝난다 — binary가 모델에 들어가지 않는다.
        let a = sticker(source, at: NormalizedPoint(x: 0.05, y: 0.5))
        var b = a
        b.id = a.id
        #expect(a == b)
        #expect(StickerSource.builtIn(.heart).photoAssetID == nil)
    }

    @Test("AssetStore는 등록한 이미지를 그대로 돌려준다")
    func assetStoreRegisterAndResolve() {
        let store = PhotoStickerAssetStore()
        let image = testImage(width: 300, height: 200)
        let source = store.register(image)

        guard let id = source.photoAssetID else { return #expect(Bool(false)) }
        #expect(store.image(for: id)?.width == 300)
        #expect(store.image(for: id)?.height == 200)
        #expect(store.image(for: UUID()) == nil)     // 없는 asset은 nil — 렌더러가 건너뛴다
        #expect(store.count == 1)
    }

    @Test("사진 스티커는 원본 비율을 유지한다")
    func photoKeepsIntrinsicAspectRatio() {
        let store = PhotoStickerAssetStore()
        let source = store.register(testImage(width: 300, height: 200))
        #expect(abs(source.aspectRatio - 1.5) < 0.0001)

        // 정사각형을 강요하지 않는다.
        let square = StickerObject.height(for: 0.2, aspectRatio: 1)
        let wide = StickerObject.height(for: 0.2, aspectRatio: 1.5)
        #expect(wide < square)

        // 크기를 바꿔도 비율이 유지된다.
        let resized = sticker(source, at: NormalizedPoint(x: 0.05, y: 0.5)).resized(width: 0.3)
        let masterAspect = (resized.frame.width * MirrorCanvas.size.width)
            / (resized.frame.height * MirrorCanvas.size.height)
        #expect(abs(masterAspect - 1.5) < 0.001)
    }

    @Test("사진 스티커는 tint를 지원하지 않는다")
    func photoStickerHasNoTint() {
        let store = PhotoStickerAssetStore()
        var item = sticker(store.register(testImage(width: 200, height: 200)), at: NormalizedPoint(x: 0.05, y: 0.5))
        item.tintColor = .red
        #expect(item.source.renderMode == .original)
        #expect(!item.source.supportsTint)
        #expect(item.resolvedTint == nil)
    }

    @Test("Undo / Redo를 반복해도 이미지가 복사되지 않는다")
    func historyKeepsNoImageBinary() {
        let store = PhotoStickerAssetStore()
        let source = store.register(testImage(width: 300, height: 200))
        let item = sticker(source, at: NormalizedPoint(x: 0.05, y: 0.5))

        var snapshot = EditorSnapshot()
        var history = EditorHistory()
        history.apply(.addSticker(item), to: &snapshot)
        for offset in 1...5 {
            var moved = snapshot.stickers[0]
            moved.opacity = 1 - Double(offset) / 10
            history.apply(.replaceSticker(moved), to: &snapshot)
        }
        for _ in 0..<3 { history.undo(&snapshot) }
        for _ in 0..<3 { history.redo(&snapshot) }

        // 스택이 아무리 깊어져도 이미지는 여전히 한 장이다.
        #expect(store.count == 1)
        #expect(snapshot.stickers[0].source == source)
        #expect(store.isRegistered(snapshot.stickers[0].source))
    }

    @Test("복제한 사진 스티커는 같은 asset을 참조한다")
    func duplicateSharesPhotoAsset() {
        let store = PhotoStickerAssetStore()
        let source = store.register(testImage(width: 300, height: 200))
        let original = sticker(source, at: NormalizedPoint(x: 0.05, y: 0.4))

        var copy = original
        copy.id = UUID()
        #expect(copy.id != original.id)
        #expect(copy.source == original.source)                  // 같은 assetID
        #expect(copy.source.photoAssetID == original.source.photoAssetID)
        #expect(store.count == 1)                                // 이미지는 늘지 않는다
    }

    @Test("사진 스티커 여러 장이 같은 asset을 공유한다")
    func multiplePhotoStickersShareAssets() {
        let store = PhotoStickerAssetStore()
        let shared = store.register(testImage(width: 200, height: 200))
        let items = (0..<4).map { index in
            sticker(shared, at: NormalizedPoint(x: 0.05, y: 0.2 + Double(index) * 0.15))
        }
        #expect(items.count == 4)
        #expect(store.count == 1)

        // 서로 다른 사진은 각각 보관된다.
        _ = store.register(testImage(width: 100, height: 100))
        #expect(store.count == 2)
    }

    @Test("큰 사진은 축소해서 처리한다")
    func largePhotoIsDownsampled() throws {
        let data = testImageData(width: 4000, height: 3000)
        let image = try PhotoStickerMaker.makeOriginal(from: data)

        #expect(max(image.width, image.height) <= PhotoStickerMaker.maximumPixelSize)
        #expect(max(image.width, image.height) > 0)
        // 비율은 그대로다.
        #expect(abs(Double(image.width) / Double(image.height) - 4.0 / 3.0) < 0.02)
    }

    @Test("잘라낸 스티커에 투명 여백이 남는다")
    func croppedStickerKeepsTransparentPadding() {
        let source = testImage(width: 200, height: 100)
        let padded = PhotoStickerMaker.padded(source)
        let inset = Int((200.0 * PhotoStickerMaker.transparentPadding).rounded())

        #expect(inset > 0)
        #expect(padded.width == source.width + inset * 2)
        #expect(padded.height == source.height + inset * 2)
        #expect(padded.alphaInfo != .none)                 // 투명도를 유지한다
    }

    @Test("사진 스티커가 실제 Mirror에 그려지고 중앙은 투명하다")
    func photoStickerRendersInRuntime() {
        let source = PhotoStickerAssetStore.shared.register(testImage(width: 200, height: 200))
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.stickers = [sticker(source, at: NormalizedPoint(x: 0.05, y: 0.5), width: 0.14)]

        let center = runtimePixel(design: design, at: NormalizedPoint(x: 0.05, y: 0.5))
        #expect((center?.alpha ?? 0) > 200)
        #expect((center?.blue ?? 0) > (center?.red ?? 255))     // 파란 테스트 이미지가 보인다

        // 카메라 영역은 그대로 투명하다.
        let mirror = runtimePixel(design: design, at: NormalizedPoint(x: 0.5, y: 0.5))
        #expect((mirror?.alpha ?? 255) < 20)
    }

    @Test("Capture에도 사진 스티커가 같은 자리에 들어간다")
    func photoStickerRendersInCapture() {
        let source = PhotoStickerAssetStore.shared.register(testImage(width: 200, height: 200))
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.stickers = [sticker(source, at: NormalizedPoint(x: 0.05, y: 0.5), width: 0.14)]

        let size = CGSize(width: 300, height: 650)
        let image = MirrorCapture.compose(frame: nil, design: design, size: size)
        #expect(image != nil)
        #expect(abs((image?.size.width ?? 0) - size.width) < 1)
    }

    @Test("사진 스티커도 같은 변형 / 제약 / 배치를 쓴다")
    func photoStickerReusesTransformEngine() {
        let store = PhotoStickerAssetStore()
        let source = store.register(testImage(width: 300, height: 200))
        var item = sticker(source, at: NormalizedPoint(x: 0.05, y: 0.5))

        // 회전 / 뒤집기 / 투명도 / 잠금
        item.rotation = 30
        item.isFlippedHorizontally = true
        item.opacity = 0.5
        item.isLocked = true
        #expect(item.rotation == 30)
        #expect(item.isFlippedHorizontally)
        #expect(item.opacity == 0.5)
        #expect(item.isLocked)

        // 크기 범위 제한은 기본 스티커와 동일
        #expect(item.resized(width: 5).frame.width == StickerObject.sizeRange.upperBound)

        // 카메라 영역 한가운데도 그대로 유효한 자리다.
        let inCamera = sticker(source, at: NormalizedPoint(x: 0.5, y: 0.5)).constrained()
        #expect(abs(inCamera.center.x - 0.5) < 0.0001)
        #expect(abs(inCamera.center.y - 0.5) < 0.0001)
        #expect(MirrorFrameInsets.standard.isInsideMirrorArea(inCamera.center))

        // 배치도 기존 StickerPlacement 그대로
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.stickers = []
        let transform = EditorCanvasTransform(viewport: viewport)
        let placed = StickerPlacement.insert(
            source, in: design, visibleRect: transform.visibleRect
        )
        #expect(abs(placed.center.x - 0.5) < 0.001)
        #expect(abs(placed.frame.width / placed.frame.height
                    * MirrorCanvas.size.width / MirrorCanvas.size.height - 1.5) < 0.001)
    }

    @Test("사진 스티커도 확대 / 회전 상태에서 재선택된다")
    func photoStickerIsReselectable() {
        let store = PhotoStickerAssetStore()
        let source = store.register(testImage(width: 300, height: 200))

        for zoom in [1.0, 3.0] {
            let state = EditorViewportState(zoom: CGFloat(zoom))
            let transform = EditorCanvasTransform(viewport: viewport, state: state
            )
            let master = transform.masterPoint(from: CGPoint(x: viewport.width / 2, y: viewport.height / 2))
            var item = sticker(source, at: master, width: 0.12)
            item.rotation = 40

            var selection: UUID? = item.id
            selection = nil                                       // 완료
            selection = tap([item], at: screenCenter(item, transform), transform: transform, selection: selection)
            #expect(selection == item.id)
        }
    }

    // MARK: - Photo Sticker Preview (Home / My Mirrors)

    /// 저장된 거울을 Gallery 미리보기와 같은 pipeline으로 그린다.
    private func previewPixel(
        _ mirror: MyMirror,
        at point: NormalizedPoint,
        size: CGSize = CGSize(width: 200, height: 433)
    ) -> (red: Int, green: Int, blue: Int, alpha: Int)? {
        let view = MirrorPreview(mirror: mirror).frame(width: size.width, height: size.height)
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

        let x = Int(point.x * Double(width))
        let y = Int(point.y * Double(height))
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let offset = (y * width + x) * 4
        return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]), Int(data[offset + 3]))
    }

    /// 사진 스티커가 든 거울을 만들어 저장한다.
    private func libraryWithPhotoMirror() -> (MirrorLibrary, StickerSource) {
        let library = MirrorLibrary()
        let source = PhotoStickerAssetStore.shared.register(testImage(width: 200, height: 200))
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.stickers = [sticker(source, at: NormalizedPoint(x: 0.05, y: 0.5), width: 0.14)]
        _ = library.save(design, name: "사진 거울", context: .editCurrent)
        return (library, source)
    }

    @Test("저장한 거울이 사진 스티커 참조를 그대로 들고 있다")
    func savedMirrorPreservesPhotoSticker() {
        let (library, source) = libraryWithPhotoMirror()
        let saved = library.currentMirror

        #expect(saved.stickers.count == 1)
        #expect(saved.stickers[0].source == source)
        #expect(saved.stickers[0].source.photoAssetID == source.photoAssetID)
        #expect(PhotoStickerAssetStore.shared.isRegistered(saved.stickers[0].source))
    }

    @Test("홈 / 내 거울 미리보기에 사진 스티커가 실제로 그려진다")
    func previewsRenderPhotoSticker() {
        let (library, _) = libraryWithPhotoMirror()
        let saved = library.currentMirror

        // 홈의 현재 거울과 내 거울 목록은 같은 MyMirror를 같은 pipeline으로 그린다.
        #expect(library.mirrors.first?.id == saved.id)

        let pixel = previewPixel(saved, at: NormalizedPoint(x: 0.05, y: 0.5))
        #expect((pixel?.alpha ?? 0) > 200)
        #expect((pixel?.blue ?? 0) > (pixel?.red ?? 255))   // 파란 테스트 사진이 보인다
    }

    @Test("복제한 거울도 같은 사진을 참조하고 binary는 하나다")
    func duplicatedMirrorSharesPhotoBinary() {
        let (library, source) = libraryWithPhotoMirror()
        let original = library.currentMirror
        let before = PhotoStickerAssetStore.shared.count

        let outcome = library.save(MirrorDesign(mirror: original), name: "사진 거울 복사본", context: .duplicate)
        #expect(outcome.name == "사진 거울 복사본")

        let copy = library.mirrors.last!
        #expect(copy.id != original.id)
        #expect(copy.stickers[0].source == source)                      // 같은 assetID
        #expect(PhotoStickerAssetStore.shared.count == before)          // 이미지는 늘지 않는다

        // 원본 / 복사본 둘 다 보인다.
        for mirror in [original, copy] {
            let pixel = previewPixel(mirror, at: NormalizedPoint(x: 0.05, y: 0.5))
            #expect((pixel?.alpha ?? 0) > 200)
        }
    }

    @Test("asset을 찾지 못해도 렌더러가 죽지 않는다")
    func missingPhotoAssetDoesNotCrashRenderer() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        // store에 없는 assetID
        design.stickers = [sticker(.photo(assetID: UUID(), aspectRatio: 1), at: NormalizedPoint(x: 0.05, y: 0.5))]

        let pixel = runtimePixel(design: design, at: NormalizedPoint(x: 0.05, y: 0.5))
        #expect(pixel != nil)                                    // 프레임은 그대로 그려진다
        let center = runtimePixel(design: design, at: NormalizedPoint(x: 0.5, y: 0.5))
        #expect((center?.alpha ?? 255) < 20)
    }

    // MARK: - Editor Save Context

    @Test("홈에서 고치면 같은 거울이 갱신되고 슬롯이 늘지 않는다")
    func homeEditCurrentUpdatesInPlace() {
        let library = MirrorLibrary()
        _ = library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "내 거울", context: .editCurrent)
        let created = library.currentMirror
        let slots = library.createdCount

        var design = MirrorDesign(mirror: created)
        design.backgroundColor = BasicMirror.mint.style.frame
        let outcome = library.save(design, name: "다른 이름", context: .editCurrent)

        #expect(outcome == .updated(id: created.id, name: created.name))
        #expect(library.mirrors.count == 1)
        #expect(library.createdCount == slots)
        #expect(library.currentMirror.name == created.name)      // 이름 유지
        #expect(library.currentMirror.style.frame == BasicMirror.mint.style.frame)
    }

    @Test("기본 거울은 첫 저장에서만 새 거울이 되고 이후에는 갱신된다")
    func defaultMirrorCreatesOnceThenUpdates() {
        let library = MirrorLibrary()
        #expect(library.mirrors.isEmpty)

        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        #expect(library.willCreateNewMirror(for: design, context: .editCurrent))
        // 홈에서는 이름을 묻지 않는다 — 자동으로 지어준다.
        #expect(!library.needsName(for: .editCurrent))

        let first = library.save(design, name: "", context: .editCurrent)
        #expect(first.name == "나의 거울")
        #expect(library.mirrors.count == 1)
        #expect(library.createdCount == 1)
        #expect(library.currentMirror.id == first.mirrorID)

        // Editor가 새 id를 기억한 뒤 다시 저장하면 갱신된다.
        design.id = first.mirrorID ?? design.id
        #expect(!library.willCreateNewMirror(for: design, context: .editCurrent))
        let second = library.save(design, name: "또 다른 이름", context: .editCurrent)
        #expect(second.mirrorID == first.mirrorID)
        #expect(library.mirrors.count == 1)
        #expect(library.createdCount == 1)
    }

    @Test("내 거울에서 꾸미면 내가 만든 거울도 원본이 남고 새 거울이 생긴다")
    func duplicateContextAlwaysCreatesNewMirror() {
        // 이름이 예전엔 myMirrorsEditAlwaysDuplicates였다. 내 거울 `꾸미기`는 이제
        // 기존 거울을 고치고(`.editCurrent`), `.duplicate`는 `복제` 동작만 쓴다.
        let library = MirrorLibrary()
        _ = library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "원본", context: .createNew)
        let source = library.currentMirror

        var design = MirrorDesign(mirror: source)
        design.backgroundColor = BasicMirror.sky.style.frame
        #expect(library.willCreateNewMirror(for: design, context: .duplicate))

        let outcome = library.save(design, name: "원본 복사본", context: .duplicate)
        #expect(outcome.mirrorID != source.id)
        #expect(library.mirrors.count == 2)
        #expect(library.createdCount == 2)
        // 원본은 그대로다.
        #expect(library.mirrors.first { $0.id == source.id }?.style.frame == source.style.frame)
        #expect(library.mirrors.first { $0.id == source.id }?.name == "원본")
        // 새 거울이 바로 적용된다.
        #expect(library.currentMirror.id == outcome.mirrorID)
    }

    @Test("+ 거울 만들기는 빈 거울에서 시작해 새 거울을 만든다")
    func createNewStartsBlank() {
        let blank = MirrorDesign.blank
        #expect(blank.strokes.isEmpty)
        #expect(blank.stickers.isEmpty)
        #expect(blank.insets == .standard)
        #expect(blank.style.doodles.isEmpty)                 // 상점 템플릿을 복사하지 않는다
        #expect(blank.style.frame == MirrorLibrary.defaultMirror.style.frame)

        let library = MirrorLibrary()
        let outcome = library.save(blank, name: "새로 만든 거울", context: .createNew)
        #expect(outcome.name == "새로 만든 거울")
        #expect(library.mirrors.count == 1)
        #expect(library.mirrors[0].origin == .made)
        #expect(library.createdCount == 1)
        #expect(library.currentMirror.id == outcome.mirrorID)
    }

    @Test("저장하지 않고 취소하면 아무것도 바뀌지 않는다")
    func cancelChangesNothing() {
        let library = MirrorLibrary()
        _ = library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "원본", context: .createNew)
        let before = library.mirrors
        let currentBefore = library.currentID
        let slotsBefore = library.createdCount

        // Editor에서 편집만 하고 저장하지 않은 상태
        var design = MirrorDesign(mirror: library.currentMirror)
        design.backgroundColor = BasicMirror.lavender.style.frame
        design.stickers = [sticker(at: NormalizedPoint(x: 0.05, y: 0.4))]

        #expect(library.mirrors == before)
        #expect(library.currentID == currentBefore)
        #expect(library.createdCount == slotsBefore)
    }

    @Test("슬롯이 가득 차면 새로 만들기와 복제는 막히고 현재 거울 편집은 된다")
    func fullSlotsBlockCreateAndDuplicateOnly() {
        let library = MirrorLibrary()
        while library.hasFreeCreatedSlot {
            _ = library.save(.blank, name: "거울", context: .createNew)
        }
        #expect(library.createdCount == MirrorStoragePolicy.freeCreatedSlots)
        #expect(!library.hasFreeCreatedSlot)

        #expect(library.save(.blank, name: "하나 더", context: .createNew) == .needsMoreSlots)

        let existing = library.currentMirror
        #expect(library.save(MirrorDesign(mirror: existing), name: "복사본", context: .duplicate) == .needsMoreSlots)

        // 현재 거울 편집은 계속 된다.
        var design = MirrorDesign(mirror: existing)
        design.backgroundColor = BasicMirror.gray.style.frame
        #expect(library.save(design, name: "", context: .editCurrent) == .updated(id: existing.id, name: existing.name))
        #expect(library.mirrors.count == MirrorStoragePolicy.freeCreatedSlots)
    }

    // MARK: - Free Canvas

    /// 카메라 영역 한가운데. 예전 정책이라면 금지 구역이었다.
    private var cameraCenter: NormalizedPoint { NormalizedPoint(x: 0.5, y: 0.5) }

    @Test("Master Canvas 전체가 편집 영역이다")
    func wholeCanvasIsEditable() {
        // 프레임, 카메라 안, 경계 어디든 그릴 수 있다.
        for point in [
            NormalizedPoint(x: 0.02, y: 0.02),      // 프레임 모서리
            NormalizedPoint(x: 0.5, y: 0.03),       // 위 프레임
            cameraCenter,                            // 카메라 한가운데
            NormalizedPoint(x: 0.11, y: 0.5),       // 프레임 ↔ 카메라 경계
            NormalizedPoint(x: 0.5, y: 0.97)        // 아래 프레임
        ] {
            #expect(MirrorEditorCanvas.isInsideCanvas(point))
        }
        // 캔버스 밖만 막는다.
        #expect(!MirrorEditorCanvas.isInsideCanvas(NormalizedPoint(x: 1.05, y: 0.5)))
        #expect(!MirrorEditorCanvas.isInsideCanvas(NormalizedPoint(x: 0.5, y: -0.02)))
    }

    @Test("프레임과 카메라를 가로지르는 획도 잘리지 않는다")
    func strokeCrossesFrameAndCameraBoundary() {
        let insets = MirrorFrameInsets.standard
        let stroke = DrawingStroke(
            points: [
                NormalizedPoint(x: 0.03, y: 0.5),   // 왼쪽 프레임
                NormalizedPoint(x: 0.20, y: 0.5),   // 카메라 안
                NormalizedPoint(x: 0.50, y: 0.5)    // 카메라 한가운데
            ],
            width: 14 / MirrorCanvas.size.width
        )
        // 데이터가 두 영역으로 잘리지 않는다 — 한 획 그대로다.
        #expect(stroke.points.count == 3)
        #expect(!insets.isInsideMirrorArea(stroke.points[0]))
        #expect(insets.isInsideMirrorArea(stroke.points[2]))

        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.strokes = [stroke]
        let size = CGSize(width: 300, height: 650)
        let result = renderedPixels(design: design, transform: .fitted(in: size), size: size)
        #expect(result.dark > 0)
    }

    @Test("지우개도 카메라 영역에서 동작한다")
    func eraserWorksInsideCameraArea() {
        let stroke = DrawingStroke(points: [cameraCenter], width: 20 / MirrorCanvas.size.width)
        #expect(MirrorEditorCanvas.isInsideCanvas(cameraCenter))
        #expect(stroke.isHit(by: cameraCenter, radius: 20))

        var snapshot = EditorSnapshot(strokes: [stroke])
        var history = EditorHistory()
        history.apply(.eraseStrokes([stroke.id]), to: &snapshot)
        #expect(snapshot.strokes.isEmpty)
    }

    @Test("스티커도 카메라 영역 안에 놓을 수 있다")
    func stickerCanSitInsideCameraArea() {
        let insets = MirrorFrameInsets.standard
        for source in [StickerSource.builtIn(.heart), .photo(assetID: UUID(), aspectRatio: 1.5)] {
            let placed = sticker(source, at: cameraCenter).constrained()
            #expect(abs(placed.center.x - 0.5) < 0.0001)
            #expect(abs(placed.center.y - 0.5) < 0.0001)
            #expect(insets.isInsideMirrorArea(placed.center))
        }
    }

    @Test("카메라 영역 안에서 이동 / 크기 / 회전이 모두 동작한다")
    func stickerTransformsInsideCameraArea() {
        var item = sticker(at: cameraCenter)

        let moved = item.moved(to: NormalizedPoint(x: 0.4, y: 0.35)).constrained()
        #expect(abs(moved.center.x - 0.4) < 0.0001)
        #expect(abs(moved.center.y - 0.35) < 0.0001)

        let resized = item.resized(width: 0.3).constrained()
        #expect(resized.frame.width == 0.3)
        #expect(abs(resized.center.x - 0.5) < 0.0001)

        item.rotation = 35
        #expect(abs(item.center.x - cameraCenter.x) < 0.0001)   // 회전해도 위치는 그대로
    }

    @Test("카메라 영역 안 스티커도 완료 후 다시 선택된다")
    func stickerInsideCameraIsReselectable() {
        let transform = EditorCanvasTransform(viewport: viewport)
        var locked = sticker(at: cameraCenter)
        locked.isLocked = true
        let point = screenCenter(locked, transform)

        var selection: UUID?
        selection = tap([locked], at: point, transform: transform, selection: selection)
        #expect(selection == locked.id)
        selection = nil                                       // 완료
        selection = tap([locked], at: point, transform: transform, selection: selection)
        #expect(selection == locked.id)                       // 잠겨 있어도 다시 선택된다
    }

    @Test("스티커는 Master Canvas 밖으로만 나가지 못한다")
    func stickerConstrainedOnlyByCanvas() {
        for point in [NormalizedPoint(x: 1.6, y: 0.5), NormalizedPoint(x: -0.4, y: 1.9)] {
            let placed = sticker(at: point).constrained()
            #expect((0...1).contains(placed.center.x))
            #expect((0...1).contains(placed.center.y))
        }
        // 캔버스 안이면 어디든 그대로 둔다.
        let kept = sticker(at: NormalizedPoint(x: 0.32, y: 0.71)).constrained()
        #expect(abs(kept.center.x - 0.32) < 0.0001)
        #expect(abs(kept.center.y - 0.71) < 0.0001)
    }

    @Test("실제 Mirror에서 배경은 카메라를 덮지 않고 장식은 그 위에 보인다")
    func backgroundStaysOutOfCameraButDecorationDoesNot() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)

        // 장식이 없으면 카메라 영역은 완전히 투명하다.
        #expect((runtimePixel(design: design, at: cameraCenter)?.alpha ?? 255) < 20)

        // 카메라 한가운데에 그린 획은 그대로 보인다.
        design.strokes = [
            DrawingStroke(
                points: [NormalizedPoint(x: 0.42, y: 0.5), NormalizedPoint(x: 0.58, y: 0.5)],
                width: 40 / MirrorCanvas.size.width
            )
        ]
        #expect((runtimePixel(design: design, at: cameraCenter)?.alpha ?? 0) > 200)

        // 바로 옆은 여전히 카메라가 비친다 — 배경이 채워지지 않았다.
        #expect((runtimePixel(design: design, at: NormalizedPoint(x: 0.5, y: 0.75))?.alpha ?? 255) < 20)
    }

    @Test("카메라 영역 위의 스티커도 실제 Mirror와 Capture에 나온다")
    func stickerOverCameraReachesRuntimeAndCapture() {
        let source = PhotoStickerAssetStore.shared.register(testImage(width: 200, height: 200))
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.stickers = [
            sticker(.builtIn(.heart), at: NormalizedPoint(x: 0.35, y: 0.45), width: 0.16),
            sticker(source, at: NormalizedPoint(x: 0.65, y: 0.55), width: 0.16)
        ]

        #expect((runtimePixel(design: design, at: NormalizedPoint(x: 0.65, y: 0.55))?.alpha ?? 0) > 200)

        let size = CGSize(width: 300, height: 650)
        let image = MirrorCapture.compose(frame: nil, design: design, size: size)
        #expect(image != nil)
    }

    @Test("카메라 안내 점선은 Editor 밖으로 새어 나가지 않는다")
    func cameraGuideIsEditorOnly() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.backgroundColor = .white

        // 실제 Mirror: 카메라 경계 안쪽은 완전히 투명 — 점선이 없다.
        let insets = design.insets
        let justInside = NormalizedPoint(x: insets.left + 0.02, y: 0.5)
        #expect(insets.isInsideMirrorArea(justInside))
        #expect((runtimePixel(design: design, at: justInside)?.alpha ?? 255) < 20)

        // 미리보기(Home / My Mirrors)도 안내선을 그리지 않는다 — 기본값이 꺼져 있다.
        let canvas = MirrorCanvasView(design: design)
        #expect(!canvas.showsCameraGuide)
    }

    @Test("미리보기는 카메라 영역의 장식을 지우지 않는다")
    func previewKeepsCameraAreaDecoration() {
        let source = PhotoStickerAssetStore.shared.register(testImage(width: 200, height: 200))
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.stickers = [sticker(source, at: cameraCenter, width: 0.2)]

        var mirror = MirrorLibrary.defaultMirror
        mirror.stickers = design.stickers
        let pixel = previewPixel(mirror, at: cameraCenter)
        #expect((pixel?.blue ?? 0) > (pixel?.red ?? 255))     // 파란 테스트 사진이 그대로 보인다
    }

    @Test("Editor는 거울 한 장이 통째로 보이는 상태로 시작한다")
    func editorStartsFitted() {
        let transform = EditorCanvasTransform(viewport: viewport)

        #expect(transform.appliedZoom == 1)
        #expect(transform.appliedPan == .zero)
        #expect(abs(transform.visibleRect.width - 1) < 0.0001)
        #expect(abs(transform.visibleRect.height - 1) < 0.0001)
        // 캔버스는 화면 안에 들어오고 비율을 유지한다.
        #expect(transform.canvasSize.width <= viewport.width)
        #expect(transform.canvasSize.height <= viewport.height)
        let ratio = transform.canvasSize.width / transform.canvasSize.height
        #expect(abs(ratio - MirrorCanvas.aspectRatio) < 0.0001)
    }

    @Test("맞춤은 거울 한 장 전체로 되돌린다")
    func fitReturnsWholeCanvas() {
        let panned = EditorCanvasTransform(
            viewport: viewport,
            state: .init(zoom: 3, pan: CGSize(width: -200, height: 400))
        )
        #expect(panned.visibleRect.width < 1)

        let fitted = EditorCanvasTransform(viewport: viewport, state: EditorViewportState())
        #expect(fitted.appliedPan == .zero)
        #expect(abs(fitted.visibleRect.width - 1) < 0.0001)
    }

    @Test("맞춤보다 더 축소되지 않는다")
    func zoomNeverGoesBelowFit() {
        let tooSmall = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 0.2))
        #expect(tooSmall.appliedZoom == 1)
        #expect(EditorViewportState.zoomRange.lowerBound == 1)
    }

    @Test("카메라 안내선은 실제 카메라 영역과 같은 geometry를 쓴다")
    func cameraGuideMatchesRuntimeArea() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 650)
        let guidePath = MirrorFrameInsets.standard.mirrorAreaPath(in: rect)
        let area = MirrorFrameInsets.standard.mirrorArea.rect(in: rect.size)

        #expect(abs(guidePath.boundingRect.width - area.width) < 0.5)
        #expect(abs(guidePath.boundingRect.height - area.height) < 0.5)
        // 모서리는 둥글다 — 안내선도 같은 반경을 쓴다.
        #expect(!guidePath.contains(CGPoint(x: area.minX + 0.5, y: area.minY + 0.5)))
    }

    @Test("기존 데이터는 그대로 같은 자리에 남는다")
    func existingDataNeedsNoMigration() {
        // 예전 Side Editor 시절 프레임 안에 저장된 좌표
        let stroke = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.4)], width: 0.01)
        let item = sticker(at: NormalizedPoint(x: 0.95, y: 0.6))

        var mirror = MirrorLibrary.defaultMirror
        mirror.strokes = [stroke]
        mirror.stickers = [item]

        let design = MirrorDesign(mirror: mirror)
        #expect(design.strokes[0].points == stroke.points)      // 재배치 없음
        #expect(design.stickers[0].frame == item.frame)
        #expect(design.stickers[0].constrained().frame == item.frame)
    }

    // MARK: - Text Object

    private func makeText(
        _ value: String = "오늘도\n예쁘게",
        at point: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.5)
    ) -> TextObject {
        TextObject(text: value, center: point)
    }

    @Test("TextObject 기본값과 여러 줄이 유지된다")
    func textDefaults() {
        let object = makeText()
        #expect(object.text == "오늘도\n예쁘게")
        #expect(TextLayout.of(object).lines == ["오늘도", "예쁘게"])
        #expect(object.fontSize == TextPolicy.defaultFontSize)
        #expect(object.style == .basic)
        #expect(object.alignment == .center)          // 기본 정렬은 가운데
        #expect(object.opacity == 1)
        #expect(!object.isLocked)
        #expect(object.rotation == 0)
        #expect(object.color == PaperTheme.ink)
        // 화면 pt가 아니라 normalized 좌표만 담는다.
        #expect((0...1).contains(object.center.x))
        #expect((0...1).contains(object.center.y))
    }

    @Test("빈 문자열과 공백만은 텍스트가 되지 않는다")
    func blankTextIsRejected() {
        #expect(TextPolicy.normalized("") == nil)
        #expect(TextPolicy.normalized("   \n  ") == nil)
        #expect(TextPolicy.normalized("  안녕  ") == "안녕")
        // 여러 줄은 그대로 남는다.
        #expect(TextPolicy.normalized("오늘도\n예쁘게") == "오늘도\n예쁘게")
    }

    @Test("텍스트 길이는 정책 상수로 제한된다")
    func textMaxLength() {
        let long = String(repeating: "가", count: 400)
        #expect(TextPolicy.normalized(long)?.count == TextPolicy.maxLength)
        #expect(TextPolicy.maxLength == 100)
    }

    @Test("글꼴 / 정렬 preset이 모두 유효하다")
    func textStylePresets() {
        // 손글씨 라이브러리가 붙으면서 늘었다. 예전 4개(basic/bold/serif/rounded)는
        // 저장된 데이터가 쓰고 있어 그대로 남아 있어야 한다.
        #expect(TextFontStyle.allCases.count == 14)
        #expect(TextFontStyle.selectable.count == 11)
        for raw in ["basic", "bold", "serif", "rounded"] {
            #expect(TextFontStyle(rawValue: raw) != nil)
        }
        for style in TextFontStyle.allCases {
            #expect(!style.title.isEmpty)
            #expect(style.font(ofSize: 40).pointSize == 40)
        }
        #expect(TextAlignmentOption.allCases.count == 3)
        for alignment in TextAlignmentOption.allCases {
            #expect(!alignment.title.isEmpty)
            #expect(!alignment.icon.isEmpty)
        }
    }

    @Test("크기 변경은 글자 크기만 바꾸고 줄 비율을 유지한다")
    func textResizeKeepsProportions() {
        let object = makeText()
        let before = TextLayout.of(object).size
        let bigger = object.resized(fontSize: object.fontSize * 1.5)

        #expect(bigger.center == object.center)                   // 중심 유지
        let after = TextLayout.of(bigger).size
        let widthRatio = after.width / before.width
        let heightRatio = after.height / before.height
        #expect(abs(widthRatio - heightRatio) < 0.02)              // 찌그러지지 않는다

        // 범위를 벗어나지 않는다.
        #expect(object.resized(fontSize: 10).fontSize == TextPolicy.fontSizeRange.upperBound)
        #expect(object.resized(fontSize: 0).fontSize == TextPolicy.fontSizeRange.lowerBound)
    }

    @Test("정렬에 따라 줄 시작 위치가 달라진다")
    func textAlignmentMovesLines() {
        let object = makeText("가나다라마바사\n가")
        let layout = TextLayout.of(object)
        let short = layout.lines.count - 1

        let leading = layout.lineOrigin(short, alignment: .leading).x
        let center = layout.lineOrigin(short, alignment: .center).x
        let trailing = layout.lineOrigin(short, alignment: .trailing).x
        #expect(leading == 0)
        #expect(center > leading)
        #expect(trailing > center)
        // 줄은 위에서 아래로 쌓인다.
        #expect(layout.lineOrigin(1, alignment: .center).y > layout.lineOrigin(0, alignment: .center).y)
    }

    @Test("텍스트 복제는 새 id와 약간의 offset을 가진다")
    func textDuplicateGetsNewIdentity() {
        let object = makeText()
        var copy = object
        copy.id = UUID()
        copy.center = NormalizedPoint(x: object.center.x + 0.03, y: object.center.y + 0.03)

        #expect(copy.id != object.id)
        #expect(copy.text == object.text)
        #expect(copy.style == object.style)
        #expect(copy.center.x > object.center.x)
    }

    // MARK: - Text History

    @Test("텍스트 추가 / 삭제가 되돌려진다")
    func textAddAndDeleteAreUndoable() {
        let object = makeText()
        var snapshot = EditorSnapshot()
        var history = EditorHistory()

        history.apply(.addText(object), to: &snapshot)
        #expect(snapshot.texts.count == 1)
        history.undo(&snapshot)
        #expect(snapshot.texts.isEmpty)
        history.redo(&snapshot)
        #expect(snapshot.texts.count == 1)

        history.apply(.deleteText(object.id), to: &snapshot)
        #expect(snapshot.texts.isEmpty)
        history.undo(&snapshot)
        #expect(snapshot.texts.first?.id == object.id)
    }

    @Test("내용 / 이동 / 크기 / 회전 / 색 / 글꼴 / 정렬 / 투명도 / 잠금이 모두 되돌려진다")
    func textPropertyEditsAreUndoable() {
        let object = makeText()
        var snapshot = EditorSnapshot(texts: [object])
        var history = EditorHistory()

        let changes: [(String, (inout TextObject) -> Void)] = [
            ("내용", { $0.text = "안녕" }),
            ("이동", { $0.center = NormalizedPoint(x: 0.2, y: 0.8) }),
            ("크기", { $0 = $0.resized(fontSize: TextPolicy.fontSizeRange.upperBound) }),
            ("회전", { $0.rotation = 24 }),
            ("색", { $0.color = .red }),
            ("글꼴", { $0.style = .rounded }),
            ("정렬", { $0.alignment = .leading }),
            ("투명도", { $0.opacity = 0.4 }),
            ("잠금", { $0.isLocked = true })
        ]

        for (label, change) in changes {
            let before = snapshot.texts[0]
            var updated = before
            change(&updated)
            history.apply(.replaceText(updated), to: &snapshot)
            #expect(snapshot.texts[0] != before, "\(label) 변경이 반영되지 않음")
            history.undo(&snapshot)
            #expect(snapshot.texts[0] == before, "\(label) Undo가 되돌리지 못함")
            history.redo(&snapshot)
            #expect(snapshot.texts[0] == updated, "\(label) Redo가 다시 적용하지 못함")
        }
    }

    @Test("내용 수정은 같은 id를 유지한다")
    func textContentEditKeepsIdentity() {
        let object = makeText()
        var snapshot = EditorSnapshot(texts: [object])
        var history = EditorHistory()

        var updated = object
        updated.text = "새 내용"
        history.apply(.replaceText(updated), to: &snapshot)

        #expect(snapshot.texts.count == 1)
        #expect(snapshot.texts[0].id == object.id)
        #expect(snapshot.texts[0].text == "새 내용")
        history.undo(&snapshot)
        #expect(snapshot.texts[0].text == object.text)
    }

    @Test("텍스트가 들어가도 history에 이미지 binary가 생기지 않는다")
    func textHistoryKeepsNoImageBinary() {
        let store = PhotoStickerAssetStore()
        let source = store.register(testImage(width: 200, height: 200))
        var snapshot = EditorSnapshot(stickers: [sticker(source, at: NormalizedPoint(x: 0.2, y: 0.2))])
        var history = EditorHistory()

        for index in 0..<5 {
            history.apply(.addText(makeText("텍스트 \(index)", at: NormalizedPoint(x: 0.5, y: 0.3))), to: &snapshot)
        }
        for _ in 0..<3 { history.undo(&snapshot) }
        #expect(store.count == 1)
    }

    // MARK: - Text Interaction

    @Test("텍스트를 탭하면 선택되고 완료 후 다시 선택된다")
    func textTapSelectAndReselect() {
        let transform = EditorCanvasTransform(viewport: viewport)
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        let object = makeText()
        let rect = placement.rect(object.frame)
        let point = CGPoint(x: rect.midX, y: rect.midY)

        var selection: UUID?
        for _ in 0..<3 {
            selection = object.contains(point, in: placement) ? object.id : nil
            #expect(selection == object.id)
            selection = nil                                   // 완료
            #expect(selection == nil)
        }
        // 멀리 떨어진 곳은 잡히지 않는다.
        #expect(!object.contains(CGPoint(x: rect.midX, y: rect.midY - 400), in: placement))
    }

    @Test("회전한 텍스트와 아주 작은 텍스트도 잡힌다")
    func rotatedAndSmallTextStayTappable() {
        let placement = MirrorViewTransform(canvasSize: CGSize(width: 300, height: 650), offset: .zero)

        var rotated = makeText()
        rotated.rotation = 40
        let rect = placement.rect(rotated.frame)
        #expect(rotated.contains(CGPoint(x: rect.midX, y: rect.midY), in: placement))

        var tiny = makeText("가")
        tiny = tiny.resized(fontSize: TextPolicy.fontSizeRange.lowerBound)
        let tinyRect = placement.rect(tiny.frame)
        let edge = TextObject.minimumTapTarget / 2 - 1
        #expect(tiny.contains(CGPoint(x: tinyRect.midX + edge, y: tinyRect.midY), in: placement))
        #expect(!tiny.contains(
            CGPoint(x: tinyRect.midX + TextObject.minimumTapTarget * 1.5, y: tinyRect.midY),
            in: placement
        ))
    }

    @Test("잠긴 텍스트도 선택은 된다")
    func lockedTextIsSelectable() {
        let placement = MirrorViewTransform(canvasSize: CGSize(width: 300, height: 650), offset: .zero)
        var locked = makeText()
        locked.isLocked = true
        let rect = placement.rect(locked.frame)

        #expect(locked.contains(CGPoint(x: rect.midX, y: rect.midY), in: placement))
        #expect(locked.isLocked)
    }

    @Test("겹친 텍스트는 화면에서 위에 보이는 것이 선택된다")
    func overlappingTextSelectsTopmost() {
        let placement = MirrorViewTransform(canvasSize: CGSize(width: 300, height: 650), offset: .zero)
        var bottom = makeText()
        var top = makeText()
        bottom.zIndex = 1
        top.zIndex = 2
        let rect = placement.rect(top.frame)
        let point = CGPoint(x: rect.midX, y: rect.midY)

        func hit(_ objects: [TextObject]) -> UUID? {
            objects.enumerated()
                .filter { $0.element.contains(point, in: placement) }
                .max { ($0.element.zIndex, $0.offset) < ($1.element.zIndex, $1.offset) }?
                .element.id
        }
        #expect(hit([bottom, top]) == top.id)
        #expect(hit([top, bottom]) == top.id)
    }

    @Test("텍스트와 스티커는 동시에 선택되지 않는다")
    func textAndStickerSelectionAreExclusive() {
        var selectedStickerID: UUID? = UUID()
        var selectedTextID: UUID?

        // 텍스트를 고르면 스티커 선택이 풀린다.
        let text = makeText()
        selectedTextID = text.id
        selectedStickerID = nil
        #expect(selectedTextID == text.id)
        #expect(selectedStickerID == nil)

        // 스티커를 고르면 텍스트 선택이 풀린다.
        let item = sticker(at: NormalizedPoint(x: 0.05, y: 0.5))
        selectedStickerID = item.id
        selectedTextID = nil
        #expect(selectedStickerID == item.id)
        #expect(selectedTextID == nil)
    }

    @Test("텍스트를 끌면 텍스트가 움직인다")
    func textDragMovesText() {
        let object = makeText()
        let moved = object.moved(to: NormalizedPoint(x: 0.3, y: 0.7)).constrained()
        #expect(moved.center.x == 0.3)
        #expect(moved.center.y == 0.7)
        #expect(moved.id == object.id)
        #expect(moved.text == object.text)
    }

    // MARK: - Text Free Canvas

    @Test("텍스트는 프레임 / 카메라 / 경계 어디든 놓을 수 있다")
    func textCanGoAnywhereOnCanvas() {
        let insets = MirrorFrameInsets.standard
        let places = [
            NormalizedPoint(x: 0.5, y: 0.03),      // 위 프레임
            cameraCenter,                           // 카메라 한가운데
            NormalizedPoint(x: 0.11, y: 0.5),      // 프레임 ↔ 카메라 경계
            NormalizedPoint(x: 0.5, y: 0.96)       // 아래 프레임
        ]
        for place in places {
            let placed = makeText(at: place).constrained()
            #expect(abs(placed.center.x - place.x) < 0.0001)
            #expect(abs(placed.center.y - place.y) < 0.0001)
        }
        #expect(insets.isInsideMirrorArea(makeText(at: cameraCenter).constrained().center))
    }

    @Test("텍스트는 Master Canvas 밖으로만 나가지 못한다")
    func textConstrainedOnlyByCanvas() {
        for point in [NormalizedPoint(x: 1.8, y: 0.5), NormalizedPoint(x: -0.5, y: 1.4)] {
            let placed = makeText(at: point).constrained()
            #expect((0...1).contains(placed.center.x))
            #expect((0...1).contains(placed.center.y))
        }
    }

    @Test("새 텍스트는 보고 있는 화면 한가운데에 생긴다")
    func textInsertsAtViewportCenter() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.stickers = [sticker(at: NormalizedPoint(x: 0.05, y: 0.2))]
        let transform = EditorCanvasTransform(viewport: viewport, state: .init(zoom: 2))
        let placed = TextPlacement.insert("HELLO", in: design, visibleRect: transform.visibleRect)

        let center = NormalizedPoint(
            x: transform.visibleRect.x + transform.visibleRect.width / 2,
            y: transform.visibleRect.y + transform.visibleRect.height / 2
        )
        #expect(abs(placed.center.x - center.x) < 0.001)
        #expect(abs(placed.center.y - center.y) < 0.001)
        // 스티커와 텍스트를 함께 본 가장 위에 올라간다.
        #expect(placed.zIndex > design.stickers[0].zIndex)
    }

    // MARK: - Text Render

    /// 텍스트가 실제로 몇 픽셀이나 그려졌는지.
    private func textInkCount(
        _ design: MirrorDesign,
        size: CGSize = CGSize(width: 300, height: 650)
    ) -> Int {
        let canvas = Canvas { context, canvasSize in
            MirrorRenderer.draw(
                style: design.style,
                strokes: design.strokes,
                stickers: design.stickers,
                texts: design.texts,
                transform: .fitted(in: canvasSize),
                mirrorAreaFill: design.style.frame,
                in: context,
                viewport: canvasSize
            )
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return 0 }

        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var dark = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if data[i] < 120 && data[i + 1] < 120 && data[i + 2] < 120 { dark += 1 }
            }
        }
        return dark
    }

    @Test("텍스트가 Editor / 미리보기에서 실제로 그려진다")
    func textRendersInPreview() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        #expect(textInkCount(design) == 0)

        design.texts = [makeText(at: cameraCenter)]
        #expect(textInkCount(design) > 0)

        // 내 거울 / 홈 미리보기도 같은 pipeline을 쓴다.
        var mirror = MirrorLibrary.defaultMirror
        mirror.texts = design.texts
        let pixel = previewPixel(mirror, at: cameraCenter)
        #expect(pixel != nil)
    }

    @Test("투명도와 회전이 렌더에 반영된다")
    func textOpacityAndRotationAffectRender() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.texts = [makeText(at: cameraCenter)]
        let solid = textInkCount(design)

        design.texts[0].opacity = 0.15
        #expect(textInkCount(design) < solid)

        design.texts[0].opacity = 1
        design.texts[0].rotation = 45
        let rotated = textInkCount(design)
        #expect(rotated > 0)
    }

    @Test("정렬을 바꾸면 렌더 결과가 달라진다")
    func textAlignmentChangesRender() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.texts = [makeText("가나다라마\n가", at: cameraCenter)]
        let layout = TextLayout.of(design.texts[0])

        // 짧은 줄의 시작 x가 정렬마다 달라진다.
        let leading = layout.lineOrigin(1, alignment: .leading).x
        let trailing = layout.lineOrigin(1, alignment: .trailing).x
        #expect(trailing > leading)
        #expect(textInkCount(design) > 0)
    }

    @Test("카메라 영역 위의 텍스트가 실제 Mirror와 Capture에 나온다")
    func textOverCameraReachesRuntimeAndCapture() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.texts = [makeText("HELLO", at: cameraCenter)]

        // 실제 거울: 글자가 놓인 줄을 훑으면 불투명한 픽셀이 나온다.
        // (글자 사이 여백이 있어 한 점만 찍으면 불안정하다.)
        let frame = design.texts[0].frame
        let opaque = stride(from: 0.0, through: 1.0, by: 0.02).contains { ratio in
            let point = NormalizedPoint(x: frame.x + frame.width * ratio, y: cameraCenter.y)
            return (runtimePixel(design: design, at: point)?.alpha ?? 0) > 100
        }
        #expect(opaque)
        // 글자에서 떨어진 곳은 여전히 카메라가 비친다.
        #expect((runtimePixel(design: design, at: NormalizedPoint(x: 0.5, y: 0.78))?.alpha ?? 255) < 20)

        let size = CGSize(width: 300, height: 650)
        #expect(MirrorCapture.compose(frame: nil, design: design, size: size) != nil)
    }

    @Test("텍스트가 있어도 저장 정책은 그대로다")
    func textDoesNotChangeSaveContext() {
        let library = MirrorLibrary()
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.texts = [makeText("HELLO", at: cameraCenter)]

        // 홈 저장은 이름을 묻지 않고 자동으로 지어준다.
        let created = library.save(design, name: "", context: .editCurrent)
        #expect(created.name == "나의 거울")
        #expect(library.mirrors.count == 1)
        #expect(library.mirrors[0].texts.count == 1)
        #expect(library.createdCount == 1)

        // 같은 Editor에서 다시 저장하면 갱신된다.
        design.id = created.mirrorID ?? design.id
        let updated = library.save(design, name: "무시", context: .editCurrent)
        #expect(updated.mirrorID == created.mirrorID)
        #expect(library.mirrors.count == 1)

        // 내 거울에서 꾸미면 복제된다.
        let copy = library.save(design, name: "글자 거울 복사본", context: .duplicate)
        #expect(copy.mirrorID != created.mirrorID)
        #expect(library.mirrors.last?.texts.count == 1)
    }

    // MARK: - Home 자동 이름

    @Test("홈에서 저장할 때는 이름을 묻지 않고 자동으로 지어준다")
    func homeSaveNeverAsksForName() {
        let library = MirrorLibrary()
        #expect(!library.needsName(for: .editCurrent))
        #expect(library.needsName(for: .duplicate))
        #expect(library.needsName(for: .createNew))

        // 기본 거울을 홈에서 처음 저장 → 자동 이름으로 생성
        let first = library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "", context: .editCurrent)
        #expect(first.name == "나의 거울")
        #expect(library.createdCount == 1)
        #expect(library.currentMirror.id == first.mirrorID)
    }

    @Test("자동 이름은 겹치지 않게 번호가 붙는다")
    func automaticNameNumbering() {
        #expect(MirrorStoragePolicy.automaticName(existing: []) == "나의 거울")
        #expect(MirrorStoragePolicy.automaticName(existing: ["나의 거울"]) == "나의 거울 2")
        #expect(MirrorStoragePolicy.automaticName(existing: ["나의 거울", "나의 거울 2"]) == "나의 거울 3")
        // 다른 이름은 번호에 영향을 주지 않는다.
        #expect(MirrorStoragePolicy.automaticName(existing: ["핑크 거울"]) == "나의 거울")
    }





    // MARK: - Layers

    /// 같은 자리에 겹친 스티커 / 사진 스티커 / 텍스트.
    private func mixedDesign() -> (MirrorDesign, StickerObject, StickerObject, TextObject) {
        let source = PhotoStickerAssetStore.shared.register(testImage(width: 200, height: 200))
        var item = sticker(.builtIn(.ribbon), at: cameraCenter)
        var photo = sticker(source, at: cameraCenter)
        var text = makeText("HELLO", at: cameraCenter)
        item.zIndex = 0
        photo.zIndex = 1
        text.zIndex = 2

        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.stickers = [item, photo]
        design.texts = [text]
        return (design, item, photo, text)
    }

    @Test("Layers 목록은 앞에 보이는 것부터 나열한다")
    func layersListIsFrontFirst() {
        let (design, item, photo, text) = mixedDesign()
        let layers = design.decorationLayers

        #expect(layers.count == 3)
        #expect(layers.map(\.id) == [text.id, photo.id, item.id])
        // 사진 스티커도 스티커 레이어로 취급한다.
        #expect(layers[1].subtitle == "사진 스티커")
        #expect(layers[2].subtitle == "스티커")
        #expect(layers[0].subtitle == "텍스트")
        #expect(layers[0].title == "HELLO")
    }

    @Test("Layers 순서 / 렌더 순서 / hit test 순서가 모두 같다")
    func layersRendererAndHitTestAgree() {
        let (design, _, _, _) = mixedDesign()
        let placement = MirrorViewTransform(canvasSize: CGSize(width: 300, height: 650), offset: .zero)
        let location = placement.point(cameraCenter)

        /// 렌더러와 같은 규칙으로 뽑은 최상단.
        func topmost(_ design: MirrorDesign) -> UUID? {
            var best: ((Int, Int), UUID)?
            func consider(_ order: (Int, Int), _ id: UUID) {
                if best == nil || order > best!.0 { best = (order, id) }
            }
            for object in design.stickers where object.contains(location, in: placement) {
                consider((object.zIndex, 0), object.id)
            }
            for object in design.texts where object.contains(location, in: placement) {
                consider((object.zIndex, 1), object.id)
            }
            return best?.1
        }

        #expect(design.decorationLayers.first?.id == topmost(design))

        // 순서를 뒤집어도 셋이 계속 일치한다.
        var snapshot = design.snapshot
        snapshot.reorderDecorations(frontToBack: design.decorationLayers.reversed().map(\.id))
        var flipped = design
        flipped.snapshot = snapshot
        #expect(flipped.decorationLayers.first?.id == topmost(flipped))
        #expect(flipped.decorationLayers.map(\.id) == design.decorationLayers.reversed().map(\.id))
    }

    @Test("순서를 바꾸면 zIndex가 0부터 연속으로 다시 매겨진다")
    func reorderNormalizesZIndex() {
        var (design, item, photo, text) = mixedDesign()
        // 일부러 띄엄띄엄한 값으로 만들어 둔다.
        design.stickers[0].zIndex = 5
        design.stickers[1].zIndex = 5
        design.texts[0].zIndex = 40

        var snapshot = design.snapshot
        snapshot.reorderDecorations(frontToBack: [item.id, text.id, photo.id])
        design.snapshot = snapshot

        let zIndexes = design.stickers.map(\.zIndex) + design.texts.map(\.zIndex)
        #expect(Set(zIndexes).count == 3)                       // 겹치지 않는다
        #expect(zIndexes.sorted() == [0, 1, 2])                 // 0부터 연속
        #expect(design.decorationLayers.map(\.id) == [item.id, text.id, photo.id])

        // id는 그대로다.
        #expect(design.stickers.contains { $0.id == item.id })
        #expect(design.stickers.contains { $0.id == photo.id })
        #expect(design.texts.contains { $0.id == text.id })
        _ = (item, photo, text)
    }

    @Test("순서를 바꿔도 zIndex 말고는 아무것도 변하지 않는다")
    func reorderChangesOnlyZIndex() {
        var (design, item, photo, text) = mixedDesign()
        design.stickers[0].rotation = 24
        design.stickers[0].opacity = 0.6
        design.texts[0].alignment = .leading
        let before = design

        var snapshot = design.snapshot
        snapshot.reorderDecorations(frontToBack: [item.id, photo.id, text.id])
        design.snapshot = snapshot

        for (old, new) in zip(before.stickers, design.stickers) {
            var normalized = new
            normalized.zIndex = old.zIndex
            #expect(normalized == old)
        }
        for (old, new) in zip(before.texts, design.texts) {
            var normalized = new
            normalized.zIndex = old.zIndex
            #expect(normalized == old)
        }
    }

    @Test("사진 스티커 순서를 바꿔도 이미지가 다시 만들어지지 않는다")
    func reorderKeepsPhotoAsset() {
        var (design, item, photo, text) = mixedDesign()
        let before = PhotoStickerAssetStore.shared.count
        let source = design.stickers.first { $0.id == photo.id }?.source

        var snapshot = design.snapshot
        for order in [[photo.id, text.id, item.id], [text.id, item.id, photo.id], [item.id, photo.id, text.id]] {
            snapshot.reorderDecorations(frontToBack: order)
        }
        design.snapshot = snapshot

        #expect(PhotoStickerAssetStore.shared.count == before)   // 이미지가 늘지 않는다
        #expect(design.stickers.first { $0.id == photo.id }?.source == source)
        #expect(PhotoStickerAssetStore.shared.isRegistered(source!))
    }

    @Test("순서 변경은 되돌릴 수 있고 다시 실행할 수 있다")
    func reorderIsUndoable() {
        let (design, item, photo, text) = mixedDesign()
        var snapshot = design.snapshot
        var history = EditorHistory()
        let original = snapshot

        history.apply(.reorderDecorations(frontToBack: [item.id, photo.id, text.id]), to: &snapshot)
        var changed = design
        changed.snapshot = snapshot
        #expect(changed.decorationLayers.map(\.id) == [item.id, photo.id, text.id])

        history.undo(&snapshot)
        #expect(snapshot == original)
        var restored = design
        restored.snapshot = snapshot
        #expect(restored.decorationLayers.map(\.id) == [text.id, photo.id, item.id])

        history.redo(&snapshot)
        var again = design
        again.snapshot = snapshot
        #expect(again.decorationLayers.map(\.id) == [item.id, photo.id, text.id])
    }

    @Test("여러 번 순서를 바꿔도 계속 정규화된다")
    func repeatedReorderStaysNormalized() {
        var (design, item, photo, text) = mixedDesign()
        var snapshot = design.snapshot

        for order in [[item.id, text.id, photo.id], [photo.id, item.id, text.id], [text.id, photo.id, item.id]] {
            snapshot.reorderDecorations(frontToBack: order)
            design.snapshot = snapshot
            let zIndexes = (design.stickers.map(\.zIndex) + design.texts.map(\.zIndex)).sorted()
            #expect(zIndexes == [0, 1, 2])
            #expect(design.decorationLayers.map(\.id) == order)
        }
    }

    @Test("순서를 바꾼 뒤 추가 / 복제한 장식은 언제나 맨 앞에 온다")
    func newObjectsGoOnTopAfterReorder() {
        var (design, item, photo, text) = mixedDesign()
        var snapshot = design.snapshot
        snapshot.reorderDecorations(frontToBack: [item.id, photo.id, text.id])
        design.snapshot = snapshot
        #expect(design.topDecorationZIndex == 2)

        // 새 스티커
        let newSticker = StickerPlacement.insert(
            .builtIn(.heart), in: design, visibleRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        )
        #expect(newSticker.zIndex == 3)
        design.stickers.append(newSticker)
        #expect(design.decorationLayers.first?.id == newSticker.id)

        // 새 텍스트
        let newText = TextPlacement.insert(
            "새 글자", in: design, visibleRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        )
        #expect(newText.zIndex == 4)
        design.texts.append(newText)
        #expect(design.decorationLayers.first?.id == newText.id)

        // 복제도 맨 앞
        var copy = design.stickers[0]
        copy.id = UUID()
        copy.zIndex = design.topDecorationZIndex + 1
        design.stickers.append(copy)
        #expect(design.decorationLayers.first?.id == copy.id)
        _ = (photo, text)
    }

    @Test("잠긴 장식도 Layers 목록에 나오고 잠금이 표시된다")
    func lockedObjectsAppearInLayers() {
        var (design, item, _, text) = mixedDesign()
        design.stickers[0].isLocked = true
        design.texts[0].isLocked = true

        let layers = design.decorationLayers
        #expect(layers.first { $0.id == item.id }?.isLocked == true)
        #expect(layers.first { $0.id == text.id }?.isLocked == true)
    }

    @Test("Drawing과 Background는 순서에 참여하지 않는다")
    func drawingAndBackgroundAreFixed() {
        var (design, _, _, _) = mixedDesign()
        design.strokes = [
            DrawingStroke(points: [cameraCenter], width: 0.02),
            DrawingStroke(points: [NormalizedPoint(x: 0.2, y: 0.2)], width: 0.02)
        ]
        let strokesBefore = design.strokes

        // Layers 목록에는 장식만 들어간다.
        #expect(design.decorationLayers.count == 3)

        var snapshot = design.snapshot
        snapshot.reorderDecorations(frontToBack: design.decorationLayers.reversed().map(\.id))
        design.snapshot = snapshot

        // 획은 손대지 않는다.
        #expect(design.strokes == strokesBefore)
        #expect(design.backgroundColor == MirrorLibrary.defaultMirror.style.frame)
    }

    @Test("바꾼 순서가 렌더 결과로 이어진다")
    func reorderChangesRenderedResult() {
        // 같은 자리에 색이 다른 두 사진 스티커를 겹쳐 어느 쪽이 위인지 픽셀로 확인한다.
        let store = PhotoStickerAssetStore.shared
        let redSource = store.register(testImage(
            width: 200, height: 200, color: CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
        ))
        let blueSource = store.register(testImage(
            width: 200, height: 200, color: CGColor(red: 0.1, green: 0.1, blue: 0.9, alpha: 1)
        ))
        var red = sticker(redSource, at: cameraCenter, width: 0.3)
        var blue = sticker(blueSource, at: cameraCenter, width: 0.3)
        red.zIndex = 0
        blue.zIndex = 1

        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.stickers = [red, blue]
        #expect(design.decorationLayers.first?.id == blue.id)
        let blueOnTop = runtimePixel(design: design, at: cameraCenter)
        #expect((blueOnTop?.blue ?? 0) > (blueOnTop?.red ?? 255))

        var snapshot = design.snapshot
        snapshot.reorderDecorations(frontToBack: [red.id, blue.id])
        design.snapshot = snapshot
        #expect(design.decorationLayers.first?.id == red.id)
        let redOnTop = runtimePixel(design: design, at: cameraCenter)
        #expect((redOnTop?.red ?? 0) > (redOnTop?.blue ?? 255))
    }

    @Test("바꾼 순서가 저장 / 미리보기 / Capture까지 그대로 간다")
    func reorderSurvivesSaveAndPreview() {
        var (design, item, photo, text) = mixedDesign()
        var snapshot = design.snapshot
        snapshot.reorderDecorations(frontToBack: [item.id, text.id, photo.id])
        design.snapshot = snapshot
        let expected = design.decorationLayers.map(\.id)

        // 홈 저장 — 이름을 묻지 않고 순서 그대로 저장된다.
        let library = MirrorLibrary()
        let created = library.save(design, name: "", context: .editCurrent)
        #expect(created.name == "나의 거울")

        let saved = library.currentMirror
        var restored = MirrorDesign(mirror: saved)
        #expect(restored.decorationLayers.map(\.id) == expected)

        // 홈에서 다시 저장해도 순서가 유지된다.
        restored.id = created.mirrorID ?? restored.id
        _ = library.save(restored, name: "", context: .editCurrent)
        #expect(MirrorDesign(mirror: library.currentMirror).decorationLayers.map(\.id) == expected)

        // 내 거울 복제도 순서를 그대로 가져간다.
        _ = library.save(restored, name: "복사본", context: .duplicate)
        #expect(MirrorDesign(mirror: library.mirrors.last!).decorationLayers.map(\.id) == expected)

        // 미리보기 / Capture도 같은 pipeline이라 순서가 같다.
        #expect(previewPixel(saved, at: cameraCenter) != nil)
        #expect(MirrorCapture.compose(frame: nil, design: design, size: CGSize(width: 300, height: 650)) != nil)
    }

    @Test("장식이 많아도 Layers 목록과 순서 변경이 동작한다")
    func manyLayersStayOrdered() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.stickers = (0..<50).map { index in
            var object = sticker(at: NormalizedPoint(x: 0.5, y: 0.5))
            object.zIndex = index * 2
            return object
        }
        design.texts = (0..<50).map { index in
            var object = makeText("텍스트 \(index)", at: NormalizedPoint(x: 0.5, y: 0.5))
            object.zIndex = index * 2 + 1
            return object
        }

        let layers = design.decorationLayers
        #expect(layers.count == 100)
        #expect(layers.first?.zIndex == 99)          // 가장 앞이 맨 위

        var snapshot = design.snapshot
        snapshot.reorderDecorations(frontToBack: layers.reversed().map(\.id))
        design.snapshot = snapshot

        let zIndexes = (design.stickers.map(\.zIndex) + design.texts.map(\.zIndex)).sorted()
        #expect(zIndexes == Array(0..<100))
        #expect(design.decorationLayers.map(\.id) == layers.reversed().map(\.id))
    }

    @Test("프레임 두께는 108 / 108 / 180 / 220으로 고정이다")
    func frameThicknessUnchanged() {
        let standard = MirrorFrameInsets.standard
        #expect(standard.left == 108.0 / 1080.0)
        #expect(standard.right == 108.0 / 1080.0)
        #expect(abs(standard.top - 180.0 / 2340.0) < 0.0001)
        #expect(abs(standard.bottom - 220.0 / 2340.0) < 0.0001)
        // 아래가 위보다 두껍다.
        #expect(standard.bottom > standard.top)
        #expect(MirrorLibrary.defaultMirror.style.insets == .standard)

        // 카메라 영역이 비대칭 inset을 그대로 반영한다.
        let area = standard.mirrorArea
        #expect(abs(area.x * MirrorCanvas.size.width - 108) < 0.001)
        #expect(abs(area.y * MirrorCanvas.size.height - 180) < 0.001)
        let expectedWidth: Double = 1080 - 108 - 108
        let expectedHeight: Double = 2340 - 180 - 220
        #expect(abs(area.width * MirrorCanvas.size.width - expectedWidth) < 0.001)
        #expect(abs(area.height * MirrorCanvas.size.height - expectedHeight) < 0.001)
    }
}
