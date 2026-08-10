//
//  MirrorPublishDraft.swift
//  ggumirror
//
//  거울을 상점에 올리기 전에 채우는 판매 정보.
//
//  중요: 이건 **등록 준비**까지다. 실제 등록 / 조각 차감 / 서버 listing은 없다.
//  로그인도 ledger도 없는 상태에서 "등록 완료"처럼 보이는 가짜 상태를 만들지 않는다.
//
//  거울 디자인(그리기 / 스티커 / 사진 / 텍스트 / 외부 디자인 / 배경)과
//  판매 정보(제목 / 설명 / 가격)는 서로 다른 것이라 따로 둔다.
//  Draft는 mirrorID만 참조하고 디자인을 복사하지 않는다 — 거울을 고치면 미리보기도 같이 바뀐다.
//

import Foundation

// MARK: - 정책

enum MirrorPublishPolicy {
    static let maxTitleLength = 24
    static let maxDescriptionLength = 200
    /// 판매자가 정하는 가격. 0(무료)도 허용한다.
    static let priceRange = 0...999
    /// 상점 공개 등록 비용. 이번 단계에서는 **안내만 하고 차감하지 않는다.**
    static let feeInShards = 20

    /// 내가 만든 거울만 올릴 수 있다.
    /// 상점에서 받은 기본 / 구매 거울을 그대로 되파는 흐름은 만들지 않는다.
    static func isEligible(_ mirror: MyMirror) -> Bool { mirror.origin == .made }

    static func normalizedTitle(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedDescription(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Draft

struct MirrorPublishDraft: Identifiable, Hashable, Codable {
    var id = UUID()
    /// 어떤 거울을 올릴지. 디자인 복사본을 들고 있지 않는다.
    var mirrorID: String
    var title = ""
    var description = ""
    var priceInShards = 0
    /// 사진 스티커가 함께 공개될 수 있다는 안내를 확인했는지.
    var didAcknowledgePhotoPrivacy = false
    var updatedAt = Date()
}

// MARK: - Manifest

/// 이 거울이 상점에 올라갈 때 함께 올라갈 이미지 목록.
/// **binary는 담지 않는다** — 참조 id만 모은다. 중복은 제거하고 순서는 항상 같다.
struct MirrorPublishManifest: Equatable {
    let mirrorID: String
    let photoAssetIDs: [UUID]
    let importedArtworkAssetIDs: [UUID]

    init(_ mirror: MyMirror) {
        mirrorID = mirror.id
        photoAssetIDs = mirror.assetIDs(.photoSticker).sorted { $0.uuidString < $1.uuidString }
        importedArtworkAssetIDs = mirror.assetIDs(.importedArtwork).sorted { $0.uuidString < $1.uuidString }
    }

    /// 내 사진이 함께 공개될 수 있다는 안내가 필요한지.
    var needsPhotoPrivacyNotice: Bool { !photoAssetIDs.isEmpty }
    /// 사용 권리 안내가 필요한지.
    var needsArtworkRightsNotice: Bool { !importedArtworkAssetIDs.isEmpty }

    var assetCount: Int { photoAssetIDs.count + importedArtworkAssetIDs.count }
}

// MARK: - 검사

enum MirrorPublishIssue: String, Equatable, CaseIterable {
    case mirrorMissing
    case notEligible
    case titleRequired
    case titleTooLong
    case descriptionTooLong
    case priceOutOfRange
    case photoAssetMissing
    case artworkAssetMissing
    case photoPrivacyNotAcknowledged

    var message: String {
        switch self {
        case .mirrorMissing: "거울을 찾지 못했어요."
        case .notEligible: "직접 만든 거울만 상점에 올릴 수 있어요."
        case .titleRequired: "제목을 입력해 주세요."
        case .titleTooLong: "제목은 \(MirrorPublishPolicy.maxTitleLength)자까지예요."
        case .descriptionTooLong: "설명은 \(MirrorPublishPolicy.maxDescriptionLength)자까지예요."
        case .priceOutOfRange: "가격은 0부터 \(MirrorPublishPolicy.priceRange.upperBound) 조각까지예요."
        case .photoAssetMissing: "사진 스티커 이미지를 찾지 못했어요."
        case .artworkAssetMissing: "외부 디자인 이미지를 찾지 못했어요."
        case .photoPrivacyNotAcknowledged: "사진 공개 안내를 확인해 주세요."
        }
    }
}

@MainActor
enum MirrorPublishValidator {
    /// 등록 준비를 마칠 수 있는지. 비어 있으면 통과다.
    /// 이미지가 하나라도 사라졌으면 완료로 넘기지 않는다.
    static func issues(
        for draft: MirrorPublishDraft,
        mirror: MyMirror?,
        photos: PhotoStickerAssetStore? = nil,
        artworks: ImportedArtworkAssetStore? = nil
    ) -> [MirrorPublishIssue] {
        let photos = photos ?? .shared
        let artworks = artworks ?? .shared
        guard let mirror else { return [.mirrorMissing] }
        guard MirrorPublishPolicy.isEligible(mirror) else { return [.notEligible] }

        var issues: [MirrorPublishIssue] = []
        if let title = MirrorPublishPolicy.normalizedTitle(draft.title) {
            if title.count > MirrorPublishPolicy.maxTitleLength { issues.append(.titleTooLong) }
        } else {
            issues.append(.titleRequired)
        }
        if MirrorPublishPolicy.normalizedDescription(draft.description).count
            > MirrorPublishPolicy.maxDescriptionLength {
            issues.append(.descriptionTooLong)
        }
        if !MirrorPublishPolicy.priceRange.contains(draft.priceInShards) {
            issues.append(.priceOutOfRange)
        }

        let manifest = MirrorPublishManifest(mirror)
        if manifest.photoAssetIDs.contains(where: { photos.image(for: $0) == nil }) {
            issues.append(.photoAssetMissing)
        }
        if manifest.importedArtworkAssetIDs.contains(where: { artworks.image(for: $0) == nil }) {
            issues.append(.artworkAssetMissing)
        }
        if manifest.needsPhotoPrivacyNotice, !draft.didAcknowledgePhotoPrivacy {
            issues.append(.photoPrivacyNotAcknowledged)
        }
        return issues
    }
}
