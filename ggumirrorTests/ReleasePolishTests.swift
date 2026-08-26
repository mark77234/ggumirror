//
//  ReleasePolishTests.swift
//  ggumirrorTests
//
//  I-2 · I-5 · I-6 · I-8 · I-10. 실기기 QA에서 나온 것만.
//

import Testing
import Foundation
@testable import ggumirror

private func polish(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

// MARK: - I-2

@Suite("탭 막대에 가리지 않는다")
struct BottomSafeAreaTests {

    private let scrollScreens = [
        "ggumirror/Home/SettingsView.swift",
        "ggumirror/Home/ProfileView.swift",
        "ggumirror/Notifications/NotificationCenterView.swift",
        "ggumirror/Admin/AdminStoreView.swift",
        "ggumirror/MyMirrors/MyMirrorsView.swift",
        "ggumirror/Store/StoreView.swift",
        "ggumirror/Store/TemplateDetailView.swift",
        "ggumirror/Store/MarketplaceGallery.swift",
    ]

    @Test("여백 authority가 한 곳이다")
    func oneSharedAuthority() {
        // 막대 높이가 바뀌면 여기 한 곳만 바뀐다.
        #expect(InkTabBar.reservedHeight == 108)
        #expect(InkTabBar.contentBreathingRoom > 0)
    }

    @Test("탭 막대 위 화면이 모두 같은 규칙을 쓴다")
    func everyScrollScreenUsesIt() throws {
        for path in scrollScreens {
            #expect(try polish(path).contains("inkTabBarSafeContent()"), "\(path)")
        }
    }

    @Test("화면마다 숫자를 적지 않는다")
    func noPerScreenMagicNumbers() throws {
        for path in scrollScreens {
            let code = try polish(path)
            // 예전에는 화면마다 `reservedHeight + 24`를 복붙했다.
            #expect(!code.contains("InkTabBar.reservedHeight +"), "\(path)")
            // 막대를 모르는 채로 적어 둔 값도 없다.
            #expect(!code.contains("padding(.bottom, 120)"), "\(path)")
            #expect(!code.contains("padding(.bottom, 40)"), "\(path)")
        }
    }

    @Test("여백이 막대보다 크다")
    func insetClearsTheBar() {
        // Dynamic Type이 커져도 막대 높이는 이 값이 상한이다.
        #expect(InkTabBar.reservedHeight + InkTabBar.contentBreathingRoom > InkTabBar.reservedHeight)
    }
}

// MARK: - I-5

@Suite("거울 미리보기 가운데 정렬")
struct MirrorPreviewCenteringTests {

    @Test("맞춘 뒤 가운데로 놓는다")
    func previewIsCenteredAfterFitting() throws {
        let card = try polish("ggumirror/Store/StoreMirrorCard.swift")
        // `.aspectRatio(.fit)`가 내놓는 크기를 다시 가운데로 놓는다.
        // 이 frame이 없으면 부모 VStack(.leading)이 왼쪽으로 붙인다.
        #expect(card.contains("frame(maxWidth: .infinity, alignment: .center)"))
    }

    @Test("비율도 content mode도 그대로다")
    func aspectAndContentModeUnchanged() throws {
        let card = try polish("ggumirror/Store/StoreMirrorCard.swift")
        #expect(card.contains("aspectRatio(StoreMirrorCardMetrics.previewRatio, contentMode: .fit)"))
        // 늘리지 않는다.
        #expect(!card.contains("contentMode: .fill"))
        #expect(!card.contains("scaledToFill"))
    }

    @Test("내장 거울 상세는 그대로다")
    func builtInDetailUnchanged() throws {
        let detail = try polish("ggumirror/Store/TemplateDetailView.swift")
        // 내장은 원래 정상이었다 — 손대지 않았다.
        #expect(detail.contains("MirrorPreview(template: template"))
    }
}

// MARK: - I-6

@Suite("구매와 내 거울 등록은 다른 일이다")
struct PurchaseRegistrationTests {

    @Test("구매 성공 뒤 등록을 안내한다")
    func successAsksToRegister() throws {
        let code = try polish("ggumirror/Store/MarketplaceGallery.swift")
        #expect(code.contains("showsRegistrationPrompt = true"))
        #expect(code.contains("구매 완료!"))
        #expect(code.contains("내 거울에 등록하기"))
        #expect(code.contains("나중에"))
    }

    @Test("등록은 기존 흐름을 그대로 쓴다")
    func registrationReusesTheExistingImport() throws {
        let code = try polish("ggumirror/Store/MarketplaceGallery.swift")
        // 새 복사 경로를 만들지 않았다 — 보관 공간 확인도 실패 안내도 거기 있다.
        #expect(code.contains("Task { await runImport() }"))
        #expect(code.contains("importer.importMirror"))
    }

    @Test("나중에는 아무것도 등록하지 않는다")
    func laterKeepsOwnershipOnly() throws {
        let code = try polish("ggumirror/Store/MarketplaceGallery.swift")
        let start = try #require(code.range(of: "InkDialogAction(\"나중에\"")).upperBound
        let action = code[start...].prefix(80)
        // 닫기만 한다. 몰래 등록하지 않는다.
        #expect(!action.contains("runImport"))
    }

    @Test("스티커에는 이 안내를 쓰지 않는다")
    func stickersAreUnaffected() throws {
        let code = try polish("ggumirror/Store/MarketplaceGallery.swift")
        #expect(code.contains("!ListingPreviewStyle.isSticker(listing.contentType)"))
    }

    @Test("CTA가 상태에 따라 갈린다")
    func ctaFollowsOwnershipState() {
        // 이미 있던 상태 모델을 그대로 쓴다 — 새로 만들지 않았다.
        let unowned = MirrorAcquireCTA.state(
            price: 3, isSignedIn: true, ownsOnServer: false, existsLocally: false
        )
        let owned = MirrorAcquireCTA.state(
            price: 3, isSignedIn: true, ownsOnServer: true, existsLocally: false
        )
        let registered = MirrorAcquireCTA.state(
            price: 3, isSignedIn: true, ownsOnServer: true, existsLocally: true
        )
        #expect(unowned.title.contains("조각"))
        #expect(owned.title == "내 거울에 추가")
        #expect(registered.title == "이미 내 거울에 있어요")
        #expect(!registered.isEnabled)
    }
}

// MARK: - I-8

@Suite("AI 생성 중에는 잃지 않는다")
struct AIGenerationWaitingTests {

    @Test("만드는 동안 닫히지 않는다")
    func sheetIsLockedWhileGenerating() throws {
        let view = try polish("ggumirror/MyMirrors/AIMirrorView.swift")
        #expect(view.contains("inkSheetDismissDisabled(maker.isGenerating)"))
    }

    @Test("끝나면 다시 닫을 수 있다")
    func lockFollowsTheGeneratingFlagOnly() throws {
        let view = try polish("ggumirror/MyMirrors/AIMirrorView.swift")
        // 성공/실패 여부가 아니라 **생성 중인지**만 본다 — 끝나면 바로 풀린다.
        #expect(!view.contains("inkSheetDismissDisabled(true)"))
    }

    @Test("커스텀 시트라 시스템 modifier가 아니다")
    func lockIsImplementedForTheCustomSheet() throws {
        let modal = try polish("ggumirror/Shared/InkModal.swift")
        // 끌기와 배경 탭 **둘 다** 막아야 실제로 닫히지 않는다.
        #expect(modal.contains("guard !isLocked else"))
        #expect(modal.contains("dismissesOnBackgroundTap && !isLocked"))
    }

    @Test("가짜 퍼센트를 보여 주지 않는다")
    func noFakeProgress() throws {
        let view = try polish("ggumirror/MyMirrors/AIMirrorView.swift")
        for fake in ["%", "progress =", "0.37", "percent"] {
            #expect(!view.contains(fake), "가짜 진행률 \(fake)")
        }
        #expect(view.contains("ProgressView()"))
    }

    @Test("보장하지 못하는 것을 말하지 않는다")
    func copyMatchesTheRealLifecycle() throws {
        let view = try polish("ggumirror/MyMirrors/AIMirrorView.swift")
        // 요청은 동기이고 `URLSession.shared`는 background 전송이 아니며
        // 서버는 결과를 저장하지 않는다 — 앱을 닫으면 그림은 사라진다.
        #expect(view.contains("이 화면을 유지해주세요"))
        #expect(!view.contains("앱을 꺼도"))
        #expect(!view.contains("백그라운드에서도"))
    }

    @Test("안전하게 멈출 수 없으면 취소 버튼을 만들지 않는다")
    func noFakeCancel() throws {
        let view = try polish("ggumirror/MyMirrors/AIMirrorView.swift")
        let maker = try polish("ggumirror/MyMirrors/AIMirrorView.swift")
        // client가 Task를 접어도 서버는 멈추지 않는다 — 조각만 나가고 그림은 없다.
        #expect(!view.contains("생성 취소"))
        #expect(!maker.contains("func cancelGeneration"))
    }

    @Test("연타로 두 번 만들지 않는다")
    func duplicateSubmitIsBlocked() throws {
        let view = try polish("ggumirror/MyMirrors/AIMirrorView.swift")
        #expect(view.contains("guard !isGenerating else { return }"))
        #expect(view.contains("disabled(maker.isGenerating)"))
    }

    @Test("I-7 경제 계약을 건드리지 않았다")
    func economyContractUnchanged() throws {
        let view = try polish("ggumirror/MyMirrors/AIMirrorView.swift")
        #expect(view.contains("requestID: UUID().uuidString"))
        #expect(view.contains("wallet?.refresh(session: session.server)"))
    }
}

// MARK: - I-10

@Suite("알림 설명이 먼저다")
@MainActor
struct NotificationOnboardingTests {

    private func onboarding() -> NotificationOnboarding {
        let suite = UserDefaults(suiteName: "onboarding-\(UUID().uuidString)")!
        return NotificationOnboarding(defaults: suite)
    }

    @Test("아직 안 물어본 사람에게만 보여 준다")
    func onlyWhenUndetermined() {
        let store = onboarding()
        #expect(store.shouldPresent(permission: .notAsked))
        // 이미 정한 사람에게 다시 설명할 것이 없다.
        #expect(!store.shouldPresent(permission: .allowed))
        #expect(!store.shouldPresent(permission: .denied))
    }

    @Test("한 번 보여 준 뒤에는 다시 띄우지 않는다")
    func neverRepeats() {
        let store = onboarding()
        store.presentIfNeeded(permission: .notAsked)
        #expect(store.isPresented)
        #expect(store.hasSeen)

        store.isPresented = false
        // 권한이 여전히 notDetermined여도 다시 띄우지 않는다 — 그건 조르기다.
        store.presentIfNeeded(permission: .notAsked)
        #expect(!store.isPresented)
    }

    @Test("앱을 다시 켜도 반복하지 않는다")
    func survivesRelaunch() {
        let suite = UserDefaults(suiteName: "onboarding-\(UUID().uuidString)")!
        NotificationOnboarding(defaults: suite).presentIfNeeded(permission: .notAsked)

        let relaunched = NotificationOnboarding(defaults: suite)
        #expect(relaunched.hasSeen)
        #expect(!relaunched.shouldPresent(permission: .notAsked))
    }

    @Test("나중에는 시스템 창을 부르지 않는다")
    func laterNeverAsksTheSystem() throws {
        let sheet = try polish("ggumirror/Notifications/NotificationOnboardingSheet.swift")
        let start = try #require(sheet.range(of: "onLater()")).lowerBound
        // `나중에` 경로에는 권한 요청이 없다.
        let after = sheet[start...].prefix(200)
        #expect(!after.contains("requestAuthorization"))
        #expect(!after.contains("onAllow"))
    }

    @Test("알림 받기에서만 권한을 요청한다")
    func allowAsksExactlyOnce() throws {
        let root = try polish("ggumirror/RootView.swift")
        // 허락 경로만 기존 enable()을 부른다 — 그 안에서 시스템 창이 뜬다.
        #expect(root.contains("await dailyReminder.enable()"))
        // 시작 경로는 여전히 refresh뿐이다(창을 띄우지 않는다).
        #expect(root.contains("dailyReminder.refresh()"))
    }

    @Test("첫 프레임에 던지지 않는다")
    func notOnTheVeryFirstFrame() throws {
        let root = try polish("ggumirror/RootView.swift")
        // 거울을 보고 홈까지 온 뒤에 보여 준다.
        #expect(root.contains("onChange(of: screen)"))
        #expect(root.contains("presentIfNeeded"))
    }

    @Test("거부한 사람은 설정에서 켤 수 있다")
    func deniedHasAWayBack() throws {
        let settings = try polish("ggumirror/Home/SettingsView.swift")
        #expect(settings.contains("permission == .denied"))
        #expect(settings.contains("openSettingsURLString"))
    }
}
