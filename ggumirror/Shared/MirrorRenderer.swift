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

    /// 화면을 꽉 채우고 넘치는 부분만 잘라내는 변환 (Uniform Scale + Crop).
    /// 카메라 preview의 resizeAspectFill과 같은 규칙이라 실제 Mirror / Capture가 같은 자리에 그린다.
    static func aspectFilled(in size: CGSize) -> MirrorViewTransform {
        let scale = max(size.width / MirrorCanvas.size.width, size.height / MirrorCanvas.size.height)
        let canvas = CGSize(
            width: MirrorCanvas.size.width * scale,
            height: MirrorCanvas.size.height * scale
        )
        return MirrorViewTransform(
            canvasSize: canvas,
            offset: CGPoint(x: (size.width - canvas.width) / 2, y: (size.height - canvas.height) / 2)
        )
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

    /// 레이어 순서 (실제 Mirror 기준):
    ///   카메라 → 프레임 배경 → 그림 → 템플릿 장식 → 스티커 / 텍스트(zIndex 순)
    ///
    /// 배경만 카메라 영역을 비운다. **장식은 전체 캔버스 어디든 그려진다** —
    /// 카메라 영역 위의 콧수염 / 하트 / 사진 스티커가 그대로 얼굴 위에 얹힌다.
    ///
    /// - Parameter mirrorAreaFill: 중앙 카메라 영역을 채울 색.
    ///   실제 카메라 위에 얹을 때는 nil을 줘서 완전히 투명하게 남긴다.
    ///   Editor는 배경색을 넘겨 한 장의 연속된 캔버스처럼 보이게 한다.
    static func draw(
        style: MirrorStyle,
        strokes: [DrawingStroke],
        stickers: [StickerObject] = [],
        texts: [TextObject] = [],
        importedArtworks: [ImportedArtworkObject] = [],
        activeStroke: DrawingStroke? = nil,
        hiddenStrokeIDs: Set<UUID> = [],
        transform: MirrorViewTransform,
        mirrorAreaFill: Color? = glass,
        in context: GraphicsContext,
        viewport: CGSize
    ) {
        let visible = CGRect(origin: .zero, size: viewport)
        let frame = framePath(insets: style.insets, transform: transform)

        // 1. 프레임 배경 + 종이 결 — 프레임 영역 안에서만 그린다.
        //    중앙은 손대지 않으므로 카메라 영상이 그대로 비친다.
        var paper = context
        paper.clip(to: frame, style: FrameMaskShape.fillStyle)
        paper.fill(frame, with: .color(style.frame), style: FrameMaskShape.fillStyle)
        drawGrain(in: paper, transform: transform, visible: visible)

        // 2. 중앙 Mirror Area (Editor / Gallery 미리보기에서만 칠한다)
        if let mirrorAreaFill {
            context.fill(
                style.insets.mirrorAreaPath(in: transform.canvasRect),
                with: .color(mirrorAreaFill)
            )
        }

        // 3. 사용자 획 — Master Canvas 안에서만 자른다.
        //    카메라 영역에서 잘리지 않는다. 프레임과 카메라를 가로지르는 획도 그대로 이어진다.
        var inked = context
        inked.clip(to: Path(transform.canvasRect))
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

        // 5. 사용자 오브젝트 — Drawing 위에 얹힌다.
        //    외부 디자인 / 스티커(사진 포함) / 텍스트를 **하나의 zIndex 순서**로 함께 그린다.
        //    선택 hit test도 정확히 같은 규칙을 뒤집어 쓴다 (DecorationLayer.renderRank).
        //    rank: zIndex가 같으면 외부 디자인(0) < 스티커(1) < 텍스트(2).
        let objects: [(order: (Int, Int), draw: () -> Void)] =
            importedArtworks.map { artwork in
                ((artwork.zIndex, 0), { drawImportedArtwork(artwork, in: context, transform: transform) })
            } + stickers.map { sticker in
                ((sticker.zIndex, 1), { drawSticker(sticker, in: context, transform: transform, visible: visible) })
            } + texts.map { text in
                ((text.zIndex, 2), { drawText(text, in: context, transform: transform, visible: visible) })
            }
        for object in objects.sorted(by: { $0.order < $1.order }) {
            object.draw()
        }
    }

    // MARK: - Imported artwork

    /// 외부 그림 앱에서 가져온 디자인. **Master Canvas 전체**에 그대로 얹는다.
    /// 카메라 영역을 따로 잘라내지 않는다 — 투명한 픽셀에서는 카메라가 그대로 비치고,
    /// 불투명한 픽셀에서는 그 그림이 카메라 위에 보인다. 이게 이 기능의 핵심이다.
    static func drawImportedArtwork(
        _ artwork: ImportedArtworkObject,
        in context: GraphicsContext,
        transform: MirrorViewTransform
    ) {
        // asset이 없으면 조용히 건너뛴다 — 파일을 못 찾아도 거울 전체가 깨지지 않는다.
        guard let image = ImportedArtworkAssetStore.shared.image(for: artwork.assetID) else { return }
        var layer = context
        layer.opacity = artwork.opacity
        layer.draw(context.resolve(Image(decorative: image, scale: 1)), in: transform.canvasRect)
    }

    // MARK: - Text

    /// 텍스트 한 덩이. 줄 배치 / 크기는 TextLayout 한 곳에서만 계산하므로
    /// Editor / 미리보기 / 실제 Mirror / Capture가 항상 같은 결과를 낸다.
    static func drawText(
        _ object: TextObject,
        in context: GraphicsContext,
        transform: MirrorViewTransform,
        visible: CGRect
    ) {
        guard !object.text.isEmpty else { return }
        let rect = transform.rect(object.frame)
        // 회전까지 고려해 넉넉히 잡고, 완전히 화면 밖일 때만 건너뛴다.
        let reach = max(rect.width, rect.height)
        guard rect.insetBy(dx: -reach / 2, dy: -reach / 2).intersects(visible) else { return }

        let layout = TextLayout.of(object)
        // Master 픽셀 → 화면 픽셀 배율. 한 번만 구해 모든 줄에 같이 쓴다.
        let scale = transform.canvasSize.width / MirrorCanvas.size.width
        let font = Font(object.style.font(ofSize: CGFloat(object.fontSize) * transform.canvasSize.width))

        var layer = context
        layer.opacity = object.opacity
        layer.translateBy(x: rect.midX, y: rect.midY)
        layer.rotate(by: .degrees(object.rotation))

        for index in layout.lines.indices where !layout.lines[index].isEmpty {
            let origin = layout.lineOrigin(index, alignment: object.alignment)
            let resolved = layer.resolve(Text(layout.lines[index]).font(font).foregroundStyle(object.color))
            layer.draw(resolved, at: CGPoint(
                x: (origin.x - layout.size.width / 2) * scale,
                y: (origin.y - layout.size.height / 2) * scale
            ), anchor: .topLeading)
        }
    }

    /// 전체 캔버스 − 중앙 Mirror Area(모서리 둥근 사각형). even-odd로 채우면 가운데가 뚫린다.
    /// 실제 Mirror / Capture의 투명 opening도 이 path 하나로 만들어진다.
    static func framePath(insets: MirrorFrameInsets, transform: MirrorViewTransform) -> Path {
        var path = Path(transform.canvasRect)
        path.addPath(insets.mirrorAreaPath(in: transform.canvasRect))
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

    // MARK: - Sticker

    static func drawSticker(
        _ sticker: StickerObject,
        in context: GraphicsContext,
        transform: MirrorViewTransform,
        visible: CGRect
    ) {
        let rect = transform.rect(sticker.frame)
        // 회전까지 고려해 넉넉히 잡고, 완전히 화면 밖일 때만 건너뛴다.
        let reach = max(rect.width, rect.height)
        guard rect.insetBy(dx: -reach / 2, dy: -reach / 2).intersects(visible) else { return }

        // 변형(이동 / 회전 / 뒤집기 / 투명도)은 source 종류와 무관하게 하나의 경로다.
        var layer = context
        layer.opacity = sticker.opacity
        layer.translateBy(x: rect.midX, y: rect.midY)
        layer.rotate(by: .degrees(sticker.rotation))
        if sticker.isFlippedHorizontally {
            layer.scaleBy(x: -1, y: 1)
        }

        let drawn: CGSize
        let artwork: GraphicsContext.ResolvedImage

        switch sticker.source {
        case .builtIn(let builtIn):
            var symbol = context.resolve(Image(systemName: builtIn.symbolName))
            // original 스티커(사진 등)는 원본 색을 유지한다.
            if let tint = sticker.resolvedTint {
                symbol.shading = .color(tint)
            }
            let intrinsic = symbol.size
            let scale = min(rect.width / intrinsic.width, rect.height / intrinsic.height)
            drawn = CGSize(width: intrinsic.width * scale, height: intrinsic.height * scale)
            artwork = symbol

        case .photo(let assetID, _):
            // asset이 없으면 조용히 건너뛴다 — 사진을 못 찾아도 거울 전체가 깨지지 않는다.
            guard let image = PhotoStickerAssetStore.shared.image(for: assetID) else { return }
            // frame이 이미 원본 비율을 담고 있으므로 그대로 채운다.
            drawn = rect.size
            artwork = context.resolve(Image(decorative: image, scale: 1))
        }

        layer.draw(artwork, in: CGRect(
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
