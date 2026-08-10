//
//  LayerModels.swift
//  ggumirror
//
//  Layers가 다루는 것은 **스티커(사진 포함) / 텍스트 / 외부 디자인**이다.
//  Drawing과 Background는 순서를 바꿀 수 없는 고정 레이어다.
//
//  순서의 진실은 오직 각 오브젝트의 zIndex 하나다.
//  Layers UI / Renderer / Hit test가 모두 이 값 하나를 같은 규칙으로 읽는다.
//

import SwiftUI

/// Layers 목록 한 줄. 세 종류를 하나의 순서로 다룬다.
enum DecorationLayer: Identifiable, Equatable {
    case importedArtwork(ImportedArtworkObject)
    case sticker(StickerObject)
    case text(TextObject)

    var id: UUID {
        switch self {
        case .importedArtwork(let object): object.id
        case .sticker(let object): object.id
        case .text(let object): object.id
        }
    }

    var zIndex: Int {
        switch self {
        case .importedArtwork(let object): object.zIndex
        case .sticker(let object): object.zIndex
        case .text(let object): object.zIndex
        }
    }

    var isLocked: Bool {
        switch self {
        case .importedArtwork: false
        case .sticker(let object): object.isLocked
        case .text(let object): object.isLocked
        }
    }

    /// 목록에 보여줄 이름.
    var title: String {
        switch self {
        case .importedArtwork:
            return "외부 디자인"
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
        case .importedArtwork: "PNG"
        case .sticker(let object): object.source.photoAssetID == nil ? "스티커" : "사진 스티커"
        case .text: "텍스트"
        }
    }

    /// 렌더 순서 기준. 같은 zIndex인 데이터에서는 외부 디자인 < 스티커 < 텍스트.
    /// Renderer / hit test와 정확히 같은 규칙이다.
    var renderRank: Int {
        switch self {
        case .importedArtwork: 0
        case .sticker: 1
        case .text: 2
        }
    }

    /// 캔버스를 눌러 고를 수 있는지.
    /// 외부 디자인은 캔버스 전체를 덮으므로 여기서 빠진다 —
    /// 그렇지 않으면 어디를 눌러도 그것만 잡혀 스티커 / 텍스트를 고를 수 없다.
    /// 선택은 Layers 목록에서 한다.
    var isCanvasSelectable: Bool {
        switch self {
        case .importedArtwork: false
        case .sticker, .text: true
        }
    }

    /// 이 화면 좌표가 오브젝트 위인지. 고를 수 없는 레이어는 항상 false다.
    func contains(_ location: CGPoint, in transform: MirrorViewTransform) -> Bool {
        switch self {
        case .importedArtwork: false
        case .sticker(let object): object.contains(location, in: transform)
        case .text(let object): object.contains(location, in: transform)
        }
    }
}

extension MirrorDesign {
    /// 화면에서 **앞에 보이는 것부터** 나열한 장식 목록. Layers UI가 이 순서 그대로 보여준다.
    var decorationLayers: [DecorationLayer] {
        let all = stickers.map(DecorationLayer.sticker)
            + texts.map(DecorationLayer.text)
            + importedArtworks.map(DecorationLayer.importedArtwork)
        return all.enumerated()
            .sorted { left, right in
                let a = (left.element.zIndex, left.element.renderRank, left.offset)
                let b = (right.element.zIndex, right.element.renderRank, right.offset)
                return a > b        // 앞에 보이는 것이 먼저
            }
            .map(\.element)
    }

    /// 눌린 지점에서 화면상 가장 위에 있는 **고를 수 있는** 장식.
    /// 렌더 순서와 같은 기준을 그대로 뒤집어 쓴다 — 캔버스 tap과 Layers 목록이 어긋나지 않는다.
    func topSelectableDecoration(at location: CGPoint, in transform: MirrorViewTransform) -> DecorationLayer? {
        decorationLayers.first { $0.isCanvasSelectable && $0.contains(location, in: transform) }
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
            } else if let position = importedArtworks.firstIndex(where: { $0.id == id }) {
                importedArtworks[position].zIndex = index
            }
        }
    }
}
