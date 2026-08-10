//
//  StoreCatalog.swift
//  ggumirror
//
//  상점에 올라가는 템플릿 목록 한 곳.
//
//  두 종류가 있다:
//    1. 단색 기본 템플릿 — 프레임 색만 다르다. 공식 제공이라 항상 무료.
//    2. 아트워크 템플릿 — 1080 × 2340 손그림 PNG 한 장이 거울의 얼굴이 된다.
//       사용자가 "외부에서 만들기"로 가져오는 것과 **완전히 같은 형식**이라
//       렌더 / 저장 / 미리보기 파이프라인을 하나도 새로 만들지 않는다.
//
//  템플릿을 늘릴 때는 `artworkTemplates`에 한 줄 추가하면 된다.
//  PNG는 Resources/StoreTemplates/<카테고리>/<파일이름>.png 에 둔다.
//  폴더 갈래는 Free / RibbonHeart / Diary / Y2K / Moments 다섯 가지로 정해 두었다.
//  (빈 폴더는 번들에 그대로 복사돼 이름 충돌을 내므로, 첫 PNG를 넣을 때 함께 만든다.)
//

import CoreGraphics
import ImageIO
import SwiftUI

// MARK: - 분류

enum StoreTag: String, CaseIterable, Identifiable {
    case ribbon = "리본"
    case y2k = "Y2K"
    case cute = "큐트"
    case minimal = "미니멀"
    case vintage = "빈티지"
    case character = "캐릭터"
    case diary = "다이어리"

    var id: String { rawValue }
}

enum StoreCategory: String, CaseIterable, Identifiable {
    case all = "전체"
    case free = "무료"
    case diary = "다이어리"
    case y2k = "Y2K"
    case basic = "기본"
    case featured = "추천"
    case popular = "인기"
    case new = "신규"

    var id: String { rawValue }
}

// MARK: - 아트워크 리소스

/// 번들에 들어 있는 전체 캔버스 PNG 한 장.
///
/// `assetID`는 **고정값**이다. 상점을 열 때마다 새 id를 만들면 같은 그림이
/// 계속 새 파일로 쌓이므로, 템플릿마다 하나씩 미리 정해 둔다.
struct StoreArtworkResource: Hashable {
    let fileName: String
    /// Resources 아래 폴더. 번들이 폴더 구조를 평탄화해도 파일 이름으로 다시 찾는다.
    let subdirectory: String
    let assetID: UUID

    var url: URL? {
        Bundle.main.url(forResource: fileName, withExtension: "png", subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: fileName, withExtension: "png")
    }

    func loadImage() -> CGImage? {
        guard let url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

// MARK: - 템플릿

struct MirrorTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let creator: String
    /// 조각 가격. 0이면 무료. 공식 기본 템플릿은 항상 0이다.
    let price: Int
    let tags: [StoreTag]
    let categories: Set<String>
    let style: MirrorStyle
    /// 손그림 PNG 템플릿이면 여기 들어온다. 단색 기본 템플릿은 nil.
    var artwork: StoreArtworkResource?

    /// 공식 단색 기본 템플릿인지. 받아도 슬롯을 쓰지 않고 항상 무료다.
    var isBasic: Bool { id.hasPrefix(StoreCatalog.basicPrefix) }
    var isFree: Bool { price == 0 }

    func matches(_ category: StoreCategory) -> Bool {
        switch category {
        case .all: true
        case .free: isFree
        default: categories.contains(category.rawValue)
        }
    }
}

// MARK: - 목록

enum StoreCatalog {
    static let basicPrefix = "basic-"

    /// 상점 전체 목록. 손그림 아트워크가 먼저, 그다음 단색 기본, 그다음 남은 샘플.
    static var samples: [MirrorTemplate] { artworkTemplates + basics + creators }

    /// 손그림 PNG 템플릿. **상점 스타일의 기준**이 되는 세 장.
    /// 새 템플릿은 여기에 추가한다 — 다른 곳은 고칠 필요가 없다.
    static let artworkTemplates: [MirrorTemplate] = [
        MirrorTemplate(
            id: "art-pink-ribbon",
            name: "핑크 리본",
            creator: "꾸미러",
            price: 0,
            tags: [.ribbon, .cute],
            categories: [StoreCategory.featured.rawValue, StoreCategory.new.rawValue],
            style: MirrorStyle(frame: Color(red: 0.980, green: 0.890, blue: 0.918)),
            artwork: StoreArtworkResource(
                fileName: "pink-ribbon",
                subdirectory: "StoreTemplates/Free",
                assetID: UUID(uuidString: "A0000001-0000-4000-A000-000000000001")!
            )
        ),
        MirrorTemplate(
            id: "art-my-diary",
            name: "마이 다이어리",
            creator: "꾸미러",
            price: 18,
            tags: [.diary, .vintage],
            categories: [StoreCategory.diary.rawValue, StoreCategory.featured.rawValue],
            style: MirrorStyle(frame: Color(red: 0.969, green: 0.945, blue: 0.890)),
            artwork: StoreArtworkResource(
                fileName: "my-diary",
                subdirectory: "StoreTemplates/Diary",
                assetID: UUID(uuidString: "A0000002-0000-4000-A000-000000000002")!
            )
        ),
        MirrorTemplate(
            id: "art-y2k-star",
            name: "Y2K 스타",
            creator: "꾸미러",
            price: 24,
            tags: [.y2k, .character],
            categories: [StoreCategory.y2k.rawValue, StoreCategory.popular.rawValue,
                         StoreCategory.new.rawValue],
            style: MirrorStyle(frame: Color(red: 0.878, green: 0.878, blue: 0.973)),
            artwork: StoreArtworkResource(
                fileName: "y2k-star",
                subdirectory: "StoreTemplates/Y2K",
                assetID: UUID(uuidString: "A0000003-0000-4000-A000-000000000003")!
            )
        ),
    ]

    /// 단색 기본 템플릿 8종. 공식 제공이라 항상 무료다.
    static let basics: [MirrorTemplate] = BasicMirror.allCases.map { basic in
        MirrorTemplate(
            id: basicPrefix + basic.id,
            name: basic.name,
            creator: "꾸미러",
            price: 0,
            tags: [.minimal],
            categories: [StoreCategory.basic.rawValue],
            style: basic.style
        )
    }

    /// **임시 placeholder.** SF Symbol을 흩뿌려 만든 개발용 샘플이라 최종 상점 콘텐츠가 아니다.
    /// 다음 Content Asset Phase에서 실제 손그림 PNG(`artworkTemplates`)로 하나씩 교체한다.
    /// 그때까지는 목록을 채워 필터 / 정렬을 확인하는 용도로만 둔다.
    static let creators: [MirrorTemplate] = [
        MirrorTemplate(
            id: "bunny-sketch",
            name: "버니 스케치",
            creator: "@dodo",
            price: 0,
            tags: [.character, .cute],
            categories: [StoreCategory.featured.rawValue],
            style: MirrorStyle(
                frame: Color(red: 0.976, green: 0.965, blue: 0.937),
                doodles: [
                    .init(symbol: "hare", x: 0.06, y: 0.038, size: 0.062, rotation: -8),
                    .init(symbol: "heart", x: 0.28, y: 0.036, size: 0.045),
                    .init(symbol: "pawprint", x: 0.52, y: 0.038, size: 0.05, rotation: 14),
                    .init(symbol: "heart", x: 0.76, y: 0.036, size: 0.045),
                    .init(symbol: "hare", x: 0.95, y: 0.038, size: 0.06, rotation: 10),
                    .init(symbol: "pawprint", x: 0.05, y: 0.26, size: 0.048, rotation: -12),
                    .init(symbol: "heart", x: 0.95, y: 0.36, size: 0.045),
                    .init(symbol: "pawprint", x: 0.05, y: 0.52, size: 0.045, rotation: 6),
                    .init(symbol: "heart", x: 0.95, y: 0.62, size: 0.045),
                    .init(symbol: "pawprint", x: 0.05, y: 0.76, size: 0.045),
                    .init(symbol: "hare", x: 0.07, y: 0.962, size: 0.06, rotation: 10),
                    .init(symbol: "pawprint", x: 0.32, y: 0.962, size: 0.05, rotation: -6),
                    .init(symbol: "heart", x: 0.56, y: 0.962, size: 0.045),
                    .init(symbol: "pawprint", x: 0.8, y: 0.962, size: 0.05, rotation: 8),
                    .init(symbol: "hare", x: 0.95, y: 0.962, size: 0.058, rotation: -10)
                ]
            )
        ),
        MirrorTemplate(
            id: "star-scribble",
            name: "별 낙서",
            creator: "@sol",
            price: 0,
            tags: [.minimal, .y2k],
            categories: [StoreCategory.new.rawValue],
            style: MirrorStyle(
                frame: Color(red: 0.969, green: 0.969, blue: 0.961),
                doodles: [
                    .init(symbol: "star", x: 0.05, y: 0.038, size: 0.052, rotation: -14),
                    .init(symbol: "sparkle", x: 0.28, y: 0.036, size: 0.042),
                    .init(symbol: "moon", x: 0.52, y: 0.038, size: 0.048),
                    .init(symbol: "sparkle", x: 0.76, y: 0.036, size: 0.042, rotation: 10),
                    .init(symbol: "star", x: 0.95, y: 0.038, size: 0.052, rotation: 8),
                    .init(symbol: "moon", x: 0.05, y: 0.3, size: 0.045, rotation: -8),
                    .init(symbol: "sparkle", x: 0.95, y: 0.42, size: 0.04),
                    .init(symbol: "star", x: 0.05, y: 0.58, size: 0.045),
                    .init(symbol: "sparkle", x: 0.95, y: 0.68, size: 0.04),
                    .init(symbol: "star", x: 0.07, y: 0.962, size: 0.05, rotation: 16),
                    .init(symbol: "sparkle", x: 0.34, y: 0.962, size: 0.042),
                    .init(symbol: "moon", x: 0.6, y: 0.962, size: 0.048),
                    .init(symbol: "star", x: 0.95, y: 0.962, size: 0.05, rotation: -10)
                ]
            )
        ),
        MirrorTemplate(
            id: "ribbon-diary",
            name: "리본 다이어리",
            creator: "@jin",
            price: 18,
            tags: [.ribbon, .diary],
            categories: [StoreCategory.popular.rawValue, StoreCategory.diary.rawValue],
            style: MirrorStyle(
                frame: Color(red: 0.941, green: 0.925, blue: 0.906),
                doodles: [
                    .init(symbol: "paperclip", x: 0.06, y: 0.038, size: 0.055, rotation: -18),
                    .init(symbol: "heart", x: 0.28, y: 0.036, size: 0.045, rotation: 12),
                    .init(symbol: "sparkle", x: 0.52, y: 0.038, size: 0.048),
                    .init(symbol: "pencil", x: 0.76, y: 0.036, size: 0.05, rotation: -30),
                    .init(symbol: "paperclip", x: 0.95, y: 0.038, size: 0.055, rotation: 8),
                    .init(symbol: "pencil", x: 0.05, y: 0.28, size: 0.048, rotation: -30),
                    .init(symbol: "heart", x: 0.95, y: 0.38, size: 0.045),
                    .init(symbol: "sparkle", x: 0.05, y: 0.54, size: 0.042),
                    .init(symbol: "paperclip", x: 0.95, y: 0.64, size: 0.048, rotation: 10),
                    .init(symbol: "heart", x: 0.05, y: 0.78, size: 0.042),
                    .init(symbol: "paperclip", x: 0.07, y: 0.962, size: 0.055, rotation: 8),
                    .init(symbol: "sparkle", x: 0.32, y: 0.962, size: 0.045),
                    .init(symbol: "heart", x: 0.58, y: 0.962, size: 0.045, rotation: -8),
                    .init(symbol: "pencil", x: 0.82, y: 0.962, size: 0.05, rotation: 20),
                    .init(symbol: "paperclip", x: 0.95, y: 0.962, size: 0.055, rotation: -12)
                ]
            )
        )
    ]
}

// MARK: - 아트워크 보관

/// 번들 PNG를 거울이 쓰는 형태(`ImportedArtworkObject`)로 바꿔 준다.
///
/// 사용자가 직접 가져올 때와 **같은 `normalize`를 거친다** — 카메라 영역이 비워지고
/// 1080 × 2340으로 맞춰지는 규칙이 상점 템플릿에도 똑같이 적용된다.
/// 결과는 템플릿 id 하나당 한 번만 만들어 캐시한다.
@MainActor
enum StoreArtworkLibrary {
    private static var cache: [String: ImportedArtworkObject] = [:]

    static func artworks(for template: MirrorTemplate) -> [ImportedArtworkObject] {
        guard let artwork = artwork(for: template) else { return [] }
        return [artwork]
    }

    static func artwork(for template: MirrorTemplate) -> ImportedArtworkObject? {
        if let cached = cache[template.id] { return cached }
        guard let resource = template.artwork,
              let image = resource.loadImage(),
              let framed = MirrorArtworkImporter.framedArtwork(image)
        else { return nil }

        ImportedArtworkAssetStore.shared.registerBundled(framed, id: resource.assetID)
        let object = ImportedArtworkObject(assetID: resource.assetID)
        cache[template.id] = object
        return object
    }
}
