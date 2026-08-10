//
//  LayerModels.swift
//  ggumirror
//
//  Layers가 다루는 것은 **스티커(사진 포함)와 텍스트** 뿐이다.
//  Drawing과 Background는 순서를 바꿀 수 없는 고정 레이어다.
//
//  순서의 진실은 오직 각 오브젝트의 zIndex 하나다.
//  Layers UI / Renderer / Hit test가 모두 이 값 하나를 같은 규칙으로 읽는다.
//

import SwiftUI

/// Layers 목록 한 줄. 스티커와 텍스트를 하나의 순서로 다룬다.
/// 향후 ImportedArtwork가 생기면 case 하나만 늘리면 된다 —
/// 지금 미래를 위한 generic protocol 계층을 만들지 않는다.
enum DecorationLayer: Identifiable, Equatable {
    case sticker(StickerObject)
    case text(TextObject)

    var id: UUID {
        switch self {
        case .sticker(let object): object.id
        case .text(let object): object.id
        }
    }

    var zIndex: Int {
        switch self {
        case .sticker(let object): object.zIndex
        case .text(let object): object.zIndex
        }
    }

    var isLocked: Bool {
        switch self {
        case .sticker(let object): object.isLocked
        case .text(let object): object.isLocked
        }
    }

    /// 목록에 보여줄 이름.
    var title: String {
        switch self {
        case .sticker(let object):
            return object.source.title
        case .text(let object):
            let line = object.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? "텍스트" : line
        }
    }

    var subtitle: String {
        switch self {
        case .sticker(let object): object.source.photoAssetID == nil ? "스티커" : "사진 스티커"
        case .text: "텍스트"
        }
    }

    /// 렌더 순서 기준. 같은 zIndex인 예전 데이터에서는 텍스트가 스티커 위다.
    /// Renderer / hit test와 정확히 같은 규칙이다.
    var renderRank: Int {
        switch self {
        case .sticker: 0
        case .text: 1
        }
    }
}

extension MirrorDesign {
    /// 화면에서 **앞에 보이는 것부터** 나열한 장식 목록. Layers UI가 이 순서 그대로 보여준다.
    var decorationLayers: [DecorationLayer] {
        let all = stickers.map(DecorationLayer.sticker) + texts.map(DecorationLayer.text)
        return all.enumerated()
            .sorted { left, right in
                let a = (left.element.zIndex, left.element.renderRank, left.offset)
                let b = (right.element.zIndex, right.element.renderRank, right.offset)
                return a > b        // 앞에 보이는 것이 먼저
            }
            .map(\.element)
    }
}

extension EditorSnapshot {
    /// 앞→뒤 순서를 받아 zIndex를 0부터 연속으로 다시 매긴다.
    /// 오브젝트 id와 zIndex 외의 속성은 건드리지 않는다.
    mutating func reorderDecorations(frontToBack: [UUID]) {
        for (index, id) in frontToBack.reversed().enumerated() {
            if let position = stickers.firstIndex(where: { $0.id == id }) {
                stickers[position].zIndex = index
            } else if let position = texts.firstIndex(where: { $0.id == id }) {
                texts[position].zIndex = index
            }
        }
    }
}
