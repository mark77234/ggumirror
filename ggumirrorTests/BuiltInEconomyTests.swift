//
//  BuiltInEconomyTests.swift
//  ggumirrorTests
//
//  내장 템플릿 유료화.
//
//  **값의 authority는 서버다.** 여기 test들이 지키는 것은 두 가지다:
//  화면에 적힌 값이 서버 표와 어긋나지 않을 것, 그리고 client가 잔액을
//  스스로 바꾸지 않을 것.
//

import Testing
import Foundation
@testable import ggumirror

private func source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

/// backend repo의 값 표를 읽는다. **두 repo가 어긋나면 여기서 걸린다** —
/// 화면은 1조각이라고 하고 서버는 3조각을 빼는 상황을 막는다.
private func backendPrices() throws -> [String: Int] {
    let models = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "ggumirror-be/app/catalog/models.py")
    let text = try String(contentsOf: models, encoding: .utf8)

    // 값이 싼 8종은 목록으로, 나머지 art는 3, basic은 0이다.
    func ids(_ name: String) -> Set<String> {
        guard let start = text.range(of: "\(name) = frozenset({") else { return [] }
        guard let end = text.range(of: "})", range: start.upperBound..<text.endIndex) else { return [] }
        let body = text[start.upperBound..<end.lowerBound]
        return Set(body.split(whereSeparator: { ",\n \"".contains($0) }).map(String.init))
    }
    let entry = ids("_ENTRY_ARTWORK_IDS")
    let artwork = ids("ARTWORK_TEMPLATE_IDS")
    var prices: [String: Int] = [:]
    for id in artwork { prices[id] = entry.contains(id) ? 1 : 3 }
    for name in ["white", "black", "cream", "softPink", "lavender", "sky", "mint", "gray"] {
        prices["basic-\(name)"] = 0
    }
    return prices
}

@Suite("내장 템플릿 값")
struct BuiltInPricingTests {

    @Test("손그림 템플릿은 1 또는 3조각이다")
    func artworkPricesAreOneOrThree() {
        let artwork = StoreCatalog.samples.filter { !$0.isBasic }
        #expect(artwork.count == 24)
        #expect(Set(artwork.map(\.price)) == [1, 3])
    }

    @Test("예전 값을 그대로 옮겼다")
    func mappingPreservesTheOldTiers() {
        let artwork = StoreCatalog.samples.filter { !$0.isBasic }
        // 예전 0원 8종 → 1조각, 4원 16종 → 3조각.
        #expect(artwork.filter { $0.price == 1 }.count == 8)
        #expect(artwork.filter { $0.price == 3 }.count == 16)
    }

    @Test("단색 기본 거울은 무료로 남는다")
    func basicMirrorsStayFree() {
        // 앱이 기본값으로 쓰는 거울이다. 값을 매기면 처음 켠 사람이 거울을 못 쓴다.
        let basics = StoreCatalog.samples.filter(\.isBasic)
        #expect(basics.count == 8)
        #expect(basics.allSatisfy { $0.price == 0 })
    }

    @Test("client와 backend의 값 표가 같다")
    func clientAndBackendAgree() throws {
        let backend = try backendPrices()
        #expect(backend.count == 32)
        for template in StoreCatalog.samples {
            let expected = try #require(backend[template.id], "backend에 \(template.id)가 없다")
            #expect(template.price == expected, "\(template.id): 화면 \(template.price) vs 서버 \(expected)")
        }
    }

    @Test("모든 값이 0...3 안에 있다")
    func pricesAreWithinRange() {
        #expect(StoreCatalog.samples.allSatisfy { (0...3).contains($0.price) })
    }
}

@Suite("내장 템플릿 CTA")
struct BuiltInCTATests {

    @Test("아직 없으면 값이 적힌 CTA다")
    func notOwnedShowsThePrice() {
        for price in [1, 3] {
            let cta = MirrorAcquireCTA.state(
                price: price, isSignedIn: true, ownsOnServer: false, existsLocally: false
            )
            #expect(cta.title == "\(price)조각으로 받기")
        }
    }

    @Test("값이 있는 템플릿에 무료 CTA가 나오지 않는다")
    func paidTemplatesNeverSayFree() {
        // 예전 8종은 이제 1조각이다 — "무료로 받기"가 남아 있으면 거짓말이다.
        for template in StoreCatalog.samples where !template.isBasic {
            let cta = MirrorAcquireCTA.state(
                price: template.price, isSignedIn: true,
                ownsOnServer: false, existsLocally: false
            )
            #expect(cta.title != "무료로 받기", "\(template.id)")
        }
    }

    @Test("무료 기본 거울에는 무료 CTA가 맞다")
    func freeBasicsStillSayFree() {
        let cta = MirrorAcquireCTA.state(
            price: 0, isSignedIn: true, ownsOnServer: false, existsLocally: false
        )
        #expect(cta.title == "무료로 받기")
    }

    @Test("샀지만 기기에 없으면 담기 CTA다")
    func ownedRemoteShowsAdd() {
        let cta = MirrorAcquireCTA.state(
            price: 3, isSignedIn: true, ownsOnServer: true, existsLocally: false
        )
        // **다시 사라고 하지 않는다.**
        #expect(cta.title == "내 거울에 추가")
    }

    @Test("이미 담았으면 잠긴다")
    func ownedLocalIsLocked() {
        let cta = MirrorAcquireCTA.state(
            price: 3, isSignedIn: true, ownsOnServer: true, existsLocally: true
        )
        #expect(cta.title == "이미 내 거울에 있어요")
        #expect(!cta.isEnabled)
    }

    @Test("로그아웃이면 로그인 안내다")
    func guestSeesTheSignInGate() {
        let cta = MirrorAcquireCTA.state(
            price: 1, isSignedIn: false, ownsOnServer: false, existsLocally: false
        )
        if case .needsSignIn = cta {} else {
            Issue.record("게스트에게 구매 CTA가 나왔다")
        }
    }

    @Test("서버 소유권이 CTA를 가른다")
    func detailUsesServerOwnership() throws {
        let view = try source("ggumirror/Store/TemplateDetailView.swift")
        #expect(view.contains("ownsOnServer: catalogStats.isOwned(template.id)"))
    }
}

@Suite("내장 구매는 client가 계산하지 않는다")
struct BuiltInEconomyGuardTests {

    @Test("잔액을 직접 바꾸지 않는다")
    func neverMutatesTheWallet() throws {
        for path in ["ggumirror/Store/CatalogStats.swift",
                     "ggumirror/Store/TemplateDetailView.swift"] {
            let code = try source(path)
            for forbidden in ["balance +=", "balance -=", "apply(balance:"] {
                #expect(!code.contains(forbidden), "\(path)에 \(forbidden)")
            }
        }
    }

    @Test("가격을 서버에 보내지 않는다")
    func priceIsNeverSent() throws {
        let api = try source("ggumirror/Backend/BackendClient+Catalog.swift")
        let start = try #require(api.range(of: "func purchaseTemplate")).upperBound
        let end = try #require(api.range(of: "func reconcileTemplates", range: start..<api.endIndex)).lowerBound
        let body = String(api[start..<end])
        // body 자체가 없다 — 가격도 수량도 사용자도 실을 자리가 없다.
        #expect(!body.contains("price"))
        #expect(!body.contains("body:"))
    }

    @Test("산 뒤에는 서버 값을 다시 읽는다")
    func refreshesAfterPurchase() throws {
        let view = try source("ggumirror/Store/TemplateDetailView.swift")
        #expect(view.contains("wallet?.refresh(session:"))
    }

    @Test("연타로 두 번 사지 않는다")
    func doubleTapIsBlocked() throws {
        let view = try source("ggumirror/Store/TemplateDetailView.swift")
        #expect(view.contains("guard !isBuying else { return }"))
    }

    @Test("사는 것과 담는 것은 따로다")
    func purchaseDoesNotAutoImport() throws {
        let view = try source("ggumirror/Store/TemplateDetailView.swift")
        let start = try #require(view.range(of: "private func buy()")).upperBound
        let end = try #require(
            view.range(of: "private func addToLibrary", range: start..<view.endIndex)
        ).lowerBound
        // 보관 공간이 없어도 소유권은 남아야 하므로 자동으로 담지 않는다.
        #expect(!view[start..<end].contains("library.acquire"))
    }

    @Test("담기는 조각을 쓰지 않는다")
    func addingToLibraryCostsNothing() throws {
        let view = try source("ggumirror/Store/TemplateDetailView.swift")
        let start = try #require(view.range(of: "private func addToLibrary")).upperBound
        #expect(!view[start...].contains("purchase("))
    }

    @Test("로그아웃하면 소유권 표시를 비운다")
    func signOutClearsOwnership() throws {
        let stats = try source("ggumirror/Store/CatalogStats.swift")
        // A가 산 것이 B에게 보이면 안 된다.
        #expect(stats.contains("owned = []"))
    }
}
