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
    }

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

    private static func nonEmpty(_ raw: String?, key: String) throws -> String {
        guard let raw else { throw Failure.missing(key) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.missing(key) }
        return trimmed
    }
}
