//
//  AccountLibraryTests.swift
//  ggumirrorTests
//
//  **내 거울과 내 스티커는 계정마다 따로 산다.**
//
//  예전에는 `Application Support/ggumirror/` 한 곳을 모든 Apple 계정이 공유했다 —
//  A로 만든 거울이 로그아웃 뒤에도, B로 로그인해도 그대로 보였다. 남의 콘텐츠가
//  보이는 문제라 고쳤다.
//
//  **로그아웃은 삭제가 아니다.** 보는 서랍만 바뀌고 파일은 남는다.
//

import Testing
import Foundation
@testable import ggumirror

private let alice = MirrorLibraryOwner.user("11111111-1111-1111-1111-111111111111")
private let bob = MirrorLibraryOwner.user("22222222-2222-2222-2222-222222222222")

/// 임시 폴더 하나를 legacy root처럼 쓴다. 실제 앱 데이터를 건드리지 않는다.
private func withAccountRoot(_ body: (URL) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "ggumirror-accounts-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

private func store(_ root: URL, _ owner: MirrorLibraryOwner) -> MirrorStore {
    MirrorStore(root: root.appending(path: "accounts/\(owner.directoryName)", directoryHint: .isDirectory))
}

/// **실제 앱 데이터를 건드리지 않는다** — 서랍 base를 임시 폴더로 준다.
@MainActor
private func library(_ root: URL, _ owner: MirrorLibraryOwner) -> MirrorLibrary {
    MirrorLibrary(store: store(root, owner), assets: PhotoStickerAssetStore(),
                  artworks: ImportedArtworkAssetStore(), accountsBase: root)
}

@Suite("서랍 이름")
struct LibraryOwnerNameTests {

    @Test("로그인하지 않으면 guest다")
    func guestForNoUser() {
        #expect(MirrorLibraryOwner(userID: nil) == .guest)
        #expect(MirrorLibraryOwner(userID: "") == .guest)
        #expect(MirrorLibraryOwner.guest.directoryName == "guest")
        #expect(MirrorLibraryOwner.guest.isGuest)
    }

    @Test("서버 user id가 그대로 폴더 이름이 된다")
    func uuidBecomesDirectory() {
        let id = "063cd7cb-0000-4000-8000-000000000000"
        #expect(MirrorLibraryOwner(userID: id).directoryName == id)
    }

    @Test("경로에 쓸 수 없는 값은 그대로 쓰지 않는다")
    func unsafeIDIsHashed() {
        for unsafe in ["../../etc", "a/b", "user@example.com", String(repeating: "x", count: 200)] {
            let name = MirrorLibraryOwner.user(unsafe).directoryName
            #expect(!name.contains("/"))
            #expect(!name.contains(".."))
            #expect(!name.contains("@"))
            #expect(name.count <= 64)
        }
        // 같은 사용자는 언제나 같은 폴더다.
        #expect(MirrorLibraryOwner.user("a/b").directoryName
                == MirrorLibraryOwner.user("a/b").directoryName)
        // 다른 사용자는 다른 폴더다.
        #expect(MirrorLibraryOwner.user("a/b").directoryName
                != MirrorLibraryOwner.user("a/c").directoryName)
    }

    @Test("계정마다 다른 폴더를 쓴다")
    func accountsDoNotShareADirectory() {
        #expect(MirrorStore.root(for: alice) != MirrorStore.root(for: bob))
        #expect(MirrorStore.root(for: alice) != MirrorStore.root(for: .guest))
        // 예전 위치와도 겹치지 않는다.
        #expect(MirrorStore.root(for: alice) != MirrorStore.legacyRoot)
    }

    @Test("경로에 raw Apple 식별자나 이메일을 쓰지 않는다")
    func pathUsesInternalIDOnly() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "ggumirror/Shared/MirrorLibraryOwner.swift")
        let source = codeWithoutComments(try String(contentsOf: root, encoding: .utf8))
        for banned in ["email", "appleSubject", "identityToken", "accessToken"] {
            #expect(!source.contains(banned))
        }
    }
}

@MainActor
@Suite("계정 사이에 내용이 새지 않는다")
struct AccountIsolationTests {

    @Test("A → 로그아웃 → 비어 있음 → B → A 복구")
    func librariesAreIsolatedAndRestored() throws {
        try withAccountRoot { root in
            // A가 거울 둘을 만든다.
            let a = library(root, alice)
            a.activate(owner: alice)
            _ = a.save(.blank, name: "A1", context: .createNew)
            _ = a.save(.blank, name: "A2", context: .createNew)
            #expect(a.storedCount == 2)

            // 로그아웃 — **화면에서 비지만 파일은 남는다.**
            a.activate(owner: .guest)
            #expect(a.storedCount == 0)
            #expect(a.owner == .guest)

            // B로 로그인 — A의 거울이 보이면 FAIL.
            a.activate(owner: bob)
            #expect(a.storedCount == 0)
            _ = a.save(.blank, name: "B1", context: .createNew)
            #expect(a.mirrors.map(\.name) == ["B1"])

            // 로그아웃 → 다시 비어 있다.
            a.activate(owner: .guest)
            #expect(a.storedCount == 0)

            // A 복구 — 로그아웃 전에 갖고 있던 그대로다.
            a.activate(owner: alice)
            #expect(a.mirrors.map(\.name) == ["A1", "A2"])

            // B 복구.
            a.activate(owner: bob)
            #expect(a.mirrors.map(\.name) == ["B1"])
        }
    }

    @Test("로그아웃이 파일을 지우지 않는다")
    func signOutIsNotDelete() throws {
        try withAccountRoot { root in
            let a = library(root, alice)
            a.activate(owner: alice)
            _ = a.save(.blank, name: "소중한 거울", context: .createNew)

            let file = store(root, alice).libraryURL
            #expect(FileManager.default.fileExists(atPath: file.path()))

            a.activate(owner: .guest)
            // **파일이 그대로 있다.** 계정 삭제와 혼동하지 않는다.
            #expect(FileManager.default.fileExists(atPath: file.path()))
        }
    }

    @Test("상점에서 받은 거울도 그 계정 서랍에만 들어간다")
    func marketplaceImportsAreScoped() throws {
        try withAccountRoot { root in
            let a = library(root, alice)
            a.activate(owner: alice)
            let bought = MyMirror(
                id: "listing-1", name: "산 거울", origin: .purchased,
                style: StoreCatalog.basics[0].style
            )
            #expect(a.adopt(bought) != nil)
            #expect(a.storedCount == 1)

            a.activate(owner: bob)
            #expect(a.storedCount == 0, "B에게 A가 산 거울이 보인다")

            a.activate(owner: alice)
            #expect(a.mirrors.contains { $0.id == "listing-1" })
        }
    }

    @Test("내장 템플릿 획득도 그 계정 것이다")
    func builtInAcquisitionsAreScoped() throws {
        try withAccountRoot { root in
            let a = library(root, alice)
            a.activate(owner: alice)
            #expect(a.acquire(StoreCatalog.basics[0]) != nil)

            a.activate(owner: bob)
            #expect(a.storedCount == 0)

            a.activate(owner: alice)
            #expect(a.storedCount == 1)
        }
    }

    @Test("보관 칸도 계정을 따라간다")
    func capacityFollowsTheAccount() throws {
        try withAccountRoot { root in
            let a = library(root, alice)
            a.activate(owner: alice)
            // 서버가 A에게 10칸을 줬다고 하자.
            a.applyServerCapacity(10)
            #expect(a.mirrorCapacity == 10)

            // B는 산 칸이 없다 — A의 10칸이 남으면 FAIL.
            a.activate(owner: bob)
            #expect(a.mirrorCapacity == MirrorStoragePolicy.freeMirrorSlots)

            a.activate(owner: .guest)
            #expect(a.mirrorCapacity == MirrorStoragePolicy.freeMirrorSlots)
        }
    }

    @Test("같은 계정으로 다시 열어도 아무 일도 하지 않는다")
    func activatingTheSameOwnerIsANoop() throws {
        try withAccountRoot { root in
            let a = library(root, alice)
            a.activate(owner: alice)
            _ = a.save(.blank, name: "A1", context: .createNew)
            a.activate(owner: alice)
            #expect(a.mirrors.map(\.name) == ["A1"])
        }
    }
}

@Suite("예전 데이터 넘겨주기")
struct LegacyClaimTests {

    /// 계정 구분 이전처럼 legacy root에 파일을 만든다.
    private func seedLegacy(_ root: URL, sticker: Bool = false) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":3,"currentMirrorID":"m","mirrors":[]}"#.utf8)
            .write(to: root.appending(path: "mirror-library.json"))
        if sticker {
            try Data("[]".utf8).write(to: root.appending(path: "sticker-projects.json"))
        }
    }

    @Test("로그인한 사용자에게 한 번만 넘긴다")
    func claimsOnceForASignedInUser() throws {
        try withAccountRoot { root in
            try seedLegacy(root)
            let claimed = claim(root, alice)
            #expect(claimed)
            #expect(FileManager.default.fileExists(
                atPath: root.appending(path: "accounts/\(alice.directoryName)/mirror-library.json").path()
            ))
            // 예전 자리에는 더 이상 없다(옮긴 것이지 복사가 아니다).
            #expect(!FileManager.default.fileExists(
                atPath: root.appending(path: "mirror-library.json").path()
            ))
            // 두 번째 호출은 아무것도 하지 않는다.
            #expect(claim(root, alice) == false)
            #expect(claim(root, bob) == false)
        }
    }

    @Test("guest에게는 주지 않는다")
    func neverClaimsForGuest() throws {
        try withAccountRoot { root in
            try seedLegacy(root)
            #expect(claim(root, .guest) == false)
            // 예전 파일이 그대로 남는다 — 지우지 않는다.
            #expect(FileManager.default.fileExists(
                atPath: root.appending(path: "mirror-library.json").path()
            ))
        }
    }

    @Test("이미 자기 서랍이 있으면 덮어쓰지 않는다")
    func neverOverwritesAnExistingLibrary() throws {
        try withAccountRoot { root in
            try seedLegacy(root)
            // A가 이미 자기 서랍을 갖고 있다.
            let mine = root.appending(path: "accounts/\(alice.directoryName)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
            try Data("MINE".utf8).write(to: mine.appending(path: "mirror-library.json"))

            #expect(claim(root, alice) == false)
            // 내 것이 그대로다.
            #expect(try String(contentsOf: mine.appending(path: "mirror-library.json"), encoding: .utf8) == "MINE")
            // 예전 파일도 지우지 않았다 — 주인 없는 채로 남는다.
            #expect(FileManager.default.fileExists(
                atPath: root.appending(path: "mirror-library.json").path()
            ))
        }
    }

    @Test("넘겨줄 것이 없으면 표시도 남기지 않는다")
    func nothingToClaim() throws {
        try withAccountRoot { root in
            #expect(claim(root, alice) == false)
            #expect(!FileManager.default.fileExists(
                atPath: root.appending(path: "legacy-claimed.json").path()
            ))
        }
    }

    @Test("스티커도 같은 서랍으로 함께 간다")
    func stickersMoveWithTheMirrors() throws {
        try withAccountRoot { root in
            try seedLegacy(root, sticker: true)
            #expect(claim(root, alice))
            #expect(FileManager.default.fileExists(
                atPath: root.appending(path: "accounts/\(alice.directoryName)/sticker-projects.json").path()
            ))
        }
    }

    /// **실제 구현**을 임시 root에 대고 돌린다. 흉내 내지 않는다.
    private func claim(_ root: URL, _ owner: MirrorLibraryOwner) -> Bool {
        MirrorStore.claimLegacy(for: owner, legacyRoot: root)
    }
}
