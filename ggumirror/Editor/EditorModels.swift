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

// MARK: - Object

/// 사용자가 얹는 오브젝트의 공통 기반.
/// Drawing / Sticker / Text는 Phase 3-2에서 이 구조 위에 붙인다.
/// side로 잘라 복제하지 않는다 — 모서리를 걸친 오브젝트도 하나로 유지된다.
struct MirrorEditorObject: Identifiable, Hashable {
    var id = UUID()
    var frame: NormalizedRect
    var rotation: Double = 0
    var opacity: Double = 1
    var zIndex: Int = 0
    var isLocked = false
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
    /// Sticker / Text는 Phase 3-3에서 여기에 붙는다.
    var objects: [MirrorEditorObject] = []

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
    }
}

/// Background Color 팔레트. 기본 거울 8종과 같은 색을 쓴다.
enum EditorBackground {
    static let options: [(name: String, color: Color)] = BasicMirror.allCases.map {
        ($0.name, $0.style.frame)
    }
}

// MARK: - Side Detail transform

/// Side Detail의 화면 변환. uniform scale + translation만 쓴다.
/// 좌표계를 회전시키거나 side별 데이터를 만들지 않는다.
struct SideDetailTransform {
    let canvasSize: CGSize
    let offset: CGPoint
    /// 지금 실제로 보이는 영역 (Master Canvas 기준 0...1). Mini Map이 이 값을 그린다.
    let visibleRect: NormalizedRect

    init(side: EditorSide, insets: MirrorFrameInsets, viewport: CGSize) {
        let band = side.boundingBox(with: insets)
        let inset: CGFloat = 24
        let availableWidth = max(viewport.width - inset, 1)
        let availableHeight = max(viewport.height - inset, 1)

        // 캔버스 전체가 들어오는 최소 배율
        let fitScale = min(
            availableWidth / MirrorCanvas.size.width,
            availableHeight / MirrorCanvas.size.height
        )

        // 밴드가 작업 가능한 크기가 되도록 키운다.
        // 가로 밴드(위/아래)는 폭 전체가 보여야 하므로 폭에 맞추고,
        // 세로 밴드(왼쪽/오른쪽)는 밴드 두께가 화면 폭의 45%가 되도록 키운다.
        let targetScale: CGFloat = switch side {
        case .top, .bottom:
            availableWidth / MirrorCanvas.size.width
        case .left, .right:
            availableWidth * 0.45 / (band.width * MirrorCanvas.size.width)
        }

        let scale = max(fitScale, targetScale)
        canvasSize = CGSize(
            width: MirrorCanvas.size.width * scale,
            height: MirrorCanvas.size.height * scale
        )

        let bandRect = band.rect(in: canvasSize)
        offset = CGPoint(
            x: Self.clamp(center: bandRect.midX, canvas: canvasSize.width, viewport: viewport.width),
            y: Self.clamp(center: bandRect.midY, canvas: canvasSize.height, viewport: viewport.height)
        )

        visibleRect = NormalizedRect(
            x: Double(-offset.x / canvasSize.width),
            y: Double(-offset.y / canvasSize.height),
            width: Double(min(viewport.width, canvasSize.width) / canvasSize.width),
            height: Double(min(viewport.height, canvasSize.height) / canvasSize.height)
        )
    }

    /// 화면 좌표 → Master Canvas normalized 좌표. Drawing / Eraser가 모두 이걸 쓴다.
    func masterPoint(from location: CGPoint) -> NormalizedPoint {
        NormalizedPoint(
            x: Double((location.x - offset.x) / canvasSize.width),
            y: Double((location.y - offset.y) / canvasSize.height)
        )
    }

    /// 화면 길이 → Master Canvas 픽셀 길이. 지우개 반경 환산에 쓴다.
    func masterLength(fromScreen length: CGFloat) -> Double {
        Double(length / canvasSize.width) * MirrorCanvas.size.width
    }

    /// 밴드를 중앙에 두되, 캔버스 밖 빈 공간이 생기지 않도록 이동량을 제한한다.
    private static func clamp(center: CGFloat, canvas: CGFloat, viewport: CGFloat) -> CGFloat {
        guard canvas > viewport else { return (viewport - canvas) / 2 }
        return min(0, max(viewport - canvas, viewport / 2 - center))
    }
}
