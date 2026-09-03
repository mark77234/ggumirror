//
//  ProfileTests.swift
//  ggumirrorTests
//
//  **이름은 계정 정보다.** 이 기기의 값이 아니다.
//
//  예전에는 모두에게 `거울지기`가 보였고, 계정을 바꿔도 같은 이름이 남았다.
//  1.1.0부터 서버가 authority이고, 이름이 **없는 것이 정상**이다.
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

private nonisolated final class FakeProfileBackend: ProfileBackend, @unchecked Sendable {
    var stored: ServerProfile
    var failure: BackendError?
    var sawNames: [String] = []

    init(_ profile: ServerProfile) { stored = profile }

    func profile(accessToken: String) async throws -> ServerProfile {
        if let failure { throw failure }
        return stored
    }

    func setDisplayName(_ name: String, accessToken: String) async throws -> ServerProfile {
        sawNames.append(name)
        if let failure { throw failure }
        stored = ServerProfile(
            id: stored.id, displayName: name,
            canChangeDisplayName: false,
            nextDisplayNameChangeAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        return stored
    }
}

private func session() -> ServerSession {
    ServerSession(accessToken: "t", expiresAt: .distantFuture, userID: "user-1")
}

private func profile(name: String?, canChange: Bool = true) -> ServerProfile {
    ServerProfile(
        id: "user-1", displayName: name,
        canChangeDisplayName: canChange, nextDisplayNameChangeAt: nil
    )
}

@Suite("이름 규칙")
struct DisplayNamePolicyTests {

    @Test("앞뒤 공백을 다듬는다")
    func trims() {
        #expect(DisplayNamePolicy.normalized("  병찬  ") == "병찬")
    }

    @Test("비었거나 공백뿐이면 거절한다")
    func rejectsEmpty() {
        #expect(DisplayNamePolicy.normalized("") == nil)
        #expect(DisplayNamePolicy.normalized("   ") == nil)
    }

    @Test("줄바꿈은 거절한다")
    func rejectsNewlines() {
        #expect(DisplayNamePolicy.normalized("이름\n둘째줄") == nil)
    }

    @Test("길이는 글자로 센다")
    func countsCharacters() {
        // 한글 20자는 UTF-8로 60 byte다. byte로 세면 정당한 이름이 막힌다.
        let name = String(repeating: "가", count: 20)
        #expect(name.utf8.count > DisplayNamePolicy.maxLength)
        #expect(DisplayNamePolicy.normalized(name) == name)
        #expect(DisplayNamePolicy.normalized(name + "가") == nil)
    }

    @Test("안내 문구는 저장되는 값이 아니다")
    func placeholderIsNotAName() {
        // 화면에만 쓰는 말이다. 이것이 이름으로 저장되면 안 된다.
        #expect(DisplayNamePolicy.placeholder == "이름을 정해주세요")
        let view = try? source("ggumirror/Home/ProfileView.swift")
        #expect(view?.contains("setDisplayName(DisplayNamePolicy.placeholder") != true)
    }
}

@Suite("프로필은 서버가 authority다")
@MainActor
struct ProfileSessionTests {

    @Test("서버 이름을 그대로 옮겨 적는다")
    func mirrorsServerName() async {
        let backend = FakeProfileBackend(profile(name: "병찬"))
        let subject = ProfileSession(backend: backend)
        await subject.refresh(session: session())
        #expect(subject.displayName == "병찬")
    }

    @Test("이름이 없는 것이 정상이다")
    func missingNameIsNormal() async {
        let subject = ProfileSession(backend: FakeProfileBackend(profile(name: nil)))
        await subject.refresh(session: session())
        // 기본 이름을 지어내지 않는다.
        #expect(subject.displayName == nil)
        #expect(subject.profile?.hasName == false)
    }

    @Test("로그아웃하면 비운다")
    func signOutClearsTheName() async {
        let subject = ProfileSession(backend: FakeProfileBackend(profile(name: "병찬")))
        await subject.refresh(session: session())
        #expect(subject.displayName == "병찬")
        // **A의 이름이 B에게 보이면 안 된다.**
        await subject.refresh(session: nil)
        #expect(subject.displayName == nil)
    }

    @Test("계정이 바뀌면 그 계정의 이름이 된다")
    func accountIsolation() async {
        let backend = FakeProfileBackend(profile(name: "A이름"))
        let subject = ProfileSession(backend: backend)
        await subject.refresh(session: session())
        #expect(subject.displayName == "A이름")

        await subject.refresh(session: nil)
        backend.stored = profile(name: "B이름")
        await subject.refresh(session: session())
        #expect(subject.displayName == "B이름")
    }

    @Test("이름을 바꾸면 서버 값으로 갈아 끼운다")
    func setNameUsesServerResult() async {
        let backend = FakeProfileBackend(profile(name: nil))
        let subject = ProfileSession(backend: backend)
        #expect(await subject.setDisplayName("병찬", session: session()) == nil)
        #expect(subject.displayName == "병찬")
        // 서버가 준 30일 상태를 그대로 쓴다 — 기기에서 세지 않는다.
        #expect(subject.profile?.canChangeDisplayName == false)
    }

    @Test("잘못된 이름은 서버에 보내지도 않는다")
    func invalidNameIsNotSent() async {
        let backend = FakeProfileBackend(profile(name: nil))
        let subject = ProfileSession(backend: backend)
        #expect(await subject.setDisplayName("   ", session: session()) != nil)
        #expect(backend.sawNames.isEmpty)
    }

    @Test("실패하면 저장되지 않은 이름을 보여 주지 않는다")
    func failureDoesNotPersistOptimistically() async {
        let backend = FakeProfileBackend(profile(name: "예전이름"))
        let subject = ProfileSession(backend: backend)
        await subject.refresh(session: session())
        backend.failure = .unavailable
        #expect(await subject.setDisplayName("새이름", session: session()) != nil)
        #expect(subject.displayName == "예전이름")
    }

    @Test("로그인 없이 바꾸지 않는다")
    func requiresSignIn() async {
        let backend = FakeProfileBackend(profile(name: nil))
        let subject = ProfileSession(backend: backend)
        #expect(await subject.setDisplayName("병찬", session: nil) != nil)
        #expect(backend.sawNames.isEmpty)
    }
}

@Suite("거울지기 하드코딩과 태그가 사라졌다")
struct ProfileCleanupTests {

    @Test("사용자 이름 fallback으로 거울지기를 쓰지 않는다")
    func noHardcodedDefaultName() throws {
        for path in ["ggumirror/Home/SettingsView.swift", "ggumirror/Home/ProfileView.swift"] {
            #expect(!(try source(path)).contains("거울지기"), "\(path)")
        }
    }

    @Test("이름이 없으면 안내 문구를 쓴다")
    func missingNameShowsGuidance() throws {
        let settings = try source("ggumirror/Home/SettingsView.swift")
        #expect(settings.contains("DisplayNamePolicy.placeholder"))
    }

    @Test("프로필 UI에 태그가 없다")
    func tagUIIsGone() throws {
        for path in ["ggumirror/Home/SettingsView.swift", "ggumirror/Home/ProfileView.swift"] {
            let code = try source(path)
            #expect(!code.contains("ProfileTag"), "\(path)")
            #expect(!code.contains("profileTags"), "\(path)")
        }
    }

    @Test("예전 저장값을 지우는 코드를 만들지 않았다")
    func legacyStorageIsNotDeleted() throws {
        // 지울 이유가 없고, 지우는 코드가 곧 새 버그다. 그냥 읽지 않는다.
        let settings = try source("ggumirror/Home/SettingsView.swift")
        #expect(!settings.contains("removeObject(forKey"))
    }

    @Test("이름은 UserDefaults가 authority가 아니다")
    func nameIsNotStoredLocally() throws {
        let settings = try source("ggumirror/Home/SettingsView.swift")
        let profile = try source("ggumirror/Home/ProfileView.swift")
        // 계정을 바꿔도 남는 저장소에 이름을 두지 않는다.
        #expect(!settings.contains("@AppStorage(ProfileStore.nameKey)"))
        #expect(!profile.contains("@AppStorage(ProfileStore.nameKey)"))
    }
}

@Suite("판매자 이름")
struct SellerAttributionTests {

    @Test("서버가 준 이름만 쓴다")
    func listingCarriesOnlyTheName() throws {
        let api = try source("ggumirror/Backend/MarketplaceAPI.swift")
        #expect(api.contains("let sellerDisplayName: String?"))
        // 내부 식별자를 담을 자리를 만들지 않는다.
        for forbidden in ["sellerUserId", "sellerId", "appleSub", "email"] {
            #expect(!api.contains(forbidden), "공개 모델에 \(forbidden)이 있다")
        }
    }

    @Test("카드가 판매자 이름을 보여 준다")
    func cardShowsSeller() throws {
        let gallery = try source("ggumirror/Store/MarketplaceGallery.swift")
        #expect(gallery.contains("subtitle: listing.sellerDisplayName"))
    }

    @Test("이름이 없어도 카드 높이가 달라지지 않는다")
    func cardGeometryStaysStable() throws {
        // subtitle 줄은 늘 그려지고, 높이는 언제나 있는 `ShardAmount`가 정한다.
        let card = try source("ggumirror/Store/StoreMirrorCard.swift")
        #expect(card.contains("Text(model.subtitle ?? \"\")"))
        #expect(card.contains("ShardAmount(amount: model.price)"))
        // 통계 줄 고정 높이도 그대로다(지난 phase 계약).
        #expect(card.contains("frame(height: StoreMirrorCardMetrics.metadataHeight)"))
    }

    @Test("이름 없는 판매자에게 가짜 이름을 붙이지 않는다")
    func noFakeSellerName() throws {
        let gallery = try source("ggumirror/Store/MarketplaceGallery.swift")
        for fake in ["\"익명\"", "\"판매자\"", "\"이름 없음\""] {
            #expect(!gallery.contains(fake), "가짜 판매자 이름 \(fake)")
        }
    }
}

@Suite("Apple 이름은 최초 로그인에만 실린다")
struct AppleNameSeedingTests {

    @Test("이름이 있으면 요청에 담는다")
    func nameTravelsWithSignIn() throws {
        let auth = try source("ggumirror/Auth/AuthSession.swift")
        #expect(auth.contains("displayName: result.displayName"))
    }

    @Test("이름이 없으면 예전 모양 그대로다")
    func nilNameKeepsTheOldShape() throws {
        let client = try source("ggumirror/Backend/BackendClient.swift")
        // optional이라 `nil`이면 JSON에서 아예 빠진다 — 1.0.7 요청과 같은 모양이다.
        #expect(client.contains("let displayName: String?"))
        #expect(client.contains("displayName: String? = nil"))
    }

    @Test("Apple 이름을 신원 판단에 쓰지 않는다")
    func appleNameIsDisplayOnly() throws {
        let auth = try source("ggumirror/Auth/AuthSession.swift")
        // userID는 서버 세션이 정한다 — Apple이 준 이름으로 계정을 고르지 않는다.
        #expect(!auth.contains("userID: result.displayName"))
    }
}
