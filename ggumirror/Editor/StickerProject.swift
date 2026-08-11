//
//  StickerProject.swift
//  ggumirror
//
//  사용자가 만든 스티커 한 장. **완성 PNG만 저장하지 않는다** —
//  레이어를 그대로 들고 있어서 나중에 다시 열어 고칠 수 있다.
//
//  레이어 컨테이너는 거울과 같은 `MirrorDesign`(canvas: .sticker)을 쓴다.
//  같은 모델을 쓰므로 Editor 엔진 · history · renderer · 제스처가 전부 그대로 재사용된다.
//  Sticker 전용 편집 엔진을 새로 만들지 않았다.
//

import Foundation
import SwiftUI

// MARK: - 정책

enum StickerProjectPolicy {
    static let maxNameLength = 24

    /// 새 스티커 기본 이름. "내 스티커" → 이미 있으면 "내 스티커 2" …
    static func automaticName(existing names: [String]) -> String {
        let base = "내 스티커"
        guard names.contains(base) else { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    static func normalizedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }
}

/// Creator에 **어떤 의도로 들어왔는가**. 저장 동작이 이 값으로 갈린다.
///
/// My Mirrors에서 "고쳤는데 새 거울이 생기던" 버그를 여기서는 처음부터 만들지 않는다:
/// 편집은 언제나 같은 id를 갱신하고, 새 id는 `createNew` / `duplicate`만 만든다.
enum StickerSaveContext: Equatable {
    case createNew
    case editExisting(String)
    case duplicate(String)

    var existingID: String? {
        switch self {
        case .editExisting(let id): id
        case .createNew, .duplicate: nil
        }
    }

    var makesNewProject: Bool { existingID == nil }
}

// MARK: - 프로젝트

/// 다시 편집할 수 있는 스티커. 레이어를 그대로 들고 있다.
struct StickerProject: Identifiable, Hashable {
    let id: String
    var name: String
    let createdAt: Date
    var updatedAt: Date
    /// 레이어 전부(그리기 · 스티커 · 사진 · 텍스트). 거울과 같은 컨테이너다.
    var design: MirrorDesign
    /// 완성된 투명 PNG. 이미지 binary는 여기 없고 **참조만** 담는다.
    var finalAssetID: UUID?

    init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        design: MirrorDesign? = nil,
        finalAssetID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.design = design ?? .blankSticker(id: id, name: name)
        self.finalAssetID = finalAssetID
    }

    /// 레이어가 하나도 없는가. 빈 스티커는 저장할 이유가 없다.
    var isEmpty: Bool {
        design.strokes.isEmpty && design.stickers.isEmpty
            && design.texts.isEmpty && design.importedArtworks.isEmpty
    }

    /// 사진 cutout이 참조하는 asset. 최종 PNG와는 다른 것이다.
    var photoAssetIDs: Set<UUID> {
        Set(design.stickers.compactMap(\.source.photoAssetID))
    }
}

extension MirrorDesign {
    /// 빈 스티커 캔버스. **배경이 없다** — 투명 PNG가 되어야 한다.
    static func blankSticker(id: String, name: String) -> MirrorDesign {
        var design = MirrorDesign.blank
        design.id = id
        design.name = name
        design.canvas = .sticker
        // 스티커는 프레임도 카메라 영역도 없다. 캔버스 전체가 편집 대상이다.
        design.insets = MirrorFrameInsets(top: 0, right: 0, bottom: 0, left: 0)
        design.backgroundColor = .clear
        return design
    }
}

/// Creator를 어떻게 열지. `fullScreenCover(item:)`에 넘긴다.
struct StickerCreatorRequest: Identifiable {
    let id = UUID()
    var startsWithPhoto = false
}
