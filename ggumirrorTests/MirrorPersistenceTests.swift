//
//  MirrorPersistenceTests.swift
//  ggumirrorTests
//
//  "앱을 완전히 끄고 다시 켜도 거울이 그대로인가"를 확인한다.
//
//  모든 테스트는 자기 임시 폴더를 쓴다 — 실제 앱 Application Support는 건드리지 않는다.
//

import Testing
import SwiftUI
import UIKit
@testable import ggumirror

@MainActor
struct MirrorPersistenceTests {

    // MARK: - 도구

    /// 테스트마다 새 임시 폴더. 끝나면 지운다.
    private func withStore(_ body: (MirrorStore) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = MirrorStore(root: root)
        defer {
            store.flush()
            try? FileManager().removeItem(at: root)
        }
        try body(store)
    }

    /// 앱을 껐다 켠 상태. 같은 폴더를 새 객체로 다시 읽는다.
    private func relaunch(_ store: MirrorStore) -> MirrorLibrary {
        store.flush()
        return MirrorLibrary(store: MirrorStore(root: store.root), assets: PhotoStickerAssetStore())
    }

    private func testImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.9, alpha: 1))
        // 가운데만 칠한다 — 가장자리는 투명하게 남는다.
        context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        return context.makeImage()!
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

    private func stroke(_ points: [NormalizedPoint], brush: EditorBrush = .marker) -> DrawingStroke {
        DrawingStroke(points: points, brush: brush, color: .red, width: 0.02, opacity: 0.7, zIndex: 1)
    }

    private func photoSticker(_ source: StickerSource, at point: NormalizedPoint, zIndex: Int = 0) -> StickerObject {
        let width = 0.2
        let height = StickerObject.height(for: width, aspectRatio: source.aspectRatio)
        return StickerObject(
            source: source,
            frame: NormalizedRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height),
            zIndex: zIndex
        )
    }

    /// 그리기 / 스티커 / 사진 / 텍스트가 모두 든 거울 한 장.
    private func richMirror(photo: StickerSource) -> MyMirror {
        var mirror = MyMirror(
            id: "made-test",
            name: "테스트 거울",
            origin: .made,
            style: MirrorStyle(frame: .green, insets: .standard, doodles: [
                .init(symbol: "heart", x: 0.1, y: 0.2, size: 0.05, rotation: 12)
            ])
        )
        mirror.strokes = [stroke([
            NormalizedPoint(x: 0.1, y: 0.1),
            NormalizedPoint(x: 0.5, y: 0.5)
        ])]
        var builtIn = photoSticker(.builtIn(.ribbon), at: NormalizedPoint(x: 0.3, y: 0.4), zIndex: 0)
        builtIn.rotation = 33
        builtIn.opacity = 0.6
        builtIn.isLocked = true
        builtIn.isFlippedHorizontally = true
        builtIn.tintColor = .purple
        mirror.stickers = [builtIn, photoSticker(photo, at: NormalizedPoint(x: 0.5, y: 0.5), zIndex: 1)]
        var text = TextObject(text: "안녕\n거울", center: NormalizedPoint(x: 0.5, y: 0.8))
        text.style = .serif
        text.alignment = .trailing
        text.color = .blue
        text.rotation = -8
        text.opacity = 0.9
        text.zIndex = 2
        text.isLocked = true
        text.fontSize = 0.12
        mirror.texts = [text]
        return mirror
    }

    private func roundTrip(_ mirror: MyMirror) throws -> MyMirror {
        let data = try JSONEncoder().encode(mirror)
        return try JSONDecoder().decode(MyMirror.self, from: data)
    }

    /// 색은 저장하면서 float로 한 번 접히므로 정확히 같지는 않다. 눈에 보이는 차이만 본다.
    private func isSameColor(_ lhs: Color, _ rhs: Color) -> Bool {
        let a = RGBAColor(lhs), b = RGBAColor(rhs)
        return abs(a.red - b.red) < 0.001 && abs(a.green - b.green) < 0.001
            && abs(a.blue - b.blue) < 0.001 && abs(a.alpha - b.alpha) < 0.001
    }

    // MARK: - Codec

    @Test("거울 한 장이 저장했다 읽어도 같다")
    func mirrorRoundTrip() throws {
        let store = PhotoStickerAssetStore()
        let mirror = richMirror(photo: store.register(testImage(width: 300, height: 200)))
        let restored = try roundTrip(mirror)

        #expect(restored.id == mirror.id)
        #expect(restored.name == mirror.name)
        #expect(restored.origin == mirror.origin)
        #expect(restored.style.insets == mirror.style.insets)
        #expect(restored.style.doodles == mirror.style.doodles)
        // 편집 화면이 쓰는 형태로 되돌려도 같은 거울이다.
        let design = MirrorDesign(mirror: restored)
        #expect(design.strokes.count == 1)
        #expect(design.stickers.count == 2)
        #expect(design.texts.count == 1)
    }

    @Test("획은 점 / 브러시 / 색 / 굵기 / 투명도가 그대로다")
    func strokeRoundTrip() throws {
        var mirror = MyMirror(id: "m", name: "n", origin: .made, style: MirrorStyle(frame: .white))
        let points = (0..<40).map { NormalizedPoint(x: Double($0) / 40, y: 0.3) }
        mirror.strokes = [stroke(points, brush: .highlighter)]

        let restored = try roundTrip(mirror).strokes[0]
        #expect(restored.id == mirror.strokes[0].id)
        #expect(restored.points.count == 40)
        #expect(restored.points[7].x == points[7].x)
        #expect(restored.brush == .highlighter)
        #expect(restored.width == 0.02)
        #expect(restored.opacity == 0.7)
        #expect(restored.zIndex == 1)
        #expect(isSameColor(restored.color, .red))
    }

    @Test("기본 스티커는 종류 / 위치 / 회전 / 뒤집기 / 색이 그대로다")
    func builtInStickerRoundTrip() throws {
        let store = PhotoStickerAssetStore()
        let mirror = richMirror(photo: store.register(testImage(width: 100, height: 100)))
        let restored = try roundTrip(mirror).stickers[0]
        let original = mirror.stickers[0]

        #expect(restored.source == .builtIn(.ribbon))
        #expect(restored.id == original.id)
        #expect(restored.frame == original.frame)
        #expect(restored.rotation == 33)
        #expect(restored.opacity == 0.6)
        #expect(restored.isFlippedHorizontally)
        #expect(isSameColor(restored.tintColor!, .purple))
    }

    @Test("사진 스티커는 참조(assetID + 비율)만 저장한다")
    func photoStickerReferenceRoundTrip() throws {
        let store = PhotoStickerAssetStore()
        let source = store.register(testImage(width: 400, height: 200))
        let mirror = richMirror(photo: source)

        let data = try JSONEncoder().encode(mirror)
        let json = String(decoding: data, as: UTF8.self)
        // 이미지 binary가 JSON에 섞이지 않았다.
        #expect(data.count < 8_000)
        #expect(json.contains(source.photoAssetID!.uuidString))

        let restored = try roundTrip(mirror).stickers[1]
        #expect(restored.source.photoAssetID == source.photoAssetID)
        #expect(abs(restored.source.aspectRatio - 2) < 0.0001)
    }

    @Test("텍스트는 내용 / 글꼴 / 정렬 / 색 / 크기가 그대로다")
    func textRoundTrip() throws {
        let store = PhotoStickerAssetStore()
        let restored = try roundTrip(richMirror(photo: store.register(testImage(width: 100, height: 100)))).texts[0]

        #expect(restored.text == "안녕\n거울")
        #expect(restored.style == .serif)
        #expect(restored.alignment == .trailing)
        #expect(restored.fontSize == 0.12)
        #expect(restored.rotation == -8)
        #expect(restored.opacity == 0.9)
        #expect(isSameColor(restored.color, .blue))
    }

    @Test("여러 줄 텍스트의 줄바꿈이 유지된다")
    func multilineTextPreserved() throws {
        var mirror = MyMirror(id: "m", name: "n", origin: .made, style: MirrorStyle(frame: .white))
        mirror.texts = [TextObject(text: "첫 줄\n둘째 줄\n셋째 줄", center: NormalizedPoint(x: 0.5, y: 0.5))]

        let restored = try roundTrip(mirror).texts[0]
        #expect(restored.text.components(separatedBy: "\n").count == 3)
        #expect(TextLayout.of(restored).lines.count == 3)
    }

    @Test("장식 zIndex가 그대로 저장된다")
    func zIndexRoundTrip() throws {
        let store = PhotoStickerAssetStore()
        let restored = try roundTrip(richMirror(photo: store.register(testImage(width: 100, height: 100))))
        #expect(restored.stickers.map(\.zIndex) == [0, 1])
        #expect(restored.texts[0].zIndex == 2)
    }

    @Test("origin 네 가지가 모두 그대로 저장된다")
    func originRoundTrip() throws {
        for origin in MirrorOrigin.allCases {
            let mirror = MyMirror(id: "m", name: "n", origin: origin, style: MirrorStyle(frame: .white))
            #expect(try roundTrip(mirror).origin == origin)
        }
    }

    @Test("배경색 / 프레임 두께 / 템플릿 낙서가 그대로 저장된다")
    func styleRoundTrip() throws {
        var mirror = MyMirror(
            id: "m", name: "n", origin: .basic,
            style: BasicMirror.lavender.style
        )
        mirror.style.doodles = [.init(symbol: "star", x: 0.2, y: 0.3, size: 0.04, rotation: -5)]

        let restored = try roundTrip(mirror)
        #expect(isSameColor(restored.style.frame, BasicMirror.lavender.style.frame))
        #expect(restored.style.insets == .standard)
        #expect(restored.style.doodles[0].symbol == "star")
        #expect(restored.style.doodles[0].rotation == -5)
    }

    @Test("저장 파일에는 지금 schemaVersion이 들어간다")
    func schemaVersionIsWritten() throws {
        let data = try JSONEncoder().encode(
            PersistedLibrary(currentMirrorID: "x", mirrors: [])
        )
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["schemaVersion"] as? Int == MirrorSchema.current)
        // 외부 디자인이 들어오면서 2, 두들 스티커가 들어오면서 3이 됐다.
        #expect(MirrorSchema.current == 3)
    }

    // MARK: - Library

    @Test("저장 파일이 없으면 내 거울은 비어 있고 기본 거울을 쓴다")
    func emptyStorageStartsWithDefault() throws {
        try withStore { store in
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore())
            #expect(library.mirrors.isEmpty)
            #expect(library.currentID == MirrorLibrary.defaultMirror.id)
            #expect(library.currentMirror.name == "기본 거울")
            #expect(store.load() == .empty)
        }
    }

    @Test("만든 거울이 다시 켜도 그대로 있다")
    func createdMirrorSurvivesRelaunch() throws {
        try withStore { store in
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore())
            var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
            design.strokes = [stroke([NormalizedPoint(x: 0.2, y: 0.2), NormalizedPoint(x: 0.4, y: 0.4)])]
            design.texts = [TextObject(text: "안녕", center: NormalizedPoint(x: 0.5, y: 0.5))]
            library.save(design, name: "내 거울 하나", context: .createNew)

            let reopened = relaunch(store)
            #expect(reopened.mirrors.count == 1)
            #expect(reopened.mirrors[0].name == "내 거울 하나")
            #expect(reopened.mirrors[0].strokes.count == 1)
            #expect(reopened.mirrors[0].texts[0].text == "안녕")
        }
    }

    @Test("홈에서 고친 내용이 그 자리에 저장된다")
    func editCurrentPersists() throws {
        try withStore { store in
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore())
            library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "", context: .editCurrent)
            let id = library.currentID

            var design = MirrorDesign(mirror: library.currentMirror)
            design.backgroundColor = .orange
            library.save(design, name: "", context: .editCurrent)

            let reopened = relaunch(store)
            #expect(reopened.mirrors.count == 1)                 // 새 거울이 늘지 않았다
            #expect(reopened.mirrors[0].id == id)
            #expect(isSameColor(reopened.mirrors[0].style.frame, .orange))
        }
    }

    @Test("홈 첫 저장의 자동 이름이 그대로 남는다")
    func automaticNamePersists() throws {
        try withStore { store in
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore())
            library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "", context: .editCurrent)
            #expect(library.mirrors[0].name == "나의 거울")

            let reopened = relaunch(store)
            #expect(reopened.mirrors[0].name == "나의 거울")
            // 다시 기본 거울에서 저장하면 다음 번호가 붙는다.
            reopened.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "", context: .editCurrent)
            #expect(reopened.mirrors[1].name == "나의 거울 2")
        }
    }

    @Test("복제하면 원본과 복사본이 둘 다 저장된다")
    func duplicatePersistsBoth() throws {
        try withStore { store in
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore())
            library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "원본", context: .createNew)
            library.duplicate(library.mirrors[0])

            let reopened = relaunch(store)
            #expect(reopened.mirrors.count == 2)
            #expect(reopened.mirrors[1].name == "원본 복사본")
        }
    }

    @Test("+ 거울 만들기로 만든 빈 거울도 저장된다")
    func createNewPersists() throws {
        try withStore { store in
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore())
            library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "새 거울", context: .createNew)

            let reopened = relaunch(store)
            #expect(reopened.mirrors.map(\.name) == ["새 거울"])
            #expect(reopened.mirrors[0].origin == .made)
        }
    }

    @Test("삭제한 거울은 다시 켜도 없다")
    func deletePersists() throws {
        try withStore { store in
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore())
            library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "하나", context: .createNew)
            library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "둘", context: .createNew)
            library.delete(library.mirrors[0])

            let reopened = relaunch(store)
            #expect(reopened.mirrors.map(\.name) == ["둘"])
        }
    }

    @Test("상점에서 받은 기본 템플릿도 저장되고 슬롯을 쓰지 않는다")
    func acquiredTemplatePersists() throws {
        try withStore { store in
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore())
            library.acquire(StoreCatalog.basics[0])

            let reopened = relaunch(store)
            #expect(reopened.mirrors.count == 1)
            #expect(reopened.mirrors[0].origin == .basic)
            #expect(reopened.createdCount == 0)
        }
    }

    @Test("쓰던 거울이 다시 켜도 현재 거울이다")
    func currentMirrorRestored() throws {
        try withStore { store in
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore())
            library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "하나", context: .createNew)
            library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "둘", context: .createNew)
            library.apply(library.mirrors[0])

            let reopened = relaunch(store)
            #expect(reopened.currentID == library.mirrors[0].id)
            #expect(reopened.currentMirror.name == "하나")
        }
    }

    @Test("없는 거울을 가리키고 있으면 기본 거울로 돌아간다")
    func invalidCurrentFallsBack() throws {
        try withStore { store in
            store.save(PersistedLibrary(currentMirrorID: "사라진-거울", mirrors: []))
            store.flush()

            let library = MirrorLibrary(store: MirrorStore(root: store.root), assets: PhotoStickerAssetStore())
            #expect(library.currentID == MirrorLibrary.defaultMirror.id)
            #expect(library.currentMirror.name == "기본 거울")
        }
    }

    @Test("보관 슬롯 개수가 거울 목록과 구매분에서 복원된다")
    func slotStateRestored() throws {
        try withStore { store in
            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore())
            library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "하나", context: .createNew)
            library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "둘", context: .createNew)
            library.acquire(StoreCatalog.basics[1])       // 받은 거울은 슬롯을 쓰지 않는다
            library.grantSlotPack()

            let reopened = relaunch(store)
            #expect(reopened.createdCount == 2)
            #expect(reopened.mirrorCapacity == MirrorStoragePolicy.freeMirrorSlots + MirrorStoragePolicy.slotPackSize)
            #expect(reopened.hasFreeMirrorSlot)
        }
    }

    // MARK: - 실패 복구

    @Test("깨진 파일은 지우지 않고 옆으로 치운 뒤 빈 상태로 시작한다")
    func damagedFileIsQuarantined() throws {
        try withStore { store in
            let fileManager = FileManager()
            try fileManager.createDirectory(at: store.root, withIntermediateDirectories: true)
            try Data("{ 이건 JSON이 아니다".utf8).write(to: store.libraryURL)

            #expect(store.load() == .damaged)
            #expect(fileManager.fileExists(atPath: store.damagedLibraryURL.path))   // 원본은 남아 있다
            #expect(!fileManager.fileExists(atPath: store.libraryURL.path))

            // 앱은 죽지 않고 빈 상태로 계속 쓸 수 있다.
            let next = MirrorStore(root: store.root)
            let library = MirrorLibrary(store: next, assets: PhotoStickerAssetStore())
            #expect(library.mirrors.isEmpty)
            library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "새로", context: .createNew)
            #expect(relaunch(next).mirrors.count == 1)
        }
    }

    @Test("앱보다 새 버전 파일은 읽지도 덮어쓰지도 않는다")
    func tooNewFileIsReadOnly() throws {
        try withStore { store in
            var future = PersistedLibrary(currentMirrorID: "x", mirrors: [])
            future.schemaVersion = MirrorSchema.current + 1
            let data = try JSONEncoder().encode(future)
            try FileManager().createDirectory(at: store.root, withIntermediateDirectories: true)
            try data.write(to: store.libraryURL)

            #expect(store.load() == .tooNew(MirrorSchema.current + 1))

            let library = MirrorLibrary(store: MirrorStore(root: store.root), assets: PhotoStickerAssetStore())
            #expect(library.mirrors.isEmpty)
            library.save(MirrorDesign(mirror: MirrorLibrary.defaultMirror), name: "덮어쓰기", context: .createNew)
            store.flush()

            // 파일은 그대로 미래 버전이다.
            #expect(store.load() == .tooNew(MirrorSchema.current + 1))
        }
    }

    // MARK: - 사진 파일

    @Test("사진을 만들면 투명한 PNG 파일이 생긴다")
    func registerWritesTransparentAsset() throws {
        try withStore { store in
            let assets = PhotoStickerAssetStore()
            assets.attach(store)
            let source = assets.register(testImage(width: 120, height: 80))
            store.flush()

            let url = store.assetURL(source.photoAssetID!)
            #expect(FileManager().fileExists(atPath: url.path))
            #expect(url.pathExtension == "png")
        }
    }

    @Test("앱을 다시 켜면 사진을 디스크에서 읽어 온다")
    func assetReloadsFromDisk() throws {
        try withStore { store in
            let assets = PhotoStickerAssetStore()
            assets.attach(store)
            let source = assets.register(testImage(width: 120, height: 80))
            store.flush()

            // 메모리 캐시가 비어 있는 새 보관소.
            let fresh = PhotoStickerAssetStore()
            fresh.attach(MirrorStore(root: store.root))
            #expect(fresh.image(for: source.photoAssetID!) != nil)
            #expect(fresh.isRegistered(source))
        }
    }

    @Test("저장했다 읽어도 투명도가 살아 있다")
    func alphaSurvivesDisk() throws {
        try withStore { store in
            let assets = PhotoStickerAssetStore()
            assets.attach(store)
            let original = testImage(width: 120, height: 80)
            let source = assets.register(original)
            store.flush()

            let loaded = try #require(MirrorStore(root: store.root).readAsset(source.photoAssetID!))
            #expect(pixel(loaded, x: 1, y: 1).alpha == 0)            // 가장자리는 투명
            let middle = pixel(loaded, x: 60, y: 40)
            #expect(middle.alpha > 200)                              // 피사체는 남아 있다
            #expect(middle.blue > middle.red)
        }
    }

    @Test("저장했다 읽어도 크기와 비율이 같다")
    func aspectRatioSurvivesDisk() throws {
        try withStore { store in
            let assets = PhotoStickerAssetStore()
            assets.attach(store)
            let source = assets.register(testImage(width: 400, height: 200))
            store.flush()

            let loaded = try #require(MirrorStore(root: store.root).readAsset(source.photoAssetID!))
            #expect(loaded.width == 400)
            #expect(loaded.height == 200)
            #expect(abs(source.aspectRatio - 2) < 0.0001)
        }
    }

    @Test("사진 스티커가 앱을 다시 켠 뒤에도 거울에서 보인다")
    func photoStickerSurvivesRelaunch() throws {
        try withStore { store in
            let assets = PhotoStickerAssetStore()
            let library = MirrorLibrary(store: store, assets: assets)
            let source = assets.register(testImage(width: 300, height: 200))

            var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
            design.stickers = [photoSticker(source, at: NormalizedPoint(x: 0.5, y: 0.5))]
            library.save(design, name: "사진 거울", context: .createNew)

            let reopened = relaunch(store)
            let restored = try #require(reopened.mirrors.first?.stickers.first)
            #expect(restored.source.photoAssetID == source.photoAssetID)
            // 이미지도 같이 살아 있다 — hydrate가 미리 올려둔다.
            let fresh = PhotoStickerAssetStore()
            fresh.attach(MirrorStore(root: store.root))
            #expect(fresh.image(for: source.photoAssetID!) != nil)
            #expect(!reopened.referencedAssetIDs(.photoSticker).isEmpty)
        }
    }

    @Test("거울을 복제해도 사진 파일이 늘지 않는다")
    func duplicateDoesNotCopyAssetFile() throws {
        try withStore { store in
            let assets = PhotoStickerAssetStore()
            let library = MirrorLibrary(store: store, assets: assets)
            let source = assets.register(testImage(width: 200, height: 200))
            var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
            design.stickers = [photoSticker(source, at: NormalizedPoint(x: 0.5, y: 0.5))]
            library.save(design, name: "원본", context: .createNew)
            library.duplicate(library.mirrors[0])
            store.flush()

            let files = try FileManager().contentsOfDirectory(at: store.assetsDirectory(.photoSticker), includingPropertiesForKeys: nil)
            #expect(files.count == 1)
            #expect(library.mirrors[1].stickers[0].source.photoAssetID == source.photoAssetID)
            #expect(library.referencedAssetIDs(.photoSticker).count == 1)
        }
    }

    @Test("같은 사진을 쓰는 거울이 남아 있으면 파일을 지우지 않는다")
    func sharedAssetSurvivesOneDeletion() throws {
        try withStore { store in
            let assets = PhotoStickerAssetStore()
            let library = MirrorLibrary(store: store, assets: assets)
            let source = assets.register(testImage(width: 200, height: 200))
            var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
            design.stickers = [photoSticker(source, at: NormalizedPoint(x: 0.5, y: 0.5))]
            library.save(design, name: "하나", context: .createNew)
            library.duplicate(library.mirrors[0])

            library.delete(library.mirrors[0])
            store.flush()

            #expect(FileManager().fileExists(atPath: store.assetURL(source.photoAssetID!).path))
            #expect(relaunch(store).mirrors.count == 1)
        }
    }

    @Test("마지막으로 쓰던 거울을 지우면 사진 파일도 정리된다")
    func lastReferenceIsCollected() throws {
        try withStore { store in
            let assets = PhotoStickerAssetStore()
            let library = MirrorLibrary(store: store, assets: assets)
            let source = assets.register(testImage(width: 200, height: 200))
            var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
            design.stickers = [photoSticker(source, at: NormalizedPoint(x: 0.5, y: 0.5))]
            library.save(design, name: "하나", context: .createNew)
            store.flush()
            #expect(FileManager().fileExists(atPath: store.assetURL(source.photoAssetID!).path))

            library.delete(library.mirrors[0])
            store.flush()
            #expect(!FileManager().fileExists(atPath: store.assetURL(source.photoAssetID!).path))
        }
    }

    @Test("아무 거울도 안 쓰는 사진은 앱을 켤 때 정리된다")
    func orphanAssetIsCleanedAtLaunch() throws {
        try withStore { store in
            let assets = PhotoStickerAssetStore()
            assets.attach(store)
            let orphan = assets.register(testImage(width: 100, height: 100))   // 거울에 넣지 않는다
            store.flush()
            #expect(FileManager().fileExists(atPath: store.assetURL(orphan.photoAssetID!).path))

            let next = MirrorStore(root: store.root)
            _ = MirrorLibrary(store: next, assets: PhotoStickerAssetStore())
            next.flush()
            #expect(!FileManager().fileExists(atPath: store.assetURL(orphan.photoAssetID!).path))
        }
    }

    @Test("사진 파일이 사라져도 앱이 죽지 않는다")
    func missingAssetFileDoesNotCrash() throws {
        try withStore { store in
            let assets = PhotoStickerAssetStore()
            let library = MirrorLibrary(store: store, assets: assets)
            let source = assets.register(testImage(width: 200, height: 200))
            var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
            design.stickers = [photoSticker(source, at: NormalizedPoint(x: 0.5, y: 0.5))]
            library.save(design, name: "하나", context: .createNew)
            store.flush()

            try FileManager().removeItem(at: store.assetURL(source.photoAssetID!))

            let reopened = relaunch(store)
            #expect(reopened.mirrors.count == 1)                    // 거울은 그대로 남는다
            let fresh = PhotoStickerAssetStore()
            fresh.attach(MirrorStore(root: store.root))
            #expect(fresh.image(for: source.photoAssetID!) == nil)  // 조용히 없는 것으로 본다
            // 렌더러도 그냥 건너뛴다.
            let design2 = MirrorDesign(mirror: reopened.mirrors[0])
            #expect(MirrorCapture.compose(frame: nil, design: design2, size: CGSize(width: 200, height: 433)) != nil)
        }
    }

    // MARK: - Layers

    @Test("스티커와 텍스트가 섞인 순서가 그대로 저장된다")
    func mixedLayerOrderPersists() throws {
        try withStore { store in
            let assets = PhotoStickerAssetStore()
            let library = MirrorLibrary(store: store, assets: assets)
            var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
            let photo = assets.register(testImage(width: 200, height: 200))
            design.stickers = [
                photoSticker(.builtIn(.star), at: NormalizedPoint(x: 0.3, y: 0.3), zIndex: 0),
                photoSticker(photo, at: NormalizedPoint(x: 0.4, y: 0.4), zIndex: 2)
            ]
            var text = TextObject(text: "가운데", center: NormalizedPoint(x: 0.5, y: 0.5))
            text.zIndex = 1
            design.texts = [text]
            let expected = design.decorationLayers.map(\.id)
            library.save(design, name: "레이어", context: .createNew)

            let reopened = relaunch(store)
            let restored = MirrorDesign(mirror: reopened.mirrors[0])
            #expect(restored.decorationLayers.map(\.id) == expected)
            #expect(restored.decorationLayers.map(\.subtitle) == ["사진 스티커", "텍스트", "스티커"])
        }
    }

    @Test("Layers에서 바꾼 순서가 다시 켜도 그대로다")
    func reorderPersists() throws {
        try withStore { store in
            let assets = PhotoStickerAssetStore()
            let library = MirrorLibrary(store: store, assets: assets)
            var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
            design.stickers = [
                photoSticker(.builtIn(.star), at: NormalizedPoint(x: 0.3, y: 0.3), zIndex: 0),
                photoSticker(.builtIn(.moon), at: NormalizedPoint(x: 0.4, y: 0.4), zIndex: 1)
            ]
            var text = TextObject(text: "텍스트", center: NormalizedPoint(x: 0.5, y: 0.5))
            text.zIndex = 2
            design.texts = [text]

            // 맨 뒤에 있던 별을 맨 앞으로.
            var snapshot = design.snapshot
            var history = EditorHistory()
            let flipped = design.decorationLayers.reversed().map(\.id)
            history.apply(.reorderDecorations(frontToBack: flipped), to: &snapshot)
            design.snapshot = snapshot
            library.save(design, name: "순서", context: .createNew)

            let restored = MirrorDesign(mirror: relaunch(store).mirrors[0])
            #expect(restored.decorationLayers.map(\.id) == flipped)
            // zIndex도 정규화된 채로 저장됐다 — 켤 때 다시 매기지 않는다.
            #expect((restored.stickers.map(\.zIndex) + restored.texts.map(\.zIndex)).sorted() == [0, 1, 2])
        }
    }

    @Test("잠금 / 글꼴 / 색 같은 장식 속성이 그대로 저장된다")
    func decorationStylePersists() throws {
        try withStore { store in
            let assets = PhotoStickerAssetStore()
            let library = MirrorLibrary(store: store, assets: assets)
            var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
            let mirror = richMirror(photo: assets.register(testImage(width: 200, height: 200)))
            design.stickers = mirror.stickers
            design.texts = mirror.texts
            library.save(design, name: "속성", context: .createNew)

            let restored = MirrorDesign(mirror: relaunch(store).mirrors[0])
            #expect(restored.stickers[0].isLocked)
            #expect(isSameColor(restored.stickers[0].tintColor!, .purple))
            #expect(restored.texts[0].isLocked)
            #expect(restored.texts[0].style == .serif)
            #expect(restored.texts[0].alignment == .trailing)
            // 잠긴 장식도 목록에 그대로 나온다.
            #expect(restored.decorationLayers.count == 3)
            #expect(restored.decorationLayers.filter(\.isLocked).count == 2)
        }
    }

    // MARK: - Free Canvas

    @Test("카메라 영역에 놓은 그림 / 스티커 / 텍스트가 그대로 저장된다")
    func cameraAreaDecorationPersists() throws {
        try withStore { store in
            let center = NormalizedPoint(x: 0.5, y: 0.5)
            #expect(MirrorFrameInsets.standard.isInsideMirrorArea(center))

            let assets = PhotoStickerAssetStore()
            let library = MirrorLibrary(store: store, assets: assets)
            var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
            design.strokes = [stroke([center, NormalizedPoint(x: 0.52, y: 0.52)])]
            design.stickers = [photoSticker(assets.register(testImage(width: 200, height: 200)), at: center)]
            design.texts = [TextObject(text: "카메라 위", center: center)]
            library.save(design, name: "카메라", context: .createNew)

            let restored = MirrorDesign(mirror: relaunch(store).mirrors[0])
            #expect(restored.strokes[0].points[0].x == 0.5)
            #expect(restored.stickers[0].center.y == 0.5)
            #expect(restored.texts[0].center.x == 0.5)
        }
    }

    @Test("프레임과 카메라 경계를 걸친 장식도 잘리지 않고 저장된다")
    func boundaryCrossingDecorationPersists() throws {
        try withStore { store in
            let insets = MirrorFrameInsets.standard
            let onFrame = NormalizedPoint(x: 0.03, y: 0.5)
            let inCamera = NormalizedPoint(x: 0.3, y: 0.5)
            #expect(!insets.isInsideMirrorArea(onFrame))
            #expect(insets.isInsideMirrorArea(inCamera))

            let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore())
            var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
            design.strokes = [stroke([onFrame, inCamera])]
            design.stickers = [photoSticker(.builtIn(.heart), at: NormalizedPoint(x: insets.left, y: 0.5))]
            library.save(design, name: "경계", context: .createNew)

            let restored = MirrorDesign(mirror: relaunch(store).mirrors[0])
            #expect(restored.strokes[0].points.count == 2)
            #expect(restored.strokes[0].points[0].x == onFrame.x)
            #expect(restored.strokes[0].points[1].x == inCamera.x)
            #expect(abs(restored.stickers[0].center.x - insets.left) < 0.0001)
        }
    }

    // MARK: - 크기 / 속도

    @Test("거울 50장 규모에서 저장 / 읽기 시간과 파일 크기를 잰다")
    func syntheticLibrarySizeAndTime() throws {
        try withStore { store in
            let points = (0..<20).map { NormalizedPoint(x: Double($0) / 20, y: 0.5) }
            let mirrors = (0..<50).map { index -> MyMirror in
                var mirror = MyMirror(
                    id: "made-\(index)", name: "거울 \(index)", origin: .made,
                    style: BasicMirror.allCases[index % 8].style
                )
                mirror.strokes = (0..<100).map { _ in stroke(points) }
                mirror.stickers = (0..<50).map { z in
                    photoSticker(.builtIn(.heart), at: NormalizedPoint(x: 0.5, y: 0.5), zIndex: z)
                }
                mirror.texts = (0..<20).map { z in
                    var text = TextObject(text: "글자 \(z)", center: NormalizedPoint(x: 0.5, y: 0.5))
                    text.zIndex = 50 + z
                    return text
                }
                return mirror
            }
            let library = PersistedLibrary(currentMirrorID: mirrors[0].id, mirrors: mirrors)

            let clock = ContinuousClock()
            var data = Data()
            let encode = try clock.measure { data = try JSONEncoder().encode(library) }
            var decoded: PersistedLibrary?
            let decode = try clock.measure { decoded = try JSONDecoder().decode(PersistedLibrary.self, from: data) }

            store.save(library)
            store.flush()
            let onDisk = try Data(contentsOf: store.libraryURL).count

            print("""
                [persistence] 거울 50장 / 장당 획 100 · 스티커 50 · 텍스트 20
                  파일 크기: \(onDisk / 1024) KB
                  encode: \(encode)
                  decode: \(decode)
                """)

            #expect(decoded?.mirrors.count == 50)
            #expect(decoded?.mirrors[7].strokes.count == 100)
            #expect(onDisk > 0)
        }
    }
}
