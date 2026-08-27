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
    var config = AIMirrorConfig(available: true, price: 10)

    func aiMirrorConfig(accessToken: String) async throws -> AIMirrorConfig { config }

    var requestIDs: [String] = []

    func generateAIMirror(
        prompt: String, requestID: String, accessToken: String
    ) async throws -> Data {
        calls += 1
        requestIDs.append(requestID)
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
        // 고칠 수 있는 실패다 — 서버를 부르지 않는다.
        #expect(backend.calls == 0)
    }

    @Test("하루 횟수 제한이 없다 — 연속 생성이 막히지 않는다")
    func generationIsNeverBlockedByADailyQuota() async {
        let backend = FakeAIBackend()
        let maker = AIMirrorMaker(backend: backend)

        // 예전 상한(3)을 넘겨야 상한이 사라진 것이 보인다.
        for _ in 0..<5 {
            await maker.generate(prompt: "핑크 리본", session: session())
            #expect(maker.artwork != nil, "\(maker.state)")
            maker.reset()
        }
        #expect(backend.calls == 5)
    }

    @Test("남은 횟수를 말하는 자리가 어디에도 없다")
    func nothingCountsDownTheDay() throws {
        let view = try source("ggumirror/MyMirrors/AIMirrorView.swift")
        let api = try source("ggumirror/Backend/BackendClient+AIMirror.swift")
        for gone in ["번 남았어요", "remaining", "dailyLimit", "quotaExceeded", "내일 다시"] {
            #expect(!view.contains(gone), "view: \(gone)")
            #expect(!api.contains(gone), "api: \(gone)")
        }
        // 429를 하루 몫으로 해석하던 분기도 없다.
        #expect(!api.contains("case 429"))
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
        // 보내는 것은 프롬프트와 멱등 키뿐이다. **값도 모델도 실을 자리가 없다** —
        // `requestId`는 같은 요청인지만 알려주고, 얼마인지는 서버 표가 정한다.
        #expect(api.contains("struct Body: Encodable { let prompt: String; let requestId: String }"))

        // 값은 **읽기만** 한다(`AIMirrorConfig.price`). 보내는 쪽에는 없다 —
        // 요청에 값을 실을 수 있으면 앱이 값을 정하는 셈이 된다.
        let body = try #require(api.range(of: "struct Body: Encodable"))
        let request = api[body.lowerBound...].prefix(400)
        #expect(!request.contains("price"))
    }

    @Test("내부 오류를 그대로 보여 주지 않는다")
    func providerErrorsAreTranslated() {
        for failure in [AIMirrorFailure.insufficientShards, .safetyRejected, .unavailable, .network] {
            let message = failure.message
            #expect(!message.isEmpty)
            for leak in ["openai", "provider", "500", "http"] {
                #expect(!message.lowercased().contains(leak), "\(failure): \(message)")
            }
        }
    }
}

@Suite("AI 거울 값")
@MainActor
struct AIMirrorPriceTests {

    private func maker(_ backend: FakeAIBackend) -> AIMirrorMaker {
        AIMirrorMaker(backend: backend)
    }

    @Test("값은 서버가 준 것을 쓴다")
    func priceComesFromTheServer() async {
        let backend = FakeAIBackend()
        let store = maker(backend)
        await store.refresh(session: session())
        #expect(store.price == 10)
    }

    @Test("앱에 값을 적어 두지 않는다")
    func priceIsNotHardcoded() throws {
        let view = try source("ggumirror/MyMirrors/AIMirrorView.swift")
        // 숫자를 적으면 서버 표를 바꿀 때 화면만 옛 값을 말한다.
        #expect(!view.contains("10조각"))
        #expect(view.contains("maker.price"))
        // 조각 표시는 상점·지갑과 같은 컴포넌트를 쓴다.
        #expect(view.contains("ShardAmount(amount: config.price"))
    }

    @Test("옛 서버 응답에는 값이 없다")
    func legacyConfigDecodes() throws {
        // 모르는 값이 더 실려 와도 읽힌다 — 값만 없으면 0이다.
        let json = """
        {"available":true,"dailyLimit":3,"remaining":2}
        """
        let config = try JSONDecoder.backend.decode(AIMirrorConfig.self, from: Data(json.utf8))
        #expect(config.price == 0)
        #expect(config.available)
    }

    @Test("잔액이 모자라면 서버를 부르지 않는다")
    func poorUserNeverCallsTheProvider() {
        let backend = FakeAIBackend()
        let store = maker(backend)
        // 값을 모르면(옛 서버) 막지 않는다 — 판단은 서버가 한다.
        #expect(store.canAfford(balance: 0))
    }

    @Test("값을 알면 부족할 때 막는다")
    func affordabilityUsesTheServerPrice() async {
        let backend = FakeAIBackend()
        let store = maker(backend)
        await store.refresh(session: session())

        #expect(!store.canAfford(balance: 9))
        #expect(store.canAfford(balance: 10))
        // 잔액을 모르면 막지 않는다.
        #expect(store.canAfford(balance: nil))
    }

    @Test("시도마다 다른 멱등 키를 보낸다")
    func eachAttemptCarriesARequestID() async {
        let backend = FakeAIBackend()
        let store = maker(backend)
        await store.generate(prompt: "핑크 리본", session: session())
        await store.generate(prompt: "노란 별", session: session())

        #expect(backend.requestIDs.count == 2)
        #expect(Set(backend.requestIDs).count == 2)
        #expect(backend.requestIDs.allSatisfy { !$0.isEmpty })
    }

    @Test("잔액을 앱이 계산하지 않는다")
    func balanceIsNeverDecrementedLocally() throws {
        let view = try source("ggumirror/MyMirrors/AIMirrorView.swift")
        // 성공/실패 어느 쪽에서도 앱이 잔액을 줄이지 않는다 — 서버에 다시 묻는다.
        #expect(view.contains("wallet?.refresh(session: session.server)"))
        #expect(!view.contains("balance -="))
        #expect(!view.contains("balance = balance"))
    }

    @Test("조각 부족을 사용자 말로 알린다")
    func insufficientHasItsOwnMessage() {
        #expect(AIMirrorFailure.insufficientShards.message.contains("조각"))
        // 서버가 닿지 않은 것과 다른 실패다 — 뭉치면 잘못 안내한다.
        #expect(AIMirrorFailure.insufficientShards != AIMirrorFailure.unavailable)
    }

    @Test("서버가 409로 조각 부족을 알린다")
    func statusMapping() throws {
        let api = try source("ggumirror/Backend/BackendClient+AIMirror.swift")
        #expect(api.contains("case 409: AIMirrorFailure.insufficientShards"))
    }
}
