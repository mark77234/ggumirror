//
//  MirrorSampleData.swift
//  ggumirror
//
//  기본 거울 색과 내 거울 라이브러리.
//  상점 템플릿 목록은 Store/StoreCatalog.swift에 있다.
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
    /// 외부 그림 앱에서 가져온 전체 캔버스 디자인.
    var importedArtworks: [ImportedArtworkObject] = []
}

/// 내 거울 보관 정책.
///
/// **origin을 가리지 않는다** — 내 거울에 보이는 전부를 센다. 예전에는 `.made`만 셌는데,
/// 그러면 화면의 "3 / 3"이 실제 보관량과 달라서 왜 못 담는지 설명할 수 없었다.
///
/// 추가 슬롯은 향후 조각으로 늘린다. **가격은 아직 없다** — 임의 숫자를 적지 않는다.
enum MirrorStoragePolicy {
    /// 무료로 주어지는 보관 수. **서버에 닿기 전의 보수적 기본값이다** —
    /// 실제 authority는 서버(`GET /users/me/mirror-capacity`)다.
    static let freeMirrorSlots = 5
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

    /// 이 library가 쓰는 파일 저장소. **상점에서 받은 이미지를 내려놓을 때만** 쓴다
    /// (`MarketplaceImporter`). 거울 목록 자체는 언제나 library를 통해 바꾼다 —
    /// 이 창구로 `save(_ library:)`를 직접 부르지 않는다.
    var assetStore: MirrorStore? { store }
    private let assets: PhotoStickerAssetStore
    private let artworks: ImportedArtworkAssetStore
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

    init(
        store: MirrorStore? = nil,
        assets: PhotoStickerAssetStore? = nil,
        artworks: ImportedArtworkAssetStore? = nil
    ) {
        let assets = assets ?? .shared
        let artworks = artworks ?? .shared
        self.store = store
        self.assets = assets
        self.artworks = artworks
        // 최초 실행 시 내 거울은 비어 있다. 상점에서 받거나 직접 만들면 그때 채워진다.
        mirrors = []
        currentID = Self.defaultMirror.id

        guard let store else {
            isReadOnly = false
            return
        }
        assets.attach(store)
        artworks.attach(store)

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
            // 저장 파일의 `purchasedCreatedSlots`는 **더 이상 읽지 않는다** —
            // 산 칸은 서버에 있다. field 자체는 남겨 둔다(예전 파일이 깨지지 않게).
            // 지워진 거울을 가리키고 있으면 기본 거울로 돌아간다.
            currentID = saved.mirrors.contains { $0.id == saved.currentMirrorID }
                ? saved.currentMirrorID
                : Self.defaultMirror.id
            // 렌더러가 그리다가 파일을 읽지 않도록 미리 올린다.
            assets.preload(saved.referencedAssetIDs(.photoSticker))
            artworks.preload(saved.referencedAssetIDs(.importedArtwork))
        }

        guard !isReadOnly else { return }
        // 사라진 거울의 준비 정보는 들고 있을 이유가 없다.
        publishDrafts = store.loadDrafts().filter { draft in
            mirrors.contains { $0.id == draft.mirrorID }
        }
        collectAssetGarbage()
    }

    // MARK: - 상점 등록 준비

    /// 상점에 올리기 전에 채워 둔 판매 정보. 거울 디자인과 별개다.
    /// 저장한다고 origin / 슬롯 / 조각 / 상점 목록이 바뀌지 않는다.
    private(set) var publishDrafts: [MirrorPublishDraft] = []

    func publishDraft(for mirrorID: String) -> MirrorPublishDraft? {
        publishDrafts.first { $0.mirrorID == mirrorID }
    }

    /// 거울 하나에 준비 정보 하나. 같은 거울이면 덮어쓴다.
    func savePublishDraft(_ draft: MirrorPublishDraft) {
        var updated = draft
        updated.updatedAt = Date()
        if let index = publishDrafts.firstIndex(where: { $0.mirrorID == draft.mirrorID }) {
            updated.id = publishDrafts[index].id
            publishDrafts[index] = updated
        } else {
            publishDrafts.append(updated)
        }
        store?.saveDrafts(publishDrafts)
    }

    func deletePublishDraft(for mirrorID: String) {
        guard publishDrafts.contains(where: { $0.mirrorID == mirrorID }) else { return }
        publishDrafts.removeAll { $0.mirrorID == mirrorID }
        store?.saveDrafts(publishDrafts)
    }

    /// 지금 어떤 거울이든 참조하는 asset. 종류별로 따로 센다.
    func referencedAssetIDs(_ kind: MirrorAssetKind) -> Set<UUID> {
        mirrors.reduce(into: Set<UUID>()) { $0.formUnion($1.assetIDs(kind)) }
    }

    /// 아무 거울도 참조하지 않는 이미지 파일을 지운다. 종류마다 자기 폴더에서만.
    private func collectAssetGarbage() {
        guard let store else { return }
        for kind in MirrorAssetKind.allCases {
            store.collectAssetGarbage(keeping: referencedAssetIDs(kind), kind: kind)
        }
    }

    /// 의미 있는 변경 1회 = 파일 쓰기 1회. Editor의 드래그 중간 상태는 여기 오지 않는다.
    private func persist() {
        guard let store, !isReadOnly else { return }
        store.save(PersistedLibrary(
            currentMirrorID: currentID,
            mirrors: mirrors,
            // 로컬에 칸을 적지 않는다. 이 값이 authority가 되는 길을 남기지 않는다.
            purchasedCreatedSlots: 0
        ))
    }

    var currentMirror: MyMirror {
        mirrors.first { $0.id == currentID } ?? Self.defaultMirror
    }

    /// 지금 보관 중인 거울 수. **origin을 가리지 않는다.** 보관 한도는 이 값으로 본다.
    var storedCount: Int { mirrors.count }

    /// 사용자가 직접 만든 거울 수. **한도 계산이 아니라** "이 동작이 새 거울을 만들었나"를
    /// 보는 용도다 — 한도를 origin으로 나누던 시절의 뜻이 아니다.
    var createdCount: Int { mirrors.count { $0.origin == .made } }

    /// 담을 수 있는 칸. **서버가 authority다.**
    ///
    /// 조각으로 산 칸은 서버 사용자 문서에 있다 — 이 기기의 저장 파일이 아니다.
    /// 앱을 지우거나 기기를 바꿔도 산 칸은 그대로 남는다.
    ///
    /// 서버에 닿기 전에는 **무료 기본값**이다. 못 읽었다고 예전 로컬 값을 authority로
    /// 올리지 않는다 — 그러면 결제하지 않은 칸이 생긴다.
    private(set) var mirrorCapacity: Int = MirrorStoragePolicy.freeMirrorSlots

    /// 서버가 알려준 칸 수를 옮겨 적는다. **`ShardWallet.apply(balance:)`와 같은 규칙이다** —
    /// 여기서 더하거나 빼지 않고 받은 값을 그대로 쓴다.
    ///
    /// 무료 기본값보다 작은 값은 무시한다. 잘못된 응답 하나로 이미 담아 둔 거울을
    /// 못 쓰게 만들지 않는다.
    func applyServerCapacity(_ effectiveSlots: Int) {
        guard effectiveSlots >= MirrorStoragePolicy.freeMirrorSlots else { return }
        mirrorCapacity = effectiveSlots
    }

    /// 하나 더 담을 수 있는가.
    ///
    /// **이미 한도를 넘긴 사용자의 거울을 지우지 않는다** — 더 담기는 것만 막는다.
    /// 예전 정책에서는 셋 이상 만들 수 있었으므로 실제로 넘긴 사용자가 있다.
    var hasFreeMirrorSlot: Bool { storedCount < mirrorCapacity }


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
            mirrors[index].importedArtworks = design.importedArtworks
            // 이름은 그대로 둔다 — 홈에서 고칠 때마다 이름을 다시 묻지 않는다.
            // 적용 상태도 건드리지 않는다: 내 거울에서 **지금 쓰지 않는** 거울을 고쳤다고
            // 쓰던 거울이 바뀌면 안 된다. 적용은 `적용` 동작이 따로 한다.
            // (홈에서 들어온 경우는 design.id == currentID라 어차피 같은 값이다.)
            if design.id == currentID { currentID = mirrors[index].id }
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
        guard hasFreeMirrorSlot else { return .needsMoreSlots }

        let copy = MyMirror(
            id: "made-\(UUID().uuidString)",
            name: name,
            origin: .made,
            style: design.style,
            strokes: design.strokes,
            // 사진 / 외부 디자인은 assetID만 참조하므로 이미지가 다시 복사되지 않는다.
            stickers: design.stickers,
            texts: design.texts,
            importedArtworks: design.importedArtworks
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
    ///
    /// **보관 공간이 없으면 `nil`이다.** 받은 거울도 자리를 차지한다 —
    /// 예전에는 `.made`만 셌기 때문에 화면의 남은 칸과 실제 보관량이 어긋났다.
    /// 이미 가지고 있으면 자리를 새로 쓰지 않으므로 그대로 돌려준다.
    ///
    /// 실제 조각 차감 / 서버 ledger는 향후 Store Phase.
    @discardableResult
    func acquire(_ template: MirrorTemplate) -> MyMirror? {
        if let existing = mirrors.first(where: { $0.id == template.id }) { return existing }
        guard hasFreeMirrorSlot else { return nil }
        // 손그림 템플릿은 PNG 한 장이 거울의 얼굴이다. 사용자가 가져온 외부 디자인과 같은 형식이라
        // 저장 / 렌더 / 미리보기가 그대로 따라온다.
        let artworks = StoreArtworkLibrary.artworks(for: template)
        let mirror = MyMirror(
            id: template.id,
            name: template.name,
            origin: template.isBasic ? .basic : .purchased,
            style: template.style,
            importedArtworks: artworks
        )
        // 이제 거울이 참조하므로 그림을 파일로 내려둔다. 앱을 껐다 켜도 남는다.
        for artwork in artworks { self.artworks.persistToDisk(artwork.assetID) }
        mirrors.append(mirror)
        persist()
        return mirror
    }

    /// 상점에서 산 거울을 목록에 담는다.
    ///
    /// `acquire`는 **내장 템플릿**용이라 번들 그림을 찾는다. 이쪽은 서버에서 받아
    /// 이미 파일로 내려놓은 거울이라 그 단계가 없다 — 목록에 넣고 저장만 한다.
    /// 같은 id가 이미 있으면 **덮어쓰지 않는다.** 보관 공간이 없으면 `nil`이다 —
    /// 서버 소유권은 그대로 남으므로 자리를 비우고 다시 받을 수 있다.
    @discardableResult
    func adopt(_ mirror: MyMirror) -> MyMirror? {
        if let existing = mirrors.first(where: { $0.id == mirror.id }) { return existing }
        guard hasFreeMirrorSlot else { return nil }
        mirrors.append(mirror)
        persist()
        return mirror
    }

    func apply(_ mirror: MyMirror) {
        currentID = mirror.id
        persist()
    }

    func duplicate(_ mirror: MyMirror) {
        guard hasFreeMirrorSlot, let index = mirrors.firstIndex(of: mirror) else { return }
        var copy = mirror
        copy = MyMirror(
            id: "\(mirror.id)-copy-\(mirrors.count)",
            name: "\(mirror.name) 복사본",
            origin: .made,
            style: mirror.style,
            strokes: mirror.strokes,
            stickers: mirror.stickers,
            texts: mirror.texts,
            // 같은 asset을 참조한다. 사진도 외부 디자인도 파일이 늘지 않는다.
            importedArtworks: mirror.importedArtworks
        )
        mirrors.insert(copy, at: index + 1)
        persist()
    }

    /// 받은 기본 템플릿도 지울 수 있다 — 상점에서 다시 무료로 받으면 된다.
    /// 마지막 거울을 지우면 목록이 비고, 기본 거울로 돌아간다.
    func delete(_ mirror: MyMirror) {
        mirrors.removeAll { $0.id == mirror.id }
        if currentID == mirror.id { currentID = Self.defaultMirror.id }
        deletePublishDraft(for: mirror.id)
        persist()
        // 다른 거울이 같은 사진 / 디자인을 쓰고 있으면 남는다. 아무도 안 쓰는 파일만 지운다.
        collectAssetGarbage()
    }
}
