//
//  AccountDeletionTests.swift
//  ggumirrorTests
//
//  계정 삭제. **서버가 지운 뒤에만 이 기기를 지운다.**
//
//  순서를 바꾸면 서버 삭제가 실패했을 때 계정은 살아 있는데 거울만 사라진다.
//  그리고 지우는 것은 **그 계정의 서랍 하나뿐**이다 — 남의 콘텐츠를 지우는 것이
//  여기서 할 수 있는 가장 나쁜 실수다.
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

private nonisolated final class FakeDeletionBackend: AccountDeletionBackend, @unchecked Sendable {
    var calls = 0
    var failure: BackendError?
    func deleteAccount(accessToken: String) async throws {
        calls += 1
        if let failure { throw failure }
    }
}

@Suite("계정 삭제")
@MainActor
struct AccountDeletionTests {

    /// 계정 두 개가 각자 서랍을 가진 상태를 만든다.
    private func withAccounts(
        _ body: (URL, MirrorLibraryOwner, MirrorLibraryOwner) throws -> Void
    ) rethrows {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-a2b-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager().removeItem(at: root) }
        try body(root, .user("account-A"), .user("account-B"))
    }

    @Test("삭제 계정의 서랍만 지운다")
    func removesOnlyThatAccountsNamespace() throws {
        let manager = FileManager()
        let a = MirrorLibraryOwner.user("account-A")
        let b = MirrorLibraryOwner.user("account-B")
        for owner in [a, b] {
            try? manager.createDirectory(
                at: MirrorStore.root(for: owner), withIntermediateDirectories: true
            )
        }
        defer {
            try? manager.removeItem(at: MirrorStore.root(for: a))
            try? manager.removeItem(at: MirrorStore.root(for: b))
        }

        #expect(MirrorStore.removeAccountNamespace(for: a))
        #expect(!manager.fileExists(atPath: MirrorStore.root(for: a).path))
        // **B는 그대로다.** 남의 콘텐츠를 지우면 BLOCKER다.
        #expect(manager.fileExists(atPath: MirrorStore.root(for: b).path))
    }

    @Test("guest 서랍은 절대 지우지 않는다")
    func neverRemovesTheGuestNamespace() {
        // guest에는 로그인하지 않은 사람의 작업물이 있다. 계정 삭제와 무관하다.
        #expect(MirrorStore.removeAccountNamespace(for: .guest) == false)
    }

    @Test("서버가 실패하면 로컬을 건드리지 않는다")
    func serverFailureLeavesLocalDataAlone() throws {
        let code = try source("ggumirror/Auth/AccountDeletion.swift")
        // 실패 경로에서 곧바로 돌아간다 — 그 아래 정리 코드에 닿지 않는다.
        let start = try #require(code.range(of: "catch let error as BackendError")).upperBound
        // 주석이 아니라 **코드**를 기준으로 자른다(`source`가 주석을 지운다).
        let end = try #require(
            code.range(of: "library.activate", range: start..<code.endIndex)
        ).lowerBound
        let failurePath = String(code[start..<end])
        #expect(failurePath.contains("return .failed"))
        #expect(!failurePath.contains("removeAccountNamespace"))
        #expect(!failurePath.contains("signOut"))
    }

    @Test("서버를 먼저 부른다")
    func serverIsCalledFirst() throws {
        let code = try source("ggumirror/Auth/AccountDeletion.swift")
        let deleteCall = try #require(code.range(of: "backend.deleteAccount")).lowerBound
        let localWipe = try #require(code.range(of: "removeAccountNamespace")).lowerBound
        #expect(deleteCall < localWipe, "로컬을 먼저 지우면 서버 실패 시 거울만 잃는다")
    }

    @Test("로그인하지 않았으면 서버를 부르지도 않는다")
    func guestDoesNothing() throws {
        let code = try source("ggumirror/Auth/AccountDeletion.swift")
        // 첫 줄에서 막는다 — 요청을 보내고 401을 받는 구조가 아니다.
        let start = try #require(code.range(of: "static func run(")).upperBound
        let end = try #require(
            code.range(of: "backend.deleteAccount", range: start..<code.endIndex)
        ).lowerBound
        #expect(code[start..<end].contains("guard let server = session.server else { return .notSignedIn }"))
    }

    @Test("세션과 프로필을 정리한다")
    func clearsSessionAndProfile() throws {
        let code = try source("ggumirror/Auth/AccountDeletion.swift")
        #expect(code.contains("profile?.clear()"))
        #expect(code.contains("session.signOut()"))
        // 계정 캐시는 세션 없이 새로고침해 비운다(로그아웃과 같은 경로).
        #expect(code.contains("refreshMine(session: nil)"))
    }

    @Test("서랍을 바꾸기 전에 쓰기를 기다린다")
    func flushesBeforeSwitching() throws {
        let code = try source("ggumirror/Auth/AccountDeletion.swift")
        // `activate`가 내부에서 flush한다(계정 전환과 같은 규칙).
        #expect(code.contains("library.activate(owner: .guest)"))
        #expect(code.contains("stickers.activate(owner: .guest)"))
    }
}

@Suite("계정 삭제 UI")
struct AccountDeletionUITests {

    private func settings() throws -> String {
        try source("ggumirror/Home/SettingsView.swift")
    }

    @Test("설정에서 찾을 수 있다")
    func entryExists() throws {
        #expect(try settings().contains("계정 삭제"))
    }

    @Test("로그인한 사람에게만 보인다")
    func onlyWhenSignedIn() throws {
        #expect(try settings().contains("if session.server != nil"))
    }

    @Test("확인을 먼저 받는다")
    func confirmsFirst() throws {
        let code = try settings()
        #expect(code.contains("isConfirmingAccountDeletion = true"))
        #expect(code.contains("InkDialogAction(\"취소\""))
        #expect(code.contains("role: .destructive"))
    }

    @Test("무엇이 사라지는지 말한다")
    func explainsConsequences() throws {
        let code = try settings()
        #expect(code.contains("복구할 수 없어요"))
        #expect(code.contains("남은 조각은 복구되지 않아요"))
        // 산 사람의 권리가 남는다는 것도 말한다.
        #expect(code.contains("이미 다른 사람이 구매한 상품은 그 사람에게 계속 제공돼요"))
    }

    @Test("Apple 연결 해제 방법을 안내한다")
    func explainsAppleRevocation() throws {
        // 자동 해제를 못 하므로 **직접 하는 방법**을 알려 준다. 조용히 넘어가지 않는다.
        #expect(try settings().contains("Apple 계정 연결은"))
    }

    @Test("연타로 두 번 지우지 않는다")
    func doubleTapIsBlocked() throws {
        #expect(try settings().contains("disabled(isDeletingAccount)"))
    }

    @Test("문의 이메일로 떠넘기지 않는다")
    func noSupportEmailDetour() throws {
        let code = try settings()
        // 앱 안에서 끝나야 한다(App Store 요구사항).
        #expect(!code.contains("mailto:"))
    }
}
