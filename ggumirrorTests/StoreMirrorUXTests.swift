//
//  StoreMirrorUXTests.swift
//  ggumirrorTests
//
//  거울을 받는 흐름이 **출처와 무관하게 같은가.**
//
//  사용자는 이 거울이 내장인지 남이 올린 것인지 몰라도 같은 문구·같은 상태를 겪어야 한다.
//  예전에는 한쪽이 `조각으로 받기`, 다른 쪽이 `조각으로 구매`·`내 것으로 받기`였다.
//

import Testing
import Foundation
import SwiftUI
@testable import ggumirror

private func uxSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

@Suite("받기 버튼 상태")
struct MirrorAcquireCTATests {

    @Test("로그인 전에는 값을 보여 주되 누르면 로그인으로 간다")
    func guestSeesPriceAndIsGated() {
        let free = MirrorAcquireCTA.state(price: 0, isSignedIn: false, existsLocally: false)
        let paid = MirrorAcquireCTA.state(price: 3, isSignedIn: false, existsLocally: false)
        #expect(free == .needsSignIn(title: "무료로 받기"))
        #expect(paid == .needsSignIn(title: "3조각으로 받기"))
        // 눌리기는 한다 — 눌러야 로그인 안내가 뜬다.
        #expect(free.isEnabled)
        // **값을 치르는 동작이 아니다.** 서버에 먼저 보내지 않는다.
        #expect(!paid.costsShards)
    }

    @Test("무료와 유료 문구가 정해진 하나뿐이다")
    func freeAndPaidCopy() {
        #expect(MirrorAcquireCTA.state(price: 0, isSignedIn: true, existsLocally: false).title
                == "무료로 받기")
        #expect(MirrorAcquireCTA.state(price: 4, isSignedIn: true, existsLocally: false).title
                == "4조각으로 받기")
        // `구매` · `다운로드`가 섞이지 않는다 — 거울을 얻는 말은 `받기` 하나다.
        for price in [0, 1, 4, 18] {
            let title = MirrorAcquireCTA.state(
                price: price, isSignedIn: true, existsLocally: false
            ).title
            #expect(!title.contains("구매"))
            #expect(!title.contains("다운로드"))
        }
    }

    @Test("서버 소유권이 있으면 다시 사지 않는다")
    func ownedNeverAsksForShardsAgain() {
        let owned = MirrorAcquireCTA.state(
            price: 4, isSignedIn: true, ownsOnServer: true, existsLocally: false
        )
        #expect(owned == .addToLibrary)
        #expect(owned.title == "내 거울에 추가")
        #expect(!owned.costsShards)
        #expect(owned.isEnabled)
    }

    @Test("이미 이 기기에 있으면 잠긴다")
    func alreadyLocalIsDisabled() {
        for owns in [true, false] {
            let cta = MirrorAcquireCTA.state(
                price: 4, isSignedIn: true, ownsOnServer: owns, existsLocally: true
            )
            #expect(cta == .alreadyInLibrary)
            #expect(cta.title == "이미 내 거울에 있어요")
            #expect(!cta.isEnabled)
            // 값을 다시 보여 주지 않는다.
            #expect(!cta.title.contains("조각"))
        }
    }

    @Test("내가 올린 상품은 살 수 없다")
    func selfListingCannotBePurchased() {
        let mine = MirrorAcquireCTA.state(
            price: 4, isSignedIn: true, isMine: true, existsLocally: false
        )
        #expect(mine == .ownListing)
        #expect(!mine.isEnabled)
        #expect(!mine.costsShards)
    }

    @Test("이미 손에 있는 것이 가장 먼저다")
    func localPresenceWinsOverEveryOtherState() {
        // 내 상품이면서 이미 담아 둔 경우에도 값을 다시 묻지 않는다.
        #expect(MirrorAcquireCTA.state(
            price: 4, isSignedIn: true, isMine: true, ownsOnServer: true, existsLocally: true
        ) == .alreadyInLibrary)
    }

    @Test("두 상세 화면이 같은 모델을 쓴다")
    func bothDetailsShareTheModel() throws {
        for path in ["ggumirror/Store/TemplateDetailView.swift",
                     "ggumirror/Store/MarketplaceGallery.swift"] {
            let source = try uxSource(path)
            #expect(source.contains("MirrorAcquireCTA.state("), "\(path)")
            #expect(source.contains("cta.title"), "\(path)")
        }
        // 예전 문구가 남아 있지 않다.
        let market = try uxSource("ggumirror/Store/MarketplaceGallery.swift")
        #expect(!market.contains("조각으로 구매"))
        #expect(!market.contains("내 것으로 받기"))
    }
}

@Suite("내장 가격")
struct BuiltInPriceTests {

    @Test("모든 내장 템플릿이 5조각 미만이다")
    func everyBuiltInIsUnderFive() {
        for template in StoreCatalog.samples {
            #expect(template.price >= 0, "\(template.id)")
            #expect(template.price < 5, "\(template.id) = \(template.price)")
        }
    }

    @Test("무료로 남는 것은 단색 기본 거울뿐이다")
    func onlyBasicsStayFree() {
        // Phase B에서 손그림 24종 전부에 값이 붙었다. 기본 거울 8종만 0으로 남는다 —
        // 앱이 기본값으로 쓰는 거울이라 값을 매기면 처음 켠 사람이 거울을 못 쓴다.
        #expect(StoreCatalog.artworkTemplates.allSatisfy { $0.price > 0 })
        #expect(StoreCatalog.basics.allSatisfy { $0.price == 0 })
        #expect(StoreCatalog.basics.count == 8)
    }

    @Test("가장 비싼 것이 3조각이다")
    func maxPriceIsThree() {
        let max = StoreCatalog.samples.map(\.price).max()
        #expect(max == 3)
        // 전체 32종이 모두 표에 있다(기본 8 + 손그림 24).
        #expect(StoreCatalog.samples.count == 32)
    }

    @Test("가격은 catalog 한 곳에서만 온다")
    func priceHasOneAuthority() throws {
        // 화면 파일에 값을 적어 두지 않는다.
        for path in ["ggumirror/Store/StoreView.swift",
                     "ggumirror/Store/TemplateDetailView.swift"] {
            let source = try uxSource(path)
            #expect(!source.contains("temporaryPrice"), "\(path)")
            #expect(source.contains("template.price") || !source.contains("price:"), "\(path)")
        }
    }
}

@Suite("거울 카드")
struct MirrorCardLayoutTests {

    @Test("거울은 내장 템플릿과 **같은 카드**를 쓴다")
    func mirrorSharesTheBuiltInCard() throws {
        // 예전에는 사용자 상품만 정사각 카드 + 왼쪽 그림 · 오른쪽 정보였다.
        // 기준은 원래 있던 내장 카드이고, 사용자 상품을 그쪽에 맞췄다.
        let gallery = try uxSource("ggumirror/Store/MarketplaceGallery.swift")
        #expect(gallery.contains("MarketplaceListingCard("))
        #expect(!gallery.contains("private var mirrorCard"))
        #expect(!gallery.contains(".aspectRatio(1, contentMode: .fit)"))
        // 스티커도 같은 카드다 — 종류별 카드가 더는 없다.
        #expect(!gallery.contains("private var stickerCard"))
        #expect(try uxSource("ggumirror/Store/MarketplaceListingCard.swift")
            .contains("StoreMirrorCard(model: model"))
    }

    @Test("칸 폭을 손으로 재지 않는다")
    func widthComesFromTheGrid() throws {
        let gallery = try uxSource("ggumirror/Store/MarketplaceGallery.swift")
        #expect(gallery.contains("GalleryLayout.columns(for: dynamicTypeSize)"))
        for guessed in ["UIScreen", "width: 160", "width: 180", "393", "430", "previewShare"] {
            #expect(!gallery.contains(guessed), "폭을 손으로 쟀다: \(guessed)")
        }
    }

    @Test("거울은 카드 가운데에 온다")
    func thumbnailIsCentered() throws {
        // `aspectRatio(_:contentMode: .fit)`이 칸 안에서 가운데로 놓는다.
        // 상품마다 왼쪽으로 붙던 구조(고정 폭 + topLeading)가 사라졌다.
        // 칸 비율은 공용 카드가 종류별 authority에게 물어 정한다.
        let card = try uxSource("ggumirror/Store/StoreMirrorCard.swift")
        #expect(card.contains("ListingPreviewStyle.aspectRatio(for: model.contentType)"))
        #expect(card.contains("frame(maxWidth: .infinity, alignment: .center)"))
        let gallery = try uxSource("ggumirror/Store/MarketplaceGallery.swift")
        #expect(!gallery.contains("alignment: .topLeading)"))
    }

    @Test("거울 비율은 그대로 9:19.5다")
    func mirrorKeepsItsAspectRatio() {
        #expect(ListingPreviewStyle.aspectRatio(for: "mirror") == MirrorStyle.aspectRatio)
        #expect(ListingPreviewStyle.contentMode(for: "mirror") == .fill)
    }

    @Test("긴 제목이 카드를 밀어내지 않는다")
    func longTitleIsClipped() throws {
        // 제목 처리도 공통 카드에 있다 — 화면마다 다르게 자르지 않는다.
        let card = try uxSource("ggumirror/Store/StoreMirrorCard.swift")
        #expect(card.contains(".lineLimit(1)"))
        #expect(card.contains(".truncationMode(.tail)"))
    }
}

@Suite("썸네일 카메라 자리")
struct ThumbnailGlassTests {

    @Test("정지 썸네일의 카메라 자리는 밝다")
    func staticThumbnailIsLight() {
        // 검은 글씨·검은 그림이 그 위에서 보여야 한다.
        let glass = PaperTheme.thumbnailGlass.resolve(in: EnvironmentValues())
        #expect(glass.red > 0.85)
        #expect(glass.green > 0.85)
        #expect(glass.blue > 0.85)
        #expect(MirrorRenderer.glass == PaperTheme.thumbnailGlass)
    }

    @Test("실제 카메라와 저장되는 사진은 이 색을 쓰지 않는다")
    func realCameraKeepsItsOpening() throws {
        let renderer = try uxSource("ggumirror/Shared/MirrorRenderer.swift")
        // `nil`이면 완전히 비운다 — 실제 Mirror / Capture가 그 경로다.
        #expect(renderer.contains("mirrorAreaFill: Color? = glass"))

        let capture = try uxSource("ggumirror/Mirror/MirrorCapture.swift")
        #expect(!capture.contains("thumbnailGlass"))
        #expect(!capture.contains("MirrorRenderer.glass"))
    }

    @Test("새 색은 종이 팔레트에서 온다")
    func colorComesFromThePaperPalette() throws {
        let theme = try uxSource("ggumirror/Shared/PaperTheme.swift")
        #expect(theme.contains("static let thumbnailGlass"))
        // 새 색 체계를 만들지 않는다.
        let renderer = try uxSource("ggumirror/Shared/MirrorRenderer.swift")
        #expect(!renderer.contains("Color(red: 0.129"))
    }
}

@Suite("Light 고정")
struct AppearanceTests {

    private func plist(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    @Test("본앱과 extension 둘 다 Light로 고정된다")
    func everyTargetIsLight() throws {
        for path in ["Config/Info.plist",
                     "GgumirrorCapture/Info.plist",
                     "GgumirrorControls/Info.plist"] {
            let source = try plist(path)
            #expect(source.contains("<key>UIUserInterfaceStyle</key>"), "\(path)")
            #expect(source.contains("<string>Light</string>"), "\(path)")
        }
    }

    @Test("화면마다 colorScheme을 뿌리지 않는다")
    func appearanceIsSetInOnePlace() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "ggumirror")
        var found: [String] = []
        if let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in files where url.pathExtension == "swift" {
                let source = codeWithoutComments(
                    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                )
                if source.contains("preferredColorScheme") { found.append(url.lastPathComponent) }
            }
        }
        #expect(found.isEmpty, "화면에서 직접 지정한다: \(found)")
    }
}
