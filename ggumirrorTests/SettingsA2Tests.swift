//
//  SettingsA2Tests.swift
//  ggumirrorTests
//
//  설정 화면의 세 가지: **구매 복원 · 법적 링크 · 리뷰 요청.**
//
//  셋 다 잘못 만들면 조용히 해로운 종류다 —
//  복원이 조각을 다시 주면 결제 없이 조각이 생기고,
//  가짜 법적 링크는 출시 전에 채우는 것을 잊게 만들고,
//  리뷰를 아무 때나 물으면 사용자가 앱을 나쁘게 기억한다.
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

private func legalDoc(_ name: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appending(path: "docs/legal/\(name)"), encoding: .utf8)
}

// MARK: - 구매 복원

private nonisolated final class FakeSync: AppStoreSyncing, @unchecked Sendable {
    var calls = 0
    var failure: Error?
    func sync() async throws {
        calls += 1
        if let failure { throw failure }
    }
}

private struct SyncFailed: Error {}

@Suite("구매 복원은 조각을 만들지 않는다")
@MainActor
struct PurchaseRestoreTests {

    private func session() -> ServerSession {
        ServerSession(accessToken: "t", expiresAt: .distantFuture, userID: "user-1")
    }

    @Test("Apple 상태를 동기화한다")
    func callsAppStoreSync() async {
        let sync = FakeSync()
        let state = await PurchaseRestore.run(
            session: session(), wallet: nil, purchases: nil,
            marketplace: nil, capacity: nil, profile: nil, storeKit: sync
        )
        #expect(sync.calls == 1)
        #expect(state == .finished)
    }

    @Test("로그인하지 않으면 아무것도 하지 않는다")
    func guestDoesNothing() async {
        let sync = FakeSync()
        let state = await PurchaseRestore.run(
            session: nil, wallet: nil, purchases: nil,
            marketplace: nil, capacity: nil, profile: nil, storeKit: sync
        )
        // 서버에 보내지도, Apple을 부르지도 않는다.
        #expect(sync.calls == 0)
        #expect(state == .failed)
    }

    @Test("동기화가 실패해도 알려 주기만 한다")
    func syncFailureIsReported() async {
        let sync = FakeSync()
        sync.failure = SyncFailed()
        let state = await PurchaseRestore.run(
            session: session(), wallet: nil, purchases: nil,
            marketplace: nil, capacity: nil, profile: nil, storeKit: sync
        )
        #expect(state == .failed)
        #expect(state.message?.contains("확인하지 못했어요") == true)
    }

    @Test("성공 문구가 조각을 준다고 말하지 않는다")
    func successCopyDoesNotPromiseShards() {
        let message = PurchaseRestoreState.finished.message ?? ""
        #expect(message == "구매 정보를 확인했어요.")
        // "10조각을 복원했어요" 같은 말은 사실이 아니고, 사용자가 잔액이 늘기를 기대하게 만든다.
        for misleading in ["조각", "복원했", "지급"] {
            #expect(!message.contains(misleading), "오해를 만드는 문구: \(misleading)")
        }
    }

    @Test("복원 경로에 잔액을 바꾸는 코드가 없다")
    func neverMutatesTheWallet() throws {
        let code = try source("ggumirror/IAP/PurchaseRestore.swift")
        for forbidden in ["balance +=", "balance -=", "apply(balance:", "credit("] {
            #expect(!code.contains(forbidden), "복원이 \(forbidden)를 한다")
        }
        // 하는 일은 **다시 읽는 것**뿐이다.
        #expect(code.contains("wallet?.refresh(session:"))
    }

    @Test("멱등은 서버 것을 그대로 쓴다")
    func idempotencyIsTheServers() throws {
        let code = try source("ggumirror/IAP/PurchaseRestore.swift")
        // 못 끝낸 결제는 기존 경로로 다시 낸다 — 서버가 한 번만 지급한다.
        #expect(code.contains("recoverUnfinished(session:"))
        // 복원이 자기만의 지급 규칙을 만들지 않는다.
        #expect(!code.contains("processed"))
    }

    @Test("산 것을 자동으로 내려받지 않는다")
    func doesNotBulkDownloadLibrary() throws {
        let code = try source("ggumirror/IAP/PurchaseRestore.swift")
        // `내 거울에 추가`는 그대로 사용자가 누른다.
        for forbidden in ["importMirror", "importSticker", "adopt(", "acquire("] {
            #expect(!code.contains(forbidden), "복원이 \(forbidden)를 한다")
        }
    }

    @Test("연타로 여러 번 돌지 않는다")
    func doubleTapIsBlocked() throws {
        let settings = try source("ggumirror/Home/SettingsView.swift")
        #expect(settings.contains("disabled(restoreState == .restoring)"))
    }

    @Test("로그아웃 상태에서는 로그인 안내로 간다")
    func guestGoesToTheSignInGate() throws {
        let settings = try source("ggumirror/Home/SettingsView.swift")
        #expect(settings.contains("requireSignIn(for: .shardTransaction)"))
    }
}

// MARK: - 법적 링크

@Suite("법적 링크")
struct LegalLinkTests {

    @Test("가짜 URL을 넣지 않았다")
    func noFakeURLsShipped() throws {
        let code = try source("ggumirror/Shared/LegalLinks.swift")
        for fake in ["example.com", "notion.so", "http://", "TODO_URL"] {
            #expect(!code.contains(fake), "가짜 링크 \(fake)")
        }
    }

    @Test("주소가 없으면 열지 않는다")
    func missingURLDoesNotOpen() throws {
        // 아직 채우지 않았다. 그때 openURL을 부르면 안 된다.
        #expect(LegalLinks.privacyPolicy == nil)
        #expect(LegalLinks.termsOfService == nil)
        let settings = try source("ggumirror/Home/SettingsView.swift")
        #expect(settings.contains("guard let url else"))
        #expect(settings.contains("LegalLinks.notReadyMessage"))
    }

    @Test("둘은 서로 다른 주소다")
    func privacyAndTermsAreSeparate() throws {
        let settings = try source("ggumirror/Home/SettingsView.swift")
        #expect(settings.contains("url: LegalLinks.privacyPolicy"))
        #expect(settings.contains("url: LegalLinks.termsOfService"))
    }

    @Test("출시 준비 여부를 한 곳에서 판단한다")
    func releaseReadinessIsCheckable() {
        // 지금은 아직 준비되지 않은 것이 **정답**이다.
        #expect(LegalLinks.isReadyForRelease == false)
    }

    @Test("문서 초안이 있다")
    func draftsExist() throws {
        let privacy = try legalDoc("privacy-policy-ko.md")
        let terms = try legalDoc("terms-of-service-ko.md")
        #expect(privacy.contains("# 개인정보처리방침"))
        #expect(terms.contains("# 이용약관"))
    }

    @Test("채워야 할 자리가 명확히 남아 있다")
    func placeholdersAreObvious() throws {
        for name in ["privacy-policy-ko.md", "terms-of-service-ko.md"] {
            let doc = try legalDoc(name)
            #expect(doc.contains("[운영자명 입력]"), "\(name)")
            #expect(doc.contains("[문의 이메일 입력]"), "\(name)")
            #expect(doc.contains("[시행일 입력]"), "\(name)")
        }
    }

    @Test("문서가 실제 정책을 적었다")
    func documentsMatchImplementedPolicy() throws {
        let terms = try legalDoc("terms-of-service-ko.md")
        // 실제로 구현된 계약들이다. 일반 약관을 복붙하지 않았다.
        #expect(terms.contains("등록비는 환불되지 않습니다"))
        #expect(terms.contains("이미 그 상품을 구매한 이용자는 계속 이용할 수 있습니다"))
        #expect(terms.contains("30일에 한 번"))
        #expect(terms.contains("현금성 자산이 아닙니다"))
        // 복원이 조각을 다시 준다고 쓰지 않았다.
        #expect(terms.contains("이미 사용한 거울조각을 다시 지급하지 않습니다"))
    }

    @Test("아직 없는 기능을 있다고 쓰지 않았다")
    func doesNotClaimUnbuiltFeatures() throws {
        let privacy = try legalDoc("privacy-policy-ko.md")
        // 푸시 알림과 AI 거울 생성은 아직 구현되지 않았다.
        #expect(!privacy.contains("푸시 알림을 발송"))
        #expect(privacy.contains("재감사 필요 시점"))
    }
}

// MARK: - 리뷰 요청

@Suite("리뷰는 성공 직후에만 묻는다")
struct ReviewPromptPolicyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func eligible() -> ReviewPromptPolicy {
        ReviewPromptPolicy(
            firstLaunchAt: now.addingTimeInterval(-ReviewPromptPolicy.minimumAge - 1),
            launchCount: ReviewPromptPolicy.minimumLaunches,
            successfulSaves: ReviewPromptPolicy.minimumSaves,
            lastRequestedVersion: nil
        )
    }

    @Test("조건을 다 채우면 묻는다")
    func eligibleAsks() {
        #expect(eligible().shouldRequest(now: now, currentVersion: "1.1.0"))
    }

    @Test("첫 실행에는 묻지 않는다")
    func neverOnFirstLaunch() {
        var policy = eligible()
        policy.firstLaunchAt = now
        #expect(!policy.shouldRequest(now: now, currentVersion: "1.1.0"))
    }

    @Test("이름조차 모르는 사용자에게 묻지 않는다")
    func neverWithoutAFirstLaunch() {
        var policy = eligible()
        policy.firstLaunchAt = nil
        #expect(!policy.shouldRequest(now: now, currentVersion: "1.1.0"))
    }

    @Test("몇 번 써 본 사람에게만 묻는다")
    func needsRepeatUse() {
        var policy = eligible()
        policy.launchCount = ReviewPromptPolicy.minimumLaunches - 1
        #expect(!policy.shouldRequest(now: now, currentVersion: "1.1.0"))
    }

    @Test("성공 경험이 쌓여야 묻는다")
    func needsSuccessfulSaves() {
        var policy = eligible()
        policy.successfulSaves = ReviewPromptPolicy.minimumSaves - 1
        #expect(!policy.shouldRequest(now: now, currentVersion: "1.1.0"))
    }

    @Test("같은 버전에서 두 번 묻지 않는다")
    func onceParVersion() {
        var policy = eligible()
        policy.lastRequestedVersion = "1.1.0"
        #expect(!policy.shouldRequest(now: now, currentVersion: "1.1.0"))
        // 새 버전에서는 다시 물어볼 수 있다.
        #expect(policy.shouldRequest(now: now, currentVersion: "1.2.0"))
    }

    @Test("공식 API만 쓴다")
    func officialAPIOnly() throws {
        let editor = try source("ggumirror/Editor/EditorView.swift")
        #expect(editor.contains("@Environment(\\.requestReview)"))
        // 별점 UI를 우리가 만들지 않는다.
        for darkPattern in ["별점", "5점", "StarRating", "rateUs"] {
            #expect(!editor.contains(darkPattern), "직접 만든 리뷰 UI: \(darkPattern)")
        }
    }

    @Test("실패한 저장에서는 묻지 않는다")
    func neverAfterFailure() throws {
        let editor = try source("ggumirror/Editor/EditorView.swift")
        // `needsMoreSlots`(보관 공간 부족)에서는 부르지 않는다.
        let start = try #require(editor.range(of: "case .needsMoreSlots")).upperBound
        let end = editor.range(of: "private func recordSuccessfulSave", range: start..<editor.endIndex)?.lowerBound
            ?? editor.endIndex
        #expect(!editor[start..<end].contains("recordSuccessfulSave"))
    }

    @Test("표시 여부를 안다고 적지 않는다")
    func recordsAttemptNotDisplay() throws {
        let code = try source("ggumirror/Shared/ReviewPrompt.swift")
        // 창이 실제로 떴는지는 OS만 안다.
        #expect(code.contains("func recordRequestAttempt"))
        #expect(!code.contains("didDisplay"))
        #expect(!code.contains("wasShown"))
    }

    @Test("서버에 아무것도 보내지 않는다")
    func costsNothing() throws {
        let code = try source("ggumirror/Shared/ReviewPrompt.swift")
        for forbidden in ["backend", "URLSession", "await ", "accessToken"] {
            #expect(!code.contains(forbidden), "리뷰 정책이 \(forbidden)를 쓴다")
        }
    }
}
