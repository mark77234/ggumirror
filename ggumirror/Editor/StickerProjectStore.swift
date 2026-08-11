//
//  StickerProjectStore.swift
//  ggumirror
//
//  스티커 프로젝트를 기기에 적어둔다. 거울 저장 파일과 **섞지 않는다.**
//
//  Application Support/ggumirror/
//    sticker-projects.json           프로젝트 목록 (자체 schemaVersion 1)
//    sticker-projects-damaged.json   읽지 못한 파일을 치워두는 자리
//    UserStickerAssets/<id>.png      완성된 투명 스티커 PNG
//
//  거울의 `mirror-library.json`(schemaVersion 3)은 건드리지 않는다 —
//  스티커가 생겼다고 거울 저장 형식을 4로 올릴 이유가 없다.
//  PNG는 JSON에 base64로 넣지 않는다. 파일로 따로 둔다.
//
//  쓰기 방식은 `MirrorStore`와 같은 규칙을 따른다: 직렬 큐 + atomic write +
//  못 읽는 파일은 지우지 않고 격리 + 미래 버전 보호.
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 저장 형식

enum StickerSchema {
    /// 스티커 저장 파일 버전. 거울 schemaVersion과 **별개**다.
    static let current = 1
}

struct PersistedStickerProjects: Codable {
    var schemaVersion = StickerSchema.current
    var projects: [StickerProject] = []
}

/// 스티커 등록 준비 정보. **거울 등록 준비와 파일을 나눈다** — 서로의 형식을 건드리지 않는다.
struct PersistedStickerDrafts: Codable {
    var schemaVersion = StickerSchema.current
    var drafts: [StickerPublishDraft] = []
}

enum StickerStoreLoad: Equatable {
    case empty
    case loaded([StickerProject])
    /// 파일이 깨졌다. 원본은 옆으로 치워두고 빈 상태로 시작한다.
    case damaged
    /// 이 앱보다 새 버전이 적어둔 파일. 읽지도 덮어쓰지도 않는다.
    case tooNew(Int)
}

// MARK: - 저장소

final class StickerProjectStore: Sendable {
    static let live = StickerProjectStore(root: MirrorStore.defaultRoot)

    let root: URL
    /// 쓰기는 전부 이 줄 하나를 지난다.
    private let queue = DispatchQueue(label: "com.ggumirror.stickers")

    init(root: URL) {
        self.root = root
    }

    var projectsURL: URL { root.appending(path: "sticker-projects.json") }
    var damagedURL: URL { root.appending(path: "sticker-projects-damaged.json") }
    var assetsDirectory: URL { root.appending(path: "UserStickerAssets", directoryHint: .isDirectory) }
    var draftsURL: URL { root.appending(path: "sticker-publish-drafts.json") }

    func assetURL(_ id: UUID) -> URL {
        assetsDirectory.appending(path: "\(id.uuidString).png")
    }

    /// 테스트에서 쓰기가 끝날 때까지 기다린다.
    func flush() { queue.sync {} }

    // MARK: 목록

    func load() -> StickerStoreLoad {
        guard let data = try? Data(contentsOf: projectsURL) else { return .empty }

        struct VersionProbe: Decodable { let schemaVersion: Int }
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else {
            return quarantine(reason: "schemaVersion을 읽지 못했다")
        }
        guard probe.schemaVersion <= StickerSchema.current else { return .tooNew(probe.schemaVersion) }

        do {
            return .loaded(try JSONDecoder().decode(PersistedStickerProjects.self, from: data).projects)
        } catch {
            return quarantine(reason: "\(error)")
        }
    }

    /// 못 읽는 파일을 지우지 않고 옆으로 치운다. 앱은 빈 상태로 계속 쓸 수 있다.
    private func quarantine(reason: String) -> StickerStoreLoad {
        #if DEBUG
        print("[StickerProjectStore] 저장 파일을 읽지 못했다: \(reason)")
        #endif
        let fileManager = FileManager()
        try? fileManager.removeItem(at: damagedURL)
        try? fileManager.moveItem(at: projectsURL, to: damagedURL)
        return .damaged
    }

    func save(_ projects: [StickerProject]) {
        guard let data = try? JSONEncoder().encode(PersistedStickerProjects(projects: projects)) else {
            assertionFailure("스티커 목록을 encode하지 못했다")
            return
        }
        let url = projectsURL
        let directory = root
        queue.async {
            let fileManager = FileManager()
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                #if DEBUG
                print("[StickerProjectStore] 저장 실패: \(error)")
                #endif
            }
        }
    }

    // MARK: 등록 준비

    /// 못 읽으면 빈 목록으로 시작한다. 다시 쓸 수 있는 정보라 격리까지 하지 않는다.
    func loadDrafts() -> [StickerPublishDraft] {
        guard let data = try? Data(contentsOf: draftsURL) else { return [] }
        do {
            return try JSONDecoder().decode(PersistedStickerDrafts.self, from: data).drafts
        } catch {
            #if DEBUG
            print("[StickerProjectStore] 등록 준비 정보를 읽지 못했다: \(error)")
            #endif
            return []
        }
    }

    func saveDrafts(_ drafts: [StickerPublishDraft]) {
        guard let data = try? JSONEncoder().encode(PersistedStickerDrafts(drafts: drafts)) else { return }
        let url = draftsURL
        let directory = root
        queue.async {
            let fileManager = FileManager()
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: 완성 PNG

    func writeAsset(_ data: Data, id: UUID) {
        let url = assetURL(id)
        let directory = assetsDirectory
        queue.async {
            let fileManager = FileManager()
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    func readAsset(_ id: UUID) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(assetURL(id) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// 어떤 프로젝트도 참조하지 않는 PNG를 지운다.
    func collectAssetGarbage(keeping ids: Set<UUID>) {
        let directory = assetsDirectory
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

// MARK: - 라이브러리

/// 내가 만든 스티커 목록. **앱 전체에서 이것 하나가 진실이다.**
///
/// `@Observable`이라 저장하면 내 스티커 화면과 Mirror Editor picker가 즉시 갱신된다 —
/// 앱을 다시 켤 필요가 없다. 화면마다 배열을 따로 들고 있지 않는다.
@Observable
@MainActor
final class StickerLibrary {
    private(set) var projects: [StickerProject] = []

    private let store: StickerProjectStore?
    /// 저장 파일이 이 앱보다 새 버전이면 읽지도 덮어쓰지도 않는다.
    private let isReadOnly: Bool

    static let live = StickerLibrary(store: .live)

    init(store: StickerProjectStore? = nil) {
        self.store = store
        guard let store else {
            isReadOnly = false
            return
        }

        switch store.load() {
        case .empty, .damaged:
            isReadOnly = false
        case .tooNew(let version):
            isReadOnly = true
            #if DEBUG
            print("[StickerLibrary] 저장 파일 버전 \(version)이 앱(\(StickerSchema.current))보다 새롭다.")
            #endif
        case .loaded(let saved):
            isReadOnly = false
            projects = saved
        }

        guard !isReadOnly else { return }
        // 사라진 스티커의 준비 정보는 들고 있을 이유가 없다.
        drafts = store.loadDrafts().filter { draft in
            projects.contains { $0.id == draft.stickerProjectID }
        }
        store.collectAssetGarbage(keeping: Set(projects.compactMap(\.finalAssetID)))
    }

    func project(id: String) -> StickerProject? {
        projects.first { $0.id == id }
    }

    /// 새 스티커의 기본 이름.
    var suggestedName: String {
        StickerProjectPolicy.automaticName(existing: projects.map(\.name))
    }

    /// 저장. **무엇이 될지는 context가 정한다** — 편집은 같은 id를 갱신하고,
    /// 새로 만들기 / 복제만 새 id를 만든다.
    @discardableResult
    func save(
        _ design: MirrorDesign,
        name rawName: String,
        context: StickerSaveContext
    ) -> StickerProject? {
        guard !isReadOnly else { return nil }

        var project: StickerProject
        if let existingID = context.existingID, let index = projects.firstIndex(where: { $0.id == existingID }) {
            // 제자리 갱신: id · 이름 · 만든 날짜를 유지한다.
            project = projects[index]
            project.design = design
            project.updatedAt = Date()
            projects[index] = project
        } else {
            let name = StickerProjectPolicy.normalizedName(rawName) ?? suggestedName
            project = StickerProject(name: name, design: design)
            project.design.id = project.id
            project.design.name = name
            projects.append(project)
        }

        // 완성 PNG를 새로 굽는다. binary는 JSON이 아니라 파일로 나간다.
        if let store, let data = StickerRenderer.pngData(project.design) {
            let assetID = project.finalAssetID ?? UUID()
            project.finalAssetID = assetID
            store.writeAsset(data, id: assetID)
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index].finalAssetID = assetID
            }
        }

        persist()
        return projects.first { $0.id == project.id }
    }

    /// 복제. **새 id · 새 완성 PNG**를 만든다. 원본은 그대로 둔다.
    @discardableResult
    func duplicate(_ project: StickerProject) -> StickerProject? {
        guard !isReadOnly else { return nil }
        let name = StickerProjectPolicy.copyName(of: project.name, existing: projects.map(\.name))
        var design = project.design
        design.name = name
        // save가 새 id를 만들고 PNG도 새로 굽는다 — finalAssetID를 물려받지 않는다.
        return save(design, name: name, context: .createNew)
    }

    /// 목록에서 지운다.
    ///
    /// **이미 거울에 놓인 스티커는 지우지 않는다.** 거울은 배치 시점에 구운
    /// 불변 스냅샷(사진 asset)을 따로 갖고 있어서 이 목록과 수명이 분리돼 있다.
    func delete(_ project: StickerProject) {
        projects.removeAll { $0.id == project.id }
        drafts.removeAll { $0.stickerProjectID == project.id }
        persist()
        store?.saveDrafts(drafts)
        // 여기서 지우는 것은 **내 스티커 목록의 완성 PNG**뿐이다(UserStickerAssets).
        // 거울이 쓰는 스냅샷은 PhotoStickerAssets에 있고 거울 GC만 건드린다.
        store?.collectAssetGarbage(keeping: Set(projects.compactMap(\.finalAssetID)))
    }

    // MARK: - 거울에 놓기

    /// 거울에 놓을 **불변 스냅샷**을 만든다.
    ///
    /// 지금 완성 PNG를 사진 asset으로 **복사해** 둔다. 그래서:
    /// - 나중에 원본 스티커를 고쳐도 이미 놓인 거울은 그대로다
    /// - 목록에서 스티커를 지워도 거울은 깨지지 않는다
    ///
    /// 새 `StickerSource` case를 만들지 않았다 — `.photo`가 이미
    /// "id로 참조하는 불변 bitmap + 비율"이고, 거울 저장 형식 · GC · 렌더 · 크기 조절이
    /// 전부 그대로 동작한다(거울 schemaVersion 3 유지).
    func placementSnapshot(for project: StickerProject) -> StickerSource? {
        guard let image = finalImage(for: project) else { return nil }
        return PhotoStickerAssetStore.shared.register(image)
    }

    /// 완성 PNG. 파일에 있으면 읽고, 없으면 지금 다시 굽는다.
    func finalImage(for project: StickerProject) -> CGImage? {
        if let assetID = project.finalAssetID, let image = store?.readAsset(assetID) {
            return image
        }
        return StickerRenderer.render(project.design)
    }

    // MARK: - 등록 준비

    /// 상점에 올리기 전에 채워 둔 판매 정보. 실제 등록도 조각 차감도 없다.
    private(set) var drafts: [StickerPublishDraft] = []

    func draft(for projectID: String) -> StickerPublishDraft? {
        drafts.first { $0.stickerProjectID == projectID }
    }

    /// 스티커 하나에 준비 정보 하나. 같은 스티커면 덮어쓴다.
    func saveDraft(_ draft: StickerPublishDraft) {
        guard !isReadOnly else { return }
        var updated = draft
        updated.updatedAt = Date()
        if let index = drafts.firstIndex(where: { $0.stickerProjectID == draft.stickerProjectID }) {
            updated.id = drafts[index].id
            drafts[index] = updated
        } else {
            drafts.append(updated)
        }
        store?.saveDrafts(drafts)
    }

    private func persist() {
        guard !isReadOnly else { return }
        store?.save(projects)
    }
}
