//
//  StoreMirrorCardTests.swift
//  ggumirrorTests
//
//  **상점의 거울 카드는 하나뿐이다.**
//
//  사용자 상품과 내장 템플릿이 서로 다른 카드처럼 보였다 — 사용자 상품만 작은 거울을
//  왼쪽에 붙이고 정보를 오른쪽에 세웠고, 하트는 카드 밖에 따로 떠 있었다.
//  기준은 원래 있던 내장 카드이고, 사용자 상품을 그쪽에 맞췄다.
//

import Testing
import Foundation
import SwiftUI
@testable import ggumirror

private func cardSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

@Suite("두 출처가 같은 카드를 쓴다")
struct StoreMirrorCardContractTests {

    @Test("사용자 상품과 내장 템플릿이 같은 컴포넌트를 쓴다")
    func bothSourcesUseOneCard() throws {
        // 이 계약이 깨지면 다시 두 벌의 레이아웃이 생긴다.
        #expect(try cardSource("ggumirror/Store/MarketplaceGallery.swift")
            .contains("StoreMirrorCard(model: cardModel"))
        #expect(try cardSource("ggumirror/Store/StoreView.swift")
            .contains("StoreMirrorCard("))
    }

    @Test("사용자 상품 전용 세로 레이아웃이 사라졌다")
    func sideInfoLayoutIsGone() throws {
        let gallery = try cardSource("ggumirror/Store/MarketplaceGallery.swift")
        // 작은 거울 + 오른쪽 정보 구조의 흔적.
        for gone in ["previewShare", "verticalMetadata", "mirrorCard",
                     "geometry.size.width * Self."] {
            #expect(!gallery.contains(gone), "\(gone)가 남아 있다")
        }
        // 거울 카드가 정사각으로 고정되지 않는다.
        #expect(!gallery.contains(".aspectRatio(1, contentMode: .fit)"))
    }

    @Test("스티커는 예전 정사각 표현을 유지한다")
    func stickerCardIsUnchanged() throws {
        let gallery = try cardSource("ggumirror/Store/MarketplaceGallery.swift")
        #expect(gallery.contains("private var stickerCard"))
        #expect(gallery.contains("if ListingPreviewStyle.isSticker(listing.contentType)"))
        // 스티커 칸은 여전히 정사각이다.
        #expect(ListingPreviewStyle.aspectRatio(for: "sticker") == 1)
    }

    @Test("거울 비율은 9:19.5 그대로다")
    func mirrorKeepsItsRatio() {
        #expect(ListingPreviewStyle.aspectRatio(for: "mirror") == MirrorStyle.aspectRatio)
        #expect(MirrorStyle.aspectRatio < 1, "거울은 세로로 길다")
    }

    @Test("두 구획이 같은 grid를 쓴다")
    func bothSectionsShareTheGrid() throws {
        for path in ["ggumirror/Store/StoreView.swift",
                     "ggumirror/Store/MarketplaceGallery.swift"] {
            #expect(try cardSource(path).contains("GalleryLayout.columns(for: dynamicTypeSize)"),
                    "\(path)")
        }
    }
}

@Suite("카드 정보 구성")
struct StoreMirrorCardModelTests {

    private func model(
        title: String = "테스트", subtitle: String? = nil, price: Int = 1,
        downloads: Int? = nil
    ) -> StoreMirrorCardModel {
        StoreMirrorCardModel(
            title: title, subtitle: subtitle, price: price,
            downloadCount: downloads, footnote: "어제"
        )
    }

    @Test("세지 않는 값은 숫자로 말하지 않는다")
    func absentCountsStaySilent() throws {
        // 내장 템플릿은 좋아요 domain이 없다 — 하트를 넘기지 않는다.
        let store = try cardSource("ggumirror/Store/StoreView.swift")
        #expect(!store.contains("StoreMirrorCardLike("))
        // 다운로드 수도 서버 값을 받은 뒤에만 보여 준다.
        #expect(model(downloads: nil).downloadCount == nil)
        #expect(model(downloads: 0).downloadCount == 0)
    }

    @Test("판매자 이름을 지어내지 않는다")
    func noInventedSellerName() throws {
        let gallery = try cardSource("ggumirror/Store/MarketplaceGallery.swift")
        // 공개 응답에 판매자 이름이 없다. `익명` 같은 값을 만들지 않는다.
        #expect(gallery.contains("subtitle: nil"))
        for invented in ["\"익명\"", "\"사용자\"", "sellerUserId"] {
            #expect(!gallery.contains(invented), "\(invented)를 화면에 쓴다")
        }
        // 내장은 실제 만든이가 있다.
        #expect(try cardSource("ggumirror/Store/StoreView.swift")
            .contains("subtitle: template.creator"))
    }

    @Test("무료와 유료가 같은 자리에서 표현된다")
    func priceSharesOnePlace() throws {
        let card = try cardSource("ggumirror/Store/StoreMirrorCard.swift")
        #expect(card.contains("ShardAmount(amount: model.price)"))
        // 카드가 가격 문구를 따로 만들지 않는다 — 공통 컴포넌트가 무료를 처리한다.
        #expect(!card.contains("\"무료로\""))
    }
}

@MainActor
@Suite("하트")
struct StoreMirrorCardLikeTests {

    @Test("하트가 통계 줄 안에 있다 — 카드 밖에 떠 있지 않다")
    func heartLivesInTheMetadataRow() throws {
        let card = try cardSource("ggumirror/Store/StoreMirrorCard.swift")
        let metadata = try #require(card.range(of: "private var metadata: some View"))
        let body = card[metadata.lowerBound...].prefix(700)
        #expect(body.contains("heart(like)"))
        // 예전처럼 미리보기 위에 얹은 캡슐이 아니다.
        #expect(!body.contains("overlay(alignment: .topTrailing)"))
    }

    @Test("손이 닿는 자리는 44pt이고 label 안에 있다")
    func heartHasARealTapTarget() throws {
        let card = try cardSource("ggumirror/Store/StoreMirrorCard.swift")
        #expect(card.contains("frame(minWidth: 44, minHeight: 44"))
        // 겉모습이 Button 밖으로 나가면 글자만 눌린다(hit-area hardening 규칙).
        let button = try #require(card.range(of: "Button(action: like.toggle)"))
        let body = card[button.lowerBound...].prefix(400)
        #expect(body.contains(".contentShape(.rect)"))
        #expect(body.firstIndex(of: "}") != nil)
    }

    @Test("내 상품은 숫자만 보이고 누를 수 없다")
    func ownListingIsNotInteractive() throws {
        let card = try cardSource("ggumirror/Store/StoreMirrorCard.swift")
        #expect(card.contains("if like.isMine {"))
        // 목록에서 감추지는 않는다.
        #expect(!card.contains("if like.isMine { EmptyView() }"))
    }

    @Test("상세 화면처럼 하트가 없는 자리도 있다")
    func likeIsOptional() throws {
        let gallery = try cardSource("ggumirror/Store/MarketplaceGallery.swift")
        #expect(gallery.contains("guard let onToggleLike else { return nil }"))
    }
}

@Suite("미리보기 안정성")
struct StoreMirrorCardPreviewTests {

    @Test("불러오는 중에도 칸 크기가 움직이지 않는다")
    func placeholderKeepsTheFrame() throws {
        let gallery = try cardSource("ggumirror/Store/MarketplaceGallery.swift")
        // 그림이 있든 없든 같은 `aspectRatio` 칸 안에서 그린다.
        let preview = try #require(gallery.range(of: "private var previewImage: some View"))
        // 함수 끝까지 본다 — 고정 길이로 자르면 아래쪽 modifier를 놓친다.
        let rest = gallery[preview.lowerBound...]
        let stop = rest.range(of: "\n    }\n") ?? rest.range(of: "\n}")
        let body = stop.map { String(rest[..<$0.lowerBound]) } ?? String(rest)
        #expect(body.contains("aspectRatio(ListingPreviewStyle.aspectRatio(for: type)"))
        #expect(body.contains("Image(systemName: \"photo\")"))
    }

    @Test("실패해도 항목이 사라지지 않는다")
    func failureKeepsTheCard() throws {
        let gallery = try cardSource("ggumirror/Store/MarketplaceGallery.swift")
        // 실패와 대기가 같은 자리표시자다 — 가짜 그림도, 빈 자리도 만들지 않는다.
        #expect(!gallery.contains("if preview == nil { EmptyView() }"))
    }

    @Test("두 출처가 같은 카메라 배경을 쓴다")
    func sameCameraBackground() {
        // 정지 썸네일의 카메라 자리는 한 곳에서 정해진다.
        #expect(MirrorRenderer.glass == PaperTheme.thumbnailGlass)
    }
}
