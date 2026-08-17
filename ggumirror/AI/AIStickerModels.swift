//
//  AIStickerModels.swift
//  ggumirror
//
//  AI 스티커 생성의 wire format과 실패 종류.
//
//  **client는 AI provider를 직접 부르지 않는다.** provider API key는 서버에만 있고,
//  앱 bundle에는 들어가지 않는다. 여기서 하는 일은 꾸미러 backend에 프롬프트를 보내고
//  **작업 상태**를 받는 것뿐이다 — 이미지는 별도 endpoint로 받는다.
//
//  **가격을 여기에 적지 않는다.** 몇 조각인지는 서버가 `config`로 알려주고
//  화면은 받은 값을 그대로 보여준다.
//

import CoreGraphics
import Foundation
import ImageIO

/// AI 스티커를 지금 쓸 수 있는지 · 얼마인지 · 결과를 며칠 동안 다시 받을 수 있는지.
/// **전부 서버가 정한다.**
nonisolated struct AIStickerConfig: Decodable, Equatable, Sendable {
    let available: Bool
    let price: Int
    /// 서버가 결과를 보관하는 기간. 복구 안내 문구가 이 값을 쓴다.
    let resultRetentionDays: Int

    /// 서버에 물어보기 전의 상태. **모르면 꺼 둔다** — 없는 기능을 보여주지 않는다.
    static let unavailable = AIStickerConfig(available: false, price: 0, resultRetentionDays: 0)
}

/// 생성 작업의 상태. **서버가 authoritative하다.**
nonisolated enum AIGenerationStatus: String, Decodable, Sendable {
    case pending
    case succeeded
    /// 실패했는데 아직 조각을 못 돌려받았다. 서버가 다음 조회 때 되돌린다.
    case failed
    /// 실패했고 조각이 돌아왔다.
    case refunded

    /// 더 기다릴 필요가 있는가.
    var isPending: Bool { self == .pending }
}

/// `POST /ai/stickers` · `GET /ai/stickers/{id}`의 응답. **이미지가 여기 없다.**
nonisolated struct AIGeneration: Decodable, Equatable, Sendable {
    /// 서버가 만든 작업 ID. 원장의 external event id와 같은 값이다.
    let generationID: String
    let status: AIGenerationStatus
    let createdAt: Date
    /// 서버가 계산한 현재 잔액. **client가 빼서 만들지 않는다.**
    let balance: Int
    /// 실패했을 때만. 안전한 분류값이다.
    let reason: String?
    /// 실패했을 때 사용자에게 보여줄 말. 서버가 준 문구를 그대로 쓴다.
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case generationID = "generationId"
        case status, createdAt, balance, reason, message
    }
}

/// 아직 끝나지 않은 생성. **기기에 적어 둔다** — 앱을 껐다 켜도 이어받기 위해서다.
///
/// **프롬프트를 담지 않는다.** 서버도 저장하지 않고 기기도 저장하지 않는다 —
/// 이어받을 때는 `requestId`만 있으면 되고, 서버가 그 작업을 이미 알고 있다.
nonisolated struct PendingAIGeneration: Codable, Equatable, Sendable {
    /// client가 만든 멱등 키. 같은 값으로 다시 보내면 새로 만들지 않는다.
    let requestID: String
    /// 응답을 한 번이라도 받았으면 채워진다. 없으면 `requestId`로 다시 POST한다.
    var generationID: String?
    let startedAt: Date

    init(requestID: String = UUID().uuidString, generationID: String? = nil, startedAt: Date = Date()) {
        self.requestID = requestID
        self.generationID = generationID
        self.startedAt = startedAt
    }
}

/// 서버가 알려준 실패 이유. 사용자에게 무엇을 하면 되는지 다르게 말하기 위해 나눈다.
nonisolated enum AIStickerFailure: Error, Equatable {
    /// 로그인이 필요하다. AI 스티커는 조각을 쓰므로 서버 계정이 있어야 한다.
    case notSignedIn
    /// 지금은 기능이 꺼져 있다(provider · 보관소 미설정 · 서버 점검).
    case unavailable
    /// 프롬프트를 고치면 된다.
    case badPrompt(String)
    /// 조각이 모자란다.
    case insufficientShards
    /// 아직 만드는 중이다. **오류가 아니다** — 조각도 그대로 나가 있다.
    case stillPending
    /// 실패했고 **조각은 돌아왔다.**
    case refunded(String)
    /// 보관 기간이 지나 그림을 다시 받을 수 없다.
    case resultExpired
    /// 연결이 끊겼다. 작업은 서버에 남아 있으므로 다시 확인할 수 있다.
    case interrupted
    /// 그 밖의 실패.
    case failed

    var message: String {
        switch self {
        case .notSignedIn: "AI 스티커를 만들려면 로그인이 필요해요."
        case .unavailable: "지금은 AI 스티커를 만들 수 없어요. 잠시 뒤 다시 시도해 주세요."
        case .badPrompt(let reason): reason
        case .insufficientShards: "거울조각이 모자라요."
        case .stillPending: "아직 만드는 중이에요. 잠시 뒤 다시 확인해 주세요."
        case .refunded(let reason): reason
        case .resultExpired: "보관 기간이 지나 그림을 다시 받을 수 없어요."
        case .interrupted: "연결이 끊겼어요. 만들던 스티커를 다시 확인할 수 있어요."
        case .failed: "만들지 못했어요. 잠시 뒤 다시 시도해 주세요."
        }
    }

    /// 조각을 더 모으면 되는 실패인가.
    var needsShards: Bool { self == .insufficientShards }

    /// **작업이 서버에 남아 있어 다시 확인할 수 있는가.** UI가 "다시 확인"을 보여줄지 정한다.
    var isRecoverable: Bool {
        switch self {
        case .stillPending, .interrupted: true
        default: false
        }
    }
}

nonisolated extension CGImage {
    /// PNG bytes → 이미지. **알파를 유지한다** — 스티커의 전부가 투명 배경이다.
    ///
    /// 축소하지 않는다. 서버가 이미 스티커 캔버스와 같은 1024 정사각으로 만들어 보낸다.
    static func fromPNG(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
