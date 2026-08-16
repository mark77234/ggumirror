//
//  AppConfig.swift
//  ggumirror
//
//  빌드 설정에서 온 값을 읽는 **유일한 곳**.
//
//  URL은 `Config/*.xcconfig` → `Config/Info.plist` → 여기로 온다.
//  코드에 주소를 적지 않는다. `BackendClient`는 Bundle을 직접 읽지 않고 이 값만 본다.
//
//  여기 있는 값은 **secret이 아니다.** 앱 bundle에 들어가는 것은 누구나 꺼내볼 수 있으므로
//  token · private key · service account · GCP project id 같은 것을 넣지 않는다.
//

import Foundation

nonisolated enum AppEnvironment: String {
    case development
    case production
}

nonisolated enum AppConfig {
    /// Info.plist key. 한 규칙으로 통일한다 — `GGUMIRROR_` prefix.
    enum Key {
        static let environment = "GGUMIRROR_APP_ENV"
        static let backendBaseURL = "GGUMIRROR_BACKEND_BASE_URL"
        static let admobRewardedAdUnitID = "GGUMIRROR_ADMOB_REWARDED_AD_UNIT_ID"
        /// Google SDK가 직접 읽는 표준 키다. 우리가 Swift에서 쓸 일은 없고,
        /// 빌드 설정이 제대로 들어갔는지 test가 확인하는 데만 쓴다.
        static let admobAppID = "GADApplicationIdentifier"
    }

    /// Google이 공개한 **예제(test) ad unit**. Debug에서만 쓴다.
    /// Release 빌드에 이 값이 들어가면 실제 사용자에게 test 광고가 나가고 정책 위반이 된다.
    static let googleTestRewardedAdUnit = "ca-app-pub-3940256099942544/1712485313"

    enum Failure: Error, CustomStringConvertible {
        case missing(String)
        case invalid(key: String, reason: String)

        var description: String {
            switch self {
            case .missing(let key):
                "빌드 설정에 \(key)가 없다. Config/*.xcconfig와 Config/Info.plist를 확인한다."
            case .invalid(let key, let reason):
                "빌드 설정 \(key)가 잘못됐다: \(reason)"
            }
        }
    }

    static let environment: AppEnvironment = resolve { try parseEnvironment(bundleValue(Key.environment)) }

    static let backendBaseURL: URL = resolve { try parseBaseURL(bundleValue(Key.backendBaseURL)) }

    /// 광고 보상에 쓸 rewarded ad unit. **없으면 `nil`이고, 그러면 광고 기능을 꺼 둔다.**
    ///
    /// 다른 설정과 달리 비어 있어도 앱을 멈추지 않는다 — 광고는 부가 기능이고,
    /// 아직 꾸미러 전용 ad unit이 없다. 거울 · 촬영 · 꾸미기 · 출석은 그대로 동작해야 한다.
    static let admobRewardedAdUnitID: String? = parseAdUnit(bundleValue(Key.admobRewardedAdUnitID))

    /// AdMob app 식별자. **Debug / Release가 같다.**
    ///
    /// 광고를 안전하게 만드는 것은 App ID가 아니라 ad unit이다(Debug는 Google test unit).
    /// App ID까지 sample 값으로 바꾸면 UMP가 남의 app 설정으로 동의 메시지를 조회해
    /// 우리 동의 흐름을 실기기에서 확인할 수 없다.
    static let admobAppID: String? = bundleValue(Key.admobAppID)

    // MARK: - 읽기

    private static func bundleValue(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    /// 설정이 깨졌으면 **숨기지 않고 즉시 멈춘다.**
    ///
    /// 이 값들은 빌드 시점에 박히므로, 잘못됐다는 것은 빌드가 잘못됐다는 뜻이다.
    /// 조용히 기본값으로 떨어지면 localhost나 엉뚱한 서버로 붙는 앱이 나간다.
    private static func resolve<T>(_ read: () throws -> T) -> T {
        do {
            return try read()
        } catch {
            preconditionFailure("설정 오류: \(error)")
        }
    }

    // MARK: - 해석 (순수 함수 — 테스트가 직접 부른다)

    static func parseEnvironment(_ raw: String?) throws -> AppEnvironment {
        let value = try nonEmpty(raw, key: Key.environment)
        guard let environment = AppEnvironment(rawValue: value) else {
            throw Failure.invalid(key: Key.environment, reason: "'\(value)'는 development / production이 아니다")
        }
        return environment
    }

    static func parseBaseURL(_ raw: String?) throws -> URL {
        let value = try nonEmpty(raw, key: Key.backendBaseURL)
        guard let url = URL(string: value), let scheme = url.scheme, let host = url.host(), !host.isEmpty else {
            throw Failure.invalid(key: Key.backendBaseURL, reason: "주소로 읽을 수 없다")
        }
        // http는 개발용으로만 허용한다. 실제로는 두 환경 모두 https를 쓴다.
        guard scheme == "https" || scheme == "http" else {
            throw Failure.invalid(key: Key.backendBaseURL, reason: "scheme이 http(s)가 아니다")
        }
        return url
    }

    /// 비어 있으면 `nil`. **production에서 test ad unit이면 무시한다.**
    ///
    /// 실수로 test 값이 Release 설정에 들어가도 실제 사용자에게 test 광고가 나가지 않는다.
    /// 빌드 설정 test(`AppConfigTests`)가 먼저 잡지만, 마지막 방어선을 코드에도 둔다.
    static func parseAdUnit(_ raw: String?, environment: AppEnvironment = AppConfig.environment) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if environment == .production, value == googleTestRewardedAdUnit {
            return nil
        }
        return value
    }

    private static func nonEmpty(_ raw: String?, key: String) throws -> String {
        guard let raw else { throw Failure.missing(key) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.missing(key) }
        return trimmed
    }
}
