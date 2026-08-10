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

enum MirrorOrigin: String, CaseIterable, Identifiable, Codable {
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
    /// Editor에서 얹은 텍스트.
    var texts: [TextObject] = []
}

/// 사용자 제작 거울 보관 정책. 기본 제공 / 구매 거울은 슬롯을 쓰지 않는다.
/// 추가 슬롯은 향후 조각으로 구매한다 — 실제 가격은 아직 정하지 않았다(TBD).
enum MirrorStoragePolicy {
    static let freeCreatedSlots = 3
    static let slotPackSize = 5
    /// 이름 입력 제한.
    static let maxNameLength = 24

    /// 홈에서 저장할 때 쓰는 자동 이름. 사용자에게 이름을 묻지 않는다.
    /// "나의 거울" → 이미 있으면 "나의 거울 2", "나의 거울 3" ...
    static func automaticName(existing names: [String]) -> String {
        let base = "나의 거울"
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

/// Editor에 **어떤 의도로 들어왔는가**. 저장 동작은 origin이 아니라 이 값으로 갈린다.
enum MirrorEditorContext: Equatable {
    /// 홈 → 거울 꾸미기. 지금 쓰는 거울을 그 자리에서 고친다.
    case editCurrent
    /// 내 거울 → 특정 거울 꾸미기. 원본은 두고 새 거울로 저장한다.
    case duplicate
    /// 내 거울 → + 거울 만들기. 빈 거울에서 시작한다.
    case createNew
}

/// 저장 결과. 슬롯이 없으면 조용히 실패하지 않고 이유를 돌려준다.
enum MirrorSaveOutcome: Equatable {
    case updated(id: String, name: String)
    case created(id: String, name: String)
    case needsMoreSlots

    var mirrorID: String? {
        switch self {
        case .updated(let id, _), .created(let id, _): id
        case .needsMoreSlots: nil
        }
    }

    var name: String? {
        switch self {
        case .updated(_, let name), .created(_, let name): name
        case .needsMoreSlots: nil
        }
    }
}

/// 내 거울 목록과 현재 사용 중인 거울. 앱 전체에서 이것 하나가 진실이다.
///
/// 화면은 각자 저장하지 않는다 — 여기서 바뀐 것만 디스크로 나간다.
/// 앱 시작: 파일 읽기 → 이 객체 채우기 → 화면.
/// 저장 / 만들기 / 복제 / 삭제 / 적용: 이 객체 수정 → 파일 쓰기.
@Observable
@MainActor
final class MirrorLibrary {
    private(set) var mirrors: [MyMirror]
    private(set) var currentID: String

    /// 디스크 저장소. nil이면 메모리에만 산다(미리보기 / 단위 테스트).
    private let store: MirrorStore?
    private let assets: PhotoStickerAssetStore
    /// 저장 파일이 이 앱보다 새 버전이면 읽지도 덮어쓰지도 않는다.
    private let isReadOnly: Bool

    /// 앱을 처음 설치한 사용자가 바로 거울을 쓸 수 있게 하는 기본값.
    /// My Mirrors 목록에 들어가지 않고, 슬롯도 쓰지 않으며, 구매 이력으로도 치지 않는다.
    static let defaultMirror = MyMirror(
        id: "default-mirror",
        name: "기본 거울",
        origin: .basic,
        style: BasicMirror.cream.style
    )

    /// 앱이 쓰는 하나뿐인 목록. SwiftUI가 View를 다시 만들어도 파일은 한 번만 읽고,
    /// 안 쓰는 사진 정리도 실행당 한 번만 돈다.
    static let live = MirrorLibrary(store: .live)

    init(store: MirrorStore? = nil, assets: PhotoStickerAssetStore? = nil) {
        let assets = assets ?? .shared
        self.store = store
        self.assets = assets
        // 최초 실행 시 내 거울은 비어 있다. 상점에서 받거나 직접 만들면 그때 채워진다.
        mirrors = []
        currentID = Self.defaultMirror.id

        guard let store else {
            isReadOnly = false
            return
        }
        assets.attach(store)

        switch store.load() {
        case .empty, .damaged:
            // 최초 실행이거나 파일이 깨졌다. 깨진 파일은 지우지 않고 옆에 치워둔 상태다.
            isReadOnly = false
        case .tooNew(let version):
            // 더 새 버전이 적어둔 데이터를 지금 형식으로 덮어쓰면 사용자 거울이 사라진다.
            isReadOnly = true
            #if DEBUG
            print("[MirrorLibrary] 저장 파일 버전 \(version)이 앱(\(MirrorSchema.current))보다 새롭다. 읽기 전용으로 시작한다.")
            #endif
        case .loaded(let saved):
            isReadOnly = false
            mirrors = saved.mirrors
            purchasedCreatedSlots = saved.purchasedCreatedSlots
            // 지워진 거울을 가리키고 있으면 기본 거울로 돌아간다.
            currentID = saved.mirrors.contains { $0.id == saved.currentMirrorID }
                ? saved.currentMirrorID
                : Self.defaultMirror.id
            // 렌더러가 그리다가 파일을 읽지 않도록 미리 올린다.
            assets.preload(saved.referencedAssetIDs)
        }

        guard !isReadOnly else { return }
        store.collectAssetGarbage(keeping: referencedAssetIDs)
    }

    /// 지금 어떤 거울이든 참조하는 사진 asset.
    var referencedAssetIDs: Set<UUID> {
        mirrors.reduce(into: Set<UUID>()) { $0.formUnion($1.photoAssetIDs) }
    }

    /// 의미 있는 변경 1회 = 파일 쓰기 1회. Editor의 드래그 중간 상태는 여기 오지 않는다.
    private func persist() {
        guard let store, !isReadOnly else { return }
        store.save(PersistedLibrary(
            currentMirrorID: currentID,
            mirrors: mirrors,
            purchasedCreatedSlots: purchasedCreatedSlots
        ))
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
        persist()
    }

    /// Editor 저장. 무엇이 될지는 **어디서 들어왔는가**(context)가 정한다.
    /// - `.editCurrent`: 내 거울에 이미 있는 거울이면 제자리 갱신(이름 유지, 슬롯 소모 없음).
    ///   목록에 없는 기본 거울이면 그때 한 번 새 거울을 만든다.
    /// - `.duplicate` / `.createNew`: 언제나 새 `.made` 거울. 원본은 건드리지 않는다.
    @discardableResult
    func save(
        _ design: MirrorDesign,
        name rawName: String,
        context: MirrorEditorContext
    ) -> MirrorSaveOutcome {
        if context == .editCurrent,
           let index = mirrors.firstIndex(where: { $0.id == design.id }) {
            mirrors[index].style = design.style
            mirrors[index].strokes = design.strokes
            mirrors[index].stickers = design.stickers
            mirrors[index].texts = design.texts
            // 이름은 그대로 둔다 — 홈에서 고칠 때마다 이름을 다시 묻지 않는다.
            currentID = mirrors[index].id
            persist()
            return .updated(id: mirrors[index].id, name: mirrors[index].name)
        }

        // 홈에서 들어왔다면 이름을 묻지 않는다 — 자동으로 지어준다.
        let name: String
        if context == .editCurrent {
            name = MirrorStoragePolicy.automaticName(existing: mirrors.map(\.name))
        } else if let entered = MirrorStoragePolicy.normalizedName(rawName) {
            name = entered
        } else {
            return .needsMoreSlots
        }
        guard hasFreeCreatedSlot else { return .needsMoreSlots }

        let copy = MyMirror(
            id: "made-\(UUID().uuidString)",
            name: name,
            origin: .made,
            style: design.style,
            strokes: design.strokes,
            // 사진 스티커는 assetID만 참조하므로 이미지가 다시 복사되지 않는다.
            stickers: design.stickers,
            texts: design.texts
        )
        mirrors.append(copy)
        currentID = copy.id
        persist()
        return .created(id: copy.id, name: copy.name)
    }

    /// 이 저장이 새 거울을 만들지.
    func willCreateNewMirror(for design: MirrorDesign, context: MirrorEditorContext) -> Bool {
        guard context == .editCurrent else { return true }
        return !mirrors.contains { $0.id == design.id }
    }

    /// Editor가 이름을 물어야 하는지.
    /// 홈(= 지금 쓰는 거울 수정)에서는 **절대 묻지 않는다.**
    /// 내 거울에서 새 결과물을 만들 때만 이름을 받는다.
    func needsName(for context: MirrorEditorContext) -> Bool {
        context != .editCurrent
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
        persist()
        return mirror
    }

    func apply(_ mirror: MyMirror) {
        currentID = mirror.id
        persist()
    }

    func duplicate(_ mirror: MyMirror) {
        guard hasFreeCreatedSlot, let index = mirrors.firstIndex(of: mirror) else { return }
        var copy = mirror
        copy = MyMirror(
            id: "\(mirror.id)-copy-\(mirrors.count)",
            name: "\(mirror.name) 복사본",
            origin: .made,
            style: mirror.style,
            strokes: mirror.strokes,
            stickers: mirror.stickers,
            texts: mirror.texts
        )
        mirrors.insert(copy, at: index + 1)
        persist()
    }

    /// 받은 기본 템플릿도 지울 수 있다 — 상점에서 다시 무료로 받으면 된다.
    /// 마지막 거울을 지우면 목록이 비고, 기본 거울로 돌아간다.
    func delete(_ mirror: MyMirror) {
        mirrors.removeAll { $0.id == mirror.id }
        if currentID == mirror.id { currentID = Self.defaultMirror.id }
        persist()
        // 다른 거울이 같은 사진을 쓰고 있으면 남는다. 아무도 안 쓰는 파일만 지운다.
        store?.collectAssetGarbage(keeping: referencedAssetIDs)
    }
}
