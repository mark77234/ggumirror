//
//  SellerListingStateTests.swift
//  ggumirrorTests
//
//  판매자가 자기 상품에 대해 **할 수 있는 일이 상태마다 다르다.**
//
//      판매 중              상점에서 내리기 · 삭제
//      판매 중지            다시 상점에 올리기 · 삭제
//      운영 정책으로 내려감  아무것도 — 서버가 409로 거절한다
//      등록 미완료          상점에 올리기 · 삭제
//      삭제됨               끝. 목록에도 보이지 않는다
//
//  **실기기에서 보고된 문제 둘이 여기 있다:**
//
//  1. 운영자가 내린 상품이 판매자에게는 계속 `판매 중`으로 보였다.
//     `status == "published"`만 봤기 때문이다 — 상태는 그대로이고 공개만 꺼진다.
//  2. "상점에서 내리기"를 눌렀는데 다시 올릴 수 없었다. 그 버튼이 실제로는
//     **끝 상태 삭제**를 부르고 있었다(내리기 버튼 자체가 없었다).
//

import Testing
import Foundation
@testable import ggumirror

/// `func <name>`부터 **바로 다음 함수 정의 직전**까지. 길이로 자르면 그 뒤에
/// 함수가 하나 생길 때마다 테스트가 엉뚱한 코드를 보게 된다.
private func functionBody(_ source: String, _ signature: String) throws -> String {
    let start = try #require(source.range(of: signature))
    let rest = source[start.upperBound...]
    guard let next = rest.range(of: "\n    private func ") else { return String(rest) }
    return String(rest[..<next.lowerBound])
}

private func sellerSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

private func owned(
    _ id: String, status: String, moderation: String = "active",
    title: String = "내 거울", type: String = "mirror"
) -> MarketplaceOwnedListing {
    MarketplaceOwnedListing(
        id: id, contentType: type, title: title, description: "",
        priceShards: 0, status: status, downloadCount: 0, likeCount: 0,
        publishedAt: nil, sourceContentId: "local-\(id)", moderationStatus: moderation
    )
}

// MARK: - 공개 여부

@Suite("판매자 화면과 운영 화면이 같은 것을 말한다")
struct SellerVisibilityTests {

    @Test("`판매 중`은 실제로 공개된 것만이다")
    func liveMeansPubliclyVisible() {
        #expect(owned("a", status: "published").isPubliclyVisible)
        // **실기기 버그**: 운영자가 내려도 status는 `published`로 남는다.
        #expect(!owned("b", status: "published", moderation: "removed").isPubliclyVisible)
        #expect(!owned("c", status: "unlisted").isPubliclyVisible)
        #expect(!owned("d", status: "draft").isPubliclyVisible)
        #expect(!owned("e", status: "deleted").isPubliclyVisible)
    }

    @Test("운영 화면과 조건이 같다")
    func oneVisibilityRuleForBothScreens() throws {
        // 두 화면이 각자 조건을 적으면 반드시 갈라진다. 같은 모양을 쓴다.
        for path in [
            "ggumirror/Backend/MarketplaceAPI.swift",
            "ggumirror/Backend/BackendClient+Admin.swift",
        ] {
            #expect(try sellerSource(path).contains("var isPubliclyVisible: Bool"), "\(path)")
        }
        // 판매자 목록이 status 문자열을 직접 보고 `판매 중`을 정하지 않는다.
        let sales = try sellerSource("ggumirror/Store/MySalesSection.swift")
        #expect(sales.contains("store.myListings.filter(\\.isPubliclyVisible)"))
        #expect(!sales.contains("filter(\\.isPublished)"))
    }

    @Test("상태 문구가 운영 조치를 먼저 말한다")
    func theLabelNamesTheModeration() {
        #expect(owned("a", status: "published").statusLabel == "판매 중")
        #expect(
            owned("b", status: "published", moderation: "removed").statusLabel
                == "운영 정책으로 내려감"
        )
        #expect(owned("c", status: "unlisted").statusLabel == "판매 중지")
        #expect(owned("d", status: "draft").statusLabel == "등록 미완료")
        // 판매자가 삭제한 것은 운영 조치가 붙어 있어도 `삭제됨`이다 — 끝 상태가 먼저다.
        #expect(owned("e", status: "deleted", moderation: "removed").statusLabel == "삭제됨")
    }

    @Test("모르는 상태를 목록에서 통째로 버리지 않는다")
    func unknownStatusStillShows() {
        #expect(owned("x", status: "quarantined").statusLabel == "알 수 없음")
    }
}

// MARK: - 구획

@Suite("내 판매는 네 구획이다")
struct MySalesGroupingTests {

    @Test("구획이 서로를 침범하지 않는다")
    func eachStateHasOneHome() throws {
        let sales = try sellerSource("ggumirror/Store/MySalesSection.swift")

        #expect(sales.contains("store.myListings.filter(\\.isPubliclyVisible)"))
        #expect(sales.contains("$0.isModerated && !$0.isDeleted"))
        #expect(sales.contains("store.myListings.filter(\\.isUnlisted)"))
        #expect(sales.contains("store.myListings.filter(\\.isDraft)"))

        // 네 구획 이름이 전부 있다.
        for title in ["판매 중", "등록 미완료", "운영 정책으로 내려감", "판매 중지"] {
            #expect(sales.contains("\"\(title)\""), "\(title)")
        }
    }

    @Test("운영자가 내린 것과 판매자가 내린 것을 섞지 않는다")
    func moderatedAndRetiredAreDifferentGroups() {
        let moderated = owned("a", status: "published", moderation: "removed")
        let retired = owned("b", status: "unlisted")

        // 하나는 `isModerated`, 하나는 `isUnlisted`다 — 겹치는 항목이 없다.
        #expect(moderated.isModerated && !moderated.isUnlisted)
        #expect(retired.isUnlisted && !retired.isModerated)
    }

    @Test("삭제된 것은 어느 구획에도 없다")
    func deletedStaysOutOfEveryGroup() {
        let gone = owned("a", status: "deleted")
        #expect(!gone.isPubliclyVisible)
        #expect(!gone.isUnlisted)
        #expect(!gone.isDraft)
        #expect(gone.isDeleted)
    }

    @Test("구획마다 무엇을 할 수 있는지 한 줄로 말한다")
    func eachGroupExplainsItself() throws {
        let sales = try sellerSource("ggumirror/Store/MySalesSection.swift")
        #expect(sales.contains("다시 올릴 수 없어요"))
        #expect(sales.contains("다시 올릴 수 있어요"))
        #expect(sales.contains("이어서 올릴 수 있어요"))
    }
}

// MARK: - 동작

@Suite("내리기 · 삭제 · 운영 조치는 서로 다른 동작이다")
struct SellerActionTests {

    @Test("판매 중인 상품의 주 동작은 삭제가 아니다")
    func theMainActionIsUnpublishNotDelete() throws {
        // **실기기 버그**: 판매 중인 상품의 유일한 동작이 `삭제`였다.
        // "잠깐 내려 두려고" 누른 판매자가 다시 올릴 수 없게 됐다.
        let sales = try sellerSource("ggumirror/Store/MySalesSection.swift")
        let body = try functionBody(sales, "private func action(for listing:")

        let visible = try #require(body.range(of: "listing.isPubliclyVisible"))
        let unpublish = try #require(body.range(of: "\"상점에서 내리기\""))
        #expect(visible.lowerBound < unpublish.lowerBound)
        // 삭제는 남지만 **주 동작 자리가 아니다.**
        #expect(!body.contains("\"삭제\""))
        #expect(sales.contains("private func deleteAction(for listing:"))
    }

    @Test("판매 중지는 다시 올릴 수 있다")
    func retiredCanBeRepublished() throws {
        let sales = try sellerSource("ggumirror/Store/MySalesSection.swift")
        #expect(sales.contains("\"다시 상점에 올리기\""))
        // 같은 listing을 그대로 올린다 — 새 snapshot도 새 listing도 만들지 않는다.
        #expect(sales.contains("await resume(listing)"))
        #expect(!sales.contains("createSnapshot"))
        #expect(!sales.contains("createDraft"))
    }

    @Test("운영자가 내린 것에는 버튼을 주지 않는다")
    func moderatedGetsNoSellerAction() throws {
        let sales = try sellerSource("ggumirror/Store/MySalesSection.swift")
        let body = try functionBody(sales, "private func action(for listing:")

        // 이 판정이 **다른 어떤 버튼보다 먼저** 나온다 — 눌러도 실패할 버튼을
        // 보여 주지 않는다(서버가 409로 거절한다).
        let guardLine = try #require(body.range(of: "listing.isModerated && !listing.isDeleted"))
        let firstButton = try #require(body.range(of: "MarketplaceCardAction("))
        #expect(guardLine.lowerBound < firstButton.lowerBound)
    }

    @Test("내리기가 삭제 endpoint를 부르지 않는다")
    func unpublishIsNotDelete() throws {
        let sales = try sellerSource("ggumirror/Store/MySalesSection.swift")
        let body = try functionBody(sales, "private func unpublish(_ listing:")

        #expect(body.contains("store.unpublish(listingID:"))
        #expect(!body.contains("store.delete("))
    }

    @Test("삭제는 확인을 받고 나서만 실행한다")
    func deleteAsksFirst() throws {
        let sales = try sellerSource("ggumirror/Store/MySalesSection.swift")
        let body = try functionBody(sales, "private func deleteAction(for listing:")

        // 누르면 바로 지우지 않고 확인 창을 연다.
        #expect(body.contains("pendingDelete = listing"))
        #expect(!body.contains("await delete("))
        // 확인 창이 **내리기와 다르다는 것**을 말한다.
        #expect(sales.contains("되돌릴 수 없어요"))
        #expect(sales.contains("`상점에서 내리기`를 눌러 주세요"))
    }

    @Test("이미 삭제된 것에는 삭제를 주지 않는다")
    func deletedGetsNoDeleteButton() throws {
        let sales = try sellerSource("ggumirror/Store/MySalesSection.swift")
        #expect(
            try functionBody(sales, "private func deleteAction(for listing:")
                .contains("!listing.isDeleted")
        )
    }

    @Test("세 동작이 각자의 통로를 쓴다")
    func threeDistinctBackendCalls() throws {
        let store = try sellerSource("ggumirror/Store/MarketplaceStore.swift")
        // 합쳐지지 않았다 — 하나가 다른 하나를 부르지 않는다.
        #expect(store.contains("func unpublish(listingID:"))
        #expect(store.contains("func delete(listingID:"))
        #expect(store.contains("func republish("))
    }
}

// MARK: - 등록 미완료가 이유를 말한다

@Suite("등록 미완료는 왜 미완료인지 말한다")
struct IncompletePublishReasonTests {

    @Test("실패 이유를 generic하게 삼키지 않는다")
    func theReasonSurvivesTheDialog() throws {
        let store = try sellerSource("ggumirror/Store/MarketplaceStore.swift")
        // 실패한 등록의 이유를 그 listing에 붙여 둔다.
        #expect(store.contains("func publishFailure(for listingID: String) -> MarketplaceFailure?"))
        #expect(store.contains("publishFailures[listingID] = error"))
        // 성공하면 지운다 — 낡은 이유가 남으면 그것도 거짓말이다.
        #expect(store.contains("publishFailures[listingID] = nil"))

        let sales = try sellerSource("ggumirror/Store/MySalesSection.swift")
        #expect(sales.contains("store.publishFailure(for: listing.id)?.message"))
    }

    @Test("서버 schema를 넓히지 않았다")
    func noNewServerField() throws {
        // draft 문서에 실패 이유를 적는 자리를 만들지 않았다 — 그것 하나 때문에
        // 경제 전체가 쓰는 schema를 넓히지 않는다.
        let api = try sellerSource("ggumirror/Backend/MarketplaceAPI.swift")
        #expect(!api.contains("failureReason"))
    }

    @Test("이름이 겹친 것과 조각이 모자란 것을 다르게 말한다")
    func distinctFailuresReadDifferently() {
        let messages = Set([
            MarketplaceFailure.titleTaken.message,
            MarketplaceFailure.insufficientShards.message,
            MarketplaceFailure.moderated.message,
            MarketplaceFailure.invalidPackage.message,
        ])
        #expect(messages.count == 4)
        #expect(MarketplaceFailure.titleTaken.message.contains("이름"))
    }

    @Test("서버가 준 409를 각각 알아본다")
    func everyConflictIsMapped() {
        func decoded(_ detail: String) -> MarketplaceFailure {
            MarketplaceFailure.from(
                status: 409, data: Data("{\"detail\":\"\(detail)\"}".utf8)
            )
        }
        #expect(decoded("listing title is already taken") == .titleTaken)
        #expect(decoded("not enough shards") == .insufficientShards)
        #expect(decoded("listing was removed by an operator") == .moderated)
        #expect(decoded("listing cannot be published") == .cannotPublish)
    }
}

// MARK: - AI 거울도 같은 통로로 올라간다

@Suite("AI 거울과 손으로 만든 거울이 같은 통로를 쓴다")
@MainActor
struct AIMirrorPublishParityTests {

    private func mirror(_ id: String, source: MirrorCreationSource?) -> MyMirror {
        MyMirror(
            id: id, name: "내 거울 \(id)", origin: .made,
            style: BasicMirror.cream.style, creationSource: source
        )
    }

    @Test("AI 거울도 상점에 올릴 수 있다")
    func aiMirrorsAreEligible() {
        // **출처로 막지 않는다.** 내가 만든 거울이면 올릴 수 있다.
        #expect(MirrorPublishPolicy.isEligible(mirror("a", source: .aiGenerated)))
        #expect(MirrorPublishPolicy.isEligible(mirror("b", source: nil)))
        // 상점에서 받은 것은 여전히 되팔 수 없다.
        var bought = mirror("c", source: nil)
        bought.origin = .purchased
        #expect(!MirrorPublishPolicy.isEligible(bought))
    }

    @Test("등록 경로에 AI 분기가 없다")
    func noAISpecificPipeline() throws {
        // AI 전용 marketplace 통로를 만들지 않았다 — 하나가 갈라지면 한쪽만 고쳐진다.
        for path in [
            "ggumirror/Store/PublishMirrorView.swift",
            "ggumirror/Store/MarketplaceStore.swift",
            "ggumirror/Store/MirrorPublishDraft.swift",
        ] {
            let code = try sellerSource(path)
            #expect(!code.contains("aiGenerated"), "\(path)")
            #expect(!code.contains("creationSource"), "\(path)")
        }
    }

    @Test("AI 거울은 외부 디자인 한 장을 참조한다")
    func theGeneratedArtworkIsAnAsset() throws {
        let view = try sellerSource("ggumirror/MyMirrors/AIMirrorView.swift")
        // 그림은 **참조 id로만** 들어간다. 저장 경로가 손으로 만든 거울과 같다.
        #expect(view.contains("ImportedArtworkAssetStore.shared.register(image)"))
        #expect(view.contains("design.importedArtworks = [artwork]"))
        // 저장은 기존 서랍 API 하나다 — AI 전용 저장 통로가 없다.
        #expect(view.contains("library.save("))
    }

    @Test("등록 검사가 그 그림을 실제로 요구한다")
    func publishRefusesWhenTheArtworkIsGone() {
        // 파일이 사라졌으면 **등록으로 넘기지 않는다.** 구매자가 빈 거울을 받는
        // 것보다 판매자가 지금 아는 편이 낫다.
        #expect(MirrorPublishIssue.artworkAssetMissing.message.contains("외부 디자인"))
        #expect(MirrorPublishIssue.allCases.contains(.artworkAssetMissing))
    }

    @Test("manifest가 그림을 빠뜨리지 않는다")
    func theManifestListsTheArtwork() {
        let id = UUID()
        var design = mirror("a", source: .aiGenerated)
        design.importedArtworks = [ImportedArtworkObject(assetID: id)]

        let manifest = MirrorPublishManifest(design)
        #expect(manifest.importedArtworkAssetIDs == [id])
        #expect(manifest.assetCount == 1)
        // 사진이 아니므로 사진 공개 안내는 필요 없다.
        #expect(!manifest.needsPhotoPrivacyNotice)
        #expect(manifest.needsArtworkRightsNotice)
    }

    @Test("등록비는 종류가 아니라 정책이 정한다")
    func theFeeIsTheSameForBoth() {
        // AI로 만들었다고 등록비가 달라지지 않는다.
        #expect(MirrorPublishPolicy.feeInShards == 10)
    }
}

// MARK: - 생성 거절 문구

@Suite("만들지 못한 이유를 아는 만큼만 말한다")
struct AIRefusalCopyTests {

    @Test("저작권이라고 단정하지 않는다")
    func weDoNotClaimCopyright() {
        let message = AIMirrorFailure.safetyRejected.message
        // provider가 돌려주는 것은 `moderation_blocked` 하나이고 이유를 나누지 않는다.
        // 우리가 이유를 지어내면 우리가 모르는 것을 아는 척하는 것이다.
        #expect(!message.contains("저작권"))
        #expect(!message.contains("상표"))
        #expect(message.contains("이미지 생성 정책"))
    }

    @Test("무엇을 바꾸면 되는지 말한다")
    func itSaysWhatToDoInstead() {
        let message = AIMirrorFailure.safetyRejected.message
        #expect(message.contains("색상"))
        #expect(message.contains("분위기"))
        #expect(message.contains("패턴"))
    }

    @Test("앱이 프롬프트를 자기 마음대로 바꾸지 않는다")
    func thePromptIsNeverRewritten() throws {
        let view = try sellerSource("ggumirror/MyMirrors/AIMirrorView.swift")
        // 우회용 치환·금지어 목록이 없다. 정규화는 **공백과 길이**뿐이다.
        for banned in ["replacingOccurrences", "blocklist", "bannedWords", "스파이더맨"] {
            #expect(!view.contains(banned), "\(banned)")
        }
        let normalize = try #require(view.range(of: "static func normalized(_ raw: String)"))
        let body = String(view[normalize.upperBound...].prefix(300))
        #expect(body.contains("trimmingCharacters"))
        #expect(body.contains("prefix(maxLength)"))
    }

    @Test("거절과 일시 장애를 다르게 말한다")
    func refusalIsNotAnOutage() {
        // 다시 시도하면 되는 것과 되지 않는 것을 뭉치지 않는다.
        #expect(AIMirrorFailure.safetyRejected.message != AIMirrorFailure.unavailable.message)
        #expect(AIMirrorFailure.unavailable.message.contains("잠시 뒤"))
        #expect(!AIMirrorFailure.safetyRejected.message.contains("잠시 뒤"))
    }
}
