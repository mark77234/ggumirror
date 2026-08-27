//
//  OverlayHardeningTests.swift
//  ggumirrorTests
//
//  모달이 **화면 좌표**에 뜨는지, 키보드가 닫히는지, 보관 한도가 origin을 가리지
//  않는지를 고정한다.
//
//  실기기에서 난 일: 상점을 아래로 내린 상태에서 삭제를 누르면 확인 창이 화면 밖
//  (스크롤 내용 기준 위쪽)에 그려졌고, 등록 시트의 `상점에 올리기`는 탭바에 가렸다.
//  둘 다 `.overlay`가 **붙은 view의 좌표계**에 그리기 때문이었다.
//

import Testing
import Foundation
@testable import ggumirror

private func overlaySource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "ggumirror")
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

@Suite("모달은 화면 좌표에 뜬다")
struct InkModalPresentationTests {

    @Test("시트와 다이얼로그가 같은 표현 경로 하나를 쓴다")
    func bothGoThroughOnePresentation() throws {
        let code = try overlaySource("Shared/InkModal.swift")
        // 화면(window)에 표현한다.
        #expect(code.contains("fullScreenCover(isPresented: $isPresented, onDismiss:"))
        #expect(code.contains("presentationBackground(.clear)"))
        // 시트 · 다이얼로그 **둘 다** 이 하나를 지난다(정의는 제네릭이라 따로 센다).
        #expect(code.components(separatedBy: ".inkModalPresentation(").count - 1 == 2)
        #expect(code.contains("func inkModalPresentation<Modal: View>("))
    }

    @Test("모달을 `.overlay`로 그리지 않는다")
    func noOverlayPresentation() throws {
        let code = try overlaySource("Shared/InkModal.swift")
        // `.overlay`는 붙은 view의 좌표계다 — ScrollView 안에서 열면 화면 밖에 그려진다.
        #expect(!code.contains(".overlay {"))
    }

    @Test("탭바를 감추던 우회가 사라졌다")
    func tabBarWorkaroundIsGone() throws {
        // cover는 탭바보다 위에 표현되므로 preference로 탭바를 감출 필요가 없다.
        for path in ["Shared/InkModal.swift", "Home/HomeView.swift"] {
            let code = try overlaySource(path)
            #expect(!code.contains("inkHiddenWhileModalPresented"))
            #expect(!code.contains("InkModalPresentedKey"))
        }
    }

    @Test("시트를 닫으면서 같은 순간에 다음 것을 열지 않는다")
    func handoffsWaitForDismissal() throws {
        // cover는 window 표현이라, 닫히는 중에 다음 것을 띄우면 조용히 버려질 수 있다.
        // 버튼을 눌렀는데 아무 일도 안 일어나는 것으로 보인다.
        let modal = try overlaySource("Shared/InkModal.swift")
        #expect(modal.contains("fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss)"))

        for path in [
            "Editor/StickerCreatorView.swift",   // AI 시트 → 조각 상점
            "Editor/EditorView.swift",           // 스티커 고르기 → 만들기 → Creator
            "Store/StickerStoreView.swift",      // 만들기 → Creator
            "MyMirrors/MyMirrorsView.swift",     // 새 거울 → 가져오기
        ] {
            #expect(try overlaySource(path).contains("onDismiss: {"), "\(path)")
        }
    }

    @Test("시트 높이는 화면 높이에서만 나온다")
    func sheetHeightIsClampedToTheViewport() {
        let screen: CGFloat = 800
        #expect(InkSheetSize.content.maxHeight(in: screen) <= screen)
        #expect(InkSheetSize.fraction(0.92).maxHeight(in: screen) <= screen)
        // 1.0을 넘겨도 화면을 넘지 않는다.
        #expect(InkSheetSize.fraction(2).maxHeight(in: screen) <= screen)
    }

    @Test("등록 시트의 실행 버튼은 스크롤 밖에 고정된다")
    func publishActionsStayOutsideTheScroll() throws {
        for path in ["Store/PublishMirrorView.swift", "Store/PublishStickerView.swift"] {
            let code = try overlaySource(path)
            #expect(code.contains("inkSheetActions"))
        }
    }
}

@Suite("키보드는 닫힌다")
struct InkKeyboardTests {

    @Test("입력이 있는 시트는 스크롤로도 빈 곳 탭으로도 닫는다")
    func inputSheetsDismissTheKeyboard() throws {
        for path in [
            "Store/PublishMirrorView.swift",
            "Store/PublishStickerView.swift",
            "Home/ProfileView.swift",
            "AI/AIStickerPromptSheet.swift",
        ] {
            let code = try overlaySource(path)
            #expect(code.contains("scrollDismissesKeyboard(.interactively)"), "\(path)")
            #expect(code.contains("inkDismissesKeyboardOnTap()"), "\(path)")
        }
    }

    @Test("탭으로 닫는 층은 내용 **뒤**에 깔린다")
    func tapLayerSitsBehindContent() throws {
        let code = try overlaySource("Shared/InkKeyboard.swift")
        // 앞에 겹치거나 simultaneousGesture로 붙이면 입력 칸을 누르는 순간
        // 방금 올라온 키보드를 도로 내리는 경주가 생긴다.
        #expect(code.contains("background {"))
        #expect(!code.contains("simultaneousGesture"))
        #expect(!code.contains("overlay {"))
    }
}

@MainActor
@Suite("이미 받은 내장 템플릿")
struct OwnedTemplateCTATests {

    @Test("이미 있으면 받기 버튼이 잠긴다")
    func ownedTemplateDisablesTheCTA() throws {
        let code = try overlaySource("Store/TemplateDetailView.swift")
        // id로 판단한다. 제목으로 맞추지 않는다.
        #expect(code.contains("library?.mirrors.contains { $0.id == template.id }"))
        #expect(!code.contains("$0.name == template.name"))
        // 문구와 잠금은 이제 사용자 상품과 공유하는 상태 모델이 정한다.
        #expect(code.contains("MirrorAcquireCTA.state("))
        #expect(code.contains("existsLocally: isOwned"))
        #expect(code.contains(".disabled(!cta.isEnabled)"))
        #expect(MirrorAcquireCTA.state(price: 0, isSignedIn: true, existsLocally: true)
                .title == "이미 내 거울에 있어요")
    }

    @Test("같은 템플릿을 두 번 받아도 하나다")
    func acquiringTwiceKeepsOne() {
        let library = MirrorLibrary()
        let template = StoreCatalog.basics[0]
        let first = library.acquire(template)
        let second = library.acquire(template)
        #expect(first?.id == second?.id)
        #expect(library.storedCount == 1)
    }
}

@MainActor
@Suite("거울 보관 한도")
struct MirrorCapacityTests {

    @Test("무료 한도는 5이고 origin을 가리지 않는다")
    func freeCapacityCountsEverything() {
        #expect(MirrorStoragePolicy.freeMirrorSlots == 5)
        let library = MirrorLibrary()
        // 서버에 닿기 전에는 무료 기본값이다. 산 칸은 서버가 알려준다.
        #expect(library.mirrorCapacity == 5)

        // 받은 것 3개 + 만든 것 2개 = 5. 종류를 가리지 않는다.
        for template in StoreCatalog.basics.prefix(3) { _ = library.acquire(template) }
        _ = library.save(.blank, name: "가", context: .createNew)
        _ = library.save(.blank, name: "나", context: .createNew)
        #expect(library.storedCount == 5)
        #expect(!library.hasFreeMirrorSlot)
    }

    @Test("가득 차면 모든 담는 길이 막힌다")
    func everyAddPathIsBlockedWhenFull() {
        let library = MirrorLibrary()
        while library.hasFreeMirrorSlot {
            _ = library.save(.blank, name: "거울", context: .createNew)
        }
        let full = library.storedCount

        // 1. 만들기
        #expect(library.save(.blank, name: "하나 더", context: .createNew) == .needsMoreSlots)
        // 2. 내장 템플릿 받기
        #expect(library.acquire(StoreCatalog.basics[0]) == nil)
        // 3. 상점에서 받은 거울 담기
        let bought = MyMirror(
            id: "bought-1", name: "산 거울", origin: .purchased,
            style: StoreCatalog.basics[0].style
        )
        #expect(library.adopt(bought) == nil)

        // **아무것도 지우지 않았다.**
        #expect(library.storedCount == full)
    }

    @Test("이미 가진 것은 자리를 새로 쓰지 않는다")
    func alreadyOwnedDoesNotNeedASlot() {
        let library = MirrorLibrary()
        let template = StoreCatalog.basics[0]
        _ = library.acquire(template)
        while library.hasFreeMirrorSlot {
            _ = library.save(.blank, name: "거울", context: .createNew)
        }
        // 가득 찼지만 이미 가진 것을 다시 받는 것은 통과한다.
        #expect(library.acquire(template)?.id == template.id)
    }

    @Test("가득 찬 안내는 **가격을 적어 두지 않는다**")
    func storageFullDialogNeverHardcodesPrice() throws {
        let code = try overlaySource("Shared/MirrorStorageFullDialog.swift")
        #expect(code.contains("\"거울 보관 공간이 가득 찼어요\""))
        // 이제 실제로 조각을 쓴다(Mirror Capacity Purchase). 다만 숫자는 **서버가 준 값**이고
        // 앱에 적어 두지 않는다 — 서버가 가격을 바꾸면 화면이 거짓말을 하게 된다.
        #expect(code.contains("costShards"), "서버가 준 가격을 쓰지 않는다")
        #expect(code.contains("slotDelta"), "서버가 준 칸 수를 쓰지 않는다")
        for guessed in ["10조각", "5칸", "costShards: 10", "slotDelta: 5"] {
            #expect(!code.contains(guessed), "가격을 적어 두었다: \(guessed)")
        }
    }

    @Test("보관 한도 안내는 한 곳에서만 나온다")
    func everyFullPathUsesTheSameDialog() throws {
        for path in [
            "MyMirrors/MyMirrorsView.swift",
            "Editor/EditorView.swift",
            "Store/TemplateDetailView.swift",
        ] {
            let code = try overlaySource(path)
            #expect(code.contains("inkMirrorStorageFullDialog"), "\(path)")
        }
    }

    @Test("상점에서 받기는 내려받기 전에 막힌다")
    func marketplaceImportChecksBeforeDownloading() throws {
        let code = try overlaySource("Store/MarketplaceImport.swift")
        let gate = try #require(code.range(of: "MarketplaceImportFailure.mirrorStorageFull"))
        let download = try #require(code.range(of: "let manifest = try await download("))
        #expect(gate.lowerBound < download.lowerBound)
    }

    @Test("보관 한도는 **로컬 저장 규칙**이지 원장 계산이 아니다")
    func capacityIsNotComputedFromTheLedger() throws {
        let code = try overlaySource("Shared/MirrorStorageFullDialog.swift")
        // 지갑은 **서버가 준 잔액을 옮겨 적을 때만** 쓴다. 여기서 계산하지 않는다.
        #expect(!code.contains("ShardReason"))
        #expect(!code.contains("balance -"))
        #expect(!code.contains("balance +"))

        // 담을 수 있는 칸도 client가 **계산하지 않는다.** 값이 바뀌는 경우는 둘뿐이다:
        // 서버 값을 옮겨 적을 때와, 계정이 바뀌어 무료 기본값으로 되돌릴 때.
        let library = try overlaySource("Shared/MirrorSampleData.swift")
        #expect(!library.contains("mirrorCapacity +="))
        #expect(!library.contains("mirrorCapacity -="))
        #expect(library.contains("mirrorCapacity = effectiveSlots"))
        #expect(library.contains("mirrorCapacity = MirrorStoragePolicy.freeMirrorSlots"))
        #expect(library.components(separatedBy: "mirrorCapacity = ").count - 1 == 2)
    }
}

@Suite("좋아요는 눈에 띈다")
struct LikeVisibilityTests {

    @Test("누른 상태가 칩 전체로 드러난다")
    func likedStateInvertsTheChip() throws {
        // 카드를 하나로 합치면서 스티커 전용 칩이 사라졌다. 그 칩이 있었던 이유
        // (caption 크기에서 빈 하트와 찬 하트의 차이가 너무 미묘하다)는 색으로 살렸다 —
        // 눌리면 속이 찬 하트 + 진한 먹지가 된다.
        let code = try overlaySource("Store/StoreMirrorCard.swift")
        #expect(code.contains("like.isLiked ? \"heart.fill\" : \"heart\""))
        #expect(code.contains("like.isLiked ? PaperTheme.ink : PaperTheme.secondaryInk"))
        // 손이 닿는 자리는 그대로 44pt다.
        #expect(code.contains("minWidth: InkTapTarget.minimum"))
        #expect(InkTapTarget.minimum == 44)
    }
}
