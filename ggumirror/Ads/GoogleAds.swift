//
//  GoogleAds.swift
//  ggumirror
//
//  Google Mobile Ads / UMP SDK에 **직접 닿는 유일한 파일.**
//
//  나머지 광고 코드(`RewardedAdController` · `AdsConsent`)는 protocol만 보고,
//  SDK 타입을 알지 못한다. SDK가 바뀌면 고칠 곳이 여기 하나다.
//
//  이 파일에도 **조각을 더하는 코드는 없다.** 광고를 다 봤다는 신호(`userDidEarnReward`)는
//  UI 상태를 바꾸는 데만 쓰이고, 실제 지급은 Google이 우리 서버로 보내는
//  SSV callback을 검증한 뒤에만 일어난다.
//

import Foundation
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

// MARK: - Mobile Ads 시작

nonisolated enum MobileAdsStarter {
    /// 동의 확인이 끝난 뒤에만 불린다. `AdsConsent`가 한 번만 부르도록 보장한다.
    static func start() {
        AdLog.diagnostic("mobile ads start requested")
        MobileAds.shared.start { status in
            // adapter가 몇 개 준비됐는지만 남긴다. adapter 이름/상세는 담지 않는다.
            AdLog.diagnostic("mobile ads started adapters=\(status.adapterStatusesByClassName.count)")
        }
    }
}

// MARK: - 화면 꼭대기 view controller

/// UMP 양식과 광고는 UIKit view controller 위에 뜬다.
/// SwiftUI 쪽에 UIKit을 퍼뜨리지 않도록 여기서만 찾는다.
@MainActor
private func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
    var controller = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    while let presented = controller?.presentedViewController {
        controller = presented
    }
    return controller
}

// MARK: - UMP

/// 실제 UMP 구현. 지역 판단도 양식 내용도 **전부 UMP가 정한다.**
nonisolated struct UMPConsentGateway: AdsConsentGateway {
    func requestUpdate() async {
        let parameters = RequestParameters()
        AdLog.diagnostic("consent update started")
        await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                if let error = error as NSError? {
                    // 동의 정보를 못 받았다. 광고만 못 나갈 뿐 앱은 그대로 동작한다.
                    AdLog.diagnostic(
                        "consent update failed domain=\(error.domain) code=\(error.code)"
                    )
                } else {
                    AdLog.diagnostic("consent update completed")
                }
                continuation.resume()
            }
        }
    }

    /// 진단용 상태 이름. **동의 내용이 아니라 상태 분류만** 담는다.
    var diagnosticStatus: String {
        get async {
            let information = ConsentInformation.shared
            let status: String = switch information.consentStatus {
            case .notRequired: "notRequired"
            case .required: "required"
            case .obtained: "obtained"
            case .unknown: "unknown"
            @unknown default: "unrecognized"
            }
            let privacyOptions: String = switch information.privacyOptionsRequirementStatus {
            case .required: "required"
            case .notRequired: "notRequired"
            case .unknown: "unknown"
            @unknown default: "unrecognized"
            }
            return "consentStatus=\(status) privacyOptions=\(privacyOptions)"
        }
    }

    @MainActor
    func presentFormIfRequired() async {
        await withCheckedContinuation { continuation in
            ConsentForm.loadAndPresentIfRequired(from: topViewController()) { error in
                if error != nil { AdLog.event("consent form failed") }
                continuation.resume()
            }
        }
    }

    var canRequestAds: Bool {
        get async { ConsentInformation.shared.canRequestAds }
    }

    var privacyOptionsRequired: Bool {
        get async { ConsentInformation.shared.privacyOptionsRequirementStatus == .required }
    }

    @MainActor
    func presentPrivacyOptions() async {
        await withCheckedContinuation { continuation in
            ConsentForm.presentPrivacyOptionsForm(from: topViewController()) { error in
                if error != nil { AdLog.event("privacy options form failed") }
                continuation.resume()
            }
        }
    }
}

// MARK: - Rewarded

/// 실제 rewarded 광고 하나를 준비하고 보여준다.
///
/// **보상을 주지 않는다.** `present`가 `.watched`를 돌려줘도 그것은
/// "사용자가 조건을 채웠다"는 UI 신호일 뿐이고, 조각은 서버가 SSV를 검증한 뒤에 늘어난다.
@MainActor
final class GoogleRewardedAdPresenter: NSObject, RewardedAdPresenting {
    /// 받아 둔 광고. Google은 대략 1시간이면 만료된다고 안내한다.
    private var ad: RewardedAd?
    private var loadedAt: Date?
    private var isLoading = false

    /// 만료 여유를 두고 다시 받는다. 만료된 광고를 present하면 실패한다.
    private static let freshness: TimeInterval = 50 * 60

    /// 광고가 닫힐 때까지 기다리는 쪽.
    private var completion: CheckedContinuation<RewardedAdResult, Never>?
    /// 이번 광고에서 보상 조건을 채웠는가. **닫기만 한 경우와 구분해야 한다.**
    private var didEarnReward = false

    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        super.init()
    }

    // MARK: 준비

    func load(adUnit: String) async {
        guard !isLoading, !isFresh else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await RewardedAd.load(with: adUnit, request: Request())
            loaded.fullScreenContentDelegate = self
            ad = loaded
            loadedAt = now()
            AdLog.diagnostic("rewarded load succeeded unitSuffix=\(AdLog.unitSuffix(adUnit))")
        } catch {
            // 못 받았다. 조각과는 아무 상관이 없다 — 화면만 "불러오지 못했어요"가 된다.
            //
            // **error를 버리지 않는다.** 예전에는 여기서 전부 삼켜서, Release에서
            // 광고가 안 뜰 때 no fill인지 설정 오류인지 네트워크인지 알 수 없었다.
            ad = nil
            loadedAt = nil
            AdLog.diagnostic(
                "rewarded load failed unitSuffix=\(AdLog.unitSuffix(adUnit)) \(Self.summary(of: error))"
            )
            // 사람이 읽을 문장은 DEBUG에서만. Release 상시 로그에는 넣지 않는다.
            AdLog.event("rewarded ad load failed: \((error as NSError).localizedDescription)")
        }
    }

    var isReady: Bool { get async { isFresh } }

    /// 오래된 광고를 무한히 재사용하지 않는다.
    private var isFresh: Bool {
        guard ad != nil, let loadedAt else { return false }
        return now().timeIntervalSince(loadedAt) < Self.freshness
    }

    // MARK: 보여주기

    /// `context`는 **서버가 발급한 짧은 수명의 값**이다.
    /// session token도, Apple token도, 내부 user id도 아니다.
    func present(context: String) async -> RewardedAdResult {
        guard let ad, isFresh else { return .unavailable }

        // 이번 광고에만 붙는 SSV 정보. present 직전에 붙여서
        // 미리 받아 둔 광고에 예전 context가 남아 있을 수 없게 한다.
        let options = ServerSideVerificationOptions()
        options.customRewardText = context
        ad.serverSideVerificationOptions = options

        didEarnReward = false
        self.ad = nil          // 한 번 보여준 광고는 다시 쓰지 않는다.
        loadedAt = nil

        return await withCheckedContinuation { continuation in
            completion = continuation
            // 인자 이름을 생략하지 않는다 — 이 closure가 "보상 지급"이 아니라
            // "사용자가 보상 조건을 채웠다"는 신호라는 것이 호출부에서 보여야 한다.
            ad.present(from: topViewController(), userDidEarnRewardHandler: { [weak self] in
                // **여기서 조각을 주지 않는다.** 서버가 Google 서명을 확인해야 지급이다.
                self?.didEarnReward = true
                AdLog.diagnostic("reward condition met")
            })
        }
    }

    /// load 실패를 **분류값으로만** 요약한다.
    ///
    /// 담는 것: error domain / code, adapter 응답 개수, 낙찰 adapter 유무,
    /// 첫 adapter의 class 이름과 error domain/code.
    /// **담지 않는 것**: `dictionaryRepresentation` 전체 dump · `responseIdentifier` ·
    /// `extras` · localizedDescription. 진단에 필요하지 않고 무엇이 들어 있는지 보장할 수 없다.
    private static func summary(of error: any Error) -> String {
        let failure = error as NSError
        var parts = ["domain=\(failure.domain)", "code=\(failure.code)"]

        guard let info = failure.userInfo[GADErrorUserInfoKeyResponseInfo] as? ResponseInfo else {
            // ResponseInfo가 없다는 것도 정보다 — 요청이 Google까지 가지 못한 경우가 많다.
            parts.append("responseInfo=none")
            return parts.joined(separator: " ")
        }

        parts.append("adapters=\(info.adNetworkInfoArray.count)")
        parts.append("loadedAdapter=\(info.loadedAdNetworkResponseInfo != nil)")
        if let first = info.adNetworkInfoArray.first {
            parts.append("adapter=\(first.adNetworkClassName)")
            if let adapterError = first.error as NSError? {
                parts.append("adapterDomain=\(adapterError.domain)")
                parts.append("adapterCode=\(adapterError.code)")
            }
        }
        return parts.joined(separator: " ")
    }

    private func finish(_ result: RewardedAdResult) {
        guard let completion else { return }
        self.completion = nil
        completion.resume(returning: result)
    }
}

// MARK: - 광고 화면 생명주기

extension GoogleRewardedAdPresenter: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        AdLog.diagnostic("rewarded dismissed earned=\(didEarnReward)")
        // 보상 조건을 채웠을 때만 `.watched`다.
        // 중간에 닫은 경우까지 `.watched`로 만들면, 오지 않을 SSV를 기다리게 된다.
        finish(didEarnReward ? .watched : .dismissed)
    }

    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        let failure = error as NSError
        AdLog.diagnostic("rewarded present failed domain=\(failure.domain) code=\(failure.code)")
        finish(.unavailable)
    }
}
