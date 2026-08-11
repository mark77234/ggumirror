//
//  MirrorCodable.swift
//  ggumirror
//
//  거울 한 장을 파일로 적기 위한 Codable 표현.
//
//  모델 구조는 그대로 두고 여기서만 encode/decode를 정의한다 —
//  저장 때문에 Editor / Renderer가 쓰는 타입을 갈아엎지 않는다.
//
//  직접 적을 수 없는 것은 Color 하나뿐이라 RGBA 네 값으로 적는다.
//  UIImage / CGImage는 애초에 모델에 없다 (사진은 assetID 참조뿐).
//

import SwiftUI
import UIKit

// MARK: - Color

/// 저장용 색. sRGB 0...1 네 값. 화면 타입(Color)과 저장 타입을 여기서만 잇는다.
struct RGBAColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    nonisolated init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        red = Double(r); green = Double(g); blue = Double(b); alpha = Double(a)
    }

    nonisolated var color: Color { Color(red: red, green: green, blue: blue).opacity(alpha) }
}

// MARK: - 모르는 값 되돌리기

extension KeyedDecodingContainer {
    /// 예전/나중 빌드에서 온 모르는 enum 값이 있어도 파일 전체를 버리지 않는다.
    func decodeOrDefault<T: RawRepresentable & Decodable>(
        _ type: T.Type,
        forKey key: Key,
        default fallback: T
    ) throws -> T where T.RawValue: Decodable {
        guard let raw = try decodeIfPresent(T.RawValue.self, forKey: key) else { return fallback }
        return T(rawValue: raw) ?? fallback
    }

    func decodeColor(forKey key: Key, default fallback: Color) throws -> Color {
        try decodeIfPresent(RGBAColor.self, forKey: key)?.color ?? fallback
    }
}

// MARK: - Style

extension MirrorStyle: Codable {
    private enum CodingKeys: String, CodingKey { case frame, insets, doodles }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            frame: try container.decodeColor(forKey: .frame, default: PaperTheme.paper),
            insets: try container.decodeIfPresent(MirrorFrameInsets.self, forKey: .insets) ?? .standard,
            doodles: try container.decodeIfPresent([Doodle].self, forKey: .doodles) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(RGBAColor(frame), forKey: .frame)
        try container.encode(insets, forKey: .insets)
        try container.encode(doodles, forKey: .doodles)
    }
}

// MARK: - Drawing

extension DrawingStroke: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, points, brush, color, width, opacity, zIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            points: try container.decode([NormalizedPoint].self, forKey: .points),
            brush: try container.decodeOrDefault(EditorBrush.self, forKey: .brush, default: .pen),
            color: try container.decodeColor(forKey: .color, default: PaperTheme.ink),
            width: try container.decode(Double.self, forKey: .width),
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
            zIndex: try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(points, forKey: .points)
        try container.encode(brush, forKey: .brush)
        try container.encode(RGBAColor(color), forKey: .color)
        try container.encode(width, forKey: .width)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(zIndex, forKey: .zIndex)
    }
}

// MARK: - Sticker

/// 스티커가 무엇으로 그려지는지. 사진은 **assetID 참조만** 적는다 — 이미지는 파일로 따로 나간다.
/// 자동 합성 대신 직접 적어서 case를 늘려도 저장 형태가 흔들리지 않게 한다.
extension StickerSource: Codable {
    private enum CodingKeys: String, CodingKey { case kind, sticker, assetID, aspectRatio }
    private enum Kind: String, Codable { case builtIn, photo, doodle }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decodeOrDefault(Kind.self, forKey: .kind, default: .builtIn) {
        case .doodle:
            // 모르는 이름이면 하트로 떨어진다 — 파일 전체를 버리지 않는다.
            self = .doodle(try container.decodeOrDefault(DoodleSticker.self, forKey: .sticker, default: .heart))
        case .builtIn:
            self = .builtIn(try container.decodeOrDefault(BuiltInSticker.self, forKey: .sticker, default: .heart))
        case .photo:
            self = .photo(
                assetID: try container.decode(UUID.self, forKey: .assetID),
                aspectRatio: try container.decodeIfPresent(Double.self, forKey: .aspectRatio) ?? 1
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .doodle(let sticker):
            try container.encode(Kind.doodle, forKey: .kind)
            try container.encode(sticker, forKey: .sticker)
        case .builtIn(let sticker):
            try container.encode(Kind.builtIn, forKey: .kind)
            try container.encode(sticker, forKey: .sticker)
        case .photo(let assetID, let aspectRatio):
            try container.encode(Kind.photo, forKey: .kind)
            try container.encode(assetID, forKey: .assetID)
            try container.encode(aspectRatio, forKey: .aspectRatio)
        }
    }
}

extension StickerObject: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, source, frame, rotation, opacity, zIndex, isLocked, isFlippedHorizontally, tintColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            source: try container.decode(StickerSource.self, forKey: .source),
            frame: try container.decode(NormalizedRect.self, forKey: .frame),
            rotation: try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
            zIndex: try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0,
            isLocked: try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false,
            isFlippedHorizontally: try container.decodeIfPresent(Bool.self, forKey: .isFlippedHorizontally) ?? false,
            tintColor: try container.decodeIfPresent(RGBAColor.self, forKey: .tintColor)?.color
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(source, forKey: .source)
        try container.encode(frame, forKey: .frame)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(zIndex, forKey: .zIndex)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(isFlippedHorizontally, forKey: .isFlippedHorizontally)
        try container.encodeIfPresent(tintColor.map(RGBAColor.init), forKey: .tintColor)
    }
}

// MARK: - Text

extension TextObject: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, text, center, fontSize, style, alignment, color, rotation, opacity, zIndex, isLocked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            text: try container.decode(String.self, forKey: .text),
            center: try container.decode(NormalizedPoint.self, forKey: .center),
            fontSize: try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? TextPolicy.defaultFontSize,
            style: try container.decodeOrDefault(TextFontStyle.self, forKey: .style, default: .basic),
            alignment: try container.decodeOrDefault(TextAlignmentOption.self, forKey: .alignment, default: .center),
            color: try container.decodeColor(forKey: .color, default: PaperTheme.ink),
            rotation: try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
            zIndex: try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0,
            isLocked: try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(center, forKey: .center)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(style, forKey: .style)
        try container.encode(alignment, forKey: .alignment)
        try container.encode(RGBAColor(color), forKey: .color)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(zIndex, forKey: .zIndex)
        try container.encode(isLocked, forKey: .isLocked)
    }
}

// MARK: - Imported artwork

extension ImportedArtworkObject: Codable {
    private enum CodingKeys: String, CodingKey { case id, assetID, opacity, zIndex }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            assetID: try container.decode(UUID.self, forKey: .assetID),
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
            zIndex: try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(assetID, forKey: .assetID)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(zIndex, forKey: .zIndex)
    }
}

// MARK: - Mirror

extension MyMirror: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, origin, style, strokes, stickers, texts, importedArtworks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            origin: try container.decodeOrDefault(MirrorOrigin.self, forKey: .origin, default: .made),
            style: try container.decode(MirrorStyle.self, forKey: .style),
            strokes: try container.decodeIfPresent([DrawingStroke].self, forKey: .strokes) ?? [],
            stickers: try container.decodeIfPresent([StickerObject].self, forKey: .stickers) ?? [],
            texts: try container.decodeIfPresent([TextObject].self, forKey: .texts) ?? [],
            // schema v1에는 이 키가 없다. 빈 배열로 읽히는 것이 곧 v1 → v2 마이그레이션이다.
            importedArtworks: try container.decodeIfPresent(
                [ImportedArtworkObject].self, forKey: .importedArtworks
            ) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(origin, forKey: .origin)
        try container.encode(style, forKey: .style)
        try container.encode(strokes, forKey: .strokes)
        try container.encode(stickers, forKey: .stickers)
        try container.encode(texts, forKey: .texts)
        try container.encode(importedArtworks, forKey: .importedArtworks)
    }
}

extension MyMirror {
    /// 이 거울이 참조하는 이미지 파일. GC와 hydrate가 이 하나를 본다.
    func assetIDs(_ kind: MirrorAssetKind) -> Set<UUID> {
        switch kind {
        case .photoSticker: Set(stickers.compactMap(\.source.photoAssetID))
        case .importedArtwork: Set(importedArtworks.map(\.assetID))
        }
    }
}

// MARK: - 스티커 프로젝트

/// 스티커 캔버스는 저장할 때 거울과 같은 부품(style / strokes / stickers / texts)을 쓴다.
/// 새 저장 형식을 따로 만들지 않았다 — `canvas` 한 칸만 더 적는다.
extension MirrorDesign: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, style, strokes, stickers, texts, importedArtworks, canvas
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mirror: MyMirror(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                origin: .made,
                style: try container.decode(MirrorStyle.self, forKey: .style),
                strokes: try container.decodeIfPresent([DrawingStroke].self, forKey: .strokes) ?? [],
                stickers: try container.decodeIfPresent([StickerObject].self, forKey: .stickers) ?? [],
                texts: try container.decodeIfPresent([TextObject].self, forKey: .texts) ?? [],
                importedArtworks: try container.decodeIfPresent(
                    [ImportedArtworkObject].self, forKey: .importedArtworks
                ) ?? []
            )
        )
        // 모르는 값이면 거울로 읽는다 — 파일 전체를 버리지 않는다.
        canvas = try container.decodeOrDefault(CanvasKind.self, forKey: .canvas, default: .mirror)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(style, forKey: .style)
        try container.encode(strokes, forKey: .strokes)
        try container.encode(stickers, forKey: .stickers)
        try container.encode(texts, forKey: .texts)
        try container.encode(importedArtworks, forKey: .importedArtworks)
        try container.encode(canvas, forKey: .canvas)
    }
}

extension StickerProject: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt, design, finalAssetID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(),
            design: try container.decode(MirrorDesign.self, forKey: .design),
            // 완성 PNG는 파일에 있고 여기에는 참조만 들어온다.
            finalAssetID: try container.decodeIfPresent(UUID.self, forKey: .finalAssetID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(design, forKey: .design)
        try container.encodeIfPresent(finalAssetID, forKey: .finalAssetID)
    }
}
