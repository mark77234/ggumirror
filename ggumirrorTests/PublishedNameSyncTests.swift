//
//  PublishedNameSyncTests.swift
//  ggumirrorTests
//
//  **같은 물건이 두 이름을 갖지 않는다.**
//
//  실기기에서 나온 버그: AI로 만든 거울(`AI 거울`)을 상점에 올리면서 이름을
//  `짱구 거울`로 바꾸면, 상점에는 `짱구 거울`인데 `내 거울`에는 계속 `AI 거울`이었다.
//  등록 화면이 상품명을 서버로만 보내고 **local 이름은 건드리지 않았기 때문**이다.
//
//  고친 뒤의 계약:
//
//      등록 성공  →  local 이름도 그 상품명이 된다 (디스크까지)
//      등록 실패  →  local 이름은 그대로다
//
//  이름으로 콘텐츠를 찾지 않는다 — `MyMirror.id` / `StickerProject.id`가 열쇠다.
//  그래서 같은 이름을 가진 거울이 여럿 있어도 엉뚱한 것이 바뀌지 않는다.
//

import Testing
import Foundation
@testable import ggumirror

private let owner = MirrorLibraryOwner.user("11111111-1111-1111-1111-111111111111")

private func withDrawer(_ body: (URL) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "ggumirror-name-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

private func mirrorStore(_ root: URL) -> MirrorStore {
    MirrorStore(
        root: root.appending(path: "accounts/\(owner.directoryName)", directoryHint: .isDirectory)
    )
}

/// 실제 앱 데이터를 건드리지 않는 서랍 하나.
@MainActor
private func mirrorLibrary(_ root: URL) -> MirrorLibrary {
    MirrorLibrary(
        store: mirrorStore(root), owner: owner,
        assets: PhotoStickerAssetStore(), artworks: ImportedArtworkAssetStore(),
        accountsBase: root
    )
}

private func aiMirror(_ id: String, name: String = "AI 거울") -> MyMirror {
    MyMirror(id: id, name: name, origin: .made, style: BasicMirror.cream.style)
}

private func nameSyncSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

// MARK: - A · D — 이름이 실제로 바뀐다

@Suite("등록한 이름이 내 거울 이름이 된다")
@MainActor
struct PublishedMirrorNameTests {

    @Test("등록 성공하면 그 거울 이름이 상품명이 된다")
    func theMirrorTakesThePublishedTitle() throws {
        try withDrawer { root in
            let library = mirrorLibrary(root)
            _ = library.adopt(aiMirror("m-1"))
            #expect(library.mirrors.first?.name == "AI 거울")

            // 등록 성공 뒤에 화면이 하는 일과 같다 — id로 찾아 이름만 바꾼다.
            let outcome = library.rename("m-1", to: "짱구 거울")

            #expect(outcome == .renamed("짱구 거울"))
            #expect(library.mirrors.first?.name == "짱구 거울")
        }
    }

    @Test("다른 거울은 건드리지 않는다")
    func onlyTheTargetMirrorChanges() throws {
        try withDrawer { root in
            let library = mirrorLibrary(root)
            // **같은 이름으로 시작한다** — 이름으로 찾았다면 여기서 엉뚱한 것이 바뀐다.
            _ = library.adopt(aiMirror("m-1"))
            _ = library.adopt(aiMirror("m-2"))
            _ = library.adopt(aiMirror("m-3"))

            _ = library.rename("m-1", to: "짱구 거울")
            _ = library.rename("m-2", to: "도라에몽 거울")

            let names = Dictionary(
                uniqueKeysWithValues: library.mirrors.map { ($0.id, $0.name) }
            )
            #expect(names["m-1"] == "짱구 거울")
            #expect(names["m-2"] == "도라에몽 거울")
            // 등록하지 않은 것은 그대로다.
            #expect(names["m-3"] == "AI 거울")
        }
    }

    @Test("이름은 identity가 아니다 — id도 origin도 그대로다")
    func renamingChangesNothingElse() throws {
        try withDrawer { root in
            let library = mirrorLibrary(root)
            _ = library.adopt(aiMirror("m-1"))
            let before = try #require(library.mirrors.first)

            _ = library.rename("m-1", to: "짱구 거울")

            let after = try #require(library.mirrors.first)
            #expect(after.id == before.id)
            #expect(after.origin == before.origin)
            #expect(after.style == before.style)
            #expect(after.importedArtworks == before.importedArtworks)
            #expect(library.mirrors.count == 1, "이름을 바꾸면서 거울이 늘지 않는다")
        }
    }

    @Test("없는 거울은 조용히 만들어지지 않는다")
    func renamingAnUnknownIDCreatesNothing() throws {
        try withDrawer { root in
            let library = mirrorLibrary(root)
            _ = library.adopt(aiMirror("m-1"))

            #expect(library.rename("사라진-거울", to: "짱구 거울") == .notFound)
            #expect(library.mirrors.count == 1)
            #expect(library.mirrors.first?.name == "AI 거울")
        }
    }
}

// MARK: - B · E — 디스크에 남는다

@Suite("바뀐 이름이 디스크에 남는다")
@MainActor
struct PublishedNamePersistenceTests {

    @Test("새 library instance로 다시 읽어도 새 이름이다")
    func theNameSurvivesAReload() throws {
        try withDrawer { root in
            let first = mirrorLibrary(root)
            _ = first.adopt(aiMirror("m-1"))
            _ = first.rename("m-1", to: "짱구 거울")
            first.assetStore?.flush()

            // 앱을 껐다 켠 것과 같다 — 같은 서랍을 새로 읽는다.
            let relaunched = mirrorLibrary(root)

            #expect(relaunched.mirrors.first?.name == "짱구 거울")
        }
    }

    @Test("cold launch에서 network 없이 바로 새 이름이 보인다")
    func coldLaunchNeedsNoNetwork() throws {
        try withDrawer { root in
            let first = mirrorLibrary(root)
            _ = first.adopt(aiMirror("m-1"))
            _ = first.rename("m-1", to: "짱구 거울")
            first.apply(aiMirror("m-1", name: "짱구 거울"))
            first.assetStore?.flush()

            // 서버 세션도 marketplace 목록도 없는 상태다.
            let relaunched = mirrorLibrary(root)

            #expect(relaunched.mirrors.first?.name == "짱구 거울")
            #expect(relaunched.currentMirror.name == "짱구 거울")
        }
        // 이름을 얻으려고 상점을 부르지 않는다 — 목록에 network가 없다.
        let library = try nameSyncSource("ggumirror/Shared/MirrorSampleData.swift")
        for network in ["MarketplaceStore", "listing", "BackendClient"] {
            #expect(!library.contains(network), "\(network)")
        }
    }

    @Test("여러 거울의 이름이 각자 남는다")
    func everyRenameSurvivesIndependently() throws {
        try withDrawer { root in
            let first = mirrorLibrary(root)
            _ = first.adopt(aiMirror("m-1"))
            _ = first.adopt(aiMirror("m-2"))
            _ = first.rename("m-1", to: "짱구 거울")
            _ = first.rename("m-2", to: "도라에몽 거울")
            first.assetStore?.flush()

            let relaunched = mirrorLibrary(root)
            let names = Dictionary(
                uniqueKeysWithValues: relaunched.mirrors.map { ($0.id, $0.name) }
            )
            #expect(names["m-1"] == "짱구 거울")
            #expect(names["m-2"] == "도라에몽 거울")
        }
    }
}

// MARK: - C — 실패하면 바꾸지 않는다

@Suite("등록 실패는 이름을 바꾸지 않는다")
struct PublishFailureKeepsTheNameTests {

    /// 등록 화면이 이름을 바꾸는 자리는 **성공 뒤 한 곳뿐**이다.
    ///
    /// 이 순서는 실제 state test로 잡을 수 없다 — `publish()`가 SwiftUI view 안이라
    /// 서버 실패를 흉내 내려면 화면 전체를 띄워야 한다. 대신 **제어 흐름**을 본다:
    /// 실패 `guard`가 rename보다 앞에 있고, rename이 `didPublish = true` 뒤에 있다.
    @Test("실패 guard가 이름 바꾸기보다 먼저다", arguments: [
        ("ggumirror/Store/PublishMirrorView.swift", "library.rename(mirror.id, to: title)"),
        ("ggumirror/Store/PublishStickerView.swift", "library.rename(project.id, to: title)"),
    ])
    func failureReturnsBeforeTheRename(path: String, rename: String) throws {
        let code = try nameSyncSource(path)
        let publish = try #require(code.range(of: "private func publish() async {"))
        let body = String(code[publish.upperBound...])

        let failure = try #require(
            body.range(of: "guard let result else {"), "실패 guard가 없다"
        )
        let success = try #require(body.range(of: "didPublish = true"))
        let renamed = try #require(body.range(of: rename), "등록 뒤 이름을 맞추지 않는다")

        // 실패면 여기서 함수가 끝난다 → 아래 rename에 닿지 않는다.
        #expect(failure.lowerBound < renamed.lowerBound)
        #expect(String(body[failure.upperBound...].prefix(200)).contains("return"))
        // 성공을 확정한 뒤에만 바꾼다.
        #expect(success.lowerBound < renamed.lowerBound)
    }

    @Test("서버로 보낸 이름과 local에 남기는 이름이 같은 값이다", arguments: [
        "ggumirror/Store/PublishMirrorView.swift",
        "ggumirror/Store/PublishStickerView.swift",
    ])
    func oneTitleGoesBothWays(path: String) throws {
        let code = try nameSyncSource(path)
        let publish = try #require(code.range(of: "private func publish() async {"))
        let body = String(code[publish.upperBound...])

        // 상품명을 **한 번만** 계산한다 — 두 번 계산하면 언젠가 갈라진다.
        #expect(body.contains("let title = "))
        #expect(body.contains("title: title,"))
        #expect(body.contains("to: title)"))
        // 정규화를 두 번 부르지 않는다.
        #expect(body.components(separatedBy: "normalizedTitle(").count - 1 == 1)
    }

    @Test("화면에서 listing 이름으로 덮어 그리지 않는다")
    func noUIOnlyWorkaround() throws {
        // 진짜 model을 고쳤으므로, 표시할 때 상점 이름을 끌어다 쓸 이유가 없다.
        let myMirrors = try nameSyncSource("ggumirror/MyMirrors/MyMirrorsView.swift")
        #expect(!myMirrors.contains("listing.title"))
        #expect(!myMirrors.contains("AI 거울"))
        // 카드는 model의 이름을 그대로 읽는다.
        #expect(myMirrors.contains("mirror.name"))
    }
}

// MARK: - 스티커도 같은 구조다

@Suite("스티커도 같은 계약이다")
@MainActor
struct PublishedStickerNameTests {

    @Test("등록 성공하면 그 스티커 이름이 상품명이 된다")
    func theStickerTakesThePublishedTitle() throws {
        try withDrawer { root in
            let store = StickerProjectStore(
                root: root.appending(
                    path: "accounts/\(owner.directoryName)", directoryHint: .isDirectory
                )
            )
            let library = StickerLibrary(store: store, owner: owner)
            let saved = try #require(
                library.save(MirrorDesign.blank, name: "내 스티커", context: .createNew)
            )

            let outcome = library.rename(saved.id, to: "짱구 스티커")

            #expect(outcome == .renamed("짱구 스티커"))
            #expect(library.projects.first?.name == "짱구 스티커")

            // 디스크까지 남는다.
            store.flush()
            let relaunched = StickerLibrary(store: store, owner: owner)
            #expect(relaunched.projects.first?.name == "짱구 스티커")
        }
    }

    @Test("거울과 같은 통로를 쓴다 — 스티커 전용 이름 체계를 만들지 않았다")
    func stickersReuseTheSameAuthority() throws {
        let sticker = try nameSyncSource("ggumirror/Store/PublishStickerView.swift")
        let mirror = try nameSyncSource("ggumirror/Store/PublishMirrorView.swift")
        // 둘 다 각자 library의 `rename(_:to:)` 하나를 부른다.
        #expect(sticker.contains("library.rename(project.id, to: title)"))
        #expect(mirror.contains("library.rename(mirror.id, to: title)"))
        // 결과 타입도 하나다.
        #expect(try nameSyncSource("ggumirror/Editor/StickerProjectStore.swift")
            .contains("-> MirrorRenameOutcome"))
    }
}

// MARK: - F — 경제·판매 상태는 건드리지 않는다

@Suite("이름만 바뀐다")
@MainActor
struct RenameTouchesNothingElseTests {

    @Test("이름 바꾸기가 서버를 부르지 않는다")
    func renameIsPurelyLocal() throws {
        let library = try nameSyncSource("ggumirror/Shared/MirrorSampleData.swift")
        let start = try #require(library.range(of: "func rename(_ mirrorID: String"))
        let body = String(library[start.upperBound...].prefix(300))
        for server in ["await", "session", "backend", "listing", "shard"] {
            #expect(!body.lowercased().contains(server), "\(server)")
        }
    }

    @Test("등록 성공 경로가 경제 상태를 새로 만지지 않는다", arguments: [
        "ggumirror/Store/PublishMirrorView.swift",
        "ggumirror/Store/PublishStickerView.swift",
    ])
    func publishStillOnlyReadsServerEconomy(path: String) throws {
        let code = try nameSyncSource(path)
        let publish = try #require(code.range(of: "private func publish() async {"))
        let body = String(code[publish.upperBound...].prefix(2400))
        // 조각은 여전히 서버가 옮기고 앱은 다시 읽기만 한다.
        #expect(body.contains("wallet.refresh(session:"))
        for banned in ["balance -=", "balance +=", "feeInShards)"] {
            #expect(!body.contains(banned), "\(banned)")
        }
    }

    @Test("판매 상태 · listing id는 그대로 서버가 authority다")
    func sellerStateIsUnchanged() throws {
        let code = try nameSyncSource("ggumirror/Store/PublishMirrorView.swift")
        // listing id는 publish **전에** 남기는 기존 순서 그대로다.
        let hook = try #require(code.range(of: "onListingCreated"))
        let publish = try #require(code.range(of: "await marketplace.publish("))
        #expect(hook.lowerBound < publish.lowerBound)
        // 판매 상태 판단은 여전히 서버 목록에서 온다.
        #expect(code.contains("marketplace.myListing(id: hint)"))
    }

    @Test("판매 중인 거울은 여전히 사용자가 이름을 못 바꾼다")
    func publishedOriginalsStayLocked() {
        // 등록 시점의 상품명이 곧 이름이고, 그 뒤에는 잠긴다 — 정책은 그대로다.
        #expect(
            MirrorRenamePolicy.availability(
                isSignedIn: true, hasSellerLinkHint: true,
                sellerListingsAreKnown: true, isPublishedOriginal: true
            ) == .lockedPublished
        )
    }
}
