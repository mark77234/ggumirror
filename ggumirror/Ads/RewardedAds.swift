//
//  RewardedAds.swift
//  ggumirror
//
//  광고 보고 조각 받기 — **client는 지급하지 않는다.**
//
//  광고를 끝까지 봤다는 사실은 Google이 서버로 직접 알려준다(SSV).
//  앱이 "다 봤다"고 말하는 것은 검증되지 않은 입력이라 조각의 근거가 될 수 없다.
//  그래서 여기 어디에도 `balance += 1`이 없고, 있을 수도 없다 —
//  이 파일은 잔액을 만질 방법 자체를 갖고 있지 않다.
//
//  앱이 하는 일은 셋뿐이다:
//    1. 광고에 실어 보낼 context를 서버에서 받아온다
//    2. 광고를 띄운다
//    3. 광고가 닫히면 **서버 값을** 다시 읽는다
//
//  Google Mobile Ads SDK에 직접 닿는 코드는 `GoogleAds.swift` 하나뿐이다.
//  이 파일은 `RewardedAdPresenting` protocol만 알고 SDK 타입을 모른다 —
//  그래서 광고 흐름 전체를 SDK 없이 테스트할 수 있다.
//

import Foundation
import os

// MARK: - 광고를 띄우는 쪽 (SDK 경계)

/// 광고 한 편을 준비하고 보여주는 능력. **보상을 주지 않는다.**
///
/// 결과가 `.watched`여도 그것은 "UX가 끝났다"는 뜻일 뿐이다.
/// 조각이 늘었는지는 서버에 물어봐야 알 수 있다.
///
/// **`@MainActor`다.** Google SDK가 `present` / `canPresent`를 UI actor로 표시하고,
/// 광고는 실제로 화면 위에 뜨는 일이라 다른 곳에서 할 수 있는 척하지 않는다.
@MainActor
protocol RewardedAdPresenting: Sendable {
    /// 광고를 미리 받아 둔다. 실패해도 던지지 않는다 — 준비 여부는 `isReady`가 답한다.
    func load(adUnit: String) async
    var isReady: Bool { get async }
    /// 광고를 보여준다. `context`는 SSV에 실려 서버로 돌아간다.
    func present(context: String) async -> RewardedAdResult
}

nonisolated enum RewardedAdResult: Equatable, Sendable {
    /// 끝까지 봤다. **보상은 아직 확인되지 않았다.**
    case watched
    /// 사용자가 중간에 닫았다. 오류가 아니다.
    case dismissed
    /// 광고를 띄우지 못했다.
    case unavailable
}

// MARK: - 화면이 보는 상태

nonisolated enum RewardedAdPhase: Equatable, Sendable {
    case idle
    case loading
    case presenting
    /// 광고는 끝났고 서버 보상을 기다리는 중. **여기서 잔액을 올리지 않는다.**
    case verifying
    case unavailable
}

// MARK: - Controller

/// 광고 흐름만 맡는다. 잔액은 `ShardWallet`이, 지급은 서버가 한다.
@Observable
@MainActor
final class RewardedAdController {
    private(set) var phase: RewardedAdPhase = .idle

    /// 광고 기능을 쓸 수 있는 빌드인가. ad unit이 없으면 CTA 자체를 보여주지 않는다.
    var isConfigured: Bool { adUnit != nil }

    /// UMP가 "광고를 요청해도 된다"고 한 뒤에만 true다.
    /// **false인 동안에는 광고를 받지도 보여주지도 않는다** — 동의 없이 광고를 요청하지 않는다.
    private(set) var canRequestAds = false

    func consentChanged(canRequestAds: Bool) {
        self.canRequestAds = canRequestAds
    }

    private let adUnit: String?
    private let presenter: (any RewardedAdPresenting)?
    private let backend: any ShardBackend
    /// SSV가 도착할 때까지 기다리는 간격. 무한 polling을 하지 않는다.
    private let verificationDelays: [Duration]
    private let sleep: @Sendable (Duration) async -> Void

    init(
        adUnit: String? = AppConfig.admobRewardedAdUnitID,
        // 주지 않으면 실제 Google 구현을 쓴다(아래 init 본문). test는 가짜를 넣는다.
        // default 인자에서 만들 수 없다 — `GoogleRewardedAdPresenter`가 MainActor라
        // nonisolated인 default 인자 자리에서는 부를 수 없다.
        presenter: (any RewardedAdPresenting)? = nil,
        backend: any ShardBackend = BackendClient(),
        // 즉시 · 1초 · 2초 · 4초. 넷이면 대개 도착하고, 안 오면 다음 새로고침이 가져간다.
        verificationDelays: [Duration] = [.zero, .seconds(1), .seconds(2), .seconds(4)],
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.adUnit = adUnit
        self.presenter = presenter ?? GoogleRewardedAdPresenter()
        self.backend = backend
        self.verificationDelays = verificationDelays
        self.sleep = sleep
    }

    /// 광고를 미리 받아 둔다. CTA를 누르기 전에 부른다.
    func prepare() async {
        guard canRequestAds else { return }
        guard let adUnit, let presenter, phase == .idle || phase == .unavailable else { return }
        phase = .loading
        AdLog.diagnostic("rewarded preload started unitSuffix=\(AdLog.unitSuffix(adUnit))")
        await presenter.load(adUnit: adUnit)
        let ready = await presenter.isReady
        phase = ready ? .idle : .unavailable
        AdLog.diagnostic("rewarded preload finished ready=\(ready)")
    }

    /// CTA. 로그인돼 있어야 하고, 남은 횟수가 있어야 한다.
    ///
    /// 광고가 끝나면 **서버 지갑을 다시 읽는다.** 여기서 조각을 더하지 않는다 —
    /// 잔액이 오르는 유일한 이유는 Google이 서버에 보낸 검증된 callback이다.
    func watch(session: ServerSession?, wallet: ShardWallet) async {
        // 동의 없이 광고를 요청하지 않는다. UMP가 허용하기 전에는 CTA를 눌러도 아무 일도 없다.
        guard canRequestAds else { return }
        guard let adUnit, let presenter, let session, session.isValid() else { return }
        guard phase != .presenting, phase != .verifying else { return }

        // 광고에 실어 보낼 context. **session token을 보내지 않는다.**
        let context: String
        do {
            context = try await backend.rewardedAdContext(accessToken: session.accessToken)
        } catch {
            // context를 못 받았다. **값은 남기지 않는다** — 실패했다는 사실만.
            AdLog.diagnostic("reward context request failed")
            phase = .unavailable
            return
        }

        if await presenter.isReady == false {
            phase = .loading
            await presenter.load(adUnit: adUnit)
        }

        phase = .presenting
        AdLog.diagnostic("rewarded present started unitSuffix=\(AdLog.unitSuffix(adUnit))")
        let result = await presenter.present(context: context)
        AdLog.diagnostic("rewarded present finished result=\(result)")

        switch result {
        case .watched:
            // 광고 UX가 끝났을 뿐이다. 보상은 서버가 확인해준다.
            phase = .verifying
            AdLog.diagnostic("verification pending")
            await waitForServerReward(session: session, wallet: wallet)
            phase = .idle
        case .dismissed:
            phase = .idle
        case .unavailable:
            phase = .unavailable
        }

        // 다음 광고를 미리 받아 둔다.
        await presenter.load(adUnit: adUnit)
    }

    /// SSV는 client와 별개 경로라 언제 도착할지 알 수 없다.
    /// **짧게 몇 번만** 확인하고, 오면 즉시 멈춘다. 못 받아도 가짜로 올리지 않는다.
    private func waitForServerReward(session: ServerSession, wallet: ShardWallet) async {
        let before = wallet.rewardedToday

        for delay in verificationDelays {
            if delay != .zero { await sleep(delay) }
            await wallet.refresh(session: session)
            if wallet.rewardedToday > before {
                AdLog.diagnostic("server reward reflected")
                return
            }
        }
        // 아직 안 왔다. 화면은 그대로 두고, 다음 새로고침(scene 복귀 등)이 가져간다.
        AdLog.diagnostic("server reward not reflected yet")
    }
}

// MARK: - 로그

/// 광고 로그는 두 갈래다.
///
/// - `event` — **DEBUG 전용** 상세 로그. Xcode console에서만 본다
/// - `diagnostic` — **Release에서도 남는** 진단 로그. `os.Logger`로 나간다
///
/// Release 갈래를 둔 이유는 하나다. 예전에는 광고 로그가 전부 `#if DEBUG`라
/// **Release에서 광고가 안 뜨면 원인을 볼 방법이 없었다.** Debug는 Google demo unit을,
/// Release는 실제 ad unit을 쓰기 때문에 정작 봐야 할 쪽이 침묵하고 있었다.
///
/// 진단 로그에 담는 것은 **분류값뿐**이다 — 상태 이름 · error domain/code ·
/// adapter 개수 · ad unit의 뒷자리. 사용자를 가리키는 값은 어느 갈래에도 넣지 않는다:
/// access token · Apple identity token · reward context(custom_data) · transaction_id ·
/// SSV signature · raw callback URL · 내부 user UUID · email.
nonisolated enum AdLog {
    private static let logger = Logger(subsystem: "com.mark77234.ggumirror", category: "ads")

    /// DEBUG 전용 상세 로그.
    static func event(_ message: String) {
        #if DEBUG
        print("[Ads] \(message)")
        #endif
    }

    /// Release에서도 남는 진단 로그.
    ///
    /// `privacy: .public`을 쓰는 이유는 **여기 오는 값이 이미 분류값뿐**이기 때문이다.
    /// 사용자 데이터를 넣지 않는 것은 이 함수가 아니라 **부르는 쪽의 책임**이다.
    static func diagnostic(_ message: String) {
        logger.info("\(message, privacy: .public)")
        #if DEBUG
        print("[Ads] \(message)")
        #endif
    }

    /// ad unit을 통째로 남기지 않는다. 어느 단위인지 알아볼 만큼만 뒤에서 자른다.
    static func unitSuffix(_ adUnit: String) -> String {
        adUnit.split(separator: "/").last.map(String.init) ?? "unknown"
    }
}
