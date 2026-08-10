//
//  EditorModels.swift
//  ggumirror
//
//  Editor의 기준 좌표계와 데이터 모델.
//  Master Canvas는 1080 x 2340 하나뿐이고, 모든 좌표는 0...1 normalized로 저장한다.
//

import SwiftUI

// MARK: - Master Canvas

enum MirrorCanvas {
    /// 논리 기준 캔버스. 실제 렌더 크기와 무관하게 이 비율만 유지한다.
    static let size = CGSize(width: 1080, height: 2340)
    static var aspectRatio: CGFloat { size.width / size.height }
}

/// 거울 자체의 geometry 상수. 화면마다 임의의 pt를 넣지 않고 여기 하나만 본다.
enum MirrorGeometry {
    /// 중앙 Mirror Area 안쪽 모서리 반경 (Master Canvas 1080 × 2340 기준 픽셀).
    /// 실제 거울처럼 살짝 둥근 정도이고, capsule처럼 과하게 둥글지 않다.
    static let innerCornerRadius: Double = 30

    /// 렌더 크기로 환산한 반경. Master → renderer 변환은 항상 이 함수를 거친다.
    static func innerCornerRadius(for canvas: CGSize) -> CGFloat {
        CGFloat(innerCornerRadius / MirrorCanvas.size.width) * canvas.width
    }
}

/// Master Canvas 기준 0...1 사각형. 화면 크기가 달라도 같은 자리에 렌더링된다.
struct NormalizedRect: Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}

// MARK: - Frame insets

/// 프레임 밴드 두께. 216px 같은 고정값을 쓰지 않고 거울마다 다르게 가질 수 있다.
struct MirrorFrameInsets: Hashable {
    var top: Double
    var right: Double
    var bottom: Double
    var left: Double

    /// MVP 정책: 모든 거울(기본 / 상점 / 사용자 제작)이 이 값을 쓴다.
    /// 두께를 바꾸는 UI는 제공하지 않는다. 모델은 향후 확장을 위해 남겨둔다.
    /// Master 기준 좌우 108 / 위 180 / **아래 220** — 아래를 조금 더 두껍게 둔다.
    static let standard = MirrorFrameInsets(
        top: 180.0 / 2340.0,
        right: 108.0 / 1080.0,
        bottom: 220.0 / 2340.0,
        left: 108.0 / 1080.0
    )

    init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    /// 실제 거울에서 카메라가 비치는 영역.
    /// **장식 금지 구역이 아니다** — 배경만 이 영역을 비우고, 그림 / 스티커는 위에 얹힌다.
    var mirrorArea: NormalizedRect {
        NormalizedRect(x: left, y: top, width: 1 - left - right, height: 1 - top - bottom)
    }

    /// 중앙 Mirror Area의 실제 모양 — 안쪽 네 모서리가 둥근 사각형.
    /// Renderer / FrameMask / Preview / Runtime / Capture가 모두 이 하나를 쓴다.
    func mirrorAreaPath(in rect: CGRect) -> Path {
        let area = mirrorArea.rect(in: rect.size).offsetBy(dx: rect.minX, dy: rect.minY)
        return Path(roundedRect: area, cornerRadius: MirrorGeometry.innerCornerRadius(for: rect.size))
    }
}

// MARK: - Design

/// Editor가 편집하는 거울 한 장. 렌더링에 필요한 모든 것이 여기 담긴다.
struct MirrorDesign: Identifiable, Hashable {
    var id: String
    var name: String
    /// 프레임 색 / 밴드 두께 / 템플릿 장식. Gallery 미리보기와 같은 값을 쓴다.
    var style: MirrorStyle
    /// 사용자가 그린 획. Master Canvas normalized 좌표만 담는다.
    var strokes: [DrawingStroke] = []
    /// 사용자가 얹은 스티커. Drawing과 같은 Master normalized 좌표를 쓴다.
    var stickers: [StickerObject] = []
    /// 사용자가 얹은 텍스트. 같은 Master normalized 좌표를 쓴다.
    var texts: [TextObject] = []
    /// 사용자가 얹은 도형 / 꾸미기 요소.
    var shapes: [ShapeObject] = []

    /// 스티커 / 텍스트 / 도형을 **하나의 순서**로 본 가장 위 zIndex.
    /// 새 장식은 항상 이 위에 올라간다. Layers Phase도 이 순서를 그대로 쓴다.
    var topDecorationZIndex: Int {
        max(
            stickers.map(\.zIndex).max() ?? 0,
            max(texts.map(\.zIndex).max() ?? 0, shapes.map(\.zIndex).max() ?? 0)
        )
    }

    var insets: MirrorFrameInsets {
        get { style.insets }
        set { style.insets = newValue }
    }

    var backgroundColor: Color {
        get { style.frame }
        set { style.frame = newValue }
    }

    init(mirror: MyMirror) {
        id = mirror.id
        name = mirror.name
        style = mirror.style
        strokes = mirror.strokes
        stickers = mirror.stickers
        texts = mirror.texts
        shapes = mirror.shapes
    }
}

/// Background Color 팔레트. 기본 거울 8종과 같은 색을 쓴다.
enum EditorBackground {
    static let options: [(name: String, color: Color)] = BasicMirror.allCases.map {
        ($0.name, $0.style.frame)
    }
}

// MARK: - Editor viewport

/// Editor 보기 상태. 디자인 데이터가 아니라 session UI state다.
/// Pan / Zoom은 오직 이 값만 바꾼다.
struct EditorViewportState: Equatable {
    /// 1.0 = 거울 한 장이 화면에 딱 들어오는 배율(맞춤).
    var zoom: CGFloat = 1
    /// 맞춤 위치에서의 이동량(화면 pt).
    var pan: CGSize = .zero

    /// 전체 캔버스를 보는 편집기라 맞춤보다 더 축소할 이유가 없다.
    static let zoomRange: ClosedRange<CGFloat> = 1...4

    var isFitted: Bool { self == EditorViewportState() }
}

/// 거울 한 장 전체를 화면에 놓는 변환. uniform scale + translation만 쓴다.
/// side별 좌표계나 별도 데이터를 만들지 않는다 — Master Canvas 하나를 그대로 본다.
struct EditorCanvasTransform {
    let canvasSize: CGSize
    let offset: CGPoint
    /// 이 변환을 계산한 화면 크기.
    let viewportSize: CGSize
    /// 지금 실제로 보이는 Master 영역 (0...1).
    let visibleRect: NormalizedRect
    /// 요청한 pan 중 실제로 반영된 값. 뷰는 이 값을 되돌려 받아 저장한다.
    let appliedPan: CGSize
    /// 실제로 반영된 배율.
    let appliedZoom: CGFloat

    /// 캔버스 둘레에 남기는 여백. 가장자리 장식도 손가락으로 잡을 수 있게 한다.
    static let edgeInset: CGFloat = 24

    init(viewport: CGSize, state: EditorViewportState = .init()) {
        viewportSize = viewport

        // zoom 1 = 거울 한 장이 통째로 들어오는 배율.
        let available = CGSize(
            width: max(viewport.width - Self.edgeInset, 1),
            height: max(viewport.height - Self.edgeInset, 1)
        )
        let base = min(
            available.width / MirrorCanvas.size.width,
            available.height / MirrorCanvas.size.height
        )
        let zoom = min(max(state.zoom, EditorViewportState.zoomRange.lowerBound),
                       EditorViewportState.zoomRange.upperBound)
        appliedZoom = zoom

        let scale = base * zoom
        canvasSize = CGSize(
            width: MirrorCanvas.size.width * scale,
            height: MirrorCanvas.size.height * scale
        )

        // 맞춤 위치 = 화면 중앙 정렬.
        let baseX = (viewport.width - canvasSize.width) / 2
        let baseY = (viewport.height - canvasSize.height) / 2
        let movedX = Self.clamp(baseX + state.pan.width, canvas: canvasSize.width, viewport: viewport.width)
        let movedY = Self.clamp(baseY + state.pan.height, canvas: canvasSize.height, viewport: viewport.height)

        offset = CGPoint(x: movedX, y: movedY)
        appliedPan = CGSize(width: movedX - baseX, height: movedY - baseY)
        visibleRect = Self.visibleMaster(offset: offset, canvas: canvasSize, viewport: viewport)
    }

    /// 캔버스가 화면보다 크면 빈 공간이 보이지 않게 끝에서 멈춘다.
    /// 화면보다 작으면(맞춤 상태) 가운데 정렬 — 의도된 여백이다.
    private static func clamp(_ value: CGFloat, canvas: CGFloat, viewport: CGFloat) -> CGFloat {
        guard canvas > viewport else { return (viewport - canvas) / 2 }
        return min(0, max(viewport - canvas, value))
    }

    /// 화면과 Master Canvas가 실제로 겹치는 부분 (0...1).
    private static func visibleMaster(offset: CGPoint, canvas: CGSize, viewport: CGSize) -> NormalizedRect {
        func span(offset: CGFloat, canvas: CGFloat, viewport: CGFloat) -> (Double, Double) {
            let start = max(0, -offset)
            let end = min(canvas, viewport - offset)
            return (Double(start / canvas), Double(max(end - start, 0) / canvas))
        }
        let (x, width) = span(offset: offset.x, canvas: canvas.width, viewport: viewport.width)
        let (y, height) = span(offset: offset.y, canvas: canvas.height, viewport: viewport.height)
        return NormalizedRect(x: x, y: y, width: width, height: height)
    }

    /// 화면 좌표 → Master Canvas normalized 좌표. Drawing / Eraser / Sticker가 모두 이걸 쓴다.
    func masterPoint(from location: CGPoint) -> NormalizedPoint {
        NormalizedPoint(
            x: Double((location.x - offset.x) / canvasSize.width),
            y: Double((location.y - offset.y) / canvasSize.height)
        )
    }

    /// Master normalized 좌표 → 화면 좌표. pinch 기준점 유지에 쓴다.
    func screenPoint(from master: NormalizedPoint) -> CGPoint {
        CGPoint(
            x: master.x * canvasSize.width + offset.x,
            y: master.y * canvasSize.height + offset.y
        )
    }

    /// 화면 길이 → Master Canvas 픽셀 길이. 지우개 반경 환산에 쓴다.
    func masterLength(fromScreen length: CGFloat) -> Double {
        Double(length / canvasSize.width) * MirrorCanvas.size.width
    }

    /// 스티커를 편하게 잡으려면 handle 주변에 이만큼 여유가 있어야 한다.
    static let focusMargin: CGFloat = 40

    /// 선택한 스티커가 이미 충분히 보이면 nil — viewport를 건드리지 않는다.
    /// 아니라면 **zoom은 그대로 두고** 최소한의 pan만 더한 상태를 돌려준다.
    func focusState(on frame: NormalizedRect, from state: EditorViewportState) -> EditorViewportState? {
        let bounds = CGRect(origin: .zero, size: viewportSize)
        let visible = MirrorViewTransform(canvasSize: canvasSize, offset: offset).rect(frame)
        guard !bounds.contains(visible) else { return nil }

        let rect = visible.insetBy(dx: -Self.focusMargin, dy: -Self.focusMargin)

        func shift(min lo: CGFloat, max hi: CGFloat, boundsMin: CGFloat, boundsMax: CGFloat) -> CGFloat {
            guard hi - lo <= boundsMax - boundsMin else { return (boundsMin + boundsMax) / 2 - (lo + hi) / 2 }
            if lo < boundsMin { return boundsMin - lo }
            if hi > boundsMax { return boundsMax - hi }
            return 0
        }

        // 실제로 움직일 수 있는 만큼만 요청한다.
        // 캔버스 끝에 붙은 스티커를 다시 눌러도 같은 값을 반복해서 쓰지 않게 한다.
        func achievable(_ delta: CGFloat, offset: CGFloat, canvas: CGFloat, viewport: CGFloat) -> CGFloat {
            guard canvas > viewport else { return 0 }
            return min(max(delta, (viewport - canvas) - offset), -offset)
        }

        let dx = achievable(
            shift(min: rect.minX, max: rect.maxX, boundsMin: bounds.minX, boundsMax: bounds.maxX),
            offset: offset.x, canvas: canvasSize.width, viewport: viewportSize.width
        )
        let dy = achievable(
            shift(min: rect.minY, max: rect.maxY, boundsMin: bounds.minY, boundsMax: bounds.maxY),
            offset: offset.y, canvas: canvasSize.height, viewport: viewportSize.height
        )
        guard dx != 0 || dy != 0 else { return nil }

        return EditorViewportState(
            zoom: state.zoom,
            pan: CGSize(width: state.pan.width + dx, height: state.pan.height + dy)
        )
    }
}

