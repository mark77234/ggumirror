//
//  MirrorNamingTests.swift
//  ggumirrorTests
//
//  거울 카드의 **자리**와 거울 **이름**을 고정한다.
//
//  두 가지는 별개로 보이지만 같은 실기기 QA에서 나왔다 — 목록이 들쭉날쭉했고,
//  거울에 이름을 붙일 방법이 없었다.
//

import Testing
import Foundation
import SwiftUI
@testable import ggumirror

private func source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

@Suite("상점 거울 카드는 데이터와 무관하게 같은 크기다")
struct StoreMirrorCardGeometryTests {

    private let cardPath = "ggumirror/Store/StoreMirrorCard.swift"

    @Test("비율은 제품 상수를 재사용한다")
    func ratioIsNotDuplicated() throws {
        // 새 비율 상수를 만들면 거울마다 다른 모양이 생긴다.
        // 카드는 비율을 **직접 알지 않고** 종류별 authority에게 묻는다.
        #expect(ListingPreviewStyle.aspectRatio(for: "mirror") == MirrorStyle.aspectRatio)
        let card = try source(cardPath)
        #expect(card.contains("ListingPreviewStyle.aspectRatio(for: model.contentType)"))
        for magic in ["0.46", "9 / 19.5", "9.0 / 19.5"] {
            #expect(!card.contains(magic), "카드가 비율을 다시 적었다: \(magic)")
        }
    }

    @Test("통계 줄 높이가 하트 유무와 무관하다")
    func metadataHeightIsFixed() throws {
        // 원인이었던 자리다: 남의 상품에만 하트 Button이 있고 그 tap target이
        // 44pt여서 그 카드만 줄이 부풀었다.
        #expect(StoreMirrorCardMetrics.metadataHeight == InkTapTarget.minimum)
        let card = try source(cardPath)
        #expect(card.contains("frame(height: StoreMirrorCardMetrics.metadataHeight)"))
        // 하트가 자기 높이를 다시 정하지 않는다.
        #expect(!card.contains("minHeight: 44"))
    }

    @Test("하트는 여전히 44pt로 눌린다")
    func heartKeepsItsTapTarget() throws {
        let card = try source(cardPath)
        // 줄이 44pt이고 Button이 그 높이를 꽉 채운다.
        #expect(card.contains("minWidth: InkTapTarget.minimum"))
        #expect(card.contains("maxHeight: .infinity"))
        #expect(card.contains(".contentShape(.rect)"))
    }

    @Test("칸 크기를 카드가 정한다 — 그림 원본 크기가 아니다")
    func previewGeometryIsOwnedByTheCard() throws {
        let card = try source(cardPath)
        // 카드가 직접 비율을 걸어 준다. 넘겨받은 그림이 높이를 정하지 못한다.
        #expect(card.contains("ListingPreviewStyle.aspectRatio(for: model.contentType), contentMode: .fit"))
        #expect(card.contains(".clipped()"))
        #expect(card.contains("frame(maxWidth: .infinity)"))
    }

    @Test("제목은 한 줄이다")
    func titleNeverWraps() throws {
        let card = try source(cardPath)
        #expect(card.contains(".lineLimit(1)"))
        #expect(card.contains(".truncationMode(.tail)"))
    }

    @Test("없는 값을 0으로 지어내지 않는다")
    func absentStatsAreNotFaked() throws {
        // 자리는 맞추되 숫자는 지어내지 않는다.
        let card = try source(cardPath)
        #expect(card.contains("if let downloadCount = model.downloadCount"))
        let model = StoreMirrorCardModel(
            title: "제목", subtitle: nil, price: 0, downloadCount: nil, footnote: "—"
        )
        #expect(model.downloadCount == nil)
        #expect(model.subtitle == nil)
    }

    @Test("스티커 카드는 건드리지 않았다")
    func stickerCardIsUntouched() throws {
        // 이번 계약은 거울 카드만이다.
        #expect(ListingPreviewStyle.aspectRatio(for: "sticker") == 1)
        #expect(ListingPreviewStyle.contentMode(for: "sticker") == .fit)
        #expect(ListingPreviewStyle.aspectRatio(for: "mirror") == MirrorStyle.aspectRatio)
    }
}

@Suite("거울 이름")
@MainActor
struct MirrorNamingTests {

    /// 거울 두 장을 담은 라이브러리. 기본 라이브러리는 **비어 있다**.
    private func library() -> MirrorLibrary {
        let library = MirrorLibrary()
        for template in StoreCatalog.samples.prefix(2) {
            _ = library.acquire(template)
        }
        return library
    }

    @Test("이름을 바꾸면 목록에 반영된다")
    func renameChangesTheName() {
        let library = library()
        let mirror = library.mirrors[0]
        #expect(library.rename(mirror.id, to: "테스트 거울") == .renamed("테스트 거울"))
        #expect(library.mirrors.first { $0.id == mirror.id }?.name == "테스트 거울")
    }

    @Test("id는 바뀌지 않고 거울이 늘지도 않는다")
    func renameKeepsIdentity() {
        let library = library()
        let before = library.mirrors.count
        let mirror = library.mirrors[0]
        _ = library.rename(mirror.id, to: "새 이름")
        #expect(library.mirrors.count == before)
        #expect(library.mirrors.contains { $0.id == mirror.id })
    }

    @Test("앞뒤 공백을 다듬는다")
    func nameIsTrimmed() {
        let library = library()
        let id = library.mirrors[0].id
        #expect(library.rename(id, to: "  가운데  ") == .renamed("가운데"))
    }

    @Test("빈 이름과 공백뿐인 이름은 거절한다")
    func emptyNameIsRejected() {
        let library = library()
        let id = library.mirrors[0].id
        let original = library.mirrors[0].name
        #expect(library.rename(id, to: "") == .invalidName)
        #expect(library.rename(id, to: "   \n ") == .invalidName)
        #expect(library.mirrors[0].name == original)
    }

    @Test("너무 긴 이름은 자른다 — 글자 기준이다")
    func nameIsCapped() {
        let library = library()
        let id = library.mirrors[0].id
        // 이모지 하나가 여러 byte라도 **한 글자**로 센다.
        let long = String(repeating: "가", count: 100)
        guard case .renamed(let name) = library.rename(id, to: long) else {
            Issue.record("이름이 저장되지 않았다"); return
        }
        #expect(name.count == MirrorStoragePolicy.maxNameLength)
    }

    @Test("같은 이름을 여러 개 허용한다")
    func duplicateNamesAreAllowed() {
        let library = library()
        let first = library.mirrors[0].id
        let second = library.mirrors[1].id
        _ = library.rename(first, to: "같은 이름")
        _ = library.rename(second, to: "같은 이름")
        // 이름은 identity가 아니다 — id가 authority다.
        #expect(library.mirrors.filter { $0.name == "같은 이름" }.count == 2)
        #expect(first != second)
    }

    @Test("없는 거울은 조용히 만들지 않는다")
    func unknownMirrorIsNotCreated() {
        let library = library()
        let before = library.mirrors.count
        #expect(library.rename("없는-id", to: "이름") == .notFound)
        #expect(library.mirrors.count == before)
    }

    @Test("이름이 없는 예전 파일도 읽힌다")
    func legacyFileWithoutNameStillDecodes() throws {
        // 이름 하나 때문에 거울을 통째로 잃으면 안 된다.
        let style = try JSONEncoder().encode(BasicMirror.white.style)
        let json = """
        {"id":"legacy-1","style":\(String(data: style, encoding: .utf8)!)}
        """
        let mirror = try JSONDecoder().decode(MyMirror.self, from: Data(json.utf8))
        #expect(mirror.id == "legacy-1")
        #expect(mirror.name == MirrorStoragePolicy.fallbackName)
    }
}

@Suite("판매 중인 거울은 이름을 바꿀 수 없다")
struct MirrorRenameLockTests {

    private func availability(
        signedIn: Bool = true, hint: Bool = false, known: Bool = true, published: Bool = false
    ) -> MirrorRenameAvailability {
        MirrorRenamePolicy.availability(
            isSignedIn: signedIn, hasSellerLinkHint: hint,
            sellerListingsAreKnown: known, isPublishedOriginal: published
        )
    }

    @Test("판매 중인 원본은 잠긴다")
    func publishedOriginalIsLocked() {
        #expect(availability(published: true) == .lockedPublished)
        #expect(availability(published: true).message == "판매 중인 거울은 이름을 바꿀 수 없어요.")
    }

    @Test("등록 미완료 · 판매 중지 · 삭제는 바꿀 수 있다")
    func nonPublishedSourcesAreAllowed() {
        // 서버 목록을 받아 왔고 판매 중 목록에 없다 = 공개 상점에 걸려 있지 않다.
        #expect(availability(hint: true, known: true, published: false) == .allowed)
    }

    @Test("상점과 무관한 내 거울은 그냥 바꿀 수 있다")
    func plainLocalMirrorIsAllowed() {
        #expect(availability(hint: false, known: true) == .allowed)
    }

    @Test("받아 온 복사본도 바꿀 수 있다")
    func purchasedAndBuiltInCopiesAreAllowed() {
        // 내 기기의 복사본이다 — 원 판매자의 상품이 아니다.
        #expect(availability(hint: false, known: true, published: false) == .allowed)
    }

    @Test("판매 상태를 모르면 잠시 막는다")
    func unknownSellerStatusIsBlocked() {
        let result = availability(hint: true, known: false)
        #expect(result == .unknownSellerStatus)
        #expect(result.message == "판매 상태를 확인한 뒤 다시 시도해 주세요.")
    }

    @Test("오프라인이어도 평범한 내 거울은 바꿀 수 있다")
    func offlineDoesNotBlockOrdinaryMirrors() {
        // 올린 적 있다는 흔적이 없으면 판매 중일 수 없다.
        #expect(availability(hint: false, known: false) == .allowed)
    }

    @Test("로그아웃 서랍에는 판매자 상품이 없다")
    func guestCanAlwaysRename() {
        #expect(availability(signedIn: false, hint: true, known: false) == .allowed)
    }

    @Test("저장 직전에 다시 확인한다")
    func statusIsRecheckedBeforeSaving() throws {
        let view = try source("ggumirror/MyMirrors/MyMirrorsView.swift")
        // 창을 열어 둔 사이에 등록이 끝났을 수 있다.
        #expect(view.contains("private func commitRename"))
        #expect(view.components(separatedBy: "renameAvailability(mirror)").count - 1 >= 2)
    }

    @Test("판매 여부는 stable id로 판단한다")
    func lockUsesSourceIdentityNotTitle() throws {
        let view = try source("ggumirror/MyMirrors/MyMirrorsView.swift")
        #expect(view.contains("sellingListing(\n                forContentID: mirror.id"))
        // 제목으로 맞추지 않는다.
        #expect(!view.contains("first { $0.title == mirror.name }"))
    }
}

@Suite("이름 변경은 상점을 건드리지 않는다")
struct MirrorRenameIntegrityTests {

    @Test("이름 변경 경로에 서버 호출이 없다")
    func renameIsLocalOnly() throws {
        let policy = try source("ggumirror/Shared/MirrorRenamePolicy.swift")
        for forbidden in ["backend", "purchase", "publish", "delete", "wallet", "ownership"] {
            #expect(!policy.contains(forbidden), "정책이 \(forbidden)를 부른다")
        }
        let library = try source("ggumirror/Shared/MirrorSampleData.swift")
        let start = try #require(library.range(of: "func rename(")).upperBound
        let end = try #require(
            library.range(of: "func willCreateNewMirror", range: start..<library.endIndex)
        ).lowerBound
        let body = String(library[start..<end])
        for forbidden in ["backend", "await", "listing", "PATCH", "wallet", "ledger"] {
            #expect(!body.contains(forbidden), "rename이 \(forbidden)를 건드린다")
        }
        // 바꾸는 것은 이름 하나이고 저장뿐이다.
        #expect(body.contains("mirrors[index].name = name"))
        #expect(body.contains("persist()"))
    }

    @Test("판매 목록을 받아 왔는지 구분한다")
    func loadedAndEmptyAreDifferent() throws {
        let store = try source("ggumirror/Store/MarketplaceStore.swift")
        // 빈 목록과 못 받은 것을 같게 보면 판매 중인 거울을 잠그지 못한다.
        #expect(store.contains("myListingsAreKnown"))
    }
}
