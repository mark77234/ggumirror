//
//  StoreActionsTests.swift
//  ggumirrorTests
//
//  UI-P3 — 상점 action 정리 · 등록 비용 · 정렬 / metadata.
//
//  여기서 고정하는 것:
//  1. 사용자-facing **복제 / 공유하기가 사라졌는가** (사진에 저장은 남는가)
//  2. 등록 비용이 **정책 상수 하나**에서만 나오는가 (거울 10 · 스티커 5)
//  3. 거울/스티커 **둘 다** 상점 등록 화면에 들어갈 수 있는가
//  4. **"인기 순"이 오직 downloadCount 기준**인가, tie-breaker가 결정적인가
//

import Foundation
import SwiftUI
import Testing

@testable import ggumirror

@MainActor
struct StoreActionsTests {

    // MARK: - 제거된 action

    /// 사용자가 직접 실행하는 복제/공유는 사라졌다.
    /// **Editor 캔버스의 오브젝트 복제는 다른 기능이라 남는다**(스티커 하나를 캔버스에서 복제).
    @Test("거울/스티커 action에 복제와 공유하기가 없다", arguments: [
        "MyMirrors/MyMirrorsView.swift",
        "Store/StickerStoreView.swift",
    ])
    func duplicateAndShareAreGone(file: String) throws {
        let code = Self.codeOnly(try Self.source(file))
        for banned in ["\"복제\"", "\"공유하기\"", "ShareSheet", "shareSticker", "library.duplicate"] {
            #expect(!code.contains(banned), "\(file): \(banned)가 남아 있다")
        }
    }

    /// 공유를 없애면서 사진 저장까지 지우지 않았다.
    @Test("사진에 저장은 남아 있다", arguments: [
        "MyMirrors/MyMirrorsView.swift",
        "Store/StickerStoreView.swift",
    ])
    func photoSaveSurvives(file: String) throws {
        let source = try Self.source(file)
        #expect(source.contains("\"사진에 저장\""), "\(file): 사진 저장이 사라졌다")
        #expect(source.contains("OwnContentExport.saveToPhotos"), "\(file): 저장 경로가 끊겼다")
    }

    /// 공유 시트를 띄우는 코드가 앱에 없다 — 한 줄로 되살아나지 않게 한다.
    @Test("공유 시트 presenter가 없다")
    func shareSheetIsGone() throws {
        #expect(!(try Self.source("Shared/OwnContentExport.swift")).contains("UIActivityViewController"))
        // 임시 파일 정리는 남는다 — 이전 빌드가 남긴 파일을 치워야 한다.
        #expect(try Self.source("Shared/OwnContentExport.swift").contains("cleanUpLeftovers"))
    }

    // MARK: - 등록 비용

    @Test("등록 비용은 거울 10 · 스티커 5다")
    func publishFeesAreLocked() {
        #expect(MirrorPublishPolicy.feeInShards == 10)
        #expect(StickerPublishPolicy.feeInShards == 5)
        // 스티커가 거울보다 싸다는 것이 정책이다.
        #expect(StickerPublishPolicy.feeInShards < MirrorPublishPolicy.feeInShards)
    }

    /// 화면이 숫자를 직접 적으면 정책이 바뀔 때 거짓말이 된다.
    @Test("등록 화면은 정책 상수를 쓴다", arguments: [
        ("Store/PublishMirrorView.swift", "MirrorPublishPolicy.feeInShards"),
        ("Store/PublishStickerView.swift", "StickerPublishPolicy.feeInShards"),
    ])
    func publishSheetsUseThePolicyConstant(file: String, constant: String) throws {
        let source = try Self.source(file)
        #expect(source.contains(constant), "\(file): 비용을 정책에서 읽지 않는다")
    }

    /// 과거 20조각 정책이 경제 상수로 남아 있지 않다(UI spacing의 20과 구분한다).
    @Test("옛 20조각 등록비가 없다")
    func oldTwentyShardFeeIsGone() throws {
        for file in [
            "Store/MirrorPublishDraft.swift",
            "Editor/StickerPublishDraft.swift",
            "Store/PublishMirrorView.swift",
            "Store/PublishStickerView.swift",
        ] {
            let code = Self.codeOnly(try Self.source(file))
            #expect(!code.contains("feeInShards = 20"), "\(file): 옛 정책이 남아 있다")
        }
    }

    // MARK: - 등록 진입점

    /// 두 화면 모두 **같은 문구**로 들어간다 — 하나만 다르면 사용자가 헷갈린다.
    @Test("거울/스티커 모두 상점 등록으로 들어갈 수 있다", arguments: [
        ("MyMirrors/MyMirrorsView.swift", "PublishMirrorView("),
        ("Store/StickerStoreView.swift", "PublishStickerView("),
    ])
    func bothSurfacesReachPublish(file: String, sheet: String) throws {
        let source = try Self.source(file)
        #expect(source.contains("\"상점에 등록\""), "\(file): 등록 CTA가 없다")
        #expect(source.contains("publishTarget"), "\(file): 등록 대상 상태가 없다")
        #expect(source.contains(sheet), "\(file): 기존 등록 화면을 열지 않는다 — 새 flow를 만들었나")
    }

    /// 회귀: 등록이 **동작 목록 안에만** 있어 아무도 찾지 못했다.
    /// 이제 카드 아래에 바로 보이는 버튼이 authority다.
    @Test("등록 CTA가 목록 화면에 바로 보인다", arguments: [
        "MyMirrors/MyMirrorsView.swift",
        "Store/StickerStoreView.swift",
    ])
    func publishCTAIsVisibleWithoutOpeningTheDialog(file: String) throws {
        let source = try Self.source(file)
        #expect(source.contains("func publishButton(for"), "\(file): 보이는 CTA가 없다")
        #expect(source.contains("publishButton(for:"), "\(file): CTA가 격자에 붙어 있지 않다")
    }

    /// 같은 동작을 두 곳에 두지 않는다 — 어느 쪽이 진짜인지 알 수 없어진다.
    @Test("등록은 한 곳에서만 시작한다", arguments: [
        "MyMirrors/MyMirrorsView.swift",
        "Store/StickerStoreView.swift",
    ])
    func publishHasExactlyOneEntryPoint(file: String) throws {
        let code = Self.codeOnly(try Self.source(file))
        #expect(
            !code.contains("InkDialogAction(\"상점에 등록\")"),
            "\(file): 동작 목록에도 등록이 남아 있다"
        )
    }

    /// 등록할 수 없어도 **버튼을 조용히 감추지 않는다** — 이유를 알려준다.
    @Test("등록 불가 항목은 이유를 알려준다")
    func ineligibleItemsExplainWhy() throws {
        let mirrors = try Self.source("MyMirrors/MyMirrorsView.swift")
        #expect(mirrors.contains("MirrorPublishPolicy.isEligible"), "eligibility 정책을 무시했다")
        #expect(mirrors.contains("직접 만든 거울만"), "왜 안 되는지 알려주지 않는다")

        let stickers = try Self.source("Store/StickerStoreView.swift")
        #expect(stickers.contains("canPublishToStore"), "스티커 eligibility를 무시했다")
        #expect(stickers.contains("AI로 만든 스티커는"), "왜 안 되는지 알려주지 않는다")
    }

    /// 사용자 요구: 두 상점 모두 세 가지 정렬을 바꿀 수 있어야 한다.
    /// **상품이 0개여도 정렬 UI는 보인다** — 거울 상점과 UI가 갈라지지 않는다.
    @Test("스티커 상점도 정렬 UI를 갖는다")
    func stickerStoreHasTheSameSortUI() throws {
        let source = try Self.source("Store/StickerStoreView.swift")
        #expect(source.contains("InkFilterBar(items: StoreSort.allCases"), "정렬 UI가 없다")
        #expect(source.contains("StoreSort = .default"), "기본값이 최신 순이 아니다")
    }

    /// 빈 상태는 정렬 UI **아래**에 온다 — 상품이 생겨도 구조가 바뀌지 않는다.
    @Test("빈 스티커 상점도 정렬 UI가 먼저 나온다")
    func emptyStickerStoreStillShowsSortFirst() throws {
        let source = try Self.source("Store/StickerStoreView.swift")
        guard let sortUI = source.range(of: "InkFilterBar(items: StoreSort.allCases"),
              let empty = source.range(of: "marketplace\n")
        else {
            Issue.record("정렬 UI 또는 빈 상태를 찾지 못했다")
            return
        }
        #expect(sortUI.lowerBound < empty.lowerBound, "빈 상태가 정렬 UI보다 먼저 나온다")
        // 가짜 상품을 만들지 않았다.
        #expect(source.contains("아직 등록된 스티커가 없어요"))
    }

    // MARK: - 정렬

    @Test("정렬은 네 가지이고 기본은 최신 순이다")
    func sortHasFourCasesAndLatestDefault() {
        #expect(StoreSort.allCases.count == 4)
        #expect(StoreSort.default == .latest)
        #expect(StoreSort.allCases.map(\.label) == ["최신 순", "인기 순", "좋아요 순", "가격 순"])
    }

    /// **"인기"의 기준은 다운로드 수 하나다.** 좋아요를 섞은 가중 점수를 만들지 않는다.
    @Test("인기 순은 오직 downloadCount 기준이다")
    func popularIsDownloadCountOnly() {
        // 좋아요가 압도적으로 많아도 다운로드가 적으면 뒤로 간다.
        let loved = Self.template(id: "b", downloads: 1, likes: 999)
        let downloaded = Self.template(id: "a", downloads: 2, likes: 0)

        let order = StoreSort.popular.sorted([loved, downloaded]).map(\.id)
        #expect(order == ["a", "b"], "좋아요가 인기 순에 섞였다")

        // 소스에서도 가중 점수를 금지한다.
        let code = Self.codeOnly(try! Self.source("Store/StoreCatalog.swift"))
        for banned in ["likeCount +", "+ likeCount", "score", "weight"] {
            #expect(!code.contains(banned), "인기 순에 가중치가 들어갔다 (\(banned))")
        }
    }

    @Test("최신 순은 uploadedAt 내림차순이다")
    func latestSortsByUploadDate() {
        let old = Self.template(id: "a", uploadedAt: Self.date(2026, 1, 1))
        let new = Self.template(id: "b", uploadedAt: Self.date(2026, 8, 19))
        #expect(StoreSort.latest.sorted([old, new]).map(\.id) == ["b", "a"])
    }

    @Test("업로드된 적 없는 상품은 최신 순에서 뒤로 간다")
    func neverUploadedGoesLast() {
        let uploaded = Self.template(id: "b", uploadedAt: Self.date(2020, 1, 1))
        let never = Self.template(id: "a", uploadedAt: nil)
        #expect(StoreSort.latest.sorted([never, uploaded]).map(\.id) == ["b", "a"])
    }

    @Test("좋아요 순은 likeCount 내림차순이다")
    func likesSortByLikeCount() {
        let few = Self.template(id: "a", likes: 1)
        let many = Self.template(id: "b", likes: 9)
        #expect(StoreSort.likes.sorted([few, many]).map(\.id) == ["b", "a"])
    }

    /// tie-breaker: 인기 = downloads → uploadedAt → id
    @Test("인기 순 동점은 업로드 날짜, 그 다음 id로 갈린다")
    func popularTieBreakersAreDeterministic() {
        let older = Self.template(id: "a", downloads: 5, uploadedAt: Self.date(2026, 1, 1))
        let newer = Self.template(id: "b", downloads: 5, uploadedAt: Self.date(2026, 5, 1))
        #expect(StoreSort.popular.sorted([older, newer]).map(\.id) == ["b", "a"])

        let sameEverything = [Self.template(id: "z"), Self.template(id: "a")]
        #expect(StoreSort.popular.sorted(sameEverything).map(\.id) == ["a", "z"])
    }

    /// 좋아요 tie-breaker: likes → downloads → uploadedAt → id
    @Test("좋아요 동점은 다운로드 수로 갈린다")
    func likeTieBreakerUsesDownloads() {
        let lessDownloaded = Self.template(id: "a", downloads: 1, likes: 7)
        let moreDownloaded = Self.template(id: "b", downloads: 8, likes: 7)
        #expect(StoreSort.likes.sorted([lessDownloaded, moreDownloaded]).map(\.id) == ["b", "a"])
    }

    /// 값이 전부 같아도 순서가 실행마다 흔들리면 목록이 이유 없이 재배열돼 보인다.
    @Test("모든 값이 같아도 순서가 결정적이다", arguments: StoreSort.allCases)
    func sortingIsStable(sort: StoreSort) {
        let items = ["c", "a", "b"].map { Self.template(id: $0) }
        #expect(sort.sorted(items).map(\.id) == ["a", "b", "c"])
        // 같은 입력을 다시 정렬해도 같다.
        #expect(sort.sorted(items).map(\.id) == sort.sorted(items.reversed()).map(\.id))
    }

    // MARK: - metadata

    /// 서버가 없으므로 내장 목록은 전부 0이다. 숫자를 지어내지 않는다.
    @Test("내장 목록은 count를 지어내지 않는다")
    func builtInCatalogNeverFakesCounts() {
        for template in StoreCatalog.samples {
            #expect(template.downloadCount == 0, "\(template.id): 다운로드 수를 지어냈다")
            #expect(template.likeCount == 0, "\(template.id): 좋아요 수를 지어냈다")
            #expect(template.uploadedAt == nil, "\(template.id): 업로드 날짜를 지어냈다")
        }
    }

    @Test("count는 음수가 될 수 없다")
    func countsAreNeverNegative() {
        for template in StoreCatalog.samples {
            #expect(template.downloadCount >= 0)
            #expect(template.likeCount >= 0)
        }
    }

    /// 0이라고 감추면 상품마다 metadata 폭이 달라져 목록이 들쭉날쭉해진다.
    @Test("0과 날짜 없음도 표시가 깨지지 않는다")
    func zeroValuesStillRender() {
        let empty = Self.template(id: "a")
        #expect(empty.uploadedAtLabel == "—", "날짜가 없을 때 자리가 비면 카드 폭이 달라진다")

        let uploaded = Self.template(id: "b", uploadedAt: Self.date(2026, 8, 19))
        #expect(uploaded.uploadedAtLabel != "—")
        #expect(!uploaded.uploadedAtLabel.isEmpty)
    }

    @Test("카드와 상세가 같은 metadata를 보여준다", arguments: [
        "Store/StoreView.swift",
        "Store/TemplateDetailView.swift",
    ])
    func cardAndDetailShowMetadata(file: String) throws {
        let source = try Self.source(file)
        #expect(source.contains("downloadCount"), "\(file): 다운로드 수가 없다")
        #expect(source.contains("uploadedAt"), "\(file): 업로드 날짜가 없다")

        // **좋아요 수는 내장 카드에서 뺐다**(Marketplace UX Hardening.1).
        //
        // 내장 템플릿에는 좋아요를 세는 서버 domain이 **없다.** 다운로드 수는
        // catalog 통계를 붙여 실제 값을 보여 주지만, 좋아요는 그럴 것이 없어서
        // `0`을 보여 주면 방금 고친 그 거짓말을 다시 하는 셈이다.
        //
        // 사용자가 올린 Marketplace 상품에는 좋아요가 있고 카드에 하트로 보인다.
    }

    /// 가짜 like/download mutation을 만들지 않는다 — 서버가 authority다.
    @Test("앱이 count를 올리지 않는다", arguments: [
        "Store/StoreView.swift",
        "Store/TemplateDetailView.swift",
        "Store/StoreCatalog.swift",
    ])
    func appNeverIncrementsCounts(file: String) throws {
        let code = Self.codeOnly(try Self.source(file))
        for banned in ["downloadCount +=", "likeCount +=", "downloadCount + 1", "likeCount + 1"] {
            #expect(!code.contains(banned), "\(file): 앱이 count를 올린다 (\(banned))")
        }
        #expect(!code.contains("Int.random"), "\(file): 숫자를 지어낸다")
    }

    /// 정렬 UI는 기존 필터 칩을 재사용한다 — 새 UI 언어를 만들지 않는다.
    @Test("상점에 정렬 선택 UI가 있다")
    func storeShowsSortPicker() throws {
        let source = try Self.source("Store/StoreView.swift")
        #expect(source.contains("InkFilterBar(items: StoreSort.allCases"))
        #expect(source.contains("sort.sorted("), "목록에 정렬이 적용되지 않는다")
        #expect(source.contains("StoreSort = .default"), "기본값이 최신 순이 아니다")
    }

    // MARK: - UI-P2 회귀

    @Test("등록 시트의 UI-P2 구조가 그대로다", arguments: [
        "Store/PublishMirrorView.swift",
        "Store/PublishStickerView.swift",
    ])
    func publishSheetsKeepTheirSafeAreaStructure(file: String) throws {
        let source = try Self.source(file)
        #expect(source.contains("ScrollView"))
        #expect(source.contains("inkSheetActions"), "\(file): 하단 CTA 고정이 풀렸다")
        #expect(!source.contains("InkTabBar.reservedHeight"), "\(file): 탭바를 손으로 피한다")
    }

    // MARK: - 도구

    static func template(
        id: String,
        price: Int = 0,
        downloads: Int = 0,
        likes: Int = 0,
        uploadedAt: Date? = nil
    ) -> MirrorTemplate {
        MirrorTemplate(
            id: id,
            name: id,
            creator: "꾸미러",
            price: price,
            style: MirrorStyle(frame: .white),
            downloadCount: downloads,
            likeCount: likes,
            uploadedAt: uploadedAt
        )
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(secondsFromGMT: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: components)!
    }

    static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "ggumirror")
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    static func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }
}
