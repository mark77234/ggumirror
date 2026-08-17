//
//  StickerStoreTests.swift
//  ggumirrorTests
//
//  Phase V-5B — 내 스티커 + 스티커 상점 연결.
//
//  가장 중요한 하나: **거울에 놓인 스티커는 목록과 수명이 분리된다.**
//  원본을 고쳐도, 목록에서 지워도 이미 놓인 거울은 그대로여야 한다.
//  이걸 놓치면 사용자가 예전에 만든 거울이 조용히 바뀌거나 깨진다.
//

import Testing
import SwiftUI
import UIKit
@testable import ggumirror

@MainActor
struct StickerStoreTests {

    // MARK: - 도구

    private func withStores(
        _ body: (StickerProjectStore, StickerLibrary, MirrorStore, MirrorLibrary) throws -> Void
    ) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-v5b-\(UUID().uuidString)", directoryHint: .isDirectory)
        let stickerStore = StickerProjectStore(root: root)
        let mirrorStore = MirrorStore(root: root)
        defer {
            stickerStore.flush()
            mirrorStore.flush()
            try? FileManager().removeItem(at: root)
        }
        // 배치 스냅샷은 사진 asset으로 저장되므로 같은 root를 쓰는 store에 붙인다.
        PhotoStickerAssetStore.shared.attach(mirrorStore)
        let mirrors = MirrorLibrary(store: mirrorStore, artworks: ImportedArtworkAssetStore())
        try body(stickerStore, StickerLibrary(store: stickerStore), mirrorStore, mirrors)
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &data, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    private func opaquePixels(_ image: CGImage) -> Int {
        let data = pixels(image)
        var count = 0
        for index in stride(from: 3, to: data.count, by: 4) where data[index] > 0 { count += 1 }
        return count
    }

    private func doodle(_ sticker: DoodleSticker, width: Double = 0.4) -> StickerObject {
        let source = StickerSource.doodle(sticker)
        let height = StickerObject.height(for: width, aspectRatio: source.aspectRatio, canvas: .sticker)
        return StickerObject(
            source: source,
            frame: NormalizedRect(x: 0.5 - width / 2, y: 0.5 - height / 2, width: width, height: height)
        )
    }

    /// 두들 하나가 들어 있는 스티커 디자인.
    private func design(_ sticker: DoodleSticker = .heart, name: String = "내 스티커") -> MirrorDesign {
        var design = MirrorDesign.blankSticker(id: UUID().uuidString, name: name)
        design.stickers = [doodle(sticker)]
        return design
    }

    // MARK: - 상점 구조

    @Test("상점에 거울 / 스티커 두 칸이 있다")
    func storeHasTwoSections() {
        #expect(StoreSection.allCases.map(\.rawValue) == ["거울", "스티커"])
        // 새 Bottom Tab을 만들지 않았다.
        #expect(MainTab.allCases.count == 3)
        #expect(MainTab.allCases.map(\.title) == ["홈", "상점", "내 거울"])
    }

    @Test("거울 상점은 그대로다")
    func mirrorStoreUnchanged() {
        #expect(StoreCatalog.artworkTemplates.count == 24)
        #expect(StoreCatalog.samples.count == 24 + BasicMirror.allCases.count)
        // 갈래 · 태그 필터 · 가격 규칙 모두 유지.
        #expect(StoreCategory.allCases.count > 1)
        #expect(TagFilter.allCases.count > 1)
        #expect(StoreCatalog.samples.contains { $0.price == 0 })
    }

    @Test("스티커 화면은 로그인 없이 쓸 수 있다")
    func stickerScreenWorksSignedOut() throws {
        try withStores { _, stickers, _, mirrors in
            let session = AuthSession(store: InMemoryIdentityStore(), sessions: InMemoryServerSessionStore())
            #expect(session.state == .signedOut)
            // 로그인 상태와 무관하게 목록 · 만들기 · 등록 준비가 모두 동작한다.
            let saved = try #require(stickers.save(design(), name: "로그아웃", context: .createNew))
            #expect(stickers.projects.count == 1)
            stickers.saveDraft(StickerPublishDraft(stickerProjectID: saved.id, title: "제목"))
            #expect(stickers.draft(for: saved.id) != nil)
            #expect(mirrors.mirrors.isEmpty)
        }
    }

    // MARK: - 내 스티커

    @Test("저장한 스티커가 목록에 바로 나타난다")
    func savedStickerAppearsImmediately() throws {
        try withStores { store, stickers, _, _ in
            #expect(stickers.projects.isEmpty)

            let saved = try #require(stickers.save(design(), name: "첫 스티커", context: .createNew))

            // 앱을 다시 켜지 않고도 목록에 있다 — 같은 @Observable 객체가 진실이다.
            #expect(stickers.projects.count == 1)
            #expect(stickers.projects.first?.id == saved.id)
            // 완성 PNG도 바로 해석된다.
            store.flush()
            let image = try #require(stickers.finalImage(for: saved))
            #expect(image.width == 1024)
            #expect(opaquePixels(image) > 0)
        }
    }

    @Test("앱을 다시 켜도 목록이 남는다")
    func listSurvivesRestart() throws {
        try withStores { store, stickers, _, _ in
            _ = stickers.save(design(.cake), name: "케이크", context: .createNew)
            _ = stickers.save(design(.crown), name: "왕관", context: .createNew)
            store.flush()

            let relaunched = StickerLibrary(store: store)
            #expect(relaunched.projects.count == 2)
            #expect(relaunched.projects.map(\.name) == ["케이크", "왕관"])
        }
    }

    @Test("꾸미기는 같은 스티커를 고친다")
    func editExistingKeepsIdentityAndCount() throws {
        try withStores { _, stickers, _, _ in
            let saved = try #require(stickers.save(design(), name: "원본", context: .createNew))

            var edited = saved.design
            edited.stickers.append(doodle(.star, width: 0.2))
            let updated = try #require(
                stickers.save(edited, name: "무시됨", context: .editExisting(saved.id))
            )

            #expect(updated.id == saved.id)
            #expect(updated.name == "원본")
            #expect(stickers.projects.count == 1)
            #expect(updated.design.stickers.count == 2)
        }
    }

    @Test("복제는 새 스티커 하나를 만든다")
    func duplicateCreatesOneNewSticker() throws {
        try withStores { store, stickers, _, _ in
            let saved = try #require(stickers.save(design(), name: "원본", context: .createNew))
            store.flush()

            let copy = try #require(stickers.duplicate(saved))

            #expect(stickers.projects.count == 2)
            #expect(copy.id != saved.id)
            #expect(copy.name == "원본 복사본")
            // 완성 PNG도 새로 굽는다 — 원본과 asset을 공유하지 않는다.
            #expect(copy.finalAssetID != nil)
            #expect(copy.finalAssetID != saved.finalAssetID)

            // 한 번 더 복제하면 이름이 겹치지 않는다.
            let second = try #require(stickers.duplicate(saved))
            #expect(second.name == "원본 복사본 2")
        }
    }

    @Test("삭제하면 목록에서 사라진다")
    func deleteRemovesFromLibrary() throws {
        try withStores { store, stickers, _, _ in
            let saved = try #require(stickers.save(design(), name: "지울 것", context: .createNew))
            stickers.saveDraft(StickerPublishDraft(stickerProjectID: saved.id, title: "제목"))
            store.flush()

            stickers.delete(saved)

            #expect(stickers.projects.isEmpty)
            // 준비 정보도 함께 정리된다.
            #expect(stickers.draft(for: saved.id) == nil)
        }
    }

    // MARK: - Editor picker

    @Test("Editor picker에 기본 / 내 스티커 두 칸이 있다")
    func pickerHasTwoGroups() throws {
        #expect(StickerGroup.allCases.map(\.rawValue) == ["기본 스티커", "내 스티커"])

        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "ggumirror/Editor/StickerPickerSheet.swift"),
            encoding: .utf8
        )
        // 기본은 두들 42종, legacy는 여전히 나오지 않는다.
        #expect(source.contains("DoodleSticker.all"))
        #expect(!source.contains("BuiltInSticker.all"))
        #expect(source.contains("stickers.projects"))
    }

    @Test("내 스티커를 거울에 놓을 수 있다")
    func userStickerCanBePlaced() throws {
        try withStores { store, stickers, _, _ in
            let saved = try #require(stickers.save(design(), name: "놓을 것", context: .createNew))
            store.flush()

            let source = try #require(stickers.placementSnapshot(for: saved))
            // 사진 asset과 같은 경로로 놓인다 — 불변 bitmap 참조다.
            #expect(source.photoAssetID != nil)
            #expect(!source.supportsTint)
            #expect(abs(source.aspectRatio - 1) < 0.01)   // 1024 × 1024

            var mirror = MirrorDesign.blank
            let width = 0.3
            let height = StickerObject.height(for: width, aspectRatio: source.aspectRatio)
            mirror.stickers = [StickerObject(
                source: source,
                frame: NormalizedRect(x: 0.35, y: 0.4, width: width, height: height)
            )]
            // 실제 거울에서 그려진다.
            #expect(MirrorCapture.compose(
                frame: nil, design: mirror, size: CGSize(width: 300, height: 650)
            ) != nil)
        }
    }

    // MARK: - 불변 스냅샷 (핵심)

    @Test("배치는 원본과 독립된 불변 asset을 만든다")
    func placementCreatesIndependentAsset() throws {
        try withStores { store, stickers, _, _ in
            let saved = try #require(stickers.save(design(), name: "원본", context: .createNew))
            store.flush()

            let first = try #require(stickers.placementSnapshot(for: saved))
            let second = try #require(stickers.placementSnapshot(for: saved))
            // 놓을 때마다 새 스냅샷이다 — 라이브러리의 finalAssetID를 직접 참조하지 않는다.
            #expect(first.photoAssetID != second.photoAssetID)
            #expect(first.photoAssetID != saved.finalAssetID)
        }
    }

    @Test("원본을 고쳐도 이미 놓인 거울은 그대로다")
    func editingLibraryDoesNotChangeOldPlacement() throws {
        try withStores { store, stickers, mirrorStore, mirrors in
            // v1: 하트만
            let v1 = try #require(stickers.save(design(.heart), name: "A", context: .createNew))
            store.flush()

            // v1을 거울에 놓고 저장한다.
            let snapshot = try #require(stickers.placementSnapshot(for: v1))
            let placedID = try #require(snapshot.photoAssetID)
            var mirror = MirrorDesign.blank
            mirror.stickers = [StickerObject(
                source: snapshot,
                frame: NormalizedRect(x: 0.3, y: 0.4, width: 0.3, height: 0.14)
            )]
            _ = mirrors.save(mirror, name: "거울 1", context: .createNew)
            mirrorStore.flush()
            let before = try #require(PhotoStickerAssetStore.shared.image(for: placedID))
            let beforePixels = pixels(before)

            // v2: 왕관을 더한다 (라이브러리 원본 수정)
            var edited = v1.design
            edited.stickers = [doodle(.crown)]
            _ = stickers.save(edited, name: "A", context: .editExisting(v1.id))
            store.flush()

            // 거울의 스냅샷은 **그대로**다.
            let after = try #require(PhotoStickerAssetStore.shared.image(for: placedID))
            #expect(pixels(after) == beforePixels)
            let reloaded = MirrorLibrary(store: mirrorStore, artworks: ImportedArtworkAssetStore())
            #expect(reloaded.mirrors.first?.stickers.first?.source.photoAssetID == placedID)
        }
    }

    @Test("새로 놓으면 최신 디자인이 쓰인다")
    func newPlacementUsesNewestDesign() throws {
        try withStores { store, stickers, _, _ in
            let v1 = try #require(stickers.save(design(.heart), name: "A", context: .createNew))
            store.flush()
            let firstSnapshot = try #require(stickers.placementSnapshot(for: v1))

            var edited = v1.design
            edited.stickers = [doodle(.crown)]
            let v2 = try #require(stickers.save(edited, name: "A", context: .editExisting(v1.id)))
            store.flush()
            let secondSnapshot = try #require(stickers.placementSnapshot(for: v2))

            let first = try #require(PhotoStickerAssetStore.shared.image(for: firstSnapshot.photoAssetID!))
            let second = try #require(PhotoStickerAssetStore.shared.image(for: secondSnapshot.photoAssetID!))
            // 하트와 왕관은 다르게 그려진다.
            #expect(pixels(first) != pixels(second))
        }
    }

    @Test("목록에서 지워도 거울은 깨지지 않는다")
    func deletingLibraryStickerKeepsMirror() throws {
        try withStores { store, stickers, mirrorStore, mirrors in
            let saved = try #require(stickers.save(design(), name: "지울 것", context: .createNew))
            store.flush()

            let snapshot = try #require(stickers.placementSnapshot(for: saved))
            let placedID = try #require(snapshot.photoAssetID)
            var mirror = MirrorDesign.blank
            mirror.stickers = [StickerObject(
                source: snapshot,
                frame: NormalizedRect(x: 0.3, y: 0.4, width: 0.3, height: 0.14)
            )]
            _ = mirrors.save(mirror, name: "거울 1", context: .createNew)
            mirrorStore.flush()

            // 라이브러리에서 삭제한다.
            stickers.delete(saved)
            store.flush()

            // 거울의 스냅샷은 살아 있다 — 수명이 분리돼 있다.
            #expect(PhotoStickerAssetStore.shared.image(for: placedID) != nil)
            let reloaded = MirrorLibrary(store: mirrorStore, artworks: ImportedArtworkAssetStore())
            #expect(reloaded.mirrors.first?.stickers.count == 1)
            #expect(FileManager().fileExists(
                atPath: mirrorStore.assetURL(placedID, kind: .photoSticker).path
            ))
        }
    }

    @Test("거울 저장 / 재실행이 배치를 유지한다")
    func mirrorReloadPreservesPlacement() throws {
        try withStores { store, stickers, mirrorStore, mirrors in
            let saved = try #require(stickers.save(design(), name: "A", context: .createNew))
            store.flush()
            let snapshot = try #require(stickers.placementSnapshot(for: saved))

            var mirror = MirrorDesign.blank
            mirror.stickers = [StickerObject(
                source: snapshot,
                frame: NormalizedRect(x: 0.2, y: 0.3, width: 0.5, height: 0.23),
                rotation: 24,
                opacity: 0.8
            )]
            _ = mirrors.save(mirror, name: "거울 1", context: .createNew)
            mirrorStore.flush()

            let reloaded = MirrorLibrary(store: mirrorStore, artworks: ImportedArtworkAssetStore())
            let restored = try #require(reloaded.mirrors.first?.stickers.first)
            #expect(restored.source.photoAssetID == snapshot.photoAssetID)
            #expect(restored.frame.width == 0.5)
            #expect(restored.rotation == 24)
            #expect(restored.opacity == 0.8)
            // 거울 저장 형식은 그대로 3이다 — 새 case를 만들지 않았다.
            #expect(MirrorSchema.current == 3)
        }
    }

    // MARK: - 크기 조절 회귀

    @Test("내 스티커도 uniform scale이고 최대 제한이 없다")
    func userStickerResizeFollowsPolicy() throws {
        try withStores { store, stickers, _, _ in
            let saved = try #require(stickers.save(design(), name: "A", context: .createNew))
            store.flush()
            let source = try #require(stickers.placementSnapshot(for: saved))

            let width = 0.3
            let base = StickerObject(
                source: source,
                frame: NormalizedRect(
                    x: 0.35, y: 0.4, width: width,
                    height: StickerObject.height(for: width, aspectRatio: source.aspectRatio)
                )
            )
            let before = (base.frame.width * MirrorCanvas.size.width)
                / (base.frame.height * MirrorCanvas.size.height)

            for target in [0.1, 1.0, 3.0, 8.0] {
                let resized = base.resized(width: target)
                #expect(resized.frame.width == target)   // 상한 없음
                let ratio = (resized.frame.width * MirrorCanvas.size.width)
                    / (resized.frame.height * MirrorCanvas.size.height)
                #expect(abs(ratio - before) < 0.001)     // 비율 유지
            }

            // 캔버스보다 커질 수 있다.
            let huge = base.resized(width: 4).constrained()
            #expect(huge.frame.width > 1)
        }
    }

    @Test("큰 내 스티커도 저장되고, 원본을 고쳐도 크기가 그대로다")
    func oversizedUserStickerPersistsAcrossLibraryEdit() throws {
        try withStores { store, stickers, mirrorStore, mirrors in
            let saved = try #require(stickers.save(design(), name: "A", context: .createNew))
            store.flush()
            let source = try #require(stickers.placementSnapshot(for: saved))

            var mirror = MirrorDesign.blank
            mirror.stickers = [StickerObject(
                source: source,
                frame: NormalizedRect(x: 0.2, y: 0.2, width: 3, height: 1.385)
            ).constrained()]
            _ = mirrors.save(mirror, name: "큰 배치", context: .createNew)
            mirrorStore.flush()

            // 라이브러리 원본을 고친다.
            var edited = saved.design
            edited.stickers = [doodle(.crown)]
            _ = stickers.save(edited, name: "A", context: .editExisting(saved.id))
            store.flush()

            let reloaded = MirrorLibrary(store: mirrorStore, artworks: ImportedArtworkAssetStore())
            let restored = try #require(reloaded.mirrors.first?.stickers.first)
            #expect(abs(restored.frame.width - 3) < 0.0001)
        }
    }

    // MARK: - 등록 준비

    @Test("등록 준비가 저장되고 다시 읽힌다")
    func publishDraftSavesAndReloads() throws {
        try withStores { store, stickers, _, _ in
            let saved = try #require(stickers.save(design(), name: "A", context: .createNew))
            var draft = StickerPublishDraft(stickerProjectID: saved.id, title: "리본 스티커")
            draft.description = "리본으로 꾸몄어요"
            draft.priceInShards = 12
            draft.didAcknowledgeRights = true
            stickers.saveDraft(draft)
            store.flush()

            let reloaded = StickerLibrary(store: store)
            let restored = try #require(reloaded.draft(for: saved.id))
            #expect(restored.title == "리본 스티커")
            #expect(restored.priceInShards == 12)
            #expect(restored.didAcknowledgeRights)
            // 거울 등록 준비와 파일이 다르다.
            #expect(store.draftsURL.lastPathComponent == "sticker-publish-drafts.json")
        }
    }

    @Test("제목 · 설명 · 가격 검사")
    func draftValidation() throws {
        let project = StickerProject(name: "A", design: design())
        func draft(_ change: (inout StickerPublishDraft) -> Void) -> StickerPublishDraft {
            var draft = StickerPublishDraft(stickerProjectID: project.id, title: "제목")
            draft.didAcknowledgeRights = true
            change(&draft)
            return draft
        }

        #expect(StickerPublishValidator.issues(for: draft { _ in }, project: project).isEmpty)
        #expect(StickerPublishValidator.issues(
            for: draft { $0.title = "  " }, project: project
        ) == [.titleRequired])
        #expect(StickerPublishValidator.issues(
            for: draft { $0.title = String(repeating: "가", count: 25) }, project: project
        ) == [.titleTooLong])
        #expect(StickerPublishValidator.issues(
            for: draft { $0.description = String(repeating: "가", count: 201) }, project: project
        ) == [.descriptionTooLong])
        for price in [-1, 1000] {
            #expect(StickerPublishValidator.issues(
                for: draft { $0.priceInShards = price }, project: project
            ) == [.priceOutOfRange])
        }
        #expect(StickerPublishValidator.issues(for: draft { _ in }, project: nil) == [.stickerMissing])
    }

    @Test("권리 확인은 반드시 필요하다")
    func rightsAcknowledgementRequired() {
        let project = StickerProject(name: "A", design: design())
        var draft = StickerPublishDraft(stickerProjectID: project.id, title: "제목")
        #expect(StickerPublishValidator.issues(for: draft, project: project) == [.rightsNotAcknowledged])
        draft.didAcknowledgeRights = true
        #expect(StickerPublishValidator.issues(for: draft, project: project).isEmpty)
    }

    @Test("사진이 있으면 공개 안내를 확인해야 한다")
    func photoRequiresPrivacyAcknowledgement() {
        let assets = PhotoStickerAssetStore.shared
        var withPhoto = MirrorDesign.blankSticker(id: UUID().uuidString, name: "사진 스티커")
        let context = CGContext(
            data: nil, width: 60, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.4, green: 0.7, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        withPhoto.stickers = [StickerObject(
            source: assets.register(context.makeImage()!),
            frame: NormalizedRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        )]
        let project = StickerProject(name: "사진 스티커", design: withPhoto)
        #expect(!project.photoAssetIDs.isEmpty)

        var draft = StickerPublishDraft(stickerProjectID: project.id, title: "제목")
        draft.didAcknowledgeRights = true
        #expect(StickerPublishValidator.issues(for: draft, project: project)
            == [.photoPrivacyNotAcknowledged])
        draft.didAcknowledgePhotoPrivacy = true
        #expect(StickerPublishValidator.issues(for: draft, project: project).isEmpty)
    }

    @Test("등록 준비는 조각을 건드리지 않고 listing도 만들지 않는다")
    func draftChangesNothingElse() throws {
        try withStores { store, stickers, _, _ in
            // 조각 잔액은 이제 서버가 정한다. 등록 준비는 client에서 잔액을 건드릴 수 없다 —
            // 애초에 그런 통로가 없다(ShardWalletTests가 고정한다).
            let saved = try #require(stickers.save(design(), name: "A", context: .createNew))
            var draft = StickerPublishDraft(stickerProjectID: saved.id, title: "제목")
            draft.didAcknowledgeRights = true
            stickers.saveDraft(draft)
            store.flush()

            // 등록 비용은 아직 정하지 않았다 — 거울의 20 조각을 가져오지 않는다.
            #expect(StickerPublishPolicy.feeInShards == nil)
            #expect(MirrorPublishPolicy.feeInShards == 20)
            // 상점에는 여전히 아무 listing도 없다.
            #expect(stickers.projects.count == 1)
            #expect(stickers.drafts.count == 1)
        }
    }

    // MARK: - GC

    @Test("참조되는 완성 PNG는 지워지지 않는다")
    func referencedFinalAssetSurvives() throws {
        try withStores { store, stickers, _, _ in
            let keep = try #require(stickers.save(design(.heart), name: "남길 것", context: .createNew))
            let drop = try #require(stickers.save(design(.crown), name: "지울 것", context: .createNew))
            store.flush()
            let keepID = try #require(keep.finalAssetID)
            let dropID = try #require(drop.finalAssetID)

            stickers.delete(drop)
            store.flush()

            #expect(FileManager().fileExists(atPath: store.assetURL(keepID).path))
            // 아무도 참조하지 않는 PNG는 정리된다.
            #expect(!FileManager().fileExists(atPath: store.assetURL(dropID).path))
        }
    }

    // MARK: - 회귀

    @Test("V-5A / PART I 정책이 그대로다")
    func earlierPoliciesUnchanged() throws {
        // 투명 출력
        let empty = MirrorDesign.blankSticker(id: "e", name: "e")
        let image = try #require(StickerRenderer.render(empty, size: CGSize(width: 64, height: 64)))
        #expect(opaquePixels(image) == 0)
        #expect(StickerCanvas.size == CGSize(width: 1024, height: 1024))

        // 크기 정책
        #expect(StickerObject.minimumWidth > 0)
        #expect(doodle(.heart).resized(width: 9, canvas: .sticker).frame.width == 9)

        // 두들 42 · legacy 유지 · 거울 24
        #expect(DoodleSticker.allCases.count == 42)
        #expect(BuiltInSticker(rawValue: "heart") == .heart)
        #expect(StoreCatalog.artworkTemplates.count == 24)

        // 스티커 저장 형식은 2(A-1A에서 출처가 생겼다), 거울은 그대로 3
        #expect(StickerSchema.current == 2)
        #expect(MirrorSchema.current == 3)
    }

    @Test("커스텀 모달 dismiss 정책이 유지된다")
    func inkModalDismissStillUsed() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "ggumirror")
        // 새로 만든 등록 준비 화면도 시트 안에서 뜨므로 같은 규칙을 따른다.
        for file in ["Store/PublishStickerView.swift", "Editor/TextEditorSheets.swift"] {
            let source = try String(contentsOf: root.appending(path: file), encoding: .utf8)
            #expect(!source.contains("Environment(\\.dismiss)"))
        }
    }
}
