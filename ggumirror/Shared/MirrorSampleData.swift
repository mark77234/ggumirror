//
//  MirrorSampleData.swift
//  ggumirror
//
//  Phase 2-2 로컬 샘플 데이터. persistence / backend는 아직 없다.
//

import SwiftUI

// MARK: - 기본 거울

/// 단색 기본 거울 8종. 단색 프레임 + 종이 질감만 쓴다.
/// 이제 "내 거울에 미리 들어 있는 것"이 아니라 **상점의 무료 기본 템플릿**이다.
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
    case basic = "기본"
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
    /// 조각 가격. 0이면 무료. 공식 기본 템플릿은 항상 0이다.
    let price: Int
    let tags: [StoreTag]
    let categories: Set<String>
    let style: MirrorStyle

    /// 공식 단색 기본 템플릿인지. 받아도 슬롯을 쓰지 않고 항상 무료다.
    var isBasic: Bool { id.hasPrefix(StoreCatalog.basicPrefix) }

    func matches(_ category: StoreCategory) -> Bool {
        switch category {
        case .all: true
        case .free: price == 0
        default: categories.contains(category.rawValue)
        }
    }
}

enum StoreCatalog {
    static let basicPrefix = "basic-"

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

    /// 상점 전체 목록. 기본 템플릿이 먼저, 그다음 Creator 템플릿.
    static var samples: [MirrorTemplate] { basics + creators }

    /// 손그림 ink / doodle / sticker / journaling 감성의 샘플 템플릿.
    static let creators: [MirrorTemplate] = [
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
    /// Editor에서 얹은 스티커.
    var stickers: [StickerObject] = []
}

/// 사용자 제작 거울 보관 정책. 기본 제공 / 구매 거울은 슬롯을 쓰지 않는다.
/// 추가 슬롯은 향후 조각으로 구매한다 — 실제 가격은 아직 정하지 않았다(TBD).
enum MirrorStoragePolicy {
    static let freeCreatedSlots = 3
    static let slotPackSize = 5
    /// 이름 입력 제한.
    static let maxNameLength = 24

    static func normalizedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }
}

/// 저장 결과. 슬롯이 없으면 조용히 실패하지 않고 이유를 돌려준다.
enum MirrorSaveOutcome: Equatable {
    case updated(String)
    case created(String)
    case needsMoreSlots
}

/// 내 거울 목록과 현재 사용 중인 거울. 아직 메모리에만 있다.
@Observable
@MainActor
final class MirrorLibrary {
    private(set) var mirrors: [MyMirror]
    var currentID: String

    /// 앱을 처음 설치한 사용자가 바로 거울을 쓸 수 있게 하는 기본값.
    /// My Mirrors 목록에 들어가지 않고, 슬롯도 쓰지 않으며, 구매 이력으로도 치지 않는다.
    static let defaultMirror = MyMirror(
        id: "default-mirror",
        name: "기본 거울",
        origin: .basic,
        style: BasicMirror.cream.style
    )

    init() {
        // 최초 실행 시 내 거울은 비어 있다. 상점에서 받거나 직접 만들면 그때 채워진다.
        mirrors = []
        currentID = Self.defaultMirror.id
    }

    var currentMirror: MyMirror {
        mirrors.first { $0.id == currentID } ?? Self.defaultMirror
    }

    /// 사용자가 직접 만든 거울 수. 기본 제공 / 구매 / 판매 중은 세지 않는다.
    var createdCount: Int { mirrors.count { $0.origin == .made } }

    /// 추가 슬롯 구매분. 아직 실제 결제는 없다.
    private(set) var purchasedCreatedSlots = 0

    var createdCapacity: Int { MirrorStoragePolicy.freeCreatedSlots + purchasedCreatedSlots }
    var hasFreeCreatedSlot: Bool { createdCount < createdCapacity }

    /// 향후 조각 결제가 붙을 자리. 지금은 호출되지 않는다.
    func grantSlotPack() {
        purchasedCreatedSlots += MirrorStoragePolicy.slotPackSize
    }

    /// Editor 저장.
    /// - 사용자가 만든 거울을 다시 편집하면 그 거울을 갱신한다(슬롯 추가 소모 없음).
    /// - 기본 제공 / 구매 거울을 꾸미면 원본은 두고 "내가 만든 거울"을 새로 만든다(슬롯 1개 필요).
    @discardableResult
    func save(_ design: MirrorDesign, name rawName: String) -> MirrorSaveOutcome {
        guard let name = MirrorStoragePolicy.normalizedName(rawName) else { return .needsMoreSlots }

        if let index = mirrors.firstIndex(where: { $0.id == design.id }), mirrors[index].origin == .made {
            mirrors[index].style = design.style
            mirrors[index].strokes = design.strokes
            mirrors[index].stickers = design.stickers
            mirrors[index].name = name
            currentID = mirrors[index].id
            return .updated(name)
        }

        guard hasFreeCreatedSlot else { return .needsMoreSlots }

        let copy = MyMirror(
            id: "made-\(UUID().uuidString)",
            name: name,
            origin: .made,
            style: design.style,
            strokes: design.strokes,
            stickers: design.stickers
        )
        mirrors.append(copy)
        currentID = copy.id
        return .created(name)
    }

    /// 이 디자인을 저장하면 새 슬롯이 필요한지.
    func needsNewSlot(for design: MirrorDesign) -> Bool {
        guard let mirror = mirrors.first(where: { $0.id == design.id }) else { return true }
        return mirror.origin != .made
    }

    /// 상점에서 템플릿을 받아 내 거울에 넣는다.
    /// 받은 템플릿은 사용자 제작 슬롯을 쓰지 않는다 — origin이 .made가 아니기 때문이다.
    /// 실제 조각 차감 / 서버 ledger는 향후 Store Phase.
    @discardableResult
    func acquire(_ template: MirrorTemplate) -> MyMirror {
        if let existing = mirrors.first(where: { $0.id == template.id }) { return existing }
        let mirror = MyMirror(
            id: template.id,
            name: template.name,
            origin: template.isBasic ? .basic : .purchased,
            style: template.style
        )
        mirrors.append(mirror)
        return mirror
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
            strokes: mirror.strokes,
            stickers: mirror.stickers
        )
        mirrors.insert(copy, at: index + 1)
    }

    /// 받은 기본 템플릿도 지울 수 있다 — 상점에서 다시 무료로 받으면 된다.
    /// 마지막 거울을 지우면 목록이 비고, 기본 거울로 돌아간다.
    func delete(_ mirror: MyMirror) {
        mirrors.removeAll { $0.id == mirror.id }
        if currentID == mirror.id { currentID = Self.defaultMirror.id }
    }
}
