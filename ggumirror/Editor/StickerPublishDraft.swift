//
//  StickerPublishDraft.swift
//  ggumirror
//
//  스티커를 상점에 올리기 전에 채우는 판매 정보.
//
//  **등록 준비까지다.** 실제 등록 / 조각 차감 / listing / 판매는 없다.
//  서버도 ledger도 없는 상태에서 "등록 완료"처럼 보이는 가짜 상태를 만들지 않는다.
//  거울 등록 준비(`MirrorPublishDraft`)와 파일도 모델도 따로 둔다.
//

import Foundation

// MARK: - 정책

enum StickerPublishPolicy {
    static let maxTitleLength = 24
    static let maxDescriptionLength = 200
    /// 판매자가 정하는 가격. 0(무료)도 허용한다.
    static let priceRange = 0...999

    /// 상점 등록 비용. 거울(10)보다 싸다 — 스티커는 더 작은 콘텐츠다.
    ///
    /// 거울과 마찬가지로 **화면·검증·안내가 전부 이 값 하나에서 나온다.**
    static let feeInShards = 5

    static func normalizedTitle(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedDescription(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Draft

struct StickerPublishDraft: Identifiable, Hashable, Codable {
    var id = UUID()
    /// 어떤 스티커를 올릴지. 디자인 복사본을 들고 있지 않다.
    var stickerProjectID: String
    var title = ""
    var description = ""
    var priceInShards = 0
    /// 사진이 함께 공개될 수 있다는 안내를 확인했는지.
    var didAcknowledgePhotoPrivacy = false
    /// 사용할 권리가 있는 콘텐츠만 올린다는 안내를 확인했는지.
    var didAcknowledgeRights = false
    var updatedAt = Date()
    /// 상점에 올린 뒤 서버가 준 listing id.
    ///
    /// **왜 여기 두는가**: backend에 "내 listing 목록"을 주는 endpoint가 없다
    /// (공개 browse는 `published`만 보여 주고, `unlisted`/`draft`는 어디에도 안 나온다).
    /// 그래서 앱이 자기 상품을 다시 찾으려면 id를 기억해야 한다 — 안 그러면
    /// 앱을 껐다 켠 뒤 자기 상품을 내릴 수 없다.
    ///
    /// optional이라 예전에 저장된 draft도 그대로 읽힌다.
    var listingID: String?
}

// MARK: - 검사

enum StickerPublishIssue: String, Equatable, CaseIterable {
    case stickerMissing
    case titleRequired
    case titleTooLong
    case descriptionTooLong
    case priceOutOfRange
    case photoPrivacyNotAcknowledged
    case rightsNotAcknowledged

    var message: String {
        switch self {
        case .stickerMissing: "스티커를 찾지 못했어요."
        case .titleRequired: "제목을 입력해 주세요."
        case .titleTooLong: "제목은 \(StickerPublishPolicy.maxTitleLength)자까지예요."
        case .descriptionTooLong: "설명은 \(StickerPublishPolicy.maxDescriptionLength)자까지예요."
        case .priceOutOfRange: "가격은 0부터 \(StickerPublishPolicy.priceRange.upperBound) 조각까지예요."
        case .photoPrivacyNotAcknowledged: "사진 공개 안내를 확인해 주세요."
        case .rightsNotAcknowledged: "콘텐츠 권리 안내를 확인해 주세요."
        }
    }
}

enum StickerPublishValidator {
    /// 등록 준비를 마칠 수 있는지. 비어 있으면 통과다.
    static func issues(for draft: StickerPublishDraft, project: StickerProject?) -> [StickerPublishIssue] {
        guard let project else { return [.stickerMissing] }

        var issues: [StickerPublishIssue] = []
        if let title = StickerPublishPolicy.normalizedTitle(draft.title) {
            if title.count > StickerPublishPolicy.maxTitleLength { issues.append(.titleTooLong) }
        } else {
            issues.append(.titleRequired)
        }
        if StickerPublishPolicy.normalizedDescription(draft.description).count
            > StickerPublishPolicy.maxDescriptionLength {
            issues.append(.descriptionTooLong)
        }
        if !StickerPublishPolicy.priceRange.contains(draft.priceInShards) {
            issues.append(.priceOutOfRange)
        }
        // 사진이 들어 있으면 그 이미지가 함께 공개될 수 있다.
        if !project.photoAssetIDs.isEmpty, !draft.didAcknowledgePhotoPrivacy {
            issues.append(.photoPrivacyNotAcknowledged)
        }
        // 권리 확인은 사진이 없어도 필요하다 — 그린 것도 남의 것일 수 있다.
        if !draft.didAcknowledgeRights {
            issues.append(.rightsNotAcknowledged)
        }
        return issues
    }
}
