//
//  MarketplaceImport.swift
//  ggumirror
//
//  산 템플릿을 내 것으로 가져온다.
//
//  manifest는 서버가 우리가 올린 바이트를 그대로 돌려준 것이라 **기존 Codable로 그대로
//  읽는다** — 별도 Marketplace 모델을 만들지 않는다.
//
//  경로를 저장하지 않는다. 서버 object key · bucket · URL은 모델에 들어가지 않고,
//  이미지는 기존 보관소(`PhotoStickerAssets` · `ImportedArtworkAssets` ·
//  `UserStickerAssets`)에 **manifest가 참조하는 그 assetID로** 내려간다.
//  그래야 manifest를 고치지 않고도 참조가 맞는다.
//
//  이미 같은 assetID가 로컬에 있으면 **덮어쓰지 않는다.** UUID가 겹치는 일은
//  사실상 없지만(자기 상품을 다시 받는 경우가 유일하다), 겹쳤을 때 남의 바이트로
//  내 거울의 그림을 갈아치우는 것이 최악이다. 서버 쪽 create-only와 같은 방향이다.
//

import CoreGraphics
import Foundation

// MARK: - 실패

nonisolated enum MarketplaceImportFailure: Error, Equatable {
    /// 서버 manifest를 우리 모델로 읽지 못했다.
    case unreadableManifest
    /// 참조하는 이미지를 받지 못했다. **반쪽 상태로 저장하지 않는다.**
    case assetDownloadFailed(UUID)
    /// 저장소가 붙지 않았다. 정상 앱에서는 일어나지 않는다.
    case noStorage
    /// 서버가 거절했다.
    case remote(MarketplaceFailure)

    var message: String {
        switch self {
        case .unreadableManifest: "받은 템플릿을 읽지 못했어요."
        case .assetDownloadFailed: "템플릿 이미지를 받지 못했어요."
        case .noStorage: "저장 공간을 준비하지 못했어요."
        case .remote(let failure): failure.message
        }
    }
}

// MARK: - 가져오기

/// 산 템플릿을 내 거울 / 내 스티커로 옮긴다.
@MainActor
final class MarketplaceImporter {
    private let backend: any MarketplaceBackend

    init(backend: any MarketplaceBackend = BackendClient()) {
        self.backend = backend
    }

    /// 거울 템플릿을 받아 내 거울에 담는다.
    ///
    /// - `listingID`를 지역 거울 id로 쓴다. manifest 안의 id는 판매자 기기의 것이라
    ///   그대로 쓰면 내가 이미 가진 거울과 부딪힐 수 있다.
    /// - `origin`은 `.purchased`다 — 상점에서 받은 것을 되팔 수 없게 하는 기존 정책
    ///   (`MirrorPublishPolicy.isEligible`)이 그대로 걸린다.
    @discardableResult
    func importMirror(
        listingID: String,
        title: String,
        session: ServerSession?,
        library: MirrorLibrary,
        store: MirrorStore?,
        photos: PhotoStickerAssetStore = .shared,
        artworks: ImportedArtworkAssetStore = .shared
    ) async throws -> MyMirror {
        guard let token = session?.accessToken else {
            throw MarketplaceImportFailure.remote(.notSignedIn)
        }
        guard let store else { throw MarketplaceImportFailure.noStorage }

        let manifest = try await download(listingID: listingID, accessToken: token)
        let decoded: MyMirror
        do {
            decoded = try JSONDecoder.marketplace.decode(MyMirror.self, from: manifest)
        } catch {
            throw MarketplaceImportFailure.unreadableManifest
        }

        // manifest가 참조하는 것과 정확히 같은 집합을 받는다.
        let references = SnapshotAssetReferences.mirror(decoded)
        try await downloadAssets(
            references.photos, listingID: listingID, kind: .photoSticker,
            accessToken: token, store: store
        )
        try await downloadAssets(
            references.artworks, listingID: listingID, kind: .importedArtwork,
            accessToken: token, store: store
        )
        // 파일이 준비된 뒤 캐시를 채운다 — 렌더러가 그리는 도중 파일을 찾지 않게 한다.
        photos.preload(references.photos)
        artworks.preload(references.artworks)

        let mirror = MyMirror(
            id: listingID,
            name: title.isEmpty ? decoded.name : title,
            origin: .purchased,
            style: decoded.style,
            strokes: decoded.strokes,
            stickers: decoded.stickers,
            texts: decoded.texts,
            importedArtworks: decoded.importedArtworks
        )
        library.adopt(mirror)
        return mirror
    }

    /// 스티커 템플릿을 받아 내 스티커에 담는다.
    ///
    /// `finalAssetID`는 optional이다 — 없으면 없는 것이고 만들어내지 않는다.
    @discardableResult
    func importSticker(
        listingID: String,
        title: String,
        session: ServerSession?,
        library: StickerLibrary,
        stickerStore: StickerProjectStore?,
        store: MirrorStore?,
        photos: PhotoStickerAssetStore = .shared,
        artworks: ImportedArtworkAssetStore = .shared
    ) async throws -> StickerProject {
        guard let token = session?.accessToken else {
            throw MarketplaceImportFailure.remote(.notSignedIn)
        }
        guard let stickerStore else { throw MarketplaceImportFailure.noStorage }

        let manifest = try await download(listingID: listingID, accessToken: token)
        let decoded: StickerProject
        do {
            decoded = try JSONDecoder.marketplace.decode(StickerProject.self, from: manifest)
        } catch {
            throw MarketplaceImportFailure.unreadableManifest
        }

        let references = SnapshotAssetReferences.sticker(decoded)
        if let finalAssetID = references.finalAsset {
            // 이미 있으면 덮지 않는다.
            if stickerStore.readAsset(finalAssetID) == nil {
                let data = try await asset(
                    finalAssetID, listingID: listingID, accessToken: token
                )
                stickerStore.writeAsset(data, id: finalAssetID)
                stickerStore.flush()
            }
        }
        if let store {
            try await downloadAssets(
                references.photos, listingID: listingID, kind: .photoSticker,
                accessToken: token, store: store
            )
            try await downloadAssets(
                references.artworks, listingID: listingID, kind: .importedArtwork,
                accessToken: token, store: store
            )
            photos.preload(references.photos)
            artworks.preload(references.artworks)
        }

        let project = StickerProject(
            id: listingID,
            name: title.isEmpty ? decoded.name : title,
            createdAt: decoded.createdAt,
            updatedAt: decoded.updatedAt,
            design: decoded.design,
            finalAssetID: references.finalAsset,
            // **manifest의 값을 그대로 보존한다.** `StickerProjectOrigin`에는 `.purchased`가
            // 없고, 지속되는 enum에 case를 더하면 구버전이 그 파일을 못 읽는다
            // (`decodeIfPresent`는 모르는 raw value에서 throw한다).
            //
            // 여기서 `.made`로 덮으면 AI로 만든 스티커의 출처 표시가 사라진다 —
            // 그건 조용히 정보를 잃는 쪽이라 하지 않는다. "산 것"이라는 표시가 필요하면
            // 별도 phase에서 schema와 함께 다룬다.
            origin: decoded.origin,
            // AI 생성 기록 id는 판매자 기기의 것이다 — 내 기록으로 옮기지 않는다.
            generationIDs: []
        )
        library.adopt(project)
        return project
    }

    // MARK: - 내부

    private func download(listingID: String, accessToken: String) async throws -> Data {
        do {
            return try await backend.templateManifest(
                listingID: listingID, accessToken: accessToken
            )
        } catch let failure as MarketplaceFailure {
            throw MarketplaceImportFailure.remote(failure)
        } catch {
            throw MarketplaceImportFailure.remote(.network)
        }
    }

    private func asset(
        _ id: UUID, listingID: String, accessToken: String
    ) async throws -> Data {
        do {
            return try await backend.templateAsset(
                listingID: listingID, assetID: id, accessToken: accessToken
            )
        } catch {
            throw MarketplaceImportFailure.assetDownloadFailed(id)
        }
    }

    /// 없는 것만 받아서 그 assetID로 내려놓는다. **있는 것은 그대로 둔다.**
    private func downloadAssets(
        _ ids: Set<UUID>,
        listingID: String,
        kind: MirrorAssetKind,
        accessToken: String,
        store: MirrorStore
    ) async throws {
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard store.readAsset(id, kind: kind) == nil else { continue }
            let data = try await asset(id, listingID: listingID, accessToken: accessToken)
            store.writeAsset(data, id: id, kind: kind)
        }
        // 쓰기는 비동기 queue를 지난다. 렌더 전에 파일이 있어야 한다.
        store.flush()
    }
}
