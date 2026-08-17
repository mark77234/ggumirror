//
//  AIStickerTests.swift
//  ggumirrorTests
//
//  AI 스티커 — 생성은 **서버가 소유하는 durable 작업**이다.
//
//  여기서 지키는 것:
//  1. **provider API key가 앱 어디에도 없다.** client는 우리 backend만 부른다
//  2. **가격을 앱에 적지 않는다.** 서버가 알려준 값을 그대로 보여준다
//  3. **client가 잔액을 계산하지 않는다.** 차감도 환불도 서버가 한다
//  4. 응답이 유실돼도 **같은 requestId로 이어받는다** — 조각이 두 번 나가지 않는다
//  5. 앱을 껐다 켜도 진행 중인 생성을 복구할 수 있다
//  6. 출처(AI인지)가 저장되고, AI 스티커는 **상점에 올라가지 않는다**(내보내기는 된다)
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ggumirror

// MARK: - 가짜 backend

/// `AIStickerBackend`가 nonisolated라 이 fake도 nonisolated다.
/// test는 한 흐름으로만 부르므로 `@unchecked Sendable`로 충분하다.
final class FakeAIStickerBackend: AIStickerBackend, @unchecked Sendable {
    var config: Result<AIStickerConfig, Error> =
        .success(AIStickerConfig(available: true, price: 6, resultRetentionDays: 7))

    /// 서버가 답할 상태. 기본은 바로 성공.
    var generation: Result<AIGeneration, Error>
    var image: Result<Data, Error> = .success(FakeAIStickerBackend.transparentPNG)

    private(set) var createCalls: [(requestID: String, prompt: String)] = []
    private(set) var statusCalls: [String] = []
    private(set) var imageCalls: [String] = []

    init(status: AIGenerationStatus = .succeeded, balance: Int = 4) {
        generation = .success(AIGeneration(
            generationID: "gen-1", status: status, createdAt: Date(),
            balance: balance, reason: nil, message: nil
        ))
    }

    func aiStickerConfig(accessToken: String) async throws -> AIStickerConfig {
        try config.get()
    }

    func generateAISticker(requestID: String, prompt: String, accessToken: String) async throws -> AIGeneration {
        createCalls.append((requestID, prompt))
        return try generation.get()
    }

    func aiStickerStatus(generationID: String, accessToken: String) async throws -> AIGeneration {
        statusCalls.append(generationID)
        return try generation.get()
    }

    func aiStickerImage(generationID: String, accessToken: String) async throws -> Data {
        imageCalls.append(generationID)
        return try image.get()
    }

    func answer(_ status: AIGenerationStatus, balance: Int = 4, message: String? = nil) {
        generation = .success(AIGeneration(
            generationID: "gen-1", status: status, createdAt: Date(),
            balance: balance, reason: nil, message: message
        ))
    }

    /// 알파가 있는 1×1 PNG.
    static let transparentPNG: Data = {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }()
}

/// 기기 배경제거를 흉내 낸다. 실제 Vision은 `PhotoStickerCutout`이 부른다.
final class FakeCutout: StickerCutout, @unchecked Sendable {
    var failure: Error?
    private(set) var calls: [Data] = []

    init(failure: Error? = nil) { self.failure = failure }

    func removeBackground(from png: Data) async throws -> CGImage {
        calls.append(png)
        if let failure { throw failure }
        // 배경이 지워진 결과를 흉내 낸다 — 알파가 있는 이미지.
        return CGImage.fromPNG(FakeAIStickerBackend.transparentPNG)!
    }
}

/// 기기에 적어 두는 자리. 앱 재시작은 **같은 저장소로 새 service를 만드는 것**으로 흉내 낸다.
@MainActor
final class FakePendingStorage: PendingGenerationStorage {
    var stored: PendingAIGeneration?

    init(stored: PendingAIGeneration? = nil) {
        self.stored = stored
    }

    func load() -> PendingAIGeneration? { stored }
    func save(_ pending: PendingAIGeneration?) { stored = pending }
}

/// 지갑이 서버 값을 그대로 받는지 보기 위한 최소 backend.
final class StubShardBackend: ShardBackend, @unchecked Sendable {
    var balance = 0
    private(set) var refreshCount = 0

    func shards(accessToken: String) async throws -> ShardBalance {
        refreshCount += 1
        return ShardBalance(balance: balance, lifetimeEarned: 0, lifetimeSpent: 0)
    }
    func attendance(accessToken: String) async throws -> AttendanceStatus {
        AttendanceStatus(attendanceDate: "2026-08-16", claimed: false)
    }
    func claimAttendance(accessToken: String) async throws -> AttendanceClaim {
        AttendanceClaim(attendanceDate: "2026-08-16", claimed: false, reward: 0, balance: balance)
    }
    func rewardedAds(accessToken: String) async throws -> RewardedAdStatus {
        RewardedAdStatus(rewardedToday: 0, remainingToday: 5, dailyLimit: 5)
    }
    func rewardedAdContext(accessToken: String) async throws -> String { "ctx" }
}

@MainActor
struct AIStickerTests {

    private func session() -> ServerSession {
        ServerSession(
            accessToken: "server-token",
            expiresAt: Date(timeIntervalSinceNow: 3600),
            userID: "internal-user-1"
        )
    }

    private func wallet() -> ShardWallet { ShardWallet(backend: StubShardBackend()) }

    /// 서버가 이미 켜져 있다고 알려준 상태의 service.
    private func ready(
        _ backend: FakeAIStickerBackend,
        storage: FakePendingStorage? = nil,
        cutout: FakeCutout? = nil
    ) async -> AIStickerService {
        let service = AIStickerService(
            backend: backend,
            storage: storage ?? FakePendingStorage(),
            cutout: cutout ?? FakeCutout()
        )
        await service.refresh(session: session())
        return service
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

    // MARK: - key와 provider는 앱에 없다

    @Test("client 어디에도 AI provider API key나 provider 주소가 없다")
    func noProviderSecretsInApp() throws {
        for path in [
            "ggumirror/AI/AIStickerModels.swift",
            "ggumirror/AI/AIStickerService.swift",
            "ggumirror/AI/AIStickerPromptSheet.swift",
            "ggumirror/Backend/BackendClient.swift",
            "ggumirror/Editor/StickerCreatorView.swift",
        ] {
            let source = codeOnly(try repoFile(path))
            #expect(!source.contains("api.openai.com"), "\(path)에 provider 주소가 있다")
            #expect(!source.contains("sk-"), "\(path)에 API key 같은 값이 있다")
            #expect(!source.lowercased().contains("apikey"), "\(path)에 apiKey가 있다")
        }
    }

    @Test("빌드 설정에 AI provider key를 넣지 않았다")
    func noProviderKeyInBuildSettings() throws {
        for path in ["Config/Base.xcconfig", "Config/Debug.xcconfig", "Config/Release.xcconfig"] {
            let source = try repoFile(path)
            #expect(!source.lowercased().contains("openai"))
            #expect(!source.contains("sk-"))
        }
    }

    @Test("client가 signed URL이나 bucket 주소를 다루지 않는다")
    func noStorageURLsInApp() throws {
        for path in ["ggumirror/AI/AIStickerService.swift", "ggumirror/Backend/BackendClient.swift"] {
            let source = codeOnly(try repoFile(path))
            #expect(!source.contains("storage.googleapis.com"))
            #expect(!source.lowercased().contains("signedurl"))
        }
    }

    // MARK: - 가격 · 보관 기간은 서버가 정한다

    @Test("가격이 client에 하드코딩돼 있지 않다")
    func priceIsNotHardcoded() throws {
        let sheet = codeOnly(try repoFile("ggumirror/AI/AIStickerPromptSheet.swift"))
        #expect(sheet.contains("let price: Int"))
        #expect(!sheet.contains("= 6"))

        let service = codeOnly(try repoFile("ggumirror/AI/AIStickerService.swift"))
        #expect(!service.contains("6"))
    }

    @Test("가격과 보관 기간이 서버 config에서 온다")
    func configComesFromServer() async {
        let backend = FakeAIStickerBackend()
        backend.config = .success(AIStickerConfig(available: true, price: 9, resultRetentionDays: 3))
        let service = AIStickerService(backend: backend)

        await service.refresh(session: session())

        #expect(service.config.price == 9)
        #expect(service.config.resultRetentionDays == 3)
    }

    // MARK: - 서버가 켜 주기 전에는 꺼져 있다

    @Test("물어보기 전에는 사용할 수 없다")
    func startsUnavailable() {
        #expect(AIStickerService(backend: FakeAIStickerBackend()).config.available == false)
    }

    @Test("로그인하지 않았으면 꺼 둔다")
    func signedOutIsUnavailable() async {
        let service = AIStickerService(backend: FakeAIStickerBackend())
        await service.refresh(session: nil)
        #expect(service.config.available == false)
    }

    @Test("config 조회가 실패하면 켜진 채로 두지 않는다")
    func failedConfigStaysOff() async {
        let backend = FakeAIStickerBackend()
        backend.config = .failure(BackendError.unavailable)
        let service = AIStickerService(backend: backend)

        await service.refresh(session: session())

        #expect(service.config.available == false)
    }

    @Test("provider가 없으면 Creator에 AI 버튼이 뜨지 않는다")
    func ctaIsGatedOnServerAvailability() throws {
        let source = codeOnly(try repoFile("ggumirror/Editor/StickerCreatorView.swift"))
        #expect(source.contains("if ai.config.available"))
    }

    // MARK: - 생성

    @Test("성공하면 서버가 준 잔액을 그대로 반영하고 이미지를 받는다")
    func successAppliesServerBalance() async throws {
        let backend = FakeAIStickerBackend(balance: 4)
        let service = await ready(backend)
        let shards = wallet()

        let image = try await service.generate(
            prompt: "귀여운 고양이", session: session(), wallet: shards
        )

        #expect(image.width == 1)
        #expect(shards.balance == 4)
        #expect(backend.createCalls.count == 1)
        #expect(backend.createCalls[0].prompt == "귀여운 고양이")
        #expect(backend.imageCalls == ["gen-1"])
    }

    @Test("성공하면 진행 중 표시가 사라진다")
    func successClearsPending() async throws {
        let storage = FakePendingStorage()
        let service = await ready(FakeAIStickerBackend(), storage: storage)

        _ = try await service.generate(prompt: "고양이", session: session(), wallet: wallet())

        #expect(service.pending == nil)
        #expect(storage.stored == nil)
    }

    @Test("client가 잔액을 계산하는 코드가 없다")
    func clientNeverComputesBalance() throws {
        for path in ["ggumirror/AI/AIStickerService.swift", "ggumirror/Editor/StickerCreatorView.swift"] {
            let source = codeOnly(try repoFile(path))
            #expect(!source.contains("balance -="))
            #expect(!source.contains("balance +="))
            #expect(!source.contains("balance - "))
        }
    }

    @Test("client에 환불 코드가 없다 — 되돌리는 것은 서버다")
    func clientNeverRefunds() throws {
        let source = codeOnly(try repoFile("ggumirror/AI/AIStickerService.swift"))
        #expect(!source.lowercased().contains("refund("))
    }

    @Test("로그인하지 않았으면 서버를 부르지 않는다")
    func requiresSignIn() async {
        let backend = FakeAIStickerBackend()
        let service = await ready(backend)

        await #expect(throws: AIStickerFailure.notSignedIn) {
            try await service.generate(prompt: "고양이", session: nil, wallet: wallet())
        }
        #expect(backend.createCalls.isEmpty)
    }

    @Test("기능이 꺼져 있으면 서버를 부르지 않는다")
    func unavailableDoesNotCallServer() async {
        let backend = FakeAIStickerBackend()
        let service = AIStickerService(backend: backend)  // refresh 안 함 → 꺼진 상태

        await #expect(throws: AIStickerFailure.unavailable) {
            try await service.generate(prompt: "고양이", session: session(), wallet: wallet())
        }
        #expect(backend.createCalls.isEmpty)
    }

    @Test("조각이 모자라면 지갑을 서버에 다시 묻는다")
    func insufficientShardsRefreshesWallet() async {
        let backend = FakeAIStickerBackend()
        backend.generation = .failure(AIStickerFailure.insufficientShards)
        let service = await ready(backend)
        let shardBackend = StubShardBackend()
        let shards = ShardWallet(backend: shardBackend)

        await #expect(throws: AIStickerFailure.insufficientShards) {
            try await service.generate(prompt: "고양이", session: session(), wallet: shards)
        }
        #expect(shardBackend.refreshCount == 1)
        // 조각이 나가지 않았으므로 복구할 작업도 없다.
        #expect(service.pending == nil)
    }

    // MARK: - 응답 유실 복구

    @Test("연결이 끊기면 작업을 기억하고 다시 확인할 수 있다고 답한다")
    func networkLossKeepsPending() async {
        let backend = FakeAIStickerBackend()
        backend.generation = .failure(BackendError.unavailable)
        let storage = FakePendingStorage()
        let service = await ready(backend, storage: storage)

        await #expect(throws: AIStickerFailure.interrupted) {
            try await service.generate(prompt: "고양이", session: session(), wallet: wallet())
        }

        #expect(service.pending != nil)
        #expect(storage.stored?.requestID == service.pending?.requestID)
        #expect(AIStickerFailure.interrupted.isRecoverable)
    }

    @Test("끊긴 뒤 다시 확인하면 **같은 requestId**로 물어본다")
    func resumeReusesTheRequestID() async throws {
        let backend = FakeAIStickerBackend()
        backend.generation = .failure(BackendError.unavailable)
        let service = await ready(backend)

        await #expect(throws: AIStickerFailure.interrupted) {
            try await service.generate(prompt: "고양이", session: session(), wallet: wallet())
        }
        let requestID = try #require(service.pending?.requestID)

        backend.answer(.succeeded)
        _ = try await service.resume(session: session(), wallet: wallet())

        #expect(backend.createCalls.count == 2)
        #expect(backend.createCalls[1].requestID == requestID)
        // 이어받을 때는 프롬프트를 보내지 않는다 — 우리도 서버도 들고 있지 않다.
        #expect(backend.createCalls[1].prompt.isEmpty)
    }

    @Test("생성 중에 다시 만들기를 눌러도 새 requestId를 만들지 않는다")
    func generateWhilePendingResumesInstead() async throws {
        let backend = FakeAIStickerBackend()
        backend.generation = .failure(BackendError.unavailable)
        let service = await ready(backend)

        await #expect(throws: AIStickerFailure.interrupted) {
            try await service.generate(prompt: "고양이", session: session(), wallet: wallet())
        }
        let requestID = try #require(service.pending?.requestID)

        backend.answer(.succeeded)
        _ = try await service.generate(prompt: "다른 그림", session: session(), wallet: wallet())

        #expect(backend.createCalls.allSatisfy { $0.requestID == requestID })
    }

    @Test("아직 만드는 중이면 그렇게 답하고 계속 기억한다")
    func pendingStaysRecoverable() async {
        let backend = FakeAIStickerBackend(status: .pending)
        let service = await ready(backend)

        await #expect(throws: AIStickerFailure.stillPending) {
            try await service.generate(prompt: "고양이", session: session(), wallet: wallet())
        }

        #expect(service.pending?.generationID == "gen-1")
        #expect(AIStickerFailure.stillPending.isRecoverable)
    }

    @Test("앱을 껐다 켜도 진행 중인 생성을 이어받는다")
    func recoversAfterAppRestart() async throws {
        // 앱이 죽기 전: 작업 id까지 알고 있었다.
        let storage = FakePendingStorage(
            stored: PendingAIGeneration(requestID: "req-1", generationID: "gen-1")
        )
        let backend = FakeAIStickerBackend()
        let service = await ready(backend, storage: storage)

        #expect(service.pending?.generationID == "gen-1")

        let image = try await service.resume(session: session(), wallet: wallet())

        #expect(image.width == 1)
        // 이미 id를 알고 있으니 조회로 끝난다 — 새로 만들지 않는다.
        #expect(backend.statusCalls == ["gen-1"])
        #expect(backend.createCalls.isEmpty)
        #expect(service.pending == nil)
    }

    @Test("작업 id를 모른 채 재시작했으면 requestId로 다시 부른다")
    func recoversWithoutGenerationID() async throws {
        let storage = FakePendingStorage(stored: PendingAIGeneration(requestID: "req-1"))
        let backend = FakeAIStickerBackend()
        let service = await ready(backend, storage: storage)

        _ = try await service.resume(session: session(), wallet: wallet())

        #expect(backend.statusCalls.isEmpty)
        #expect(backend.createCalls.map(\.requestID) == ["req-1"])
    }

    @Test("이미지를 두 번 받을 수 있다 — 한 번 받으면 사라지는 그림이 아니다")
    func imageCanBeFetchedAgain() async throws {
        let backend = FakeAIStickerBackend()
        let storage = FakePendingStorage(
            stored: PendingAIGeneration(requestID: "req-1", generationID: "gen-1")
        )
        let service = await ready(backend, storage: storage)

        _ = try await service.resume(session: session(), wallet: wallet())
        storage.stored = PendingAIGeneration(requestID: "req-1", generationID: "gen-1")
        let again = AIStickerService(backend: backend, storage: storage)
        await again.refresh(session: session())
        _ = try await again.resume(session: session(), wallet: wallet())

        #expect(backend.imageCalls == ["gen-1", "gen-1"])
    }

    // MARK: - 기기 배경제거 (A-1B.2)

    @Test("AI 이미지는 기존 사진 배경제거를 그대로 지난다")
    func aiImageGoesThroughExistingCutout() async throws {
        let backend = FakeAIStickerBackend()
        let cutout = FakeCutout()
        let service = await ready(backend, cutout: cutout)

        let image = try await service.generate(prompt: "고양이", session: session(), wallet: wallet())

        // 서버에서 받은 그 bytes가 그대로 배경제거로 넘어간다.
        #expect(cutout.calls.count == 1)
        #expect(cutout.calls[0] == FakeAIStickerBackend.transparentPNG)
        #expect(image.alphaInfo != .none, "결과가 투명 스티커가 아니다")
    }

    @Test("production 컷아웃은 사진 스티커와 같은 함수를 쓴다 — 새 engine을 만들지 않았다")
    func cutoutReusesPhotoStickerMaker() throws {
        let source = codeOnly(try repoFile("ggumirror/AI/AIStickerService.swift"))
        #expect(source.contains("PhotoStickerMaker.makeSticker"))
        // 별도 segmentation을 새로 들이지 않았다.
        #expect(!source.contains("VNGenerateForegroundInstanceMaskRequest"))
        #expect(!source.contains("GenerateForegroundInstanceMaskRequest"))
    }

    @Test("배경제거 중에는 그렇게 말한다")
    func phaseSaysRemovingBackground() async throws {
        let backend = FakeAIStickerBackend()
        var seen: [AIStickerService.Phase] = []
        final class Watcher: StickerCutout, @unchecked Sendable {
            let onCall: @Sendable () -> Void
            init(onCall: @escaping @Sendable () -> Void) { self.onCall = onCall }
            func removeBackground(from png: Data) async throws -> CGImage {
                onCall()
                return CGImage.fromPNG(FakeAIStickerBackend.transparentPNG)!
            }
        }
        let service = AIStickerService(
            backend: backend, storage: FakePendingStorage(),
            cutout: Watcher(onCall: { })
        )
        await service.refresh(session: session())
        #expect(service.phase == .idle)

        _ = try await service.generate(prompt: "고양이", session: session(), wallet: wallet())
        seen.append(service.phase)
        #expect(seen == [.idle], "끝나면 idle로 돌아온다")

        let creator = codeOnly(try repoFile("ggumirror/Editor/StickerCreatorView.swift"))
        #expect(creator.contains("스티커 배경을 정리하고 있어요"))
        #expect(creator.contains("AI가 스티커를 만들고 있어요"))
    }

    @Test("배경제거가 실패해도 작업을 잊지 않는다")
    func cutoutFailureKeepsPending() async {
        let backend = FakeAIStickerBackend()
        let storage = FakePendingStorage()
        let cutout = FakeCutout(failure: PhotoStickerError.noSubject)
        let service = await ready(backend, storage: storage, cutout: cutout)

        await #expect(throws: AIStickerFailure.cutoutFailed) {
            try await service.generate(prompt: "고양이", session: session(), wallet: wallet())
        }

        #expect(service.pending?.generationID == "gen-1")
        #expect(storage.stored?.generationID == "gen-1")
        #expect(AIStickerFailure.cutoutFailed.isRecoverable)
        #expect(AIStickerFailure.cutoutFailed.message == "배경을 제거하지 못했어요.")
    }

    @Test("배경제거 재시도는 provider를 다시 부르지 않는다")
    func cutoutRetryNeverCallsProviderAgain() async throws {
        let backend = FakeAIStickerBackend()
        let cutout = FakeCutout(failure: PhotoStickerError.noSubject)
        let service = await ready(backend, cutout: cutout)

        await #expect(throws: AIStickerFailure.cutoutFailed) {
            try await service.generate(prompt: "고양이", session: session(), wallet: wallet())
        }
        let createsAfterFirst = backend.createCalls.count

        cutout.failure = nil
        let image = try await service.resume(session: session(), wallet: wallet())

        #expect(image.width >= 1)
        // 새 생성이 없다 — 상태 조회 + 이미지 재다운로드뿐이다.
        #expect(backend.createCalls.count == createsAfterFirst, "provider를 다시 불렀다")
        #expect(backend.statusCalls == ["gen-1"])
        #expect(backend.imageCalls == ["gen-1", "gen-1"], "같은 그림을 다시 받아야 한다")
        #expect(service.pending == nil)
    }

    @Test("배경제거 재시도는 조각을 다시 쓰지 않는다")
    func cutoutRetryNeverSpendsShardsAgain() async throws {
        let backend = FakeAIStickerBackend(balance: 4)
        let cutout = FakeCutout(failure: PhotoStickerError.noSubject)
        let service = await ready(backend, cutout: cutout)
        let shards = wallet()

        await #expect(throws: AIStickerFailure.cutoutFailed) {
            try await service.generate(prompt: "고양이", session: session(), wallet: shards)
        }
        #expect(shards.balance == 4)

        cutout.failure = nil
        _ = try await service.resume(session: session(), wallet: shards)

        // 서버가 준 잔액 그대로 — 두 번째 차감이 없다.
        #expect(shards.balance == 4)
    }

    @Test("앱을 껐다 켠 뒤에도 같은 그림으로 배경제거를 다시 할 수 있다")
    func cutoutRetrySurvivesAppRestart() async throws {
        let storage = FakePendingStorage(
            stored: PendingAIGeneration(requestID: "req-1", generationID: "gen-1")
        )
        let backend = FakeAIStickerBackend()
        let cutout = FakeCutout()
        let service = await ready(backend, storage: storage, cutout: cutout)

        let image = try await service.resume(session: session(), wallet: wallet())

        #expect(image.alphaInfo != .none)
        #expect(backend.createCalls.isEmpty, "재시작 후 새 생성을 만들었다")
        #expect(backend.imageCalls == ["gen-1"])
        #expect(cutout.calls.count == 1)
    }

    @Test("불투명 PNG도 정상 입력이다 — 투명은 기기가 만든다")
    func opaquePNGIsAcceptedFromServer() async throws {
        let opaque: Data = {
            let context = CGContext(
                data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )!
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            let data = NSMutableData()
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.png.identifier as CFString, 1, nil
            )!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            CGImageDestinationFinalize(destination)
            return data as Data
        }()

        let backend = FakeAIStickerBackend()
        backend.image = .success(opaque)
        let cutout = FakeCutout()
        let service = await ready(backend, cutout: cutout)

        let image = try await service.generate(prompt: "고양이", session: session(), wallet: wallet())

        #expect(cutout.calls[0] == opaque, "불투명 PNG가 배경제거로 넘어가야 한다")
        #expect(image.alphaInfo != .none, "배경제거 결과는 투명해야 한다")
    }

    // MARK: - 실패

    @Test("환불된 실패는 조각이 돌아왔다고 알려주고 작업을 잊는다")
    func refundedClearsPending() async {
        let backend = FakeAIStickerBackend()
        backend.answer(.refunded, balance: 10, message: "만드는 도중에 끊겼어요. 조각은 돌려드렸어요.")
        let storage = FakePendingStorage()
        let service = await ready(backend, storage: storage)
        let shards = wallet()

        await #expect(throws: AIStickerFailure.refunded("만드는 도중에 끊겼어요. 조각은 돌려드렸어요.")) {
            try await service.generate(prompt: "고양이", session: session(), wallet: shards)
        }

        #expect(service.pending == nil)
        #expect(storage.stored == nil)
        // 서버가 돌려준 잔액을 그대로 반영한다.
        #expect(shards.balance == 10)
    }

    @Test("보관 기간이 지났으면 붙잡고 있지 않는다")
    func expiredResultClearsPending() async {
        let backend = FakeAIStickerBackend()
        backend.image = .failure(AIStickerFailure.resultExpired)
        let service = await ready(backend)

        await #expect(throws: AIStickerFailure.resultExpired) {
            try await service.generate(prompt: "고양이", session: session(), wallet: wallet())
        }
        #expect(service.pending == nil)
    }

    @Test("사용자가 그만두면 기억에서 지운다")
    func forgetPending() async {
        let backend = FakeAIStickerBackend()
        backend.generation = .failure(BackendError.unavailable)
        let storage = FakePendingStorage()
        let service = await ready(backend, storage: storage)

        await #expect(throws: AIStickerFailure.interrupted) {
            try await service.generate(prompt: "고양이", session: session(), wallet: wallet())
        }
        service.forgetPending()

        #expect(service.pending == nil)
        #expect(storage.stored == nil)
    }

    @Test("진행 중인 생성은 프롬프트를 기기에 남기지 않는다")
    func pendingNeverStoresThePrompt() async throws {
        let backend = FakeAIStickerBackend()
        backend.generation = .failure(BackendError.unavailable)
        let storage = FakePendingStorage()
        let service = await ready(backend, storage: storage)

        await #expect(throws: AIStickerFailure.interrupted) {
            try await service.generate(prompt: "비밀 프롬프트", session: session(), wallet: wallet())
        }

        let encoded = try #require(try? JSONEncoder().encode(storage.stored))
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("비밀 프롬프트"))
        #expect(!text.lowercased().contains("prompt"))
    }

    // MARK: - 서버 실패를 사용자 말로 옮긴다

    @Test("서버 reason이 사용자가 할 수 있는 일로 나뉜다")
    func mapsServerReasons() {
        func failure(_ status: Int, _ reason: String) -> AIStickerFailure? {
            let body = #"{"detail":{"reason":"\#(reason)","message":"안내"}}"#.data(using: .utf8)!
            return BackendClient.aiFailure(status: status, data: body) as? AIStickerFailure
        }

        #expect(failure(409, "insufficient_shards") == .insufficientShards)
        #expect(failure(400, "empty_prompt") == .badPrompt("안내"))
        #expect(failure(400, "invalid_request_id") == .badPrompt("안내"))
        #expect(failure(422, "provider_rejected") == .badPrompt("안내"))
        #expect(failure(503, "not_configured") == .unavailable)
        #expect(failure(409, "still_pending") == .stillPending)
        #expect(failure(409, "interrupted") == .refunded("안내"))
        #expect(failure(503, "storage_failed") == .refunded("안내"))
        #expect(failure(410, "result_expired") == .resultExpired)
        #expect(failure(500, "who_knows") == .failed)
    }

    @Test("401은 로그인 문제로 본다")
    func unauthorizedIsSignInProblem() {
        let empty = Data()
        #expect(BackendClient.aiFailure(status: 401, data: empty) as? AIStickerFailure == .notSignedIn)
        #expect(BackendClient.aiFailure(status: 403, data: empty) as? AIStickerFailure == .notSignedIn)
    }

    @Test("남의 작업은 404다 — 조회로 답하지 않는다")
    func otherUsersGenerationIsNotFound() {
        let body = #"{"detail":{"reason":"not_found","message":"요청을 찾을 수 없어요."}}"#.data(using: .utf8)!
        #expect(BackendClient.aiFailure(status: 404, data: body) as? AIStickerFailure == .failed)
    }

    // MARK: - 시간

    @Test("AI 생성 요청은 기본 timeout(15초)을 쓰지 않는다")
    func generationUsesALongTimeout() throws {
        let source = codeOnly(try repoFile("ggumirror/Backend/BackendClient.swift"))
        #expect(source.contains("timeout: 200"))
    }

    // MARK: - PNG

    @Test("투명 PNG를 알파를 지킨 채 읽는다")
    func decodesTransparentPNG() throws {
        let image = try #require(CGImage.fromPNG(FakeAIStickerBackend.transparentPNG))
        #expect(image.width == 1)
        #expect(image.alphaInfo != .none)
    }

    @Test("PNG가 아니면 nil이다")
    func rejectsNonImageData() {
        #expect(CGImage.fromPNG(Data("nope".utf8)) == nil)
    }

    // MARK: - 출처

    @Test("AI 생성이 없으면 사람이 만든 것이다")
    func defaultOriginIsMade() {
        let project = StickerProject(name: "내 스티커")
        #expect(project.origin == .made)
        #expect(project.generationIDs.isEmpty)
        #expect(project.canPublishToStore)
    }

    @Test("AI 생성을 기록하면 출처가 바뀌고 상점에 못 올린다")
    func recordingMakesItAIGenerated() {
        var project = StickerProject(name: "내 스티커")
        project.record(generationIDs: ["gen-1"])

        #expect(project.origin == .aiGenerated)
        #expect(project.generationIDs == ["gen-1"])
        #expect(!project.canPublishToStore)
    }

    @Test("같은 생성이 두 번 적히지 않는다")
    func generationIDsAreDeduplicated() {
        var project = StickerProject(name: "내 스티커")
        project.record(generationIDs: ["gen-1"])
        project.record(generationIDs: ["gen-1", "gen-2"])

        #expect(project.generationIDs == ["gen-1", "gen-2"])
    }

    @Test("한 번 AI가 들어간 스티커는 사람이 만든 것으로 되돌아가지 않는다")
    func originIsIrreversible() {
        var project = StickerProject(name: "내 스티커")
        project.record(generationIDs: ["gen-1"])
        project.design = .blankSticker(id: project.id, name: project.name)
        project.record(generationIDs: [])

        #expect(project.origin == .aiGenerated)
    }

    @Test("프롬프트 원문을 저장하지 않는다")
    func promptIsNeverPersisted() throws {
        let source = codeOnly(try repoFile("ggumirror/Editor/StickerProject.swift"))
        #expect(!source.contains("prompt"))

        let codable = codeOnly(try repoFile("ggumirror/Shared/MirrorCodable.swift"))
        #expect(!codable.contains("prompt"))
    }

    // MARK: - 저장

    private func library() -> (StickerLibrary, StickerProjectStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ai-sticker-tests-\(UUID().uuidString)")
        let store = StickerProjectStore(root: root)
        return (StickerLibrary(store: store), store, root)
    }

    @Test("AI 생성과 함께 저장하면 출처가 파일에 남는다")
    func savesOrigin() throws {
        let (library, store, root) = library()
        defer { try? FileManager.default.removeItem(at: root) }

        let saved = try #require(library.save(
            .blankSticker(id: "x", name: "AI 고양이"),
            name: "AI 고양이",
            context: .createNew,
            generationIDs: ["gen-1"]
        ))

        #expect(saved.origin == .aiGenerated)
        #expect(saved.generationIDs == ["gen-1"])

        store.flush()
        guard case .loaded(let projects) = StickerProjectStore(root: root).load() else {
            Issue.record("저장 파일을 읽지 못했다")
            return
        }
        #expect(projects.first?.origin == .aiGenerated)
        #expect(projects.first?.generationIDs == ["gen-1"])
    }

    @Test("AI 스티커를 복제해도 AI 스티커다")
    func duplicateKeepsOrigin() throws {
        let (library, _, root) = library()
        defer { try? FileManager.default.removeItem(at: root) }

        let original = try #require(library.save(
            .blankSticker(id: "x", name: "AI 고양이"),
            name: "AI 고양이", context: .createNew, generationIDs: ["gen-1"]
        ))
        let copy = try #require(library.duplicate(original))

        #expect(copy.id != original.id)
        #expect(copy.origin == .aiGenerated)
        #expect(copy.generationIDs == ["gen-1"])
    }

    @Test("편집해서 다시 저장해도 출처가 유지된다")
    func editKeepsOrigin() throws {
        let (library, _, root) = library()
        defer { try? FileManager.default.removeItem(at: root) }

        let saved = try #require(library.save(
            .blankSticker(id: "x", name: "AI 고양이"),
            name: "AI 고양이", context: .createNew, generationIDs: ["gen-1"]
        ))
        let edited = try #require(library.save(
            saved.design, name: saved.name, context: .editExisting(saved.id)
        ))

        #expect(edited.origin == .aiGenerated)
        #expect(edited.generationIDs == ["gen-1"])
    }

    @Test("AI 스티커는 상점 등록 준비 정보를 만들 수 없다")
    func aiStickerCannotBeDrafted() throws {
        let (library, _, root) = library()
        defer { try? FileManager.default.removeItem(at: root) }

        let ai = try #require(library.save(
            .blankSticker(id: "a", name: "AI"), name: "AI",
            context: .createNew, generationIDs: ["gen-1"]
        ))
        let made = try #require(library.save(
            .blankSticker(id: "b", name: "손그림"), name: "손그림", context: .createNew
        ))

        library.saveDraft(StickerPublishDraft(stickerProjectID: ai.id))
        library.saveDraft(StickerPublishDraft(stickerProjectID: made.id))

        #expect(library.draft(for: ai.id) == nil)
        #expect(library.draft(for: made.id) != nil)
    }

    // MARK: - 저장 형식

    @Test("스티커 저장 파일 버전이 2다")
    func schemaVersionIsTwo() {
        #expect(StickerSchema.current == 2)
    }

    @Test("출처가 없던 예전 파일도 그대로 읽힌다")
    func oldFilesStillLoad() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ai-sticker-legacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let design = MirrorDesign.blankSticker(id: "legacy", name: "옛날 스티커")
        let project = StickerProject(id: "legacy", name: "옛날 스티커", design: design)
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(PersistedStickerProjects(projects: [project]))
        ) as! [String: Any]
        json["schemaVersion"] = 1
        var projects = json["projects"] as! [[String: Any]]
        projects[0].removeValue(forKey: "origin")
        projects[0].removeValue(forKey: "generationIDs")
        json["projects"] = projects
        try JSONSerialization.data(withJSONObject: json)
            .write(to: root.appending(path: "sticker-projects.json"))

        guard case .loaded(let loaded) = StickerProjectStore(root: root).load() else {
            Issue.record("예전 파일을 읽지 못했다")
            return
        }
        #expect(loaded.first?.origin == .made)
        #expect(loaded.first?.canPublishToStore == true)
    }
}
