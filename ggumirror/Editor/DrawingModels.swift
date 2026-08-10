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
    case fine, pen, pencil, marker, highlighter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fine: "가는 펜"
        case .pen: "기본 펜"
        case .pencil: "연필"
        case .marker: "마커"
        case .highlighter: "형광펜"
        }
    }

    /// 1080 기준 px을 normalized로 환산한 기본 굵기.
    var defaultWidth: Double {
        switch self {
        case .fine: 5 / MirrorCanvas.size.width
        case .pen: 11 / MirrorCanvas.size.width
        case .pencil: 8 / MirrorCanvas.size.width
        case .marker: 30 / MirrorCanvas.size.width
        case .highlighter: 46 / MirrorCanvas.size.width
        }
    }

    /// 현재 renderer로 표현 가능한 범위의 차이만 쓴다.
    /// 종이 질감 연필 / 크레용 같은 texture brush는 후속 Phase.
    var opacity: Double {
        switch self {
        case .pencil: 0.85
        case .marker: 0.8
        case .highlighter: 0.32
        default: 1
        }
    }

    /// 형광펜만 끝을 각지게 해서 마커 느낌을 준다.
    var lineCap: CGLineCap {
        switch self {
        case .highlighter: .square
        default: .round
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
        path.addPath(insets.mirrorAreaPath(in: rect))
        return path   // even-odd로 채우면 가운데가 뚫린다
    }

    static let fillStyle = FillStyle(eoFill: true)
}

extension MirrorFrameInsets {
    /// 실제 거울에서 카메라가 비치는 영역 안쪽인지.
    /// **장식 금지 구역이 아니다** — 배경을 비우고 Editor 안내 점선을 그릴 때 쓰는 판정이다.
    /// 모서리가 둥근 사각형이므로 곡선 바깥은 프레임 쪽으로 본다.
    func isInsideMirrorArea(_ point: NormalizedPoint) -> Bool {
        let area = mirrorArea
        guard point.x > area.x, point.x < area.x + area.width,
              point.y > area.y, point.y < area.y + area.height
        else { return false }

        // Master 기준 원형 모서리를 normalized로 보면 타원이 된다.
        let rx = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.width
        let ry = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.height
        let dx = max(area.x + rx - point.x, point.x - (area.x + area.width - rx), 0)
        let dy = max(area.y + ry - point.y, point.y - (area.y + area.height - ry), 0)
        guard dx > 0, dy > 0 else { return true }   // 모서리 사각형 밖 = 직선 구간
        let nx: Double = dx / rx
        let ny: Double = dy / ry
        return nx * nx + ny * ny <= 1
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
                    lineCap: stroke.brush.lineCap,
                    lineJoin: .round
                )
            )
        }
    }
}

// MARK: - History

/// Editor가 되돌릴 수 있는 편집 의도.
/// 배열 스냅샷을 통째로 넘기지 않으므로 오래된 복사본이 최신 상태를 덮어쓰지 않는다.
enum EditorEdit {
    case addStroke(DrawingStroke)
    case eraseStrokes(Set<UUID>)
    case addSticker(StickerObject)
    /// 이동 / 크기 / 회전 / 뒤집기 / 잠금 / 투명도 — 모두 최종값 1회 반영.
    case replaceSticker(StickerObject)
    case deleteSticker(UUID)
    case addText(TextObject)
    /// 내용 / 이동 / 크기 / 회전 / 색 / 글꼴 / 정렬 / 잠금 / 투명도 — 최종값 1회 반영.
    case replaceText(TextObject)
    case deleteText(UUID)
    /// Layers에서 순서를 바꿨다. 앞에 보이는 것부터 나열한 id 목록.
    /// drag 중이 아니라 놓았을 때 1회만 들어온다.
    case reorderDecorations(frontToBack: [UUID])
}

/// Undo / Redo가 되돌리는 편집 대상 전체.
struct EditorSnapshot: Equatable {
    var strokes: [DrawingStroke] = []
    var stickers: [StickerObject] = []
    var texts: [TextObject] = []
}

/// Drawing / Sticker / Text를 하나의 시간순 history로 관리한다.
/// Pan / Zoom / Scroll Handle / Fit 같은 viewport 조작은 여기 들어오지 않는다.
struct EditorHistory {
    private var undoStack: [EditorSnapshot] = []
    private var redoStack: [EditorSnapshot] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// 새 작업이 생기면 redo는 버린다.
    mutating func commit(_ new: EditorSnapshot, to snapshot: inout EditorSnapshot) {
        guard new != snapshot else { return }
        undoStack.append(snapshot)
        redoStack.removeAll()
        snapshot = new
    }

    /// 편집 의도를 **지금 시점의** 상태에 적용한다.
    mutating func apply(_ edit: EditorEdit, to snapshot: inout EditorSnapshot) {
        var updated = snapshot
        switch edit {
        case .addStroke(let stroke):
            guard !updated.strokes.contains(where: { $0.id == stroke.id }) else { return }
            updated.strokes.append(stroke)
        case .eraseStrokes(let ids):
            updated.strokes.removeAll { ids.contains($0.id) }
        case .addSticker(let sticker):
            guard !updated.stickers.contains(where: { $0.id == sticker.id }) else { return }
            updated.stickers.append(sticker)
        case .replaceSticker(let sticker):
            guard let index = updated.stickers.firstIndex(where: { $0.id == sticker.id }) else { return }
            updated.stickers[index] = sticker
        case .deleteSticker(let id):
            updated.stickers.removeAll { $0.id == id }
        case .addText(let text):
            guard !updated.texts.contains(where: { $0.id == text.id }) else { return }
            updated.texts.append(text)
        case .replaceText(let text):
            guard let index = updated.texts.firstIndex(where: { $0.id == text.id }) else { return }
            updated.texts[index] = text
        case .deleteText(let id):
            updated.texts.removeAll { $0.id == id }
        case .reorderDecorations(let frontToBack):
            updated.reorderDecorations(frontToBack: frontToBack)
        }
        commit(updated, to: &snapshot)
    }

    mutating func undo(_ snapshot: inout EditorSnapshot) {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        snapshot = previous
    }

    mutating func redo(_ snapshot: inout EditorSnapshot) {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        snapshot = next
    }
}

extension MirrorDesign {
    /// history가 다루는 편집 대상만 떼어내고 되돌려 받는다.
    var snapshot: EditorSnapshot {
        get { EditorSnapshot(strokes: strokes, stickers: stickers, texts: texts) }
        set {
            strokes = newValue.strokes
            stickers = newValue.stickers
            texts = newValue.texts
        }
    }
}
