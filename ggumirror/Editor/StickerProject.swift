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

    /// 복제할 때 붙이는 이름. 이미 있으면 번호를 늘린다.
    static func copyName(of name: String, existing names: [String]) -> String {
        let base = "\(name) 복사본"
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

// MARK: - 출처

/// 이 스티커가 **어디서 왔는가**. 저장 파일에 남는 값이라 rawValue를 바꾸지 않는다.
///
/// 무엇에 쓰는가: 내가 만든 것과 AI가 그린 것을 **구분해서 다루기 위해서**다.
/// 내보내기(D-1)는 둘 다 되지만, 상점 판매는 AI 스티커에 아직 열려 있지 않다.
/// 화면마다 "이거 AI였나"를 다시 추측하지 않도록 저장 시점에 한 번 적어 둔다.
enum StickerProjectOrigin: String, Codable, Hashable {
    /// 사람이 그리고 얹어서 만든 것.
    case made
    /// AI가 만든 레이어가 **하나라도** 들어 있는 것.
    case aiGenerated
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
    /// 사람이 만든 것인지 AI가 들어갔는지.
    var origin: StickerProjectOrigin
    /// 이 스티커에 쓰인 AI 생성들. 서버 원장의 external event id와 같은 값이라
    /// **어떤 조각이 어디에 쓰였는지** 나중에 원장만 보고 따라갈 수 있다.
    ///
    /// 프롬프트 원문은 여기에 없다. 서버도 저장하지 않고 기기도 저장하지 않는다 —
    /// 다시 편집할 때 필요한 것은 그림이지 그때 뭐라고 적었는지가 아니다.
    var generationIDs: [String]

    init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        design: MirrorDesign? = nil,
        finalAssetID: UUID? = nil,
        origin: StickerProjectOrigin = .made,
        generationIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.design = design ?? .blankSticker(id: id, name: name)
        self.finalAssetID = finalAssetID
        self.origin = origin
        self.generationIDs = generationIDs
    }

    /// 상점에 올릴 수 있는가.
    ///
    /// AI 스티커는 **아직 팔 수 없다.** 내보내기(사진 저장 · 공유)는 되고 판매만 막는다 —
    /// 내가 쓰려고 만든 것과 남에게 파는 것은 다른 문제다.
    var canPublishToStore: Bool { origin != .aiGenerated }

    /// AI 생성을 기록한다. **되돌릴 수 없다** — 한 번 AI가 들어간 스티커는
    /// 그 레이어를 지워도 출처가 `made`로 돌아가지 않는다.
    mutating func record(generationIDs newIDs: [String]) {
        guard !newIDs.isEmpty else { return }
        // 같은 생성이 두 번 적히지 않게 한다(편집을 저장할 때마다 다시 넘어온다).
        let known = Set(generationIDs)
        generationIDs.append(contentsOf: newIDs.filter { !known.contains($0) })
        origin = .aiGenerated
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
    /// 편집할 스티커. nil이면 빈 캔버스에서 새로 만든다.
    var design: MirrorDesign?
    var context: StickerSaveContext = .createNew
}
