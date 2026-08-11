//
//  ExternalArtworkTests.swift
//  ggumirrorTests
//
//  외부 그림 앱에서 만든 디자인을 가져오는 길 전체를 확인한다.
//  작업 가이드 → 외부 앱 → 투명 PNG → 검사 → 전체 캔버스 고정 레이어.
//
//  파일을 쓰는 테스트는 전부 자기 임시 폴더만 쓴다.
//

import Testing
import SwiftUI
import UIKit
import UniformTypeIdentifiers
@testable import ggumirror

@MainActor
struct ExternalArtworkTests {

    // MARK: - 도구

    private func withStore(_ body: (MirrorStore) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-artwork-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = MirrorStore(root: root)
        defer {
            store.flush()
            try? FileManager().removeItem(at: root)
        }
        try body(store)
    }

    private func relaunch(_ store: MirrorStore) -> MirrorLibrary {
        store.flush()
        return MirrorLibrary(
            store: MirrorStore(root: store.root),
            assets: PhotoStickerAssetStore(),
            artworks: ImportedArtworkAssetStore()
        )
    }

    /// 왼쪽 위 프레임에 빨간 표식이 있는 투명 디자인.
    /// 카메라 영역은 비워 두는 것이 기본이다 — 실제 거울에서 얼굴이 보여야 한다.
    private func artworkImage(
        width: Int = 1080,
        height: Int = 2340,
        cameraOpaque: Bool = false,
        markColor: CGColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    ) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        // 프레임 밴드 전체를 먼저 채운다 — 어디가 지워지는지 경계를 볼 수 있다.
        let area = MirrorFrameInsets.standard.mirrorArea
        context.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.5, alpha: 1))
        let band = CGMutablePath()
        band.addRect(CGRect(x: 0, y: 0, width: Double(width), height: Double(height)))
        band.addRect(CGRect(
            x: area.x * Double(width),
            y: Double(height) - (area.y + area.height) * Double(height),
            width: area.width * Double(width),
            height: area.height * Double(height)
        ))
        context.addPath(band)
        context.fillPath(using: .evenOdd)

        // CG 좌표는 아래가 0이라 위쪽 표식은 맨 위 행에 그린다. 밴드 위에 얹는다.
        let mark = Double(width) * 0.14
        context.setFillColor(markColor)
        context.fill(CGRect(x: 0, y: Double(height) - mark, width: mark, height: mark))

        if cameraOpaque {
            let area = MirrorFrameInsets.standard.mirrorArea
            context.setFillColor(CGColor(red: 0, green: 0.6, blue: 0.2, alpha: 1))
            context.fill(CGRect(
                x: area.x * Double(width),
                y: Double(height) - (area.y + area.height) * Double(height),
                width: area.width * Double(width),
                height: area.height * Double(height)
            ))
        }
        return context.makeImage()!
    }

    private func pngData(_ image: CGImage) -> Data {
        UIImage(cgImage: image).pngData()!
    }

    private func jpegData(_ image: CGImage, orientation: Int) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(
            destination, image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// 픽셀 한 점. 왼쪽 위가 (0, 0).
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.draw(
            image,
            in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height)
        )
        return (data[0], data[1], data[2], data[3])
    }

    private func pixel(_ image: CGImage, at point: NormalizedPoint) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        pixel(
            image,
            x: min(max(Int(point.x * Double(image.width)), 0), image.width - 1),
            y: min(max(Int(point.y * Double(image.height)), 0), image.height - 1)
        )
    }

    /// 실제 Mirror overlay(카메라 위)에서의 픽셀.
    private func runtimePixel(
        _ design: MirrorDesign,
        at point: NormalizedPoint,
        size: CGSize = CGSize(width: 300, height: 650)
    ) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        let view = MirrorDecorationView(design: design).frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return nil }
        let transform = MirrorViewTransform.aspectFilled(in: CGSize(width: image.width, height: image.height))
        let screen = transform.point(point)
        return pixel(image, x: min(max(Int(screen.x), 0), image.width - 1),
                     y: min(max(Int(screen.y), 0), image.height - 1))
    }

    /// Home / My Mirrors가 쓰는 미리보기에서의 픽셀.
    private func previewPixel(
        _ mirror: MyMirror,
        at point: NormalizedPoint,
        size: CGSize = CGSize(width: 200, height: 433)
    ) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        let view = MirrorPreview(mirror: mirror).frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return nil }
        return pixel(image, at: point)
    }

    private func mirror(with artwork: ImportedArtworkObject) -> MyMirror {
        var mirror = MyMirror(
            id: "made-artwork",
            name: "외부 디자인 거울",
            origin: .made,
            style: MirrorLibrary.defaultMirror.style
        )
        mirror.importedArtworks = [artwork]
        return mirror
    }

    private func sticker(at point: NormalizedPoint, zIndex: Int) -> StickerObject {
        let width = 0.16
        let height = StickerObject.height(for: width, aspectRatio: 1)
        return StickerObject(
            source: .builtIn(.heart),
            frame: NormalizedRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height),
            zIndex: zIndex
        )
    }

    /// 실제 가져오기를 거친 디자인. 카메라 영역은 이 단계에서 지워진다.
    private func importedArtworkImage(cameraOpaque: Bool = true) throws -> CGImage {
        try MirrorArtworkImporter.normalize(pngData(artworkImage(cameraOpaque: cameraOpaque)))
    }

    /// 캔버스 tap 판정에 쓰는 것과 같은 변환.
    private let fitted = MirrorViewTransform.fitted(in: CGSize(width: 360, height: 780))

    // MARK: - 작업 가이드

    @Test("작업 가이드는 1080 × 2340이다")
    func guideSizeMatchesMasterCanvas() {
        #expect(MirrorArtworkGuide.size == MirrorCanvas.size)
        let image = MirrorArtworkGuide.makeImage()
        #expect(image.size.width == 1080)
        #expect(image.size.height == 2340)
        #expect(image.scale == 1)
    }

    @Test("가이드의 카메라 영역이 실제 거울과 같은 자리다")
    func guideCameraAreaMatchesGeometry() throws {
        let image = try #require(MirrorArtworkGuide.makeImage().cgImage)
        let area = MirrorFrameInsets.standard.mirrorArea

        // 카메라 영역 위쪽 경계선을 가로로 훑으면 점선이 잡힌다 (dash 사이 빈 칸이 있어 구간으로 본다).
        func hasLine(alongY y: Double, from startX: Double, to endX: Double) -> Bool {
            stride(from: startX, through: endX, by: 0.002).contains { x in
                pixel(image, at: NormalizedPoint(x: x, y: y)).alpha > 40
            }
        }
        #expect(hasLine(alongY: area.y, from: 0.3, to: 0.7))
        #expect(hasLine(alongY: area.y + area.height, from: 0.3, to: 0.7))

        // 실제 규격 그대로다 — 가이드가 자기 숫자를 따로 갖지 않는다.
        #expect(abs(area.x * MirrorCanvas.size.width - 108) < 0.001)
        #expect(abs(area.width * MirrorCanvas.size.width - 864) < 0.001)
        #expect(abs(area.height * MirrorCanvas.size.height - 1940) < 0.001)
    }

    @Test("가이드 아래 프레임도 220으로 두껍다")
    func guideBottomInsetIs220() throws {
        let insets = MirrorFrameInsets.standard
        #expect(abs(insets.bottom * MirrorCanvas.size.height - 220) < 0.001)
        #expect(insets.bottom > insets.top)

        // 아래 경계선이 실제로 220px 위쪽에 그려진다.
        let image = try #require(MirrorArtworkGuide.makeImage().cgImage)
        let bottomEdge = 1 - insets.bottom
        let onLine = stride(from: 0.3, through: 0.7, by: 0.002).contains { x in
            pixel(image, at: NormalizedPoint(x: x, y: bottomEdge)).alpha > 40
        }
        #expect(onLine)
        // 그보다 한참 아래(프레임 한가운데)는 비어 있다.
        #expect(pixel(image, at: NormalizedPoint(x: 0.5, y: 1 - insets.bottom / 2)).alpha == 0)
    }

    @Test("가이드 카메라 모서리도 같은 반경으로 둥글다")
    func guideCornerUsesSharedRadius() throws {
        let image = try #require(MirrorArtworkGuide.makeImage().cgImage)
        let area = MirrorFrameInsets.standard.mirrorArea
        let radiusX = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.width
        let radiusY = MirrorGeometry.innerCornerRadius / MirrorCanvas.size.height

        // 둥글기 때문에 사각형 꼭짓점 자리에는 선이 없다.
        let corner = pixel(image, at: NormalizedPoint(x: area.x + radiusX * 0.1, y: area.y + radiusY * 0.1))
        #expect(corner.alpha == 0)
        // 반경만큼 안쪽으로 들어온 곳에서는 곡선이 지난다.
        let onCurve = stride(from: 0.0, through: 1.0, by: 0.05).contains { t in
            let angle = Double.pi / 2 * t
            let point = NormalizedPoint(
                x: area.x + radiusX - radiusX * sin(angle),
                y: area.y + radiusY - radiusY * cos(angle)
            )
            return pixel(image, at: point).alpha > 30
        }
        #expect(onCurve)
    }

    @Test("가이드 배경은 투명하다")
    func guideBackgroundIsTransparent() throws {
        let image = try #require(MirrorArtworkGuide.makeImage().cgImage)
        // 프레임 한가운데도, 카메라 한가운데도 비어 있다 — 밑에 깔고 그리는 참고선이다.
        #expect(pixel(image, at: NormalizedPoint(x: 0.05, y: 0.5)).alpha == 0)
        #expect(pixel(image, at: NormalizedPoint(x: 0.5, y: 0.5)).alpha == 0)
    }

    @Test("가이드를 파일로 내보낼 수 있다")
    func guideExportsPNGFile() throws {
        let url = try MirrorArtworkGuide.exportPNG()
        defer { try? FileManager().removeItem(at: url) }

        #expect(url.pathExtension == "png")
        #expect(FileManager().fileExists(atPath: url.path))
        // 임시 파일이다 — 사용자 콘텐츠 저장소에 남기지 않는다.
        #expect(url.path.contains(FileManager.default.temporaryDirectory.lastPathComponent)
                || url.path.hasPrefix(NSTemporaryDirectory()))

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 1080)
        #expect(decoded.height == 2340)
    }

    // MARK: - 가져오기 검사

    @Test("정확히 1080 × 2340이면 크기를 바꾸지 않는다")
    func exactSizeKeepsItsSize() throws {
        let result = try MirrorArtworkImporter.normalize(pngData(artworkImage()))
        #expect(result.width == 1080)
        #expect(result.height == 2340)
        // 프레임에 그린 표식은 그대로 남는다.
        #expect(pixel(result, at: NormalizedPoint(x: 0.05, y: 0.02)).red > 200)
    }

    @Test("비율이 같고 더 크면 1080 × 2340으로 줄인다")
    func sameRatioLargerImageIsNormalized() throws {
        let result = try MirrorArtworkImporter.normalize(pngData(artworkImage(width: 2160, height: 4680)))
        #expect(result.width == 1080)
        #expect(result.height == 2340)
        // 위치 비율이 그대로다 — 표식이 여전히 왼쪽 위에 있다.
        #expect(pixel(result, at: NormalizedPoint(x: 0.05, y: 0.02)).red > 200)
        #expect(pixel(result, at: NormalizedPoint(x: 0.5, y: 0.5)).alpha == 0)
    }

    @Test("비율이 다르면 늘리지 않고 되묻는다")
    func wrongAspectRatioIsRejected() {
        #expect(throws: ArtworkImportError.wrongAspectRatio(width: 1000, height: 1000)) {
            try MirrorArtworkImporter.normalize(pngData(artworkImage(width: 1000, height: 1000)))
        }
        #expect(throws: ArtworkImportError.self) {
            try MirrorArtworkImporter.normalize(pngData(artworkImage(width: 1080, height: 1920)))
        }
    }

    @Test("읽을 수 없는 파일은 조용히 실패한다")
    func unreadableDataThrows() {
        #expect(throws: ArtworkImportError.unreadable) {
            try MirrorArtworkImporter.normalize(Data("이건 이미지가 아니다".utf8))
        }
    }

    @Test("투명 PNG는 투명도를 유지한 채 통과한다")
    func transparentPNGKeepsAlpha() throws {
        let result = try MirrorArtworkImporter.normalize(pngData(artworkImage()))
        #expect(pixel(result, at: NormalizedPoint(x: 0.5, y: 0.5)).alpha == 0)   // 카메라 영역은 비었다
        #expect(pixel(result, at: NormalizedPoint(x: 0.05, y: 0.02)).alpha > 200)
    }

    @Test("카메라 영역은 가져올 때 지워진다 — 프레임만 남는다")
    func cameraAreaIsClearedOnImport() throws {
        // 캔버스 전체를 칠해서 가져와도
        let imported = try importedArtworkImage(cameraOpaque: true)
        let area = MirrorFrameInsets.standard.mirrorArea

        // 점선 안쪽은 전부 비어 있다.
        for point in [
            NormalizedPoint(x: 0.5, y: 0.5),
            NormalizedPoint(x: area.x + 0.02, y: area.y + 0.02),
            NormalizedPoint(x: area.x + area.width - 0.02, y: area.y + area.height - 0.02)
        ] {
            #expect(pixel(imported, at: point).alpha == 0)
        }
        // 프레임에 그린 것은 그대로 남는다.
        #expect(pixel(imported, at: NormalizedPoint(x: 0.05, y: 0.02)).alpha > 200)
    }

    @Test("지워지는 경계가 실제 카메라 영역과 정확히 같다")
    func clearedAreaMatchesCameraGeometry() throws {
        let imported = try importedArtworkImage()
        let area = MirrorFrameInsets.standard.mirrorArea
        let insets = MirrorFrameInsets.standard

        // 위(180)와 아래(220)는 두께가 다르다. 뒤집혀 지워졌다면 여기서 걸린다.
        let justAbove = NormalizedPoint(x: 0.5, y: area.y - 6 / MirrorCanvas.size.height)
        let justInsideTop = NormalizedPoint(x: 0.5, y: area.y + 6 / MirrorCanvas.size.height)
        let justBelow = NormalizedPoint(x: 0.5, y: 1 - insets.bottom + 6 / MirrorCanvas.size.height)
        let justInsideBottom = NormalizedPoint(x: 0.5, y: 1 - insets.bottom - 6 / MirrorCanvas.size.height)

        #expect(pixel(imported, at: justAbove).alpha > 200)          // 위 프레임은 남는다
        #expect(pixel(imported, at: justInsideTop).alpha == 0)
        #expect(pixel(imported, at: justBelow).alpha > 200)          // 아래 프레임도 남는다
        #expect(pixel(imported, at: justInsideBottom).alpha == 0)

        // 좌우도 같은 규격.
        #expect(pixel(imported, at: NormalizedPoint(x: insets.left / 2, y: 0.5)).alpha > 200)
        #expect(pixel(imported, at: NormalizedPoint(x: 1 - insets.right / 2, y: 0.5)).alpha > 200)
    }

    @Test("EXIF 회전이 있는 이미지는 실제 방향으로 펴서 받는다")
    func orientationIsNormalized() throws {
        // 저장된 픽셀은 가로(2340 × 1080)지만 orientation 6은 세로로 보이라는 뜻이다.
        let landscape = artworkImage(width: 2340, height: 1080)
        let result = try MirrorArtworkImporter.normalize(jpegData(landscape, orientation: 6))
        #expect(result.width == 1080)
        #expect(result.height == 2340)
    }

    @Test("가져온 디자인은 PNG로 저장되고 캐시를 비워도 다시 읽힌다")
    func importedAssetIsStoredAsPNG() throws {
        try withStore { store in
            let artworks = ImportedArtworkAssetStore()
            artworks.attach(store)
            let id = artworks.register(artworkImage())
            store.flush()

            let url = store.assetURL(id, kind: .importedArtwork)
            #expect(url.pathExtension == "png")
            #expect(url.path.contains("ImportedArtworkAssets"))
            #expect(FileManager().fileExists(atPath: url.path))
            // 사진 스티커 폴더와 섞이지 않는다.
            #expect(!FileManager().fileExists(atPath: store.assetURL(id, kind: .photoSticker).path))

            // 메모리 캐시가 빈 새 보관소에서도 읽힌다.
            let fresh = ImportedArtworkAssetStore()
            fresh.attach(MirrorStore(root: store.root))
            let reloaded = try #require(fresh.image(for: id))
            #expect(reloaded.width == 1080)
            #expect(pixel(reloaded, at: NormalizedPoint(x: 0.5, y: 0.5)).alpha == 0)   // 투명도 유지
        }
    }

    // MARK: - 모델 / History

    @Test("외부 디자인은 참조와 순서만 저장한다")
    func artworkRoundTrip() throws {
        let artwork = ImportedArtworkObject(assetID: UUID(), opacity: 0.6, zIndex: 3)
        let data = try JSONEncoder().encode(artwork)
        let restored = try JSONDecoder().decode(ImportedArtworkObject.self, from: data)

        #expect(restored == artwork)
        #expect(data.count < 400)                       // binary가 섞이지 않았다
        // 위치 / 크기 / 회전을 갖지 않는다. 언제나 캔버스 전체다.
        #expect(ImportedArtworkObject.frame == NormalizedRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test("추가는 Undo / Redo된다")
    func addIsUndoable() {
        var design = MirrorDesign.blank
        var history = EditorHistory()
        let artwork = ImportedArtworkObject(assetID: UUID())

        history.apply(.addImportedArtwork(artwork), to: &design.snapshot)
        #expect(design.importedArtworks.count == 1)

        history.undo(&design.snapshot)
        #expect(design.importedArtworks.isEmpty)

        history.redo(&design.snapshot)
        #expect(design.importedArtworks.map(\.id) == [artwork.id])
    }

    @Test("투명도는 Undo / Redo된다")
    func opacityIsUndoable() {
        var design = MirrorDesign.blank
        var history = EditorHistory()
        let artwork = ImportedArtworkObject(assetID: UUID())
        history.apply(.addImportedArtwork(artwork), to: &design.snapshot)

        var faded = artwork
        faded.opacity = 0.4
        history.apply(.replaceImportedArtwork(faded), to: &design.snapshot)
        #expect(design.importedArtworks[0].opacity == 0.4)

        history.undo(&design.snapshot)
        #expect(design.importedArtworks[0].opacity == 1)
    }

    @Test("교체해도 같은 레이어다 — id와 순서가 유지된다")
    func replaceKeepsIdentityAndOrder() {
        var design = MirrorDesign.blank
        var history = EditorHistory()
        var artwork = ImportedArtworkObject(assetID: UUID())
        artwork.zIndex = 2
        history.apply(.addImportedArtwork(artwork), to: &design.snapshot)

        let newAsset = UUID()
        var replaced = artwork
        replaced.assetID = newAsset
        history.apply(.replaceImportedArtwork(replaced), to: &design.snapshot)

        #expect(design.importedArtworks.count == 1)
        #expect(design.importedArtworks[0].id == artwork.id)
        #expect(design.importedArtworks[0].zIndex == 2)
        #expect(design.importedArtworks[0].assetID == newAsset)

        history.undo(&design.snapshot)
        #expect(design.importedArtworks[0].assetID == artwork.assetID)
    }

    @Test("삭제는 Undo된다")
    func deleteIsUndoable() {
        var design = MirrorDesign.blank
        var history = EditorHistory()
        let artwork = ImportedArtworkObject(assetID: UUID())
        history.apply(.addImportedArtwork(artwork), to: &design.snapshot)
        history.apply(.deleteImportedArtwork(artwork.id), to: &design.snapshot)
        #expect(design.importedArtworks.isEmpty)

        history.undo(&design.snapshot)
        #expect(design.importedArtworks.map(\.assetID) == [artwork.assetID])
    }

    @Test("History에는 이미지가 아니라 참조만 들어간다")
    func historyKeepsReferenceOnly() {
        let store = ImportedArtworkAssetStore()
        let assetID = store.register(artworkImage())
        let before = store.count

        var design = MirrorDesign.blank
        var history = EditorHistory()
        let artwork = ImportedArtworkObject(assetID: assetID)
        history.apply(.addImportedArtwork(artwork), to: &design.snapshot)
        for _ in 0..<20 {
            history.apply(.replaceImportedArtwork(artwork), to: &design.snapshot)
            history.undo(&design.snapshot)
            history.redo(&design.snapshot)
        }

        #expect(store.count == before)                                  // 이미지가 늘지 않았다
        #expect(design.snapshot.importedArtworks[0].assetID == assetID) // 참조만 들고 있다
    }

    // MARK: - Layers

    @Test("외부 디자인도 Layers 목록에 나온다")
    func artworkAppearsInLayers() {
        var design = MirrorDesign.blank
        design.importedArtworks = [ImportedArtworkObject(assetID: UUID())]

        let layer = design.decorationLayers[0]
        #expect(layer.title == "외부 디자인")
        #expect(layer.subtitle == "PNG")
        #expect(layer.id == design.importedArtworks[0].id)
        #expect(!layer.isLocked)
    }

    @Test("외부 디자인 / 스티커 / 텍스트가 하나의 순서를 공유한다")
    func mixedOrderIncludesArtwork() {
        var design = MirrorDesign.blank
        design.importedArtworks = [ImportedArtworkObject(assetID: UUID(), zIndex: 0)]
        design.stickers = [sticker(at: NormalizedPoint(x: 0.5, y: 0.4), zIndex: 1)]
        var text = TextObject(text: "위", center: NormalizedPoint(x: 0.5, y: 0.6))
        text.zIndex = 2
        design.texts = [text]

        #expect(design.decorationLayers.map(\.subtitle) == ["텍스트", "스티커", "PNG"])
        // 새 장식은 외부 디자인 위로, 새 외부 디자인은 맨 아래로 들어간다.
        #expect(design.topDecorationZIndex == 2)
        #expect(design.bottomDecorationZIndex == 0)
    }

    @Test("순서를 바꾸면 셋 모두 0부터 다시 매겨진다")
    func reorderNormalizesEveryDecoration() {
        var design = MirrorDesign.blank
        let assetID = UUID()
        design.importedArtworks = [ImportedArtworkObject(assetID: assetID, opacity: 0.7, zIndex: 5)]
        design.stickers = [sticker(at: NormalizedPoint(x: 0.5, y: 0.4), zIndex: 9)]
        var text = TextObject(text: "위", center: NormalizedPoint(x: 0.5, y: 0.6))
        text.zIndex = 2
        design.texts = [text]

        let artworkID = design.importedArtworks[0].id
        var snapshot = design.snapshot
        snapshot.reorderDecorations(frontToBack: [artworkID, text.id, design.stickers[0].id])
        design.snapshot = snapshot

        let all = design.importedArtworks.map(\.zIndex) + design.stickers.map(\.zIndex) + design.texts.map(\.zIndex)
        #expect(all.sorted() == [0, 1, 2])
        #expect(design.decorationLayers.map(\.id) == [artworkID, text.id, design.stickers[0].id])
        // 참조와 나머지 속성은 그대로다.
        #expect(design.importedArtworks[0].assetID == assetID)
        #expect(design.importedArtworks[0].opacity == 0.7)
    }

    @Test("외부 디자인은 캔버스를 눌러 고를 수 없다")
    func artworkIsNotACanvasHitTestTarget() {
        var design = MirrorDesign.blank
        design.importedArtworks = [ImportedArtworkObject(assetID: UUID(), zIndex: 9)]

        // 캔버스 전체를 덮지만 어디를 눌러도 잡히지 않는다.
        for point in [NormalizedPoint(x: 0.5, y: 0.5), NormalizedPoint(x: 0.05, y: 0.05)] {
            let location = fitted.point(point)
            #expect(design.topSelectableDecoration(at: location, in: fitted) == nil)
        }
        #expect(!design.decorationLayers[0].isCanvasSelectable)
        // 목록에는 있으므로 Layers에서 고를 수 있다.
        #expect(design.decorationLayers.count == 1)
    }

    @Test("외부 디자인 위의 스티커 / 텍스트는 그대로 잡힌다")
    func decorationsAboveArtworkStayTappable() {
        var design = MirrorDesign.blank
        // 외부 디자인이 zIndex가 더 높아도 선택을 방해하지 않는다.
        design.importedArtworks = [ImportedArtworkObject(assetID: UUID(), zIndex: 99)]
        design.stickers = [sticker(at: NormalizedPoint(x: 0.5, y: 0.5), zIndex: 1)]
        var text = TextObject(text: "글", center: NormalizedPoint(x: 0.3, y: 0.3))
        text.zIndex = 2
        design.texts = [text]

        let onSticker = design.topSelectableDecoration(at: fitted.point(design.stickers[0].center), in: fitted)
        #expect(onSticker?.id == design.stickers[0].id)

        let onText = design.topSelectableDecoration(at: fitted.point(text.center), in: fitted)
        #expect(onText?.id == text.id)
    }

    // MARK: - 렌더

    @Test("투명한 부분에서는 실제 카메라가 그대로 보인다")
    func transparentAreaLeavesCameraVisible() {
        let assetID = ImportedArtworkAssetStore.shared.register(artworkImage())
        var design = MirrorDesign.blank
        design.importedArtworks = [ImportedArtworkObject(assetID: assetID)]

        let center = runtimePixel(design, at: NormalizedPoint(x: 0.5, y: 0.5))
        #expect((center?.alpha ?? 255) < 20)
    }

    @Test("가져온 디자인은 프레임에만 보이고 카메라는 비운다")
    func importedArtworkOnlyCoversFrame() throws {
        let assetID = ImportedArtworkAssetStore.shared.register(try importedArtworkImage())
        var design = MirrorDesign.blank
        design.importedArtworks = [ImportedArtworkObject(assetID: assetID)]

        // 프레임에는 그려지고
        let frame = runtimePixel(design, at: NormalizedPoint(x: 0.05, y: 0.5))
        #expect((frame?.alpha ?? 0) > 200)
        // 카메라 영역은 비어 있다 — 얼굴이 그대로 보인다.
        let center = runtimePixel(design, at: NormalizedPoint(x: 0.5, y: 0.5))
        #expect((center?.alpha ?? 255) < 20)
    }

    @Test("전체 캔버스에 어긋남 없이 정렬된다")
    func artworkFillsWholeCanvasExactly() {
        let assetID = ImportedArtworkAssetStore.shared.register(artworkImage())
        var design = MirrorDesign.blank
        design.importedArtworks = [ImportedArtworkObject(assetID: assetID)]

        // 원본에서 빨간 표식은 왼쪽 위 가로 14% 안에만 있다. 렌더 결과도 정확히 같은 자리다.
        let inside = runtimePixel(design, at: NormalizedPoint(x: 0.12, y: 0.02))
        #expect((inside?.red ?? 0) > 150)
        #expect((inside?.green ?? 255) < 120)

        // 경계 바로 바깥은 표식이 아니라 디자인의 프레임 밴드(분홍)다.
        let outside = runtimePixel(design, at: NormalizedPoint(x: 0.17, y: 0.02))
        #expect((outside?.green ?? 0) > 90)
        #expect((outside?.alpha ?? 0) > 200)
    }

    @Test("홈 / 내 거울 미리보기에도 나온다")
    func artworkAppearsInPreviews() throws {
        let assetID = ImportedArtworkAssetStore.shared.register(try importedArtworkImage())
        let saved = mirror(with: ImportedArtworkObject(assetID: assetID))

        let mark = previewPixel(saved, at: NormalizedPoint(x: 0.04, y: 0.02))
        #expect((mark?.red ?? 0) > 150)
        #expect((mark?.green ?? 255) < 120)
    }

    @Test("Capture에도 포함된다")
    func artworkReachesCapture() throws {
        let assetID = ImportedArtworkAssetStore.shared.register(try importedArtworkImage())
        var design = MirrorDesign.blank
        design.importedArtworks = [ImportedArtworkObject(assetID: assetID)]

        let captured = try #require(
            MirrorCapture.compose(frame: nil, design: design, size: CGSize(width: 300, height: 650))
        )
        let image = try #require(captured.cgImage)
        let transform = MirrorViewTransform.aspectFilled(in: CGSize(width: image.width, height: image.height))
        let screen = transform.point(NormalizedPoint(x: 0.04, y: 0.02))
        let mark = pixel(image, x: Int(screen.x), y: Int(screen.y))
        #expect(mark.red > mark.green)
    }

    @Test("투명도가 렌더에 반영된다")
    func opacityChangesRender() throws {
        let assetID = ImportedArtworkAssetStore.shared.register(try importedArtworkImage())
        var design = MirrorDesign.blank
        design.importedArtworks = [ImportedArtworkObject(assetID: assetID, opacity: 1)]
        // 표식은 순수 빨강이라 초록이 0에 가깝다. 옅어질수록 아래 크림색 초록이 올라온다.
        let spot = NormalizedPoint(x: 0.04, y: 0.02)
        let full = runtimePixel(design, at: spot)?.green ?? 255
        design.importedArtworks[0].opacity = 0.3
        let faded = runtimePixel(design, at: spot)?.green ?? 0

        #expect(full < 60)
        #expect(faded > full + 60)
    }

    @Test("순서를 바꾸면 그림이 실제로 위아래로 바뀐다")
    func reorderChangesRenderedResult() throws {
        let assetID = ImportedArtworkAssetStore.shared.register(try importedArtworkImage())
        let photo = PhotoStickerAssetStore.shared.register(solidImage())

        // 프레임 위에서 겹쳐 본다 — 이제 외부 디자인은 카메라 영역에 그려지지 않는다.
        let spot = NormalizedPoint(x: 0.04, y: 0.02)
        var design = MirrorDesign.blank
        design.importedArtworks = [ImportedArtworkObject(assetID: assetID, zIndex: 0)]
        let width = 0.12
        design.stickers = [StickerObject(
            source: photo,
            frame: NormalizedRect(x: spot.x - width / 2, y: spot.y - width / 8, width: width, height: width / 4),
            zIndex: 1
        )]

        // 스티커가 위 → 파란 스티커가 보인다.
        let stickerOnTop = runtimePixel(design, at: spot)
        #expect((stickerOnTop?.blue ?? 0) > (stickerOnTop?.red ?? 255))

        var snapshot = design.snapshot
        snapshot.reorderDecorations(frontToBack: [design.importedArtworks[0].id, design.stickers[0].id])
        design.snapshot = snapshot

        // 외부 디자인이 위 → 빨간 표식이 덮는다.
        let artworkOnTop = runtimePixel(design, at: spot)
        #expect((artworkOnTop?.red ?? 0) > (artworkOnTop?.blue ?? 255))
    }

    private func solidImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 120, height: 120,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        return context.makeImage()!
    }

    // MARK: - Persistence

    /// 예전(v1) 저장 파일을 그대로 흉내 낸다 — `importedArtworks` 키가 아예 없다.
    private func makeV1File(in store: MirrorStore) throws -> (mirrorID: String, photoAssetID: UUID) {
        let photo = PhotoStickerAssetStore.shared.register(solidImage())
        var old = MyMirror(
            id: "made-v1", name: "예전 거울", origin: .made,
            style: BasicMirror.mint.style
        )
        old.strokes = [DrawingStroke(
            points: [NormalizedPoint(x: 0.1, y: 0.1), NormalizedPoint(x: 0.6, y: 0.6)],
            brush: .pencil, color: .red, width: 0.02, opacity: 0.8, zIndex: 1
        )]
        old.stickers = [StickerObject(
            source: photo,
            frame: NormalizedRect(x: 0.3, y: 0.3, width: 0.2, height: 0.1),
            zIndex: 4
        )]
        var text = TextObject(text: "예전\n텍스트", center: NormalizedPoint(x: 0.5, y: 0.8))
        text.zIndex = 7
        text.style = .rounded
        old.texts = [text]

        let library = PersistedLibrary(currentMirrorID: old.id, mirrors: [old], purchasedCreatedSlots: 5)
        var json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(library)) as! [String: Any]
        json["schemaVersion"] = 1
        json["mirrors"] = (json["mirrors"] as! [[String: Any]]).map { mirror -> [String: Any] in
            var copy = mirror
            copy.removeValue(forKey: "importedArtworks")     // v1에는 없던 키
            return copy
        }

        try FileManager().createDirectory(at: store.root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json).write(to: store.libraryURL)
        return (old.id, photo.photoAssetID!)
    }

    @Test("schema v1 파일이 v2로 올라오고 내용이 하나도 사라지지 않는다")
    func v1MigratesToV2WithoutLoss() throws {
        try withStore { store in
            let (mirrorID, photoAssetID) = try makeV1File(in: store)

            let library = MirrorLibrary(
                store: store,
                assets: PhotoStickerAssetStore(),
                artworks: ImportedArtworkAssetStore()
            )
            let restored = try #require(library.mirrors.first)

            #expect(library.mirrors.count == 1)
            #expect(restored.id == mirrorID)
            #expect(restored.name == "예전 거울")
            #expect(restored.origin == .made)
            #expect(restored.strokes[0].points.count == 2)
            #expect(restored.strokes[0].brush == .pencil)
            #expect(restored.stickers[0].source.photoAssetID == photoAssetID)
            #expect(restored.stickers[0].zIndex == 4)
            #expect(restored.texts[0].text == "예전\n텍스트")
            #expect(restored.texts[0].style == .rounded)
            #expect(restored.texts[0].zIndex == 7)
            #expect(library.currentID == mirrorID)
            #expect(library.createdCapacity == MirrorStoragePolicy.freeCreatedSlots + 5)
            // 새 필드는 빈 배열로 들어온다.
            #expect(restored.importedArtworks.isEmpty)

            // 다시 저장하면 지금 버전으로 적힌다.
            library.apply(restored)
            store.flush()
            let data = try Data(contentsOf: store.libraryURL)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            #expect(json["schemaVersion"] as? Int == MirrorSchema.current)
            #expect(relaunch(store).mirrors.count == 1)
        }
    }

    @Test("외부 디자인이 앱을 다시 켜도 그대로 있다")
    func artworkSurvivesRelaunch() throws {
        try withStore { store in
            let artworks = ImportedArtworkAssetStore()
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore(), artworks: artworks)
            let assetID = artworks.register(artworkImage())

            var design = MirrorDesign.blank
            design.importedArtworks = [ImportedArtworkObject(assetID: assetID, opacity: 0.8, zIndex: 0)]
            library.save(design, name: "외부 거울", context: .createNew)

            let reopened = relaunch(store)
            let restored = try #require(reopened.mirrors.first?.importedArtworks.first)
            #expect(restored.assetID == assetID)
            #expect(restored.opacity == 0.8)
            #expect(MirrorDesign(mirror: reopened.mirrors[0]).decorationLayers.count == 1)

            let fresh = ImportedArtworkAssetStore()
            fresh.attach(MirrorStore(root: store.root))
            #expect(fresh.image(for: assetID) != nil)
        }
    }

    @Test("거울을 복제해도 디자인 파일이 늘지 않는다")
    func duplicateSharesArtworkFile() throws {
        try withStore { store in
            let artworks = ImportedArtworkAssetStore()
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore(), artworks: artworks)
            let assetID = artworks.register(artworkImage())

            var design = MirrorDesign.blank
            design.importedArtworks = [ImportedArtworkObject(assetID: assetID)]
            library.save(design, name: "원본", context: .createNew)
            library.duplicate(library.mirrors[0])
            store.flush()

            let files = try FileManager().contentsOfDirectory(
                at: store.assetsDirectory(.importedArtwork), includingPropertiesForKeys: nil
            )
            #expect(files.count == 1)
            #expect(library.mirrors[1].importedArtworks[0].assetID == assetID)
        }
    }

    @Test("같은 디자인을 쓰는 거울이 남아 있으면 파일을 지우지 않는다")
    func sharedArtworkSurvivesOneDeletion() throws {
        try withStore { store in
            let artworks = ImportedArtworkAssetStore()
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore(), artworks: artworks)
            let assetID = artworks.register(artworkImage())

            var design = MirrorDesign.blank
            design.importedArtworks = [ImportedArtworkObject(assetID: assetID)]
            library.save(design, name: "하나", context: .createNew)
            library.duplicate(library.mirrors[0])

            library.delete(library.mirrors[0])
            store.flush()
            #expect(FileManager().fileExists(atPath: store.assetURL(assetID, kind: .importedArtwork).path))
        }
    }

    @Test("마지막으로 쓰던 거울을 지우면 디자인 파일도 정리된다")
    func lastArtworkReferenceIsCollected() throws {
        try withStore { store in
            let artworks = ImportedArtworkAssetStore()
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore(), artworks: artworks)
            let assetID = artworks.register(artworkImage())

            var design = MirrorDesign.blank
            design.importedArtworks = [ImportedArtworkObject(assetID: assetID)]
            library.save(design, name: "하나", context: .createNew)
            store.flush()
            #expect(FileManager().fileExists(atPath: store.assetURL(assetID, kind: .importedArtwork).path))

            library.delete(library.mirrors[0])
            store.flush()
            #expect(!FileManager().fileExists(atPath: store.assetURL(assetID, kind: .importedArtwork).path))
        }
    }

    @Test("고르다 만 디자인은 앱을 켤 때 정리된다")
    func orphanArtworkIsCleanedAtLaunch() throws {
        try withStore { store in
            let artworks = ImportedArtworkAssetStore()
            artworks.attach(store)
            let orphan = artworks.register(artworkImage())      // 미리보기까지만 보고 취소한 경우
            store.flush()
            #expect(FileManager().fileExists(atPath: store.assetURL(orphan, kind: .importedArtwork).path))

            let next = MirrorStore(root: store.root)
            _ = MirrorLibrary(store: next, assets: PhotoStickerAssetStore(), artworks: ImportedArtworkAssetStore())
            next.flush()
            #expect(!FileManager().fileExists(atPath: store.assetURL(orphan, kind: .importedArtwork).path))
        }
    }

    @Test("앱보다 새 버전 파일은 여전히 읽지도 덮어쓰지도 않는다")
    func futureSchemaIsStillProtected() throws {
        try withStore { store in
            var future = PersistedLibrary(currentMirrorID: "x", mirrors: [])
            future.schemaVersion = MirrorSchema.current + 1
            try FileManager().createDirectory(at: store.root, withIntermediateDirectories: true)
            try JSONEncoder().encode(future).write(to: store.libraryURL)

            #expect(store.load() == .tooNew(MirrorSchema.current + 1))

            let library = MirrorLibrary(
                store: MirrorStore(root: store.root),
                assets: PhotoStickerAssetStore(),
                artworks: ImportedArtworkAssetStore()
            )
            library.save(MirrorDesign.blank, name: "덮어쓰기", context: .createNew)
            store.flush()
            #expect(store.load() == .tooNew(MirrorSchema.current + 1))
        }
    }

    @Test("외부에서 만들기도 새 거울 저장 정책(createNew)을 그대로 따른다")
    func externalCreationUsesCreateNewContext() throws {
        try withStore { store in
            let artworks = ImportedArtworkAssetStore()
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore(), artworks: artworks)
            var design = MirrorDesign.blank
            design.importedArtworks = [ImportedArtworkObject(assetID: artworks.register(artworkImage()))]

            #expect(library.needsName(for: .createNew))          // 이름을 묻는다
            let outcome = library.save(design, name: "외부 거울", context: .createNew)
            #expect(outcome.name == "외부 거울")
            #expect(library.mirrors[0].origin == .made)
            #expect(library.createdCount == 1)
            // 홈 저장 정책은 그대로다.
            #expect(!library.needsName(for: .editCurrent))
        }
    }
}
