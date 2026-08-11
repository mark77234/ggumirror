//
//  StickerResizeTests.swift
//  ggumirrorTests
//
//  스티커 크기 조절. 두 가지를 지킨다.
//
//  1. **비율은 절대 변하지 않는다.** 어떤 스티커든, 어떤 각도로 돌아가 있든,
//     어느 캔버스에 있든 uniform scale이다. 눌리거나 늘어나면 실패다.
//  2. **최대 크기 제한이 없다.** 캔버스보다 몇 배로도 키울 수 있고 캔버스를 넘어가도 된다.
//     (viewport 확대 1…4는 보기 배율이고 오브젝트 크기와 별개다.)
//
//  source 코드만 믿지 않는다 — **렌더된 bitmap의 bounding box**로 비율을 재확인한다.
//

import Testing
import SwiftUI
import UIKit
@testable import ggumirror

@MainActor
struct StickerResizeTests {

    // MARK: - 도구

    private func render(_ view: some View, size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.cgImage
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &data, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// 실제로 그려진 픽셀의 bounding box. 비율 검증의 근거다.
    private func inkBounds(_ image: CGImage) -> CGRect? {
        let data = pixels(image)
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let index = (y * image.width + x) * 4
                guard data[index + 3] > 30 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// 스티커 하나만 있는 캔버스를 **투명하게** 렌더해 bounding box를 잰다.
    ///
    /// 편집용 `MirrorCanvasView`를 쓰면 체크무늬가 함께 칠해져 모든 픽셀이 불투명해진다 —
    /// 그러면 bounding box가 언제나 캔버스 전체가 되어 비율을 재는 의미가 없다.
    private func stickerBounds(_ object: StickerObject, size: CGFloat = 300) -> CGRect? {
        var design = MirrorDesign.blankSticker(id: "resize", name: "resize")
        design.stickers = [object]
        guard let image = StickerRenderer.render(design, size: CGSize(width: size, height: size)) else {
            return nil
        }
        return inkBounds(image)
    }

    private func doodle(
        _ sticker: DoodleSticker = .heart,
        width: Double,
        canvas: CanvasKind = .sticker,
        rotation: Double = 0
    ) -> StickerObject {
        let source = StickerSource.doodle(sticker)
        let height = StickerObject.height(for: width, aspectRatio: source.aspectRatio, canvas: canvas)
        return StickerObject(
            source: source,
            frame: NormalizedRect(x: 0.5 - width / 2, y: 0.5 - height / 2, width: width, height: height),
            rotation: rotation
        )
    }

    /// 세로로 긴 가짜 사진 cutout (사람 사진처럼 2:3).
    private func tallPhoto() -> StickerSource {
        let context = CGContext(
            data: nil, width: 200, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        return PhotoStickerAssetStore.shared.register(context.makeImage()!)
    }

    private func photo(_ source: StickerSource, width: Double, canvas: CanvasKind, rotation: Double = 0) -> StickerObject {
        let height = StickerObject.height(for: width, aspectRatio: source.aspectRatio, canvas: canvas)
        return StickerObject(
            source: source,
            frame: NormalizedRect(x: 0.5 - width / 2, y: 0.5 - height / 2, width: width, height: height),
            rotation: rotation
        )
    }

    /// 정규화 폭/높이 비율. 캔버스 비율을 곱해 **화면에서 보이는** 비율로 바꾼다.
    private func visualRatio(_ object: StickerObject, canvas: CanvasKind) -> Double {
        (object.frame.width * canvas.size.width) / (object.frame.height * canvas.size.height)
    }

    // MARK: - 비율 유지

    @Test("두들 크기를 바꿔도 비율이 그대로다", arguments: [CanvasKind.mirror, .sticker])
    func doodleResizePreservesAspect(canvas: CanvasKind) {
        let base = doodle(width: 0.2, canvas: canvas)
        let before = visualRatio(base, canvas: canvas)

        for width in [0.05, 0.3, 1.0, 2.5, 8.0] {
            let resized = base.resized(width: width, canvas: canvas)
            #expect(abs(visualRatio(resized, canvas: canvas) - before) < 0.001,
                    "\(canvas.rawValue) @\(width): \(visualRatio(resized, canvas: canvas)) != \(before)")
        }
    }

    @Test("사진 스티커는 원본 비율을 유지한다", arguments: [CanvasKind.mirror, .sticker])
    func photoResizePreservesSourceAspect(canvas: CanvasKind) {
        let source = tallPhoto()
        let base = photo(source, width: 0.3, canvas: canvas)
        // 원본은 2:3 세로 사진이다.
        #expect(abs(source.aspectRatio - 200.0 / 300.0) < 0.001)

        for width in [0.1, 0.6, 2.0, 6.0] {
            let resized = base.resized(width: width, canvas: canvas)
            // 화면에서 보이는 비율이 원본 픽셀 비율과 같다 — 사람이 옆으로 퍼지지 않는다.
            #expect(abs(visualRatio(resized, canvas: canvas) - source.aspectRatio) < 0.001)
        }
    }

    @Test("legacy 스티커도 같은 규칙을 따른다")
    func legacyResizePreservesAspect() {
        let source = StickerSource.builtIn(.heart)
        let base = photo(source, width: 0.2, canvas: .mirror)
        let before = visualRatio(base, canvas: .mirror)
        for width in [0.5, 3.0] {
            #expect(abs(visualRatio(base.resized(width: width), canvas: .mirror) - before) < 0.001)
        }
    }

    @Test("사용자 스티커 캔버스(1024²)에서도 비율이 유지된다")
    func userStickerCanvasPreservesAspect() {
        // 정사각 캔버스에서 거울 비율로 높이를 구하면 납작해졌다 — 그게 찌그러짐의 원인이었다.
        let base = doodle(width: 0.3, canvas: .sticker)
        let resized = base.resized(width: 0.9, canvas: .sticker)
        #expect(abs(resized.frame.width - resized.frame.height) < 0.0001, "정사각 캔버스에서 정사각이어야 한다")

        // 캔버스를 안 넘겨주면(예전 기본값) 납작해진다는 것을 함께 고정해 둔다.
        let wrong = base.resized(width: 0.9)
        #expect(wrong.frame.height < wrong.frame.width * 0.6)
    }

    @Test("회전한 스티커도 비율이 유지된다", arguments: [0.0, 30, 45, 89, 90, 91, 135, 180, 269, 270, 359])
    func rotatedResizePreservesAspect(rotation: Double) {
        for canvas in [CanvasKind.mirror, .sticker] {
            let base = doodle(width: 0.2, canvas: canvas, rotation: rotation)
            let before = visualRatio(base, canvas: canvas)
            let resized = base.resized(width: 1.2, canvas: canvas)
            #expect(abs(visualRatio(resized, canvas: canvas) - before) < 0.001, "\(rotation)°")
            // 회전값 자체는 크기 조절로 바뀌지 않는다.
            #expect(resized.rotation == rotation)
        }

        // 사진도 같다.
        let source = tallPhoto()
        let base = photo(source, width: 0.3, canvas: .mirror, rotation: rotation)
        let resized = base.resized(width: 1.5)
        #expect(abs(visualRatio(resized, canvas: .mirror) - source.aspectRatio) < 0.001)
    }

    @Test("크기 조절은 하나의 배율만 쓴다 — 폭/높이 독립 경로가 없다")
    func noIndependentWidthHeightPath() throws {
        // 제스처는 스칼라 하나(`alongWidth`)를 넘기고, 높이는 원본 비율에서 다시 계산된다.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "ggumirror")
        let canvas = try String(
            contentsOf: root.appending(path: "Editor/MirrorEditorCanvas.swift"), encoding: .utf8
        )
        #expect(canvas.contains("resized(width:"))
        // 높이를 직접 넣는 경로가 생기면 여기서 걸린다.
        #expect(!canvas.contains("frame.height ="))
        #expect(!canvas.contains("height: base.frame.height +"))

        let overlay = try String(
            contentsOf: root.appending(path: "Editor/StickerSelectionOverlay.swift"), encoding: .utf8
        )
        // handle은 x/y를 각각 넘기지 않는다 — 오브젝트 방향으로 투영한 스칼라 하나다.
        #expect(overlay.contains("alongWidth"))
        #expect(overlay.contains("onResize(alongWidth"))
    }

    // MARK: - bitmap 검증

    @Test("렌더된 두들의 bounding box 비율이 유지된다")
    func renderedDoodleKeepsAspect() throws {
        let small = try #require(stickerBounds(doodle(.ribbon, width: 0.25)))
        let large = try #require(stickerBounds(doodle(.ribbon, width: 0.25).resized(width: 0.7, canvas: .sticker)))

        let smallRatio = small.width / small.height
        let largeRatio = large.width / large.height
        #expect(abs(smallRatio - largeRatio) < 0.08, "작을 때 \(smallRatio), 클 때 \(largeRatio)")
        // 실제로 커졌다.
        #expect(large.width > small.width * 1.5)
    }

    @Test("렌더된 사진의 bounding box가 원본 비율을 지킨다")
    func renderedPhotoKeepsSourceAspect() throws {
        let source = tallPhoto()
        let base = photo(source, width: 0.3, canvas: .sticker)
        let bounds = try #require(stickerBounds(base))
        // 2:3 세로 사진 → 그려진 상자도 2:3.
        #expect(abs(bounds.width / bounds.height - source.aspectRatio) < 0.06)

        // 캔버스 안에 다 들어오는 크기로 키운다 — 넘어가면 경계에서 잘려(의도된 동작)
        // bounding box가 잘린 만큼만 나온다. 잘림 자체는 아래 rendererClipsInsteadOfFitting이 본다.
        let big = try #require(stickerBounds(base.resized(width: 0.6, canvas: .sticker)))
        #expect(abs(big.width / big.height - source.aspectRatio) < 0.06)
        #expect(big.height > bounds.height * 1.5)
    }

    @Test("찌그러진 frame이 들어와도 두들은 늘어나지 않는다")
    func doodleNeverStretchesEvenWithSquashedFrame() throws {
        // 예전 데이터나 잘못된 계산으로 정사각이 아닌 frame이 와도 디자인은 그대로여야 한다.
        var squashed = doodle(.ring, width: 0.6)
        squashed.frame = NormalizedRect(x: 0.2, y: 0.35, width: 0.6, height: 0.2)
        let bounds = try #require(stickerBounds(squashed))
        // 동그라미는 여전히 동그랗다 (짧은 변에 맞춰 그린다).
        #expect(abs(bounds.width / bounds.height - 1) < 0.15, "비율 \(bounds.width / bounds.height)")
    }

    // MARK: - 최대 제한 없음

    @Test("제품 차원의 최대 크기 제한이 없다")
    func noProductMaximumScale() throws {
        // 모델에 상한이 없다.
        #expect(StickerObject.minimumWidth > 0)
        for width in [1.0, 3.0, 12.0, 50.0] {
            #expect(doodle(width: 0.2).resized(width: width, canvas: .sticker).frame.width == width)
            #expect(doodle(width: 0.2, canvas: .mirror).resized(width: width).frame.width == width)
        }

        // 소스에도 상한이 남아 있지 않다.
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "ggumirror/Editor/StickerModels.swift"),
            encoding: .utf8
        )
        #expect(!source.contains("sizeRange"))
        #expect(!source.contains("maxScale"))
        #expect(!source.contains("maximumScale"))
    }

    @Test("스티커는 캔버스보다 커질 수 있다", arguments: [CanvasKind.mirror, .sticker])
    func stickerCanExceedCanvas(canvas: CanvasKind) {
        let base = doodle(width: 0.2, canvas: canvas)
        for multiple in [2.0, 3.0, 5.0] {
            let huge = base.resized(width: multiple, canvas: canvas).constrained()
            // 폭이 캔버스를 넘는다. (거울 캔버스는 세로로 길어서 폭 2배가 높이로는 0.92배다 —
            // 그래서 높이는 "넘는다"가 아니라 "비례해서 커졌다"로 본다.)
            #expect(huge.frame.width > 1)
            #expect(huge.frame.height > base.frame.height * multiple * 0.99)
            // 중심만 캔버스 안에 남는다 — 완전히 사라지지 않게 하는 최소한의 제약이다.
            #expect(huge.center.x >= 0 && huge.center.x <= 1)
            #expect(huge.center.y >= 0 && huge.center.y <= 1)
        }
    }

    @Test("viewport 확대 한계가 오브젝트 크기를 묶지 않는다")
    func viewportZoomDoesNotClampObjectScale() {
        // 보기 배율은 1…4다.
        #expect(EditorViewportState.zoomRange == 1...4)
        // 오브젝트는 그와 무관하게 10배도 된다.
        let huge = doodle(width: 0.2).resized(width: 10, canvas: .sticker)
        #expect(huge.frame.width == 10)
        #expect(huge.frame.width > EditorViewportState.zoomRange.upperBound)
    }

    // MARK: - 안전값

    @Test("최소 크기는 지켜진다")
    func minimumSizeIsProtected() {
        let base = doodle(width: 0.3)
        for width in [0.0, -1.0, 0.000001] {
            let tiny = base.resized(width: width, canvas: .sticker)
            #expect(tiny.frame.width == StickerObject.minimumWidth)
            #expect(tiny.frame.height > 0)
        }
    }

    @Test("NaN / 무한 크기는 걸러진다")
    func nonFiniteSizeIsRejected() {
        let base = doodle(width: 0.3)
        for width in [Double.nan, .infinity, -.infinity] {
            // 계산이 깨진 값이면 지금 크기를 그대로 둔다.
            let result = base.resized(width: width, canvas: .sticker)
            #expect(result.frame.width == base.frame.width)
            #expect(result.frame.height.isFinite)
        }

        // 이미 깨진 frame이 들어와도 constrained가 살려낸다.
        var broken = base
        broken.frame = NormalizedRect(x: .nan, y: 0.5, width: .infinity, height: .nan)
        let fixed = broken.constrained()
        #expect(fixed.frame.width.isFinite)
        #expect(fixed.frame.height.isFinite)
        #expect(fixed.frame.width >= StickerObject.minimumWidth)
        #expect(fixed.center.x.isFinite && fixed.center.y.isFinite)
    }

    // MARK: - 저장 / 렌더

    @Test("캔버스 2배 · 5배 크기가 저장되고 복원된다", arguments: [2.0, 5.0])
    func largeScalePersists(multiple: Double) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-resize-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = MirrorStore(root: root)
        defer {
            store.flush()
            try? FileManager().removeItem(at: root)
        }

        let library = MirrorLibrary(
            store: store, assets: PhotoStickerAssetStore(), artworks: ImportedArtworkAssetStore()
        )
        var design = MirrorDesign.blank
        let huge = doodle(width: 0.2, canvas: .mirror).resized(width: multiple).constrained()
        design.stickers = [huge]
        _ = library.save(design, name: "큰 스티커", context: .createNew)
        store.flush()

        let reloaded = MirrorLibrary(
            store: store, assets: PhotoStickerAssetStore(), artworks: ImportedArtworkAssetStore()
        )
        let restored = try #require(reloaded.mirrors.first?.stickers.first)
        // 저장 단계에서 예전 상한(0.45)으로 깎이지 않는다.
        #expect(abs(restored.frame.width - multiple) < 0.0001)
        #expect(abs(restored.frame.height - huge.frame.height) < 0.0001)
    }

    @Test("스티커 프로젝트도 큰 크기를 그대로 저장한다")
    func largeScalePersistsInStickerProject() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-resize-sticker-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = StickerProjectStore(root: root)
        defer {
            store.flush()
            try? FileManager().removeItem(at: root)
        }

        let library = StickerLibrary(store: store)
        var design = MirrorDesign.blankSticker(id: UUID().uuidString, name: "큰 스티커")
        design.stickers = [doodle(width: 0.3).resized(width: 4, canvas: .sticker).constrained()]
        let saved = try #require(library.save(design, name: "큰 스티커", context: .createNew))
        store.flush()

        let restored = try #require(StickerLibrary(store: store).project(id: saved.id))
        let sticker = try #require(restored.design.stickers.first)
        #expect(abs(sticker.frame.width - 4) < 0.0001)
        #expect(abs(sticker.frame.height - 4) < 0.0001)   // 정사각 캔버스
    }

    @Test("렌더러가 큰 스티커를 억지로 줄이지 않고 캔버스에서만 자른다")
    func rendererClipsInsteadOfFitting() throws {
        // 캔버스보다 3배 큰 스티커를 가운데 둔다 → 캔버스가 통째로 덮여야 한다.
        let huge = doodle(.heartSmall, width: 0.3).resized(width: 3, canvas: .sticker)
        var design = MirrorDesign.blankSticker(id: "huge", name: "huge")
        design.stickers = [huge]

        let image = try #require(StickerRenderer.render(design, size: CGSize(width: 120, height: 120)))
        let data = pixels(image)
        var opaque = 0
        for index in stride(from: 3, to: data.count, by: 4) where data[index] > 30 { opaque += 1 }
        // 자동으로 축소했다면 가운데 작은 하트만 남아 비율이 작을 것이다.
        #expect(opaque > 120 * 120 / 2, "\(opaque)px만 칠해졌다 — 렌더러가 스티커를 줄인 것 같다")

        // 캔버스 밖으로는 나가지 않는다(경계에서 잘린다).
        #expect(image.width == 120 && image.height == 120)
    }

    @Test("큰 스티커가 Editor · 실제 거울 · Capture에서 같은 자리다")
    func oversizedGeometryMatchesEverywhere() throws {
        var design = MirrorDesign.blank
        design.stickers = [doodle(.ring, width: 0.2, canvas: .mirror).resized(width: 2.5)]

        let size = CGSize(width: 200, height: 433)
        // Editor(맞춤 배율) 와 실제 거울(aspectFill)이 같은 transform 규칙을 쓴다.
        let editor = try #require(render(
            MirrorCanvasView(design: design, transform: .fitted(in: size), mirrorAreaFill: nil), size: size
        ))
        let runtime = try #require(render(MirrorDecorationView(design: design), size: size))

        // 둘 다 캔버스를 크게 덮는다 — 한쪽만 줄어들면 실패다.
        func coverage(_ image: CGImage) -> Double {
            let data = pixels(image)
            var opaque = 0
            for index in stride(from: 3, to: data.count, by: 4) where data[index] > 30 { opaque += 1 }
            return Double(opaque) / Double(image.width * image.height)
        }
        #expect(coverage(editor) > 0.15)
        #expect(abs(coverage(editor) - coverage(runtime)) < 0.25)

        // Capture도 같은 렌더 경로를 지난다.
        #expect(MirrorCapture.compose(frame: nil, design: design, size: size) != nil)
    }

    @Test("텍스트 크기 정책은 건드리지 않았다")
    func textResizePolicyUnchanged() {
        // 텍스트는 별도 정책이다(fontSize 범위 유지). 스티커 수정 때문에 바꾸지 않았다.
        #expect(TextPolicy.fontSizeRange.lowerBound > 0)
        #expect(TextPolicy.fontSizeRange.upperBound > TextPolicy.fontSizeRange.lowerBound)
        #expect(TextPolicy.resizeSensitivity == 0.45)
    }
}
