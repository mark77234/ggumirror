//
//  ImportedArtworkModels.swift
//  ggumirror
//
//  외부 그림 앱에서 만들어 온 거울 디자인 한 장.
//
//  사진 스티커와 완전히 다른 물건이다:
//    사진 스티커 — 옮기고 키우고 돌리는 작은 오브젝트, 배경 제거를 거친다.
//    외부 디자인 — Master Canvas(1080 × 2340) 전체에 딱 맞는 **고정** 레이어.
//
//  사용자가 작업 가이드 기준으로 그린 위치를 앱이 다시 옮기지 않는다.
//  그래서 center / frame / rotation / scale을 아예 저장하지 않는다.
//

import CoreGraphics
import Foundation

// MARK: - Object

struct ImportedArtworkObject: Identifiable, Hashable {
    var id = UUID()
    /// 이미지 파일 참조. binary는 ImportedArtworkAssetStore에만 있다.
    var assetID: UUID
    var opacity: Double = 1
    var zIndex: Int = 0

    /// 언제나 Master Canvas 전체. 이 값은 바뀌지 않는다.
    static let frame = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    static let opacityRange: ClosedRange<Double> = 0.1...1
}

// MARK: - 보관소

/// 외부 디자인 PNG 보관. 메모리 캐시 + 디스크.
/// PhotoStickerAssetStore와 같은 규칙이지만 폴더가 다르고 배경 제거를 하지 않는다.
/// 렌더러가 그리는 도중 파일을 읽지 않도록 앱 시작 때 `preload`로 올려둔다.
@MainActor
final class ImportedArtworkAssetStore {
    static let shared = ImportedArtworkAssetStore()

    private var assets: [UUID: CGImage] = [:]
    /// 디스크에도 없던 것. 매 프레임 같은 파일을 다시 찾지 않게 한다.
    private var missing: Set<UUID> = []
    private var storage: MirrorStore?

    init(storage: MirrorStore? = nil) {
        self.storage = storage
    }

    func attach(_ store: MirrorStore) {
        storage = store
        missing.removeAll()
    }

    /// 보관하고 참조용 id를 돌려준다.
    @discardableResult
    func register(_ image: CGImage) -> UUID {
        let id = UUID()
        assets[id] = image
        missing.remove(id)
        if let storage, let data = storage.encodePNG(image) {
            storage.writeAsset(data, id: id, kind: .importedArtwork)
        }
        return id
    }

    func image(for id: UUID) -> CGImage? {
        if let cached = assets[id] { return cached }
        guard let storage, !missing.contains(id) else { return nil }
        guard let loaded = storage.readAsset(id, kind: .importedArtwork) else {
            missing.insert(id)
            return nil
        }
        assets[id] = loaded
        return loaded
    }

    func preload(_ ids: Set<UUID>) {
        for id in ids { _ = image(for: id) }
    }

    var count: Int { assets.count }
}
