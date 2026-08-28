//
//  DeviceQAFixPackTests.swift
//  ggumirrorTests
//
//  실기기 QA에서 나온 것들. 각각 **원인이 다른 문제**라 한 파일에 모으되 구획을 나눈다.
//
//    AI 거울 이름       생성 직후 이름을 받는다. 기본 `AI 거울`로 쌓이지 않는다
//    이름 겹침          한 서랍에 같은 이름을 두 개 두지 않는다
//    카메라 기본값      `채우기`. 이미 고른 사람의 선택은 덮지 않는다
//    Admin 유령 상품    운영 `판매 중`이 공개 상점과 같은 조건을 본다
//    Admin 내리기       창이 닫히면서 대상이 사라지던 것을 붙잡는다
//    등록 문구          "지금은 차감되지 않아요"는 사실이 아니다
//    판매자 이름        이름 없이 상점에 올릴 수 없다
//

import Testing
import AVFoundation
import Foundation
@testable import ggumirror

private func qaSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

private let owner = MirrorLibraryOwner.user("11111111-1111-1111-1111-111111111111")

private func withDrawer(_ body: (URL) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "ggumirror-qa-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

@MainActor
private func drawer(_ root: URL) -> MirrorLibrary {
    MirrorLibrary(
        store: MirrorStore(
            root: root.appending(path: "accounts/\(owner.directoryName)", directoryHint: .isDirectory)
        ),
        owner: owner,
        assets: PhotoStickerAssetStore(), artworks: ImportedArtworkAssetStore(),
        accountsBase: root
    )
}

private func mirror(_ id: String, name: String) -> MyMirror {
    MyMirror(id: id, name: name, origin: .made, style: BasicMirror.cream.style)
}

// MARK: - 이름 겹침 (계정 안)

@Suite("한 서랍에 같은 이름을 두 개 두지 않는다")
@MainActor
struct LocalNameUniquenessTests {

    @Test("같은 이름은 쓸 수 없다")
    func duplicatesAreRefused() throws {
        try withDrawer { root in
            let library = drawer(root)
            _ = library.adopt(mirror("m-1", name: "핑크 리본"))
            _ = library.adopt(mirror("m-2", name: "다른 거울"))

            #expect(!library.isNameAvailable("핑크 리본"))
            #expect(library.rename("m-2", to: "핑크 리본") == .duplicateName)
            // 실패했으므로 이름은 그대로다.
            #expect(library.mirrors.first { $0.id == "m-2" }?.name == "다른 거울")
        }
    }

    @Test("공백과 대소문자로 몰래 겹칠 수 없다")
    func normalizationBlocksSneakyDuplicates() throws {
        try withDrawer { root in
            let library = drawer(root)
            _ = library.adopt(mirror("m-1", name: "Pink"))
            _ = library.adopt(mirror("m-2", name: "다른 거울"))

            for sneaky in [" Pink ", "pink", "PINK", "  pink"] {
                #expect(!library.isNameAvailable(sneaky), "\(sneaky)")
                #expect(library.rename("m-2", to: sneaky) == .duplicateName, "\(sneaky)")
            }
        }
    }

    @Test("한글 자모 분리도 같은 이름으로 센다")
    func hangulDecompositionIsTheSameName() {
        // 자모가 풀린 이름은 **바이트가 다르다**(NFC vs NFD). Swift `String ==`는
        // 이것을 같다고 보지만, Firestore 문서 id처럼 바이트로 비교하는 곳은 다르게 본다.
        // 그래서 정규화가 필요하고, 여기서는 실제로 바이트가 다른지부터 확인한다.
        let composed = "핑크"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        #expect(Array(composed.unicodeScalars) != Array(decomposed.unicodeScalars))
        #expect(ContentNameKey.matches(composed, decomposed))
        // 정규화한 열쇠는 바이트까지 같아진다.
        #expect(
            Array(ContentNameKey.canonical(composed).unicodeScalars)
                == Array(ContentNameKey.canonical(decomposed).unicodeScalars)
        )
    }

    @Test("자기 이름을 자기가 막지 않는다")
    func renamingToYourOwnNameIsFine() throws {
        try withDrawer { root in
            let library = drawer(root)
            _ = library.adopt(mirror("m-1", name: "핑크 리본"))

            #expect(library.isNameAvailable("핑크 리본", excluding: "m-1"))
            // 대소문자만 바꾸는 것도 정상적인 이름 바꾸기다.
            #expect(library.rename("m-1", to: "핑크 리본 ") == .renamed("핑크 리본"))
        }
    }

    @Test("다른 계정 서랍과는 무관하다")
    func otherAccountsAreIndependent() throws {
        try withDrawer { root in
            let mine = drawer(root)
            _ = mine.adopt(mirror("m-1", name: "핑크 리본"))

            let other = MirrorLibraryOwner.user("22222222-2222-2222-2222-222222222222")
            let theirs = MirrorLibrary(
                store: MirrorStore(
                    root: root.appending(
                        path: "accounts/\(other.directoryName)", directoryHint: .isDirectory
                    )
                ),
                owner: other,
                assets: PhotoStickerAssetStore(), artworks: ImportedArtworkAssetStore(),
                accountsBase: root
            )
            // 계정 안의 규칙이다 — 상점 전체 이름 겹침과 다른 질문이다.
            #expect(theirs.isNameAvailable("핑크 리본"))
        }
    }

    @Test("스티커도 같은 규칙을 쓴다")
    func stickersShareTheRule() throws {
        try withDrawer { root in
            let store = StickerProjectStore(
                root: root.appending(
                    path: "accounts/\(owner.directoryName)", directoryHint: .isDirectory
                )
            )
            let library = StickerLibrary(store: store, owner: owner)
            let first = try #require(
                library.save(MirrorDesign.blank, name: "Pink", context: .createNew)
            )
            let second = try #require(
                library.save(MirrorDesign.blank, name: "다른 스티커", context: .createNew)
            )

            #expect(!library.isNameAvailable(" PINK "))
            #expect(library.rename(second.id, to: "pink") == .duplicateName)
            // 자기 자신은 세지 않는다.
            #expect(library.isNameAvailable("Pink", excluding: first.id))
        }
    }

    @Test("비교 규칙이 하나다")
    func oneNormalizationAuthority() throws {
        // 두 library가 같은 `ContentNameKey`를 부른다 — 규칙을 두 벌 만들지 않았다.
        for path in [
            "ggumirror/Shared/MirrorSampleData.swift",
            "ggumirror/Editor/StickerProjectStore.swift",
        ] {
            #expect(try qaSource(path).contains("ContentNameKey.canonical"), "\(path)")
        }
    }
}

// MARK: - AI 거울 이름 정하기

@Suite("AI 거울은 이름을 정하고 저장한다")
struct AIMirrorNamingTests {

    @Test("기본 `AI 거울`로 저장하지 않는다")
    func theDefaultNameNeverReachesTheLibrary() throws {
        let view = try qaSource("ggumirror/MyMirrors/AIMirrorView.swift")
        // 예전에는 `design.name = "AI 거울"`이 그대로 저장됐다.
        #expect(!view.contains("design.name = \"AI 거울\""))
        // 저장 경로 어디에도 기본 이름이 없다. 화면 제목은 별개다.
        let start = try #require(view.range(of: "private func save(_ artwork: ImportedArtworkObject, named raw: String)"))
        let body = String(view[start.upperBound...].prefix(1200))
        #expect(!body.contains("AI 거울"))
        #expect(body.contains("design.name = name"))
    }

    @Test("저장 전에 이름을 받는다")
    func savingGoesThroughTheNamingStep() throws {
        let view = try qaSource("ggumirror/MyMirrors/AIMirrorView.swift")
        // `내 거울에 저장` 버튼이 바로 저장하지 않고 이름 단계를 연다.
        #expect(view.contains("beginNaming(artwork)"))
        #expect(view.contains("MirrorNameSheet("))
        #expect(view.contains("거울 이름을 정하세요"))
        // 저장은 사용자가 정한 이름을 받는다.
        #expect(view.contains("private func save(_ artwork: ImportedArtworkObject, named raw: String)"))
    }

    @Test("이름 단계가 생성을 다시 부르지 않는다")
    func namingNeverRegenerates() throws {
        let view = try qaSource("ggumirror/MyMirrors/AIMirrorView.swift")
        let start = try #require(view.range(of: "private func save(_ artwork: ImportedArtworkObject, named raw: String)"))
        let body = String(view[start.upperBound...].prefix(1200))
        // 조각도 provider도 건드리지 않는다 — 이미 낸 값으로 이미 받은 그림이다.
        for forbidden in ["generate(", "maker.generate", "wallet", "canAfford", "shard"] {
            #expect(!body.contains(forbidden), "\(forbidden)")
        }
    }

    @Test("이름 단계가 서랍 규칙을 그대로 쓴다")
    func namingAsksTheLibrary() throws {
        let view = try qaSource("ggumirror/MyMirrors/AIMirrorView.swift")
        // 화면이 자기 판정 규칙을 적지 않는다.
        #expect(view.contains("library.isNameAvailable(candidate)"))
        // 저장 직전에 서랍이 마지막 판단을 한다 — 시트를 우회할 수 없다.
        #expect(view.contains("library.isNameAvailable(name)"))
    }

    @Test("시트를 닫아도 결과를 잃지 않는다")
    func dismissingTheSheetKeepsTheArtwork() throws {
        let view = try qaSource("ggumirror/MyMirrors/AIMirrorView.swift")
        // 결과는 `maker.artwork`에 남아 있고, 이름 시트는 그것을 가리킬 뿐이다.
        // 닫는다고 `maker.reset()`을 부르지 않는다 — 부르면 이미 낸 조각이 사라진다.
        let start = try #require(view.range(of: "inkBottomSheet(item: $naming"))
        let body = String(view[start.upperBound...].prefix(700))
        #expect(!body.contains("maker.reset()"))
    }

    @Test("이름 시트가 공용 component다")
    func theNamingSheetIsShared() throws {
        // 거울 이름 시트를 새로 만들지 않았다 — 이름 바꾸기·새 거울 저장과 같은 것이다.
        let sheet = try qaSource("ggumirror/Editor/MirrorSaveSheets.swift")
        #expect(sheet.contains("var validate: ((String) -> String?)?"))
        #expect(sheet.contains("private var canSave: Bool"))
    }
}

// MARK: - 카메라 기본값

@Suite("거울 카메라 기본은 채우기")
struct CameraFramingDefaultTests {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "ggumirror.tests.\(UUID().uuidString)")!
    }

    @Test("고른 적이 없으면 채우기다")
    func freshInstallFills() async {
        let camera = await MirrorCamera(role: .mirror, preferences: defaults())
        #expect(MirrorCamera.Framing.default == .fill)
        #expect(await camera.frontFraming == .fill)
    }

    @Test("실제 그리는 방법도 채우기다")
    func theRenderingModeIsActuallyFill() {
        // label만 바꾼 것이 아니다 — layer가 쓰는 값이 `resizeAspectFill`이다.
        #expect(MirrorCamera.Framing.fill.previewGravity == .resizeAspectFill)
        #expect(MirrorCamera.Framing.default.previewGravity == .resizeAspectFill)
        // `넓게`는 그대로 남아 있다 — 기능을 없앤 것이 아니다.
        #expect(MirrorCamera.Framing.wide.previewGravity == .resizeAspect)
        #expect(MirrorCamera.Framing.allCases.count == 2)
    }

    @Test("이미 `넓게`를 고른 사람의 선택을 덮지 않는다")
    func anExplicitWideChoiceSurvives() async {
        let store = defaults()
        store.set("wide", forKey: "ggumirror.camera.frontFraming")

        let camera = await MirrorCamera(role: .mirror, preferences: store)
        #expect(await camera.frontFraming == .wide)
    }

    @Test("`채우기`를 고른 사람도 그대로다")
    func anExplicitFillChoiceSurvives() async {
        let store = defaults()
        store.set("fill", forKey: "ggumirror.camera.frontFraming")

        #expect(await MirrorCamera(role: .mirror, preferences: store).frontFraming == .fill)
    }

    @Test("고른 값이 앱을 다시 켜도 남는다")
    func theChoiceSurvivesRelaunch() async throws {
        // `setFrontFraming`은 살아 있는 카메라(`canChooseFraming`)를 요구하므로
        // 테스트에서는 부를 수 없다. 대신 **저장 계약**을 양쪽에서 확인한다:
        // 무엇을 적는지(소스)와 적힌 것을 어떻게 읽는지(실제 동작).
        let code = try qaSource("ggumirror/Mirror/MirrorCamera.swift")
        let setter = try #require(code.range(of: "func setFrontFraming(_ next: Framing)"))
        let body = String(code[setter.upperBound...].prefix(400))
        #expect(body.contains("preferences.set(next.rawValue, forKey: Self.framingKey)"))

        // 적힌 값은 다음 실행에서 그대로 돌아온다.
        for choice in [MirrorCamera.Framing.wide, .fill] {
            let store = defaults()
            store.set(choice.rawValue, forKey: "ggumirror.camera.frontFraming")
            #expect(await MirrorCamera(role: .mirror, preferences: store).frontFraming == choice)
        }
    }

    @Test("기본값을 미리 적어 두지 않는다")
    func theDefaultIsNeverWritten() async {
        let store = defaults()
        _ = await MirrorCamera(role: .mirror, preferences: store)
        // 적어 두면 나중에 기본값을 바꿔도 "이미 고른 사람"으로 취급된다.
        #expect(store.string(forKey: "ggumirror.camera.frontFraming") == nil)
    }

    @Test("모르는 값이 저장돼 있으면 기본값으로 간다")
    func unknownStoredValuesFallBack() async {
        let store = defaults()
        store.set("diagonal", forKey: "ggumirror.camera.frontFraming")

        #expect(await MirrorCamera(role: .mirror, preferences: store).frontFraming == .fill)
    }
}

// MARK: - Admin

@Suite("운영 화면이 공개 상점과 같은 것을 말한다")
struct AdminVisibilityTests {

    private func listing(status: String, moderation: String = "active") -> AdminListing {
        AdminListing(
            id: "l-1", contentType: "mirror", title: "찬찡", description: "",
            priceShards: 0, status: status, moderationStatus: moderation,
            moderationReason: nil, downloadCount: 0, likeCount: 0,
            createdAt: .distantPast, publishedAt: nil, sellerDisplayName: nil
        )
    }

    @Test("`판매 중`은 실제로 공개된 것만이다")
    func liveMeansPubliclyVisible() {
        // **실기기 버그**: `찬찡`은 draft였는데 운영 화면 `판매 중`에 있었다.
        // 공개 상점에는 없었으므로 운영자가 무엇을 조치해야 하는지 알 수 없었다.
        #expect(!AdminStatusFilter.live.includes(listing(status: "draft")))
        #expect(!AdminStatusFilter.live.includes(listing(status: "unlisted")))
        #expect(!AdminStatusFilter.live.includes(listing(status: "deleted")))
        #expect(AdminStatusFilter.live.includes(listing(status: "published")))
        // 운영자가 내린 것도 `판매 중`이 아니다.
        #expect(!AdminStatusFilter.live.includes(
            listing(status: "published", moderation: "removed")
        ))
    }

    @Test("`내려감`은 운영자가 내린 것만이다")
    func removedMeansModerated() {
        #expect(AdminStatusFilter.removed.includes(
            listing(status: "published", moderation: "removed")
        ))
        // 판매자가 삭제한 것은 끝 상태라 여기 오지 않는다.
        #expect(!AdminStatusFilter.removed.includes(
            listing(status: "deleted", moderation: "removed")
        ))
    }

    @Test("`전체`는 기록을 전부 보여 준다")
    func allShowsEverything() {
        for status in ["draft", "published", "unlisted", "deleted"] {
            #expect(AdminStatusFilter.all.includes(listing(status: status)), "\(status)")
        }
    }

    @Test("공개 판단이 한 곳에서 나온다")
    func oneVisibilityRule() {
        // 운영 필터가 자기 조건을 다시 적지 않고 이 값을 읽는다.
        #expect(listing(status: "published").isPubliclyVisible)
        #expect(!listing(status: "draft").isPubliclyVisible)
    }
}

@Suite("운영자 조치가 실제로 나간다")
struct AdminModerationDispatchTests {

    @Test("창이 닫히기 전에 대상을 붙잡는다")
    func theTargetIsCapturedBeforeDismissal() throws {
        // **실기기 버그**: `InkDialog`는 버튼을 누르면 `onAction()`(창 닫기)을 먼저
        // 부르고 그다음 `handler()`를 부른다. 창이 닫히면서 binding setter가
        // `pendingTakedown = nil`을 쓰므로, handler 안에서 그 값을 읽으면 언제나 비어
        // 있었다 — 버튼을 눌러도 요청이 나가지 않았다.
        let modal = try qaSource("ggumirror/Shared/InkModal.swift")
        let button = try #require(modal.range(of: "Button {"))
        let body = String(modal[button.upperBound...].prefix(120))
        #expect(body.contains("onAction()"))
        #expect(body.contains("action.handler()"))

        let admin = try qaSource("ggumirror/Admin/AdminStoreView.swift")
        // 이제 값을 창 만들 때 붙잡는다.
        #expect(admin.contains("let target = pendingTakedown"))
        #expect(admin.contains("let target = pendingRestore"))
        // handler가 @State를 다시 읽지 않는다.
        #expect(!admin.contains("if let listing = pendingTakedown"))
        #expect(!admin.contains("if let listing = pendingRestore"))
    }

    @Test("조치 정책은 그대로다")
    func moderationPolicyIsUnchanged() throws {
        let admin = try qaSource("ggumirror/Admin/AdminStoreView.swift")
        // 판매자가 삭제한 것은 되살릴 수 없다.
        #expect(admin.contains("guard !listing.isDeletedBySeller else { return nil }"))
        #expect(admin.contains("store.takedown("))
        #expect(admin.contains("store.restore("))
        #expect(admin.contains("AdminModerationReason.allCases"))
    }

    @Test("조치 뒤 목록이 그 자리에서 바뀐다")
    func theListUpdatesInPlace() throws {
        let admin = try qaSource("ggumirror/Admin/AdminStoreView.swift")
        // 성공하면 그 항목만 새 값으로 바꾼다 — 목록 전체를 다시 받지 않는다.
        #expect(admin.contains("listings[index] = updated"))
        // **id로 찾는다.** 제목으로 찾으면 같은 이름이 여럿일 때 엉뚱한 것이 바뀐다.
        #expect(admin.contains("firstIndex(where: { $0.id == listingID })"))
        // 같은 상품을 두 번 넣지 않는다(pagination 겹침).
        #expect(admin.contains("known.contains($0.id)"))
    }
}

// MARK: - 등록 문구 · 판매자 이름

@Suite("등록 화면이 사실을 말한다")
struct PublishCopyTests {

    @Test("`지금은 차감되지 않아요`가 사라졌다")
    func theMisleadingCopyIsGone() throws {
        for path in [
            "ggumirror/Store/PublishMirrorView.swift",
            "ggumirror/Store/PublishStickerView.swift",
        ] {
            let code = try qaSource(path)
            // 등록비는 실제로 차감된다 — 안 빠진다고 말하면 거짓말이다.
            #expect(!code.contains("지금은 차감되지 않아요"), "\(path)")
            #expect(!code.contains("다음 업데이트에서"), "\(path)")
        }
    }

    @Test("등록 비용은 그대로 보여 준다")
    func theFeeIsStillShown() throws {
        for (path, policy) in [
            ("ggumirror/Store/PublishMirrorView.swift", "MirrorPublishPolicy.feeInShards"),
            ("ggumirror/Store/PublishStickerView.swift", "StickerPublishPolicy.feeInShards"),
        ] {
            #expect(try qaSource(path).contains(policy), "\(path)")
        }
        #expect(MirrorPublishPolicy.feeInShards == 10)
        #expect(StickerPublishPolicy.feeInShards == 10)
    }

    @Test("draft 저장 안내는 사실이라 남는다")
    func theDraftNoticeIsStillTrue() throws {
        // 등록 준비 저장은 **정말로** 차감하지 않는다. 그 말까지 지우면
        // 사용자가 저장만 해도 조각이 빠지는 줄 안다.
        for path in [
            "ggumirror/Store/PublishMirrorView.swift",
            "ggumirror/Store/PublishStickerView.swift",
        ] {
            #expect(try qaSource(path).contains("조각도 차감되지 않았어요"), "\(path)")
        }
    }
}

@Suite("이름 없이 상점에 올릴 수 없다")
struct SellerNameRequiredTests {

    @Test("이름이 없으면 서버에 보내지 않는다")
    func publishStopsBeforeTheNetwork() throws {
        for path in [
            "ggumirror/Store/PublishMirrorView.swift",
            "ggumirror/Store/PublishStickerView.swift",
        ] {
            let code = try qaSource(path)
            let publish = try #require(code.range(of: "private func publish() async {"))
            let body = String(code[publish.upperBound...])

            let gate = try #require(body.range(of: "profile?.profile?.hasName == true"))
            let request = try #require(body.range(of: "await marketplace.publish("))
            // 관문이 요청보다 앞이다 — 이름 없이 snapshot을 올리지 않는다.
            #expect(gate.lowerBound < request.lowerBound, "\(path)")
            // 관문에 걸리면 이름 시트를 연다.
            #expect(body.contains("isNamingSeller = true"), "\(path)")
        }
    }

    @Test("이름 시트가 서버를 authority로 쓴다")
    func theSheetTrustsTheServer() throws {
        let sheet = try qaSource("ggumirror/Store/SellerNameSheet.swift")
        // 저장은 서버를 지난다 — client가 "찾아보니 없더라"로 정하지 않는다.
        #expect(sheet.contains("profile?.setDisplayName(name, session: session.server)"))
        // 서버가 받아 준 뒤에만 닫는다.
        let save = try #require(sheet.range(of: "private func save() async {"))
        let body = String(sheet[save.upperBound...].prefix(400))
        let failure = try #require(body.range(of: "problem = failure"))
        let dismissed = try #require(body.range(of: "dismiss()"))
        #expect(failure.lowerBound < dismissed.lowerBound)
        // 길이 규칙은 기존 정책에서 온다 — 새 숫자를 적지 않는다.
        #expect(sheet.contains("DisplayNamePolicy.maxLength"))
        #expect(!sheet.contains("count > 20"))
    }

    @Test("겹친 이름을 사용자 말로 알린다")
    func duplicateNamesGetTheirOwnMessage() {
        #expect(DisplayNameFailure.taken.message == "이미 사용 중인 이름이에요.")
        // 30일 규칙과 다른 말이다 — 뭉치면 사용자가 무엇을 고쳐야 할지 모른다.
        #expect(DisplayNameFailure.taken != DisplayNameFailure.cooldown)
        #expect(DisplayNameFailure.cooldown.message.contains("30일"))
    }

    @Test("겹친 상품 이름도 자기 말이 있다")
    func duplicateTitlesGetTheirOwnMessage() {
        #expect(MarketplaceFailure.titleTaken.message == "이미 사용 중인 상품 이름이에요.")
        // 다시 시도해도 같은 답이므로 "잠시 뒤"라고 말하지 않는다.
        #expect(!MarketplaceFailure.titleTaken.isTemporary)
        #expect(MarketplaceFailure.from(
            status: 409,
            data: Data(#"{"detail":"listing title is already taken"}"#.utf8)
        ) == .titleTaken)
    }

    @Test("이름이 겹쳐 실패하면 local 이름도 그대로다")
    func aRefusedPublishKeepsTheLocalName() throws {
        // 직전 phase의 계약이 그대로다 — 실패 guard가 rename보다 앞이다.
        for (path, rename) in [
            ("ggumirror/Store/PublishMirrorView.swift", "library.rename(mirror.id, to: title)"),
            ("ggumirror/Store/PublishStickerView.swift", "library.rename(project.id, to: title)"),
        ] {
            let code = try qaSource(path)
            let failure = try #require(code.range(of: "guard let result else {"))
            let renamed = try #require(code.range(of: rename))
            #expect(failure.lowerBound < renamed.lowerBound, "\(path)")
        }
    }
}
