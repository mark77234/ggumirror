//
//  AIStickerService.swift
//  ggumirror
//
//  AI 스티커 생성 흐름. **조각을 여기서 계산하지 않는다** — 차감도 환불도 서버가 하고,
//  이 클래스는 서버가 돌려준 잔액을 지갑에 옮겨 적기만 한다.
//
//  ## 응답을 잃어도 잃지 않는다
//
//  생성은 서버가 소유하는 작업이다. 우리는 시작할 때 `requestId`(UUID) 하나를 만들어
//  **기기에 적어 두고**, 연결이 끊기면 같은 `requestId`로 다시 물어본다.
//  서버는 그것을 새 생성이 아니라 "그 작업의 지금 상태"로 답하므로:
//
//  - 조각이 두 번 나가지 않는다
//  - 이미 만들어진 그림을 다시 받을 수 있다
//  - 앱을 껐다 켜도 이어받을 수 있다
//
//  적어 두는 것은 `requestId`와 `generationId`뿐이다. **프롬프트는 남기지 않는다** —
//  서버도 저장하지 않고, 이어받을 때 필요하지도 않다.
//

import Foundation
import SwiftUI

nonisolated protocol AIStickerBackend: Sendable {
    func aiStickerConfig(accessToken: String) async throws -> AIStickerConfig
    func generateAISticker(requestID: String, prompt: String, accessToken: String) async throws -> AIGeneration
    func aiStickerStatus(generationID: String, accessToken: String) async throws -> AIGeneration
    func aiStickerImage(generationID: String, accessToken: String) async throws -> Data
}

extension BackendClient: AIStickerBackend {}

/// 진행 중인 생성을 기기에 적어 두는 곳. 앱을 껐다 켜도 남는다.
///
/// `Sendable`이 아니라 `@MainActor`다 — 부르는 곳이 `AIStickerService` 하나뿐이고
/// 그것이 이미 MainActor다. 넘나들지 않는 값에 동시성 보증을 붙이지 않는다.
@MainActor
protocol PendingGenerationStorage {
    func load() -> PendingAIGeneration?
    func save(_ pending: PendingAIGeneration?)
}

/// `UserDefaults` 한 칸. 이만한 정보에 파일이나 Keychain을 쓰지 않는다 —
/// **secret이 아니다**(id 둘과 시각뿐).
struct UserDefaultsPendingStorage: PendingGenerationStorage {
    static let key = "ggumirror.ai.pendingGeneration"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PendingAIGeneration? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(PendingAIGeneration.self, from: data)
    }

    func save(_ pending: PendingAIGeneration?) {
        guard let pending, let data = try? JSONEncoder().encode(pending) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}

@Observable
@MainActor
final class AIStickerService {
    static let live = AIStickerService()

    /// 서버가 정한 사용 가능 여부 · 가격 · 보관 기간. **물어보기 전에는 꺼져 있다.**
    private(set) var config: AIStickerConfig = .unavailable
    /// 지금 만드는 중인가. 두 번 눌러 조각이 두 번 나가지 않게 한다.
    private(set) var isGenerating = false
    /// 아직 결과를 받지 못한 생성. 있으면 화면이 "다시 확인"을 보여준다.
    private(set) var pending: PendingAIGeneration?

    private let backend: any AIStickerBackend
    private let storage: any PendingGenerationStorage

    /// `storage`는 기본 인자로 둘 수 없다 — `@MainActor` 타입이라 기본값이
    /// nonisolated 문맥에서 만들어진다. B-5C의 `GoogleRewardedAdPresenter`와 같은 이유다.
    init(
        backend: any AIStickerBackend = BackendClient(),
        storage: (any PendingGenerationStorage)? = nil
    ) {
        self.backend = backend
        let storage = storage ?? UserDefaultsPendingStorage()
        self.storage = storage
        // 앱이 켜질 때 남아 있던 작업을 집어 든다. 조회는 화면이 요청할 때 한다.
        pending = storage.load()
    }

    /// 로그인 상태가 바뀔 때마다 다시 묻는다. 실패하면 **꺼진 상태로 둔다.**
    ///
    /// 서버는 이 요청을 받은 김에 이 사용자의 묶인 조각도 정리한다 — 앱을 켜면
    /// 끊겼던 생성이 저절로 성공이나 환불로 끝나 있다.
    func refresh(session: ServerSession?) async {
        guard let session else {
            config = .unavailable
            return
        }
        do {
            config = try await backend.aiStickerConfig(accessToken: session.accessToken)
        } catch {
            config = .unavailable
        }
    }

    /// 새 스티커를 만든다. **requestId를 먼저 적어 두고** 시작한다 —
    /// 응답이 오기 전에 죽어도 무엇을 시작했는지 남아 있어야 한다.
    func generate(
        prompt: String,
        session: ServerSession?,
        wallet: ShardWallet
    ) async throws -> CGImage {
        guard let session else { throw AIStickerFailure.notSignedIn }
        guard config.available else { throw AIStickerFailure.unavailable }
        guard !isGenerating else { throw AIStickerFailure.stillPending }

        // 이미 끝나지 않은 작업이 있으면 새로 시작하지 않는다. 그것부터 확인한다.
        if pending != nil { return try await resume(session: session, wallet: wallet) }

        let started = PendingAIGeneration()
        remember(started)

        return try await run(session: session, wallet: wallet) {
            try await self.backend.generateAISticker(
                requestID: started.requestID, prompt: prompt, accessToken: session.accessToken
            )
        }
    }

    /// 끊겼던 생성을 이어받는다. **프롬프트 없이** 물어본다.
    func resume(session: ServerSession?, wallet: ShardWallet) async throws -> CGImage {
        guard let session else { throw AIStickerFailure.notSignedIn }
        guard let pending else { throw AIStickerFailure.failed }
        guard !isGenerating else { throw AIStickerFailure.stillPending }

        return try await run(session: session, wallet: wallet) {
            if let generationID = pending.generationID {
                // 작업 id를 알고 있으면 조회가 가장 싸다.
                return try await self.backend.aiStickerStatus(
                    generationID: generationID, accessToken: session.accessToken
                )
            }
            // 응답을 한 번도 못 받았다. 같은 requestId로 다시 부른다 —
            // 서버는 새로 만들지 않고 그 작업을 돌려준다.
            return try await self.backend.generateAISticker(
                requestID: pending.requestID, prompt: "", accessToken: session.accessToken
            )
        }
    }

    /// 사용자가 포기했다. **서버 작업은 건드리지 않는다** — 조각은 서버가 알아서 정리한다.
    func forgetPending() {
        remember(nil)
    }

    // MARK: - 내부

    private func run(
        session: ServerSession,
        wallet: ShardWallet,
        request: @escaping () async throws -> AIGeneration
    ) async throws -> CGImage {
        isGenerating = true
        defer { isGenerating = false }

        let generation: AIGeneration
        do {
            generation = try await request()
        } catch let failure as AIStickerFailure {
            // 조각이 돌아왔거나 프롬프트가 잘못됐다면 그 작업은 끝난 것이다.
            if !failure.isRecoverable { remember(nil) }
            if failure.needsShards { await wallet.refresh(session: session) }
            throw failure
        } catch {
            // 네트워크가 끊겼다. **작업은 서버에 남아 있다** — 잊지 않고 다시 확인한다.
            throw AIStickerFailure.interrupted
        }

        // 서버가 계산한 잔액을 그대로 옮겨 적는다. `balance -= 6`을 하지 않는다.
        wallet.apply(balance: generation.balance)
        // 이제 작업 id를 안다. 앱을 껐다 켜도 이것으로 조회할 수 있다.
        if var current = pending, current.generationID == nil {
            current.generationID = generation.generationID
            remember(current)
        }

        switch generation.status {
        case .pending:
            throw AIStickerFailure.stillPending
        case .failed, .refunded:
            remember(nil)
            throw AIStickerFailure.refunded(generation.message ?? AIStickerFailure.failed.message)
        case .succeeded:
            break
        }

        let png: Data
        do {
            png = try await backend.aiStickerImage(
                generationID: generation.generationID, accessToken: session.accessToken
            )
        } catch let failure as AIStickerFailure {
            // 보관 기간이 지났으면 다시 받을 수 없다. 계속 붙잡고 있지 않는다.
            if case .resultExpired = failure { remember(nil) }
            throw failure
        } catch {
            throw AIStickerFailure.interrupted
        }

        guard let image = CGImage.fromPNG(png) else {
            remember(nil)
            throw AIStickerFailure.failed
        }
        // 여기까지 왔으면 그림이 손에 있다. 더 이상 복구할 것이 없다.
        remember(nil)
        return image
    }

    private func remember(_ next: PendingAIGeneration?) {
        pending = next
        storage.save(next)
    }
}
