//
//  StickerRenameTests.swift
//  ggumirrorTests
//
//  **거울과 스티커는 같은 이름 규칙을 쓴다.**
//
//  이름은 이 기기의 표시용 값이고, Marketplace 상품명은 서버의 별개 authority다.
//  그래서 산 것을 내 마음대로 불러도 상점의 상품명은 그대로다.
//
//  단 하나 잠기는 것은 **지금 상점에서 팔리고 있는 원본**이다.
//  판단은 서버가 준 `sourceContentId`로 한다 — 이름이나 그림이 닮았다고 잠그지 않는다.
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

@Suite("스티커 이름")
@MainActor
struct StickerRenameTests {

    private func withLibrary(_ body: (StickerLibrary, StickerProjectStore) throws -> Void) rethrows {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-a3-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = StickerProjectStore(root: root)
        defer {
            store.flush()
            try? FileManager().removeItem(at: root)
        }
        try body(StickerLibrary(store: store), store)
    }

    /// **`save`를 쓰지 않는다.** 그 경로는 사진 asset 전역 저장소
    /// (`PhotoStickerAssetStore.shared`)를 지나는데, 다른 suite가 같은 전역을
    /// 자기 임시 폴더로 갈아 끼우기 때문에 나란히 돌면 서로를 깨뜨린다.
    /// 이름만 시험하는 데는 프로젝트를 그대로 담으면 충분하다.
    private func seed(_ library: StickerLibrary, name: String = "내 스티커") -> StickerProject? {
        library.adopt(StickerProject(id: "s-\(UUID().uuidString)", name: name))
    }

    @Test("이름을 바꾸면 목록에 반영된다")
    func renameChangesTheName() throws {
        try withLibrary { library, _ in
            let project = try #require(seed(library))
            #expect(library.rename(project.id, to: "새 이름") == .renamed("새 이름"))
            #expect(library.projects.first { $0.id == project.id }?.name == "새 이름")
        }
    }

    @Test("id는 바뀌지 않고 스티커가 늘지도 않는다")
    func renameKeepsIdentity() throws {
        try withLibrary { library, _ in
            let project = try #require(seed(library))
            let before = library.projects.count
            _ = library.rename(project.id, to: "다른 이름")
            #expect(library.projects.count == before)
            #expect(library.projects.contains { $0.id == project.id })
        }
    }

    @Test("앞뒤 공백을 다듬는다")
    func trimsWhitespace() throws {
        try withLibrary { library, _ in
            let project = try #require(seed(library))
            #expect(library.rename(project.id, to: "  가운데  ") == .renamed("가운데"))
        }
    }

    @Test("빈 이름은 거절한다")
    func rejectsEmptyName() throws {
        try withLibrary { library, _ in
            let project = try #require(seed(library))
            let original = project.name
            #expect(library.rename(project.id, to: "   ") == .invalidName)
            #expect(library.projects.first { $0.id == project.id }?.name == original)
        }
    }

    @Test("같은 이름을 여러 개 허용한다")
    func duplicateNamesAreAllowed() throws {
        try withLibrary { library, _ in
            let first = try #require(seed(library, name: "하나"))
            let second = try #require(seed(library, name: "둘"))
            _ = library.rename(first.id, to: "같은 이름")
            _ = library.rename(second.id, to: "같은 이름")
            // 이름은 identity가 아니다 — id가 authority다.
            #expect(library.projects.filter { $0.name == "같은 이름" }.count == 2)
            #expect(first.id != second.id)
        }
    }

    @Test("없는 스티커는 조용히 만들지 않는다")
    func unknownProjectIsNotCreated() throws {
        try withLibrary { library, _ in
            let before = library.projects.count
            #expect(library.rename("없는-id", to: "이름") == .notFound)
            #expect(library.projects.count == before)
        }
    }

    @Test("다시 열어도 이름이 남는다")
    func renamePersists() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-a3p-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager().removeItem(at: root) }

        let store = StickerProjectStore(root: root)
        let library = StickerLibrary(store: store)
        let seeded = try #require(library.adopt(StickerProject(id: "s1", name: "처음")))
        let id = seeded.id
        _ = library.rename(id, to: "바꾼 이름")
        store.flush()

        // 앱을 다시 켠 셈이다.
        let reopened = StickerLibrary(store: StickerProjectStore(root: root))
        #expect(reopened.projects.first { $0.id == id }?.name == "바꾼 이름")
    }
}

@Suite("거울과 스티커가 같은 정책을 쓴다")
struct SharedRenamePolicyTests {

    private func availability(
        signedIn: Bool = true, hint: Bool = false, known: Bool = true, published: Bool = false
    ) -> MirrorRenameAvailability {
        MirrorRenamePolicy.availability(
            isSignedIn: signedIn, hasSellerLinkHint: hint,
            sellerListingsAreKnown: known, isPublishedOriginal: published
        )
    }

    @Test("판매 중인 원본은 둘 다 잠긴다")
    func publishedOriginalLockedForBoth() {
        let locked = availability(published: true)
        #expect(locked == .lockedPublished)
        #expect(locked.message(for: .mirror) == "판매 중인 거울은 이름을 바꿀 수 없어요.")
        #expect(locked.message(for: .sticker) == "판매 중인 스티커는 이름을 바꿀 수 없어요.")
    }

    @Test("등록 미완료 · 판매 중지 · 삭제는 둘 다 허용")
    func nonPublishedAllowedForBoth() {
        #expect(availability(hint: true, known: true, published: false) == .allowed)
    }

    @Test("받아 온 복사본은 둘 다 허용")
    func copiesAllowedForBoth() {
        // 산 것도 내장에서 받은 것도 내 기기의 복사본이다.
        #expect(availability(hint: false, known: true) == .allowed)
    }

    @Test("판매 상태를 모르면 둘 다 잠시 막는다")
    func unknownStatusBlocksBoth() {
        let unknown = availability(hint: true, known: false)
        #expect(unknown == .unknownSellerStatus)
        // 문구는 종류와 무관하게 같다.
        #expect(unknown.message(for: .mirror) == unknown.message(for: .sticker))
    }

    @Test("오프라인이어도 평범한 작업물은 바꿀 수 있다")
    func offlineDoesNotBlockOrdinaryAssets() {
        #expect(availability(hint: false, known: false) == .allowed)
    }

    @Test("종류는 서버 계약과 같은 문자열을 쓴다")
    func contentTypeMatchesTheServer() {
        #expect(RenameableAssetKind.mirror.contentType == "mirror")
        #expect(RenameableAssetKind.sticker.contentType == "sticker")
    }

    @Test("스티커도 stable id로 판단한다")
    func stickerLockUsesSourceIdentity() throws {
        let view = try source("ggumirror/Store/StickerStoreView.swift")
        #expect(view.contains("forContentID: project.id"))
        #expect(view.contains("RenameableAssetKind.sticker.contentType"))
        // 이름이나 제목으로 맞추지 않는다.
        #expect(!view.contains("$0.title == project.name"))
    }

    @Test("스티커도 저장 직전에 다시 확인한다")
    func stickerRechecksBeforeSaving() throws {
        let view = try source("ggumirror/Store/StickerStoreView.swift")
        #expect(view.contains("private func commitRename"))
        #expect(view.components(separatedBy: "renameAvailability(project)").count - 1 >= 2)
    }

    @Test("거울 정책은 그대로다")
    func mirrorPolicyIsUnchanged() throws {
        let view = try source("ggumirror/MyMirrors/MyMirrorsView.swift")
        // A1/지난 phase의 계약이 그대로 있다.
        #expect(view.contains("private func commitRename"))
        #expect(view.contains("forContentID: mirror.id"))
    }
}

@Suite("이름 변경은 상점을 건드리지 않는다")
struct StickerRenameIntegrityTests {

    @Test("스티커 이름 변경 경로에 서버 호출이 없다")
    func renameIsLocalOnly() throws {
        let store = try source("ggumirror/Editor/StickerProjectStore.swift")
        let start = try #require(store.range(of: "func rename(_ projectID:")).upperBound
        let end = try #require(
            store.range(of: "func duplicate", range: start..<store.endIndex)
        ).lowerBound
        let body = String(store[start..<end])
        for forbidden in ["backend", "await", "listing", "wallet", "ledger", "ownership"] {
            #expect(!body.contains(forbidden), "rename이 \(forbidden)를 건드린다")
        }
        // 바꾸는 것은 이름 하나이고 저장뿐이다.
        #expect(body.contains("projects[index].name = name"))
        #expect(body.contains("persist()"))
    }

    @Test("상품명을 따라 바꾸지 않는다")
    func listingTitleIsNeverTouched() throws {
        let view = try source("ggumirror/Store/StickerStoreView.swift")
        let start = try #require(view.range(of: "private func commitRename")).upperBound
        let end = try #require(
            view.range(of: "private func actions(for", range: start..<view.endIndex)
        ).lowerBound
        let body = String(view[start..<end])
        // local 이름과 상점 상품명은 별개다.
        for forbidden in ["publish", "updateListing", "title =", "snapshot"] {
            #expect(!body.contains(forbidden), "rename이 \(forbidden)를 한다")
        }
    }

    @Test("이름 변경 UI가 거울과 같은 시트를 쓴다")
    func sharesTheMirrorSheet() throws {
        let view = try source("ggumirror/Store/StickerStoreView.swift")
        #expect(view.contains("MirrorNameSheet(name: $renameText"))
    }

    @Test("숨은 long-press가 아니라 목록 action이다")
    func discoverableEntryPoint() throws {
        let view = try source("ggumirror/Store/StickerStoreView.swift")
        #expect(view.contains("InkDialogAction(\"이름 변경\")"))
    }
}
