//
//  StoreCatalogTests.swift
//  ggumirrorTests
//
//  상점에 실제 손그림 템플릿 24장이 연결됐는지.
//  PNG가 번들에 있고, 갈래로 갈라지고, 받으면 내 거울에 그림까지 따라오는지 본다.
//  placeholder(SF Symbol 낙서 샘플)가 한 장도 남지 않았는지도 여기서 막는다.
//

import Testing
import SwiftUI
import UIKit
@testable import ggumirror

@MainActor
struct StoreCatalogTests {

    // MARK: - 도구

    private func withStore(_ body: (MirrorStore) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = MirrorStore(root: root)
        defer {
            store.flush()
            try? FileManager().removeItem(at: root)
        }
        try body(store)
    }

    private func library(_ store: MirrorStore) -> MirrorLibrary {
        MirrorLibrary(store: store, assets: PhotoStickerAssetStore(), artworks: .shared)
    }

    private func template(_ id: String) throws -> MirrorTemplate {
        try #require(StoreCatalog.samples.first { $0.id == id })
    }

    private func pixel(_ image: CGImage, at point: NormalizedPoint) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let x = min(max(Int(point.x * Double(image.width)), 0), image.width - 1)
        let y = min(max(Int(point.y * Double(image.height)), 0), image.height - 1)
        context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y),
                                       width: image.width, height: image.height))
        return (data[0], data[1], data[2], data[3])
    }

    private func render(_ view: some View, size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.cgImage
    }

    // MARK: - 목록

    /// 상점에 보이는 최종 목록. 순서와 갈래까지 여기 한 곳에 적어 둔다.
    static let expected: [(id: String, file: String, category: StoreCategory)] = [
        ("art-pink-ribbon", "pink-ribbon", .free),
        ("art-ink-heart", "ink-heart", .free),
        ("art-cream-note", "cream-note", .free),
        ("art-lavender-star", "lavender-star", .free),
        ("art-sky-cloud", "sky-cloud", .free),
        ("art-mint-flower", "mint-flower", .free),
        ("art-gray-check", "gray-check", .free),
        ("art-red-point", "red-point", .free),
        ("art-lovely-bow", "lovely-bow", .ribbonHeart),
        ("art-love-letter", "love-letter", .ribbonHeart),
        ("art-cherry-love", "cherry-love", .ribbonHeart),
        ("art-angel-heart", "angel-heart", .ribbonHeart),
        ("art-my-diary", "my-diary", .diary),
        ("art-checklist", "checklist", .diary),
        ("art-scrapbook", "scrapbook", .diary),
        ("art-cafe-note", "cafe-note", .diary),
        ("art-y2k-star", "y2k-star", .y2k),
        ("art-cyber-love", "cyber-love", .y2k),
        ("art-flash-girl", "flash-girl", .y2k),
        ("art-retro-pop", "retro-pop", .y2k),
        ("art-birthday", "birthday", .moments),
        ("art-summer-trip", "summer-trip", .moments),
        ("art-spring-bloom", "spring-bloom", .moments),
        ("art-winter-letter", "winter-letter", .moments),
    ]

    @Test("손그림 템플릿이 정확히 24장이고 고정 id를 갖는다")
    func artworkTemplatesAreListed() throws {
        #expect(StoreCatalog.artworkTemplates.count == 24)
        #expect(StoreCatalog.artworkTemplates.map(\.id) == Self.expected.map(\.id))
        // 상점 목록의 맨 앞이다 — 단색 기본보다 먼저 보인다.
        #expect(StoreCatalog.samples.prefix(24).map(\.id) == Self.expected.map(\.id))
        // id는 전체에서 겹치지 않는다.
        #expect(Set(StoreCatalog.samples.map(\.id)).count == StoreCatalog.samples.count)
    }

    @Test("이미 연결됐던 3장은 id를 그대로 유지한다")
    func originalThreeKeepTheirIdentity() throws {
        for (id, assetID) in [
            ("art-pink-ribbon", "A0000001-0000-4000-A000-000000000001"),
            ("art-my-diary", "A0000002-0000-4000-A000-000000000002"),
            ("art-y2k-star", "A0000003-0000-4000-A000-000000000003"),
        ] {
            let template = try template(id)
            #expect(template.artwork?.assetID == UUID(uuidString: assetID))
        }
    }

    @Test("placeholder 템플릿이 한 장도 남아 있지 않다")
    func noPlaceholdersRemain() {
        // 옛 개발용 샘플은 SF Symbol 낙서(style.doodles)로 만들어져 있었다.
        for template in StoreCatalog.samples {
            #expect(template.style.doodles.isEmpty, "\(template.id)에 낙서 placeholder가 남아 있다")
            #expect(!["bunny-sketch", "star-scribble", "ribbon-diary"].contains(template.id))
        }
        // 아트워크가 아닌 것은 공식 단색 기본뿐이다.
        for template in StoreCatalog.samples where template.artwork == nil {
            #expect(template.isBasic, "\(template.id)는 그림도 기본도 아니다")
        }
    }

    @Test("갈래별 개수가 8 / 4 / 4 / 4 / 4다")
    func categoryCountsMatch() {
        func count(_ category: StoreCategory) -> Int {
            StoreCatalog.artworkTemplates.filter { $0.category == category }.count
        }
        #expect(count(.free) == 8)
        #expect(count(.ribbonHeart) == 4)
        #expect(count(.diary) == 4)
        #expect(count(.y2k) == 4)
        #expect(count(.moments) == 4)
        // 갈래는 정확히 하나씩만 갖는다 — 합이 곧 전체다.
        #expect(count(.free) + count(.ribbonHeart) + count(.diary) + count(.y2k) + count(.moments) == 24)
    }

    @Test("각 템플릿이 이름 / 카테고리 / 그림 / 가격을 갖는다")
    func templatesCarryRequiredInfo() throws {
        for template in StoreCatalog.artworkTemplates {
            #expect(!template.name.isEmpty)
            #expect(!template.creator.isEmpty)
            #expect(StoreCategory.contentGroups.contains(template.category))
            #expect(template.price >= 0)
            #expect(template.price == template.category.temporaryPrice)
            let artwork = try #require(template.artwork)
            #expect(!artwork.fileName.isEmpty)
            #expect(artwork.subdirectory.hasPrefix("StoreTemplates/"))
        }
    }

    @Test("그림 참조 id는 템플릿마다 고정이고 서로 다르다")
    func artworkAssetIDsAreStableAndUnique() {
        let ids = StoreCatalog.artworkTemplates.compactMap { $0.artwork?.assetID }
        #expect(ids.count == 24)
        #expect(Set(ids).count == 24)
        // 두 번 읽어도 같은 값 — 볼 때마다 새 파일이 생기지 않는다.
        #expect(StoreCatalog.artworkTemplates.compactMap { $0.artwork?.assetID } == ids)
    }

    @Test("PNG가 앱 번들에 들어 있고 1080 × 2340이다")
    func artworkFilesShipInTheBundle() throws {
        for template in StoreCatalog.artworkTemplates {
            let resource = try #require(template.artwork)
            #expect(resource.url != nil, "\(resource.fileName).png가 번들에 없다")
            let image = try #require(resource.loadImage(), "\(resource.fileName).png를 읽지 못했다")
            #expect(image.width == 1080)
            #expect(image.height == 2340)
        }
        // 파일 이름도 의도한 그림과 정확히 맞는다.
        #expect(StoreCatalog.artworkTemplates.compactMap { $0.artwork?.fileName } == Self.expected.map(\.file))
    }

    /// 그림 한 장의 alpha 채널만 한 번에 읽는다.
    /// 점 하나마다 다시 그리면 1080 × 2340짜리 24장에서 감당이 안 된다.
    private func alphaMap(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height)
        let context = CGContext(
            data: &data, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    @Test("상점 그림 24장 모두 카메라 영역이 비어 있고 프레임에는 그림이 있다")
    func artworkKeepsCameraAreaClear() throws {
        let insets = MirrorFrameInsets.standard
        for template in StoreCatalog.artworkTemplates {
            let artwork = try #require(StoreArtworkLibrary.artwork(for: template))
            let image = try #require(ImportedArtworkAssetStore.shared.image(for: artwork.assetID))
            let alpha = alphaMap(image)
            let (w, h) = (image.width, image.height)

            let left = Int(insets.left * Double(w))
            let right = w - Int(insets.right * Double(w))
            let top = Int(insets.top * Double(h))
            let bottom = h - Int(insets.bottom * Double(h))
            // 둥근 모서리는 판정에서 뺀다 — 반경 안쪽 사각형만 본다.
            let margin = Int(MirrorGeometry.innerCornerRadius) + 2

            var insideCamera = 0
            var paintedFrame = 0
            for y in 0..<h {
                for x in 0..<w where alpha[y * w + x] > 10 {
                    if x >= left + margin && x < right - margin
                        && y >= top + margin && y < bottom - margin {
                        insideCamera += 1
                    } else if x < left || x >= right || y < top || y >= bottom {
                        paintedFrame += 1
                    }
                }
            }

            #expect(insideCamera == 0, "\(template.id): 카메라 영역에 \(insideCamera)픽셀이 남아 있다")
            // 테두리와 장식이 실제로 그려져 있다. 얼굴이 주인공이라 덮는 비율은 작지만 0은 아니다.
            #expect(paintedFrame > 15_000, "\(template.id): 프레임이 거의 비어 있다 (\(paintedFrame))")
        }
    }

    // MARK: - 카테고리 / 가격

    @Test("다섯 갈래가 상점 필터에서 실제로 갈라진다")
    func categoriesSplitTheCatalog() throws {
        func ids(_ category: StoreCategory) -> [String] {
            StoreCatalog.samples.filter { $0.matches(category) }.map(\.id)
        }
        for (id, _, category) in Self.expected {
            #expect(ids(category).contains(id), "\(id)가 \(category.rawValue)에 없다")
            // 다른 갈래에는 들어가지 않는다.
            for other in StoreCategory.contentGroups where other != category {
                #expect(!ids(other).contains(id), "\(id)가 \(other.rawValue)에도 들어갔다")
            }
        }
        #expect(ids(.all).count == StoreCatalog.samples.count)
        for category in StoreCategory.contentGroups {
            #expect(StoreCategory.allCases.contains(category))
            #expect(!ids(category).isEmpty)
        }
    }

    @Test("추천 / 인기 / 신규는 갈래와 섞이지 않는 별도 꼬리표다")
    func highlightsAreSeparateFromCategories() {
        for template in StoreCatalog.samples {
            // 꼬리표 자리에 갈래가 들어가지 않는다.
            #expect(template.highlights.allSatisfy(StoreCategory.highlightTags.contains))
        }
        for tag in StoreCategory.highlightTags {
            let tagged = StoreCatalog.samples.filter { $0.matches(tag) }
            #expect(!tagged.isEmpty)
            #expect(tagged.allSatisfy { $0.highlights.contains(tag) })
        }
    }

    @Test("무료는 0, 유료는 값이 있고 표시가 갈린다")
    func freeAndPaidAreDistinguishable() throws {
        let free = try template("art-pink-ribbon")
        #expect(free.isFree)
        #expect(free.price == 0)

        #expect(StoreCatalog.artworkTemplates.filter(\.isFree).count == 8)

        for id in ["art-my-diary", "art-y2k-star"] {
            let paid = try template(id)
            #expect(!paid.isFree)
            #expect(paid.price > 0)
            #expect(paid.matches(.free) == false)
        }
        // 무료 갈래는 모두 0 조각이다.
        #expect(StoreCatalog.samples.filter { $0.matches(.free) }.allSatisfy { $0.price == 0 })
        // 기존 두 장의 값은 그대로 유지된다.
        #expect(try template("art-my-diary").price == 18)
        #expect(try template("art-y2k-star").price == 24)
    }

    // MARK: - 미리보기

    @Test("목록 썸네일이 9 : 19.5 비율을 유지한다 — 찌그러지지 않는다")
    func previewKeepsAspectRatio() throws {
        // 정사각형 칸에 넣어도 거울은 원래 비율대로 들어간다.
        let template = try template("art-pink-ribbon")
        let image = try #require(render(MirrorPreview(template: template), size: CGSize(width: 400, height: 400)))

        var minX = image.width, maxX = 0, minY = image.height, maxY = 0
        for y in stride(from: 0, to: image.height, by: 2) {
            for x in stride(from: 0, to: image.width, by: 2) where pixel(
                image, at: NormalizedPoint(x: Double(x) / Double(image.width),
                                           y: Double(y) / Double(image.height))
            ).alpha > 40 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        let ratio = Double(maxX - minX) / Double(maxY - minY)
        #expect(abs(ratio - MirrorCanvas.size.width / MirrorCanvas.size.height) < 0.03,
                "그려진 비율 \(ratio)")
    }

    @Test("목록과 상세가 같은 그림을 보여준다")
    func listAndDetailShowTheArtwork() throws {
        let template = try template("art-y2k-star")
        for size in [CGSize(width: 200, height: 433), CGSize(width: 420, height: 910)] {
            let image = try #require(render(MirrorPreview(template: template), size: size))
            // 프레임 자리에 실제 그림이 있고
            let frame = pixel(image, at: NormalizedPoint(x: 0.05, y: 0.5))
            #expect(frame.alpha > 200)
            #expect(frame.blue > frame.red)      // Y2K 템플릿은 보라·블루 계열
        }
    }

    @Test("단색 기본 템플릿은 그림 없이도 그대로 보인다")
    func basicTemplatesStillRender() throws {
        let basic = try #require(StoreCatalog.basics.first)
        #expect(basic.artwork == nil)
        #expect(StoreArtworkLibrary.artworks(for: basic).isEmpty)
        let image = try #require(render(MirrorPreview(template: basic), size: CGSize(width: 200, height: 433)))
        #expect(pixel(image, at: NormalizedPoint(x: 0.05, y: 0.5)).alpha > 200)
    }

    @Test("같은 템플릿을 여러 번 그려도 그림은 한 장만 만들어진다")
    func artworkIsCachedPerTemplate() throws {
        let template = try template("art-my-diary")
        let first = try #require(StoreArtworkLibrary.artwork(for: template))
        let before = ImportedArtworkAssetStore.shared.count
        for _ in 0..<5 { _ = StoreArtworkLibrary.artwork(for: template) }

        #expect(StoreArtworkLibrary.artwork(for: template)?.assetID == first.assetID)
        #expect(ImportedArtworkAssetStore.shared.count == before)
        #expect(first.assetID == template.artwork?.assetID)
    }

    // MARK: - 받기

    @Test("무료 손그림 템플릿을 받으면 그림까지 내 거울에 담긴다")
    func acquiringFreeArtworkKeepsTheArtwork() throws {
        try withStore { store in
            let library = library(store)
            let template = try template("art-pink-ribbon")
            let mirror = try #require(library.acquire(template))

            #expect(library.mirrors.count == 1)
            #expect(mirror.id == template.id)
            #expect(mirror.importedArtworks.count == 1)
            #expect(mirror.importedArtworks[0].assetID == template.artwork?.assetID)
            // 받은 거울은 "내가 만든 것"으로 세지 않는다. 보관 한도는 별개로 전부를 센다.
            #expect(library.createdCount == 0)
            #expect(library.storedCount == 1)
            #expect(mirror.origin == .purchased)
        }
    }

    @Test("받은 템플릿은 앱을 다시 켜도 그림까지 남는다")
    func acquiredArtworkSurvivesRelaunch() throws {
        try withStore { store in
            let template = try template("art-y2k-star")
            library(store).acquire(template)
            store.flush()

            let assetID = try #require(template.artwork?.assetID)
            #expect(FileManager().fileExists(
                atPath: store.assetURL(assetID, kind: .importedArtwork).path
            ), "받은 그림이 파일로 남아야 한다")

            let reopened = MirrorLibrary(
                store: MirrorStore(root: store.root),
                assets: PhotoStickerAssetStore(),
                artworks: ImportedArtworkAssetStore()   // 메모리 캐시가 빈 새 보관소
            )
            let restored = try #require(reopened.mirrors.first)
            #expect(restored.importedArtworks.map(\.assetID) == [assetID])
            // 디스크에서 다시 읽혀 실제로 그려진다.
            let image = try #require(render(MirrorPreview(mirror: restored),
                                            size: CGSize(width: 200, height: 433)))
            #expect(pixel(image, at: NormalizedPoint(x: 0.05, y: 0.5)).alpha > 200)
        }
    }

    @Test("같은 템플릿을 두 번 받아도 거울은 하나다")
    func acquiringTwiceKeepsOneMirror() throws {
        try withStore { store in
            let library = library(store)
            let template = try template("art-pink-ribbon")
            library.acquire(template)
            library.acquire(template)

            #expect(library.mirrors.count == 1)
            #expect(library.referencedAssetIDs(.importedArtwork).count == 1)
        }
    }

    @Test("상점을 구경하는 것만으로는 파일이 생기지 않는다")
    func browsingDoesNotWriteFiles() throws {
        try withStore { store in
            _ = library(store)                       // 앱 시작
            for template in StoreCatalog.artworkTemplates {
                _ = StoreArtworkLibrary.artworks(for: template)   // 목록 그리기
            }
            store.flush()

            let directory = store.assetsDirectory(.importedArtwork)
            let files = (try? FileManager().contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            #expect(files.isEmpty, "받기 전에는 디스크에 쓰지 않는다")
        }
    }

    @Test("템플릿을 받아도 현재 거울 / 저장 정책은 그대로다")
    func acquiringDoesNotTouchSavePolicy() throws {
        try withStore { store in
            let library = library(store)
            let currentBefore = library.currentID
            let capacityBefore = library.mirrorCapacity

            library.acquire(try template("art-my-diary"))

            #expect(library.currentID == currentBefore)     // 받는다고 바로 적용되지 않는다
            #expect(library.mirrorCapacity == capacityBefore)
            #expect(library.createdCount == 0)
            #expect(library.needsName(for: .editCurrent) == false)
        }
    }
}
