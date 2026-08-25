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

    /// 상점에 보이는 최종 목록과 그림 파일. **순서까지** 여기 한 곳에 적어 둔다.
    ///
    /// 값은 담지 않는다 — 값의 authority는 backend이고, client와 맞는지는
    /// `BuiltInEconomyTests.clientAndBackendAgree`가 id 하나하나로 확인한다.
    /// 여기에 숫자를 또 적어 두면 아무도 읽지 않는 채로 낡아, 나중에 그것을
    /// 믿고 고치는 사람이 생긴다(실제로 18 · 24가 그대로 남아 있었다).
    static let expected: [(id: String, file: String)] = [
        ("art-pink-ribbon", "pink-ribbon"),
        ("art-ink-heart", "ink-heart"),
        ("art-cream-note", "cream-note"),
        ("art-lavender-star", "lavender-star"),
        ("art-sky-cloud", "sky-cloud"),
        ("art-mint-flower", "mint-flower"),
        ("art-gray-check", "gray-check"),
        ("art-red-point", "red-point"),
        ("art-lovely-bow", "lovely-bow"),
        ("art-love-letter", "love-letter"),
        ("art-cherry-love", "cherry-love"),
        ("art-angel-heart", "angel-heart"),
        ("art-my-diary", "my-diary"),
        ("art-checklist", "checklist"),
        ("art-scrapbook", "scrapbook"),
        ("art-cafe-note", "cafe-note"),
        ("art-y2k-star", "y2k-star"),
        ("art-cyber-love", "cyber-love"),
        ("art-flash-girl", "flash-girl"),
        ("art-retro-pop", "retro-pop"),
        ("art-birthday", "birthday"),
        ("art-summer-trip", "summer-trip"),
        ("art-spring-bloom", "spring-bloom"),
        ("art-winter-letter", "winter-letter"),
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

    @Test("가격 분포가 그대로다 — 갈래를 없애도 값은 잃지 않았다")
    func priceDistributionMatches() {
        func count(_ price: Int) -> Int {
            StoreCatalog.artworkTemplates.filter { $0.price == price }.count
        }
        // Phase B에서 손그림 24종에 값을 매겼다. **예전 등급을 그대로 옮긴 것이다** —
        // 0원이던 8종이 1조각, 4조각이던 16종이 3조각이 됐다. 어떤 그림이 더
        // 예뻐 보이는지로 새로 매기지 않았다.
        #expect(count(1) == 8)
        #expect(count(3) == 16)
        #expect(count(1) + count(3) == 24)
        // **가장 비싼 것이 3조각이다.** 상한이 올라가면 여기서 걸린다.
        #expect(StoreCatalog.samples.map(\.price).max() == 3)
    }

    @Test("각 템플릿이 이름 / 그림 / 가격을 갖는다")
    func templatesCarryRequiredInfo() throws {
        for template in StoreCatalog.artworkTemplates {
            #expect(!template.name.isEmpty)
            #expect(!template.creator.isEmpty)
            #expect(template.price >= 0)
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

    @Test("상점 필터는 가격 하나뿐이다 — 디자인 갈래가 없다")
    func onlyPriceFilterRemains() {
        #expect(StorePriceFilter.allCases.map(\.rawValue) == ["전체", "무료"])
        #expect(StorePriceFilter.default == .all)

        let all = StoreCatalog.samples.filter { StorePriceFilter.all.includes(price: $0.price) }
        #expect(all.count == StoreCatalog.samples.count)

        let free = StoreCatalog.samples.filter { StorePriceFilter.free.includes(price: $0.price) }
        #expect(free.allSatisfy { $0.price == 0 })
        #expect(!free.isEmpty)
        #expect(free.count < all.count)
    }

    @Test("디자인 갈래 이름이 코드에 남아 있지 않다")
    func designCategoriesAreGone() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "ggumirror")
        for path in ["Store/StoreCatalog.swift", "Store/StoreView.swift",
                     "Store/StickerStoreView.swift", "Store/TemplateDetailView.swift",
                     "Store/PublishMirrorView.swift", "Store/PublishStickerView.swift"] {
            // **주석은 걷어낸다.** "예전에는 갈래를 골랐다"는 설명 자체가 걸리면
            // 왜 없앴는지 적어 둘 수 없다.
            let source = codeWithoutComments(
                try String(contentsOf: root.appending(path: path), encoding: .utf8)
            )
            // **분류 장치**가 사라졌는지 본다. 그림 이름("Y2K 스타")과 에셋 폴더
            // 경로("StoreTemplates/Y2K")는 사용자가 고르는 분류가 아니라 그대로 둔다.
            for gone in ["StoreCategory", "StoreTag", "TagFilter",
                         "ribbonHeart", "highlightTags", "contentGroups", "temporaryPrice",
                         ".matches(", "리본 & 하트"] {
                #expect(!source.contains(gone), "\(path)에 \(gone)이 남아 있다")
            }
        }
    }

    @Test("무료는 0, 유료는 값이 있고 표시가 갈린다")
    func freeAndPaidAreDistinguishable() throws {
        // **손그림 중에 무료는 하나도 없다.** 예전에 0원이던 것까지 1조각이 됐다 —
        // 하나라도 0으로 돌아가면 서버는 값을 받고 화면은 공짜라고 말한다.
        #expect(StoreCatalog.artworkTemplates.allSatisfy { !$0.isFree })
        let ribbon = try template("art-pink-ribbon")
        #expect(ribbon.price == 1)

        for id in ["art-my-diary", "art-y2k-star"] {
            let paid = try template(id)
            #expect(!paid.isFree)
            #expect(paid.price == 3)
            #expect(!StorePriceFilter.free.includes(price: paid.price))
        }
        // 무료 필터에 걸리는 것은 모두 0 조각이다.
        #expect(StoreCatalog.samples.filter { StorePriceFilter.free.includes(price: $0.price) }
            .allSatisfy { $0.price == 0 })
        // 무료로 남는 것은 **단색 기본 거울 8종뿐**이다. 앱이 기본값으로 쓰는
        // 거울이라 값을 매기면 처음 켠 사람이 거울을 못 쓴다.
        let free = StoreCatalog.samples.filter { $0.isFree }
        #expect(free.count == 8)
        #expect(free.allSatisfy { $0.isBasic })
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
