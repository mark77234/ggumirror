//
//  EditorGestureTests.swift
//  ggumirrorTests
//
//  꾸미기 Editor의 이동 / 그리기 제스처 규칙.
//
//  실기기 피드백은 두 가지였다 — 확대한 뒤 화면을 옮기기 어렵고,
//  그리는 중에 화면을 옮기려면 도구를 껐다 켜야 한다.
//  여기서는 그 규칙(한 손가락이 무엇을 하는가 / 어디까지를 오브젝트로 보는가)을 못 박는다.
//

import Testing
import SwiftUI
@testable import ggumirror

@MainActor
struct EditorGestureTests {

    // MARK: - 도구

    /// 화면 크기와 배율만 주면 그 상태의 변환을 돌려준다.
    private func transform(zoom: CGFloat = 1, pan: CGSize = .zero) -> EditorCanvasTransform {
        EditorCanvasTransform(
            viewport: CGSize(width: 390, height: 620),
            state: EditorViewportState(zoom: zoom, pan: pan)
        )
    }

    private func placement(_ transform: EditorCanvasTransform) -> MirrorViewTransform {
        MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
    }

    private func sticker(
        center: NormalizedPoint,
        width: Double = 0.16,
        locked: Bool = false,
        photo: Bool = false
    ) -> StickerObject {
        let source: StickerSource = photo
            ? .photo(assetID: UUID(), aspectRatio: 1)
            : .builtIn(.heart)
        var object = StickerObject(
            source: source,
            frame: NormalizedRect(
                x: center.x - width / 2,
                y: center.y - width / 2 * MirrorCanvas.aspectRatio,
                width: width,
                height: width * MirrorCanvas.aspectRatio
            ),
            zIndex: 1
        )
        object.isLocked = locked
        return object
    }

    private func design(_ stickers: [StickerObject] = [], texts: [TextObject] = []) -> MirrorDesign {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.stickers = stickers
        design.texts = texts
        return design
    }

    /// 소스에서 규칙을 확인해야 하는 것들(제스처 recognizer 설정 등)을 읽는다.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // ggumirrorTests
            .deletingLastPathComponent()          // 프로젝트 루트
            .appending(path: "ggumirror/Editor/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 1~3. 스티커 / 사진 스티커에서 빈 곳을 끌면 화면이 움직인다

    @Test("스티커 도구에서 빈 곳을 끌면 화면 이동이다")
    func emptyDragPansInStickerTool() {
        let object = sticker(center: NormalizedPoint(x: 0.2, y: 0.2))
        let design = design([object])
        let view = transform()
        // 스티커에서 한참 떨어진 곳.
        let empty = placement(view).rect(object.frame).offsetBy(dx: 200, dy: 200).origin

        let grabbed = design.topSelectableDecoration(
            at: empty, in: placement(view), minimumTapTarget: EditorGesturePolicy.dragTapTarget
        )
        #expect(grabbed == nil)
        #expect(EditorGesturePolicy.oneFingerAction(
            tool: .sticker, drawingMode: .draw, grabbed: grabbed) == .panViewport)
    }

    @Test("스티커 위를 끌면 스티커가 움직인다")
    func stickerDragStillMovesTheSticker() {
        let object = sticker(center: NormalizedPoint(x: 0.5, y: 0.5))
        let design = design([object])
        let view = transform()
        let center = placement(view).rect(object.frame).origin.applying(
            CGAffineTransform(translationX: placement(view).rect(object.frame).width / 2,
                              y: placement(view).rect(object.frame).height / 2)
        )

        let grabbed = design.topSelectableDecoration(
            at: center, in: placement(view), minimumTapTarget: EditorGesturePolicy.dragTapTarget
        )
        #expect(grabbed?.id == object.id)
        #expect(EditorGesturePolicy.oneFingerAction(
            tool: .sticker, drawingMode: .draw, grabbed: grabbed) == .moveObject)
    }

    @Test("사진 스티커도 규칙이 같다")
    func photoStickerFollowsTheSameRule() {
        let object = sticker(center: NormalizedPoint(x: 0.5, y: 0.5), photo: true)
        #expect(object.source.photoAssetID != nil)
        let design = design([object])
        let view = transform()
        let rect = placement(view).rect(object.frame)

        let onObject = design.topSelectableDecoration(
            at: CGPoint(x: rect.midX, y: rect.midY), in: placement(view),
            minimumTapTarget: EditorGesturePolicy.dragTapTarget
        )
        let onEmpty = design.topSelectableDecoration(
            at: CGPoint(x: rect.midX, y: rect.midY - 250), in: placement(view),
            minimumTapTarget: EditorGesturePolicy.dragTapTarget
        )
        #expect(EditorGesturePolicy.oneFingerAction(
            tool: .sticker, drawingMode: .draw, grabbed: onObject) == .moveObject)
        #expect(EditorGesturePolicy.oneFingerAction(
            tool: .sticker, drawingMode: .draw, grabbed: onEmpty) == .panViewport)
    }

    // MARK: - 3'. tap target을 넓히는 건 tap에서만

    @Test("작은 스티커 옆 빈 곳은 끌 때 오브젝트로 잡히지 않는다")
    func dragDoesNotInflateTheHitArea() {
        // 맞춤 배율에서 폭 0.16짜리 스티커는 화면에서 44pt보다 작다.
        let object = sticker(center: NormalizedPoint(x: 0.5, y: 0.5), width: 0.08)
        let design = design([object])
        let view = transform()
        let rect = placement(view).rect(object.frame)
        #expect(rect.width < StickerObject.minimumTapTarget)

        // 보이는 사각형 바로 바깥 — 44pt 확대 범위 안쪽.
        let justOutside = CGPoint(x: rect.midX + rect.width / 2 + 4, y: rect.midY)

        // 제자리 tap은 여기서도 스티커를 고른다(손가락으로 다시 고를 수 있어야 한다).
        #expect(design.topSelectableDecoration(
            at: justOutside, in: placement(view),
            minimumTapTarget: EditorGesturePolicy.selectTapTarget) != nil)
        // 하지만 끌기는 빈 곳으로 본다 — 그래야 옆 여백을 밀 수 있다.
        #expect(design.topSelectableDecoration(
            at: justOutside, in: placement(view),
            minimumTapTarget: EditorGesturePolicy.dragTapTarget) == nil)
    }

    // MARK: - 4~5. 두 손가락 / pinch

    @Test("두 손가락은 도구와 상관없이 화면 이동 / 확대다")
    func twoFingerGesturesAreAlwaysNavigation() throws {
        let gestures = try source("EditorCanvasGestures.swift")
        // 이동 recognizer는 두 손가락 전용이라 오브젝트 위에서 시작해도 화면이 움직인다.
        #expect(gestures.contains("navigate.minimumNumberOfTouches = 2"))
        #expect(gestures.contains("draw.maximumNumberOfTouches = 1"))
        // 두 손가락이 들어오면 진행 중인 한 손가락 입력을 끊는다.
        #expect(gestures.contains("cancelDrawing()"))

        let canvas = try source("MirrorEditorCanvas.swift")
        let navigate = try #require(canvas.range(of: "private func navigate("))
        let body = String(canvas[navigate.lowerBound...].prefix(2000))
        // 두 손가락 경로는 viewport만 바꾼다 — 오브젝트도, history도 건드리지 않는다.
        #expect(!body.contains("draggingSticker ="))
        #expect(!body.contains("resizeSelected"))
        #expect(!body.contains("onEdit("))
    }

    @Test("확대 범위는 1...4 그대로다")
    func zoomRangeIsUnchanged() {
        #expect(EditorViewportState.zoomRange == 1...4)
        // 범위를 벗어나는 값을 넣어도 잘린다.
        #expect(transform(zoom: 8).appliedZoom == 4)
        #expect(transform(zoom: 0.2).appliedZoom == 1)
        // 맞춤은 기본 상태 하나다.
        #expect(EditorViewportState().isFitted)
    }

    // MARK: - 6. 잠긴 오브젝트

    @Test("잠긴 스티커는 끌어도 움직이지 않고 화면이 움직인다")
    func lockedObjectPansInstead() {
        let object = sticker(center: NormalizedPoint(x: 0.5, y: 0.5), locked: true)
        let design = design([object])
        let view = transform()
        let rect = placement(view).rect(object.frame)

        let grabbed = design.topSelectableDecoration(
            at: CGPoint(x: rect.midX, y: rect.midY), in: placement(view),
            minimumTapTarget: EditorGesturePolicy.dragTapTarget
        )
        // 선택은 된다 — 잠금 해제 버튼을 눌러야 하니까.
        #expect(grabbed?.id == object.id)
        #expect(grabbed?.isLocked == true)
        // 하지만 끌기는 화면 이동이다.
        #expect(EditorGesturePolicy.oneFingerAction(
            tool: .sticker, drawingMode: .draw, grabbed: grabbed) == .panViewport)
    }

    @Test("잠긴 텍스트도 같다")
    func lockedTextPansInstead() {
        var text = TextObject(text: "안녕", center: NormalizedPoint(x: 0.5, y: 0.5))
        text.isLocked = true
        let grabbed = DecorationLayer.text(text)
        #expect(EditorGesturePolicy.oneFingerAction(
            tool: .text, drawingMode: .draw, grabbed: grabbed) == .panViewport)
    }

    // MARK: - 7~11. 그리기 / 손바닥 모드

    @Test("그리기 도구의 기본은 그리기 모드다")
    func drawingStartsInDrawMode() throws {
        #expect(DrawingInteractionMode.draw.makesStrokes)
        #expect(!DrawingInteractionMode.pan.makesStrokes)
        #expect(DrawingInteractionMode.allCases == [.draw, .pan])

        let editor = try source("EditorView.swift")
        #expect(editor.contains("drawingMode: DrawingInteractionMode = .draw"))
        // 도구를 나갔다 들어오면 항상 그리기로 되돌아온다.
        #expect(editor.contains("drawingMode = .draw"))
    }

    @Test("그리기 모드에서는 한 손가락이 획을 만든다")
    func drawModeDrawsWithOneFinger() {
        #expect(EditorGesturePolicy.oneFingerAction(
            tool: .draw, drawingMode: .draw, grabbed: nil) == .draw)
    }

    @Test("손바닥 모드에서는 한 손가락이 화면을 민다")
    func panModePansWithOneFinger() {
        #expect(EditorGesturePolicy.oneFingerAction(
            tool: .draw, drawingMode: .pan, grabbed: nil) == .panViewport)
        // 오브젝트가 있어도 그리기 도구에서는 오브젝트를 잡지 않는다.
        let object = sticker(center: NormalizedPoint(x: 0.5, y: 0.5))
        #expect(EditorGesturePolicy.oneFingerAction(
            tool: .draw, drawingMode: .pan, grabbed: .sticker(object)) == .panViewport)
    }

    @Test("손바닥 모드는 획을 하나도 만들지 않는다")
    func panModeMakesNoStrokes() throws {
        // 손바닥 모드의 동작에는 draw / erase가 없다.
        for grabbed in [nil, DecorationLayer.sticker(sticker(center: .init(x: 0.5, y: 0.5)))] {
            let action = EditorGesturePolicy.oneFingerAction(
                tool: .draw, drawingMode: .pan, grabbed: grabbed)
            #expect(action != .draw)
            #expect(action != .erase)
        }
        // 캔버스도 이 규칙을 통해서만 획을 만든다.
        let canvas = try source("MirrorEditorCanvas.swift")
        #expect(canvas.contains("if oneFingerAction() == .draw { extendStroke(to: point) }"))
    }

    @Test("두 손가락을 대다 살짝 미끄러진 흔적은 남지 않는다")
    func shortCancelledStrokeIsDiscarded() {
        // pinch를 시작하려고 손가락을 대는 동안의 이동은 이보다 짧다.
        #expect(!DrawingCommitPolicy.keepsCancelledWork(travel: 0))
        #expect(!DrawingCommitPolicy.keepsCancelledWork(travel: 12))
        #expect(!DrawingCommitPolicy.keepsCancelledWork(travel: 43))
        // 이미 충분히 그린 획은 취소돼도 살린다.
        #expect(DrawingCommitPolicy.keepsCancelledWork(travel: 44))
        #expect(DrawingCommitPolicy.keepsCancelledWork(travel: 300))
    }

    // MARK: - 13~14. 모드를 바꿔도 나머지는 그대로

    @Test("그리기 ↔ 손바닥 전환은 붓 / 색 / 굵기 / 보기 상태를 건드리지 않는다")
    func switchingModeKeepsEverythingElse() throws {
        let editor = try source("EditorView.swift")
        let button = try #require(editor.range(of: "private func drawingModeButton("))
        let body = String(editor[button.lowerBound...].prefix(900))

        #expect(body.contains("drawingMode = mode"))
        for untouched in ["brush =", "brushColor =", "brushWidth =", "viewport =", "history."] {
            #expect(!body.contains(untouched), "모드 전환이 \(untouched)를 건드린다")
        }
    }

    // MARK: - 12 / 15. 화면 이동은 history에 들어가지 않는다

    @Test("이동 / 확대 / 맞춤은 실행 취소에 쌓이지 않는다")
    func viewportChangesAreNotUndoable() throws {
        // history가 다루는 것은 편집 데이터(EditorSnapshot)뿐이다.
        var snapshot = EditorSnapshot(strokes: [], stickers: [], texts: [], importedArtworks: [])
        var history = EditorHistory()
        #expect(!history.canUndo)

        let stroke = DrawingStroke(
            points: [NormalizedPoint(x: 0.2, y: 0.2), NormalizedPoint(x: 0.3, y: 0.3)],
            brush: .pen, color: .black, width: 0.01, opacity: 1, zIndex: 1
        )
        history.apply(.addStroke(stroke), to: &snapshot)
        #expect(history.canUndo)
        #expect(snapshot.strokes.count == 1)

        // 실행 취소는 획을 되돌린다 — 이동한 화면이 아니라.
        history.undo(&snapshot)
        #expect(snapshot.strokes.isEmpty)

        // 화면을 미는 경로는 onEdit을 부르지 않는다.
        let canvas = try source("MirrorEditorCanvas.swift")
        let pan = try #require(canvas.range(of: "private func panWithOneFinger("))
        #expect(!String(canvas[pan.lowerBound...].prefix(700)).contains("onEdit("))
    }

    // MARK: - 16. 확대해도 좌표계가 맞는다

    @Test("1x / 2x / 4x 어디서도 화면 ↔ Master 좌표가 정확히 왕복한다")
    func coordinatesRoundTripAtEveryZoom() {
        for zoom in [CGFloat(1), 2, 3, 4] {
            let view = transform(zoom: zoom, pan: CGSize(width: -40, height: -60))
            for point in [NormalizedPoint(x: 0.1, y: 0.15),
                          NormalizedPoint(x: 0.5, y: 0.5),
                          NormalizedPoint(x: 0.92, y: 0.88)] {
                let back = view.masterPoint(from: view.screenPoint(from: point))
                #expect(abs(back.x - point.x) < 0.0001, "zoom \(zoom)")
                #expect(abs(back.y - point.y) < 0.0001, "zoom \(zoom)")
            }
        }
    }

    @Test("확대할수록 같은 손가락 거리가 더 작은 Master 거리로 바뀐다")
    func panDistanceScalesWithZoom() {
        var previous = Double.infinity
        for zoom in [CGFloat(1), 2, 4] {
            let view = transform(zoom: zoom)
            let origin = view.masterPoint(from: .zero)
            let moved = view.masterPoint(from: CGPoint(x: 100, y: 0))
            let distance = moved.x - origin.x
            #expect(distance > 0)
            #expect(distance < previous, "zoom \(zoom)에서 이동량이 줄지 않았다")
            previous = distance
        }
        // 지우개 반경도 같은 변환을 쓴다 — 배율이 올라가면 Master 반경이 줄어든다.
        #expect(transform(zoom: 4).masterLength(fromScreen: 22)
                < transform(zoom: 1).masterLength(fromScreen: 22))
    }

    @Test("모든 도구가 같은 viewport 변환 하나를 쓴다")
    func toolsShareOneTransform() throws {
        let canvas = try source("MirrorEditorCanvas.swift")
        // 그리기 / 지우개 / 스티커 / 텍스트가 모두 같은 한 줄로 좌표를 바꾼다.
        #expect(canvas.components(separatedBy: "transform.masterPoint(from: location)").count - 1 == 2)
        // 도구별 변환을 따로 만들지 않는다 — 캔버스 안에 좌표 계산식이 없다.
        #expect(!canvas.contains("/ canvasSize.width"))
        #expect(!canvas.contains("- offset.x"))

        // 화면 ↔ Master 변환은 EditorCanvasTransform 한 곳에만 있다.
        let models = try source("EditorModels.swift")
        #expect(models.components(separatedBy: "func masterPoint(from").count - 1 == 1)
        #expect(models.components(separatedBy: "func screenPoint(from").count - 1 == 1)
    }

    // MARK: - 17. V-1 회전 회귀 방지

    @Test("회전 handle이 오브젝트를 따라 돈다 — V-1 동작 그대로")
    func rotationHandlesStillFollowTheObject() throws {
        let overlay = try source("StickerSelectionOverlay.swift")
        // 회전한 오브젝트의 실제 모서리로 handle을 옮긴다.
        #expect(overlay.contains("private func corner(x: CGFloat, y: CGFloat) -> CGPoint"))
        // 크기 조절은 오브젝트가 누운 방향으로 투영한다.
        #expect(overlay.contains("private func alongWidth(_ translation: CGSize) -> CGFloat"))
        #expect(overlay.contains("DragGesture(coordinateSpace: .local)"))

        // 360도 연속 회전 — 각도를 자르지 않는다.
        let canvas = try source("MirrorEditorCanvas.swift")
        #expect(canvas.contains("rotated.rotation = angle * 180 / .pi + 45"))
    }

    @Test("회전한 스티커의 판정은 보이는 모양을 따른다")
    func rotatedHitTestFollowsTheVisibleShape() {
        var object = sticker(center: NormalizedPoint(x: 0.5, y: 0.5), width: 0.3)
        object.rotation = 45
        let view = transform()
        let rect = placement(view).rect(object.frame)

        // 회전하지 않은 사각형의 모서리는 45도로 돌리면 밖으로 나간다.
        let corner = CGPoint(x: rect.maxX - 2, y: rect.maxY - 2)
        #expect(!object.contains(corner, in: placement(view), minimumTapTarget: 0))
        // 중심은 언제나 안이다.
        #expect(object.contains(CGPoint(x: rect.midX, y: rect.midY),
                                in: placement(view), minimumTapTarget: 0))
    }

    // MARK: - 그리기는 계속 Free Canvas

    @Test("손바닥 모드가 생겨도 카메라 영역에 그릴 수 있다")
    func drawingStaysFreeCanvas() {
        // 캔버스 안이면 어디든 그린다 — 카메라 영역도 포함이다.
        #expect(MirrorEditorCanvas.isInsideCanvas(NormalizedPoint(x: 0.5, y: 0.5)))
        #expect(MirrorEditorCanvas.isInsideCanvas(NormalizedPoint(x: 0.02, y: 0.02)))
        #expect(!MirrorEditorCanvas.isInsideCanvas(NormalizedPoint(x: 1.2, y: 0.5)))
    }
}
