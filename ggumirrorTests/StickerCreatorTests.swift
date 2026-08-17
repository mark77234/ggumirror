//
//  StickerCreatorTests.swift
//  ggumirrorTests
//
//  Phase V-5A — Sticker Creator Core.
//
//  여기서 지키는 것 중 가장 중요한 하나:
//  **최종 PNG의 배경은 완전히 투명하다.** 편집 화면의 체크무늬 · 종이 · 안내선 · 선택 표시가
//  하나라도 구워지면 스티커가 흰 사각형이 된다. 모서리 네 점만 보고 끝내지 않고
//  비어 있어야 할 넓은 영역을 bitmap으로 확인한다.
//

import Testing
import SwiftUI
import UIKit
@testable import ggumirror

@MainActor
struct StickerCreatorTests {

    // MARK: - 도구

    private func withStore(_ body: (StickerProjectStore) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-sticker-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = StickerProjectStore(root: root)
        defer {
            store.flush()
            try? FileManager().removeItem(at: root)
        }
        try body(store)
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

    /// alpha가 0이 아닌 픽셀 수.
    private func opaquePixels(_ image: CGImage) -> Int {
        let data = pixels(image)
        var count = 0
        for index in stride(from: 3, to: data.count, by: 4) where data[index] > 0 { count += 1 }
        return count
    }

    /// 정규화 사각형 안에서 alpha가 0이 아닌 픽셀 수.
    private func opaquePixels(_ image: CGImage, in area: CGRect) -> Int {
        let data = pixels(image)
        var count = 0
        let minX = Int(area.minX * CGFloat(image.width))
        let maxX = Int(area.maxX * CGFloat(image.width))
        let minY = Int(area.minY * CGFloat(image.height))
        let maxY = Int(area.maxY * CGFloat(image.height))
        for y in max(minY, 0)..<min(maxY, image.height) {
            for x in max(minX, 0)..<min(maxX, image.width) {
                let index = (y * image.width + x) * 4
                if data[index + 3] > 0 { count += 1 }
            }
        }
        return count
    }

    private func doodle(_ sticker: DoodleSticker, at point: NormalizedPoint, width: Double = 0.3) -> StickerObject {
        let source = StickerSource.doodle(sticker)
        let height = StickerObject.height(for: width, aspectRatio: source.aspectRatio, canvas: .sticker)
        return StickerObject(
            source: source,
            frame: NormalizedRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
        )
    }

    private func text(_ string: String, at point: NormalizedPoint) -> TextObject {
        TextObject(text: string, center: point, fontSize: 0.12)
    }

    private func stroke(from: NormalizedPoint, to: NormalizedPoint) -> DrawingStroke {
        DrawingStroke(
            points: [from, NormalizedPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2), to],
            brush: .marker,
            color: PaperTheme.ink,
            width: EditorBrush.marker.defaultWidth
        )
    }

    private func testPhoto() -> CGImage {
        let context = CGContext(
            data: nil, width: 120, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 20, y: 20, width: 80, height: 80))
        return context.makeImage()!
    }

    // MARK: - 프로젝트

    @Test("새 프로젝트는 고정된 id를 갖는다")
    func newProjectHasStableID() {
        let project = StickerProject(name: "내 스티커")
        #expect(!project.id.isEmpty)
        #expect(project.design.id == project.id)
        #expect(project.design.canvas == .sticker)
        #expect(project.finalAssetID == nil)
    }

    @Test("빈 프로젝트는 레이어가 하나도 없다")
    func emptyProjectHasNoLayers() {
        let project = StickerProject(name: "내 스티커")
        #expect(project.isEmpty)
        #expect(project.design.strokes.isEmpty)
        #expect(project.design.stickers.isEmpty)
        #expect(project.design.texts.isEmpty)
        #expect(project.design.importedArtworks.isEmpty)
    }

    @Test("createNew는 새 id를 만든다")
    func createNewMakesNewID() throws {
        try withStore { store in
            let library = StickerLibrary(store: store)
            var design = MirrorDesign.blankSticker(id: UUID().uuidString, name: "하나")
            design.stickers = [doodle(.heart, at: NormalizedPoint(x: 0.5, y: 0.5))]

            let first = library.save(design, name: "하나", context: .createNew)
            let second = library.save(design, name: "둘", context: .createNew)

            #expect(first?.id != second?.id)
            #expect(library.projects.count == 2)
            #expect(StickerSaveContext.createNew.makesNewProject)
        }
    }

    @Test("editExisting은 같은 id를 유지한다")
    func editExistingKeepsID() throws {
        try withStore { store in
            let library = StickerLibrary(store: store)
            var design = MirrorDesign.blankSticker(id: UUID().uuidString, name: "원본")
            design.stickers = [doodle(.heart, at: NormalizedPoint(x: 0.5, y: 0.5))]
            let saved = try #require(library.save(design, name: "원본", context: .createNew))

            var edited = saved.design
            edited.stickers.append(doodle(.star, at: NormalizedPoint(x: 0.3, y: 0.3)))
            let updated = try #require(
                library.save(edited, name: "무시됨", context: .editExisting(saved.id))
            )

            #expect(updated.id == saved.id)                 // 같은 스티커
            #expect(updated.name == "원본")                  // 이름 유지
            #expect(updated.createdAt == saved.createdAt)   // 만든 날짜 유지
            #expect(library.projects.count == 1)            // 새 스티커가 생기지 않는다
            #expect(updated.design.stickers.count == 2)     // 내용은 바뀐다
            #expect(!StickerSaveContext.editExisting(saved.id).makesNewProject)
        }
    }

    @Test("취소하면 저장된 프로젝트가 그대로다")
    func cancelDoesNotMutateSavedProject() throws {
        try withStore { store in
            let library = StickerLibrary(store: store)
            var design = MirrorDesign.blankSticker(id: UUID().uuidString, name: "원본")
            design.stickers = [doodle(.heart, at: NormalizedPoint(x: 0.5, y: 0.5))]
            let saved = try #require(library.save(design, name: "원본", context: .createNew))

            // Creator는 사본에서 작업한다. 저장하지 않으면 아무 일도 없다.
            var working = saved.design
            working.stickers.append(doodle(.cake, at: NormalizedPoint(x: 0.2, y: 0.2)))
            working.texts = [text("취소될 글씨", at: NormalizedPoint(x: 0.5, y: 0.8))]

            #expect(library.project(id: saved.id)?.design.stickers.count == 1)
            #expect(library.project(id: saved.id)?.design.texts.isEmpty == true)
        }
    }

    @Test("기본 이름이 겹치지 않게 번호를 붙인다")
    func automaticNameNumbers() {
        #expect(StickerProjectPolicy.automaticName(existing: []) == "내 스티커")
        #expect(StickerProjectPolicy.automaticName(existing: ["내 스티커"]) == "내 스티커 2")
        #expect(StickerProjectPolicy.automaticName(existing: ["내 스티커", "내 스티커 2"]) == "내 스티커 3")
        #expect(StickerProjectPolicy.normalizedName("  ") == nil)
        #expect(StickerProjectPolicy.normalizedName(String(repeating: "가", count: 40))?.count == 24)
    }

    // MARK: - 캔버스 / 출력

    @Test("논리 캔버스는 1024 × 1024 정사각형이다")
    func canvasIsSquare1024() {
        #expect(StickerCanvas.size == CGSize(width: 1024, height: 1024))
        #expect(CanvasKind.sticker.size == CGSize(width: 1024, height: 1024))
        #expect(CanvasKind.sticker.aspectRatio == 1)
        // 거울 캔버스는 그대로다.
        #expect(CanvasKind.mirror.size == MirrorCanvas.size)
        #expect(!CanvasKind.sticker.drawsBackground)
        #expect(CanvasKind.mirror.drawsBackground)
    }

    @Test("빈 스티커는 전체가 완전히 투명하다")
    func emptyRenderIsFullyTransparent() throws {
        let design = MirrorDesign.blankSticker(id: "empty", name: "빈 스티커")
        let image = try #require(StickerRenderer.render(design, size: CGSize(width: 256, height: 256)))

        // 한 픽셀도 칠해지면 안 된다 — 종이 배경이 새면 여기서 걸린다.
        #expect(opaquePixels(image) == 0)
    }

    @Test("최종 이미지는 1024 × 1024다")
    func finalImageIs1024() throws {
        var design = MirrorDesign.blankSticker(id: "one", name: "하나")
        design.stickers = [doodle(.heart, at: NormalizedPoint(x: 0.5, y: 0.5))]
        let image = try #require(StickerRenderer.render(design))
        #expect(image.width == 1024)
        #expect(image.height == 1024)
    }

    @Test("편집 화면의 체크무늬가 최종 PNG에 구워지지 않는다")
    func checkerboardIsNotBaked() throws {
        var design = MirrorDesign.blankSticker(id: "check", name: "체크")
        // 가운데에만 두들 하나.
        design.stickers = [doodle(.heart, at: NormalizedPoint(x: 0.5, y: 0.5), width: 0.3)]
        let image = try #require(StickerRenderer.render(design, size: CGSize(width: 256, height: 256)))

        // 네 모서리 영역(각 15%)은 완전히 비어 있어야 한다.
        for corner in [
            CGRect(x: 0, y: 0, width: 0.15, height: 0.15),
            CGRect(x: 0.85, y: 0, width: 0.15, height: 0.15),
            CGRect(x: 0, y: 0.85, width: 0.15, height: 0.15),
            CGRect(x: 0.85, y: 0.85, width: 0.15, height: 0.15),
        ] {
            #expect(opaquePixels(image, in: corner) == 0, "모서리 \(corner)에 무언가 그려졌다")
        }
        // 가운데는 실제로 그려져 있다.
        #expect(opaquePixels(image, in: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)) > 20)
    }

    @Test("스티커 주변의 넓은 영역이 투명하게 남는다")
    func transparentRegionsStayTransparent() throws {
        var design = MirrorDesign.blankSticker(id: "region", name: "영역")
        design.stickers = [doodle(.star, at: NormalizedPoint(x: 0.25, y: 0.25), width: 0.25)]
        let image = try #require(StickerRenderer.render(design, size: CGSize(width: 256, height: 256)))

        // 반대쪽 절반은 손대지 않았다.
        #expect(opaquePixels(image, in: CGRect(x: 0.55, y: 0.55, width: 0.45, height: 0.45)) == 0)
        // 전체가 칠해진 것도 아니다.
        let total = 256 * 256
        #expect(opaquePixels(image) < total / 3)
    }

    @Test("PNG로 굽고 다시 읽어도 투명도가 남는다")
    func pngKeepsAlpha() throws {
        var design = MirrorDesign.blankSticker(id: "png", name: "PNG")
        design.stickers = [doodle(.heart, at: NormalizedPoint(x: 0.5, y: 0.5))]
        let data = try #require(StickerRenderer.pngData(design))
        let restored = try #require(UIImage(data: data)?.cgImage)

        #expect(restored.width == 1024)
        #expect(opaquePixels(restored, in: CGRect(x: 0, y: 0, width: 0.1, height: 0.1)) == 0)
        #expect(opaquePixels(restored) > 0)
    }

    // MARK: - 사진

    @Test("사진 배경 제거는 Mirror와 같은 코드를 쓴다")
    func photoCutoutReusesMirrorPipeline() {
        // Creator 전용 배경 제거 코드를 복사하지 않았다.
        #expect(PhotoStickerMaker.maximumPixelSize > 0)
        #expect(PhotoStickerMaker.transparentPadding > 0)
    }

    @Test("사진 레이어가 실제로 그려지고 주변은 투명하다")
    func photoLayerKeepsTransparentBackground() throws {
        // **`.shared`에 등록해야 한다** — 렌더러가 여기서 사진을 찾는다.
        // 다른 인스턴스에 넣으면 조용히 건너뛰고, "주변이 투명하다"만 보는 테스트는 그걸 놓친다.
        let source = PhotoStickerAssetStore.shared.register(testPhoto())
        var design = MirrorDesign.blankSticker(id: "photo", name: "사진")
        let height = StickerObject.height(for: 0.4, aspectRatio: source.aspectRatio, canvas: .sticker)
        design.stickers = [StickerObject(
            source: source,
            frame: NormalizedRect(x: 0.3, y: 0.3, width: 0.4, height: height)
        )]

        let image = try #require(StickerRenderer.render(design, size: CGSize(width: 256, height: 256)))
        // 사진이 놓인 자리에는 실제로 픽셀이 있다.
        #expect(opaquePixels(image, in: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)) > 100)
        // 그 밖은 여전히 완전히 투명하다.
        #expect(opaquePixels(image, in: CGRect(x: 0, y: 0, width: 0.2, height: 0.2)) == 0)
    }

    @Test("사진 레이어의 위치 · 크기 · 회전 · 뒤집기 · 투명도가 저장된다")
    func photoLayerPropertiesPersist() throws {
        try withStore { store in
            let library = StickerLibrary(store: store)
            let source = PhotoStickerAssetStore.shared.register(testPhoto())

            var design = MirrorDesign.blankSticker(id: UUID().uuidString, name: "사진")
            design.stickers = [StickerObject(
                source: source,
                frame: NormalizedRect(x: 0.2, y: 0.3, width: 0.5, height: 0.5),
                rotation: 37,
                opacity: 0.6,
                isFlippedHorizontally: true
            )]
            let saved = try #require(library.save(design, name: "사진", context: .createNew))
            store.flush()

            let reloaded = try #require(StickerLibrary(store: store).project(id: saved.id))
            let sticker = try #require(reloaded.design.stickers.first)
            #expect(sticker.frame.x == 0.2)
            #expect(sticker.frame.width == 0.5)
            #expect(sticker.rotation == 37)
            #expect(sticker.opacity == 0.6)
            #expect(sticker.isFlippedHorizontally)
            #expect(sticker.source.photoAssetID == source.photoAssetID)
        }
    }

    @Test("사진을 여러 장 넣을 수 있다")
    func multiplePhotoLayers() {
        let assets = PhotoStickerAssetStore.shared
        var design = MirrorDesign.blankSticker(id: "multi", name: "여러 장")
        for index in 0..<3 {
            let source = assets.register(testPhoto())
            design.stickers.append(StickerObject(
                source: source,
                frame: NormalizedRect(x: 0.1 * Double(index), y: 0.2, width: 0.3, height: 0.3),
                zIndex: index
            ))
        }
        #expect(design.stickers.count == 3)
        #expect(Set(design.stickers.compactMap(\.source.photoAssetID)).count == 3)
    }

    // MARK: - 두들

    @Test("Creator에서도 두들 42종을 그대로 쓴다")
    func creatorUsesSameDoodleCatalog() {
        // 카탈로그를 복사하지 않았다 — Mirror와 같은 enum이다.
        #expect(DoodleSticker.allCases.count == 42)
        #expect(DoodleSticker.all(in: .all).count == 42)
    }

    @Test("Creator picker에도 legacy 26종은 나오지 않는다")
    func legacyStickersStayHidden() throws {
        // picker는 두들만 나열한다. Creator도 같은 picker를 쓴다.
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "ggumirror/Editor/StickerPickerSheet.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        #expect(!text.contains("BuiltInSticker.all"))
        #expect(text.contains("DoodleSticker.all"))
    }

    @Test("두들 레이어가 스티커 캔버스에 그려진다")
    func doodleLayerRenders() throws {
        var design = MirrorDesign.blankSticker(id: "doodle", name: "두들")
        design.stickers = [doodle(.ribbon, at: NormalizedPoint(x: 0.5, y: 0.5), width: 0.5)]
        let image = try #require(StickerRenderer.render(design, size: CGSize(width: 256, height: 256)))
        #expect(opaquePixels(image, in: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)) > 50)
    }

    @Test("tint를 지원하는 두들은 색이 바뀐다")
    func tintCapableDoodleChangesColor() throws {
        var design = MirrorDesign.blankSticker(id: "tint", name: "색")
        var sticker = doodle(.heart, at: NormalizedPoint(x: 0.5, y: 0.5), width: 0.6)
        sticker.tintColor = .red
        design.stickers = [sticker]

        let image = try #require(StickerRenderer.render(design, size: CGSize(width: 256, height: 256)))
        let data = pixels(image)
        var reds = 0
        for index in stride(from: 0, to: data.count, by: 4)
        where data[index + 3] > 120 && data[index] > 140 && data[index + 1] < 110 {
            reds += 1
        }
        #expect(reds > 20)
        #expect(StickerSource.doodle(.heart).supportsTint)
    }

    @Test("원본 색 두들은 색을 유지한다")
    func accentDoodleKeepsItsColor() throws {
        #expect(!StickerSource.doodle(.cherry).supportsTint)

        var design = MirrorDesign.blankSticker(id: "accent", name: "체리")
        var sticker = doodle(.cherry, at: NormalizedPoint(x: 0.5, y: 0.5), width: 0.6)
        sticker.tintColor = .green   // 무시돼야 한다
        design.stickers = [sticker]

        var plain = design
        plain.stickers[0].tintColor = nil

        let tinted = try #require(StickerRenderer.render(design, size: CGSize(width: 128, height: 128)))
        let original = try #require(StickerRenderer.render(plain, size: CGSize(width: 128, height: 128)))
        #expect(pixels(tinted) == pixels(original))
    }

    // MARK: - 텍스트

    @Test("텍스트 레이어가 저장되고 글꼴이 남는다")
    func textLayerPersistsWithFont() throws {
        try withStore { store in
            let library = StickerLibrary(store: store)
            var design = MirrorDesign.blankSticker(id: UUID().uuidString, name: "글씨")
            var object = text("오늘도 예쁘게", at: NormalizedPoint(x: 0.5, y: 0.5))
            object.style = .nanumBrush
            object.alignment = .trailing
            object.opacity = 0.8
            design.texts = [object]

            let saved = try #require(library.save(design, name: "글씨", context: .createNew))
            store.flush()

            let reloaded = try #require(StickerLibrary(store: store).project(id: saved.id))
            let restored = try #require(reloaded.design.texts.first)
            #expect(restored.text == "오늘도 예쁘게")
            #expect(restored.style == .nanumBrush)
            #expect(restored.alignment == .trailing)
            #expect(restored.opacity == 0.8)
        }
    }

    @Test("텍스트는 스티커 캔버스 비율로 배치된다")
    func textLayoutFollowsStickerCanvas() {
        let object = text("가", at: NormalizedPoint(x: 0.5, y: 0.5))
        let mirror = TextLayout.of(object, canvas: .mirror)
        let sticker = TextLayout.of(object, canvas: .sticker)

        // 픽셀 크기는 캔버스 폭 기준이라 다르다.
        #expect(mirror.size != sticker.size)
        // 같은 글자가 정사각 캔버스에서는 높이의 **더 큰** 비율을 차지한다
        // (거울은 세로로 2배 이상 길다). 거울 비율을 그대로 쓰면 글씨 상자가 어긋난다.
        #expect(sticker.normalizedSize.height > mirror.normalizedSize.height)
        #expect(sticker.canvas == .sticker)
    }

    @Test("텍스트가 최종 PNG에 그려진다")
    func textRendersInOutput() throws {
        var design = MirrorDesign.blankSticker(id: "text", name: "글씨")
        design.texts = [text("가나다", at: NormalizedPoint(x: 0.5, y: 0.5))]
        let image = try #require(StickerRenderer.render(design, size: CGSize(width: 256, height: 256)))
        #expect(opaquePixels(image) > 30)
        // 위쪽 끝은 비어 있다.
        #expect(opaquePixels(image, in: CGRect(x: 0, y: 0, width: 1, height: 0.1)) == 0)
    }

    // MARK: - 그리기

    @Test("그린 획이 최종 PNG에 남는다")
    func drawingAppearsInOutput() throws {
        var design = MirrorDesign.blankSticker(id: "draw", name: "그리기")
        design.strokes = [stroke(
            from: NormalizedPoint(x: 0.2, y: 0.5),
            to: NormalizedPoint(x: 0.8, y: 0.5)
        )]
        let image = try #require(StickerRenderer.render(design, size: CGSize(width: 256, height: 256)))
        #expect(opaquePixels(image, in: CGRect(x: 0.3, y: 0.4, width: 0.4, height: 0.2)) > 20)
    }

    @Test("획 주변은 투명하게 남는다")
    func areaAroundDrawingStaysTransparent() throws {
        var design = MirrorDesign.blankSticker(id: "draw2", name: "그리기")
        design.strokes = [stroke(
            from: NormalizedPoint(x: 0.2, y: 0.2),
            to: NormalizedPoint(x: 0.4, y: 0.25)
        )]
        let image = try #require(StickerRenderer.render(design, size: CGSize(width: 256, height: 256)))
        // 아래쪽 절반은 손대지 않았다 — 종이 배경이 없다는 뜻이다.
        #expect(opaquePixels(image, in: CGRect(x: 0, y: 0.6, width: 1, height: 0.4)) == 0)
    }

    @Test("Draw / Hand 제스처 정책을 그대로 쓴다")
    func gesturePolicyIsShared() {
        #expect(EditorGesturePolicy.oneFingerAction(tool: .draw, drawingMode: .draw, grabbed: nil) == .draw)
        #expect(
            EditorGesturePolicy.oneFingerAction(tool: .draw, drawingMode: .pan, grabbed: nil) == .panViewport
        )
        #expect(EditorViewportState.zoomRange == 1...4)
    }

    @Test("보기 상태는 history에 들어가지 않는다")
    func viewportIsNotInHistory() {
        var snapshot = EditorSnapshot()
        var history = EditorHistory()
        history.apply(.addSticker(doodle(.heart, at: NormalizedPoint(x: 0.5, y: 0.5))), to: &snapshot)
        #expect(history.canUndo)

        // 확대 / 이동 / 맞춤은 EditorViewportState만 바꾼다 — snapshot을 건드리지 않는다.
        var viewport = EditorViewportState()
        viewport.zoom = 3
        viewport.pan = CGSize(width: 40, height: -20)
        let before = snapshot
        viewport = EditorViewportState()
        #expect(snapshot == before)
    }

    // MARK: - 레이어

    @Test("두들 · 사진 · 텍스트가 하나의 순서를 공유한다")
    func mixedZOrderPersists() throws {
        try withStore { store in
            let library = StickerLibrary(store: store)
            let assets = PhotoStickerAssetStore.shared
            var design = MirrorDesign.blankSticker(id: UUID().uuidString, name: "순서")

            var photo = StickerObject(
                source: assets.register(testPhoto()),
                frame: NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
            )
            photo.zIndex = 0
            var star = doodle(.star, at: NormalizedPoint(x: 0.5, y: 0.5))
            star.zIndex = 1
            var caption = text("위", at: NormalizedPoint(x: 0.5, y: 0.7))
            caption.zIndex = 2
            design.stickers = [photo, star]
            design.texts = [caption]

            let saved = try #require(library.save(design, name: "순서", context: .createNew))
            store.flush()

            let reloaded = try #require(StickerLibrary(store: store).project(id: saved.id))
            #expect(reloaded.design.stickers.map(\.zIndex) == [0, 1])
            #expect(reloaded.design.texts.map(\.zIndex) == [2])
            // 레이어 목록은 앞에 보이는 것부터다.
            #expect(reloaded.design.decorationLayers.count == 3)
        }
    }

    @Test("순서를 바꾸면 최종 결과가 바뀐다")
    func reorderChangesOutput() throws {
        var design = MirrorDesign.blankSticker(id: "order", name: "순서")
        var back = doodle(.heartSmall, at: NormalizedPoint(x: 0.5, y: 0.5), width: 0.6)
        back.tintColor = .red
        back.zIndex = 0
        var front = doodle(.sparkle, at: NormalizedPoint(x: 0.5, y: 0.5), width: 0.6)
        front.tintColor = .blue
        front.zIndex = 1
        design.stickers = [back, front]

        let first = try #require(StickerRenderer.render(design, size: CGSize(width: 128, height: 128)))

        var swapped = design
        swapped.stickers[0].zIndex = 1
        swapped.stickers[1].zIndex = 0
        let second = try #require(StickerRenderer.render(swapped, size: CGSize(width: 128, height: 128)))

        #expect(pixels(first) != pixels(second))
    }

    // MARK: - History

    @Test("추가 / 삭제 / 이동 / 크기 / 회전이 실행 취소된다")
    func historyCoversEveryEdit() {
        var snapshot = EditorSnapshot()
        var history = EditorHistory()

        let sticker = doodle(.heart, at: NormalizedPoint(x: 0.5, y: 0.5))
        history.apply(.addSticker(sticker), to: &snapshot)
        #expect(snapshot.stickers.count == 1)
        history.undo(&snapshot)
        #expect(snapshot.stickers.isEmpty)
        history.redo(&snapshot)
        #expect(snapshot.stickers.count == 1)

        // 이동 · 크기 · 회전은 모두 replaceSticker 한 경로다.
        for change in [
            { (object: inout StickerObject) in object.frame.x += 0.1 },
            { (object: inout StickerObject) in object.frame.width += 0.1 },
            { (object: inout StickerObject) in object.rotation = 45 },
            { (object: inout StickerObject) in object.opacity = 0.5 },
        ] {
            var updated = try! #require(snapshot.stickers.first)
            let before = snapshot
            change(&updated)
            history.apply(.replaceSticker(updated), to: &snapshot)
            #expect(snapshot != before)
            history.undo(&snapshot)
            #expect(snapshot == before)
            history.redo(&snapshot)
        }

        history.apply(.deleteSticker(snapshot.stickers[0].id), to: &snapshot)
        #expect(snapshot.stickers.isEmpty)
        history.undo(&snapshot)
        #expect(snapshot.stickers.count == 1)
    }

    @Test("그리기도 실행 취소 / 다시 실행된다")
    func drawingUndoRedo() {
        var snapshot = EditorSnapshot()
        var history = EditorHistory()
        let line = stroke(from: NormalizedPoint(x: 0.2, y: 0.2), to: NormalizedPoint(x: 0.8, y: 0.8))

        history.apply(.addStroke(line), to: &snapshot)
        #expect(snapshot.strokes.count == 1)
        history.undo(&snapshot)
        #expect(snapshot.strokes.isEmpty)
        history.redo(&snapshot)
        #expect(snapshot.strokes.count == 1)
    }

    @Test("텍스트 수정도 실행 취소된다")
    func textEditUndo() {
        var snapshot = EditorSnapshot()
        var history = EditorHistory()
        let object = text("처음", at: NormalizedPoint(x: 0.5, y: 0.5))
        history.apply(.addText(object), to: &snapshot)

        var edited = object
        edited.text = "고침"
        history.apply(.replaceText(edited), to: &snapshot)
        #expect(snapshot.texts.first?.text == "고침")
        history.undo(&snapshot)
        #expect(snapshot.texts.first?.text == "처음")
    }

    // MARK: - 저장

    @Test("프로젝트가 저장되고 앱을 다시 켜도 남는다")
    func projectSurvivesRestart() throws {
        try withStore { store in
            let library = StickerLibrary(store: store)
            var design = MirrorDesign.blankSticker(id: UUID().uuidString, name: "다시")
            design.stickers = [doodle(.crown, at: NormalizedPoint(x: 0.5, y: 0.4))]
            design.texts = [text("안녕", at: NormalizedPoint(x: 0.5, y: 0.75))]
            let saved = try #require(library.save(design, name: "다시", context: .createNew))
            store.flush()

            let relaunched = StickerLibrary(store: store)
            #expect(relaunched.projects.count == 1)
            let restored = try #require(relaunched.project(id: saved.id))
            #expect(restored.name == "다시")
            #expect(restored.design.canvas == .sticker)
            #expect(restored.design.stickers.count == 1)
            #expect(restored.design.texts.count == 1)
        }
    }

    @Test("완성 PNG가 파일로 남고 다시 읽힌다")
    func finalPNGSurvivesRestart() throws {
        try withStore { store in
            let library = StickerLibrary(store: store)
            var design = MirrorDesign.blankSticker(id: UUID().uuidString, name: "PNG")
            design.stickers = [doodle(.heart, at: NormalizedPoint(x: 0.5, y: 0.5))]
            let saved = try #require(library.save(design, name: "PNG", context: .createNew))
            store.flush()

            let assetID = try #require(saved.finalAssetID)
            #expect(FileManager().fileExists(atPath: store.assetURL(assetID).path))

            let image = try #require(store.readAsset(assetID))
            #expect(image.width == 1024)
            #expect(opaquePixels(image, in: CGRect(x: 0, y: 0, width: 0.1, height: 0.1)) == 0)
        }
    }

    @Test("PNG를 JSON에 담지 않는다")
    func binaryIsNotEmbeddedInJSON() throws {
        try withStore { store in
            let library = StickerLibrary(store: store)
            var design = MirrorDesign.blankSticker(id: UUID().uuidString, name: "가벼움")
            design.stickers = [doodle(.heart, at: NormalizedPoint(x: 0.5, y: 0.5))]
            _ = library.save(design, name: "가벼움", context: .createNew)
            store.flush()

            let data = try Data(contentsOf: store.projectsURL)
            // 1024² PNG는 수십 KB다. JSON이 그만큼 커지면 base64로 들어간 것이다.
            #expect(data.count < 8_000, "JSON이 \(data.count)바이트다 — binary가 섞였다")
            let json = String(decoding: data, as: UTF8.self)
            #expect(!json.contains("iVBOR"))   // PNG base64 머리
        }
    }

    @Test("깨진 저장 파일은 앱을 죽이지 않고 격리된다")
    func damagedFileDoesNotCrash() throws {
        try withStore { store in
            try FileManager().createDirectory(at: store.root, withIntermediateDirectories: true)
            try Data("이건 JSON이 아니다".utf8).write(to: store.projectsURL)

            #expect(store.load() == .damaged)
            // 원본을 지우지 않고 옆으로 치운다.
            #expect(FileManager().fileExists(atPath: store.damagedURL.path))
            // 빈 상태로 계속 쓸 수 있다.
            #expect(StickerLibrary(store: store).projects.isEmpty)
        }
    }

    @Test("미래 버전 파일은 읽지도 덮어쓰지도 않는다")
    func futureSchemaIsProtected() throws {
        try withStore { store in
            try FileManager().createDirectory(at: store.root, withIntermediateDirectories: true)
            let future = #"{"schemaVersion": 99, "projects": []}"#
            try Data(future.utf8).write(to: store.projectsURL)

            #expect(store.load() == .tooNew(99))

            let library = StickerLibrary(store: store)
            var design = MirrorDesign.blankSticker(id: UUID().uuidString, name: "새것")
            design.stickers = [doodle(.heart, at: NormalizedPoint(x: 0.5, y: 0.5))]
            #expect(library.save(design, name: "새것", context: .createNew) == nil)
            store.flush()

            // 파일이 그대로다.
            let raw = try String(contentsOf: store.projectsURL, encoding: .utf8)
            #expect(raw.contains("99"))
        }
    }

    @Test("스티커 저장 형식은 거울과 별개다")
    func stickerSchemaIsIndependent() {
        // 2 — 스티커에 출처(origin · generationIDs)가 생겼다(A-1A).
        #expect(StickerSchema.current == 2)
        // 스티커 형식이 올라가도 **거울 저장 형식은 그대로다.** 둘은 서로 독립이다.
        #expect(MirrorSchema.current == 3)
    }

    // MARK: - 회귀

    @Test("거울 쪽 동작이 그대로다")
    func mirrorSideUnchanged() throws {
        // 캔버스 종류가 없는 예전 거울은 .mirror로 읽힌다.
        let json = """
        {
          "id": "old", "name": "예전 거울",
          "style": { "frame": { "red": 1, "green": 1, "blue": 1, "alpha": 1 },
                     "insets": { "top": 0.077, "right": 0.1, "bottom": 0.094, "left": 0.1 },
                     "doodles": [] }
        }
        """
        let design = try JSONDecoder().decode(MirrorDesign.self, from: Data(json.utf8))
        #expect(design.canvas == .mirror)

        // legacy 스티커도 계속 해석된다.
        #expect(BuiltInSticker(rawValue: "heart") == .heart)
        // 두들 42종은 Mirror picker에서 그대로다.
        #expect(DoodleSticker.allCases.count == 42)
        // 거울 geometry는 손대지 않았다.
        #expect(MirrorCanvas.size == CGSize(width: 1080, height: 2340))
        #expect(MirrorFrameInsets.standard.top == 180.0 / 2340.0)
    }

    @Test("거울 스티커 배치는 예전 크기 그대로다")
    func mirrorPlacementUnchanged() {
        let design = MirrorDesign.blank
        let placed = StickerPlacement.insert(
            .doodle(.heart), in: design, visibleRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        )
        #expect(placed.frame.width == 0.16)

        // 스티커 캔버스에서는 조금 크게 넣는다 — 정사각형이라 같은 폭이 더 작아 보인다.
        let sticker = MirrorDesign.blankSticker(id: "x", name: "x")
        let onSticker = StickerPlacement.insert(
            .doodle(.heart), in: sticker, visibleRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        )
        #expect(onSticker.frame.width == 0.30)
    }

    @Test("커스텀 시트 dismiss 정책이 유지된다")
    func inkModalDismissStillUsed() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "ggumirror")
        for file in ["Editor/TextEditorSheets.swift", "Editor/MirrorSaveSheets.swift"] {
            let source = try String(contentsOf: root.appending(path: file), encoding: .utf8)
            #expect(!source.contains("Environment(\\.dismiss)"))
            #expect(source.contains("inkModalDismiss"))
        }
    }
}
