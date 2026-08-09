//
//  MirrorSampleData.swift
//  ggumirror
//
//  Phase 2-2 로컬 샘플 데이터. persistence / backend는 아직 없다.
//

import SwiftUI

// MARK: - 기본 거울

/// PRODUCT.md의 기본 거울 8종. 단색 프레임 + 종이 질감만 쓴다.
enum BasicMirror: String, CaseIterable, Identifiable {
    case white, black, cream, softPink, lavender, sky, mint, gray

    var id: String { rawValue }

    var name: String {
        switch self {
        case .white: "화이트"
        case .black: "블랙"
        case .cream: "크림"
        case .softPink: "소프트 핑크"
        case .lavender: "라벤더"
        case .sky: "스카이"
        case .mint: "민트"
        case .gray: "그레이"
        }
    }

    var style: MirrorStyle {
        MirrorStyle(frame: color)   // 낙서 없음 — 기본 거울은 단색 + 종이 질감만
    }

    private var color: Color {
        switch self {
        case .white: Color(red: 0.976, green: 0.973, blue: 0.965)
        case .black: Color(red: 0.145, green: 0.141, blue: 0.137)
        case .cream: Color(red: 0.965, green: 0.937, blue: 0.855)
        case .softPink: Color(red: 0.965, green: 0.886, blue: 0.886)
        case .lavender: Color(red: 0.898, green: 0.882, blue: 0.949)
        case .sky: Color(red: 0.855, green: 0.910, blue: 0.949)
        case .mint: Color(red: 0.855, green: 0.933, blue: 0.898)
        case .gray: Color(red: 0.878, green: 0.875, blue: 0.867)
        }
    }
}

// MARK: - 상점 템플릿

enum StoreTag: String, CaseIterable, Identifiable {
    case ribbon = "리본"
    case y2k = "Y2K"
    case cute = "큐트"
    case minimal = "미니멀"
    case vintage = "빈티지"
    case character = "캐릭터"

    var id: String { rawValue }
}

enum StoreCategory: String, CaseIterable, Identifiable {
    case all = "전체"
    case featured = "추천"
    case popular = "인기"
    case new = "신규"
    case free = "무료"

    var id: String { rawValue }
}

struct MirrorTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let creator: String
    /// 조각 가격. 0이면 무료.
    let price: Int
    let tags: [StoreTag]
    let categories: Set<String>
    let style: MirrorStyle

    func matches(_ category: StoreCategory) -> Bool {
        switch category {
        case .all: true
        case .free: price == 0
        default: categories.contains(category.rawValue)
        }
    }
}

enum StoreCatalog {
    /// 손그림 ink / doodle / sticker / journaling 감성의 샘플 템플릿.
    static let samples: [MirrorTemplate] = [
        MirrorTemplate(
            id: "ribbon-heart",
            name: "리본 하트",
            creator: "@mochi",
            price: 12,
            tags: [.ribbon, .cute],
            categories: ["추천", "인기"],
            style: MirrorStyle(
                frame: Color(red: 0.976, green: 0.910, blue: 0.906),
                doodles: [
                    .init(symbol: "heart", x: 0.05, y: 0.038, size: 0.058, rotation: -12),
                    .init(symbol: "sparkle", x: 0.22, y: 0.036, size: 0.05, rotation: 8),
                    .init(symbol: "heart", x: 0.5, y: 0.04, size: 0.055),
                    .init(symbol: "sparkle", x: 0.78, y: 0.036, size: 0.05, rotation: -8),
                    .init(symbol: "heart", x: 0.95, y: 0.038, size: 0.058, rotation: 15),
                    .init(symbol: "drop", x: 0.05, y: 0.22, size: 0.05, rotation: -6),
                    .init(symbol: "heart", x: 0.95, y: 0.3, size: 0.05, rotation: 12),
                    .init(symbol: "sparkle", x: 0.05, y: 0.45, size: 0.045),
                    .init(symbol: "heart", x: 0.95, y: 0.55, size: 0.05, rotation: -10),
                    .init(symbol: "drop", x: 0.05, y: 0.7, size: 0.045, rotation: 8),
                    .init(symbol: "sparkle", x: 0.95, y: 0.78, size: 0.045),
                    .init(symbol: "heart", x: 0.06, y: 0.962, size: 0.058, rotation: 10),
                    .init(symbol: "sparkle", x: 0.3, y: 0.962, size: 0.05, rotation: -14),
                    .init(symbol: "heart", x: 0.55, y: 0.962, size: 0.055, rotation: 6),
                    .init(symbol: "sparkle", x: 0.78, y: 0.962, size: 0.05),
                    .init(symbol: "heart", x: 0.95, y: 0.962, size: 0.058, rotation: -8)
                ]
            )
        ),
        MirrorTemplate(
            id: "y2k-doodle",
            name: "Y2K 두들",
            creator: "@nabi",
            price: 20,
            tags: [.y2k, .character],
            categories: ["인기", "신규"],
            style: MirrorStyle(
                frame: Color(red: 0.898, green: 0.914, blue: 0.965),
                doodles: [
                    .init(symbol: "star", x: 0.05, y: 0.038, size: 0.058, rotation: 12),
                    .init(symbol: "circle.dashed", x: 0.24, y: 0.036, size: 0.05),
                    .init(symbol: "star", x: 0.5, y: 0.04, size: 0.055, rotation: -6),
                    .init(symbol: "sparkle", x: 0.76, y: 0.036, size: 0.048),
                    .init(symbol: "star", x: 0.95, y: 0.038, size: 0.058, rotation: -8),
                    .init(symbol: "sparkle", x: 0.05, y: 0.24, size: 0.048, rotation: -10),
                    .init(symbol: "star", x: 0.95, y: 0.32, size: 0.05, rotation: -18),
                    .init(symbol: "circle.dashed", x: 0.05, y: 0.48, size: 0.045),
                    .init(symbol: "star", x: 0.95, y: 0.58, size: 0.05, rotation: 10),
                    .init(symbol: "sparkle", x: 0.05, y: 0.72, size: 0.045),
                    .init(symbol: "circle.dashed", x: 0.95, y: 0.8, size: 0.045),
                    .init(symbol: "star", x: 0.06, y: 0.962, size: 0.058, rotation: 6),
                    .init(symbol: "sparkle", x: 0.3, y: 0.962, size: 0.05),
                    .init(symbol: "star", x: 0.55, y: 0.962, size: 0.055, rotation: -12),
                    .init(symbol: "circle.dashed", x: 0.78, y: 0.962, size: 0.048),
                    .init(symbol: "star", x: 0.95, y: 0.962, size: 0.058, rotation: 8)
                ]
            )
        ),
        MirrorTemplate(
            id: "bunny-sketch",
            name: "버니 스케치",
            creator: "@dodo",
            price: 0,
            tags: [.character, .cute],
            categories: ["추천", "신규"],
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
            id: "vintage-flower",
            name: "빈티지 플라워",
            creator: "@haru",
            price: 25,
            tags: [.vintage, .minimal],
            categories: ["추천"],
            style: MirrorStyle(
                frame: Color(red: 0.949, green: 0.937, blue: 0.898),
                doodles: [
                    .init(symbol: "camera.macro", x: 0.05, y: 0.038, size: 0.058, rotation: -10),
                    .init(symbol: "leaf", x: 0.24, y: 0.036, size: 0.05, rotation: 20),
                    .init(symbol: "camera.macro", x: 0.5, y: 0.04, size: 0.055),
                    .init(symbol: "leaf", x: 0.76, y: 0.036, size: 0.048, rotation: -16),
                    .init(symbol: "camera.macro", x: 0.95, y: 0.038, size: 0.058, rotation: 8),
                    .init(symbol: "leaf", x: 0.05, y: 0.24, size: 0.048, rotation: -24),
                    .init(symbol: "camera.macro", x: 0.95, y: 0.34, size: 0.05),
                    .init(symbol: "leaf", x: 0.05, y: 0.5, size: 0.045, rotation: 12),
                    .init(symbol: "camera.macro", x: 0.95, y: 0.6, size: 0.05),
                    .init(symbol: "leaf", x: 0.05, y: 0.74, size: 0.045, rotation: -8),
                    .init(symbol: "camera.macro", x: 0.06, y: 0.962, size: 0.058, rotation: -6),
                    .init(symbol: "leaf", x: 0.3, y: 0.962, size: 0.05, rotation: 16),
                    .init(symbol: "camera.macro", x: 0.55, y: 0.962, size: 0.055),
                    .init(symbol: "leaf", x: 0.78, y: 0.962, size: 0.048, rotation: -20),
                    .init(symbol: "camera.macro", x: 0.95, y: 0.962, size: 0.058, rotation: 10)
                ]
            )
        ),
        MirrorTemplate(
            id: "star-scribble",
            name: "별 낙서",
            creator: "@sol",
            price: 0,
            tags: [.minimal, .y2k],
            categories: ["신규"],
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
            tags: [.ribbon, .vintage],
            categories: ["인기"],
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

// MARK: - 내 거울

enum MirrorOrigin: String, CaseIterable, Identifiable {
    case basic = "기본 제공"
    case made = "내가 만든"
    case purchased = "구매한"
    case listed = "판매 중"

    var id: String { rawValue }
}

enum MyMirrorFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case made = "내가 만든"
    case purchased = "구매한"
    case listed = "판매 중"

    var id: String { rawValue }

    var origin: MirrorOrigin? {
        switch self {
        case .all: nil
        case .made: .made
        case .purchased: .purchased
        case .listed: .listed
        }
    }
}

struct MyMirror: Identifiable, Hashable {
    let id: String
    var name: String
    var origin: MirrorOrigin
    var style: MirrorStyle
    /// Editor에서 그린 획. 아직 앱이 살아 있는 동안만 유지된다.
    var strokes: [DrawingStroke] = []
}

/// 내 거울 목록과 현재 사용 중인 거울. 아직 메모리에만 있다.
@Observable
@MainActor
final class MirrorLibrary {
    private(set) var mirrors: [MyMirror]
    var currentID: String

    init() {
        var items = BasicMirror.allCases.map {
            MyMirror(id: $0.id, name: $0.name, origin: .basic, style: $0.style)
        }
        items.append(contentsOf: [
            MyMirror(
                id: "made-star",
                name: "내 별 낙서",
                origin: .made,
                style: StoreCatalog.samples[4].style
            ),
            MyMirror(
                id: "bought-ribbon",
                name: "리본 하트",
                origin: .purchased,
                style: StoreCatalog.samples[0].style
            ),
            MyMirror(
                id: "listed-bunny",
                name: "버니 스케치",
                origin: .listed,
                style: StoreCatalog.samples[2].style
            )
        ])
        mirrors = items
        currentID = BasicMirror.softPink.id
    }

    var currentMirror: MyMirror {
        mirrors.first { $0.id == currentID } ?? mirrors[0]
    }

    /// Editor에서 저장한 결과를 반영한다. 아직 메모리에만 남는다.
    func save(_ design: MirrorDesign) {
        guard let index = mirrors.firstIndex(where: { $0.id == design.id }) else { return }
        mirrors[index].style = design.style
        mirrors[index].strokes = design.strokes
        mirrors[index].name = design.name
    }

    func apply(_ mirror: MyMirror) {
        currentID = mirror.id
    }

    func duplicate(_ mirror: MyMirror) {
        guard let index = mirrors.firstIndex(of: mirror) else { return }
        var copy = mirror
        copy = MyMirror(
            id: "\(mirror.id)-copy-\(mirrors.count)",
            name: "\(mirror.name) 복사본",
            origin: .made,
            style: mirror.style,
            strokes: mirror.strokes
        )
        mirrors.insert(copy, at: index + 1)
    }

    func delete(_ mirror: MyMirror) {
        guard mirror.origin != .basic else { return }   // 기본 거울은 지울 수 없다
        mirrors.removeAll { $0.id == mirror.id }
        if currentID == mirror.id { currentID = BasicMirror.white.id }
    }
}
