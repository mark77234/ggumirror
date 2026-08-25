//
//  StoreBrowsingTests.swift
//  ggumirrorTests
//
//  공개 상점 탐색 — 정렬 · 필터 · 좋아요 · 로그인 관문 · 스티커 카드.
//
//  실기기에서 한꺼번에 드러난 문제들이다: 등록한 거울이 안 보이고, 카드에 하트가 없고,
//  정렬을 눌러도 그대로였다. **원인이 하나였다** — 공개 목록을 받아오는 `.task`가
//  목록이 비면 그려지지 않는 view에 붙어 있었다.
//

import Testing
import Foundation
import SwiftUI
@testable import ggumirror

private func browseSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

private func listing(
    _ id: String, type: String = "mirror", price: Int,
    downloads: Int, likes: Int, published: String
) -> MarketplaceListing {
    let formatter = ISO8601DateFormatter()
    return MarketplaceListing(
        id: id, contentType: type, title: id, description: "",
        priceShards: price, downloadCount: downloads, likeCount: likes,
        publishedAt: formatter.date(from: published) ?? .distantPast,
        sellerDisplayName: nil
    )
}

/// 명세 §42의 fixture.
private let fixtures = [
    listing("A", price: 5, downloads: 10, likes: 1, published: "2026-08-03T00:00:00Z"),
    listing("B", price: 0, downloads: 20, likes: 0, published: "2026-08-01T00:00:00Z"),
    listing("C", price: 1, downloads: 5, likes: 8, published: "2026-08-02T00:00:00Z"),
]

@Suite("정렬")
struct StoreSortingTests {

    private func order(_ sort: StoreSort) -> [String] {
        sort.ordered(fixtures).map(\.id)
    }

    @Test("네 가지 정렬이 각각 다른 순서를 낸다")
    func everySortHasItsOwnOrder() {
        #expect(order(.latest) == ["A", "C", "B"])
        #expect(order(.popular) == ["B", "A", "C"])
        #expect(order(.likes) == ["C", "A", "B"])
        #expect(order(.price) == ["B", "C", "A"])
    }

    @Test("가격 순은 싼 것부터다")
    func priceIsAscending() {
        let prices = StoreSort.price.ordered(fixtures).map(\.priceShards)
        #expect(prices == prices.sorted())
    }

    @Test("값이 같으면 최신 → id 순으로 흔들리지 않는다")
    func tiesAreDeterministic() {
        let same = [
            listing("z", price: 1, downloads: 0, likes: 0, published: "2026-08-01T00:00:00Z"),
            listing("a", price: 1, downloads: 0, likes: 0, published: "2026-08-01T00:00:00Z"),
            listing("m", price: 1, downloads: 0, likes: 0, published: "2026-08-05T00:00:00Z"),
        ]
        for sort in StoreSort.allCases {
            #expect(sort.ordered(same).map(\.id) == ["m", "a", "z"], "\(sort.label)")
        }
    }

    @Test("서버와 같은 이름을 쓴다")
    func serverValuesMatchTheContract() {
        #expect(StoreSort.allCases.map(\.serverValue) == ["latest", "popular", "likes", "price"])
    }

    @Test("필터와 정렬은 독립이다")
    func filterAndSortCompose() {
        let free = fixtures.filter { StorePriceFilter.free.includes(price: $0.priceShards) }
        #expect(free.map(\.id) == ["B"])
        // 무료 + 어떤 정렬이든 성립한다.
        for sort in StoreSort.allCases {
            #expect(sort.ordered(free).map(\.id) == ["B"], "\(sort.label)")
        }
        let all = fixtures.filter { StorePriceFilter.all.includes(price: $0.priceShards) }
        #expect(all.count == 3)
    }

    @Test("내장 목록과 사용자 상품이 같은 규칙으로 정렬된다")
    func builtInsAndListingsShareTheRule() {
        // 같은 규칙(`StoreSortable`)을 쓰므로 두 목록이 서로 다른 순서를 내지 않는다.
        let byPrice = StoreSort.price.ordered(StoreCatalog.samples).map(\.price)
        #expect(byPrice == byPrice.sorted())
        let listingPrices = StoreSort.price.ordered(fixtures).map(\.priceShards)
        #expect(listingPrices == listingPrices.sorted())
    }
}

@Suite("공개 목록을 실제로 받아온다")
struct StoreFeedTests {

    @Test("목록이 비어도 요청이 나간다")
    func fetchDoesNotLiveInsideAnEmptyView() throws {
        // **회귀**: 받아오는 `.task`가 상품 구획 안에 있었다. 그 구획은 비면
        // `EmptyView()`를 그리고, 그 위의 `.task`는 한 번도 실행되지 않는다.
        let section = try browseSource("ggumirror/Store/MarketplaceGallery.swift")
        #expect(!section.contains(".task(id: \"\\(contentType)-\\(sort.rawValue)\")"))
        #expect(!section.contains("await store.refresh(contentType: contentType"))

        // 받아오는 일은 **언제나 그려지는 화면**이 한다.
        for (path, type) in [("ggumirror/Store/StoreView.swift", "mirror"),
                             ("ggumirror/Store/StickerStoreView.swift", "sticker")] {
            let screen = try browseSource(path)
            #expect(screen.contains("contentType: \"\(type)\""), "\(path)")
            #expect(screen.contains("publicFeedVersion"), "\(path)")
        }
    }

    @Test("등록에 성공하면 공개 목록을 다시 받는다")
    func publishInvalidatesTheFeed() throws {
        let store = try browseSource("ggumirror/Store/MarketplaceStore.swift")
        #expect(store.contains("func invalidatePublicFeed()"))
        // 등록 성공 경로마다 부른다.
        #expect(store.components(separatedBy: "invalidatePublicFeed()").count - 1 >= 3)
    }

    @Test("자기 상품을 공개 목록에서 빼지 않는다")
    func ownListingsStayPublic() throws {
        let section = try browseSource("ggumirror/Store/MarketplaceGallery.swift")
        // self-like만 막는다. 상품 자체는 상점에서 보여야 한다.
        #expect(!section.contains("sellerId != me"))
        #expect(!section.contains("filter { $0.isMine == false }"))
        #expect(section.contains("isMine"))
    }
}

@Suite("좋아요")
struct StoreLikeTests {

    @Test("공개 카드에 하트가 있다")
    func publicCardsHaveHearts() throws {
        let gallery = try browseSource("ggumirror/Store/MarketplaceGallery.swift")
        #expect(gallery.contains("heart"))
        #expect(gallery.contains("onToggleLike"))
        // 손이 닿는 자리는 44pt다.
        #expect(gallery.contains("minWidth: 44, minHeight: 44"))
        // 거울/스티커 카드가 **같은 view**를 쓴다 — 한쪽에만 하트가 있을 수 없다.
        for path in ["ggumirror/Store/StoreView.swift", "ggumirror/Store/StickerStoreView.swift"] {
            #expect(try browseSource(path).contains("MarketplaceSection("), "\(path)")
        }
    }

    @Test("자기 상품에는 숫자만 보이고 누를 수 없다")
    func selfLikeIsNotOffered() throws {
        let gallery = try browseSource("ggumirror/Store/MarketplaceGallery.swift")
        #expect(gallery.contains("if isMine {"))
        // 목록에서 감추지는 않는다.
        #expect(!gallery.contains("if isMine { EmptyView() }"))
    }

    @Test("좋아요 상태는 서버가 정한다 — 낙관적 표시를 남기지 않는다")
    func likeStateIsServerAuthoritative() throws {
        let store = try browseSource("ggumirror/Store/MarketplaceStore.swift")
        #expect(store.contains("if result.liked { likedListingIDs.insert(result.listingId) }"))
        #expect(store.contains("apply(likeCount: result.likeCount, to: result.listingId)"))
        // 요청 전에 미리 바꿔 두지 않는다.
        #expect(!store.contains("likedListingIDs.insert(listingID)"))
    }
}

@Suite("로그인 관문")
struct GuestAuthGateTests {

    @Test("로그인 전에는 요청을 보내지 않고 안내한다")
    func guestNeverSendsTheRequest() throws {
        let store = try browseSource("ggumirror/Store/MarketplaceStore.swift")
        // 401을 받고 나서 알리지 않는다 — 이미 아는 사실이다.
        #expect(store.contains("guard let token = session?.accessToken else { return false }"))
    }

    @Test("안내 창이 하나뿐이고 root-level 경로를 쓴다")
    func oneDialogForEveryGuestAction() throws {
        let dialog = try browseSource("ggumirror/Shared/SignInRequiredDialog.swift")
        #expect(dialog.contains("\"로그인이 필요해요\""))
        #expect(dialog.contains("inkDialog("))
        // ScrollView 안 `.overlay`로 새 창을 만들지 않는다.
        #expect(!dialog.contains(".overlay"))
        #expect(!dialog.contains("inkBottomSheet"))
        // 두 번째 auth 체계를 만들지 않는다.
        #expect(!dialog.contains("SignInWithAppleButton"))
        #expect(dialog.contains("pendingAction"))
    }

    @Test("탭 컨테이너 한 곳에 달려 어느 탭에서나 뜬다")
    func gateIsMountedOnce() throws {
        let home = try browseSource("ggumirror/Home/HomeView.swift")
        #expect(home.contains("inkSignInRequiredDialog"))
        #expect(home.components(separatedBy: "inkSignInRequiredDialog").count - 1 == 1)
        // 로그인 CTA는 기존 설정 화면으로 보낸다.
        #expect(home.contains("SettingsRoute.settings"))
    }

    @Test("판매 관리는 로그인 전에 열리지 않는다")
    func mySalesIsGated() throws {
        let store = try browseSource("ggumirror/Store/StoreView.swift")
        #expect(store.contains("guard item != .mySales || session.server != nil"))
        #expect(store.contains("requireSignIn"))
    }

    @Test("상점 탐색 자체에는 관문이 없다")
    func browsingStaysOpen() throws {
        let store = try browseSource("ggumirror/Store/MarketplaceStore.swift")
        // 공개 목록은 로그인 없이 받아온다.
        #expect(store.contains("func refresh(contentType: String?, sort: StoreSort"))
        #expect(!store.contains("guard session != nil else { return }\n        listings"))
    }
}

@Suite("스티커 카드가 거울 칸을 쓰지 않는다")
struct StickerCardLayoutTests {

    @Test("종류마다 칸 비율이 다르다")
    func aspectRatioFollowsContentType() {
        #expect(ListingPreviewStyle.aspectRatio(for: "sticker") == 1)
        #expect(ListingPreviewStyle.aspectRatio(for: "mirror") == MirrorStyle.aspectRatio)
        // 거울은 세로로 길고 스티커는 정사각이다.
        #expect(ListingPreviewStyle.aspectRatio(for: "mirror") < 1)
    }

    @Test("스티커는 잘라내지 않는다")
    func stickersAreFittedNotFilled() {
        #expect(ListingPreviewStyle.contentMode(for: "sticker") == .fit)
        #expect(ListingPreviewStyle.contentMode(for: "mirror") == .fill)
        #expect(ListingPreviewStyle.showsTransparency(for: "sticker"))
        #expect(!ListingPreviewStyle.showsTransparency(for: "mirror"))
    }

    @Test("모르는 종류는 거울처럼 다룬다 — 카드가 무너지지 않는다")
    func unknownTypeFallsBackSafely() {
        for unknown in ["", "video", "future-type"] {
            #expect(ListingPreviewStyle.aspectRatio(for: unknown) == MirrorStyle.aspectRatio)
            #expect(ListingPreviewStyle.contentMode(for: unknown) == .fill)
        }
    }

    @Test("칸 크기가 원본 픽셀 크기에 기대지 않는다")
    func cardSizeIgnoresSourcePixels() throws {
        for path in ["ggumirror/Store/MarketplaceGallery.swift",
                     "ggumirror/Store/MySalesSection.swift"] {
            let source = try browseSource(path)
            #expect(source.contains("ListingPreviewStyle.aspectRatio(for:"), "\(path)")
            // 원본 크기를 재서 칸을 정하지 않는다.
            #expect(!source.contains("image.size"), "\(path)")
            #expect(!source.contains("cgImage?.width"), "\(path)")
        }
    }

    @Test("긴 제목이 카드를 밀어내지 않는다")
    func longTitlesAreClipped() throws {
        for path in ["ggumirror/Store/MarketplaceGallery.swift",
                     "ggumirror/Store/MySalesSection.swift"] {
            #expect(try browseSource(path).contains(".lineLimit(1)"), "\(path)")
        }
    }
}


@Suite("로그아웃하면 개인화 상태가 남지 않는다")
struct SignOutStateResetTests {

    @Test("계정이 바뀌면 좋아요 · 구매 · 판매 목록을 다시 맞춘다")
    func personalizedStateFollowsTheAccount() throws {
        // **회귀**: 공개 목록 `.task`는 갈래·정렬로만 다시 돈다. 상점 화면에 머문 채
        // 로그아웃하면 이전 계정의 하트가 채워진 채 남아 있었다.
        let root = try browseSource("ggumirror/RootView.swift")
        #expect(root.contains("await marketplace.refreshMine(session: server)"))
        #expect(root.contains("await marketplace.refreshMyListings(session: server)"))
        #expect(root.contains("if server == nil { catalogStats.clear() }"))
    }

    @Test("로그인하지 않았으면 개인화 목록이 비어 있다")
    func signedOutMeansEmptyPersonalState() throws {
        let store = try browseSource("ggumirror/Store/MarketplaceStore.swift")
        #expect(store.contains("likedListingIDs = []"))
        #expect(store.contains("purchasedListingIDs = []"))
        #expect(store.contains("myListings = []"))
    }

    @Test("공개 목록까지 지우지는 않는다")
    func publicFeedSurvivesSignOut() throws {
        let store = try browseSource("ggumirror/Store/MarketplaceStore.swift")
        // 로그아웃했다고 상점이 통째로 비면 안 된다 — guest도 구경할 수 있다.
        let mine = try #require(store.range(of: "func refreshMine(session: ServerSession?) async"))
        let body = store[mine.lowerBound...].prefix(500)
        #expect(!body.contains("listings = []"))
    }

    @Test("지갑도 로그아웃에서 표시만 지운다")
    func walletClearsDisplayOnly() throws {
        let wallet = try browseSource("ggumirror/Shared/ShardWallet.swift")
        #expect(wallet.contains("guard let session, session.isValid() else {"))
        #expect(wallet.contains("clear()"))
    }
}
