//
//  SnapshotPackaging.swift
//  ggumirror
//
//  상점에 올릴 꾸러미 하나를 만든다.
//
//  **새 template schema를 만들지 않는다.** manifest는 `MyMirror` / `StickerProject`의
//  기존 `Codable` 결과 그대로다. 모델에 파일 경로가 없고 이미지는 assetID(UUID)로만
//  참조되므로, 그것을 그대로 담으면 다른 기기에서 그대로 열린다.
//
//  Master Canvas(1080 × 2340)와 insets는 client **상수**라 꾸러미에 담지 않는다 —
//  담으면 두 곳이 어긋날 수 있다.
//
//  가장 중요한 규칙:
//
//      manifest가 참조하는 assetID  ==  업로드하는 assetID
//
//  정확히 같아야 한다. 빠지면 산 사람 기기에서 이미지가 조용히 비고,
//  남으면 아무도 쓰지 않는 그림을 상품에 끼워 넣은 것이다.
//  서버도 같은 규칙으로 거절하지만(B-7F.1) **보내기 전에 앱이 먼저 막는다.**
//

import CoreGraphics
import Foundation

// MARK: - 실패

nonisolated enum SnapshotPackagingFailure: Error, Equatable {
    /// manifest가 참조하는 이미지가 이 기기에 없다.
    /// **반쪽 꾸러미를 서버에 보내지 않는다.**
    case missingAsset(UUID)
    /// 대표 이미지를 만들지 못했다.
    case previewFailed
    /// manifest를 적지 못했다. 정상 앱에서는 일어나지 않는다.
    case encodingFailed

    var message: String {
        switch self {
        case .missingAsset: "이미지를 찾지 못해 상점에 올릴 수 없어요."
        case .previewFailed: "대표 이미지를 만들지 못했어요."
        case .encodingFailed: "상점에 올릴 준비를 마치지 못했어요."
        }
    }
}

// MARK: - 꾸러미

/// 서버로 나갈 세 부분. 검증을 통과한 뒤에만 만들어진다.
nonisolated struct SnapshotPackage: Equatable {
    /// client Codable JSON 그대로.
    let manifest: Data
    /// 상점 카드에 보일 대표 이미지(PNG).
    let preview: Data
    /// manifest가 참조하는 이미지 전부. assetID → PNG bytes.
    let assets: [UUID: Data]

    /// `mirror` 또는 `sticker`. 서버 `contentType`과 같은 문자열이다.
    let contentType: String
}

// MARK: - 참조 추출

/// manifest가 참조하는 local asset을 모은다.
///
/// **client 코드에서 확인한 위치만** 본다. `stickers[].id` 같은 오브젝트 자기
/// 식별자는 asset이 아니다 — 둘 다 UUID라서 구분하지 않으면 없는 PNG를 요구하게 된다.
nonisolated enum SnapshotAssetReferences {

    /// 거울이 참조하는 이미지. 종류별로 나눠 준다 — 저장 폴더가 다르다.
    ///
    /// - `photoSticker`: `stickers[].source.assetID` (`kind == .photo`일 때만)
    /// - `importedArtwork`: `importedArtworks[].assetID`
    static func mirror(_ mirror: MyMirror) -> (photos: Set<UUID>, artworks: Set<UUID>) {
        // 이미 있는 하나뿐인 authority를 쓴다. GC도 이것을 본다.
        (mirror.assetIDs(.photoSticker), mirror.assetIDs(.importedArtwork))
    }

    /// 스티커가 참조하는 이미지.
    ///
    /// - `finalAsset`: `finalAssetID` — 완성 PNG(`UserStickerAssets`). **optional이다.**
    ///   없으면 없는 것이고 가짜로 만들지 않는다.
    /// - `photoSticker` · `importedArtwork`: `design` 안의 같은 위치
    ///
    /// `generationIDs`는 AI 생성 기록 id이고 **파일이 아니다** — 올리지 않는다.
    static func sticker(
        _ project: StickerProject
    ) -> (finalAsset: UUID?, photos: Set<UUID>, artworks: Set<UUID>) {
        (
            project.finalAssetID,
            project.photoAssetIDs,
            Set(project.design.importedArtworks.map(\.assetID))
        )
    }
}

// MARK: - 만들기

/// 꾸러미를 만든다. 이미지 bytes는 **기존 보관소**에서 읽는다 —
/// 새 저장 체계를 만들지 않는다.
@MainActor
enum SnapshotPackager {

    /// 거울 하나를 상점 꾸러미로.
    ///
    /// 대표 이미지는 기존 `OwnContentExport.mirrorPNG`(1080 × 2340)를 쓴다 —
    /// 사용자가 실제로 보게 될 그림과 같은 렌더러여야 카드가 거짓말을 하지 않는다.
    static func package(
        _ mirror: MyMirror,
        store: MirrorStore? = nil,
        photos: PhotoStickerAssetStore = .shared,
        artworks: ImportedArtworkAssetStore = .shared
    ) throws -> SnapshotPackage {
        let manifest: Data
        do {
            manifest = try JSONEncoder.marketplace.encode(mirror)
        } catch {
            throw SnapshotPackagingFailure.encodingFailed
        }

        let references = SnapshotAssetReferences.mirror(mirror)
        var assets: [UUID: Data] = [:]
        for id in references.photos.sorted(by: { $0.uuidString < $1.uuidString }) {
            assets[id] = try png(id, kind: .photoSticker, store: store) {
                photos.image(for: id)
            }
        }
        for id in references.artworks.sorted(by: { $0.uuidString < $1.uuidString }) {
            assets[id] = try png(id, kind: .importedArtwork, store: store) {
                artworks.image(for: id)
            }
        }

        let preview: Data
        do {
            preview = try OwnContentExport.mirrorPNG(mirror)
        } catch {
            throw SnapshotPackagingFailure.previewFailed
        }

        return try checked(
            SnapshotPackage(
                manifest: manifest, preview: preview, assets: assets, contentType: "mirror"
            ),
            referenced: references.photos.union(references.artworks)
        )
    }

    /// 스티커 하나를 상점 꾸러미로.
    ///
    /// 대표 이미지는 기존 `OwnContentExport.stickerPNG`(투명 PNG)를 쓴다.
    static func package(
        _ project: StickerProject,
        store: MirrorStore? = nil,
        stickerStore: StickerProjectStore? = nil,
        photos: PhotoStickerAssetStore = .shared,
        artworks: ImportedArtworkAssetStore = .shared
    ) throws -> SnapshotPackage {
        let manifest: Data
        do {
            manifest = try JSONEncoder.marketplace.encode(project)
        } catch {
            throw SnapshotPackagingFailure.encodingFailed
        }

        let references = SnapshotAssetReferences.sticker(project)
        var assets: [UUID: Data] = [:]
        if let finalAssetID = references.finalAsset {
            guard let data = stickerAssetPNG(finalAssetID, store: stickerStore) else {
                throw SnapshotPackagingFailure.missingAsset(finalAssetID)
            }
            assets[finalAssetID] = data
        }
        for id in references.photos.sorted(by: { $0.uuidString < $1.uuidString }) {
            assets[id] = try png(id, kind: .photoSticker, store: store) {
                photos.image(for: id)
            }
        }
        for id in references.artworks.sorted(by: { $0.uuidString < $1.uuidString }) {
            assets[id] = try png(id, kind: .importedArtwork, store: store) {
                artworks.image(for: id)
            }
        }

        let preview: Data
        do {
            preview = try OwnContentExport.stickerPNG(project)
        } catch {
            throw SnapshotPackagingFailure.previewFailed
        }

        var referenced = references.photos.union(references.artworks)
        if let finalAssetID = references.finalAsset { referenced.insert(finalAssetID) }

        return try checked(
            SnapshotPackage(
                manifest: manifest, preview: preview, assets: assets, contentType: "sticker"
            ),
            referenced: referenced
        )
    }

    // MARK: - 내부

    /// **보내기 전 마지막 확인.** 서버가 같은 규칙으로 거절하지만, 앱이 먼저 막으면
    /// 사용자는 실패한 업로드를 기다리지 않는다.
    private static func checked(
        _ package: SnapshotPackage, referenced: Set<UUID>
    ) throws -> SnapshotPackage {
        // 빠진 것.
        if let missing = referenced.subtracting(package.assets.keys).first {
            throw SnapshotPackagingFailure.missingAsset(missing)
        }
        // 남는 것. `assets`는 참조에서만 채우므로 정상 경로에서는 일어나지 않지만,
        // 규칙을 코드로 남겨 두면 나중에 참조 위치가 늘어날 때 조용히 어긋나지 않는다.
        if let extra = Set(package.assets.keys).subtracting(referenced).first {
            throw SnapshotPackagingFailure.missingAsset(extra)
        }
        return package
    }

    /// 이미지 bytes를 얻는다. **디스크 파일을 그대로 읽는 쪽을 먼저 본다** —
    /// 다시 encode하면 산 사람이 받는 바이트가 원본과 달라진다.
    private static func png(
        _ id: UUID,
        kind: MirrorAssetKind,
        store: MirrorStore?,
        fallback: () -> CGImage?
    ) throws -> Data {
        if let store, let data = try? Data(contentsOf: store.assetURL(id, kind: kind)) {
            return data
        }
        // 디스크에 없다 — 메모리에만 있는 번들 템플릿 그림이 이 경로로 온다.
        guard let image = fallback(), let data = encoded(image, store: store) else {
            throw SnapshotPackagingFailure.missingAsset(id)
        }
        return data
    }

    /// 완성 스티커 PNG(`UserStickerAssets`)는 별도 보관소에 있다.
    private static func stickerAssetPNG(_ id: UUID, store: StickerProjectStore?) -> Data? {
        guard let store else { return nil }
        return try? Data(contentsOf: store.assetURL(id))
    }

    private static func encoded(_ image: CGImage, store: MirrorStore?) -> Data? {
        if let store { return store.encodePNG(image) }
        // 저장소가 없는 경우(테스트 · 미리보기)에도 같은 규칙으로 굽는다.
        return MirrorStore.encodePNG(image)
    }
}

// MARK: - JSON

nonisolated extension JSONEncoder {
    /// manifest용. **서버는 이 바이트를 그대로 보관하고 checksum을 낸다.**
    ///
    /// 날짜는 서버 규칙과 같은 ISO8601이다(`StickerProject.createdAt`이 쓴다).
    /// key를 정렬해 같은 문서가 항상 같은 바이트로 나가게 한다 — 그래야 checksum이
    /// 같은 내용에 대해 흔들리지 않는다.
    static var marketplace: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

nonisolated extension JSONDecoder {
    /// 내려받은 manifest용. 서버는 우리가 보낸 바이트를 그대로 돌려준다.
    static var marketplace: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let raw = try container.singleValueContainer().decode(String.self)
            guard let date = BackendDate.parse(raw) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: container.codingPath, debugDescription: "bad date")
                )
            }
            return date
        }
        return decoder
    }
}
