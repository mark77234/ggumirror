//
//  AIMirrorFlowTests.swift
//  ggumirrorTests
//
//  AI 거울 만들기 흐름.
//
//  비싼 기능이라 지키는 것이 분명하다:
//  **헛되이 부르지 않고, 두 번 부르지 않고, 실패하면 아무것도 남기지 않는다.**
//

import Testing
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import ggumirror

private func source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

/// 캔버스 비율의 단색 PNG. 규격을 지나갈 수 있는 최소한의 그림이다.
private func generatedPNG() -> Data {
    let w = 512
    let h = Int(512 / ExternalMirrorImportContract.aspectRatio)
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    for i in stride(from: 0, to: pixels.count, by: 4) {
        (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]) = (200, 120, 160, 255)
    }
    let image = CGContext(
        data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.makeImage()!
    let out = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
        out, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return out as Data
}

private nonisolated final class FakeAIBackend: AIMirrorBackend, @unchecked Sendable {
    var calls = 0
    var failure: AIMirrorFailure?
    var config = AIMirrorConfig(available: true, dailyLimit: 3, remaining: 3)

    func aiMirrorConfig(accessToken: String) async throws -> AIMirrorConfig { config }

    func generateAIMirror(prompt: String, accessToken: String) async throws -> Data {
        calls += 1
        if let failure { throw failure }
        return generatedPNG()
    }
}

private func session() -> ServerSession {
    ServerSession(accessToken: "t", expiresAt: .distantFuture, userID: "user-1")
}

@Suite("AI 거울 만들기")
@MainActor
struct AIMirrorMakerTests {

    @Test("성공하면 미리보기가 준비된다")
    func successProducesArtwork() async {
        let backend = FakeAIBackend()
        let maker = AIMirrorMaker(backend: backend)
        await maker.generate(prompt: "핑크 리본", session: session())
        #expect(maker.state == .ready)
        #expect(maker.artwork != nil)
        #expect(backend.calls == 1)
    }

    @Test("로그인하지 않으면 서버를 부르지 않는다")
    func guestNeverCallsTheProvider() async {
        let backend = FakeAIBackend()
        let maker = AIMirrorMaker(backend: backend)
        await maker.generate(prompt: "핑크 리본", session: nil)
        #expect(backend.calls == 0)
        #expect(maker.artwork == nil)
    }

    @Test("빈 프롬프트는 서버를 부르지 않는다")
    func emptyPromptNeverCallsTheProvider() async {
        let backend = FakeAIBackend()
        let maker = AIMirrorMaker(backend: backend)
        await maker.generate(prompt: "   ", session: session())
        // 고칠 수 있는 실패다 — 하루 몫을 쓰지 않는다.
        #expect(backend.calls == 0)
    }

    @Test("하루 몫을 다 쓰면 그렇게 말한다")
    func quotaFailureIsExplained() async {
        let backend = FakeAIBackend()
        backend.failure = .quotaExceeded
        let maker = AIMirrorMaker(backend: backend)
        await maker.generate(prompt: "핑크 리본", session: session())

        guard case .failed(let message) = maker.state else {
            Issue.record("실패 상태가 아니다"); return
        }
        #expect(message.contains("내일"))
        #expect(maker.artwork == nil)
    }

    @Test("거절당하면 다른 표현을 권한다")
    func safetyRejectionIsExplained() async {
        let backend = FakeAIBackend()
        backend.failure = .safetyRejected
        let maker = AIMirrorMaker(backend: backend)
        await maker.generate(prompt: "무언가", session: session())

        guard case .failed(let message) = maker.state else {
            Issue.record("실패 상태가 아니다"); return
        }
        #expect(message.contains("다른 표현"))
    }

    @Test("실패하면 거울이 남지 않는다")
    func failureLeavesNothing() async {
        let backend = FakeAIBackend()
        backend.failure = .unavailable
        let maker = AIMirrorMaker(backend: backend)
        await maker.generate(prompt: "핑크 리본", session: session())
        #expect(maker.artwork == nil)
    }

    @Test("만드는 동안 다시 부르지 않는다")
    func doubleTapIsBlocked() throws {
        let code = try source("ggumirror/MyMirrors/AIMirrorView.swift")
        // 연타로 두 번 만들면 하루 몫이 두 번 빠진다.
        #expect(code.contains("guard !isGenerating else { return }"))
        #expect(code.contains("disabled(maker.isGenerating)"))
    }

    @Test("결과는 반드시 규격을 지난다")
    func resultGoesThroughTheAdapter() throws {
        let code = try source("ggumirror/MyMirrors/AIMirrorView.swift")
        #expect(code.contains("GeneratedMirrorAdapter.prepare"))
    }
}

@Suite("AI 거울 저장")
struct AIMirrorSaveTests {

    private func view() throws -> String {
        try source("ggumirror/MyMirrors/AIMirrorView.swift")
    }

    @Test("만들기 전에 보관 공간을 본다")
    func capacityIsCheckedBeforeGenerating() throws {
        let code = try view()
        // 비싼 그림을 만들어 놓고 저장 못 하는 상황을 줄인다.
        let start = try #require(code.range(of: "private func make()")).upperBound
        let end = try #require(
            code.range(of: "private func save(", range: start..<code.endIndex)
        ).lowerBound
        #expect(code[start..<end].contains("hasFreeMirrorSlot"))
    }

    @Test("저장 직전에 다시 본다")
    func capacityIsRecheckedBeforeSaving() throws {
        let code = try view()
        let start = try #require(code.range(of: "private func save(")).upperBound
        #expect(code[start...].contains("hasFreeMirrorSlot"))
    }

    @Test("AI로 만들었다고 기록한다")
    func recordsTheAIOrigin() throws {
        #expect(try view().contains("creationSource: .aiGenerated"))
    }

    @Test("보통 거울로 저장한다")
    func savesAsAnOrdinaryMirror() throws {
        let code = try view()
        // AI 전용 라이브러리를 만들지 않는다 — 이름 변경·상점 등록이 그대로 된다.
        #expect(code.contains("library.save("))
        #expect(!code.contains("AIMirrorLibrary"))
    }

    @Test("만드는 방법에 AI가 있다")
    func entryPointExists() throws {
        let mirrors = try source("ggumirror/MyMirrors/MyMirrorsView.swift")
        #expect(mirrors.contains("AI로 만들기"))
    }
}

@Suite("AI 출처는 이름으로 추측하지 않는다")
struct MirrorCreationSourceTests {

    @Test("새 값은 없을 수 있다")
    func legacyMirrorsHaveNoSource() throws {
        // 이 값이 생기기 전 파일에는 없다. 없다고 읽기가 깨지면 안 된다.
        let style = try JSONEncoder().encode(BasicMirror.white.style)
        let json = """
        {"id":"legacy-1","name":"예전 거울","style":\(String(data: style, encoding: .utf8)!)}
        """
        let mirror = try JSONDecoder().decode(MyMirror.self, from: Data(json.utf8))
        #expect(mirror.creationSource == nil)
    }

    @Test("적어 두면 다시 읽힌다")
    func sourceSurvivesEncoding() throws {
        var mirror = MirrorLibrary.defaultMirror
        mirror.creationSource = .aiGenerated
        let decoded = try JSONDecoder().decode(
            MyMirror.self, from: try JSONEncoder().encode(mirror)
        )
        #expect(decoded.creationSource == .aiGenerated)
    }

    @Test("출처와 상점 상태를 섞지 않는다")
    func originAndSourceAreSeparate() {
        // `MirrorOrigin`에 AI를 넣었다면 AI 거울이 `내가 만든` 목록에서 사라졌을 것이다.
        #expect(!MirrorOrigin.allCases.contains { $0.rawValue.contains("AI") })
        var mirror = MirrorLibrary.defaultMirror
        mirror.origin = .made
        mirror.creationSource = .aiGenerated
        #expect(mirror.origin == .made)
        #expect(mirror.creationSource == .aiGenerated)
    }
}

@Suite("client는 provider를 모른다")
struct AIMirrorSecurityTests {

    @Test("모델도 provider도 보내지 않는다")
    func clientCannotChooseTheModel() throws {
        let api = try source("ggumirror/Backend/BackendClient+AIMirror.swift")
        for forbidden in ["model", "provider", "apiKey", "openai", "OPENAI"] {
            #expect(!api.contains(forbidden), "client가 \(forbidden)를 보낸다")
        }
        // 보내는 것은 프롬프트 하나뿐이다.
        #expect(api.contains("struct Body: Encodable { let prompt: String }"))
    }

    @Test("내부 오류를 그대로 보여 주지 않는다")
    func providerErrorsAreTranslated() {
        for failure in [AIMirrorFailure.quotaExceeded, .safetyRejected, .unavailable, .network] {
            let message = failure.message
            #expect(!message.isEmpty)
            for leak in ["openai", "provider", "500", "http"] {
                #expect(!message.lowercased().contains(leak), "\(failure): \(message)")
            }
        }
    }
}
