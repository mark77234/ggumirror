//
//  DrawingModels.swift
//  ggumirror
//
//  Drawing도 Master Canvas(1080 x 2340) normalized 좌표만 쓴다.
//  화면 좌표나 side별 캔버스를 따로 만들지 않는다.
//

import SwiftUI

// MARK: - Point

/// Master Canvas 기준 0...1 좌표.
struct NormalizedPoint: Hashable {
    var x: Double
    var y: Double

    func point(in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }

    /// 화면 비율이 아니라 Master Canvas 픽셀 기준 거리. x / y 스케일이 달라서 필요하다.
    func masterDistance(to other: NormalizedPoint) -> Double {
        let dx = (x - other.x) * MirrorCanvas.size.width
        let dy = (y - other.y) * MirrorCanvas.size.height
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - Brush

/// Clean Pen Sketch에 맞는 최소 preset. 굵기는 Master Canvas 폭 기준 normalized 값이다.
enum EditorBrush: String, CaseIterable, Identifiable {
    case fine, pen, marker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fine: "가는 펜"
        case .pen: "기본 펜"
        case .marker: "굵은 마커"
        }
    }

    /// 1080 기준 px을 normalized로 환산한 기본 굵기.
    var defaultWidth: Double {
        switch self {
        case .fine: 5 / MirrorCanvas.size.width
        case .pen: 11 / MirrorCanvas.size.width
        case .marker: 30 / MirrorCanvas.size.width
        }
    }

    var opacity: Double {
        switch self {
        case .marker: 0.75
        default: 1
        }
    }

    /// 슬라이더 범위도 normalized.
    static let widthRange: ClosedRange<Double> =
        (3 / MirrorCanvas.size.width)...(56 / MirrorCanvas.size.width)
}

// MARK: - Stroke

/// 획 하나가 오브젝트 하나. side별로 잘라 복제하지 않는다.
struct DrawingStroke: Identifiable, Hashable {
    var id = UUID()
    var points: [NormalizedPoint]
    var brush: EditorBrush = .pen
    var color: Color = PaperTheme.ink
    /// Master Canvas 폭 기준 normalized 굵기.
    var width: Double
    var opacity: Double = 1
    var zIndex: Int = 0

    /// 지우개 hit test. Master Canvas 픽셀 기준으로 잰다.
    func isHit(by point: NormalizedPoint, radius: Double) -> Bool {
        let reach = radius + width * MirrorCanvas.size.width / 2
        return points.contains { $0.masterDistance(to: point) <= reach }
    }
}

// MARK: - Frame mask

/// 그릴 수 있는 영역 = 전체 캔버스 − 중앙 Mirror Area.
/// 두께는 template마다 다르므로 항상 design의 frameInsets에서 계산한다.
struct FrameMaskShape: Shape {
    let insets: MirrorFrameInsets

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let mirror = insets.mirrorArea
            .rect(in: rect.size)
            .offsetBy(dx: rect.minX, dy: rect.minY)
        path.addRect(mirror)
        return path   // even-odd로 채우면 가운데가 뚫린다
    }

    static let fillStyle = FillStyle(eoFill: true)
}

extension MirrorFrameInsets {
    /// 중앙 Mirror Area 안쪽인지. 여기에는 그림이 남으면 안 된다.
    func isInsideMirrorArea(_ point: NormalizedPoint) -> Bool {
        let area = mirrorArea
        return point.x > area.x
            && point.x < area.x + area.width
            && point.y > area.y
            && point.y < area.y + area.height
    }
}

// MARK: - Render

enum StrokeRenderer {
    /// midpoint quadratic으로 이어 각지지 않게 그린다.
    static func path(for stroke: DrawingStroke, in size: CGSize) -> Path {
        let points = stroke.points.map { $0.point(in: size) }
        var path = Path()
        guard let first = points.first else { return path }

        guard points.count > 1 else {
            let radius = stroke.width * size.width / 2
            path.addEllipse(in: CGRect(
                x: first.x - radius,
                y: first.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            return path
        }

        path.move(to: first)
        guard points.count > 2 else {
            path.addLine(to: points[1])
            return path
        }

        for index in 1..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: current)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    static func draw(_ stroke: DrawingStroke, in context: GraphicsContext, size: CGSize) {
        let path = path(for: stroke, in: size)
        let shading = GraphicsContext.Shading.color(stroke.color.opacity(stroke.opacity))

        if stroke.points.count <= 1 {
            context.fill(path, with: shading)
        } else {
            context.stroke(
                path,
                with: shading,
                style: StrokeStyle(
                    lineWidth: stroke.width * size.width,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }
}

// MARK: - History

/// stroke 배열 스냅샷 기반 Undo / Redo. 추가 / 지우기 모두 같은 방식으로 처리된다.
struct DrawingHistory {
    private var undoStack: [[DrawingStroke]] = []
    private var redoStack: [[DrawingStroke]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// 새 작업이 생기면 redo는 버린다.
    mutating func commit(_ new: [DrawingStroke], to strokes: inout [DrawingStroke]) {
        guard new != strokes else { return }
        undoStack.append(strokes)
        redoStack.removeAll()
        strokes = new
    }

    mutating func undo(_ strokes: inout [DrawingStroke]) {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = previous
    }

    mutating func redo(_ strokes: inout [DrawingStroke]) {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
    }
}
