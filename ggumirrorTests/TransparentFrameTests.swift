//
//  TransparentFrameTests.swift
//  ggumirrorTests
//
//  C-2A — 투명 프레임 + 편집 guide 노출 규칙.
//
//  여기서 고정하는 것:
//  1. 투명은 색이 아니라 `MirrorStyle.isFrameVisible`이다. 색은 그대로 남는다
//  2. 투명 관련 field가 없는 **예전 저장 파일은 프레임이 보이는 상태**로 읽힌다
//  3. 프레임을 없애도 장식과 좌표는 하나도 움직이지 않는다
//  4. 편집 guide(점선)는 **Editor에서만** 그려진다 — Mirror / Capture / Quick Mirror는 절대
//

import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import ggumirror

@MainActor
struct TransparentFrameTests {

    // MARK: - 도구

    nonisolated private static let size = CGSize(width: 270, height: 585)

    private func mirror(_ style: MirrorStyle) -> MyMirror {
        MyMirror(id: "m-1", name: "테스트 거울", origin: .made, style: style)
    }

    private var solid: MirrorStyle { BasicMirror.softPink.style }

    private var transparent: MirrorStyle {
        var style = solid
        style.isFrameVisible = false
        return style
    }

    private func sticker(at point: NormalizedPoint, width: Double = 0.3) -> StickerObject {
        let source = StickerSource.builtIn(.heart)
        let height = StickerObject.height(for: width, aspectRatio: source.aspectRatio)
        return StickerObject(
            source: source,
            frame: NormalizedRect(
                x: point.x - width / 2, y: point.y - height / 2, width: width, height: height
            )
        )
    }

    @MainActor private struct Bitmap {
        let data: [UInt8]
        let width: Int
        let height: Int

        func alpha(_ x: Int, _ y: Int) -> Int { Int(data[(y * width + x) * 4 + 3]) }

        /// 프레임 밴드(위쪽 띠) 안에서 실제로 칠해진 픽셀 수.
        func opaqueInTopBand(_ insets: MirrorFrameInsets) -> Int {
            let band = Int(insets.top * Double(height))
            var count = 0
            for y in 0..<max(band - 2, 1) {
                for x in 0..<width where alpha(x, y) > 8 { count += 1 }
            }
            return count
        }

        /// 카메라 구멍 위쪽 경계선을 따라 alpha가 켜졌다 꺼지는 횟수.
        /// 점선이면 여러 번 토글된다. 단색 경계면 한 덩이(1)다.
        func boundaryToggles(_ insets: MirrorFrameInsets) -> Int {
            let y = max(Int(insets.top * Double(height)) - 1, 0)
            var toggles = 0
            var previous = false
            for x in Int(insets.left * Double(width))..<(width - Int(insets.left * Double(width))) {
                let on = alpha(x, y) > 8
                if on != previous { toggles += 1 }
                previous = on
            }
            return toggles
        }
    }

    private func render(_ view: some View, size: CGSize = Self.size) -> Bitmap? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return nil }
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &data, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Bitmap(data: data, width: image.width, height: image.height)
    }

    private func withStore(_ body: (MirrorStore) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-frame-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = MirrorStore(root: root)
        defer {
            store.flush()
            try? FileManager().removeItem(at: root)
        }
        try body(store)
    }

    private func library(_ store: MirrorStore) -> MirrorLibrary {
        MirrorLibrary(store: store, assets: PhotoStickerAssetStore(), artworks: ImportedArtworkAssetStore())
    }

    private func repoFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    // MARK: - 모델

    @Test("투명은 색이 아니다 — 색은 그대로 남는다")
    func transparentKeepsTheChosenColor() {
        var style = BasicMirror.softPink.style
        style.isFrameVisible = false

        #expect(style.frameFill == nil)
        // 색을 지우지 않았다. 다시 켜면 고르던 색이 그대로 돌아온다.
        #expect(style.frame == BasicMirror.softPink.style.frame)
        style.isFrameVisible = true
        #expect(style.frameFill == BasicMirror.softPink.style.frame)
    }

    @Test("예전 저장 파일에는 투명 field가 없다 — 프레임이 보이는 상태로 읽는다")
    func legacyFileKeepsVisibleFrame() throws {
        // C-2A 이전 형식 그대로. frameVisible key가 아예 없다.
        let legacy = """
        {"frame":{"red":0.9,"green":0.8,"blue":0.7,"alpha":1},
         "insets":{"top":0.0769,"right":0.1,"bottom":0.094,"left":0.1},
         "doodles":[]}
        """
        let style = try JSONDecoder().decode(MirrorStyle.self, from: Data(legacy.utf8))

        #expect(style.isFrameVisible, "업데이트 후 기존 거울이 무프레임이 되면 안 된다")
        #expect(style.frameFill != nil)
    }

    @Test("투명 상태가 저장되고 그대로 돌아온다")
    func transparentRoundTrips() throws {
        let data = try JSONEncoder().encode(transparent)
        let decoded = try JSONDecoder().decode(MirrorStyle.self, from: data)

        #expect(!decoded.isFrameVisible)
        #expect(decoded.frameFill == nil)
        // 색과 두께도 같이 살아 있다. Color는 wrapper 차이가 있어 저장 표현으로 비교한다.
        #expect(RGBAColor(decoded.frame) == RGBAColor(solid.frame))
        #expect(decoded.insets == solid.insets)
    }

    @Test("기본 8색 round-trip은 그대로다")
    func basicColorsStillRoundTrip() throws {
        for basic in BasicMirror.allCases {
            let decoded = try JSONDecoder().decode(
                MirrorStyle.self, from: try JSONEncoder().encode(basic.style)
            )
            #expect(RGBAColor(decoded.frame) == RGBAColor(basic.style.frame))
            #expect(decoded.isFrameVisible)
        }
    }

    @Test("거울 한 장이 투명 상태로 저장됐다 읽혀도 장식이 그대로다")
    func transparentMirrorKeepsDecorations() throws {
        try withStore { store in
            let mine = library(store)
            var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
            design.style = transparent
            design.stickers = [sticker(at: NormalizedPoint(x: 0.5, y: 0.5))]
            design.texts = [TextObject(text: "안녕", center: NormalizedPoint(x: 0.5, y: 0.2))]
            design.strokes = [DrawingStroke(
                points: [NormalizedPoint(x: 0.2, y: 0.8), NormalizedPoint(x: 0.8, y: 0.8)],
                width: 0.02
            )]
            mine.save(design, name: "투명 거울", context: .createNew)

            store.flush()
            let reopened = MirrorLibrary(
                store: MirrorStore(root: store.root),
                assets: PhotoStickerAssetStore(),
                artworks: ImportedArtworkAssetStore()
            )
            let saved = try #require(reopened.mirrors.first)
            #expect(!saved.style.isFrameVisible)
            #expect(saved.stickers.count == 1)
            #expect(saved.texts.first?.text == "안녕")
            #expect(saved.strokes.count == 1)
        }
    }

    @Test("프레임을 껐다 켜도 좌표와 두께가 하나도 움직이지 않는다")
    func togglingFrameDoesNotMoveAnything() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.stickers = [sticker(at: NormalizedPoint(x: 0.4, y: 0.6))]
        design.texts = [TextObject(text: "글", center: NormalizedPoint(x: 0.5, y: 0.3))]
        let before = design

        design.style.isFrameVisible = false
        #expect(design.stickers == before.stickers)
        #expect(design.texts == before.texts)
        #expect(design.insets == before.insets)
        #expect(design.insets == MirrorFrameInsets.standard)

        design.style.isFrameVisible = true
        #expect(design.style == before.style, "다시 켜면 원래 style로 정확히 돌아온다")
        #expect(design.style.frameFill != nil)
    }

    // MARK: - 렌더

    @Test("색 프레임은 밴드가 실제로 칠해진다")
    func solidFrameFillsTheBand() throws {
        let bitmap = try #require(render(MirrorDecorationView(design: MirrorDesign(mirror: mirror(solid)))))
        #expect(bitmap.opaqueInTopBand(solid.insets) > 0)
        // 카메라 영역은 언제나 비어 있다.
        #expect(bitmap.alpha(bitmap.width / 2, bitmap.height / 2) == 0)
    }

    @Test("투명 프레임은 밴드에 아무것도 남기지 않는다 — 종이 결도 없다")
    func transparentFrameLeavesNothing() throws {
        let bitmap = try #require(render(
            MirrorDecorationView(design: MirrorDesign(mirror: mirror(transparent)))
        ))
        // 색만 빼고 종이 결(점)을 남기면 카메라 위에 점이 흩뿌려진 것처럼 보인다.
        #expect(bitmap.opaqueInTopBand(transparent.insets) == 0)
    }

    @Test("투명 프레임에서도 스티커는 그대로 그려진다")
    func transparentKeepsStickers() throws {
        var design = MirrorDesign(mirror: mirror(transparent))
        design.stickers = [sticker(at: NormalizedPoint(x: 0.5, y: 0.5))]

        let bitmap = try #require(render(MirrorDecorationView(design: design)))
        var drawn = 0
        for y in (bitmap.height / 3)..<(bitmap.height * 2 / 3) {
            for x in (bitmap.width / 4)..<(bitmap.width * 3 / 4) where bitmap.alpha(x, y) > 8 {
                drawn += 1
            }
        }
        #expect(drawn > 0, "프레임 없음이 장식 없음을 뜻하면 안 된다")
    }

    @Test("투명 프레임에서도 그림과 텍스트가 그대로 그려진다")
    func transparentKeepsInkAndText() throws {
        var design = MirrorDesign(mirror: mirror(transparent))
        design.strokes = [DrawingStroke(
            points: [NormalizedPoint(x: 0.15, y: 0.5), NormalizedPoint(x: 0.85, y: 0.5)],
            width: 0.03
        )]
        design.texts = [TextObject(text: "꾸미러", center: NormalizedPoint(x: 0.5, y: 0.75))]

        let inked = try #require(render(MirrorDecorationView(design: design)))
        let empty = try #require(render(
            MirrorDecorationView(design: MirrorDesign(mirror: mirror(transparent)))
        ))
        #expect(inked.data != empty.data)
    }

    // MARK: - guide는 Editor에서만

    @Test("실제 Mirror 렌더에는 편집 점선이 없다")
    func mirrorRenderHasNoGuide() throws {
        for style in [solid, transparent] {
            let bitmap = try #require(render(MirrorDecorationView(design: MirrorDesign(mirror: mirror(style)))))
            // 점선이면 경계 scanline에서 여러 번 토글된다.
            #expect(bitmap.boundaryToggles(style.insets) <= 1)
        }
    }

    @Test("촬영 합성에도 편집 점선이 없다")
    func captureHasNoGuide() throws {
        // 촬영은 화면 스냅샷이 아니라 MirrorDecorationView를 다시 그린다.
        // 그 경로에 guide를 켤 수 있는 인자 자체가 없다.
        let capture = codeOnly(try repoFile("ggumirror/Mirror/MirrorCapture.swift"))
        #expect(capture.contains("MirrorDecorationView(design: design)"))
        #expect(!capture.contains("showsCameraGuide"))

        let decoration = codeOnly(try repoFile("ggumirror/Shared/MirrorDecorationView.swift"))
        #expect(!decoration.contains("showsCameraGuide"))
    }

    @Test("Editor에서는 점선이 실제로 그려진다")
    func editorShowsGuide() throws {
        let design = MirrorDesign(mirror: mirror(solid))
        let withGuide = try #require(render(MirrorCanvasView(design: design, showsCameraGuide: true)))
        let without = try #require(render(MirrorCanvasView(design: design, showsCameraGuide: false)))

        #expect(withGuide.data != without.data, "Editor guide가 아무것도 그리지 않는다")
    }

    @Test("guide는 기본이 꺼짐이고, 켜는 곳은 Editor canvas 한 곳뿐이다")
    func guideIsOptInAndEditorOnly() throws {
        let canvas = codeOnly(try repoFile("ggumirror/Editor/MirrorCanvasView.swift"))
        // 기본값이 실수로 production 화면에서 guide를 보여주는 방향이면 안 된다.
        #expect(canvas.contains("var showsCameraGuide = false"))

        // 켜는 곳을 전부 센다.
        let sources = [
            "ggumirror/Editor/MirrorEditorCanvas.swift",
            "ggumirror/Editor/EditorView.swift",
            "ggumirror/Shared/MirrorDecorationView.swift",
            "ggumirror/Shared/MirrorPreview.swift",
            "ggumirror/Mirror/MirrorView.swift",
            "ggumirror/Mirror/MirrorCapture.swift",
            "ggumirror/Mirror/QuickMirrorComposer.swift",
            "ggumirror/Mirror/QuickMirrorFrameView.swift",
            "ggumirror/Store/StoreView.swift",
            "ggumirror/Store/TemplateDetailView.swift",
            "ggumirror/Home/HomeView.swift",
            "ggumirror/MyMirrors/MyMirrorsView.swift",
        ]
        var enablers: [String] = []
        for path in sources where codeOnly(try repoFile(path)).contains("showsCameraGuide: true") {
            enablers.append(path)
        }
        #expect(enablers == ["ggumirror/Editor/MirrorEditorCanvas.swift"], "guide를 켜는 곳: \(enablers)")
    }

    private func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - Quick Mirror

    @Test("투명 프레임은 이미 있는 none preset을 쓴다")
    func transparentMapsToNone() {
        #expect(QuickMirrorSync.preset(for: mirror(transparent)) == .none)

        // 장식이 있어도 마찬가지다 — 사용자가 "프레임 없음"을 고른 것이다.
        var decorated = mirror(transparent)
        decorated.stickers = [sticker(at: NormalizedPoint(x: 0.5, y: 0.5))]
        #expect(QuickMirrorSync.preset(for: decorated) == .none)
    }

    @Test("색 프레임 매핑은 그대로다")
    func solidMappingUnchanged() {
        for basic in BasicMirror.allCases {
            #expect(QuickMirrorSync.preset(for: mirror(basic.style)) == basic.quickMirrorPreset)
        }
        // transparent라는 새 preset을 만들지 않았다.
        #expect(QuickMirrorPresetID.allCases.count == 9)
        #expect(QuickMirrorPresetID(rawValue: "transparent") == nil)
    }

    @Test("none preset은 잠금화면에 프레임을 그리지 않는다")
    func noneDrawsNoOverlay() throws {
        #expect(QuickMirrorPresetID.none.frameColor == nil)
        #expect(!QuickMirrorPresetID.none.drawsFrame)

        // 빈 화면과 완전히 같아야 한다 — overlay가 하나도 없다는 뜻이다.
        let none = try #require(render(QuickMirrorFrameView(preset: .none)))
        let blank = try #require(render(Color.clear))
        #expect(none.data == blank.data)

        // 색 preset은 당연히 그린다 — 위 비교가 무의미한 비교가 아니라는 확인.
        let cream = try #require(render(QuickMirrorFrameView(preset: .cream)))
        #expect(cream.data != blank.data)
    }

    @Test("투명이어도 context는 여전히 아주 작다")
    func contextStaysTiny() throws {
        let data = try JSONEncoder().encode(QuickMirrorContext(presetID: .none))
        #expect(data.count < 4096)
    }
}
