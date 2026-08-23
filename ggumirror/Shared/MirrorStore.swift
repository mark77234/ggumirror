//
//  MirrorStore.swift
//  ggumirror
//
//  내 거울을 기기에 적어두는 곳. 서버도 클라우드 동기화도 없다.
//
//  Application Support/ggumirror/
//    mirror-library.json             — 거울 목록 + 현재 거울 (JSON 한 장)
//    publish-drafts.json             — 상점 등록 준비 중인 판매 정보
//    PhotoStickerAssets/<id>.png     — 배경 지운 사진 (투명도 유지)
//    ImportedArtworkAssets/<id>.png  — 외부 그림 앱에서 가져온 전체 캔버스 디자인
//
//  사진 binary는 JSON에 넣지 않는다. 거울은 assetID만 참조하므로
//  거울을 복제해도 같은 파일 하나를 같이 본다.
//
//  Caches가 아니라 Application Support를 쓴다 — 사용자가 만든 콘텐츠라
//  시스템이 마음대로 지우면 안 된다.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - 저장 형식

enum MirrorSchema {
    /// 저장 파일 버전. 형식을 바꾸면 올리고 migrate에 case를 추가한다.
    /// 1 → 2: 거울에 `importedArtworks`가 생겼다.
    /// 2 → 3: 스티커에 `doodle` 종류가 생겼다. 예전 파일은 `builtIn`뿐이라 그대로 읽힌다.
    static let current = 3
}

/// 이미지 파일이 사는 폴더. 종류마다 따로 두고 정리도 각자 한다.
enum MirrorAssetKind: String, CaseIterable {
    case photoSticker = "PhotoStickerAssets"
    case importedArtwork = "ImportedArtworkAssets"
}

struct PersistedLibrary: Codable {
    var schemaVersion: Int = MirrorSchema.current
    var currentMirrorID: String
    var mirrors: [MyMirror]
    /// 조각으로 산 추가 보관 슬롯. 거울 목록에서 다시 계산할 수 없는 유일한 값이라 같이 적는다.
    var purchasedCreatedSlots: Int = 0

    /// 지금 어떤 거울이든 참조하고 있는 asset 전부. 종류별로 따로 센다.
    func referencedAssetIDs(_ kind: MirrorAssetKind) -> Set<UUID> {
        mirrors.reduce(into: Set<UUID>()) { $0.formUnion($1.assetIDs(kind)) }
    }
}

/// 읽기 결과. 실패했다고 사용자 데이터를 조용히 덮어쓰지 않는다.
enum MirrorStoreLoad: Equatable {
    /// 저장 파일이 없다 — 정상적인 최초 실행.
    case empty
    case loaded(PersistedLibrary)
    /// 파일이 깨졌다. 원본은 옆으로 치워두고 새로 시작한다.
    case damaged
    /// 이 앱보다 새 버전이 적어둔 파일. 읽지도 덮어쓰지도 않는다.
    case tooNew(Int)

    static func == (lhs: MirrorStoreLoad, rhs: MirrorStoreLoad) -> Bool {
        switch (lhs, rhs) {
        case (.empty, .empty), (.damaged, .damaged): true
        case (.tooNew(let a), .tooNew(let b)): a == b
        case (.loaded(let a), .loaded(let b)): a.mirrors == b.mirrors && a.currentMirrorID == b.currentMirrorID
        default: false
        }
    }
}

/// 등록 준비 중인 판매 정보. 거울 목록과 파일을 나눠서 서로의 형식을 건드리지 않는다.
struct PersistedDrafts: Codable {
    var schemaVersion = 1
    var drafts: [MirrorPublishDraft] = []
}

// MARK: - 저장소

final class MirrorStore: Sendable {
    /// 앱이 실제로 쓰는 저장소. 테스트는 임시 폴더로 자기 것을 만든다.
    static let live = MirrorStore(root: defaultRoot)

    let root: URL
    /// 쓰기는 전부 이 줄 하나를 지난다 — 나중 저장이 먼저 저장을 앞지르지 않는다.
    private let queue = DispatchQueue(label: "com.ggumirror.persistence")

    init(root: URL) {
        self.root = root
    }

    /// 예전(계정 구분 없던) 저장 위치. **여기 있는 파일을 지우지 않는다** —
    /// 로그인한 사용자에게 한 번 넘겨준다(`claimLegacy`).
    static var legacyRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "ggumirror", directoryHint: .isDirectory)
    }

    /// 계정별 서랍이 사는 곳.
    static var accountsRoot: URL {
        legacyRoot.appending(path: "accounts", directoryHint: .isDirectory)
    }

    /// 이 계정의 서랍. 로그아웃 상태는 `guest`라 **비어 있는 것이 정상**이다.
    static func root(for owner: MirrorLibraryOwner) -> URL {
        accountsRoot.appending(path: owner.directoryName, directoryHint: .isDirectory)
    }

    static func store(for owner: MirrorLibraryOwner) -> MirrorStore {
        MirrorStore(root: root(for: owner))
    }

    /// 예전 이름. 계정 구분 이전 코드가 가리키던 곳이다.
    static var defaultRoot: URL { legacyRoot }

    // MARK: - 예전 데이터 넘겨주기 (한 번만)

    /// 계정 구분이 없던 시절의 파일을 **이 사용자 서랍으로 옮긴다.**
    ///
    /// 규칙은 셋뿐이다:
    /// - 로그인한 사용자가 분명할 때만 옮긴다. guest에게 주지 않는다
    /// - 그 사용자 서랍에 **이미 무언가 있으면 건드리지 않는다** — 덮어쓰지 않는다
    /// - 한 번 옮기면 표시를 남겨 다시 하지 않는다
    ///
    /// 어느 쪽으로도 확신이 없으면 **예전 파일을 그 자리에 그대로 둔다.**
    /// 지우지도, 아무에게나 주지도 않는다.
    /// - Returns: 이번 호출이 실제로 옮겼는가.
    @discardableResult
    static func claimLegacy(
        for owner: MirrorLibraryOwner,
        legacyRoot: URL = MirrorStore.legacyRoot,
        fileManager: FileManager = .default
    ) -> Bool {
        guard case .user = owner else { return false }
        let marker = legacyRoot.appending(path: "legacy-claimed.json")
        guard !fileManager.fileExists(atPath: marker.path()) else { return false }

        // 거울이든 스티커든 예전 파일이 하나라도 있으면 넘겨준다.
        let legacyFiles = ["mirror-library.json", "sticker-projects.json"]
        guard legacyFiles.contains(where: {
            fileManager.fileExists(atPath: legacyRoot.appending(path: $0).path())
        }) else { return false }

        let destination = legacyRoot
            .appending(path: "accounts", directoryHint: .isDirectory)
            .appending(path: owner.directoryName, directoryHint: .isDirectory)
        // 이미 자기 서랍이 있으면 손대지 않는다. 예전 파일은 주인 없는 채로 남는다.
        if legacyFiles.contains(where: {
            fileManager.fileExists(atPath: destination.appending(path: $0).path())
        }) { return false }

        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            // 스티커도 **같은 서랍**으로 간다. 계정 privacy는 거울과 스티커를 구분하지 않는다.
            for name in [
                "mirror-library.json", "publish-drafts.json",
                "sticker-projects.json", "sticker-publish-drafts.json", "UserStickerAssets",
            ] + MirrorAssetKind.allCases.map(\.rawValue) {
                let from = legacyRoot.appending(path: name)
                guard fileManager.fileExists(atPath: from.path()) else { continue }
                try fileManager.moveItem(at: from, to: destination.appending(path: name))
            }
            // 옮긴 뒤에 표시한다 — 중간에 실패하면 다음 실행이 다시 시도한다.
            try Data("{\"claimed\":true}".utf8).write(to: marker, options: .atomic)
            return true
        } catch {
            // 실패해도 **아무것도 지우지 않았다.** 다음 실행이 다시 시도한다.
            return false
        }
    }

    var libraryURL: URL { root.appending(path: "mirror-library.json") }
    var draftsURL: URL { root.appending(path: "publish-drafts.json") }
    var damagedLibraryURL: URL { root.appending(path: "mirror-library-damaged.json") }

    func assetsDirectory(_ kind: MirrorAssetKind) -> URL {
        root.appending(path: kind.rawValue, directoryHint: .isDirectory)
    }

    /// 테스트에서 쓰기가 끝날 때까지 기다린다.
    func flush() { queue.sync {} }

    // MARK: 거울 목록

    func load() -> MirrorStoreLoad {
        guard let data = try? Data(contentsOf: libraryURL) else { return .empty }

        // 버전을 먼저 본다 — 미래 버전 파일을 억지로 읽어서 망가뜨리지 않는다.
        struct VersionProbe: Decodable { let schemaVersion: Int }
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else {
            return quarantine(reason: "schemaVersion을 읽지 못했다")
        }
        guard probe.schemaVersion <= MirrorSchema.current else { return .tooNew(probe.schemaVersion) }

        do {
            return .loaded(try migrate(data, from: probe.schemaVersion))
        } catch {
            return quarantine(reason: "\(error)")
        }
    }

    /// v1은 `importedArtworks` 키가 없을 뿐이라 같은 decoder가 빈 배열로 읽어 준다.
    /// (`MyMirror`의 decoder가 없는 키를 기본값으로 채운다.)
    /// 다음 저장 때 v2 형식으로 다시 적힌다. 형식이 실제로 갈라지면 여기 case를 나눈다.
    private func migrate(_ data: Data, from version: Int) throws -> PersistedLibrary {
        switch version {
        case 1, 2, 3: try JSONDecoder().decode(PersistedLibrary.self, from: data)
        default: throw CocoaError(.fileReadCorruptFile)
        }
    }

    /// 못 읽는 파일을 지우지 않고 옆으로 치운다. 앱은 빈 상태로 계속 쓸 수 있다.
    private func quarantine(reason: String) -> MirrorStoreLoad {
        #if DEBUG
        print("[MirrorStore] 저장 파일을 읽지 못했다: \(reason)")
        #endif
        let fileManager = FileManager()
        try? fileManager.removeItem(at: damagedLibraryURL)
        try? fileManager.moveItem(at: libraryURL, to: damagedLibraryURL)
        return .damaged
    }

    /// encode는 호출한 쪽(MainActor)에서, 디스크 쓰기는 뒤에서. 쓰기 중 종료돼도 파일이 반쪽 나지 않는다.
    func save(_ library: PersistedLibrary) {
        var payload = library
        payload.schemaVersion = MirrorSchema.current
        guard let data = try? JSONEncoder().encode(payload) else {
            assertionFailure("거울 목록을 encode하지 못했다")
            return
        }
        let url = libraryURL
        let directory = root
        queue.async {
            let fileManager = FileManager()
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                #if DEBUG
                print("[MirrorStore] 저장 실패: \(error)")
                #endif
            }
        }
    }

    // MARK: 등록 준비

    /// 못 읽으면 빈 목록으로 시작한다. 거울 데이터와 달리 다시 쓸 수 있는 정보라 격리까지 하지 않는다.
    func loadDrafts() -> [MirrorPublishDraft] {
        guard let data = try? Data(contentsOf: draftsURL) else { return [] }
        do {
            return try JSONDecoder().decode(PersistedDrafts.self, from: data).drafts
        } catch {
            #if DEBUG
            print("[MirrorStore] 등록 준비 정보를 읽지 못했다: \(error)")
            #endif
            return []
        }
    }

    func saveDrafts(_ drafts: [MirrorPublishDraft]) {
        guard let data = try? JSONEncoder().encode(PersistedDrafts(drafts: drafts)) else { return }
        let url = draftsURL
        let directory = root
        queue.async {
            let fileManager = FileManager()
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: 사진 asset

    func assetURL(_ id: UUID, kind: MirrorAssetKind = .photoSticker) -> URL {
        assetsDirectory(kind).appending(path: "\(id.uuidString).png")
    }

    /// 투명도를 유지해야 하므로 항상 PNG다. JPEG는 쓰지 않는다.
    func encodePNG(_ image: CGImage) -> Data? { Self.encodePNG(image) }

    /// 저장소 없이도 같은 규칙으로 굽는다. instance 상태를 쓰지 않으므로
    /// **encoder를 하나 더 만들지 않고** 이것을 공유한다.
    static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    func writeAsset(_ data: Data, id: UUID, kind: MirrorAssetKind = .photoSticker) {
        let url = assetURL(id, kind: kind)
        let directory = assetsDirectory(kind)
        queue.async {
            let fileManager = FileManager()
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    func readAsset(_ id: UUID, kind: MirrorAssetKind = .photoSticker) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(assetURL(id, kind: kind) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// 어떤 거울도 참조하지 않는 사진 파일을 지운다.
    /// Editor 작업 중에는 부르지 않는다 — Undo로 되살릴 스티커의 사진을 미리 지우면 안 된다.
    func collectAssetGarbage(keeping ids: Set<UUID>, kind: MirrorAssetKind = .photoSticker) {
        let directory = assetsDirectory(kind)
        queue.async {
            let fileManager = FileManager()
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ) else { return }
            for file in files where file.pathExtension == "png" {
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                      !ids.contains(id)
                else { continue }
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
