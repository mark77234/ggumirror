//
//  MirrorEditorCanvas.swift
//  ggumirror
//
//  거울 한 장(1080 × 2340) 전체를 그대로 꾸미는 편집 캔버스.
//  상/하/좌/우를 고르지 않는다 — 카메라 영역을 포함한 캔버스 전체가 편집 대상이다.
//  그리기 / 지우기는 화면 좌표를 역변환해 Master normalized 좌표로만 다룬다.
//  Pan / Zoom은 viewport state만 바꾸고 디자인 데이터는 건드리지 않는다.
//

import SwiftUI

struct MirrorEditorCanvas: View {
    let design: MirrorDesign
    let tool: EditorTool
    /// 그리기 도구에서 한 손가락이 무엇을 하는가. 다른 도구는 이 값을 보지 않는다.
    let drawingMode: DrawingInteractionMode
    let brush: EditorBrush
    let brushWidth: Double
    let brushColor: Color

    /// 보기 상태. Editor session UI state이고 디자인 데이터가 아니다.
    @Binding var viewport: EditorViewportState
    @Binding var visibleRect: NormalizedRect
    /// 제스처가 끝났을 때만 확정한다. 그리는 동안에는 design을 건드리지 않는다.
    /// 현재 선택된 스티커. 텍스트와 동시에 선택되지 않는다.
    @Binding var selectedStickerID: UUID?
    /// 현재 선택된 텍스트.
    @Binding var selectedTextID: UUID?
    /// 현재 선택된 외부 디자인. 캔버스에서는 고를 수 없고, 캔버스를 누르면 풀린다.
    @Binding var selectedArtworkID: UUID?
    let onEdit: (EditorEdit) -> Void

    /// 손가락을 떼기 전의 진행 중인 획. 여기만 자주 갱신된다.
    @State private var activeStroke: DrawingStroke?
    /// 지우는 동안 지워질 예정인 획.
    @State private var pendingErase: Set<UUID> = []
    /// 두 손가락 조작 시작 시점의 viewport.
    @State private var viewportAtGestureStart: EditorViewportState?
    /// 스티커 조작 중인 임시 상태. 제스처가 끝날 때 한 번만 history에 남긴다.
    @State private var draggingSticker: StickerObject?
    @State private var stickerAtGestureStart: StickerObject?
    @State private var stickerGrabOffset = NormalizedPoint(x: 0, y: 0)
    /// 텍스트 조작 중인 임시 상태. 스티커와 같은 규칙으로 제스처 끝에 1회 커밋한다.
    @State private var draggingText: TextObject?
    @State private var textAtGestureStart: TextObject?
    @State private var textGrabOffset = NormalizedPoint(x: 0, y: 0)
    /// 빈 곳(또는 손바닥 모드)을 한 손가락으로 끌 때의 직전 위치.
    @State private var oneFingerPanAnchor: CGPoint?
    /// 이번 한 손가락 제스처가 화면에서 움직인 총 거리(pt).
    /// 두 손가락이 들어와 취소됐을 때 "그리려던 것"인지 "미끄러진 것"인지를 이 값으로 가른다.
    @State private var touchTravel: CGFloat = 0
    @State private var lastTouchLocation: CGPoint?
    /// 이동 중 촉각 피드백. 프레임마다 울리지 않도록 시간 + 거리로 제한한다.
    @State private var hapticLimiter = HapticRateLimiter()
    /// 제스처 힌트는 한 번 이해하면 다시 보여주지 않는다.
    @AppStorage("editorGestureHintSeen") private var hasSeenGestureHint = false
    @State private var didInteract = false

    private var showsGestureHint: Bool { !hasSeenGestureHint && !didInteract }

    /// 화면 기준 지우개 반경. Master 반경은 배율에 따라 환산된다.
    private let eraserScreenRadius: CGFloat = 22
    /// 너무 촘촘한 점은 버려 성능과 곡선 품질을 지킨다 (Master Canvas 픽셀 기준).
    private let minimumPointSpacing: Double = 6
    /// 이 개수 이상이면 제스처가 취소돼도 살릴 가치가 있는 획으로 본다.
    private let minimumCommittablePoints = 2

    /// 오브젝트를 잡아 옮기는 도구인지. 빈 곳 한 손가락 드래그가 화면 이동이 된다.
    private var isObjectTool: Bool { tool == .sticker || tool == .text }

    /// 이번 한 손가락 입력이 무엇을 하는가. 규칙은 `EditorGesturePolicy` 하나뿐이다.
    private func oneFingerAction(grabbed: DecorationLayer? = nil) -> EditorGesturePolicy.OneFingerAction {
        EditorGesturePolicy.oneFingerAction(tool: tool, drawingMode: drawingMode, grabbed: grabbed)
    }

    /// Master Canvas 안인지. 프레임 / 카메라 구분은 하지 않는다.
    static func isInsideCanvas(_ point: NormalizedPoint) -> Bool {
        (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    var body: some View {
        GeometryReader { proxy in
            let transform = EditorCanvasTransform(viewport: proxy.size, state: viewport, canvas: design.canvas)

            ZStack {
                // 뷰는 항상 viewport 크기다. 확대/이동은 그리는 좌표에만 반영한다.
                MirrorCanvasView(
                    design: previewDesign,
                    transform: MirrorViewTransform(
                        canvasSize: transform.canvasSize,
                        offset: transform.offset
                    ),
                    hiddenStrokeIDs: pendingErase,
                    activeStroke: activeStroke,
                    // Editor에서는 카메라 영역도 배경색으로 채워 한 장의 캔버스처럼 보인다.
                    // 저장되는 배경이 카메라를 덮는다는 뜻이 아니다 — 실제 거울에서는 그대로 비워진다.
                    mirrorAreaFill: design.backgroundColor,
                    showsCameraGuide: true
                )
                .allowsHitTesting(false)

                EditorCanvasGestureOverlay(
                    onTouch: { handleTouch($0, transform: transform, viewportSize: proxy.size) },
                    onNavigate: { navigate($0, transform: transform, viewportSize: proxy.size) }
                )

                if let selected = selectedSticker {
                    ObjectSelectionOverlay(
                        frame: selected.frame,
                        rotation: selected.rotation,
                        isLocked: selected.isLocked,
                        transform: MirrorViewTransform(
                            canvasSize: transform.canvasSize,
                            offset: transform.offset
                        ),
                        onResize: { delta, ended in
                            resizeSelected(by: delta, transform: transform, isEnded: ended)
                        },
                        onRotate: { location, ended in
                            rotateSelected(towards: location, transform: transform, isEnded: ended)
                        }
                    )
                }

                if let selected = selectedText {
                    ObjectSelectionOverlay(
                        frame: selected.frame,
                        rotation: selected.rotation,
                        isLocked: selected.isLocked,
                        transform: MirrorViewTransform(
                            canvasSize: transform.canvasSize,
                            offset: transform.offset
                        ),
                        onResize: { delta, ended in
                            resizeSelectedText(by: delta, transform: transform, isEnded: ended)
                        },
                        onRotate: { location, ended in
                            rotateSelectedText(towards: location, transform: transform, isEnded: ended)
                        }
                    )
                }


                if showsGestureHint {
                    GestureHint()
                }
            }
            .onChange(of: transform.visibleRect, initial: true) { _, newValue in
                visibleRect = newValue
            }
            .onChange(of: tool) { _, _ in
                // 도구가 바뀌어도 이미 그린 획은 버리지 않는다.
                commitActiveWork()
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - 한 손가락

    private func handleTouch(_ phase: CanvasTouchPhase, transform: EditorCanvasTransform, viewportSize: CGSize) {
        switch phase {
        case .tapped(let location):
            // 제자리 tap은 오브젝트 도구에서만 의미가 있다. 그리기 / 지우개 동작은 그대로 둔다.
            dismissGestureHint()
            guard isObjectTool else { return }
            selectObject(at: location, transform: transform, viewportSize: viewportSize)

        case .began(let location):
            dismissGestureHint()
            touchTravel = 0
            lastTouchLocation = location
            let point = transform.masterPoint(from: location)
            switch tool {
            case .draw:
                // 손바닥 모드면 그 자리에서 화면 이동이 시작된다.
                if oneFingerAction() == .draw { extendStroke(to: point) }
                else { oneFingerPanAnchor = location }
            case .erase: erase(at: point, transform: transform)
            case .sticker, .text:
                beginObjectTouch(at: location, point: point, transform: transform, viewportSize: viewportSize)
            }
        case .moved(let location):
            if let last = lastTouchLocation {
                touchTravel += hypot(location.x - last.x, location.y - last.y)
            }
            lastTouchLocation = location
            let point = transform.masterPoint(from: location)
            switch tool {
            case .draw:
                if oneFingerAction() == .draw { extendStroke(to: point) }
                else { panWithOneFinger(to: location, viewportSize: viewportSize) }
            case .erase: erase(at: point, transform: transform)
            case .sticker, .text:
                // 오브젝트를 잡았으면 이동, 빈 곳 / 잠긴 것이면 화면을 민다.
                if draggingSticker != nil {
                    moveSticker(to: point)
                } else if draggingText != nil {
                    moveText(to: point)
                } else {
                    panWithOneFinger(to: location, viewportSize: viewportSize)
                }
            }
        case .ended:
            endOneFingerTouch()
            commitActiveWork()
        case .cancelled:
            endOneFingerTouch()
            // 두 손가락이 들어와 끊긴 경우다. 충분히 그렸으면 살리고,
            // pinch를 시작하려다 살짝 미끄러진 정도면 흔적을 남기지 않는다.
            if DrawingCommitPolicy.keepsCancelledWork(travel: touchTravel) {
                commitActiveWork()
            } else {
                discardActiveStrokeWork()
            }
        }
    }

    private func endOneFingerTouch() {
        oneFingerPanAnchor = nil
        lastTouchLocation = nil
    }

    /// 오브젝트 이동은 눈에 보인 대로 확정하고, 짧게 끊긴 획 / 지우기만 버린다.
    private func discardActiveStrokeWork() {
        commitSticker()
        commitText()
        activeStroke = nil
        pendingErase = []
    }

    private func extendStroke(to point: NormalizedPoint) {
        // 캔버스 안이면 어디든 그린다 — 카메라 영역도 포함이다.
        guard Self.isInsideCanvas(point) else { return }

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

    private func erase(at point: NormalizedPoint, transform: EditorCanvasTransform) {
        guard Self.isInsideCanvas(point) else { return }
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
        commitSticker()
        commitText()
        if let stroke = activeStroke {
            if stroke.points.count >= minimumCommittablePoints || tool == .draw {
                onEdit(.addStroke(stroke))
            }
            activeStroke = nil
        }
        if !pendingErase.isEmpty {
            onEdit(.eraseStrokes(pendingErase))
            pendingErase = []
        }
    }

    // MARK: - Sticker

    /// 조작 중에는 임시 스티커를 얹어 보여주고 design은 건드리지 않는다.
    private var previewDesign: MirrorDesign {
        var copy = design
        if let draggingSticker,
           let index = copy.stickers.firstIndex(where: { $0.id == draggingSticker.id }) {
            copy.stickers[index] = draggingSticker
        }
        if let draggingText,
           let index = copy.texts.firstIndex(where: { $0.id == draggingText.id }) {
            copy.texts[index] = draggingText
        }
        return copy
    }


    private var selectedText: TextObject? {
        guard let selectedTextID else { return nil }
        if let draggingText, draggingText.id == selectedTextID { return draggingText }
        return design.texts.first { $0.id == selectedTextID }
    }

    private var selectedSticker: StickerObject? {
        guard let selectedStickerID else { return nil }
        if let draggingSticker, draggingSticker.id == selectedStickerID { return draggingSticker }
        return design.stickers.first { $0.id == selectedStickerID }
    }

    /// 눌린 지점에서 화면상 가장 위에 있는 장식.
    /// 판정 규칙은 `MirrorDesign.topSelectableDecoration` 하나뿐이다 —
    /// 렌더 순서와 Layers 목록과 정확히 같은 기준을 쓴다.
    /// 외부 디자인은 캔버스 전체를 덮으므로 여기서 잡히지 않는다.
    private func topLayer(
        at location: CGPoint,
        transform: EditorCanvasTransform,
        minimumTapTarget: CGFloat
    ) -> DecorationLayer? {
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        return design.topSelectableDecoration(
            at: location,
            in: placement,
            minimumTapTarget: minimumTapTarget
        )
    }

    private func topObject(
        at location: CGPoint,
        transform: EditorCanvasTransform,
        minimumTapTarget: CGFloat = EditorGesturePolicy.selectTapTarget
    ) -> (sticker: StickerObject?, text: TextObject?) {
        switch topLayer(at: location, transform: transform, minimumTapTarget: minimumTapTarget) {
        case .sticker(let object): return (object, nil)
        case .text(let object): return (nil, object)
        case .importedArtwork, .none: return (nil, nil)
        }
    }

    /// 제자리 tap — 선택만 바꾼다. 화면을 움직이거나 오브젝트를 잡지 않는다.
    private func selectObject(at location: CGPoint, transform: EditorCanvasTransform, viewportSize: CGSize) {
        let hit = topObject(at: location, transform: transform)
        selectedArtworkID = nil

        // 한 번에 하나만 선택된다.
        let changed = selectedStickerID != hit.sticker?.id || selectedTextID != hit.text?.id
        selectedStickerID = hit.sticker?.id
        selectedTextID = hit.text?.id

        guard let frame = hit.sticker?.frame ?? hit.text?.frame else { return }
        if changed { EditorHaptics.placementConfirmed() }
        // focus는 선택 이후에만. 선택 자체를 취소하지 않는다.
        _ = focus(on: frame, transform: transform, viewportSize: viewportSize)
    }

    /// 끌기 시작. 오브젝트를 잡으면 이동, 빈 곳이면 그 자리에서 한 손가락 Pan이 시작된다.
    private func beginObjectTouch(
        at location: CGPoint,
        point: NormalizedPoint,
        transform: EditorCanvasTransform,
        viewportSize: CGSize
    ) {
        // 끌기는 **눈에 보이는 크기 그대로** 판정한다. tap처럼 44pt까지 넓히면
        // 작은 오브젝트 옆 빈 곳을 밀 수 없어 화면 이동이 막힌다.
        let grabbed = topLayer(
            at: location,
            transform: transform,
            minimumTapTarget: EditorGesturePolicy.dragTapTarget
        )
        let hit: (sticker: StickerObject?, text: TextObject?) = switch grabbed {
        case .sticker(let object): (object, nil)
        case .text(let object): (nil, object)
        case .importedArtwork, .none: (nil, nil)
        }
        selectedStickerID = hit.sticker?.id
        selectedTextID = hit.text?.id
        selectedArtworkID = nil

        // 빈 곳이거나 잠긴 오브젝트면 그 자리에서 화면 이동이 시작된다.
        guard oneFingerAction(grabbed: grabbed) == .moveObject else {
            oneFingerPanAnchor = location
            return
        }

        if let sticker = hit.sticker {
            oneFingerPanAnchor = nil
            // 일부만 보이는 오브젝트는 zoom을 유지한 채 최소한만 끌어온다.
            let shift = focus(on: sticker.frame, transform: transform, viewportSize: viewportSize)
            stickerAtGestureStart = sticker
            draggingSticker = sticker
            hapticLimiter.reset()
            EditorHaptics.prepare()
            // focus로 화면이 움직인 만큼 잡은 지점을 보정한다. 손가락 아래에서 튀지 않게.
            stickerGrabOffset = NormalizedPoint(
                x: point.x - sticker.center.x - shift.x,
                y: point.y - sticker.center.y - shift.y
            )
        } else if let text = hit.text {
            oneFingerPanAnchor = nil
            let shift = focus(on: text.frame, transform: transform, viewportSize: viewportSize)
            textAtGestureStart = text
            draggingText = text
            hapticLimiter.reset()
            EditorHaptics.prepare()
            textGrabOffset = NormalizedPoint(
                x: point.x - text.center.x - shift.x,
                y: point.y - text.center.y - shift.y
            )
        }
    }

    /// 이미 충분히 보이면 아무것도 하지 않는다. 움직였다면 Master 기준 이동량을 돌려준다.
    /// 스티커 데이터는 절대 건드리지 않는다 — viewport state만 바뀐다.
    private func focus(
        on frame: NormalizedRect,
        transform: EditorCanvasTransform,
        viewportSize: CGSize
    ) -> NormalizedPoint {
        guard let focused = transform.focusState(on: frame, from: viewport) else {
            return NormalizedPoint(x: 0, y: 0)
        }
        let next = EditorCanvasTransform(viewport: viewportSize, state: focused, canvas: design.canvas)
        viewport = EditorViewportState(zoom: next.appliedZoom, pan: next.appliedPan)
        return NormalizedPoint(
            x: Double((next.offset.x - transform.offset.x) / next.canvasSize.width),
            y: Double((next.offset.y - transform.offset.y) / next.canvasSize.height)
        )
    }

    /// 스티커 도구에서 빈 곳을 한 손가락으로 끌면 화면이 움직인다.
    /// 두 손가락 Pan / Pinch / Scroll Handle / 맞춤과 완전히 같은 viewport state를 쓴다.
    private func panWithOneFinger(to location: CGPoint, viewportSize: CGSize) {
        guard let anchor = oneFingerPanAnchor else { return }
        oneFingerPanAnchor = location

        var next = viewport
        next.pan.width += location.x - anchor.x
        next.pan.height += location.y - anchor.y

        let clamped = EditorCanvasTransform(viewport: viewportSize, state: next, canvas: design.canvas)
        viewport = EditorViewportState(zoom: clamped.appliedZoom, pan: clamped.appliedPan)
    }

    private func moveSticker(to point: NormalizedPoint) {
        guard let current = draggingSticker, !current.isLocked else { return }
        let target = NormalizedPoint(
            x: point.x - stickerGrabOffset.x,
            y: point.y - stickerGrabOffset.y
        )
        let updated = current.moved(to: target).constrained()
        if hapticLimiter.shouldFire(at: updated.center, time: ProcessInfo.processInfo.systemUptime) {
            EditorHaptics.movementTick()
        }
        draggingSticker = updated
    }

    private func moveText(to point: NormalizedPoint) {
        guard let current = draggingText, !current.isLocked else { return }
        let target = NormalizedPoint(
            x: point.x - textGrabOffset.x,
            y: point.y - textGrabOffset.y
        )
        let updated = current.moved(to: target).constrained()
        if hapticLimiter.shouldFire(at: updated.center, time: ProcessInfo.processInfo.systemUptime) {
            EditorHaptics.movementTick()
        }
        draggingText = updated
    }

    /// 텍스트 크기는 글자 크기 하나로만 바뀐다 — 가로 / 세로를 따로 늘리지 않는다.
    private func resizeSelectedText(by delta: CGFloat, transform: EditorCanvasTransform, isEnded: Bool) {
        guard let base = textAtGestureStart ?? selectedText, !base.isLocked else { return }
        if textAtGestureStart == nil { textAtGestureStart = base }
        // 스티커와 같은 식에 감도만 낮춰 곱한다. 조금 끌면 조금만 커진다.
        let sizeDelta = Double(delta * 2 / transform.canvasSize.width) * TextPolicy.resizeSensitivity
        draggingText = base.resized(fontSize: base.fontSize + sizeDelta).constrained()
        if isEnded { commitText() }
    }

    private func rotateSelectedText(towards location: CGPoint, transform: EditorCanvasTransform, isEnded: Bool) {
        guard let base = textAtGestureStart ?? selectedText, !base.isLocked else { return }
        if textAtGestureStart == nil { textAtGestureStart = base }
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        let rect = placement.rect(base.frame)
        let angle = atan2(location.y - rect.midY, location.x - rect.midX)
        var rotated = base
        rotated.rotation = angle * 180 / .pi + 45
        draggingText = rotated
        if isEnded { commitText() }
    }

    /// 제스처가 끝났을 때만 history에 1회 남긴다.
    private func commitText() {
        defer {
            draggingText = nil
            textAtGestureStart = nil
        }
        guard let final = draggingText, final != textAtGestureStart else { return }
        EditorHaptics.placementConfirmed()
        onEdit(.replaceText(final))
    }

    private func resizeSelected(by delta: CGFloat, transform: EditorCanvasTransform, isEnded: Bool) {
        guard let base = stickerAtGestureStart ?? selectedSticker, !base.isLocked else { return }
        if stickerAtGestureStart == nil { stickerAtGestureStart = base }
        let widthDelta = Double(delta * 2 / transform.canvasSize.width)
        let resized = base.resized(width: base.frame.width + widthDelta, canvas: design.canvas).constrained()
        draggingSticker = resized
        if isEnded { commitSticker() }
    }

    private func rotateSelected(towards location: CGPoint, transform: EditorCanvasTransform, isEnded: Bool) {
        guard let base = stickerAtGestureStart ?? selectedSticker, !base.isLocked else { return }
        if stickerAtGestureStart == nil { stickerAtGestureStart = base }
        let placement = MirrorViewTransform(canvasSize: transform.canvasSize, offset: transform.offset)
        let rect = placement.rect(base.frame)
        let angle = atan2(location.y - rect.midY, location.x - rect.midX)
        var rotated = base
        // 오른쪽 위 handle이 기준이라 45도만큼 보정한다.
        rotated.rotation = angle * 180 / .pi + 45
        draggingSticker = rotated
        if isEnded { commitSticker() }
    }

    /// 제스처가 끝났을 때만 history에 1회 남긴다.
    private func commitSticker() {
        defer {
            draggingSticker = nil
            stickerAtGestureStart = nil
        }
        guard let final = draggingSticker, final != stickerAtGestureStart else { return }
        EditorHaptics.placementConfirmed()
        onEdit(.replaceSticker(final))
    }

    private func dismissGestureHint() {
        guard !didInteract else { return }
        didInteract = true
        hasSeenGestureHint = true
    }


    // MARK: - 두 손가락

    private func navigate(_ navigation: CanvasNavigation, transform: EditorCanvasTransform, viewportSize: CGSize) {
        guard !navigation.isEnded else {
            viewportAtGestureStart = nil
            return
        }
        dismissGestureHint()
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
            let zoomed = EditorCanvasTransform(viewport: viewportSize, state: next, canvas: design.canvas)
            let moved = zoomed.screenPoint(from: anchor)
            next.pan.width += navigation.center.x - moved.x
            next.pan.height += navigation.center.y - moved.y
        }

        // 배율이 바뀌면 pan 범위도 달라지므로 항상 다시 clamp된 값을 저장한다.
        let clamped = EditorCanvasTransform(viewport: viewportSize, state: next, canvas: design.canvas)
        viewport = EditorViewportState(zoom: clamped.appliedZoom, pan: clamped.appliedPan)
    }
}

/// Editor에 처음 들어온 사용자에게 한 번만 보여주는 안내.
/// 점선이 "꾸미면 안 되는 곳"으로 보이지 않도록 그 자리에서 설명한다.
struct GestureHint: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("점선 안쪽은 실제 거울에서 카메라가 보여요")
            Text("이 영역도 자유롭게 꾸밀 수 있어요")
                .foregroundStyle(PaperTheme.secondaryInk)
        }
        .font(InkFont.caption)
        .foregroundStyle(PaperTheme.ink)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            UnevenRoundedRectangle.ink(15, 12, 16, 13)
                .fill(PaperTheme.subtleSurface)
                .overlay(
                    UnevenRoundedRectangle.ink(15, 12, 16, 13)
                        .stroke(PaperTheme.ink, lineWidth: 1.5)
                )
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 12)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("점선 안쪽은 실제 거울에서 카메라가 보여요. 이 영역도 자유롭게 꾸밀 수 있어요")
    }
}

enum EditorTool: String, CaseIterable, Identifiable {
    case draw, erase, sticker, text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draw: "그리기"
        case .erase: "지우개"
        case .sticker: "스티커"
        case .text: "텍스트"
        }
    }

    var icon: String {
        switch self {
        case .draw: "scribble"
        case .erase: "eraser"
        case .sticker: "heart"
        case .text: "textformat"
        }
    }
}
