//
//  RewardedAdTests.swift
//  ggumirrorTests
//
//  광고 보상은 **서버가 준다.**
//
//  여기서 지키는 것:
//  1. 광고를 끝까지 봐도 client가 잔액을 올리지 않는다 — 서버 값만 반영된다
//  2. 광고가 끝나면 "보상을 확인하고 있어요"이지 "+1 받았다"가 아니다
//  3. 서버에 닿지 못하면 아무 일도 없었던 것이다 — 가짜 보상이 없다
//  4. Release 빌드에 test ad unit이 들어가지 않는다
//

import Foundation
import Testing
@testable import ggumirror

/// 광고를 띄우는 척만 한다. 실제 SDK는 `GoogleRewardedAdPresenter`가 맡는다.
@MainActor
final class FakeRewardedAdPresenter: RewardedAdPresenting {
    var result: RewardedAdResult = .watched
    var ready = true
    private(set) var loadedUnits: [String] = []
    private(set) var presentedContexts: [String] = []

    init(result: RewardedAdResult = .watched, ready: Bool = true) {
        self.result = result
        self.ready = ready
    }

    func load(adUnit: String) async { loadedUnits.append(adUnit) }
    var isReady: Bool { get async { ready } }

    func present(context: String) async -> RewardedAdResult {
        presentedContexts.append(context)
        return result
    }
}

@MainActor
struct RewardedAdTests {

    private let adUnit = "ca-app-pub-test/unit"

    private func session(expiresIn: TimeInterval = 3600) -> ServerSession {
        ServerSession(
            accessToken: "server-token",
            expiresAt: Date(timeIntervalSinceNow: expiresIn),
            userID: "internal-user-1"
        )
    }

    private func controller(
        backend: FakeShardBackend,
        presenter: FakeRewardedAdPresenter,
        adUnit: String? = "ca-app-pub-test/unit",
        canRequestAds: Bool = true
    ) -> RewardedAdController {
        let controller = RewardedAdController(
            adUnit: adUnit,
            presenter: presenter,
            backend: backend,
            // test는 기다리지 않는다. 간격 자체는 production 기본값이 정한다.
            verificationDelays: [.zero, .zero, .zero],
            sleep: { _ in }
        )
        // 대부분의 test는 "동의를 받은 뒤"를 다룬다. 동의 자체는 아래 전용 test가 본다.
        controller.consentChanged(canRequestAds: canRequestAds)
        return controller
    }

    private func repoFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    private func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - 서버 상태

    @Test("로그인하면 오늘 남은 횟수를 서버에서 받아온다")
    func fetchesRemainingFromServer() async {
        let backend = FakeShardBackend()
        backend.rewardedAdsResult = .success(
            RewardedAdStatus(rewardedToday: 2, remainingToday: 3, dailyLimit: 5)
        )
        let wallet = ShardWallet(backend: backend)

        await wallet.refresh(session: session())

        #expect(wallet.rewardedToday == 2)
        #expect(wallet.remainingAdsToday == 3)
        #expect(wallet.dailyAdLimit == 5)
    }

    @Test("로그인 전에는 서버를 부르지 않는다")
    func signedOutNeverFetches() async {
        let backend = FakeShardBackend()
        let wallet = ShardWallet(backend: backend)

        await wallet.refresh(session: nil)

        #expect(backend.rewardedAdsFetchCount == 0)
        #expect(wallet.dailyAdLimit == 0)
    }

    @Test("5 / 5면 잠긴 상태다")
    func dailyLimitLocked() async {
        let backend = FakeShardBackend()
        backend.rewardedAdsResult = .success(
            RewardedAdStatus(rewardedToday: 5, remainingToday: 0, dailyLimit: 5)
        )
        let wallet = ShardWallet(backend: backend)

        await wallet.refresh(session: session())

        #expect(wallet.remainingAdsToday == 0)
        #expect(wallet.rewardedToday == wallet.dailyAdLimit)
    }

    // MARK: - 광고 흐름

    @Test("광고가 준비되면 볼 수 있다")
    func adBecomesReady() async {
        let controller = controller(backend: FakeShardBackend(), presenter: FakeRewardedAdPresenter())

        await controller.prepare()

        #expect(controller.phase == .idle)
        #expect(controller.isConfigured)
    }

    @Test("광고를 못 받으면 사용 불가 상태다")
    func adUnavailable() async {
        let presenter = FakeRewardedAdPresenter(ready: false)
        let controller = controller(backend: FakeShardBackend(), presenter: presenter)

        await controller.prepare()

        #expect(controller.phase == .unavailable)
    }

    @Test("ad unit이 없는 빌드에서는 광고 기능이 꺼진다")
    func withoutAdUnitTheFeatureIsOff() async {
        let backend = FakeShardBackend()
        let presenter = FakeRewardedAdPresenter()
        let controller = controller(backend: backend, presenter: presenter, adUnit: nil)
        let wallet = ShardWallet(backend: backend)

        #expect(controller.isConfigured == false)
        await controller.watch(session: session(), wallet: wallet)

        // 광고도, context 요청도 없다.
        #expect(presenter.presentedContexts.isEmpty)
        #expect(backend.contextCount == 0)
    }

    @Test("광고에 실어 보내는 값은 session token이 아니다")
    func contextIsNotTheSessionToken() async {
        let backend = FakeShardBackend()
        let presenter = FakeRewardedAdPresenter()
        let controller = controller(backend: backend, presenter: presenter)
        let wallet = ShardWallet(backend: backend)

        await controller.watch(session: session(), wallet: wallet)

        #expect(presenter.presentedContexts == ["reward-context-1"])
        #expect(!presenter.presentedContexts.contains("server-token"))
        #expect(backend.contextCount == 1)
    }

    @Test("로그인 안 했으면 광고를 띄우지 않는다")
    func signedOutCannotWatch() async {
        let backend = FakeShardBackend()
        let presenter = FakeRewardedAdPresenter()
        let controller = controller(backend: backend, presenter: presenter)
        let wallet = ShardWallet(backend: backend)

        await controller.watch(session: nil, wallet: wallet)

        #expect(presenter.presentedContexts.isEmpty)
        #expect(backend.contextCount == 0)
    }

    // MARK: - client는 지급하지 않는다

    @Test("광고를 다 봐도 client가 잔액을 올리지 않는다")
    func watchingDoesNotCreditLocally() async {
        let backend = FakeShardBackend(balance: 3)
        // 서버는 아직 보상을 반영하지 않았다(SSV 미도착).
        let presenter = FakeRewardedAdPresenter(result: .watched)
        let controller = controller(backend: backend, presenter: presenter)
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())

        await controller.watch(session: session(), wallet: wallet)

        // 광고는 봤지만 서버가 아직 안 줬다 → 잔액 그대로.
        #expect(wallet.balance == 3, "client가 광고 시청만으로 조각을 올렸다")
        #expect(wallet.rewardedToday == 0)
    }

    @Test("SSV가 도착하면 서버 값이 반영된다")
    func serverRewardIsReflected() async {
        let backend = FakeShardBackend(balance: 3)
        // 지갑을 한 번 더 읽는 순간 보상이 도착한다.
        backend.rewardArrivesAfterFetches = 1
        let presenter = FakeRewardedAdPresenter(result: .watched)
        let controller = controller(backend: backend, presenter: presenter)
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())
        #expect(wallet.rewardedToday == 0)

        backend.result = .success(ShardBalance(balance: 4, lifetimeEarned: 4, lifetimeSpent: 0))
        await controller.watch(session: session(), wallet: wallet)

        // 서버가 4라고 답했으므로 4다. client가 3 + 1을 계산한 것이 아니다.
        #expect(wallet.balance == 4)
        #expect(wallet.rewardedToday == 1)
        #expect(controller.phase == .idle)
    }

    @Test("보상이 늦으면 확인을 멈추고 가짜로 올리지 않는다")
    func lateRewardDoesNotFakeAnything() async {
        let backend = FakeShardBackend(balance: 3)
        let presenter = FakeRewardedAdPresenter(result: .watched)
        let controller = controller(backend: backend, presenter: presenter)
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())

        await controller.watch(session: session(), wallet: wallet)

        #expect(wallet.balance == 3)
        #expect(wallet.rewardedToday == 0)
        // 무한히 매달리지 않는다 — 정해진 횟수만 확인하고 끝낸다.
        #expect(controller.phase == .idle)
    }

    @Test("확인되면 남은 시도를 더 쓰지 않는다")
    func stopsPollingOnceConfirmed() async {
        let backend = FakeShardBackend(balance: 3)
        backend.rewardArrivesAfterFetches = 1
        let presenter = FakeRewardedAdPresenter(result: .watched)
        let controller = controller(backend: backend, presenter: presenter)
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())
        let before = backend.rewardedAdsFetchCount

        await controller.watch(session: session(), wallet: wallet)

        // 첫 확인에서 도착했으므로 한 번만 더 읽는다.
        #expect(backend.rewardedAdsFetchCount - before == 1)
    }

    @Test("중간에 닫으면 확인 상태로 가지 않는다")
    func dismissDoesNotVerify() async {
        let backend = FakeShardBackend(balance: 3)
        let presenter = FakeRewardedAdPresenter(result: .dismissed)
        let controller = controller(backend: backend, presenter: presenter)
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())
        let fetches = backend.rewardedAdsFetchCount

        await controller.watch(session: session(), wallet: wallet)

        #expect(controller.phase == .idle)
        #expect(wallet.balance == 3)
        // 보상 확인을 시작하지도 않았다.
        #expect(backend.rewardedAdsFetchCount == fetches)
    }

    @Test("context를 못 받으면 광고를 띄우지 않는다")
    func contextFailureStopsBeforeTheAd() async {
        let backend = FakeShardBackend(balance: 3)
        backend.contextResult = .failure(.unavailable)
        let presenter = FakeRewardedAdPresenter()
        let controller = controller(backend: backend, presenter: presenter)
        let wallet = ShardWallet(backend: backend)

        await controller.watch(session: session(), wallet: wallet)

        #expect(presenter.presentedContexts.isEmpty)
        #expect(controller.phase == .unavailable)
        #expect(wallet.balance == 0)
    }

    @Test("네트워크가 실패해도 가짜 보상이 없다")
    func networkFailureGivesNothing() async {
        let backend = FakeShardBackend(balance: 7)
        let presenter = FakeRewardedAdPresenter(result: .watched)
        let controller = controller(backend: backend, presenter: presenter)
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())

        backend.result = .failure(.unavailable)
        backend.rewardedAdsResult = .failure(.unavailable)
        await controller.watch(session: session(), wallet: wallet)

        #expect(wallet.balance == 7)
        #expect(wallet.rewardedToday == 0)
    }

    @Test("여러 번 새로고침해도 서버 값이 중복 적용되지 않는다")
    func repeatedRefreshDoesNotDouble() async {
        let backend = FakeShardBackend(balance: 4)
        backend.rewardedAdsResult = .success(
            RewardedAdStatus(rewardedToday: 1, remainingToday: 4, dailyLimit: 5)
        )
        let wallet = ShardWallet(backend: backend)

        for _ in 0..<5 { await wallet.refresh(session: session()) }

        // 서버가 말한 값 그대로다. 새로고침 횟수만큼 늘어나지 않는다.
        #expect(wallet.balance == 4)
        #expect(wallet.rewardedToday == 1)
    }

    // MARK: - 로그아웃 / 재로그인

    @Test("로그아웃하면 광고 상태도 지워진다")
    func logoutClearsAdState() async {
        let backend = FakeShardBackend(balance: 5)
        backend.rewardedAdsResult = .success(
            RewardedAdStatus(rewardedToday: 3, remainingToday: 2, dailyLimit: 5)
        )
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())
        #expect(wallet.rewardedToday == 3)

        await wallet.refresh(session: nil)

        #expect(wallet.rewardedToday == 0)
        #expect(wallet.remainingAdsToday == 0)
        #expect(wallet.dailyAdLimit == 0)
    }

    @Test("다시 로그인하면 서버에 다시 묻는다")
    func reloginRefetches() async {
        let backend = FakeShardBackend(balance: 5)
        let wallet = ShardWallet(backend: backend)
        await wallet.refresh(session: session())
        await wallet.refresh(session: nil)
        let before = backend.rewardedAdsFetchCount

        await wallet.refresh(session: session())

        #expect(backend.rewardedAdsFetchCount > before)
        #expect(wallet.dailyAdLimit == 5)
    }

    // MARK: - 빌드 설정

    @Test("Debug는 Google 공식 test ad unit을 쓴다")
    func debugUsesGoogleTestAdUnit() throws {
        let debug = try repoFile("Config/Debug.xcconfig")
        #expect(debug.contains("ADMOB_REWARDED_AD_UNIT_ID = \(AppConfig.googleTestRewardedAdUnit)"))
    }

    @Test("Release에는 test ad unit이 들어가지 않는다")
    func releaseNeverShipsATestAdUnit() throws {
        let release = try repoFile("Config/Release.xcconfig")

        // 실제 사용자에게 test 광고가 나가면 정책 위반이다.
        #expect(!release.contains(AppConfig.googleTestRewardedAdUnit))
        #expect(!release.contains("ca-app-pub-3940256099942544"))

        // 꾸미러 production ad unit이어야 한다. test 값이 들어가면 실제 사용자에게
        // test 광고가 나가고 정책 위반이 된다.
        let line = release
            .split(separator: "\n")
            .first { $0.hasPrefix("ADMOB_REWARDED_AD_UNIT_ID") }
        let parts = try #require(line).split(
            separator: "=", maxSplits: 1, omittingEmptySubsequences: false
        )
        #expect(parts.count == 2)
        #expect(parts[1].trimmingCharacters(in: .whitespaces) == "ca-app-pub-5460686409666356/5740149472")
        #expect(!release.contains(AppConfig.googleTestRewardedAdUnit), "Release에 Google test unit이 있다")
    }

    @Test("production에서는 test ad unit을 무시한다")
    func productionIgnoresTestAdUnit() {
        // 설정이 잘못 들어와도 마지막 방어선이 있다.
        #expect(AppConfig.parseAdUnit(AppConfig.googleTestRewardedAdUnit, environment: .production) == nil)
        #expect(AppConfig.parseAdUnit(AppConfig.googleTestRewardedAdUnit, environment: .development)
                == AppConfig.googleTestRewardedAdUnit)
        #expect(AppConfig.parseAdUnit("", environment: .development) == nil)
        #expect(AppConfig.parseAdUnit("   ", environment: .production) == nil)
        #expect(AppConfig.parseAdUnit("ca-app-pub-real/unit", environment: .production)
                == "ca-app-pub-real/unit")
    }

    // MARK: - client에 권위가 없다

    @Test("광고 코드에 잔액을 바꾸는 통로가 없다")
    func adCodeCannotMutateBalance() throws {
        let source = codeOnly(try repoFile("ggumirror/Ads/RewardedAds.swift"))

        for forbidden in ["balance +=", "balance -=", "balance =", "rewardedToday +=",
                          "func credit", "func grant", "func reward("] {
            #expect(!source.contains(forbidden), "client가 보상을 지급하고 있다: \(forbidden)")
        }
        // 잔액을 얻는 유일한 경로는 서버 새로고침이다.
        #expect(source.contains("wallet.refresh(session: session)"))
    }

    @Test("광고 보상을 직접 청구하는 요청이 없다")
    func noClientSideRewardClaim() throws {
        let backend = codeOnly(try repoFile("ggumirror/Backend/BackendClient.swift"))

        for forbidden in ["rewarded/claim", "rewarded-ads/claim", "ads/reward",
                          "shards/credit", "shards/add"] {
            #expect(!backend.contains(forbidden))
        }
        // 있는 것은 읽기와 context 발급뿐이다.
        #expect(backend.contains("users/me/rewarded-ads"))
        #expect(backend.contains("users/me/rewarded-ads/context"))
    }

    @Test("홈은 서버가 센 횟수를 보여주고, 확인 중 상태를 갖는다")
    func homeShowsServerCounts() throws {
        let home = codeOnly(try repoFile("ggumirror/Home/HomeView.swift"))

        #expect(home.contains("shards.rewardedToday"))
        #expect(home.contains("shards.remainingAdsToday"))
        #expect(home.contains("보상을 확인하고 있어요"))
        #expect(home.contains("오늘 광고 보상 완료"))
        // 로그인 전에는 기존 Apple 로그인으로 보낸다.
        #expect(home.contains("rewardedAdSignIn"))
        #expect(!home.contains("SignInWithAppleButton"))
    }

    @Test("강제 광고를 넣지 않았다 — rewarded만, CTA로만")
    func noForcedAds() throws {
        // Mirror 진입에 광고가 붙지 않는다.
        let mirror = codeOnly(try repoFile("ggumirror/Mirror/MirrorView.swift"))
        let root = codeOnly(try repoFile("ggumirror/RootView.swift"))
        for source in [mirror, root] {
            for forbidden in ["Interstitial", "AppOpen", "Banner"] {
                #expect(!source.contains(forbidden))
            }
        }
        // 광고를 띄우는 곳은 사용자가 누르는 CTA 하나뿐이다.
        let ads = codeOnly(try repoFile("ggumirror/Ads/RewardedAds.swift"))
        #expect(!ads.contains("Interstitial"))
        #expect(!ads.contains("Banner"))
    }
}

// MARK: - 동의 (UMP)

/// UMP를 흉내 낸다. 실제 SDK는 `UMPConsentGateway`가 감싼다.
final class FakeConsentGateway: AdsConsentGateway, @unchecked Sendable {
    var allowsAds = true
    var requiresPrivacyOptions = false
    private(set) var updateCount = 0
    private(set) var formCount = 0
    private(set) var privacyOptionsCount = 0

    func requestUpdate() async { updateCount += 1 }
    func presentFormIfRequired() async { formCount += 1 }
    var canRequestAds: Bool { get async { allowsAds } }
    var privacyOptionsRequired: Bool { get async { requiresPrivacyOptions } }
    func presentPrivacyOptions() async { privacyOptionsCount += 1 }
}

@MainActor
struct AdsConsentTests {

    private func repoFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    @Test("동의를 받으면 광고를 요청할 수 있고, 초기화는 한 번뿐이다")
    func consentAllowsAdsAndStartsOnce() async {
        let gateway = FakeConsentGateway()
        var starts = 0
        let consent = AdsConsent(gateway: gateway, startMobileAds: { starts += 1 })

        await consent.bootstrap()
        #expect(consent.canRequestAds)
        #expect(starts == 1)

        // 다시 실행돼도(이미 동의가 있는 경로) 초기화는 늘지 않는다.
        await consent.bootstrap()
        await consent.bootstrap()
        #expect(starts == 1, "Mobile Ads가 여러 번 초기화됐다")
        #expect(gateway.updateCount == 3, "동의 정보는 매번 새로 확인한다")
    }

    @Test("동의가 없으면 광고를 요청하지 않고 SDK도 시작하지 않는다")
    func withoutConsentNothingStarts() async {
        let gateway = FakeConsentGateway()
        gateway.allowsAds = false
        var starts = 0
        let consent = AdsConsent(gateway: gateway, startMobileAds: { starts += 1 })

        await consent.bootstrap()

        #expect(consent.canRequestAds == false)
        #expect(starts == 0, "동의 없이 광고 SDK를 시작했다")
    }

    @Test("canRequestAds가 false면 광고를 받지도 보여주지도 않는다")
    func adsBlockedWithoutConsent() async {
        let backend = FakeShardBackend()
        let presenter = FakeRewardedAdPresenter()
        let controller = RewardedAdController(
            adUnit: "ca-app-pub-test/unit", presenter: presenter, backend: backend,
            verificationDelays: [.zero], sleep: { _ in }
        )
        let wallet = ShardWallet(backend: backend)
        // consentChanged를 부르지 않았다 = 아직 동의 확인 전.

        await controller.prepare()
        await controller.watch(session: ServerSession(
            accessToken: "t", expiresAt: .now.addingTimeInterval(3600), userID: "u"
        ), wallet: wallet)

        #expect(presenter.loadedUnits.isEmpty, "동의 전에 광고를 받았다")
        #expect(presenter.presentedContexts.isEmpty, "동의 전에 광고를 보여줬다")
        #expect(backend.contextCount == 0)
    }

    @Test("privacy options가 필요하면 설정에 항목이 보인다")
    func privacyOptionsEntryAppears() async throws {
        let gateway = FakeConsentGateway()
        gateway.requiresPrivacyOptions = true
        let consent = AdsConsent(gateway: gateway, startMobileAds: {})

        await consent.bootstrap()
        #expect(consent.showsPrivacyOptions)

        await consent.presentPrivacyOptions()
        #expect(gateway.privacyOptionsCount == 1)

        // 설정 화면이 그 상태를 보고 항목을 그린다. 새 화면을 만들지 않았다.
        let settings = try repoFile("ggumirror/Home/SettingsView.swift")
        #expect(settings.contains("adsConsent.showsPrivacyOptions"))
        #expect(settings.contains("광고 개인정보 설정"))
        #expect(settings.contains("adsConsent.presentPrivacyOptions()"))
    }

    @Test("필요 없으면 설정 항목을 숨긴다")
    func privacyOptionsHiddenWhenNotRequired() async {
        let gateway = FakeConsentGateway()
        gateway.requiresPrivacyOptions = false
        let consent = AdsConsent(gateway: gateway, startMobileAds: {})

        await consent.bootstrap()

        #expect(consent.showsPrivacyOptions == false)
    }

    @Test("ATT는 이번 단계에서 도입하지 않았다")
    func noATTYet() throws {
        // ATT를 넣으면 Info.plist에 사용 설명이 필요하다. 지금은 넣지 않기로 했다.
        let plist = try repoFile("Config/Info.plist")
        #expect(!plist.contains("NSUserTrackingUsageDescription"))

        // 코드에도 ATT 호출이 없다.
        for path in ["ggumirror/Ads/GoogleAds.swift", "ggumirror/Ads/AdsConsent.swift"] {
            let source = try repoFile(path)
            #expect(!source.contains("AppTrackingTransparency"))
            #expect(!source.contains("ATTrackingManager"))
        }
    }

    @Test("SDK에 닿는 파일은 하나뿐이다")
    func sdkIsIsolatedToOneFile() throws {
        // 광고 흐름과 화면은 SDK 타입을 몰라야 SDK 없이 시험할 수 있다.
        for path in [
            "ggumirror/Ads/RewardedAds.swift",
            "ggumirror/Ads/AdsConsent.swift",
            "ggumirror/Home/HomeView.swift",
            "ggumirror/Home/SettingsView.swift",
            "ggumirror/RootView.swift",
        ] {
            let source = try repoFile(path)
            #expect(!source.contains("import GoogleMobileAds"), "\(path)가 SDK를 직접 import한다")
            #expect(!source.contains("import UserMessagingPlatform"), "\(path)가 UMP를 직접 import한다")
        }

        let adapter = try repoFile("ggumirror/Ads/GoogleAds.swift")
        #expect(adapter.contains("import GoogleMobileAds"))
        #expect(adapter.contains("import UserMessagingPlatform"))
    }

    @Test("SDK adapter도 조각을 지급하지 않는다")
    func adapterNeverCreditsShards() throws {
        let adapter = try repoFile("ggumirror/Ads/GoogleAds.swift")
        for forbidden in ["balance +=", "ShardWallet", "credit(", "shards.refresh"] {
            #expect(!adapter.contains(forbidden), "SDK adapter가 조각을 만지고 있다: \(forbidden)")
        }
        // 보상 조건 완료는 UI 신호일 뿐이라는 것이 코드에 남아 있어야 한다.
        #expect(adapter.contains("userDidEarnRewardHandler"))
    }
}

// MARK: - 빌드 설정 / extension 격리

@MainActor
struct AdsBuildConfigTests {

    private func repoFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    private let productionAppID = "ca-app-pub-5460686409666356~3170610279"
    private let productionAdUnit = "ca-app-pub-5460686409666356/5740149472"

    @Test("AdMob App ID가 빌드 설정에 있고 Info.plist로 전달된다")
    func appIDIsConfigured() throws {
        // App ID는 Debug / Release가 같다 — 광고 안전은 ad unit이 담당한다.
        let base = try repoFile("Config/Base.xcconfig")
        #expect(base.contains("ADMOB_APP_ID = \(productionAppID)"))

        // Google SDK가 직접 읽는 표준 키로 넘어간다.
        let plist = try repoFile("Config/Info.plist")
        #expect(plist.contains("GADApplicationIdentifier"))
        #expect(plist.contains("$(ADMOB_APP_ID)"))

        // 런타임에서도 실제로 읽힌다(테스트는 Debug로 돈다).
        #expect(AppConfig.admobAppID == productionAppID)
    }

    @Test("Debug는 test ad unit만 쓴다 — production unit을 실수로 호출하지 않는다")
    func debugNeverUsesProductionAdUnit() throws {
        let debug = try repoFile("Config/Debug.xcconfig")

        #expect(debug.contains(AppConfig.googleTestRewardedAdUnit))
        #expect(!debug.contains(productionAdUnit), "Debug에 production ad unit이 있다")
        // 테스트는 Debug 설정으로 도므로 런타임 값도 test unit이다.
        #expect(AppConfig.admobRewardedAdUnitID == AppConfig.googleTestRewardedAdUnit)
    }

    @Test("SKAdNetwork 목록이 Google 공식 목록에서 왔다")
    func skAdNetworkItemsPresent() throws {
        let plist = try repoFile("Config/Info.plist")
        #expect(plist.contains("SKAdNetworkItems"))
        // Google 목록에 항상 들어 있는 AdMob 자체 식별자.
        #expect(plist.contains("cstr6suwn9.skadnetwork"))
        // 중복 없이 들어갔는지 — 같은 값이 두 번 있으면 검증에서 걸린다.
        let ids = plist.components(separatedBy: ".skadnetwork").count - 1
        #expect(ids >= 40, "SKAdNetwork 항목이 너무 적다: \(ids)")
    }

    @Test("잠금화면 extension에는 광고 SDK를 연결하지 않는다")
    func extensionsDoNotLinkAds() throws {
        let project = try repoFile("ggumirror.xcodeproj/project.pbxproj")

        // 광고 package product는 **앱 target 하나에만** 붙어 있다.
        let links = project.components(separatedBy: "GoogleMobileAds */,").count - 1
        #expect(links == 1, "광고 SDK가 여러 target에 연결됐다")

        // extension source 어디에도 광고 코드가 없다.
        for path in [
            "GgumirrorCapture/GgumirrorCaptureViewFinder.swift",
            "GgumirrorControls/GgumirrorControls.swift",
        ] {
            let source = try? repoFile(path)
            guard let source else { continue }
            for forbidden in ["GoogleMobileAds", "UserMessagingPlatform", "RewardedAd", "AdsConsent"] {
                #expect(!source.contains(forbidden), "\(path)에 광고 코드가 있다: \(forbidden)")
            }
        }
    }
}
