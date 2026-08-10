//
//  ShapeModels.swift
//  ggumirror
//
//  도형 / 꾸미기 요소. Sticker asset이 아니라 색과 크기를 자유롭게 바꾸는 Editor-native 오브젝트다.
//  좌표와 크기는 Sticker / Text와 같은 Master Canvas(1080 × 2340) normalized 값만 쓴다.
//
//  모양은 `ShapeKind.path(in:)` 한 곳에서만 만든다.
//  렌더러 / hit test / 미리보기가 같은 path 정의를 공유한다.
//

import SwiftUI

// MARK: - 종류

enum ShapeCategory: String, CaseIterable, Identifiable, Hashable {
    case all = "전체"
    case basic = "기본"
    case decorative = "꾸미기"

    var id: String { rawValue }
}

enum ShapeKind: String, CaseIterable, Identifiable, Hashable {
    // 기본 도형
    case circle, rectangle, roundedRectangle, line
    // 꾸미기 요소
    case heart, star, wave, ribbon, tape, speechBubble

    var id: String { rawValue }

    var title: String {
        switch self {
        case .circle: "원"
        case .rectangle: "사각형"
        case .roundedRectangle: "둥근 사각형"
        case .line: "선"
        case .heart: "하트"
        case .star: "별"
        case .wave: "물결선"
        case .ribbon: "리본 라인"
        case .tape: "테이프"
        case .speechBubble: "말풍선"
        }
    }

    var category: ShapeCategory {
        switch self {
        case .circle, .rectangle, .roundedRectangle, .line: .basic
        default: .decorative
        }
    }

    /// 선으로만 그리는 종류. 채우기가 의미 없다.
    var isStrokeOnly: Bool {
        switch self {
        case .line, .wave, .ribbon: true
        default: false
        }
    }

    /// 처음 놓을 때의 화면상 가로 / 세로 비율.
    var defaultAspectRatio: Double {
        switch self {
        case .circle, .heart, .star: 1
        case .rectangle, .roundedRectangle, .speechBubble: 1.4
        case .tape: 2.6
        case .line, .wave, .ribbon: 3.2
        }
    }

    /// 처음 놓을 때의 화면 폭 비율.
    var defaultWidth: Double {
        switch self {
        case .line, .wave, .ribbon, .tape: 0.34
        default: 0.24
        }
    }

    static func all(in category: ShapeCategory) -> [ShapeKind] {
        category == .all ? allCases : allCases.filter { $0.category == category }
    }

    /// 주어진 사각형 안의 모양. 회전 / 색은 렌더러가 처리한다.
    /// 매번 같은 결과를 내야 하므로 난수를 쓰지 않는다 — 저장 후 모습이 변하면 안 된다.
    func path(in rect: CGRect) -> Path {
        switch self {
        case .circle:
            return Path(ellipseIn: rect)

        case .rectangle:
            return Path(rect)

        case .roundedRectangle:
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.22)

        case .line:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path

        case .heart:
            // 단위 사각형에서 만들고 마지막에 늘린다 — 주어진 사각형을 넘지 않는다.
            var unit = Path()
            unit.move(to: CGPoint(x: 0.5, y: 1))
            unit.addCurve(
                to: CGPoint(x: 0, y: 0.3),
                control1: CGPoint(x: 0.2, y: 0.8),
                control2: CGPoint(x: 0, y: 0.6)
            )
            unit.addArc(
                center: CGPoint(x: 0.25, y: 0.3), radius: 0.25,
                startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
            )
            unit.addArc(
                center: CGPoint(x: 0.75, y: 0.3), radius: 0.25,
                startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
            )
            unit.addCurve(
                to: CGPoint(x: 0.5, y: 1),
                control1: CGPoint(x: 1, y: 0.6),
                control2: CGPoint(x: 0.8, y: 0.8)
            )
            unit.closeSubpath()
            return unit
                .applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
                .offsetBy(dx: rect.minX, dy: rect.minY)

        case .star:
            var path = Path()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let outer = min(rect.width, rect.height) / 2
            let inner = outer * 0.42
            for step in 0..<10 {
                let radius = step.isMultiple(of: 2) ? outer : inner
                let angle = -CGFloat.pi / 2 + CGFloat(step) * .pi / 5
                let point = CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )
                step == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.closeSubpath()
            return path

        case .wave:
            var path = Path()
            let amplitude = rect.height / 2
            let steps = 48
            for step in 0...steps {
                let ratio = CGFloat(step) / CGFloat(steps)
                let point = CGPoint(
                    x: rect.minX + rect.width * ratio,
                    y: rect.midY + sin(ratio * .pi * 4) * amplitude
                )
                step == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            return path

        case .ribbon:
            // 가운데 매듭이 있는 리본 끈. 선 하나로 이어 그린다.
            var path = Path()
            let knot = rect.width * 0.16
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX - knot, y: rect.midY))
            path.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.midY),
                control: CGPoint(x: rect.midX - knot, y: rect.minY)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.midX - knot, y: rect.midY),
                control: CGPoint(x: rect.midX - knot, y: rect.maxY)
            )
            path.move(to: CGPoint(x: rect.midX, y: rect.midY))
            path.addQuadCurve(
                to: CGPoint(x: rect.midX + knot, y: rect.midY),
                control: CGPoint(x: rect.midX + knot, y: rect.minY)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.midY),
                control: CGPoint(x: rect.midX + knot, y: rect.maxY)
            )
            path.move(to: CGPoint(x: rect.midX + knot, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path

        case .tape:
            // 끝이 살짝 잘린 마스킹 테이프. 고정된 모양이라 저장 후에도 변하지 않는다.
            var path = Path()
            let cut = rect.width * 0.06
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.midY))
            path.closeSubpath()
            return path

        case .speechBubble:
            let body = CGRect(
                x: rect.minX, y: rect.minY,
                width: rect.width, height: rect.height * 0.78
            )
            var path = Path(roundedRect: body, cornerRadius: min(body.width, body.height) * 0.28)
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.26, y: body.maxY - 1))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: body.maxY - 1))
            path.closeSubpath()
            return path
        }
    }
}

/// 칠하기 방식. 선으로만 그리는 종류는 언제나 `.stroke`다.
enum ShapeFillMode: String, CaseIterable, Identifiable, Hashable {
    case fill, stroke, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: "채우기"
        case .stroke: "테두리"
        case .both: "둘 다"
        }
    }

    var icon: String {
        switch self {
        case .fill: "square.fill"
        case .stroke: "square"
        case .both: "square.inset.filled"
        }
    }
}

// MARK: - 정책

enum ShapePolicy {
    /// 화면 폭 기준 크기 범위. 너무 작아 못 고르거나 거울을 통째로 덮지 않게 한다.
    static let widthRange: ClosedRange<Double> = 0.06...0.9
    /// Master Canvas 폭 기준 normalized 선 굵기. zoom과 무관하게 저장된다.
    static let strokeWidthRange: ClosedRange<Double> = (2 / 1080.0)...(40 / 1080.0)
    static let defaultStrokeWidth: Double = 8 / 1080.0
}

// MARK: - Object

struct ShapeObject: Identifiable, Hashable {
    var id = UUID()
    var kind: ShapeKind
    /// Master Canvas 기준 0...1 사각형.
    var frame: NormalizedRect
    var rotation: Double = 0
    var fillColor: Color = Color(red: 0.965, green: 0.886, blue: 0.886)
    var strokeColor: Color = PaperTheme.ink
    /// Master Canvas 폭 기준 normalized 굵기.
    var strokeWidth: Double = ShapePolicy.defaultStrokeWidth
    var fillMode: ShapeFillMode = .both
    var opacity: Double = 1
    var zIndex: Int = 0
    var isLocked = false

    /// 손가락으로 다시 고를 수 있는 최소 크기(pt). 스티커 / 텍스트와 같은 값이다.
    static let minimumTapTarget: CGFloat = StickerObject.minimumTapTarget

    /// 선으로만 그리는 종류는 채우기를 무시한다.
    var resolvedFillMode: ShapeFillMode {
        kind.isStrokeOnly ? .stroke : fillMode
    }

    var center: NormalizedPoint {
        NormalizedPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
    }

    /// 중심을 유지한 채 크기를 바꾼다. 가로 / 세로 비율은 그대로 — 찌그러지지 않는다.
    /// (한 방향만 늘리는 두 번째 handle은 만들지 않았다.)
    func resized(width: Double) -> ShapeObject {
        var copy = self
        let clamped = min(max(width, ShapePolicy.widthRange.lowerBound), ShapePolicy.widthRange.upperBound)
        let scale = clamped / max(frame.width, 0.0001)
        let height = frame.height * scale
        let middle = center
        copy.frame = NormalizedRect(
            x: middle.x - clamped / 2,
            y: middle.y - height / 2,
            width: clamped,
            height: height
        )
        return copy
    }

    func moved(to point: NormalizedPoint) -> ShapeObject {
        var copy = self
        copy.frame = NormalizedRect(
            x: point.x - frame.width / 2,
            y: point.y - frame.height / 2,
            width: frame.width,
            height: frame.height
        )
        return copy
    }

    /// 캔버스 어디에나 놓을 수 있다 — 카메라 영역도 포함이다.
    func constrained() -> ShapeObject {
        let middle = center
        return moved(to: NormalizedPoint(
            x: min(max(middle.x, 0), 1),
            y: min(max(middle.y, 0), 1)
        ))
    }

    /// 이 화면 좌표가 도형 위인지.
    /// 스티커 / 텍스트와 같은 규칙 — 중심 기준 역회전 + 최소 tap target.
    /// 선처럼 얇은 도형은 이 최소 크기 덕분에 자연스럽게 넉넉한 touch tolerance를 갖는다.
    func contains(_ location: CGPoint, in transform: MirrorViewTransform) -> Bool {
        let rect = transform.rect(frame)
        let dx = location.x - rect.midX
        let dy = location.y - rect.midY
        let radians = -CGFloat(rotation) * .pi / 180
        let localX = dx * cos(radians) - dy * sin(radians)
        let localY = dx * sin(radians) + dy * cos(radians)

        let width = max(rect.width, Self.minimumTapTarget)
        let height = max(rect.height, Self.minimumTapTarget)
        return abs(localX) <= width / 2 && abs(localY) <= height / 2
    }
}

// MARK: - 배치

enum ShapePlacement {
    /// 지금 보고 있는 화면 한가운데에 넣는다.
    /// 프레임이든 카메라 영역이든 사용자가 보고 있는 자리에 그대로 생긴다.
    static func insert(
        _ kind: ShapeKind,
        in design: MirrorDesign,
        visibleRect: NormalizedRect
    ) -> ShapeObject {
        let width = kind.defaultWidth
        // 화면상 비율을 유지하려면 Master Canvas가 세로로 긴 것을 보정해야 한다.
        let height = StickerObject.height(for: width, aspectRatio: kind.defaultAspectRatio)
        let center = NormalizedPoint(
            x: visibleRect.x + visibleRect.width / 2,
            y: visibleRect.y + visibleRect.height / 2
        )
        let shape = ShapeObject(
            kind: kind,
            frame: NormalizedRect(
                x: center.x - width / 2,
                y: center.y - height / 2,
                width: width,
                height: height
            ),
            fillMode: kind.isStrokeOnly ? .stroke : .both,
            zIndex: design.topDecorationZIndex + 1
        )
        return shape.constrained()
    }
}
