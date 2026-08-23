//
//  PublishDraftTests.swift
//  ggumirrorTests
//
//  상점에 올리기 **전** 단계 — 판매 정보 작성과 검사.
//  실제 등록 / 조각 차감 / 상점 노출은 아직 없다. 그 "없음"도 여기서 지킨다.
//

import Testing
import SwiftUI
import UIKit
@testable import ggumirror

@MainActor
struct PublishDraftTests {

    // MARK: - 도구

    private func withStore(_ body: (MirrorStore) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-publish-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = MirrorStore(root: root)
        defer {
            store.flush()
            try? FileManager().removeItem(at: root)
        }
        try body(store)
    }

    private func library(_ store: MirrorStore) -> MirrorLibrary {
        MirrorLibrary(store: store, assets: PhotoStickerAssetStore(), artworks: ImportedArtworkAssetStore())
    }

    private func testImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 80, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        return context.makeImage()!
    }

    private func made(_ id: String = "made-1") -> MyMirror {
        MyMirror(id: id, name: "나의 거울", origin: .made, style: BasicMirror.mint.style)
    }

    private func sticker(_ source: StickerSource) -> StickerObject {
        StickerObject(
            source: source,
            frame: NormalizedRect(x: 0.3, y: 0.3, width: 0.2, height: 0.1)
        )
    }

    private func valid(_ mirror: MyMirror) -> MirrorPublishDraft {
        MirrorPublishDraft(mirrorID: mirror.id, title: "리본 거울", description: "리본으로 꾸몄어요", priceInShards: 12)
    }

    // MARK: - 검사

    @Test("제목이 비어 있으면 등록 준비를 마칠 수 없다")
    func blankTitleIsRejected() {
        let mirror = made()
        for title in ["", "   ", "\n"] {
            var draft = valid(mirror)
            draft.title = title
            #expect(MirrorPublishValidator.issues(for: draft, mirror: mirror) == [.titleRequired])
        }
        #expect(MirrorPublishPolicy.normalizedTitle("  거울  ") == "거울")
        #expect(MirrorPublishPolicy.normalizedTitle("   ") == nil)
    }

    @Test("제목 / 설명 길이 제한을 넘기면 걸린다")
    func lengthLimitsAreEnforced() {
        let mirror = made()
        var draft = valid(mirror)
        draft.title = String(repeating: "가", count: MirrorPublishPolicy.maxTitleLength + 1)
        #expect(MirrorPublishValidator.issues(for: draft, mirror: mirror).contains(.titleTooLong))

        draft = valid(mirror)
        draft.description = String(repeating: "나", count: MirrorPublishPolicy.maxDescriptionLength + 1)
        #expect(MirrorPublishValidator.issues(for: draft, mirror: mirror).contains(.descriptionTooLong))

        // 딱 맞으면 통과한다.
        draft = valid(mirror)
        draft.title = String(repeating: "다", count: MirrorPublishPolicy.maxTitleLength)
        draft.description = String(repeating: "라", count: MirrorPublishPolicy.maxDescriptionLength)
        #expect(MirrorPublishValidator.issues(for: draft, mirror: mirror).isEmpty)
    }

    @Test("설명은 비워도 된다")
    func descriptionIsOptional() {
        let mirror = made()
        var draft = valid(mirror)
        draft.description = ""
        #expect(MirrorPublishValidator.issues(for: draft, mirror: mirror).isEmpty)
    }

    @Test("가격은 0(무료)부터 상한까지만 받는다")
    func priceRangeIsEnforced() {
        let mirror = made()
        var draft = valid(mirror)

        draft.priceInShards = 0
        #expect(MirrorPublishValidator.issues(for: draft, mirror: mirror).isEmpty)   // 무료 허용

        draft.priceInShards = MirrorPublishPolicy.priceRange.upperBound
        #expect(MirrorPublishValidator.issues(for: draft, mirror: mirror).isEmpty)

        draft.priceInShards = -1
        #expect(MirrorPublishValidator.issues(for: draft, mirror: mirror) == [.priceOutOfRange])

        draft.priceInShards = MirrorPublishPolicy.priceRange.upperBound + 1
        #expect(MirrorPublishValidator.issues(for: draft, mirror: mirror) == [.priceOutOfRange])
    }

    @Test("내가 만든 거울만 올릴 수 있다")
    func onlyMadeMirrorsAreEligible() {
        let mirror = made()
        #expect(MirrorPublishPolicy.isEligible(mirror))
        #expect(MirrorPublishValidator.issues(for: valid(mirror), mirror: mirror).isEmpty)

        // 받은 / 구매한 / 판매 중 거울은 그대로 되팔 수 없다.
        for origin in [MirrorOrigin.basic, .purchased, .listed] {
            var other = mirror
            other.origin = origin
            #expect(!MirrorPublishPolicy.isEligible(other))
            #expect(MirrorPublishValidator.issues(for: valid(other), mirror: other) == [.notEligible])
        }
    }

    @Test("거울이 없으면 등록 준비를 마칠 수 없다")
    func missingMirrorIsRejected() {
        let draft = MirrorPublishDraft(mirrorID: "사라진-거울", title: "제목")
        #expect(MirrorPublishValidator.issues(for: draft, mirror: nil) == [.mirrorMissing])
    }

    // MARK: - Manifest

    @Test("manifest가 사진 스티커와 외부 디자인을 모은다")
    func manifestCollectsAssets() {
        let photos = PhotoStickerAssetStore()
        let artworks = ImportedArtworkAssetStore()
        let photo = photos.register(testImage())
        let artworkID = artworks.register(testImage())

        var mirror = made()
        mirror.stickers = [sticker(photo), sticker(.builtIn(.heart))]
        mirror.importedArtworks = [ImportedArtworkObject(assetID: artworkID)]

        let manifest = MirrorPublishManifest(mirror)
        #expect(manifest.mirrorID == mirror.id)
        #expect(manifest.photoAssetIDs == [photo.photoAssetID!])   // 기본 스티커는 파일이 없다
        #expect(manifest.importedArtworkAssetIDs == [artworkID])
        #expect(manifest.assetCount == 2)
        #expect(manifest.needsPhotoPrivacyNotice)
        #expect(manifest.needsArtworkRightsNotice)
    }

    @Test("같은 이미지를 여러 번 써도 manifest에는 한 번만 담긴다")
    func manifestDeduplicatesAssets() {
        let photos = PhotoStickerAssetStore()
        let photo = photos.register(testImage())

        var mirror = made()
        mirror.stickers = [sticker(photo), sticker(photo), sticker(photo)]

        let manifest = MirrorPublishManifest(mirror)
        #expect(mirror.stickers.count == 3)
        #expect(manifest.photoAssetIDs.count == 1)
        // 순서는 항상 같다.
        #expect(MirrorPublishManifest(mirror) == manifest)
    }

    @Test("manifest에는 이미지가 아니라 참조만 들어간다")
    func manifestKeepsNoBinary() {
        let photos = PhotoStickerAssetStore()
        var mirror = made()
        mirror.stickers = [sticker(photos.register(testImage()))]

        let manifest = MirrorPublishManifest(mirror)
        // id 목록뿐이라 이미지 크기와 무관하게 작다.
        #expect(MemoryLayout.size(ofValue: manifest.photoAssetIDs[0]) == 16)
        #expect(manifest.photoAssetIDs.count == 1)
    }

    @Test("장식이 없는 거울은 manifest가 비어 있고 안내도 필요 없다")
    func plainMirrorNeedsNoNotice() {
        let manifest = MirrorPublishManifest(made())
        #expect(manifest.photoAssetIDs.isEmpty)
        #expect(manifest.importedArtworkAssetIDs.isEmpty)
        #expect(!manifest.needsPhotoPrivacyNotice)
        #expect(!manifest.needsArtworkRightsNotice)
        #expect(MirrorPublishValidator.issues(for: valid(made()), mirror: made()).isEmpty)
    }

    // MARK: - 사라진 이미지

    @Test("사진 이미지를 못 찾으면 등록 준비를 마칠 수 없다")
    func missingPhotoAssetBlocksDraft() {
        let photos = PhotoStickerAssetStore()
        var mirror = made()
        // 어떤 보관소에도 없는 참조.
        mirror.stickers = [sticker(.photo(assetID: UUID(), aspectRatio: 1))]

        let issues = MirrorPublishValidator.issues(
            for: valid(mirror), mirror: mirror, photos: photos, artworks: ImportedArtworkAssetStore()
        )
        #expect(issues.contains(.photoAssetMissing))
    }

    @Test("외부 디자인 이미지를 못 찾으면 등록 준비를 마칠 수 없다")
    func missingArtworkAssetBlocksDraft() {
        var mirror = made()
        mirror.importedArtworks = [ImportedArtworkObject(assetID: UUID())]

        let issues = MirrorPublishValidator.issues(
            for: valid(mirror), mirror: mirror,
            photos: PhotoStickerAssetStore(), artworks: ImportedArtworkAssetStore()
        )
        #expect(issues.contains(.artworkAssetMissing))
    }

    // MARK: - 사진 공개 확인

    @Test("사진 스티커가 있으면 공개 안내를 확인해야 넘어간다")
    func photoPrivacyMustBeAcknowledged() {
        let photos = PhotoStickerAssetStore()
        let artworks = ImportedArtworkAssetStore()
        var mirror = made()
        mirror.stickers = [sticker(photos.register(testImage()))]

        var draft = valid(mirror)
        #expect(!draft.didAcknowledgePhotoPrivacy)
        #expect(
            MirrorPublishValidator.issues(for: draft, mirror: mirror, photos: photos, artworks: artworks)
                == [.photoPrivacyNotAcknowledged]
        )

        draft.didAcknowledgePhotoPrivacy = true
        #expect(
            MirrorPublishValidator.issues(for: draft, mirror: mirror, photos: photos, artworks: artworks).isEmpty
        )
    }

    @Test("사진이 없는 거울은 확인 없이도 넘어간다")
    func noPhotoNeedsNoAcknowledgement() {
        var mirror = made()
        mirror.stickers = [sticker(.builtIn(.star))]

        let draft = valid(mirror)
        #expect(!draft.didAcknowledgePhotoPrivacy)
        #expect(MirrorPublishValidator.issues(for: draft, mirror: mirror).isEmpty)
        #expect(!MirrorPublishManifest(mirror).needsPhotoPrivacyNotice)
    }

    // MARK: - 저장

    @Test("등록 준비는 앱을 다시 켜도 남아 있다")
    func draftSurvivesRelaunch() throws {
        try withStore { store in
            let first = library(store)
            let mirror = made()
            first.save(MirrorDesign(mirror: mirror), name: "나의 거울", context: .createNew)
            let saved = try #require(first.mirrors.first)

            var draft = valid(saved)
            draft.mirrorID = saved.id
            first.savePublishDraft(draft)
            store.flush()

            let reopened = library(MirrorStore(root: store.root))
            let restored = try #require(reopened.publishDraft(for: saved.id))
            #expect(restored.title == "리본 거울")
            #expect(restored.description == "리본으로 꾸몄어요")
            #expect(restored.priceInShards == 12)
        }
    }

    @Test("거울 하나에 준비 정보 하나 — 다시 저장하면 덮어쓴다")
    func draftIsUpsertedPerMirror() throws {
        try withStore { store in
            let library = library(store)
            library.save(MirrorDesign(mirror: made()), name: "나의 거울", context: .createNew)
            let mirrorID = library.mirrors[0].id

            var draft = MirrorPublishDraft(mirrorID: mirrorID, title: "처음")
            library.savePublishDraft(draft)
            let firstID = library.publishDraft(for: mirrorID)?.id

            draft.title = "고침"
            library.savePublishDraft(draft)

            #expect(library.publishDrafts.count == 1)
            #expect(library.publishDraft(for: mirrorID)?.title == "고침")
            #expect(library.publishDraft(for: mirrorID)?.id == firstID)   // 같은 준비 정보다
        }
    }

    @Test("거울을 지우면 준비 정보도 같이 사라진다")
    func deletingMirrorRemovesDraft() throws {
        try withStore { store in
            let library = library(store)
            library.save(MirrorDesign(mirror: made()), name: "나의 거울", context: .createNew)
            let mirror = library.mirrors[0]
            library.savePublishDraft(MirrorPublishDraft(mirrorID: mirror.id, title: "제목"))

            library.delete(mirror)
            #expect(library.publishDrafts.isEmpty)
            store.flush()
            #expect(self.library(MirrorStore(root: store.root)).publishDrafts.isEmpty)
        }
    }

    // MARK: - 건드리지 않는 것

    @Test("등록 준비를 저장해도 거울 / 슬롯 / 조각 / 상점은 그대로다")
    func draftChangesNothingElse() throws {
        try withStore { store in
            let library = library(store)
            library.save(MirrorDesign(mirror: made()), name: "나의 거울", context: .createNew)
            let mirror = library.mirrors[0]

            let originBefore = mirror.origin
            let createdBefore = library.createdCount
            let capacityBefore = library.mirrorCapacity
            let storeListingsBefore = StoreCatalog.samples.count

            var draft = valid(mirror)
            draft.mirrorID = mirror.id
            library.savePublishDraft(draft)

            #expect(library.mirrors[0].origin == originBefore)          // 판매 중으로 바뀌지 않는다
            #expect(library.mirrors[0].origin == .made)
            #expect(library.createdCount == createdBefore)              // 슬롯 변화 없음
            #expect(library.mirrorCapacity == capacityBefore)
            #expect(StoreCatalog.samples.count == storeListingsBefore)  // 상점 목록에 끼어들지 않는다
            #expect(!StoreCatalog.samples.contains { $0.id == mirror.id })
            // 거울 디자인 데이터도 그대로다.
            #expect(library.mirrors[0].name == "나의 거울")
        }
    }

    @Test("등록 비용은 안내만 하고 차감하지 않는다")
    func feeIsOnlyDisplayed() throws {
        try withStore { store in
            let library = library(store)
            library.save(MirrorDesign(mirror: made()), name: "나의 거울", context: .createNew)

            #expect(MirrorPublishPolicy.feeInShards == 10)

            var draft = valid(library.mirrors[0])
            draft.mirrorID = library.mirrors[0].id
            library.savePublishDraft(draft)

            // 준비만 저장됐다. 조각은 서버 원장에만 있고 client에 차감 통로 자체가 없다
            // (ShardWalletTests가 고정한다).
            #expect(library.publishDraft(for: library.mirrors[0].id) != nil)
        }
    }
}
