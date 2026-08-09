//
//  MirrorRenderer.swift
//  ggumirror
//
//  거울 한 장을 GraphicsContext에 그리는 단일 렌더러.
//
//  파이프라인:
//    Master Canvas content → FrameMask → viewport transform → viewport clip
//
//  중요: 뷰를 Master Canvas 크기로 키워서 offset으로 밀지 않는다.
//  확대 배율이 커지면 레이어가 GPU 텍스처 한계를 넘어 통째로 렌더되지 않는 문제가 생긴다.
//  대신 뷰는 항상 viewport 크기이고, 확대/이동은 그리는 좌표에만 반영한다.
//

import SwiftUI

/// Master Canvas를 화면에 놓는 방법. canvasSize는 확대까지 반영된 크기다.
struct MirrorViewTransform: Equatable {
    var canvasSize: CGSize
    var offset: CGPoint

    /// 변환 없이 주어진 크기에 꽉 채우는 기본 변환.
    static func fitted(in size: CGSize) -> MirrorViewTransform {
        MirrorViewTransform(canvasSize: size, offset: .zero)
    }

    func rect(_ normalized: NormalizedRect) -> CGRect {
        normalized.rect(in: canvasSize).offsetBy(dx: offset.x, dy: offset.y)
    }

    func point(_ normalized: NormalizedPoint) -> CGPoint {
        CGPoint(
            x: normalized.x * canvasSize.width + offset.x,
            y: normalized.y * canvasSize.height + offset.y
        )
    }

    var canvasRect: CGRect {
        CGRect(origin: offset, size: canvasSize)
    }
}

enum MirrorRenderer {
    /// 거울 면. 그라디언트 없이 평평한 톤으로만 표현한다.
    static let glass = Color(red: 0.129, green: 0.125, blue: 0.145)

    static func draw(
        style: MirrorStyle,
        strokes: [DrawingStroke],
        activeStroke: DrawingStroke? = nil,
        hiddenStrokeIDs: Set<UUID> = [],
        transform: MirrorViewTransform,
        in context: GraphicsContext,
        viewport: CGSize
    ) {
        let canvas = transform.canvasRect
        let visible = CGRect(origin: .zero, size: viewport)

        // 1. 프레임 배경 + 종이 결
        context.fill(Path(canvas), with: .color(style.frame))
        drawGrain(in: context, transform: transform, visible: visible)

        // 2. 중앙 Mirror Area
        let mirror = transform.rect(style.insets.mirrorArea)
        context.fill(
            Path(roundedRect: mirror, cornerRadius: min(10, mirror.width / 8)),
            with: .color(glass)
        )

        // 3. 사용자 획 — FrameMask 안에서만 보인다.
        //    데이터를 자르지 않고 clip으로만 가린다.
        var inked = context
        inked.clip(to: framePath(insets: style.insets, transform: transform), style: FrameMaskShape.fillStyle)
        for stroke in strokes.filter({ !hiddenStrokeIDs.contains($0.id) }).sorted(by: { $0.zIndex < $1.zIndex }) {
            drawStroke(stroke, in: inked, transform: transform, visible: visible)
        }
        if let activeStroke {
            drawStroke(activeStroke, in: inked, transform: transform, visible: visible)
        }

        // 4. 템플릿 장식
        for doodle in style.doodles {
            drawDoodle(doodle, in: context, transform: transform, visible: visible)
        }
    }

    /// 전체 캔버스 − 중앙 Mirror Area. even-odd로 채우면 가운데가 뚫린다.
    static func framePath(insets: MirrorFrameInsets, transform: MirrorViewTransform) -> Path {
        var path = Path(transform.canvasRect)
        path.addRect(transform.rect(insets.mirrorArea))
        return path
    }

    // MARK: - Stroke

    private static func drawStroke(
        _ stroke: DrawingStroke,
        in context: GraphicsContext,
        transform: MirrorViewTransform,
        visible: CGRect
    ) {
        let path = StrokeRenderer.path(for: stroke, in: transform.canvasSize)
            .offsetBy(dx: transform.offset.x, dy: transform.offset.y)
        let lineWidth = stroke.width * transform.canvasSize.width

        // 화면과 전혀 겹치지 않을 때만 건너뛴다.
        // 일부만 걸친 획은 반드시 그린다 — 통째로 사라지면 안 된다.
        guard path.boundingRect.insetBy(dx: -lineWidth, dy: -lineWidth).intersects(visible) else { return }

        let shading = GraphicsContext.Shading.color(stroke.color.opacity(stroke.opacity))
        if stroke.points.count <= 1 {
            context.fill(path, with: shading)
        } else {
            context.stroke(
                path,
                with: shading,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: stroke.brush.lineCap, lineJoin: .round)
            )
        }
    }

    // MARK: - Doodle

    private static func drawDoodle(
        _ doodle: MirrorStyle.Doodle,
        in context: GraphicsContext,
        transform: MirrorViewTransform,
        visible: CGRect
    ) {
        let side = doodle.size * transform.canvasSize.width
        let center = transform.point(NormalizedPoint(x: doodle.x, y: doodle.y))
        let box = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        guard box.intersects(visible) else { return }

        var symbol = context.resolve(Image(systemName: doodle.symbol))
        symbol.shading = .color(PaperTheme.ink.opacity(0.75))

        // 원본 비율을 유지하면서 원하는 크기로 그린다.
        let intrinsic = symbol.size
        let scale = side / max(intrinsic.width, intrinsic.height)
        let drawn = CGSize(width: intrinsic.width * scale, height: intrinsic.height * scale)

        var rotated = context
        rotated.translateBy(x: center.x, y: center.y)
        rotated.rotate(by: .degrees(doodle.rotation))
        rotated.draw(symbol, in: CGRect(
            x: -drawn.width / 2, y: -drawn.height / 2,
            width: drawn.width, height: drawn.height
        ))
    }

    // MARK: - Paper grain

    /// 결정적 speckle. 배율과 무관하게 Master Canvas 기준으로 흩뿌린다.
    private static func drawGrain(
        in context: GraphicsContext,
        transform: MirrorViewTransform,
        visible: CGRect
    ) {
        var seed: UInt64 = 20_260_809
        func random() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(UInt32.max)
        }

        let dotSize = max(transform.canvasSize.width / 900, 0.6)
        for _ in 0..<2600 {
            let point = transform.point(NormalizedPoint(x: random(), y: random()))
            let alpha = 0.03 + random() * 0.04
            let box = CGRect(
                x: point.x, y: point.y,
                width: dotSize * (1 + random()), height: dotSize * (1 + random())
            )
            guard box.intersects(visible) else { continue }
            context.fill(Path(ellipseIn: box), with: .color(PaperTheme.ink.opacity(alpha)))
        }
    }
}
