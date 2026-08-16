//
//  AdsConsent.swift
//  ggumirror
//
//  광고를 요청해도 되는지 **먼저 묻는다.**
//
//  Google UMP(User Messaging Platform)가 지역 규제(EU GDPR · 미국 주법 등)에 맞는
//  동의 양식을 관리한다. 우리가 지역을 판단하거나 동의 UI를 직접 만들지 않는다 —
//  어떤 양식이 필요한지는 AdMob console 설정과 UMP가 정한다.
//
//  **여기서 지키는 것 두 가지:**
//  1. `canRequestAds`가 true가 되기 전에는 광고를 부르지 않는다
//  2. Mobile Ads 초기화는 **정확히 한 번**이다. 동의가 이미 있는 경우와
//     방금 받은 경우 두 경로 모두 여기로 들어오기 때문이다
//
//  그리고 이 과정이 **Mirror를 막지 않는다.** 꾸미러는 실행하면 거울이 먼저다.
//  동의 확인은 화면이 뜬 뒤 비동기로 하고, 실패하든 늦든 카메라를 붙잡지 않는다.
//

import Foundation

// MARK: - UMP 경계

/// 동의 상태를 묻고 양식을 띄우는 능력. 실제 구현은 `UMPConsentGateway`다.
///
/// protocol로 떼어 둔 이유는 하나다 — test가 SDK 없이 흐름을 확인하기 위해서다.
nonisolated protocol AdsConsentGateway: Sendable {
    /// 지금 지역/설정에 맞는 동의 정보를 새로 받아온다. 앱 실행마다 한 번 부른다.
    func requestUpdate() async
    /// 필요하면 동의 양식을 띄운다. 필요 없으면 아무 일도 하지 않는다.
    func presentFormIfRequired() async
    var canRequestAds: Bool { get async }
    /// 설정에 "광고 개인정보 설정" 항목을 보여줘야 하는가.
    var privacyOptionsRequired: Bool { get async }
    /// 진단용 상태 이름(동의 내용이 아니라 분류만).
    var diagnosticStatus: String { get async }
    /// 사용자가 그 항목을 눌렀을 때.
    func presentPrivacyOptions() async
}

// MARK: - 상태

@Observable
@MainActor
final class AdsConsent {
    /// 앱이 쓰는 하나뿐인 동의 상태.
    static let live = AdsConsent()

    /// 광고를 요청해도 되는가. **false면 광고를 load하지 않는다.**
    private(set) var canRequestAds = false
    /// 설정에 "광고 개인정보 설정"을 보여줄지. UMP가 필요하다고 할 때만 true다.
    private(set) var showsPrivacyOptions = false

    /// Mobile Ads를 이미 시작했는가. **두 번 시작하지 않기 위한 전부**다 —
    /// 상태 기계를 만들지 않는다.
    private var hasStartedMobileAds = false

    private let gateway: any AdsConsentGateway
    private let startMobileAds: @Sendable () -> Void

    init(
        gateway: any AdsConsentGateway = UMPConsentGateway(),
        startMobileAds: @escaping @Sendable () -> Void = { MobileAdsStarter.start() }
    ) {
        self.gateway = gateway
        self.startMobileAds = startMobileAds
    }

    /// 앱 실행마다 한 번. **화면이 뜬 뒤에** 부른다.
    ///
    /// 동의가 이미 있으면 양식은 뜨지 않고 그대로 통과한다.
    /// 어느 경로로 통과하든 Mobile Ads 시작은 한 번뿐이다.
    func bootstrap() async {
        await gateway.requestUpdate()
        await gateway.presentFormIfRequired()

        canRequestAds = await gateway.canRequestAds
        showsPrivacyOptions = await gateway.privacyOptionsRequired
        AdLog.diagnostic(
            "consent resolved \(await gateway.diagnosticStatus) canRequestAds=\(canRequestAds)"
        )

        guard canRequestAds, !hasStartedMobileAds else { return }
        hasStartedMobileAds = true
        startMobileAds()
    }

    /// 설정 → 광고 개인정보 설정.
    func presentPrivacyOptions() async {
        await gateway.presentPrivacyOptions()
        // 양식에서 동의를 철회했을 수 있다. 상태를 다시 읽는다.
        canRequestAds = await gateway.canRequestAds
        showsPrivacyOptions = await gateway.privacyOptionsRequired
    }
}
