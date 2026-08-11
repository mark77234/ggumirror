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
