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

/// 내가 만든 스티커 목록. 앱 전체에서 이것 하나가 진실이다.
///
/// 이번 Phase에서는 Creator가 저장하는 것까지다 —
/// My Stickers 화면 · Mirror picker 연동 · 상점은 V-5B다.
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

    func delete(_ project: StickerProject) {
        projects.removeAll { $0.id == project.id }
        persist()
        store?.collectAssetGarbage(keeping: Set(projects.compactMap(\.finalAssetID)))
    }

    private func persist() {
        guard !isReadOnly else { return }
        store?.save(projects)
    }
}
