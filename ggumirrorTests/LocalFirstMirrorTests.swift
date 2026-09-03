//
//  LocalFirstMirrorTests.swift
//  ggumirrorTests
//
//  **거울 화면은 network보다 먼저 쓸 수 있어야 한다.**
//
//  예전에는 서랍을 여는 일이 `await session.refreshServerSession()` 뒤에 있었다.
//  그 한 줄이 서버 왕복 하나라, 앱을 켜고 바로 거울로 들어가면 그동안 guest 서랍
//  (= 비어 있음)이 보였다 — 마지막에 쓰던 거울이 사라졌다가 잠시 뒤 되살아나는
//  것처럼 보인 이유가 정확히 이것이다.
//
//  여기서 고정하는 것 넷:
//    1. cold launch가 지난 실행의 서랍을 **곧바로** 연다
//    2. 서버가 답한 뒤에 맞춘다(reconcile) — 그 전에 기본 거울로 되돌아가지 않는다
//    3. 계정이 섞이지 않는다(**release blocker**)
//    4. 이 캐시는 소유권 · 결제 · 잔액의 근거가 아니다
//

import Testing
import Foundation
@testable import ggumirror

private let alice = MirrorLibraryOwner.user("11111111-1111-1111-1111-111111111111")
private let bob = MirrorLibraryOwner.user("22222222-2222-2222-2222-222222222222")

/// 실제 사용자 설정을 건드리지 않는다.
private func temporaryDefaults() -> UserDefaults {
    let suite = "ggumirror.tests.\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

private func withAccountRoot(_ body: (URL) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "ggumirror-localfirst-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

private func store(_ root: URL, _ owner: MirrorLibraryOwner) -> MirrorStore {
    MirrorStore(
        root: root.appending(path: "accounts/\(owner.directoryName)", directoryHint: .isDirectory)
    )
}

/// 실제 앱 데이터를 건드리지 않는 library 하나. 서랍 base가 임시 폴더다.
@MainActor
private func library(_ root: URL, _ owner: MirrorLibraryOwner) -> MirrorLibrary {
    MirrorLibrary(
        store: store(root, owner), owner: owner,
        assets: PhotoStickerAssetStore(), artworks: ImportedArtworkAssetStore(),
        accountsBase: root
    )
}

/// **쓰기가 디스크에 닿을 때까지 기다린다.** 저장은 비동기라(`queue.async`) 기다리지
/// 않으면 "다시 켰다"가 아직 쓰이지 않은 상태를 읽는다.
/// `flush()`는 그 store instance의 줄 하나를 비우는 것이라 **같은 instance**여야 한다.
@MainActor
private func flush(_ library: MirrorLibrary) {
    library.assetStore?.flush()
}

private func mirror(_ id: String, name: String) -> MyMirror {
    MyMirror(id: id, name: name, origin: .made, style: BasicMirror.cream.style)
}

private func testSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

// MARK: - 마지막 사용자 기억

@Suite("마지막 사용자")
struct LastActiveUserTests {

    @Test("기억한 적이 없으면 guest다")
    func nothingRememberedMeansGuest() {
        #expect(LastActiveUser(defaults: temporaryDefaults()).owner == .guest)
    }

    @Test("서버 세션이 확인되면 그 사용자를 기억한다")
    func rememberingASession() {
        let defaults = temporaryDefaults()
        let last = LastActiveUser(defaults: defaults)
        last.remember("11111111-1111-1111-1111-111111111111")

        #expect(LastActiveUser(defaults: defaults).owner == alice)
    }

    @Test("풀면 다음 실행은 guest로 시작한다")
    func forgettingReturnsToGuest() {
        let defaults = temporaryDefaults()
        let last = LastActiveUser(defaults: defaults)
        last.remember("11111111-1111-1111-1111-111111111111")
        last.forget()

        #expect(LastActiveUser(defaults: defaults).owner == .guest)
        // `nil`을 기억하라는 것도 푸는 것이다.
        last.remember("11111111-1111-1111-1111-111111111111")
        last.remember(nil)
        #expect(LastActiveUser(defaults: defaults).owner == .guest)
    }

    @Test("credential을 적어 두지 않는다")
    func onlyAnIdentifierIsStored() throws {
        let code = try testSource("ggumirror/Auth/LastActiveUser.swift")
        // 세션 token은 여전히 Keychain에만 있다.
        for forbidden in ["accessToken", "refreshToken", "identityToken", "Keychain", "email"] {
            #expect(!code.contains(forbidden), "\(forbidden)")
        }
    }
}

// MARK: - cold launch

@Suite("cold launch — 서버를 기다리지 않는다")
@MainActor
struct ColdLaunchRestoreTests {

    @Test("세션이 아직 없어도 지난 실행의 거울이 곧바로 보인다")
    func theCachedMirrorIsShownBeforeAnyServerAnswer() throws {
        try withAccountRoot { root in
            // 지난 실행: 거울을 만들고 적용했다.
            let first = library(root, alice)
            _ = first.adopt(mirror("m-1", name: "리본 거울"))
            first.apply(mirror("m-1", name: "리본 거울"))
            flush(first)

            // 이번 실행: **서버 세션이 없다.** 그래도 기억해 둔 서랍을 곧바로 연다.
            let relaunched = library(root, alice)

            #expect(relaunched.mirrors.map(\.id) == ["m-1"])
            #expect(relaunched.currentMirror.id == "m-1")
            #expect(relaunched.currentMirror.name == "리본 거울")
        }
    }

    @Test("마지막 적용 거울이 다음 실행에도 남는다")
    func theLastAppliedMirrorSurvivesRelaunch() throws {
        try withAccountRoot { root in
            let first = library(root, alice)
            _ = first.adopt(mirror("m-1", name: "하나"))
            _ = first.adopt(mirror("m-2", name: "둘"))
            first.apply(mirror("m-2", name: "둘"))
            flush(first)

            #expect(library(root, alice).currentMirror.id == "m-2")
        }
    }

    @Test("기본 거울로 되돌아가지 않는다 — 서버가 답하기 전에도")
    func noFlashBackToTheDefaultMirror() throws {
        try withAccountRoot { root in
            let first = library(root, alice)
            _ = first.adopt(mirror("m-1", name: "리본 거울"))
            first.apply(mirror("m-1", name: "리본 거울"))
            flush(first)

            let relaunched = library(root, alice)
            #expect(relaunched.currentMirror.id != MirrorLibrary.defaultMirror.id)

            // 같은 주인으로 다시 맞춰도(서버가 같은 답을 준 경우) 아무 일도 없다.
            relaunched.activate(owner: alice)
            #expect(relaunched.currentMirror.id == "m-1")
            #expect(relaunched.mirrors.map(\.id) == ["m-1"])
        }
    }

    @Test("앱이 쓰는 목록이 기억해 둔 서랍에서 시작한다")
    func theLiveLibraryOpensTheRememberedDrawer() throws {
        let code = try testSource("ggumirror/Shared/MirrorSampleData.swift")
        #expect(code.contains("LastActiveUser.shared.owner"))
        #expect(code.contains("MirrorLibrary(store: .store(for: owner), owner: owner)"))
        // 스티커도 같은 순간에 같은 주인을 본다.
        let stickers = try testSource("ggumirror/Editor/StickerProjectStore.swift")
        #expect(stickers.contains("LastActiveUser.shared.owner"))
    }

    @Test("서랍을 여는 일이 network 뒤에 있지 않다")
    func hydrationHappensBeforeTheNetworkWait() throws {
        let code = try testSource("ggumirror/RootView.swift")
        // 서랍을 여는 호출이 `refreshServerSession` **앞**에 이미 있다.
        let hydrate = try #require(code.range(of: "activateLibraries(owner: .user(restored))"))
        let refresh = try #require(code.range(of: "await session.refreshServerSession()"))
        #expect(hydrate.lowerBound < refresh.lowerBound)
        // 확인은 **곁가지 Task로** 나간다 — 서랍은 그 Task가 시작되기도 전에 열려 있다.
        let between = String(code[hydrate.upperBound..<refresh.lowerBound])
        #expect(between.contains("Task {"))
        // 서랍을 여는 그 줄 자체가 기다리는 호출이 아니다.
        #expect(!String(code[..<hydrate.lowerBound]).hasSuffix("await "))
        let guardLine = try #require(code.range(of: "if let restored = session.account?.userID"))
        #expect(guardLine.lowerBound < refresh.lowerBound)
    }

    @Test("서버가 답한 뒤에 맞춘다")
    func theServerAnswerStillReconciles() throws {
        let code = try testSource("ggumirror/RootView.swift")
        let refresh = try #require(code.range(of: "await session.refreshServerSession()"))
        let after = String(code[refresh.upperBound...].prefix(400))
        #expect(after.contains("activateLibraries(owner: MirrorLibraryOwner(userID:"))
    }
}

// MARK: - 계정 격리 (release blocker)

@Suite("계정이 섞이지 않는다")
@MainActor
struct AccountIsolationOnLaunchTests {

    @Test("A를 보고 있다가 B 세션이 확인되면 A가 남지 않는다")
    func switchingAccountsLeavesNothingBehind() throws {
        try withAccountRoot { root in
            let a = library(root, alice)
            _ = a.adopt(mirror("a-1", name: "A의 거울"))
            a.apply(mirror("a-1", name: "A의 거울"))
            flush(a)

            // 이번 실행은 A 캐시로 시작했다.
            let live = library(root, alice)
            #expect(live.mirrors.map(\.id) == ["a-1"])

            // 서버가 B라고 답했다.
            live.activate(owner: bob)

            #expect(live.owner == bob)
            #expect(live.mirrors.isEmpty, "A의 거울이 B 화면에 남았다")
            #expect(live.currentMirror.id == MirrorLibrary.defaultMirror.id)
        }
    }

    @Test("B에게 캐시가 있으면 그것부터 보여 준다")
    func theOtherAccountHydratesFromItsOwnCache() throws {
        try withAccountRoot { root in
            let b = library(root, bob)
            _ = b.adopt(mirror("b-1", name: "B의 거울"))
            b.apply(mirror("b-1", name: "B의 거울"))
            flush(b)

            let live = library(root, alice)
            _ = live.adopt(mirror("a-1", name: "A의 거울"))
            live.activate(owner: bob)

            #expect(live.mirrors.map(\.id) == ["b-1"])
            #expect(live.currentMirror.id == "b-1")
        }
    }

    @Test("되돌아오면 A의 거울이 그대로 있다 — 전환은 삭제가 아니다")
    func switchingIsNotDeleting() throws {
        try withAccountRoot { root in
            let live = library(root, alice)
            _ = live.adopt(mirror("a-1", name: "A의 거울"))
            live.apply(mirror("a-1", name: "A의 거울"))

            live.activate(owner: bob)
            live.activate(owner: alice)

            #expect(live.mirrors.map(\.id) == ["a-1"])
            #expect(live.currentMirror.id == "a-1")
        }
    }

    @Test("명시적 로그아웃은 다음 실행의 자동 표시를 푼다")
    func explicitSignOutUnbindsTheDrawer() throws {
        let code = try testSource("ggumirror/Auth/AuthSession.swift")
        // 로그아웃은 세션 정리 한 곳을 지난다 — 거기서 표시도 푼다.
        let start = try #require(code.range(of: "private func clearServerSession() {"))
        let body = String(code[start.upperBound...].prefix(200))
        #expect(body.contains("lastActiveUser.forget()"))
        // `signOut()`이 그 경로를 부른다.
        let signOut = try #require(code.range(of: "func signOut() async {"))
        #expect(String(code[signOut.upperBound...].prefix(300)).contains("clearServerSession()"))
    }

    @Test("계정 삭제는 그 서랍 자체를 지운다")
    func deletingAnAccountRemovesItsCache() throws {
        try withAccountRoot { root in
            let live = library(root, alice)
            _ = live.adopt(mirror("a-1", name: "A의 거울"))
            live.activate(owner: .guest)

            let root = MirrorStore.root(for: alice)
            #expect(!root.path.contains("guest"))
        }
        // 실제 삭제 경로가 그 서랍 하나만 지우고, 로그아웃까지 함께 지난다.
        let code = try testSource("ggumirror/Auth/AccountDeletion.swift")
        #expect(code.contains("MirrorStore.removeAccountNamespace(for: owner)"))
        #expect(code.contains("await session.signOut()"))
    }

    @Test("guest 서랍은 지우지 않는다")
    func guestIsNeverErased() {
        #expect(MirrorStore.removeAccountNamespace(for: .guest) == false)
    }
}

// MARK: - 견고함

@Suite("캐시가 망가져도 앱은 산다")
@MainActor
struct MirrorCacheResilienceTests {

    @Test("깨진 파일이면 빈 서랍으로 안전하게 시작한다")
    func corruptCacheFallsBackSafely() throws {
        try withAccountRoot { root in
            let drawer = store(root, alice)
            try FileManager.default.createDirectory(
                at: drawer.root, withIntermediateDirectories: true
            )
            try Data("{ 이건 JSON이 아니다".utf8).write(to: drawer.libraryURL)

            let live = library(root, alice)

            #expect(live.mirrors.isEmpty)
            #expect(live.currentMirror.id == MirrorLibrary.defaultMirror.id)
            // 원본은 지우지 않고 옆으로 치워 둔다.
            #expect(FileManager.default.fileExists(atPath: drawer.damagedLibraryURL.path))
        }
    }

    @Test("더 새 버전이 적은 파일은 읽지도 덮어쓰지도 않는다")
    func newerSchemaIsLeftAlone() throws {
        try withAccountRoot { root in
            let drawer = store(root, alice)
            try FileManager.default.createDirectory(
                at: drawer.root, withIntermediateDirectories: true
            )
            let future = """
            {"schemaVersion":\(MirrorSchema.current + 1),"currentMirrorID":"x","mirrors":[]}
            """
            try Data(future.utf8).write(to: drawer.libraryURL)

            let live = library(root, alice)
            _ = live.adopt(mirror("m-1", name: "새 거울"))
            flush(live)

            // 덮어쓰지 않았다 — 더 새 버전 앱의 거울을 잃지 않는다.
            let raw = try String(contentsOf: drawer.libraryURL, encoding: .utf8)
            #expect(raw.contains("\(MirrorSchema.current + 1)"))
        }
    }

    @Test("없는 거울을 가리키고 있으면 기본 거울로 돌아간다")
    func aDanglingCurrentIDIsSafe() throws {
        try withAccountRoot { root in
            let drawer = store(root, alice)
            drawer.save(PersistedLibrary(currentMirrorID: "사라진-거울", mirrors: []))
            drawer.flush()

            #expect(library(root, alice).currentMirror.id == MirrorLibrary.defaultMirror.id)
        }
    }

    @Test("network 없이도 캐시된 거울이 그려진다")
    func renderingNeverWaitsOnTheNetwork() throws {
        let code = try testSource("ggumirror/Shared/MirrorSampleData.swift")
        // 목록을 읽는 자리에 network가 없다 — 파일뿐이다.
        for forbidden in ["URLSession", "BackendClient", "accessToken"] {
            #expect(!code.contains(forbidden), "\(forbidden)")
        }
    }
}

// MARK: - 이 캐시는 authority가 아니다

@Suite("캐시는 소유권의 근거가 아니다")
@MainActor
struct CacheIsNotAuthorityTests {

    @Test("잔액 · 소유권 · 결제 상태를 적지 않는다")
    func nothingEconomicIsCached() throws {
        let store = try testSource("ggumirror/Shared/MirrorStore.swift")
        // 저장 형식에 경제 값이 없다. 산 칸도 서버에 있다(이미 0으로만 쓴다).
        for forbidden in ["balance", "shard", "entitlement", "purchasedListing", "ownership"] {
            #expect(!store.lowercased().contains(forbidden.lowercased()), "\(forbidden)")
        }
        let library = try testSource("ggumirror/Shared/MirrorSampleData.swift")
        #expect(library.contains("purchasedCreatedSlots: 0"))
    }

    @Test("보관 칸은 서버가 다시 정한다")
    func capacityIsRefetchedAfterTheSessionReturns() throws {
        let code = try testSource("ggumirror/RootView.swift")
        let refresh = try #require(code.range(of: "await session.refreshServerSession()"))
        let after = String(code[refresh.upperBound...].prefix(400))
        #expect(after.contains("mirrorCapacity.refresh(session: session.server"))
    }

    @Test("계정이 바뀌면 칸 수가 무료 기본값에서 다시 시작한다")
    func switchingResetsCapacity() throws {
        try withAccountRoot { root in
            let live = library(root, alice)
            live.applyServerCapacity(30)
            #expect(live.mirrorCapacity == 30)

            live.activate(owner: bob)

            #expect(live.mirrorCapacity == MirrorStoragePolicy.freeMirrorSlots)
        }
    }
}

// MARK: - 시작이 느려지지 않는다

@Suite("시작 성능")
struct LaunchPerformanceTests {

    @Test("시작할 때 지금 거울의 그림만 푼다")
    func onlyTheCurrentMirrorIsPreloaded() throws {
        let code = try testSource("ggumirror/Shared/MirrorSampleData.swift")
        // 서랍 전체의 PNG를 main actor에서 해독하지 않는다.
        #expect(!code.contains("referencedAssetIDs(.photoSticker))"))
        #expect(code.contains("private func preloadCurrentMirrorAssets()"))
        let start = try #require(code.range(of: "private func preloadCurrentMirrorAssets()"))
        let body = String(code[start.upperBound...].prefix(220))
        #expect(body.contains("currentMirror"))
        #expect(body.contains("mirror.assetIDs(.photoSticker)"))
        #expect(body.contains("mirror.assetIDs(.importedArtwork)"))
    }

    @Test("나머지 그림은 필요할 때 읽는다")
    func everythingElseLoadsLazily() throws {
        let code = try testSource("ggumirror/Editor/ImportedArtworkModels.swift")
        // `image(for:)`가 캐시에 없으면 그때 디스크에서 읽는다 — 미리 풀 필요가 없다.
        let start = try #require(code.range(of: "func image(for id: UUID) -> CGImage? {"))
        let body = String(code[start.upperBound...].prefix(320))
        #expect(body.contains("storage.readAsset"))
    }

    @Test("시작 경로가 서랍 하나만 읽는다")
    func launchReadsOneDrawer() throws {
        let code = try testSource("ggumirror/RootView.swift")
        // 서랍을 여는 호출이 한 helper를 지난다 — 두 번 열지 않는다.
        #expect(code.contains("private func activateLibraries(owner: MirrorLibraryOwner)"))
        // 같은 주인이면 `activate`가 곧바로 돌아온다.
        let library = try testSource("ggumirror/Shared/MirrorSampleData.swift")
        #expect(library.contains("guard next != owner else { return }"))
    }
}
