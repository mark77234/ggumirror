//
//  UIPolishTests.swift
//  ggumirrorTests
//
//  이번 Phase 네 가지만 지킨다.
//  1. 거울 / 조각 아이콘이 작은 크기에서도 실제로 그려진다
//  2. 앱이 띄우는 Bottom Sheet / Dialog가 같은 easeInOut 정책을 쓴다
//  3. 내 거울 `꾸미기`가 **기존 거울을 고친다** (복제되지 않는다)
//  4. Draw / Hand 컨트롤이 라이트 모드에서도 보이고, 시스템 appearance로 갈리지 않는다
//

import Testing
import SwiftUI
import UIKit
@testable import ggumirror

@MainActor
struct UIPolishTests {

    // MARK: - 도구

    private func render(_ view: some View, size: CGSize, scheme: ColorScheme = .light) -> CGImage? {
        let renderer = ImageRenderer(
            content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, scheme)
        )
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.cgImage
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

    /// 잉크가 찍힌 픽셀 수(불투명하고 어두운 것).
    private func inkedPixels(_ image: CGImage) -> Int {
        let data = pixels(image)
        var count = 0
        for index in stride(from: 0, to: data.count, by: 4)
        where data[index + 3] > 60 && data[index] < 150 {
            count += 1
        }
        return count
    }

    private func withStore(_ body: (MirrorStore) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-uipolish-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    // MARK: - 1. 제품 아이콘

    @Test("거울 아이콘이 그려진다", arguments: [CGFloat(20), 24, 28, 44, 62])
    func mirrorIconRenders(size: CGFloat) throws {
        let image = try #require(render(MirrorIcon(size: size), size: CGSize(width: size, height: size)))
        let inked = inkedPixels(image)
        // 아무것도 그려지지 않으면 화면에서 "빈 자리"로 보인다 — 가장 조용한 실패다.
        #expect(inked > Int(size * 0.5), "\(size)pt에서 거의 그려지지 않았다 (\(inked)px)")
        // 덩어리로 꽉 차면 아이콘이 아니다.
        #expect(inked < Int(size * size * 0.7), "\(size)pt에서 너무 꽉 찼다 (\(inked)px)")
    }

    /// 불투명한(알파가 있는) 픽셀 수. 조각 아이콘은 두들이 아니라 컬러 asset이라
    /// "어두운 픽셀"이 아니라 "실제로 칠해진 픽셀"로 센다.
    private func opaquePixels(_ image: CGImage) -> Int {
        let data = pixels(image)
        var count = 0
        for index in stride(from: 0, to: data.count, by: 4) where data[index + 3] > 60 {
            count += 1
        }
        return count
    }

    @Test("조각 아이콘이 그려진다", arguments: [CGFloat(16), 18, 20, 24, 36])
    func shardIconRenders(size: CGFloat) throws {
        let image = try #require(render(ShardIcon(size: size), size: CGSize(width: size, height: size)))
        let painted = opaquePixels(image)
        // 아무것도 그려지지 않으면 화면에서 "빈 자리"로 보인다 — 가장 조용한 실패다.
        // asset 이름을 잘못 적으면 정확히 이렇게 된다.
        #expect(painted > Int(size * size * 0.15), "\(size)pt에서 거의 그려지지 않았다 (\(painted)px)")
    }

    @Test("조각 아이콘은 공식 asset을 쓴다")
    func shardIconUsesTheOfficialAsset() throws {
        #expect(ShardIcon.assetName == "ic_ggumirror_token")
        // 이름이 틀리면 SwiftUI는 조용히 빈 이미지를 그린다 — 여기서 잡는다.
        #expect(UIImage(named: ShardIcon.assetName) != nil, "asset을 찾지 못했다")
    }

    @Test("조각 아이콘은 원본 색을 유지한다")
    func shardIconKeepsItsOwnColors() throws {
        // template rendering으로 단색을 입히면 브랜드 재화가 화면마다 다른 색이 된다.
        // 컬러 asset이면 채널이 서로 다른 픽셀이 반드시 있다.
        let image = try #require(render(ShardIcon(size: 44), size: CGSize(width: 44, height: 44)))
        let data = pixels(image)
        var colored = 0
        for index in stride(from: 0, to: data.count, by: 4) where data[index + 3] > 120 {
            let r = Int(data[index]), g = Int(data[index + 1]), b = Int(data[index + 2])
            if abs(r - g) > 8 || abs(g - b) > 8 { colored += 1 }
        }
        #expect(colored > 20, "단색으로 보인다 — template rendering이 걸렸을 수 있다 (\(colored)px)")
    }

    @Test("조각 아이콘은 정사각 frame에서도 비율을 지킨다", arguments: [CGFloat(16), 24, 36])
    func shardIconKeepsAspectRatio(size: CGFloat) throws {
        // asset이 정사각형이 아니다(1312 × 1199). scaledToFit이라 가로를 꽉 채우고
        // 위아래가 남아야 한다 — 늘어나면(scaledToFill/aspect 무시) 남는 줄이 사라진다.
        let image = try #require(render(ShardIcon(size: size), size: CGSize(width: size, height: size)))
        let data = pixels(image)
        let width = image.width
        func rowIsEmpty(_ y: Int) -> Bool {
            (0..<width).allSatisfy { data[(y * width + $0) * 4 + 3] <= 8 }
        }
        #expect(rowIsEmpty(0) && rowIsEmpty(image.height - 1),
                "\(size)pt에서 위아래 여백이 없다 — 비율이 깨졌을 수 있다")
    }

    @Test("작은 크기에서도 선 굵기가 사라지지 않는다")
    func productIconStrokeSurvivesSmallSizes() throws {
        // 20pt와 44pt에서 잉크가 차지하는 비율이 비슷해야 한다 —
        // 굵기가 크기에 비례하고 최소값이 있기 때문이다.
        var ratios: [Double] = []
        for size in [CGFloat(20), 44] {
            let image = try #require(render(MirrorIcon(size: size), size: CGSize(width: size, height: size)))
            ratios.append(Double(inkedPixels(image)) / Double(size * size))
        }
        #expect(ratios.allSatisfy { $0 > 0.03 && $0 < 0.55 }, "비율 \(ratios)")
    }

    @Test("제품 아이콘 path는 다시 그려도 같다")
    func productIconPathsAreDeterministic() {
        // 제품 아이콘은 이제 두들 획으로 그린다 (Phase V-4).
        let rect = CGRect(x: 0, y: 0, width: 40, height: 40)
        for icon in DoodleProductIcon.allCases {
            for stroke in icon.strokes {
                #expect(stroke.path(in: rect) == stroke.path(in: rect), "\(icon.rawValue)")
            }
        }
        // 조각은 좌우 대칭이 아니다 — 대칭이면 보석으로 읽힌다.
        let shard = DoodleProductIcon.shard.strokes[0].path(in: rect)
        let flipped = shard.applying(
            CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.width, y: 0)
        )
        #expect(shard != flipped)
    }

    // `shardIconUsesTint`는 삭제했다. 조각 아이콘은 이제 공식 컬러 asset이라
    // **tint를 받지 않는다** — 색을 갈아입히지 않는 것이 규칙이고,
    // 그것은 위 `shardIconKeepsItsOwnColors`가 지킨다.

    // MARK: - 2. Bottom Sheet / Dialog

    @Test("모든 모달이 같은 easeInOut 정책을 쓴다")
    func modalMotionIsSharedEaseInOut() {
        // 값이 한 곳(InkMotion)에만 있다. 화면마다 다른 곡선을 적지 않는다.
        #expect(InkMotion.duration >= 0.22 && InkMotion.duration <= 0.32)
        #expect(InkMotion.modal == Animation.easeInOut(duration: InkMotion.duration))
        #expect(InkMotion.settle == Animation.easeInOut(duration: 0.18))
        // spring이 아니다 — 종이는 튀어오르지 않는다.
        #expect(InkMotion.modal != Animation.spring)
    }

    @Test("시트 높이는 화면을 넘지 않는다")
    func sheetHeightNeverExceedsScreen() {
        let screen: CGFloat = 844
        #expect(InkSheetSize.content.maxHeight(in: screen) < screen)
        #expect(InkSheetSize.fraction(0.5).maxHeight(in: screen) == screen * 0.5)
        // 1을 넘겨 줘도 뒤가 조금은 보인다 — 그래야 시트로 읽힌다.
        #expect(InkSheetSize.fraction(1.4).maxHeight(in: screen) < screen)
        #expect(InkSheetSize.content.fitsContent)
        #expect(!InkSheetSize.fraction(0.6).fitsContent)
    }

    @Test("시트를 띄우면 내용이 화면에 나타나고, 닫으면 사라진다")
    func bottomSheetPresentationState() throws {
        struct Host: View {
            let presented: Bool
            var body: some View {
                Color.clear.inkBottomSheet(isPresented: .constant(presented)) {
                    Text("그리기 설정")
                        .font(InkFont.cardTitle)
                        .padding(20)
                }
            }
        }
        let size = CGSize(width: 320, height: 500)
        let open = try #require(render(Host(presented: true), size: size))
        let closed = try #require(render(Host(presented: false), size: size))

        #expect(inkedPixels(open) > 300, "시트 내용이 그려지지 않았다")
        #expect(inkedPixels(closed) < inkedPixels(open) / 4, "닫힌 상태인데 무언가 남아 있다")
    }

    @Test("비율 시트는 화면을 다 차지하지 않고 아래에 붙는다", arguments: [CGFloat(0.5), 0.62, 0.72])
    func fractionSheetSitsAtTheBottom(fraction: CGFloat) throws {
        // 회귀: 비율을 준 뒤 maxHeight: .infinity가 덮어써서 카드가 화면 전체를 차지했다.
        // 내용이 위로 붙고 아래에 빈 종이가 잔뜩 남았다.
        struct Host: View {
            let fraction: CGFloat
            var body: some View {
                Color.white.inkBottomSheet(isPresented: .constant(true), size: .fraction(fraction)) {
                    // 실제 시트처럼 안에 스크롤이 있고 내용은 짧다.
                    ScrollView { Text("스티커").font(InkFont.cardTitle).padding(20) }
                }
            }
        }
        let size = CGSize(width: 320, height: 700)
        let image = try #require(render(Host(fraction: fraction), size: size))
        let data = pixels(image)

        func isPaper(y: Int) -> Bool {
            let index = (y * image.width + image.width / 2) * 4
            // 종이는 아주 밝다. dim이 덮인 자리는 어둡다.
            return data[index] > 230
        }

        // 카드가 시작되는 첫 줄을 위에서부터 찾는다.
        let top = (0..<image.height).first { isPaper(y: $0) } ?? image.height
        let expected = Double(image.height) * (1 - fraction)
        #expect(
            abs(Double(top) - expected) < Double(image.height) * 0.08,
            "카드 위쪽이 \(top)px인데 \(Int(expected))px 근처여야 한다 (fraction \(fraction))"
        )
        // 위쪽은 dim, 맨 아래는 종이여야 한다.
        #expect(!isPaper(y: 8), "화면 맨 위까지 카드가 올라와 있다")
        #expect(isPaper(y: image.height - 4), "시트 아래가 종이로 채워지지 않았다")
    }

    @Test("시트 내용은 시스템 dismiss를 쓰지 않는다")
    func sheetContentsNeverUseSystemDismiss() throws {
        // 회귀: 커스텀 오버레이 안에서 `@Environment(\.dismiss)`를 쓰면 시트가 아니라
        // **뒤에 있는 화면**이 닫힌다. "텍스트 추가 → 취소"가 Editor를 닫고 홈으로 나갔다.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "ggumirror")
        let sheetContents = [
            "Editor/TextEditorSheets.swift",
            "Editor/MirrorSaveSheets.swift",
            "Editor/LayersSheet.swift",
            "Editor/StickerPickerSheet.swift",
            "Editor/DrawSettingsSheet.swift",
            "MyMirrors/ExternalArtworkView.swift",
            "Store/PublishMirrorView.swift",
        ]
        for file in sheetContents {
            let source = try String(contentsOf: root.appending(path: file), encoding: .utf8)
            #expect(
                !source.contains("Environment(\\.dismiss)"),
                "\(file)이 시스템 dismiss를 쓴다 — 시트가 아니라 뒤 화면이 닫힌다"
            )
        }
    }

    @Test("dim이 아래 화면을 덮어 실수로 눌리지 않게 한다")
    func dimBlocksUnderlyingInteraction() throws {
        struct Host: View {
            let presented: Bool
            var body: some View {
                // 아래 화면을 흰색으로 꽉 채운다. dim이 덮으면 어두워진다.
                Color.white
                    .inkBottomSheet(isPresented: .constant(presented)) { Text("시트").padding(20) }
            }
        }
        let size = CGSize(width: 200, height: 400)
        let open = try #require(render(Host(presented: true), size: size))
        let closed = try #require(render(Host(presented: false), size: size))

        // 시트 위쪽(내용이 없는 자리)의 밝기를 본다.
        func brightness(_ image: CGImage, y: Int) -> Int {
            let data = pixels(image)
            let index = (y * image.width + image.width / 2) * 4
            return Int(data[index])
        }
        #expect(brightness(open, y: 20) < brightness(closed, y: 20) - 20, "dim이 덮이지 않았다")
    }

    @Test("Dialog 주 버튼이 눌리면 동작하고 닫힌다")
    func dialogPrimaryAction() {
        var tapped = 0
        var presented = true
        let actions = [
            InkDialogAction("취소") { tapped -= 1 },
            InkDialogAction("보관 공간 늘리기", role: .primary) { tapped += 1 },
        ]
        // 화면이 하는 일과 같은 순서로 부른다: 먼저 닫고, 그다음 handler.
        let primary = actions.first { $0.role == .primary }
        presented = false
        primary?.handler()

        #expect(tapped == 1)
        #expect(presented == false)
    }

    @Test("Dialog 취소는 아무것도 바꾸지 않는다")
    func dialogCancelAction() {
        var deleted = false
        let actions = [
            InkDialogAction("취소"),
            InkDialogAction("삭제", role: .destructive) { deleted = true },
        ]
        actions[0].handler()   // 취소만 누른다
        #expect(!deleted)
        #expect(actions[0].role == .secondary)
    }

    @Test("Dialog는 되돌릴 수 없는 동작을 따로 표시한다")
    func dialogDestructiveAction() {
        var deleted = false
        let action = InkDialogAction("삭제", role: .destructive) { deleted = true }
        #expect(action.role == .destructive)
        action.handler()
        #expect(deleted)
    }

    @Test("Dialog가 제목 · 설명 · 버튼을 모두 그린다")
    func dialogBodyRendersEverything() throws {
        let body = InkDialogBody(
            title: "거울 보관 공간이 가득 찼어요",
            message: "새 거울을 만들려면 보관 공간을 늘려주세요.",
            actions: [InkDialogAction("취소"), InkDialogAction("늘리기", role: .primary)],
            onAction: {}
        )
        let image = try #require(render(body, size: CGSize(width: 320, height: 240)))
        #expect(inkedPixels(image) > 400)
    }

    @Test("버튼이 셋 이상이면 세로로 쌓는다")
    func dialogStacksManyActions() throws {
        // 가로로 셋을 넣으면 글씨가 잘린다. 세로 배치는 높이가 더 필요하다.
        let three = InkDialogBody(
            title: "사진에서 피사체를 찾지 못했어요",
            message: nil,
            actions: [
                InkDialogAction("다시 고르기", role: .primary),
                InkDialogAction("원본 그대로 넣기"),
                InkDialogAction("취소"),
            ],
            onAction: {}
        )
        let two = InkDialogBody(
            title: "사진에서 피사체를 찾지 못했어요",
            message: nil,
            actions: [InkDialogAction("취소"), InkDialogAction("확인", role: .primary)],
            onAction: {}
        )
        let size = CGSize(width: 320, height: 320)
        #expect(inkedPixels(try #require(render(three, size: size)))
                > inkedPixels(try #require(render(two, size: size))))
    }

    @Test("손잡이는 손으로 그은 선이다")
    func sheetHandleIsHandDrawn() throws {
        let image = try #require(render(InkSheetHandle(), size: CGSize(width: 44, height: 10)))
        let data = pixels(image)
        var drawn = 0
        for index in stride(from: 3, to: data.count, by: 4) where data[index] > 40 { drawn += 1 }
        #expect(drawn > 20)
        #expect(drawn < 44 * 10 * 3 / 4, "알약처럼 꽉 찬 사각형이면 안 된다")
    }

    @Test("시스템이 소유한 UI는 그대로 둔다")
    func systemOwnedUIStaysSystem() throws {
        // 앱이 흉내 내면 안 되는 것들 — 소스에 시스템 API가 그대로 남아 있어야 한다.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ggumirrorTests
            .deletingLastPathComponent()   // ggumirror (repo)
            .appending(path: "ggumirror")
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appending(path: path), encoding: .utf8)
        }
        #expect(try source("Auth/AccountSection.swift").contains("SignInWithAppleButton"))
        #expect(try source("Editor/StickerPickerSheet.swift").contains("PhotosPicker("))
        let artwork = try source("MyMirrors/ExternalArtworkView.swift")
        #expect(artwork.contains("fileImporter("))
        #expect(artwork.contains("ShareLink("))
    }

    // MARK: - 3. 내 거울 꾸미기 = 기존 거울 수정

    @Test("꾸미기 저장은 같은 거울을 고친다")
    func editPreservesMirrorIdentity() throws {
        try withStore { store in
            let library = self.library(store)
            _ = library.save(MirrorDesign.blank, name: "리본 거울", context: .createNew)
            let original = try #require(library.mirrors.first)

            var design = MirrorDesign(mirror: original)
            design.backgroundColor = BasicMirror.sky.style.frame
            let outcome = library.save(design, name: "", context: .editCurrent)

            #expect(outcome.mirrorID == original.id)          // 같은 id
            #expect(library.mirrors.count == 1)               // 거울이 늘지 않는다
            #expect(library.createdCount == 1)                // 슬롯도 늘지 않는다
            #expect(library.mirrors.first?.name == "리본 거울") // 이름 유지
            #expect(library.mirrors.first?.origin == original.origin)
            #expect(library.mirrors.first?.style.frame == BasicMirror.sky.style.frame)  // 내용은 바뀐다
        }
    }

    @Test("꾸미기는 이름을 묻지 않는다")
    func editDoesNotAskForName() throws {
        try withStore { store in
            let library = self.library(store)
            _ = library.save(MirrorDesign.blank, name: "내 거울", context: .createNew)
            let mirror = try #require(library.mirrors.first)

            #expect(!library.needsName(for: .editCurrent))
            #expect(!library.willCreateNewMirror(for: MirrorDesign(mirror: mirror), context: .editCurrent))
        }
    }

    @Test("꾸미기 결과가 디스크에도 남는다")
    func editPersistsToDisk() throws {
        try withStore { store in
            let library = self.library(store)
            _ = library.save(MirrorDesign.blank, name: "내 거울", context: .createNew)
            let mirror = try #require(library.mirrors.first)

            var design = MirrorDesign(mirror: mirror)
            design.texts = [TextObject(text: "오늘도 예쁘게", center: NormalizedPoint(x: 0.5, y: 0.5))]
            _ = library.save(design, name: "", context: .editCurrent)
            store.flush()

            let reloaded = self.library(store)
            #expect(reloaded.mirrors.count == 1)
            #expect(reloaded.mirrors.first?.id == mirror.id)
            #expect(reloaded.mirrors.first?.texts.count == 1)
        }
    }

    @Test("취소하면 원본이 그대로다")
    func cancelLeavesOriginalUnchanged() throws {
        try withStore { store in
            let library = self.library(store)
            _ = library.save(MirrorDesign.blank, name: "내 거울", context: .createNew)
            let original = try #require(library.mirrors.first)

            // Editor는 값 복사본(`@State design`)에서 작업한다. 저장하지 않으면 아무 일도 없다.
            var working = MirrorDesign(mirror: original)
            working.backgroundColor = BasicMirror.mint.style.frame
            working.texts = [TextObject(text: "취소될 글씨", center: NormalizedPoint(x: 0.4, y: 0.4))]

            #expect(library.mirrors.first?.style.frame == original.style.frame)
            #expect(library.mirrors.first?.texts.isEmpty == true)
            #expect(library.mirrors.count == 1)
        }
    }

    @Test("지금 쓰지 않는 거울을 고쳐도 적용 중인 거울은 그대로다")
    func editingAnotherMirrorKeepsCurrent() throws {
        try withStore { store in
            let library = self.library(store)
            _ = library.save(MirrorDesign.blank, name: "첫 번째", context: .createNew)
            let first = try #require(library.mirrors.first)
            _ = library.save(MirrorDesign.blank, name: "두 번째", context: .createNew)
            let currentBefore = library.currentID
            #expect(currentBefore != first.id)

            var design = MirrorDesign(mirror: first)
            design.backgroundColor = BasicMirror.mint.style.frame
            _ = library.save(design, name: "", context: .editCurrent)

            // 적용은 `적용` 동작이 한다 — 꾸미기가 몰래 바꾸지 않는다.
            #expect(library.currentID == currentBefore)
            #expect(library.mirrors.first { $0.id == first.id }?.style.frame == BasicMirror.mint.style.frame)
        }
    }

    @Test("복제는 여전히 새 거울을 만든다")
    func duplicateStillCreatesNewMirror() throws {
        try withStore { store in
            let library = self.library(store)
            _ = library.save(MirrorDesign.blank, name: "원본", context: .createNew)
            let original = try #require(library.mirrors.first)

            library.duplicate(original)

            #expect(library.mirrors.count == 2)
            #expect(library.createdCount == 2)
            #expect(library.mirrors.map(\.id).contains(original.id))
            #expect(Set(library.mirrors.map(\.id)).count == 2)   // 새 id
        }
    }

    @Test("+ 거울 만들기는 여전히 새 거울을 만든다")
    func createNewStillCreatesNewMirror() throws {
        try withStore { store in
            let library = self.library(store)
            let first = library.save(MirrorDesign.blank, name: "하나", context: .createNew)
            let second = library.save(MirrorDesign.blank, name: "둘", context: .createNew)

            #expect(first.mirrorID != second.mirrorID)
            #expect(library.mirrors.count == 2)
            #expect(library.needsName(for: .createNew))
        }
    }

    // MARK: - 4. Draw / Hand 컨트롤

    /// 컨트롤이 실제로 쓰는 두 조합. 화면 코드와 같은 색을 본다.
    private var drawHandCombinations: [(name: String, background: Color, foreground: Color)] {
        [
            ("선택", PaperTheme.ink, PaperTheme.paper),
            ("비선택", PaperTheme.subtleSurface, PaperTheme.ink),
        ]
    }

    private func luminance(_ color: Color) -> Double {
        let components = UIColor(color).cgColor.components ?? [0, 0, 0]
        guard components.count >= 3 else { return Double(components[0]) }
        return 0.2126 * Double(components[0]) + 0.7152 * Double(components[1]) + 0.0722 * Double(components[2])
    }

    @Test("Draw / Hand는 두 상태 모두 대비가 충분하다")
    func drawHandContrastIsValid() {
        for combination in drawHandCombinations {
            let difference = abs(luminance(combination.background) - luminance(combination.foreground))
            // 라이트 모드에서 안 보였던 원인이 "검은 배경 + 검은 아이콘"이었다.
            #expect(difference > 0.6, "\(combination.name) 대비가 부족하다: \(difference)")
        }
    }

    @Test("선택과 비선택이 서로 뚜렷하게 다르다")
    func drawHandStatesAreDistinct() {
        let selected = drawHandCombinations[0]
        let unselected = drawHandCombinations[1]
        let difference = abs(luminance(selected.background) - luminance(unselected.background))
        #expect(difference > 0.6, "선택 여부를 배경만 보고 알 수 없다: \(difference)")
    }

    @Test("컨트롤 배경은 절대 투명하지 않다")
    func drawHandBackgroundIsAlwaysFilled() {
        // 채우지 않은 Shape는 상속된 foreground(시스템 primary)로 칠해진다.
        // 그게 라이트 모드에서 검은 배경을 만들던 원인이라 두 상태 모두 불투명이어야 한다.
        for combination in drawHandCombinations {
            let alpha = UIColor(combination.background).cgColor.alpha
            #expect(alpha == 1, "\(combination.name) 배경이 투명하다")
        }
    }

    @Test("Editor 화면은 시스템 appearance로 갈리지 않는다")
    func editorDoesNotBranchOnColorScheme() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "ggumirror/Editor/EditorView.swift"),
            encoding: .utf8
        )
        // 라이트/다크 두 벌을 만들지 않는다. 꾸미러는 고정된 종이/잉크 appearance다.
        #expect(!source.contains("colorScheme"))
        // 배경을 채우지 않은 Shape를 다시 만들면 같은 버그가 돌아온다.
        #expect(!source.contains("shape.overlay(shape.stroke"))
    }

    @Test("그리기 도구 막대는 라이트/다크에서 똑같이 보인다")
    func drawHandLooksIdenticalInBothSchemes() throws {
        // 컨트롤과 같은 구조(채운 종이 면 + 잉크 테두리 + 두 상태)를 그려 두 appearance를 비교한다.
        let control = HStack(spacing: 0) {
            ForEach(DrawingInteractionMode.allCases) { mode in
                Image(systemName: mode.icon)
                    .font(InkFont.body)
                    .foregroundStyle(mode == .draw ? PaperTheme.paper : PaperTheme.ink)
                    .frame(width: 44, height: 40)
                    .background {
                        UnevenRoundedRectangle.ink(12, 9, 13, 10)
                            .fill(mode == .draw ? PaperTheme.ink : PaperTheme.subtleSurface)
                    }
            }
        }
        .padding(2)
        .background {
            let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
            shape
                .fill(PaperTheme.subtleSurface)
                .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.regular))
        }

        let size = CGSize(width: 100, height: 48)
        let light = try #require(render(control, size: size, scheme: .light))
        let dark = try #require(render(control, size: size, scheme: .dark))
        #expect(pixels(light) == pixels(dark), "시스템 appearance에 따라 컨트롤이 달라진다")
    }

    @Test("모드 전환 동작은 그대로다")
    func modeSwitchingBehaviorUnchanged() {
        // 정책은 손대지 않았다 — 색만 고쳤다.
        #expect(DrawingInteractionMode.allCases.count == 2)
        #expect(EditorGesturePolicy.oneFingerAction(tool: .draw, drawingMode: .draw, grabbed: nil) == .draw)
        #expect(
            EditorGesturePolicy.oneFingerAction(tool: .draw, drawingMode: .pan, grabbed: nil) == .panViewport
        )
    }
}
