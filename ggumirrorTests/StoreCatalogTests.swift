//
//  StoreCatalogTests.swift
//  ggumirrorTests
//
//  상점에 실제 손그림 템플릿 3장이 연결됐는지.
//  PNG가 번들에 있고, 카테고리로 갈라지고, 받으면 내 거울에 그림까지 따라오는지 본다.
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

    @Test("손그림 템플릿 3장이 고정 id로 상점에 있다")
    func artworkTemplatesAreListed() throws {
        let ids = StoreCatalog.artworkTemplates.map(\.id)
        #expect(ids == ["art-pink-ribbon", "art-my-diary", "art-y2k-star"])
        // 상점 목록의 맨 앞이다 — 이 3장이 스타일 기준이다.
        #expect(StoreCatalog.samples.prefix(3).map(\.id) == ids)
        // id는 전체에서 겹치지 않는다.
        #expect(Set(StoreCatalog.samples.map(\.id)).count == StoreCatalog.samples.count)
    }

    @Test("각 템플릿이 이름 / 카테고리 / 그림 / 가격을 갖는다")
    func templatesCarryRequiredInfo() throws {
        for template in StoreCatalog.artworkTemplates {
            #expect(!template.name.isEmpty)
            #expect(!template.creator.isEmpty)
            #expect(!template.categories.isEmpty || template.isFree)
            #expect(template.price >= 0)
            let artwork = try #require(template.artwork)
            #expect(!artwork.fileName.isEmpty)
            #expect(artwork.subdirectory.hasPrefix("StoreTemplates/"))
        }
    }

    @Test("그림 참조 id는 템플릿마다 고정이고 서로 다르다")
    func artworkAssetIDsAreStableAndUnique() {
        let ids = StoreCatalog.artworkTemplates.compactMap { $0.artwork?.assetID }
        #expect(ids.count == 3)
        #expect(Set(ids).count == 3)
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
    }

    @Test("상점 그림도 카메라 영역이 비어 있다")
    func artworkKeepsCameraAreaClear() throws {
        for template in StoreCatalog.artworkTemplates {
            let artwork = try #require(StoreArtworkLibrary.artwork(for: template))
            let image = try #require(ImportedArtworkAssetStore.shared.image(for: artwork.assetID))
            // 가운데는 비고, 프레임에는 그림이 있다.
            #expect(pixel(image, at: NormalizedPoint(x: 0.5, y: 0.5)).alpha == 0)
            #expect(pixel(image, at: NormalizedPoint(x: 0.05, y: 0.5)).alpha > 200)
            #expect(pixel(image, at: NormalizedPoint(x: 0.5, y: 0.03)).alpha > 200)
        }
    }

    // MARK: - 카테고리 / 가격

    @Test("무료 / 다이어리 / Y2K 카테고리로 갈라진다")
    func categoriesSplitTheThreeTemplates() throws {
        func ids(_ category: StoreCategory) -> [String] {
            StoreCatalog.samples.filter { $0.matches(category) }.map(\.id)
        }
        #expect(ids(.free).contains("art-pink-ribbon"))
        #expect(!ids(.free).contains("art-my-diary"))       // 유료
        #expect(!ids(.free).contains("art-y2k-star"))

        #expect(ids(.diary).contains("art-my-diary"))
        #expect(!ids(.diary).contains("art-y2k-star"))

        #expect(ids(.y2k).contains("art-y2k-star"))
        #expect(!ids(.y2k).contains("art-my-diary"))

        #expect(ids(.all).count == StoreCatalog.samples.count)
        // 세 카테고리 모두 상점 필터에 실제로 노출된다.
        for category in [StoreCategory.free, .diary, .y2k] {
            #expect(StoreCategory.allCases.contains(category))
            #expect(!ids(category).isEmpty)
        }
    }

    @Test("무료는 0, 유료는 값이 있고 표시가 갈린다")
    func freeAndPaidAreDistinguishable() throws {
        let free = try template("art-pink-ribbon")
        #expect(free.isFree)
        #expect(free.price == 0)

        for id in ["art-my-diary", "art-y2k-star"] {
            let paid = try template(id)
            #expect(!paid.isFree)
            #expect(paid.price > 0)
            #expect(paid.matches(.free) == false)
        }
        // 무료 필터는 값이 0인 것만 모은다.
        #expect(StoreCatalog.samples.filter { $0.matches(.free) }.allSatisfy { $0.price == 0 })
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
            let mirror = library.acquire(template)

            #expect(library.mirrors.count == 1)
            #expect(mirror.id == template.id)
            #expect(mirror.importedArtworks.count == 1)
            #expect(mirror.importedArtworks[0].assetID == template.artwork?.assetID)
            // 받은 거울은 사용자 제작 슬롯을 쓰지 않는다 — 기존 정책 그대로.
            #expect(library.createdCount == 0)
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
            let capacityBefore = library.createdCapacity

            library.acquire(try template("art-my-diary"))

            #expect(library.currentID == currentBefore)     // 받는다고 바로 적용되지 않는다
            #expect(library.createdCapacity == capacityBefore)
            #expect(library.createdCount == 0)
            #expect(library.needsName(for: .editCurrent) == false)
        }
    }
}
