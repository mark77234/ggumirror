//
//  AppConfigTests.swift
//  ggumirrorTests
//
//  빌드 설정(`Config/*.xcconfig` → `Config/Info.plist` → `AppConfig`)을 고정한다.
//
//  Release 값은 Debug로 도는 테스트에서 런타임으로 확인할 수 없으므로
//  **xcconfig 파일을 직접 읽어** 검사한다. 이 프로젝트가 이미 쓰는 방식이다.
//

import Foundation
import Testing
@testable import ggumirror

struct AppConfigTests {

    // MARK: - 도구

    /// repo 안의 파일을 읽는다. `#filePath`는 ggumirrorTests/ 안이다.
    private func repoFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ggumirrorTests
            .deletingLastPathComponent()   // repo root
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    /// xcconfig의 값을 조립까지 해서 돌려준다(`$(VAR)` 치환 · `#include` 따라가기).
    private func settings(_ configName: String) throws -> [String: String] {
        var raw: [String: String] = [:]

        func load(_ name: String) throws {
            let text = try repoFile("Config/\(name)")
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let include = trimmed.firstMatch(of: /^#include\??\s+"(.+)"$/) {
                    // 없을 수 있는 include는 건너뛴다(Local.xcconfig).
                    try? load(String(include.1))
                    continue
                }
                guard !trimmed.hasPrefix("//"), let equals = trimmed.firstIndex(of: "=") else { continue }
                let key = String(trimmed[trimmed.startIndex..<equals]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
                if let comment = value.range(of: "//") { value = String(value[..<comment.lowerBound]) }
                raw[key] = value.trimmingCharacters(in: .whitespaces)
            }
        }
        try load(configName)

        // $(VAR) 치환.
        func expand(_ value: String, depth: Int = 0) -> String {
            guard depth < 8 else { return value }
            var result = value
            while let match = result.firstMatch(of: /\$\((\w+)\)/) {
                let replacement = raw[String(match.1)].map { expand($0, depth: depth + 1) } ?? ""
                result.replaceSubrange(match.range, with: replacement)
            }
            return result
        }
        return raw.mapValues { expand($0) }
    }

    private let productionURL = "https://ggumirror-api-cmyv4amroa-du.a.run.app"

    /// 주석을 걷어낸 실제 코드 / 설정 줄만. 주석에는 "localhost를 쓰지 않는 이유"처럼
    /// 금지 단어가 정당하게 등장하므로, 값 검사에서는 제외해야 한다.
    private func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - 환경 구분

    @Test("Debug는 development다")
    func debugEnvironment() throws {
        #expect(try settings("Debug.xcconfig")["APP_ENV"] == "development")
    }

    @Test("Release는 production이다")
    func releaseEnvironment() throws {
        #expect(try settings("Release.xcconfig")["APP_ENV"] == "production")
    }

    @Test("테스트는 Debug로 도니까 런타임 환경도 development다")
    func runtimeEnvironmentIsDevelopment() {
        #expect(AppConfig.environment == .development)
    }

    // MARK: - 주소

    @Test("Debug backend는 꾸미러 전용 production API다")
    func debugBackendURL() throws {
        #expect(try settings("Debug.xcconfig")["BACKEND_BASE_URL"] == productionURL)
    }

    @Test("Release backend도 같은 production API다")
    func releaseBackendURL() throws {
        #expect(try settings("Release.xcconfig")["BACKEND_BASE_URL"] == productionURL)
    }

    @Test("런타임 값도 같은 주소다")
    func runtimeBackendURL() {
        #expect(AppConfig.backendBaseURL.absoluteString == productionURL)
    }

    @Test("두 환경 모두 HTTPS다")
    func bothAreHTTPS() throws {
        for config in ["Debug.xcconfig", "Release.xcconfig"] {
            let raw = try #require(settings(config)["BACKEND_BASE_URL"])
            let url = try #require(URL(string: raw))
            #expect(url.scheme == "https")
        }
    }

    @Test("두 환경 모두 ggumirror-api host다")
    func bothPointAtGgumirrorAPI() throws {
        for config in ["Debug.xcconfig", "Release.xcconfig"] {
            let raw = try #require(settings(config)["BACKEND_BASE_URL"])
            let host = try #require(URL(string: raw)?.host())
            #expect(host.hasPrefix("ggumirror-api-"))
            #expect(host.hasSuffix(".run.app"))
        }
    }

    @Test("추적되는 config 값에 localhost / 다른 서비스 흔적이 없다")
    func noForbiddenHosts() throws {
        for config in ["Base.xcconfig", "Debug.xcconfig", "Release.xcconfig"] {
            let values = try settings(config).values.joined(separator: " ")
            for forbidden in ["localhost", "127.0.0.1", "opicmobile", "dailyopic"] {
                #expect(!values.contains(forbidden), "\(config) 값에 \(forbidden)이 있다")
            }
        }
    }

    // MARK: - BackendClient 연결

    @Test("BackendClient 기본 주소는 AppConfig에서 온다")
    func clientUsesAppConfig() {
        #expect(BackendClient().baseURL == AppConfig.backendBaseURL)
    }

    @Test("테스트는 원하는 주소를 넣을 수 있다")
    func clientAllowsInjection() {
        let fake = URL(string: "https://example.test")!
        #expect(BackendClient(baseURL: fake).baseURL == fake)
        #expect(BackendClient(baseURL: nil).baseURL == nil)
    }

    @Test("주소를 코드에 하드코딩하지 않았다")
    func noHardcodedURLInSource() throws {
        for file in ["ggumirror/Backend/BackendClient.swift", "ggumirror/Backend/AppConfig.swift"] {
            let source = codeOnly(try repoFile(file))
            #expect(!source.contains("run.app"), "\(file)에 주소가 박혀 있다")
            #expect(!source.contains("127.0.0.1"), "\(file)에 주소가 박혀 있다")
            #expect(!source.contains("localhost"), "\(file)에 주소가 박혀 있다")
            #expect(!source.contains("https:/"), "\(file)에 URL 리터럴이 있다")
        }
    }

    // MARK: - 잘못된 설정

    @Test("설정이 비어 있으면 잡아낸다")
    func detectsMissingConfig() {
        #expect(throws: AppConfig.Failure.self) { try AppConfig.parseEnvironment(nil) }
        #expect(throws: AppConfig.Failure.self) { try AppConfig.parseEnvironment("   ") }
        #expect(throws: AppConfig.Failure.self) { try AppConfig.parseBaseURL(nil) }
        #expect(throws: AppConfig.Failure.self) { try AppConfig.parseBaseURL("") }
    }

    @Test("망가진 설정이면 잡아낸다")
    func detectsMalformedConfig() {
        #expect(throws: AppConfig.Failure.self) { try AppConfig.parseEnvironment("staging") }
        #expect(throws: AppConfig.Failure.self) { try AppConfig.parseBaseURL("not a url") }
        // scheme이 http(s)가 아니면 거부한다.
        #expect(throws: AppConfig.Failure.self) { try AppConfig.parseBaseURL("ftp://example.test") }
        // host가 없으면 거부한다.
        #expect(throws: AppConfig.Failure.self) { try AppConfig.parseBaseURL("https://") }
    }

    @Test("정상 값은 통과한다")
    func acceptsValidConfig() throws {
        #expect(try AppConfig.parseEnvironment("production") == .production)
        #expect(try AppConfig.parseEnvironment(" development ") == .development)
        #expect(try AppConfig.parseBaseURL(productionURL).host() == "ggumirror-api-cmyv4amroa-du.a.run.app")
    }

    // MARK: - 파일 추적

    @Test("Local.xcconfig는 gitignore되고 example은 추적된다")
    func localOverrideIsIgnored() throws {
        let ignore = try repoFile(".gitignore")
        #expect(ignore.contains("Config/Local.xcconfig"))

        let example = try repoFile("Config/Local.xcconfig.example")
        #expect(example.contains("Local.xcconfig"))
        // example에 실제 값을 넣지 않는다.
        for secret in ["private_key", "client_secret", "Bearer ", "serviceAccount"] {
            #expect(!example.contains(secret))
        }
    }

    @Test("기본 config 파일은 gitignore하지 않는다 — fresh clone에서 빌드돼야 한다")
    func defaultConfigsAreTracked() throws {
        let ignore = try repoFile(".gitignore")
        for tracked in ["Config/Base.xcconfig", "Config/Debug.xcconfig", "Config/Release.xcconfig", "Config/Info.plist"] {
            #expect(!ignore.contains(tracked))
            #expect(try !repoFile(tracked).isEmpty)
        }
    }

    // MARK: - 앱 / extension 버전 parity

    /// `PRODUCT_BUNDLE_IDENTIFIER` → (build number, marketing version).
    ///
    /// pbxproj를 **build configuration 블록 단위**로 나눠 bundle id를 열쇠로 읽는다.
    /// 줄 번호나 target 이름 순서에 기대지 않으므로 Xcode가 파일을 다시 써도 견딘다.
    private func projectVersions() throws -> [String: [(build: String, marketing: String)]] {
        let text = try repoFile("ggumirror.xcodeproj/project.pbxproj")
        var versions: [String: [(build: String, marketing: String)]] = [:]

        for block in text.components(separatedBy: "isa = XCBuildConfiguration;").dropFirst() {
            guard let bundle = value(of: "PRODUCT_BUNDLE_IDENTIFIER", in: block),
                  let build = value(of: "CURRENT_PROJECT_VERSION", in: block),
                  let marketing = value(of: "MARKETING_VERSION", in: block)
            else { continue }
            versions[bundle, default: []].append((build, marketing))
        }
        return versions
    }

    private func value(of key: String, in block: String) -> String? {
        guard let start = block.range(of: "\(key) = "),
              let end = block[start.upperBound...].firstIndex(of: ";")
        else { return nil }
        return String(block[start.upperBound..<end]).trimmingCharacters(in: .whitespaces)
    }

    @Test("앱과 extension의 build number / version이 같다")
    func extensionsMatchTheApp() throws {
        let versions = try projectVersions()

        let app = try #require(versions["com.mark77234.ggumirror"]?.first)
        // Debug / Release 두 configuration 모두 잡혔는지 먼저 확인한다.
        #expect(versions["com.mark77234.ggumirror"]?.count == 2)

        // **embed되는 target을 손으로 적지 않는다.** 목록을 적어 두면 나중에 extension을
        // 하나 더 만들었을 때 이 테스트가 조용히 그것을 빼놓는다 — parity가 깨져도
        // 초록으로 남는다. 앱 bundle id로 시작하는 것은 전부 embed 대상이다.
        let embedded = versions.keys
            .filter { $0.hasPrefix("com.mark77234.ggumirror.") }
            .sorted()
        #expect(embedded.count >= 2, "embed되는 target을 찾지 못했다")
        // test target은 앱에 embed되지 않으므로 이 규칙에서 빠진다.
        #expect(!embedded.contains { $0.hasSuffix("Tests") })

        // 앱 안에 embed되는 extension은 **반드시** 부모와 같아야 한다.
        // 다르면 `CFBundleVersion ... must match` 경고가 나고 App Store 검증에서 막힌다.
        for target in embedded {
            let configurations = try #require(versions[target], "\(target) 설정을 찾지 못했다")
            #expect(configurations.count == 2, "\(target): Debug/Release 둘 다 잡히지 않았다")
            for configuration in configurations {
                #expect(
                    configuration.build == app.build,
                    "\(target) build \(configuration.build) ≠ app \(app.build)"
                )
                #expect(
                    configuration.marketing == app.marketing,
                    "\(target) version \(configuration.marketing) ≠ app \(app.marketing)"
                )
            }
        }

        // 앱 자신의 두 configuration도 서로 같아야 한다.
        //
        // **실제로 이것이 깨진 적이 있다** — Xcode General 탭에서 Version을 고치면
        // 그 target의 Debug/Release만 함께 바뀌고 extension은 그대로 남는다.
        // 위 비교는 `app.first`(Debug 하나)만 기준으로 삼으므로, 앱의 두 값이
        // 서로 다른 경우는 여기서만 잡힌다.
        let appConfigurations = try #require(versions["com.mark77234.ggumirror"])
        #expect(Set(appConfigurations.map(\.marketing)).count == 1, "앱의 Debug/Release version이 다르다")
        #expect(Set(appConfigurations.map(\.build)).count == 1, "앱의 Debug/Release build가 다르다")
    }

    @Test("출시 버전이 의도한 값이다")
    func releaseVersionIsIntentional() throws {
        // 버전은 **사람이 정하는 값**이라 여기서 형태만 확인한다. 특정 숫자를 못 박으면
        // 다음 출시마다 이 테스트를 고쳐야 하고, 그러면 고치는 것이 습관이 되어
        // 의도하지 않은 bump도 함께 통과한다.
        //
        // 대신 **모든 target이 한 값을 말하는지**를 본다 — drift는 그 조건을 깬다.
        // **앱에 embed되는 것만** 본다. test target(`…ggumirrorTests`)은 앱에 들어가지
        // 않으므로 자기 버전(1.0)을 그대로 둔다 — 이 규칙에서 빠진다.
        let versions = try projectVersions()
        let shipping = versions
            .filter { $0.key == "com.mark77234.ggumirror"
                || $0.key.hasPrefix("com.mark77234.ggumirror.") }
            .values.flatMap { $0 }

        #expect(Set(shipping.map(\.marketing)).count == 1, "target마다 version이 다르다")
        let marketing = try #require(shipping.first?.marketing)
        // `1.1.0` 같은 세 자리 형태다.
        #expect(marketing.split(separator: ".").count == 3, "version 형태가 아니다: \(marketing)")
        #expect(marketing.allSatisfy { $0.isNumber || $0 == "." })
    }

    // MARK: - Privacy manifest

    /// 앱 bundle에 실제로 들어간 manifest를 읽는다(repo 파일이 아니라 **결과물**).
    private func bundledPrivacyManifest() throws -> [String: Any] {
        let url = try #require(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "앱 bundle에 PrivacyInfo.xcprivacy가 없다 — App Store 제출에서 막힌다"
        )
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    private func reasons(_ manifest: [String: Any], for category: String) -> [String] {
        let types = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let match = types.first { $0["NSPrivacyAccessedAPIType"] as? String == category }
        return match?["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
    }

    @Test("앱 bundle에 privacy manifest가 들어 있다")
    func privacyManifestIsBundled() throws {
        let manifest = try bundledPrivacyManifest()
        #expect(manifest["NSPrivacyAccessedAPITypes"] != nil)
    }

    @Test("UserDefaults는 CA92.1로 선언한다 — App Group reason이 아니다")
    func userDefaultsReason() throws {
        let manifest = try bundledPrivacyManifest()
        let reasons = reasons(manifest, for: "NSPrivacyAccessedAPICategoryUserDefaults")

        #expect(reasons.contains("CA92.1"))
        // App Group을 쓰지 않는다. 1C8F.1을 적으면 사실과 다르다.
        #expect(!reasons.contains("1C8F.1"), "App Group을 쓰지 않는데 1C8F.1을 선언했다")
    }

    @Test("systemUptime은 35F9.1로 선언한다")
    func systemBootTimeReason() throws {
        // Editor의 햅틱 rate limiter가 ProcessInfo.systemUptime을 쓴다 —
        // Required Reason API라서 선언이 필요하다.
        let manifest = try bundledPrivacyManifest()
        #expect(reasons(manifest, for: "NSPrivacyAccessedAPICategorySystemBootTime").contains("35F9.1"))
    }

    @Test("쓰지도 않는 API를 선언하지 않는다")
    func declaresOnlyWhatWeUse() throws {
        let manifest = try bundledPrivacyManifest()
        let declared = Set(
            (manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? [])
                .compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        )

        #expect(declared == [
            "NSPrivacyAccessedAPICategoryUserDefaults",
            "NSPrivacyAccessedAPICategorySystemBootTime",
        ], "실제로 쓰지 않는 항목이 선언돼 있다")
    }

    @Test("추적한다고 임의로 선언하지 않는다")
    func doesNotClaimTracking() throws {
        let manifest = try bundledPrivacyManifest()
        // ATT를 도입하지 않았고 IDFA도 읽지 않는다.
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String] ?? []).isEmpty)
        // 근거 없이 수집 항목을 지어내지 않는다. SDK 수집은 SDK manifest가 선언한다.
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []).isEmpty)
    }

    @Test("SDK manifest는 각 framework가 따로 들고 온다")
    func sdkManifestsAreSeparate() throws {
        // 우리 manifest가 SDK를 대신하지 않고, SDK 내용을 베껴 오지도 않는다.
        let manifest = try bundledPrivacyManifest()
        let raw = String(describing: manifest)
        #expect(!raw.contains("NSPrivacyCollectedDataTypeAdvertisingData"))
        #expect(!raw.contains("DeviceID"))

        // Google framework 두 개는 자기 manifest를 들고 앱 안에 들어온다.
        for framework in ["GoogleMobileAds", "UserMessagingPlatform"] {
            let url = Bundle.main.bundleURL
                .appending(path: "Frameworks/\(framework).framework/PrivacyInfo.xcprivacy")
            #expect(FileManager.default.fileExists(atPath: url.path),
                    "\(framework)의 privacy manifest가 없다")
        }
    }

    @Test("extension에는 privacy manifest를 만들지 않았다 — 필요가 없다")
    func extensionsNeedNoManifest() throws {
        // 두 extension은 Required Reason API를 쓰지 않는다(코드/바이너리로 확인).
        // 필요 없는 manifest를 넣지 않는다.
        for path in ["GgumirrorCapture", "GgumirrorControls"] {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: path)
            let manifest = root.appending(path: "PrivacyInfo.xcprivacy")
            #expect(!FileManager.default.fileExists(atPath: manifest.path))

            // 정말 안 쓰는지도 함께 고정한다 — 나중에 쓰기 시작하면 여기서 걸린다.
            let sources = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            for name in sources where name.hasSuffix(".swift") {
                let source = try String(contentsOf: root.appending(path: name), encoding: .utf8)
                for api in ["UserDefaults", "@AppStorage", "systemUptime", "mach_absolute_time"] {
                    #expect(!source.contains(api), "\(path)/\(name)이 \(api)를 쓴다 — manifest가 필요해졌다")
                }
            }
        }
    }

    @Test("client에 credential이 없다")
    func noCredentialsInConfig() throws {
        for file in ["Config/Base.xcconfig", "Config/Debug.xcconfig", "Config/Release.xcconfig", "Config/Info.plist"] {
            let text = try repoFile(file)
            for forbidden in [
                "GCP_PROJECT_ID", "FIRESTORE", "private_key", "client_secret",
                "serviceAccount", "service-account", "identityToken", "RevenueCat",
            ] {
                #expect(!text.contains(forbidden), "\(file)에 \(forbidden)이 있다")
            }
        }
    }
}
