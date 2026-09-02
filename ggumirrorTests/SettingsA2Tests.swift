//
//  SettingsA2Tests.swift
//  ggumirrorTests
//
//  설정 화면의 세 가지: **소모품 복원 제거 · 법적 링크 · 리뷰 요청.**
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

// MARK: - 소모품 복원 제거 (App Store 3.1.1)

/// 조각은 consumable이다. **Apple의 구매 복원으로 되돌리지 않는다** —
/// 소모품은 그렇게 복원되지 않고, Apple도 그런 UI를 금지한다(Guideline 3.1.1).
/// 잔액의 authority는 서버 원장이고, 같은 계정으로 로그인하면 그대로 다시 읽어 온다.
@Suite("소모품 복원 UI와 StoreKit restore 경로가 없다")
struct ConsumableRestoreRemovalTests {

    @Test("설정에 구매 복원 항목이 없다")
    func settingsHasNoRestoreRow() throws {
        let settings = try source("ggumirror/Home/SettingsView.swift")
        for forbidden in ["구매 복원", "PurchaseRestore", "restoreState"] {
            #expect(!settings.contains(forbidden), "설정에 \(forbidden)이 남아 있다")
        }
        // Apple 로그인은 그대로다 — 이쪽이 서버 잔액을 되찾는 정상 경로다.
        #expect(settings.contains("AccountSection(session: session)"))
    }

    @Test("앱 코드 어디에도 StoreKit restore 호출이 없다")
    func noStoreKitRestoreAnywhere() throws {
        for forbidden in ["AppStore.sync", "restoreCompletedTransactions", "currentEntitlements"] {
            #expect(!appSources().contains { $0.contains(forbidden) }, "\(forbidden) 호출이 남아 있다")
        }
    }

    /// iPad(Apple 심사 기기가 iPad Air 11" M3였다)에서만 다른 설정 화면이 뜨는 길이 없어야
    /// 한다. **설정은 구현이 하나뿐이고**, 기기·size class로 갈라지지 않는다 —
    /// 갈라지는 순간 한쪽에만 복원 항목이 남아도 다른 쪽 테스트는 초록으로 통과한다.
    @Test("기기별로 다른 설정 화면이 없다")
    func settingsHasNoDeviceSpecificVariant() throws {
        for forbidden in ["horizontalSizeClass", "verticalSizeClass", "userInterfaceIdiom"] {
            #expect(!appSources().contains { $0.contains(forbidden) }, "\(forbidden) 분기가 생겼다")
        }
        // `#if DEBUG` 말고 다른 조건부 컴파일이 없다 — Release에서만 살아나는 길도 없다.
        for line in appSources().flatMap({ $0.split(separator: "\n") }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if") {
                #expect(trimmed == "#if DEBUG", "예상 못 한 조건부 컴파일: \(trimmed)")
            }
        }
    }

    @Test("정상 구매 처리는 그대로 있다")
    func purchaseProcessingSurvives() throws {
        let store = try source("ggumirror/IAP/StoreKitShardStore.swift")
        // 미완료 거래 되찾기는 복원이 아니라 **결제 완결**이다. 없애지 않는다.
        #expect(store.contains("Transaction.unfinished"))
        #expect(store.contains("Transaction.updates"))
    }
}

/// 앱 target의 Swift 소스 전부(주석 제거). 테스트 코드는 보지 않는다.
private func appSources() -> [String] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "ggumirror")
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    else { return [] }
    return walker.compactMap { entry in
        guard let url = entry as? URL, url.pathExtension == "swift",
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return codeWithoutComments(text)
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
        // 주소는 채워졌지만 **없을 때의 길은 그대로 남는다** — 나중에 문서를
        // 내리거나 주소를 바꾸는 동안 빈 페이지를 여는 대신 사람 말로 답한다.
        let settings = try source("ggumirror/Home/SettingsView.swift")
        #expect(settings.contains("guard let url else"))
        #expect(settings.contains("LegalLinks.notReadyMessage"))
    }

    @Test("두 링크가 실제 공개 문서를 가리킨다")
    func linksPointAtPublishedDocuments() throws {
        let privacy = try #require(LegalLinks.privacyPolicy)
        let terms = try #require(LegalLinks.termsOfService)

        // 사용자의 기기에서 열리는 주소다. http로 두면 App Store 심사에서 걸리고,
        // 무엇보다 중간에서 내용이 바뀔 수 있다.
        for url in [privacy, terms] {
            #expect(url.scheme == "https")
            #expect(url.host()?.isEmpty == false)
        }
        // **서로 다른 문서다.** 한 주소를 두 곳에 붙여 넣으면 약관을 눌러도
        // 개인정보처리방침이 열린다 — 눈으로는 잘 보이지 않는 실수다.
        #expect(privacy != terms)
    }

    @Test("둘은 서로 다른 주소다")
    func privacyAndTermsAreSeparate() throws {
        let settings = try source("ggumirror/Home/SettingsView.swift")
        #expect(settings.contains("url: LegalLinks.privacyPolicy"))
        #expect(settings.contains("url: LegalLinks.termsOfService"))
    }

    @Test("출시 준비 여부를 한 곳에서 판단한다")
    func releaseReadinessIsCheckable() {
        // 두 주소가 모두 채워졌다. 하나라도 비면 여기서 먼저 걸린다.
        #expect(LegalLinks.isReadyForRelease)
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
        // Apple 복원으로 소모품이 돌아온다고 쓰지 않았다 — 그런 기능은 없다.
        #expect(terms.contains("Apple의 구매 복원으로 되돌릴 수 없습니다"))
        #expect(terms.contains("같은 계정으로 다시 로그인하면 서버에 기록된 잔액이 그대로 보입니다"))
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
