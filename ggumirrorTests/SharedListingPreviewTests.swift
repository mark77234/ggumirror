//
//  SharedListingPreviewTests.swift
//  ggumirrorTests
//
//  I-3. 같은 상품은 어느 화면에서든 같게 보인다.
//

import Testing
import Foundation
import SwiftUI
@testable import ggumirror

private func listingSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

/// 상품을 보여 주는 화면 전부. **직접 그리는 코드가 하나도 없어야 한다.**
private let surfaces = [
    "ggumirror/Store/MarketplaceGallery.swift",
    "ggumirror/Store/MyListingsSection.swift",
    "ggumirror/Store/MySalesSection.swift",
    "ggumirror/Admin/AdminStoreView.swift",
    "ggumirror/Store/MarketplaceListingCard.swift",
]

/// 격자에 상품을 늘어놓는 세 화면. **같은 카드를 쓴다.**
///
/// 예전에는 셋이 각자 카드를 갖고 있었다 — 상점은 격자 카드, 내 판매는 가로 줄,
/// 상점 관리는 작은 썸네일 표. 그림 그리는 규칙만 공유하고 그것을 감싼 카드는
/// 셋이라, 규칙이 갈라질 자리가 셋이었다.
private let gridSurfaces = [
    "ggumirror/Store/MarketplaceGallery.swift",
    "ggumirror/Store/MySalesSection.swift",
    "ggumirror/Admin/AdminStoreView.swift",
]

@Suite("상품 미리보기는 한 규칙이다")
struct SharedListingPreviewTests {

    @Test("모든 화면이 공용 view를 쓴다")
    func everySurfaceUsesTheSharedPreview() throws {
        // 격자 화면은 공용 **카드**를 쓰고, 그 카드가 공용 preview를 쓴다.
        for path in gridSurfaces {
            #expect(try listingSource(path).contains("MarketplaceListingCard("), "\(path)")
        }
        let card = try listingSource("ggumirror/Store/MarketplaceListingCard.swift")
        #expect(card.contains("MarketplaceListingPreview("))
        // 카드를 쓰지 않는 나머지 화면도 공용 preview를 지난다.
        #expect(try listingSource("ggumirror/Store/MyListingsSection.swift")
            .contains("MarketplaceListingPreview("))
    }

    @Test("세 화면이 같은 카드 구현을 쓴다")
    func theThreeScreensShareOneCard() throws {
        for path in gridSurfaces {
            let code = try listingSource(path)
            // 자기 카드를 다시 만들지 않는다.
            #expect(!code.contains("private var stickerCard"), "\(path)")
            #expect(!code.contains("StoreMirrorCard(model:"), "\(path)")
        }
        // 카드는 종류를 스스로 판정하지 않고 공용 규칙에게 묻는다.
        let card = try listingSource("ggumirror/Store/StoreMirrorCard.swift")
        #expect(card.contains("ListingPreviewStyle.aspectRatio(for: model.contentType)"))
    }

    @Test("세 화면이 같은 격자를 쓴다")
    func theThreeScreensShareOneGrid() throws {
        for path in gridSurfaces + ["ggumirror/Store/StoreView.swift"] {
            let code = try listingSource(path)
            #expect(code.contains("GalleryLayout.columns(for: dynamicTypeSize)"), "\(path)")
            #expect(code.contains("GalleryLayout.spacing"), "\(path)")
            // 열 수와 간격을 손으로 다시 적지 않는다.
            #expect(!code.contains("GridItem("), "\(path)")
        }
    }

    @Test("화면이 직접 그리지 않는다")
    func noSurfaceDecodesItsOwnImage() throws {
        // 손으로 그리기 시작하면 규칙이 갈라진다 — 실제로 그렇게 갈라져 있었다.
        for path in surfaces {
            #expect(!(try listingSource(path).contains("UIImage(data:")), "\(path)")
        }
    }

    @Test("종류 판정을 화면이 하지 않는다")
    func contentModeIsNeverHardcoded() throws {
        // 관리자와 `내 상품`이 `.fill`을 직접 적어 두고 종류를 보지 않아서
        // 스티커가 거울 모양 칸에 꽉 채워져 잘렸다.
        for path in surfaces {
            let code = try listingSource(path)
            #expect(!code.contains("scaledToFill"), "\(path)")
            #expect(!code.contains("contentMode: .fill"), "\(path)")
        }
    }

    @Test("판정 authority는 ListingPreviewStyle 하나다")
    func styleOwnsTheRules() throws {
        let preview = try listingSource("ggumirror/Store/MarketplaceListingPreview.swift")
        #expect(preview.contains("ListingPreviewStyle.aspectRatio(for: contentType)"))
        #expect(preview.contains("ListingPreviewStyle.contentMode(for: contentType)"))
        #expect(preview.contains("ListingPreviewStyle.showsTransparency(for: contentType)"))
    }

    @Test("거울과 스티커 규칙이 실제로 다르다")
    func mirrorAndStickerDiffer() {
        #expect(ListingPreviewStyle.contentMode(for: "mirror") == .fill)
        // 스티커를 자르면 스티커가 아니다.
        #expect(ListingPreviewStyle.contentMode(for: "sticker") == .fit)
        #expect(ListingPreviewStyle.aspectRatio(for: "sticker") == 1)
        #expect(ListingPreviewStyle.aspectRatio(for: "mirror") == MirrorStyle.aspectRatio)
        // 투명한 것이 정상인 쪽에만 바탕을 깐다.
        #expect(ListingPreviewStyle.showsTransparency(for: "sticker"))
        #expect(!ListingPreviewStyle.showsTransparency(for: "mirror"))
    }

    @Test("공용 view가 관리 권한을 모른다")
    func previewKnowsNothingAboutModeration() throws {
        let preview = try listingSource("ggumirror/Store/MarketplaceListingPreview.swift")
        for admin in ["takedown", "restore", "moderation", "AdminListing", "isRemoved"] {
            #expect(!preview.contains(admin), "카드가 \(admin)를 안다")
        }
    }

    @Test("격자 geometry가 상세로 새지 않는다")
    func detailDoesNotInheritGridGeometry() throws {
        // I-5가 그렇게 생겼다 — 격자용 카드를 상세 hero로 그대로 쓰면
        // 맞춘 그림이 왼쪽에 붙는다. 맞춘 뒤 가운데로 놓는 규칙을 유지한다.
        let card = try listingSource("ggumirror/Store/StoreMirrorCard.swift")
        #expect(card.contains("frame(maxWidth: .infinity, alignment: .center)"))
    }

    @Test("공개 노출 판정을 화면으로 옮기지 않았다")
    func filteringStaysOnTheServer() throws {
        let preview = try listingSource("ggumirror/Store/MarketplaceListingPreview.swift")
        // 무엇을 보여 줄지는 서버가 정한다(Phase E `_is_public`).
        for banned in ["moderationStatus", "isPublic", "status ==", "filter"] {
            #expect(!preview.contains(banned), "표현 계층이 \(banned)로 거른다")
        }
        let store = try listingSource("ggumirror/Store/MarketplaceStore.swift")
        #expect(store.contains("listings = try await backend.listings("))
    }

    @Test("DTO를 새로 복사하지 않았다")
    func noDuplicateListingModel() throws {
        let preview = try listingSource("ggumirror/Store/MarketplaceListingPreview.swift")
        // 기존 model을 그대로 쓴다 — 종류 문자열과 바이트만 받는다.
        #expect(preview.contains("let contentType: String"))
        #expect(!preview.contains("struct MarketplaceListingModel"))
        #expect(!preview.contains("struct ListingDTO"))
    }
}
