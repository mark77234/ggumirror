//
//  MarketplaceGridUnificationTests.swift
//  ggumirrorTests
//
//  **같은 상품을 세 화면에서 봐도 같은 카드다.**
//
//  `ListingPreviewStyle`(그림 그리는 규칙)은 이미 셋이 공유하고 있었다. 갈라져 있던
//  것은 **그 그림을 감싼 카드와 격자**였다 — 상점은 2열 카드, 내 판매는 가로로 꽉 찬 줄,
//  상점 관리는 작은 썸네일 표. 판매자와 운영자는 사용자가 보는 것과 다른 화면을 보고
//  판단했고, 규칙이 갈라질 자리가 셋이었다.
//
//  여기서 고정하는 것:
//    1. 세 화면이 같은 카드 · 같은 격자를 쓴다
//    2. 종류 판정은 여전히 `ListingPreviewStyle` 하나가 한다
//    3. 관리 · 운영 기능이 자리를 옮겼을 뿐 하나도 사라지지 않았다
//

import Testing
import Foundation
import SwiftUI
@testable import ggumirror

private func gridSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

private let storePath = "ggumirror/Store/StoreView.swift"
private let galleryPath = "ggumirror/Store/MarketplaceGallery.swift"
private let salesPath = "ggumirror/Store/MySalesSection.swift"
private let adminPath = "ggumirror/Admin/AdminStoreView.swift"
private let cardPath = "ggumirror/Store/MarketplaceListingCard.swift"

// MARK: - 격자

@Suite("세 화면이 같은 2열 격자다")
struct MarketplaceGridLayoutTests {

    @Test("2열이 기본이다")
    func twoColumnsByDefault() {
        for size in [DynamicTypeSize.small, .large, .xxxLarge] {
            #expect(GalleryLayout.columns(for: size).count == 2, "\(size)")
        }
    }

    @Test("큰 글씨에서는 1열로 내려간다")
    func accessibilitySizesFallBackToOne() {
        for size in [DynamicTypeSize.accessibility1, .accessibility5] {
            #expect(GalleryLayout.columns(for: size).count == 1, "\(size)")
        }
    }

    @Test("상점 · 내 판매 · 상점 관리가 같은 격자를 부른다")
    func everyScreenAsksTheSameAuthority() throws {
        for path in [storePath, galleryPath, salesPath, adminPath] {
            let code = try gridSource(path)
            #expect(code.contains("LazyVGrid("), "\(path): 격자가 없다")
            #expect(code.contains("GalleryLayout.columns(for: dynamicTypeSize)"), "\(path)")
            #expect(code.contains("GalleryLayout.spacing"), "\(path)")
            #expect(code.contains("GalleryLayout.horizontalPadding"), "\(path)")
        }
    }

    @Test("열 수와 간격을 화면이 다시 적지 않는다")
    func nobodyCopiesTheGridValues() throws {
        for path in [storePath, galleryPath, salesPath, adminPath] {
            let code = try gridSource(path)
            #expect(!code.contains("GridItem("), "\(path): 격자 정의를 복사했다")
            #expect(!code.contains("spacing: 18"), "\(path): 간격을 복사했다")
        }
        // 정의는 한 곳에만 있다.
        #expect(try gridSource(cardPath).contains("GridItem("))
    }

    @Test("관리 화면이 표로 돌아가지 않는다")
    func managementScreensAreNotLists() throws {
        for path in [salesPath, adminPath] {
            let code = try gridSource(path)
            // 가로로 꽉 찬 줄 · 구분선 표는 사라졌다.
            #expect(!code.contains("InkSeparator()"), "\(path)")
            #expect(!code.contains("List("), "\(path)")
            #expect(!code.contains("HStack(alignment: .top, spacing: 12)"), "\(path)")
        }
    }
}

// MARK: - 공용 카드

@Suite("세 화면이 같은 카드다")
struct SharedMarketplaceCardTests {

    @Test("세 화면 모두 공용 카드를 그린다")
    func everyScreenDrawsTheSharedCard() throws {
        for path in [galleryPath, salesPath, adminPath] {
            #expect(try gridSource(path).contains("MarketplaceListingCard("), "\(path)")
        }
    }

    @Test("화면이 자기 이미지 렌더링 코드를 갖지 않는다")
    func noScreenDrawsItsOwnImage() throws {
        for path in [galleryPath, salesPath, adminPath] {
            let code = try gridSource(path)
            for forbidden in [
                "UIImage(data:", "Image(uiImage:", "scaledToFill", "contentMode: .fill",
                "TransparencyCheckerboard", "MarketplaceListingPreview(",
            ] {
                #expect(!code.contains(forbidden), "\(path): \(forbidden)")
            }
        }
    }

    @Test("카드가 종류를 스스로 판정하지 않는다")
    func theCardAsksTheStyleAuthority() throws {
        let card = try gridSource("ggumirror/Store/StoreMirrorCard.swift")
        #expect(card.contains("ListingPreviewStyle.aspectRatio(for: model.contentType)"))
        // 거울 비율을 못 박아 두었던 것이 스티커 카드를 따로 만들게 한 원인이었다.
        #expect(!card.contains("MirrorStyle.aspectRatio"))
        for magic in ["0.46", "9 / 19.5"] {
            #expect(!card.contains(magic), "\(magic)")
        }
    }

    @Test("스티커 전용 카드가 사라졌다")
    func theStickerCardIsGone() throws {
        let gallery = try gridSource(galleryPath)
        // 카드 부분만 본다 — 상세 화면은 종류를 알아야 한다(스티커에는 미리보기가 없다).
        let start = try #require(gallery.range(of: "struct MarketplaceGalleryItem: View {"))
        let end = try #require(gallery.range(of: "nonisolated extension MarketplaceListing {"))
        let card = String(gallery[start.upperBound..<end.lowerBound])

        #expect(!card.contains("stickerCard"))
        // 카드가 종류로 분기하지 않는다 — **값으로 넘기고** 판정은 공용 규칙이 한다.
        #expect(!card.contains("ListingPreviewStyle.isSticker"))
        #expect(card.contains("contentType: listing.contentType"))
    }

    @Test("거울과 스티커가 다른 칸 비율을 받는다")
    func mirrorAndStickerStillDiffer() {
        #expect(ListingPreviewStyle.aspectRatio(for: "mirror") == MirrorStyle.aspectRatio)
        #expect(ListingPreviewStyle.aspectRatio(for: "sticker") == 1)
        #expect(ListingPreviewStyle.contentMode(for: "mirror") == .fill)
        // 스티커를 자르면 스티커가 아니다.
        #expect(ListingPreviewStyle.contentMode(for: "sticker") == .fit)
        // 투명한 것이 정상인 스티커는 바탕을 깔아야 보인다.
        #expect(ListingPreviewStyle.showsTransparency(for: "sticker"))
        #expect(!ListingPreviewStyle.showsTransparency(for: "mirror"))
    }

    @Test("모르는 종류도 카드가 무너지지 않는다")
    func unknownTypeStillGetsACard() {
        for unknown in ["", "video", "future-type"] {
            #expect(ListingPreviewStyle.aspectRatio(for: unknown) == MirrorStyle.aspectRatio)
        }
    }

    @Test("카드가 대기와 실패를 구분한다")
    func waitingAndFailureAreDifferent() throws {
        let preview = try gridSource("ggumirror/Store/MarketplaceListingPreview.swift")
        #expect(preview.contains("didFail"))
        #expect(preview.contains("미리보기를 불러오지 못했어요"))
        // 관리 화면이 실패 상태를 실제로 넘긴다 — 판매자는 그림이 왜 없는지 알아야 한다.
        #expect(try gridSource(salesPath).contains("didFail: store.myPreviewFailures"))
    }

    @Test("카드가 운영 정책을 알지 않는다")
    func theCardKnowsNoPolicy() throws {
        let card = try gridSource(cardPath)
        for policy in ["isDeletedBySeller", "moderationStatus", "takedown", "restore",
                       "purchase", "priceShards", "isPublished"] {
            #expect(!card.contains(policy), "\(policy)")
        }
    }
}

// MARK: - 상점

@Suite("상점은 하나의 연속된 격자다")
struct StoreGridContinuityTests {

    @Test("내장 템플릿과 사용자 상품이 한 목록이다")
    func oneSequenceNotTwoSections() throws {
        let code = try gridSource(storePath)
        #expect(code.contains("ForEach(mirrorItems)"))
        // 격자는 하나뿐이라 구획 경계에서 빈 칸이 생길 자리가 없다.
        #expect(code.components(separatedBy: "LazyVGrid(").count - 1 == 1)
        #expect(!code.contains("MarketplaceSection("))
    }

    @Test("홀수 개여도 순서가 이어진다")
    func oddCountsJustEnd() {
        // 5개 = 2 + 2 + 1. 중간에 빈 칸이 생기지 않는다는 것은 곧
        // **하나의 sequence**라는 뜻이다.
        let formatter = ISO8601DateFormatter()
        let listings = (0..<3).map { index in
            StoreMirrorItem.marketplace(
                MarketplaceListing(
                    id: "u\(index)", contentType: "mirror", title: "u\(index)",
                    description: "", priceShards: index, downloadCount: index,
                    likeCount: index,
                    publishedAt: formatter.date(from: "2026-08-0\(index + 1)T00:00:00Z")!,
                    sellerDisplayName: nil
                )
            )
        }
        let builtIn = (0..<2).map { index in
            StoreMirrorItem.builtIn(
                MirrorTemplate(
                    id: "t\(index)", name: "t\(index)", creator: "꾸미러",
                    price: index, style: BasicMirror.cream.style
                )
            )
        }
        let ordered = StoreSort.latest.ordered(listings + builtIn)
        #expect(ordered.count == 5)
        #expect(Set(ordered.map(\.id)).count == 5)
    }

    @Test("정렬 authority를 다시 만들지 않는다")
    func sortingStillComesFromStoreSort() throws {
        let code = try gridSource(storePath)
        #expect(code.contains("sort.ordered("))
        // 화면이 자기 비교 규칙을 적지 않는다.
        #expect(!code.contains(".sorted { "))
        #expect(!code.contains("publishedAt >"))
    }
}

// MARK: - 내 판매

@Suite("내 판매 관리 기능이 그대로다")
struct MySalesGridTests {

    @Test("판매자에게 필요한 값이 카드에 남아 있다")
    func sellerMetadataSurvives() throws {
        let code = try gridSource(salesPath)
        #expect(code.contains("price: listing.priceShards"))
        #expect(code.contains("downloadCount: listing.downloadCount"))
        #expect(code.contains("count: listing.likeCount"))
        // 판매 상태는 배지와 통계 줄 양쪽에 온다.
        #expect(code.contains("status: listing.statusLabel"))
        // 등록에 실패했으면 그 자리에 **이유**가 온다 — `등록 미완료`만으로는
        // 무엇을 고쳐야 할지 알 수 없다.
        #expect(code.contains("store.publishFailure(for: listing.id)?.message ?? listing.statusLabel"))
    }

    @Test("상태 구획이 그대로다")
    func statusGroupsAreKept() throws {
        let code = try gridSource(salesPath)
        for group in ["판매 중", "등록 미완료", "운영 정책으로 내려감", "판매 중지"] {
            #expect(code.contains(group), "\(group)")
        }
    }

    @Test("관리 동작이 하나도 사라지지 않았다")
    func everyManagementActionSurvives() throws {
        let code = try gridSource(salesPath)
        #expect(code.contains("\"삭제\""))
        #expect(code.contains("\"상점에 올리기\""))
        #expect(code.contains("store.resumePublish("))
        #expect(code.contains("store.delete(listingID:"))
        // 삭제는 되살릴 수 없으므로 **확인을 먼저 받는다.**
        #expect(code.contains("pendingDelete = listing"))
        #expect(code.contains("InkDialogAction(\"삭제\", role: .destructive)"))
    }

    @Test("내려간 상품에 '다시 판매'를 만들지 않는다")
    func retiredListingsOnlyOfferDelete() throws {
        let code = try gridSource(salesPath)
        #expect(!code.contains("다시 판매"))
        #expect(!code.contains("store.republish("))
    }

    @Test("자기 상품에는 좋아요를 누를 수 없다")
    func selfLikeIsNotOffered() throws {
        // 서버가 거절할 CTA를 일부러 보여 주지 않는다. 숫자는 보인다.
        #expect(try gridSource(salesPath).contains("isMine: true"))
    }

    @Test("칸마다 관리 버튼을 여러 개 붙이지 않는다")
    func atMostOneActionPerCell() throws {
        let card = try gridSource(cardPath)
        // 카드가 받는 동작은 하나뿐이다 — 배열이 아니다.
        #expect(card.contains("var action: MarketplaceCardAction?"))
        #expect(!card.contains("[MarketplaceCardAction]"))
    }
}

// MARK: - 상점 관리 (Admin)

@Suite("운영자 기능이 그대로다")
struct AdminGridTests {

    @Test("필터가 그대로다")
    func filtersAreKept() throws {
        let code = try gridSource(adminPath)
        // 종류 축.
        #expect(code.contains("(\"전체\", nil), (\"거울\", \"mirror\"), (\"스티커\", \"sticker\")"))
        // 상태 축. 둘은 여전히 **다른 축**이다.
        #expect(code.contains("AdminStatusFilter.allCases"))
        #expect(code.contains("store.statusFilter"))
        #expect(code.contains("store.visible"))
    }

    @Test("상태 필터 규칙이 바뀌지 않았다")
    func statusFilterRulesAreUnchanged() {
        #expect(AdminStatusFilter.allCases.map(\.label) == ["판매 중", "내려감", "전체"])
    }

    @Test("takedown · restore가 그대로다")
    func moderationActionsSurvive() throws {
        let code = try gridSource(adminPath)
        #expect(code.contains("\"상점에서 내리기\""))
        #expect(code.contains("\"다시 공개하기\""))
        #expect(code.contains("store.takedown("))
        #expect(code.contains("store.restore("))
        // 사유를 고르는 것이 곧 확인이다 — 확인창을 두 번 띄우지 않는다.
        #expect(code.contains("AdminModerationReason.allCases"))
    }

    @Test("판매자가 삭제한 상품은 되살릴 수 없다")
    func sellerDeletedIsTerminal() throws {
        let code = try gridSource(adminPath)
        // 버튼 자체를 주지 않는다 — 서버가 409로 거절할 CTA를 보여 주지 않는다.
        #expect(code.contains("guard !listing.isDeletedBySeller else { return nil }"))
        // 목록 필터에서도 끝 상태로 남는다.
        #expect(code.contains("listing.isRemoved && !listing.isDeletedBySeller"))
    }

    @Test("내려간 사유가 카드에 남아 있다")
    func moderationReasonIsStillShown() throws {
        let code = try gridSource(adminPath)
        #expect(code.contains("listing.reasonLabel"))
        // 모르는 사유를 지어내지 않는다.
        #expect(code.contains("?? listing.statusLabel"))
    }

    @Test("운영 판단에 필요한 값이 카드에 있다")
    func adminMetadataSurvives() throws {
        let code = try gridSource(adminPath)
        #expect(code.contains("listing.sellerLabel"))
        #expect(code.contains("price: listing.priceShards"))
        #expect(code.contains("downloadCount: listing.downloadCount"))
        #expect(code.contains("count: listing.likeCount"))
        #expect(code.contains("status: listing.statusLabel"))
    }

    @Test("운영자 전용 preview component를 만들지 않았다")
    func noAdminOnlyPreview() throws {
        let code = try gridSource(adminPath)
        #expect(!code.contains("private func preview("))
        #expect(!code.contains("frame(width: 62)"))
    }
}

// MARK: - 실제로 그려 본다

/// 소스에 무엇이 적혀 있는지가 아니라 **실제 view 계층이 낸 크기**를 본다.
/// 하나의 카드가 두 종류를 모두 감당한다는 것은 결국 칸 모양으로 드러난다.
@Suite("카드가 실제로 종류에 맞는 칸을 낸다")
@MainActor
struct MarketplaceCardGeometryTests {

    /// 카드 하나를 정해진 폭으로 그려 실제 높이를 잰다.
    private func renderedSize(contentType: String) throws -> CGSize {
        let card = MarketplaceListingCard(
            model: StoreMirrorCardModel(
                contentType: contentType,
                title: "샘플",
                subtitle: "판매자",
                price: 10,
                downloadCount: 3,
                footnote: "판매 중"
            )
        )
        .frame(width: 180)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderer.isOpaque = false
        let image = try #require(renderer.cgImage)
        return CGSize(width: image.width, height: image.height)
    }

    @Test("거울 칸은 세로로 길고 스티커 칸은 정사각이다")
    func eachTypeGetsItsOwnBox() throws {
        let mirror = try renderedSize(contentType: "mirror")
        let sticker = try renderedSize(contentType: "sticker")

        #expect(mirror.width == 180)
        #expect(sticker.width == 180)

        // 글자 줄은 두 카드가 똑같으므로, 높이 차이는 곧 **칸 높이 차이**다.
        // 거울 칸은 180 / 0.46 ≈ 390, 스티커 칸은 180.
        let expectedGap = 180 / ListingPreviewStyle.aspectRatio(for: "mirror") - 180
        let actualGap = mirror.height - sticker.height
        #expect(abs(actualGap - expectedGap) < 3, "\(actualGap) vs \(expectedGap)")
    }

    @Test("스티커가 거울 칸에 눌려 들어가지 않는다")
    func stickersAreNotSquashedIntoAMirrorBox() throws {
        let sticker = try renderedSize(contentType: "sticker")
        // 정사각 칸 + 글자 몇 줄이므로 폭보다 조금만 크다.
        // 거울 비율로 눌렸다면 여기서 두 배 넘게 커진다.
        #expect(sticker.height < 180 * 1.8, "\(sticker.height)")
        #expect(sticker.height > 180, "\(sticker.height)")
    }

    @Test("관리 버튼이 있어도 칸 폭은 그대로다")
    func theActionButtonDoesNotWidenTheCell() throws {
        let plain = try renderedSize(contentType: "mirror")
        let withAction = ImageRenderer(
            content: MarketplaceListingCard(
                model: StoreMirrorCardModel(
                    contentType: "mirror", title: "샘플", price: 10,
                    downloadCount: 0, footnote: "판매 중", status: "판매 중"
                ),
                action: MarketplaceCardAction(title: "삭제") {}
            )
            .frame(width: 180)
        )
        withAction.scale = 1
        withAction.isOpaque = false
        let image = try #require(withAction.cgImage)

        #expect(image.width == Int(plain.width))
        // 버튼만큼만 길어진다 — 44pt 손가락 자리 + 사이 간격.
        #expect(CGFloat(image.height) > plain.height)
        #expect(CGFloat(image.height) - plain.height < InkTapTarget.minimum + 20)
    }
}
