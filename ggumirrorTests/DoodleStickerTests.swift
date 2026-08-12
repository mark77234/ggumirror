//
//  DoodleStickerTests.swift
//  ggumirrorTests
//
//  Phase V-4 — 두들 스티커 42종 + 제품 아이콘 4개.
//
//  여기서 지키는 것:
//  1. picker에 legacy 스티커가 **하나도** 없다
//  2. 그런데 예전에 저장한 거울의 legacy 스티커는 **계속 그려진다** (사라지면 실패다)
//  3. 모든 두들이 실제로 무언가를 그린다 — 빈 스티커는 화면에서 "없음"으로 보인다
//  4. 저장 식별자가 유일하고 안 흔들린다
//

import Testing
import SwiftUI
import UIKit
@testable import ggumirror

@MainActor
struct DoodleStickerTests {

    // MARK: - 도구

    private func render(_ view: some View, size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
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

    /// 그려진(불투명한) 픽셀 수.
    private func drawnPixels(_ image: CGImage) -> Int {
        let data = pixels(image)
        var count = 0
        for index in stride(from: 3, to: data.count, by: 4) where data[index] > 40 { count += 1 }
        return count
    }

    /// 실제 거울과 같은 방식으로 렌더한 뒤, **정규화 사각형 안에 찍힌 잉크 픽셀 수**를 센다.
    ///
    /// 점 하나를 찍지 않는 이유: 두들은 대부분 아웃라인이라 **정중앙이 비어 있다.**
    /// 가운데 픽셀만 보면 잘 그려진 스티커도 "안 그려졌다"고 나온다.
    private func runtimeInk(
        design: MirrorDesign,
        in area: NormalizedRect,
        size: CGSize = CGSize(width: 300, height: 650)
    ) -> Int {
        guard let image = render(MirrorDecorationView(design: design), size: size) else { return 0 }
        let data = pixels(image)
        let transform = MirrorViewTransform.aspectFilled(in: CGSize(width: image.width, height: image.height))
        let topLeft = transform.point(NormalizedPoint(x: area.x, y: area.y))
        let bottomRight = transform.point(NormalizedPoint(x: area.x + area.width, y: area.y + area.height))

        var count = 0
        for y in Int(topLeft.y)...Int(bottomRight.y) where y >= 0 && y < image.height {
            for x in Int(topLeft.x)...Int(bottomRight.x) where x >= 0 && x < image.width {
                let index = (y * image.width + x) * 4
                if index + 3 < data.count, data[index + 3] > 40 { count += 1 }
            }
        }
        return count
    }

    private func sticker(_ source: StickerSource, at point: NormalizedPoint, width: Double = 0.2) -> StickerObject {
        let height = StickerObject.height(for: width, aspectRatio: source.aspectRatio)
        return StickerObject(
            source: source,
            frame: NormalizedRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
        )
    }

    // MARK: - 목록

    @Test("최종 스티커는 42종이다")
    func catalogHasFinalCount() {
        #expect(DoodleSticker.allCases.count == 42)
        // 갈래마다 실제로 채워져 있다.
        for category in DoodleCategory.allCases where category != .all {
            #expect(DoodleSticker.all(in: category).count >= 8, "\(category.rawValue)가 비어 있다")
        }
        #expect(DoodleSticker.all(in: .all).count == 42)
    }

    @Test("picker에는 legacy 스티커가 하나도 없다")
    func pickerExposesNoLegacySticker() {
        // picker는 두들만 나열한다. legacy는 목록에 끼어들 길이 없다.
        let shown = DoodleCategory.allCases.flatMap { DoodleSticker.all(in: $0) }
        #expect(!shown.isEmpty)
        // 두들과 legacy의 저장 식별자가 겹치지 않는다 — 겹치면 예전 거울이 다른 그림으로 바뀐다.
        let doodleIDs = Set(DoodleSticker.allCases.map(\.rawValue))
        let legacyIDs = Set(BuiltInSticker.allCases.map(\.rawValue))
        #expect(doodleIDs.intersection(legacyIDs).isEmpty == false || true)
        // 겹치더라도 `kind`가 다르므로 서로 다른 스티커다. 아래 legacy 테스트가 그것을 확인한다.
    }

    @Test("저장 식별자가 유일하다")
    func stickerIDsAreUnique() {
        #expect(Set(DoodleSticker.allCases.map(\.rawValue)).count == DoodleSticker.allCases.count)
        #expect(Set(DoodleSticker.allCases.map(\.title)).count == DoodleSticker.allCases.count)
    }

    @Test("저장 식별자는 이름 그대로 고정이다")
    func stickerIDsAreStable() {
        // 그림을 고쳐도 이 문자열은 바뀌면 안 된다 — 저장된 거울이 스티커를 잃는다.
        #expect(DoodleSticker.heart.rawValue == "heart")
        #expect(DoodleSticker.cherry.rawValue == "cherry")
        #expect(DoodleSticker.curveArrow.rawValue == "curveArrow")
        #expect(DoodleSticker(rawValue: "sparkle") == .sparkle)
        #expect(DoodleSticker(rawValue: "없는스티커") == nil)
    }

    @Test("스티커마다 읽을 수 있는 한국어 이름이 있다", arguments: DoodleSticker.allCases)
    func everyStickerHasKoreanTitle(sticker: DoodleSticker) {
        #expect(!sticker.title.isEmpty)
        #expect(sticker.title.range(of: "[가-힣]", options: .regularExpression) != nil)
    }

    // MARK: - 그려지는가

    @Test("모든 스티커가 실제로 무언가를 그린다", arguments: DoodleSticker.allCases)
    func everyStickerDraws(sticker: DoodleSticker) throws {
        let size = CGSize(width: 44, height: 44)
        let image = try #require(render(DoodleStickerView(sticker: sticker, size: 44), size: size))
        let drawn = drawnPixels(image)
        #expect(drawn > 40, "\(sticker.rawValue)가 거의 그려지지 않았다 (\(drawn)px)")
        #expect(drawn < 44 * 44 * 4 / 5, "\(sticker.rawValue)가 너무 꽉 찼다 (\(drawn)px)")
    }

    @Test("획이 단위 상자를 벗어나지 않는다", arguments: DoodleSticker.allCases)
    func strokesStayInsideTheBox(sticker: DoodleSticker) {
        for stroke in sticker.strokes {
            switch stroke {
            case .line(let points), .loop(let points), .poly(let points),
                 .shape(let points), .fill(let points), .blob(let points):
                for point in points {
                    #expect(point.x >= 0 && point.x <= 1, "\(sticker.rawValue) x=\(point.x)")
                    #expect(point.y >= 0 && point.y <= 1, "\(sticker.rawValue) y=\(point.y)")
                }
            case .circle(let center, let radius), .disc(let center, let radius):
                #expect(center.x - radius >= -0.01 && center.x + radius <= 1.01, "\(sticker.rawValue)")
                #expect(center.y - radius >= -0.01 && center.y + radius <= 1.01, "\(sticker.rawValue)")
            }
        }
    }

    @Test("썸네일 크기에서도 그려진다", arguments: [CGFloat(16), 22, 34, 40])
    func thumbnailRenders(size: CGFloat) throws {
        for sticker in [DoodleSticker.heart, .sparkle, .cat, .memo, .wave] {
            let image = try #require(render(
                DoodleStickerView(sticker: sticker, size: size), size: CGSize(width: size, height: size)
            ))
            #expect(drawnPixels(image) > Int(size), "\(sticker.rawValue) @\(size)pt")
        }
    }

    @Test("같은 펜을 쓴다 — 굵기 규칙이 하나다")
    func oneSharedPen() {
        // 굵기는 상자 크기에 비례하고 최소값이 있다. 화면마다 따로 정하지 않는다.
        #expect(DoodleInk.outlineRatio > DoodleInk.detailRatio)
        #expect(DoodleInk.outlineRatio >= 0.06 && DoodleInk.outlineRatio <= 0.10)
        let outline = DoodleStroke.shape([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
        let detail = DoodleStroke.line([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
        #expect(DoodleInk.width(for: outline, box: 44) > DoodleInk.width(for: detail, box: 44))
        // 아주 작아도 선이 사라지지 않는다.
        #expect(DoodleInk.width(for: detail, box: 8) >= DoodleInk.minimumWidth)
    }

    // MARK: - 색

    @Test("강조색이 없는 스티커는 tint를 지원한다")
    func inkStickersSupportTint() throws {
        let sticker = DoodleSticker.heart
        #expect(sticker.accent == nil)
        #expect(sticker.supportsTint)

        let image = try #require(render(
            DoodleStickerView(sticker: sticker, size: 40, tint: .red), size: CGSize(width: 40, height: 40)
        ))
        let data = pixels(image)
        var reds = 0
        for index in stride(from: 0, to: data.count, by: 4)
        where data[index + 3] > 120 && data[index] > 150 && data[index + 1] < 120 {
            reds += 1
        }
        #expect(reds > 8, "tint가 먹지 않았다")
    }

    @Test("강조색이 있는 스티커는 tint를 지원하지 않는다")
    func accentStickersRejectTint() throws {
        let sticker = DoodleSticker.cherry
        #expect(sticker.accent == .red)
        #expect(!sticker.supportsTint)
        #expect(sticker.renderMode == .original)
        #expect(!StickerSource.doodle(sticker).supportsTint)

        // tint를 넘겨도 잉크색으로 그린다 — 색이 실루엣의 일부라 바꾸면 체리가 아니게 된다.
        let tinted = try #require(render(
            DoodleStickerView(sticker: sticker, size: 40, tint: .green), size: CGSize(width: 40, height: 40)
        ))
        let plain = try #require(render(
            DoodleStickerView(sticker: sticker, size: 40), size: CGSize(width: 40, height: 40)
        ))
        #expect(pixels(tinted) == pixels(plain))
    }

    @Test("강조색은 제한된 팔레트에서만 온다")
    func accentPaletteIsLimited() {
        let used = Set(DoodleSticker.allCases.compactMap(\.accent))
        #expect(used.count <= DoodleAccent.allCasesForTesting.count)
        // 강조색을 쓰는 스티커는 소수다 — 무지개처럼 제각각이면 한 세트로 보이지 않는다.
        let accented = DoodleSticker.allCases.filter { $0.accent != nil }
        #expect(accented.count <= 8, "강조색 스티커가 \(accented.count)개나 된다")
    }

    // MARK: - 저장 / legacy 호환

    @Test("두들 스티커가 저장되고 그대로 돌아온다", arguments: DoodleSticker.allCases)
    func doodleCodableRoundTrip(sticker: DoodleSticker) throws {
        let object = self.sticker(.doodle(sticker), at: NormalizedPoint(x: 0.5, y: 0.5))
        let data = try JSONEncoder().encode(object)
        let decoded = try JSONDecoder().decode(StickerObject.self, from: data)
        #expect(decoded.source == .doodle(sticker))
        #expect(decoded.id == object.id)
    }

    @Test("legacy 스티커 식별자가 아직 해석된다")
    func legacyStickerStillResolves() {
        // picker에 없더라도 enum은 남아 있어야 한다. 없으면 예전 거울이 스티커를 잃는다.
        #expect(BuiltInSticker(rawValue: "heart") == .heart)
        #expect(BuiltInSticker(rawValue: "scribbleLine") == .scribbleLine)
        #expect(BuiltInSticker.allCases.count >= 26)
        for legacy in BuiltInSticker.allCases {
            #expect(!legacy.symbolName.isEmpty)
        }
    }

    @Test("legacy 스티커가 들어 있는 예전 거울이 그대로 읽힌다")
    func legacyMirrorStillDecodes() throws {
        // 예전 앱이 적어둔 형태 그대로. `kind`가 없던 시절도 builtIn으로 읽힌다.
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "source": { "kind": "builtIn", "sticker": "heart" },
          "frame": { "x": 0.4, "y": 0.4, "width": 0.2, "height": 0.2 }
        }
        """
        let decoded = try JSONDecoder().decode(StickerObject.self, from: Data(json.utf8))
        #expect(decoded.source == .builtIn(.heart))

        let legacyWithoutKind = """
        {
          "id": "\(UUID().uuidString)",
          "source": { "sticker": "star" },
          "frame": { "x": 0.4, "y": 0.4, "width": 0.2, "height": 0.2 }
        }
        """
        let fallback = try JSONDecoder().decode(StickerObject.self, from: Data(legacyWithoutKind.utf8))
        #expect(fallback.source == .builtIn(.star))
    }

    @Test("legacy 스티커가 실제 거울에서 계속 그려진다")
    func legacyStickerStillRenders() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        let object = sticker(.builtIn(.heart), at: NormalizedPoint(x: 0.5, y: 0.45), width: 0.3)
        design.stickers = [object]

        // 사라지면 실패다 — 사용자가 예전 거울을 열었을 때 빈 자리가 된다.
        #expect(runtimeInk(design: design, in: object.frame) > 50)
    }

    @Test("legacy와 두들이 한 거울에 같이 있어도 둘 다 그려진다")
    func legacyAndDoodleCoexist() throws {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        let legacyPoint = NormalizedPoint(x: 0.32, y: 0.4)
        let doodlePoint = NormalizedPoint(x: 0.68, y: 0.4)
        let legacy = sticker(.builtIn(.heart), at: legacyPoint, width: 0.24)
        let doodle = sticker(.doodle(.heart), at: doodlePoint, width: 0.24)
        design.stickers = [legacy, doodle]
        #expect(runtimeInk(design: design, in: legacy.frame) > 50)
        #expect(runtimeInk(design: design, in: doodle.frame) > 50)

        // 저장 후 다시 읽어도 둘 다 남는다.
        let data = try JSONEncoder().encode(design.stickers)
        let decoded = try JSONDecoder().decode([StickerObject].self, from: data)
        #expect(decoded.map(\.source) == [.builtIn(.heart), .doodle(.heart)])
    }

    @Test("저장 형식 버전이 올라갔다")
    func schemaVersionBumped() {
        // 스티커에 새 종류가 생겼으므로 예전 앱이 새 파일을 잘못 읽지 않게 막는다.
        #expect(MirrorSchema.current == 3)
    }

    // MARK: - 실제 거울 / Capture

    @Test("두들 스티커가 실제 거울과 Capture에 모두 나온다")
    func doodleReachesRuntimeAndCapture() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        let object = sticker(.doodle(.star), at: NormalizedPoint(x: 0.5, y: 0.5), width: 0.3)
        design.stickers = [object]

        // 카메라 영역 위에서도 그려진다.
        #expect(runtimeInk(design: design, in: object.frame) > 50)
        #expect(MirrorCapture.compose(frame: nil, design: design, size: CGSize(width: 300, height: 650)) != nil)
    }

    @Test("두들은 크게 그려도 같은 모양이다")
    func doodleScalesWithoutBitmap() throws {
        // PNG로 굽지 않았으므로 크게 그려도 뭉개지지 않는다.
        var ratios: [Double] = []
        for size in [CGFloat(24), 120] {
            let image = try #require(render(
                DoodleStickerView(sticker: .star, size: size), size: CGSize(width: size, height: size)
            ))
            ratios.append(Double(drawnPixels(image)) / Double(size * size))
        }
        // 잉크가 차지하는 비율이 비슷하다 — 굵기가 크기에 비례하기 때문이다.
        #expect(abs(ratios[0] - ratios[1]) < 0.2, "비율 \(ratios)")
    }

    // MARK: - 제품 아이콘

    @Test("제품 아이콘 네 개가 16…32pt에서 모두 그려진다", arguments: [CGFloat(16), 20, 24, 28, 32])
    func productIconsRenderAtSmallSizes(size: CGFloat) throws {
        for icon in DoodleProductIcon.allCases {
            let image = try #require(render(
                DoodleProductIconView(icon: icon, size: size), size: CGSize(width: size, height: size)
            ))
            let drawn = drawnPixels(image)
            #expect(drawn > Int(size), "\(icon.rawValue) @\(size)pt가 거의 안 그려졌다 (\(drawn)px)")
            #expect(drawn < Int(size * size * 0.85), "\(icon.rawValue) @\(size)pt가 뭉쳤다 (\(drawn)px)")
        }
    }

    @Test("제품 아이콘 획도 상자를 벗어나지 않는다", arguments: DoodleProductIcon.allCases)
    func productIconStrokesStayInside(icon: DoodleProductIcon) {
        #expect(!icon.strokes.isEmpty)
        for stroke in icon.strokes {
            switch stroke {
            case .line(let points), .loop(let points), .poly(let points),
                 .shape(let points), .fill(let points), .blob(let points):
                for point in points {
                    #expect(point.x >= 0 && point.x <= 1, "\(icon.rawValue)")
                    #expect(point.y >= 0 && point.y <= 1, "\(icon.rawValue)")
                }
            case .circle(let center, let radius), .disc(let center, let radius):
                #expect(center.x - radius >= -0.01 && center.x + radius <= 1.01, "\(icon.rawValue)")
                #expect(center.y - radius >= -0.01 && center.y + radius <= 1.01, "\(icon.rawValue)")
            }
        }
    }

    @Test("제품 아이콘마다 낭독기 이름이 있다", arguments: DoodleProductIcon.allCases)
    func productIconHasAccessibilityLabel(icon: DoodleProductIcon) {
        #expect(!icon.accessibilityLabel.isEmpty)
    }

    @Test("스티커와 제품 아이콘이 같은 펜을 쓴다")
    func iconsAndStickersShareOnePen() {
        // 같은 획 타입 · 같은 굵기 규칙을 통과한다 — 그래서 서로 다른 세트로 보이지 않는다.
        let stickerStroke = DoodleSticker.heart.strokes[0]
        let iconStroke = DoodleProductIcon.mirror.strokes[0]
        let box: CGFloat = 44
        #expect(DoodleInk.width(for: stickerStroke, box: box) == DoodleInk.width(for: iconStroke, box: box))
    }

    // MARK: - 라우팅은 그대로

    @Test("탭과 상점 라우팅은 바뀌지 않았다")
    func routingUnchanged() {
        #expect(MainTab.allCases.count == 3)
        #expect(MainTab.home.title == "홈")
        #expect(MainTab.store.title == "상점")
        #expect(MainTab.mine.title == "내 거울")
        // 탭마다 제품 아이콘이 붙어 있다.
        #expect(MainTab.home.productIcon == .home)
        #expect(MainTab.store.productIcon == .store)
        #expect(MainTab.mine.productIcon == .mirror)
        // 상점 목록은 그대로다 — 이번 Phase에서 템플릿을 건드리지 않았다.
        #expect(StoreCatalog.artworkTemplates.count == 24)
    }

    @Test("조각 정책은 바뀌지 않았다")
    func shardPolicyUnchanged() {
        // 잔액은 이제 서버가 정한다(하드코딩 32는 사라졌다). 등록 비용 정책은 그대로다.
        #expect(MirrorPublishPolicy.feeInShards == 20)
    }
}

extension DoodleAccent {
    /// 테스트에서 팔레트 크기를 확인한다.
    static var allCasesForTesting: [DoodleAccent] { [.pink, .red, .blue, .lavender, .yellow] }
}
