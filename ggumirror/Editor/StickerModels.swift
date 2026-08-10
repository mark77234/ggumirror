//
//  StickerModels.swift
//  ggumirror
//
//  Sticker도 Drawing과 같은 Master Canvas(1080 x 2340) normalized 좌표만 쓴다.
//  side별로 잘라 저장하지 않으므로 모서리를 걸친 스티커도 하나의 오브젝트다.
//

import SwiftUI

/// 기본 제공 스티커. 지금은 개발용 placeholder이고
/// 최종 hand-drawn asset library는 후속 Visual Content Polish에서 교체한다.
enum StickerSource: String, CaseIterable, Identifiable, Hashable {
    case heart, ribbon, star, flower, sparkle, smile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heart: "하트"
        case .ribbon: "리본"
        case .star: "별"
        case .flower: "꽃"
        case .sparkle: "반짝임"
        case .smile: "스마일"
        }
    }

    var symbolName: String {
        switch self {
        case .heart: "heart"
        case .ribbon: "bookmark"
        case .star: "star"
        case .flower: "camera.macro"
        case .sparkle: "sparkles"
        case .smile: "face.smiling"
        }
    }
}

/// 사용자가 얹은 스티커 하나.
/// 사진 스티커(Phase 3-3D)도 source만 늘려 같은 transform engine을 쓴다.
struct StickerObject: Identifiable, Hashable {
    var id = UUID()
    var source: StickerSource
    /// Master Canvas 기준 0...1 사각형.
    var frame: NormalizedRect
    var rotation: Double = 0
    var opacity: Double = 1
    var zIndex: Int = 0
    var isLocked = false
    var isFlippedHorizontally = false

    /// 화면 폭 기준 최소 / 최대 크기. 너무 작아지거나 거울을 통째로 덮지 않게 한다.
    static let sizeRange: ClosedRange<Double> = 0.06...0.45

    var center: NormalizedPoint {
        NormalizedPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
    }

    /// Master Canvas는 세로로 길어서, 정사각 스티커를 만들려면 높이 비율을 보정해야 한다.
    static func squareHeight(for width: Double) -> Double {
        width * MirrorCanvas.size.width / MirrorCanvas.size.height
    }

    /// 중심을 유지한 채 폭을 바꾼다. 종횡비는 항상 유지된다.
    func resized(width: Double) -> StickerObject {
        var copy = self
        let clamped = min(max(width, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        let height = Self.squareHeight(for: clamped)
        let middle = center
        copy.frame = NormalizedRect(
            x: middle.x - clamped / 2,
            y: middle.y - height / 2,
            width: clamped,
            height: height
        )
        return copy
    }

    /// 중심을 옮긴다. 위치 제약은 constrained(to:)에서 처리한다.
    func moved(to point: NormalizedPoint) -> StickerObject {
        var copy = self
        copy.frame = NormalizedRect(
            x: point.x - frame.width / 2,
            y: point.y - frame.height / 2,
            width: frame.width,
            height: frame.height
        )
        return copy
    }

    /// 스티커는 프레임 장식이다. **중심**이 프레임 밴드 안에 남도록만 제한한다.
    /// bounding box 전체를 가두지 않으므로 모서리를 걸치거나 살짝 넘어가는 디자인은 허용된다.
    /// 회전과 무관하게 중심만 보므로 회전했다고 위치가 튀지 않는다.
    func constrained(to insets: MirrorFrameInsets) -> StickerObject {
        let middle = center
        guard insets.isInsideMirrorArea(middle) else { return clampedToCanvas() }

        // 중앙에 들어갔다면 가장 가까운 밴드로 밀어낸다.
        let area = insets.mirrorArea
        let distances: [(Double, NormalizedPoint)] = [
            (middle.y - area.y, NormalizedPoint(x: middle.x, y: insets.top / 2)),
            (area.y + area.height - middle.y, NormalizedPoint(x: middle.x, y: 1 - insets.bottom / 2)),
            (middle.x - area.x, NormalizedPoint(x: insets.left / 2, y: middle.y)),
            (area.x + area.width - middle.x, NormalizedPoint(x: 1 - insets.right / 2, y: middle.y))
        ]
        let nearest = distances.min { $0.0 < $1.0 }?.1 ?? NormalizedPoint(x: insets.left / 2, y: middle.y)
        return moved(to: nearest).clampedToCanvas()
    }

    /// 중심이 캔버스 밖으로 나가지 않게 한다.
    private func clampedToCanvas() -> StickerObject {
        let middle = center
        return moved(to: NormalizedPoint(
            x: min(max(middle.x, 0), 1),
            y: min(max(middle.y, 0), 1)
        ))
    }

    /// 화면 좌표 hit test용 사각형. 회전은 근사로만 반영한다.
    func hitRect(in transform: MirrorViewTransform) -> CGRect {
        transform.rect(frame).insetBy(dx: -6, dy: -6)
    }
}

// MARK: - 배치

enum StickerPlacement {
    /// 지금 보고 있는 화면 중앙 근처의 프레임 영역에 넣는다.
    /// Right 하단을 보고 있으면 Right 하단에 생긴다.
    static func insert(
        _ source: StickerSource,
        in design: MirrorDesign,
        visibleRect: NormalizedRect,
        side: EditorSide
    ) -> StickerObject {
        let width = 0.16
        let height = StickerObject.squareHeight(for: width)
        let viewportCenter = NormalizedPoint(
            x: visibleRect.x + visibleRect.width / 2,
            y: visibleRect.y + visibleRect.height / 2
        )

        // 화면 중앙이 거울 영역이면 현재 편집 중인 밴드 쪽으로 당긴다.
        let insets = design.insets
        let placed: NormalizedPoint = if insets.isInsideMirrorArea(viewportCenter) {
            switch side {
            case .left: NormalizedPoint(x: insets.left / 2, y: viewportCenter.y)
            case .right: NormalizedPoint(x: 1 - insets.right / 2, y: viewportCenter.y)
            case .top: NormalizedPoint(x: viewportCenter.x, y: insets.top / 2)
            case .bottom: NormalizedPoint(x: viewportCenter.x, y: 1 - insets.bottom / 2)
            }
        } else {
            viewportCenter
        }

        let sticker = StickerObject(
            source: source,
            frame: NormalizedRect(
                x: placed.x - width / 2,
                y: placed.y - height / 2,
                width: width,
                height: height
            ),
            zIndex: (design.stickers.map(\.zIndex).max() ?? 0) + 1
        )
        return sticker.constrained(to: insets)
    }
}
