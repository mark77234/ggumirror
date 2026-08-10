//
//  StickerModels.swift
//  ggumirror
//
//  Sticker도 Drawing과 같은 Master Canvas(1080 x 2340) normalized 좌표만 쓴다.
//  side별로 잘라 저장하지 않으므로 모서리를 걸친 스티커도 하나의 오브젝트다.
//

import SwiftUI

/// 기본 제공 스티커. 지금은 개발용 placeholder이고
/// 최종 hand-drawn asset library는 후속 Visual Content Polish에서 교체한다.
enum StickerCategory: String, CaseIterable, Identifiable, Hashable {
    case all = "전체"
    case heart = "하트"
    case ribbon = "리본"
    case sparkle = "반짝임"
    case flower = "꽃"
    case doodle = "두들"

    var id: String { rawValue }
}

/// 스티커를 어떻게 칠할지. 향후 사진 / 멀티컬러 asset을 위한 최소 구분이다.
enum StickerRenderMode: Hashable {
    /// 단색 template — 사용자가 색을 바꿀 수 있다.
    case template
    /// 원본 색을 그대로 쓴다. 사진 스티커가 여기 들어온다.
    case original
}

/// 기본 제공 스티커. 지금은 개발용 placeholder이고
/// 최종 hand-drawn asset library는 후속 Visual Content Polish에서 교체한다.
/// rawValue는 저장 식별자이므로 asset을 바꿔도 유지한다.
enum BuiltInSticker: String, CaseIterable, Identifiable, Hashable, Codable {
    // 하트 / 러브
    case heart, heartSmall, heartDouble, heartArrow
    // 리본 / 패션
    case ribbon, ribbonSmall, bow, tape
    // 별 / 반짝임
    case star, starSmall, sparkle, sparkles, moon
    // 꽃 / 자연
    case flower, daisy, leaf, drop
    // 두들
    case smile, check, exclaim, cloud, bolt, crown
    // 장식
    case dot, dots, scribbleLine, snow

    var id: String { rawValue }

    var category: StickerCategory {
        switch self {
        case .heart, .heartSmall, .heartDouble, .heartArrow: .heart
        case .ribbon, .ribbonSmall, .bow, .tape: .ribbon
        case .star, .starSmall, .sparkle, .sparkles, .moon: .sparkle
        case .flower, .daisy, .leaf, .drop: .flower
        default: .doodle
        }
    }

    var title: String {
        switch self {
        case .heart: "하트"
        case .heartSmall: "작은 하트"
        case .heartDouble: "겹하트"
        case .heartArrow: "하트 화살"
        case .ribbon: "리본"
        case .ribbonSmall: "작은 리본"
        case .bow: "보우"
        case .tape: "테이프"
        case .star: "별"
        case .starSmall: "작은 별"
        case .sparkle: "스파클"
        case .sparkles: "반짝임"
        case .moon: "달"
        case .flower: "꽃"
        case .daisy: "데이지"
        case .leaf: "잎"
        case .drop: "물방울"
        case .smile: "스마일"
        case .check: "체크"
        case .exclaim: "느낌표"
        case .cloud: "구름"
        case .bolt: "번개"
        case .crown: "왕관"
        case .dot: "점"
        case .dots: "점 세 개"
        case .scribbleLine: "손그림 선"
        case .snow: "눈꽃"
        }
    }

    var symbolName: String {
        switch self {
        case .heart: "heart"
        case .heartSmall: "heart.circle"
        case .heartDouble: "bolt.heart"
        case .heartArrow: "arrow.up.heart"
        case .ribbon: "bookmark"
        case .ribbonSmall: "tag"
        case .bow: "gift"
        case .tape: "paperclip"
        case .star: "star"
        case .starSmall: "star.circle"
        case .sparkle: "sparkle"
        case .sparkles: "sparkles"
        case .moon: "moon"
        case .flower: "camera.macro"
        case .daisy: "fanblades"
        case .leaf: "leaf"
        case .drop: "drop"
        case .smile: "face.smiling"
        case .check: "checkmark"
        case .exclaim: "exclamationmark"
        case .cloud: "cloud"
        case .bolt: "bolt"
        case .crown: "crown"
        case .dot: "circle"
        case .dots: "ellipsis"
        case .scribbleLine: "scribble"
        case .snow: "snowflake"
        }
    }

    /// 현재 placeholder는 전부 단색이라 tint를 지원한다.
    /// 사진 / 멀티컬러 asset이 생기면 .original을 돌려주면 된다.
    var renderMode: StickerRenderMode { .template }

    var supportsTint: Bool { renderMode == .template }

    static func all(in category: StickerCategory) -> [BuiltInSticker] {
        category == .all ? allCases : allCases.filter { $0.category == category }
    }
}

/// 스티커 하나가 무엇으로 그려지는지.
/// 사진 스티커도 **참조만** 담는다 — 이미지 자체는 PhotoStickerAssetStore에 한 번만 보관한다.
/// 덕분에 MirrorDesign / EditorSnapshot / Undo 스택에 binary가 복사되지 않는다.
enum StickerSource: Hashable {
    case builtIn(BuiltInSticker)
    /// - Parameter aspectRatio: 잘라낸 foreground의 가로 / 세로. 정사각형을 강요하지 않는다.
    case photo(assetID: UUID, aspectRatio: Double)

    var title: String {
        switch self {
        case .builtIn(let sticker): sticker.title
        case .photo: "내 사진"
        }
    }

    /// 사진은 원본 색을 그대로 쓴다 — tint를 지원하지 않는다.
    var renderMode: StickerRenderMode {
        switch self {
        case .builtIn(let sticker): sticker.renderMode
        case .photo: .original
        }
    }

    var supportsTint: Bool { renderMode == .template }

    /// 가로 / 세로 비율. 기본 제공 스티커는 정사각형이다.
    var aspectRatio: Double {
        switch self {
        case .builtIn: 1
        case .photo(_, let aspectRatio): aspectRatio
        }
    }

    var photoAssetID: UUID? {
        if case .photo(let assetID, _) = self { assetID } else { nil }
    }
}

/// 사용자가 얹은 스티커 하나.
/// 사진 스티커(Phase 3-3D)도 source만 늘려 같은 transform engine을 쓴다.
struct StickerObject: Identifiable, Hashable {
    var id = UUID()
    var source: StickerSource
    /// Master Canvas 기준 0...1 사각형.
    var frame: NormalizedRect
    var rotation: Double = 0
    var opacity: Double = 1
    var zIndex: Int = 0
    var isLocked = false
    var isFlippedHorizontally = false
    /// template 스티커의 색. nil이면 기본 잉크색.
    var tintColor: Color?

    /// 실제로 칠할 색. original 스티커는 tint를 무시한다.
    var resolvedTint: Color? {
        guard source.supportsTint else { return nil }
        return tintColor ?? PaperTheme.ink
    }

    /// 화면 폭 기준 최소 / 최대 크기. 너무 작아지거나 거울을 통째로 덮지 않게 한다.
    static let sizeRange: ClosedRange<Double> = 0.06...0.45

    var center: NormalizedPoint {
        NormalizedPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
    }

    /// Master Canvas는 세로로 길어서, 화면상 비율을 유지하려면 높이를 보정해야 한다.
    /// aspectRatio는 artwork의 가로 / 세로. 사진 스티커는 원본 비율을 그대로 쓴다.
    static func height(for width: Double, aspectRatio: Double) -> Double {
        width / max(aspectRatio, 0.0001) * MirrorCanvas.size.width / MirrorCanvas.size.height
    }

    /// 정사각 스티커용 단축. 기본 제공 스티커가 쓴다.
    static func squareHeight(for width: Double) -> Double {
        height(for: width, aspectRatio: 1)
    }

    /// 중심을 유지한 채 폭을 바꾼다. 종횡비는 항상 유지된다.
    func resized(width: Double) -> StickerObject {
        var copy = self
        let clamped = min(max(width, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        let height = Self.height(for: clamped, aspectRatio: source.aspectRatio)
        let middle = center
        copy.frame = NormalizedRect(
            x: middle.x - clamped / 2,
            y: middle.y - height / 2,
            width: clamped,
            height: height
        )
        return copy
    }

    /// 중심을 옮긴다. 위치 제약은 constrained(to:)에서 처리한다.
    func moved(to point: NormalizedPoint) -> StickerObject {
        var copy = self
        copy.frame = NormalizedRect(
            x: point.x - frame.width / 2,
            y: point.y - frame.height / 2,
            width: frame.width,
            height: frame.height
        )
        return copy
    }

    /// 스티커는 캔버스 어디에나 놓을 수 있다 — 카메라 영역도 포함이다.
    /// 화면 밖으로 완전히 사라지지 않도록 **중심**만 Master Canvas 안에 붙잡는다.
    func constrained() -> StickerObject {
        let middle = center
        return moved(to: NormalizedPoint(
            x: min(max(middle.x, 0), 1),
            y: min(max(middle.y, 0), 1)
        ))
    }

    /// 이 화면 좌표가 스티커 위인지.
    /// 회전 bounding box로 넓게 잡으면 눈에 보이는 모양과 어긋나므로,
    /// 중심 기준으로 역회전시켜 실제 스티커 사각형 안인지 본다.
    /// (좌우 뒤집기는 이 사각형에 대해 대칭이라 판정에 영향이 없다.)
    func contains(_ location: CGPoint, in transform: MirrorViewTransform) -> Bool {
        let rect = transform.rect(frame)
        let dx = location.x - rect.midX
        let dy = location.y - rect.midY
        let radians = -CGFloat(rotation) * .pi / 180
        let localX = dx * cos(radians) - dy * sin(radians)
        let localY = dx * sin(radians) + dy * cos(radians)

        // 작게 줄인 스티커만 최소 tap target까지 넓힌다.
        // 큰 스티커는 보이는 크기 그대로라 옆 스티커를 덮지 않는다.
        let width = max(rect.width, Self.minimumTapTarget)
        let height = max(rect.height, Self.minimumTapTarget)
        return abs(localX) <= width / 2 && abs(localY) <= height / 2
    }

    /// 손가락으로 다시 고를 수 있는 최소 크기(pt).
    static let minimumTapTarget: CGFloat = 44
}

// MARK: - 배치

enum StickerPlacement {
    /// 지금 보고 있는 화면 한가운데에 넣는다.
    /// 프레임이든 카메라 영역이든 사용자가 보고 있는 자리에 그대로 생긴다.
    static func insert(
        _ source: StickerSource,
        in design: MirrorDesign,
        visibleRect: NormalizedRect
    ) -> StickerObject {
        let width = 0.16
        let height = StickerObject.height(for: width, aspectRatio: source.aspectRatio)
        let viewportCenter = NormalizedPoint(
            x: visibleRect.x + visibleRect.width / 2,
            y: visibleRect.y + visibleRect.height / 2
        )

        let sticker = StickerObject(
            source: source,
            frame: NormalizedRect(
                x: viewportCenter.x - width / 2,
                y: viewportCenter.y - height / 2,
                width: width,
                height: height
            ),
            zIndex: (design.stickers.map(\.zIndex).max() ?? 0) + 1
        )
        return sticker.constrained()
    }
}
