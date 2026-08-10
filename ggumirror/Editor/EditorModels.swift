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
    static let standard = MirrorFrameInsets(
        top: 180.0 / 2340.0,
        right: 108.0 / 1080.0,
        bottom: 180.0 / 2340.0,
        left: 108.0 / 1080.0
    )

    init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    /// 중앙 Mirror Area. 카메라가 비치는 영역이라 항상 투명하게 유지된다.
    var mirrorArea: NormalizedRect {
        NormalizedRect(x: left, y: top, width: 1 - left - right, height: 1 - top - bottom)
    }

    func value(for side: EditorSide) -> Double {
        switch side {
        case .top: top
        case .right: right
        case .bottom: bottom
        case .left: left
        }
    }
}

// MARK: - Side

enum EditorSide: String, CaseIterable, Identifiable, Hashable {
    case top, right, bottom, left

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: "위"
        case .right: "오른쪽"
        case .bottom: "아래"
        case .left: "왼쪽"
        }
    }

    /// 이 side를 편집할 때 움직일 수 있는 축.
    /// 세로 밴드는 위→아래, 가로 밴드는 좌→우. 자유로운 2D 이동은 만들지 않는다.
    var panAxis: PanAxis {
        switch self {
        case .left, .right: .vertical
        case .top, .bottom: .horizontal
        }
    }

    enum PanAxis { case vertical, horizontal }

    /// 이 side 밴드의 bounding box (Master Canvas 기준 0...1).
    func boundingBox(with insets: MirrorFrameInsets) -> NormalizedRect {
        switch self {
        case .top: NormalizedRect(x: 0, y: 0, width: 1, height: insets.top)
        case .bottom: NormalizedRect(x: 0, y: 1 - insets.bottom, width: 1, height: insets.bottom)
        case .left: NormalizedRect(x: 0, y: 0, width: insets.left, height: 1)
        case .right: NormalizedRect(x: 1 - insets.right, y: 0, width: insets.right, height: 1)
        }
    }
}

/// 액자처럼 모서리를 45도로 나눈 밴드 모양.
/// 네 밴드가 서로 겹치지 않아 corner에서도 hit testing이 예측 가능하다.
struct SideBandShape: Shape {
    let side: EditorSide
    let insets: MirrorFrameInsets

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let top = insets.top * h
        let bottom = insets.bottom * h
        let left = insets.left * w
        let right = insets.right * w

        // 안쪽 사각형(= 중앙 Mirror Area)의 네 꼭짓점
        let innerTopLeft = CGPoint(x: rect.minX + left, y: rect.minY + top)
        let innerTopRight = CGPoint(x: rect.maxX - right, y: rect.minY + top)
        let innerBottomRight = CGPoint(x: rect.maxX - right, y: rect.maxY - bottom)
        let innerBottomLeft = CGPoint(x: rect.minX + left, y: rect.maxY - bottom)

        let corners: [CGPoint]
        switch side {
        case .top:
            corners = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                innerTopRight,
                innerTopLeft
            ]
        case .right:
            corners = [
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                innerBottomRight,
                innerTopRight
            ]
        case .bottom:
            corners = [
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY),
                innerBottomLeft,
                innerBottomRight
            ]
        case .left:
            corners = [
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.minY),
                innerTopLeft,
                innerBottomLeft
            ]
        }

        var path = Path()
        path.addLines(corners)
        path.closeSubpath()
        return path
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
    }
}

/// Background Color 팔레트. 기본 거울 8종과 같은 색을 쓴다.
enum EditorBackground {
    static let options: [(name: String, color: Color)] = BasicMirror.allCases.map {
        ($0.name, $0.style.frame)
    }
}

// MARK: - Side Detail viewport

/// Side Detail의 보기 상태. 디자인 데이터가 아니라 Editor session UI state다.
/// Pan / Zoom은 오직 이 값만 바꾼다.
struct EditorViewportState: Equatable {
    /// fit 상태를 1.0으로 보는 배율.
    var zoom: CGFloat = 1
    /// fit 기준 위치에서의 이동량(화면 pt).
    var pan: CGSize = .zero

    /// 정책상 허용 범위. 실제 하한은 Side / viewport geometry에 따라 더 좁아질 수 있다.
    static let zoomRange: ClosedRange<CGFloat> = 0.65...3

    var isFitted: Bool { self == EditorViewportState() }
}

/// Side Detail의 화면 변환. uniform scale + translation만 쓴다.
/// 좌표계를 회전시키거나 side별 데이터를 만들지 않는다.
struct SideDetailTransform {
    let canvasSize: CGSize
    let offset: CGPoint
    /// 지금 실제로 보이는 영역 (Master Canvas 기준 0...1). Mini Map이 이 값을 그린다.
    let visibleRect: NormalizedRect
    /// 요청한 pan 중 실제로 반영된 값. 뷰는 이 값을 되돌려 받아 저장한다.
    let appliedPan: CGSize
    /// 실제로 반영된 배율. zoomRange로 제한된다.
    let appliedZoom: CGFloat

    init(side: EditorSide, insets: MirrorFrameInsets, viewport: CGSize, state: EditorViewportState = .init()) {
        let band = side.boundingBox(with: insets)
        let inset: CGFloat = 24
        let availableWidth = max(viewport.width - inset, 1)
        let availableHeight = max(viewport.height - inset, 1)

        // 캔버스 전체가 들어오는 최소 배율
        let fitScale = min(
            availableWidth / MirrorCanvas.size.width,
            availableHeight / MirrorCanvas.size.height
        )

        let base = max(fitScale, Self.targetScale(for: side, band: band, availableWidth: availableWidth))

        // 축소해도 캔버스가 화면보다 좁아져 떠다니지 않도록 하한을 한 번 더 좁힌다.
        let minimumZoom = max(
            EditorViewportState.zoomRange.lowerBound,
            min(1, viewport.width / (MirrorCanvas.size.width * base))
        )
        let zoom = min(max(state.zoom, minimumZoom), EditorViewportState.zoomRange.upperBound)
        appliedZoom = zoom

        let scale = base * zoom
        canvasSize = CGSize(
            width: MirrorCanvas.size.width * scale,
            height: MirrorCanvas.size.height * scale
        )

        // pan이 0일 때의 기준 위치 — 밴드를 화면 중앙에 둔다.
        let bandRect = band.rect(in: canvasSize)
        let baseX = Self.clampOffset(
            viewport.width / 2 - bandRect.midX,
            canvas: canvasSize.width, viewport: viewport.width,
            bandMin: bandRect.minX, bandMax: bandRect.maxX
        )
        let baseY = Self.clampOffset(
            viewport.height / 2 - bandRect.midY,
            canvas: canvasSize.height, viewport: viewport.height,
            bandMin: bandRect.minY, bandMax: bandRect.maxY
        )

        let movedX = Self.clampOffset(
            baseX + state.pan.width,
            canvas: canvasSize.width, viewport: viewport.width,
            bandMin: bandRect.minX, bandMax: bandRect.maxX
        )
        let movedY = Self.clampOffset(
            baseY + state.pan.height,
            canvas: canvasSize.height, viewport: viewport.height,
            bandMin: bandRect.minY, bandMax: bandRect.maxY
        )

        offset = CGPoint(x: movedX, y: movedY)
        appliedPan = CGSize(width: movedX - baseX, height: movedY - baseY)

        visibleRect = NormalizedRect(
            x: Double(-offset.x / canvasSize.width),
            y: Double(-offset.y / canvasSize.height),
            width: Double(min(viewport.width, canvasSize.width) / canvasSize.width),
            height: Double(min(viewport.height, canvasSize.height) / canvasSize.height)
        )
    }

    /// Side별 기본 배율(zoom 1.0 기준).
    /// 가로 밴드는 폭 전체가 보이도록, 세로 밴드는 밴드 두께가 화면 폭의 일정 비율이 되도록 맞춘다.
    /// 임의의 magic number를 흩뿌리지 않고 이 한 곳에서만 정한다.
    static func targetScale(for side: EditorSide, band: NormalizedRect, availableWidth: CGFloat) -> CGFloat {
        switch side {
        case .top, .bottom:
            availableWidth / MirrorCanvas.size.width
        case .left, .right:
            availableWidth * Self.verticalBandScreenShare / (band.width * MirrorCanvas.size.width)
        }
    }

    /// 세로 밴드가 화면 폭에서 차지할 비율. 낮출수록 주변 맥락이 더 보인다.
    static let verticalBandScreenShare: CGFloat = 0.25

    /// 이 viewport에서 실제로 허용되는 최소 배율.
    static func minimumZoom(side: EditorSide, insets: MirrorFrameInsets, viewport: CGSize) -> CGFloat {
        SideDetailTransform(side: side, insets: insets, viewport: viewport,
                            state: .init(zoom: EditorViewportState.zoomRange.lowerBound)).appliedZoom
    }

    /// Scroll Handle이 track 위치를 그대로 viewport 위치로 바꿀 때 쓰는 값.
    /// 0 = 프레임 최상단, 1 = 최하단.
    func pan(forVerticalProgress progress: Double, viewport: CGSize) -> CGSize {
        let travel = max(canvasSize.height - viewport.height, 0)
        let desiredOffsetY = -CGFloat(min(max(progress, 0), 1)) * travel
        let baseOffsetY = offset.y - appliedPan.height
        return CGSize(width: appliedPan.width, height: desiredOffsetY - baseOffsetY)
    }

    /// 현재 세로 위치 0...1. Mini Map / Scroll Handle이 같은 값을 쓴다.
    var verticalProgress: Double {
        let travel = 1 - visibleRect.height
        guard travel > 0.0001 else { return 0 }
        return min(max(visibleRect.y / travel, 0), 1)
    }

    /// 화면 좌표 → Master Canvas normalized 좌표. Drawing / Eraser가 모두 이걸 쓴다.
    /// zoom / pan은 canvasSize와 offset에 이미 반영돼 있어 별도 보정이 필요 없다.
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
    /// zoom이 올라가면 화면 반경이 같아도 Master 반경은 작아진다.
    func masterLength(fromScreen length: CGFloat) -> Double {
        Double(length / canvasSize.width) * MirrorCanvas.size.width
    }

    /// 캔버스가 화면을 덮도록, 그리고 선택한 밴드를 놓치지 않도록 offset을 제한한다.
    /// rubber-band 없이 끝에서 멈춘다.
    private static func clampOffset(
        _ value: CGFloat,
        canvas: CGFloat,
        viewport: CGFloat,
        bandMin: CGFloat,
        bandMax: CGFloat
    ) -> CGFloat {
        // 캔버스가 화면보다 작으면 가운데 정렬 (의도된 여백)
        guard canvas > viewport else { return (viewport - canvas) / 2 }

        var lower = viewport - canvas
        var upper: CGFloat = 0

        // 선택한 밴드가 화면 밖으로 완전히 빠지지 않도록 한 번 더 좁힌다.
        let keep = min(bandMax - bandMin, viewport) * 0.5
        let bandLower = -bandMax + keep      // 밴드 아래쪽 끝이 화면 위에 걸치는 한계
        let bandUpper = viewport - bandMin - keep
        lower = max(lower, min(bandLower, upper))
        upper = min(upper, max(bandUpper, lower))

        return min(upper, max(lower, value))
    }
}
