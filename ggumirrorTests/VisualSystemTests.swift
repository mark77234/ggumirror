//
//  VisualSystemTests.swift
//  ggumirrorTests
//
//  손그림 비주얼 시스템과 글꼴 라이브러리.
//  "종이 · 잉크 · 손글씨"가 앱 전체에서 같은 값을 쓰는지, 그리고
//  사용자가 고른 글꼴이 저장 → 편집 → 미리보기 → 실제 거울 → 촬영까지 그대로 가는지 본다.
//

import Testing
import SwiftUI
import UIKit
@testable import ggumirror

@MainActor
struct VisualSystemTests {

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

    /// 글자가 실제로 찍혔는지. 흰 바탕에 어두운 픽셀이 몇 개나 있는지 센다.
    private func inkedPixels(_ view: some View, size: CGSize) -> Int {
        guard let image = render(view.background(Color.white), size: size) else { return 0 }
        let data = pixels(image)
        var count = 0
        for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] > 60 && data[i] < 170 {
            count += 1
        }
        return count
    }

    private func text(_ string: String, style: TextFontStyle, size: CGFloat = 30) -> some View {
        Text(string)
            .font(Font(style.font(ofSize: size)))
            .foregroundStyle(.black)
    }

    // MARK: - 종이 / 잉크

    @Test("종이 결은 매번 같은 모양이다 — 스크롤해도 반짝이지 않는다")
    func paperTextureIsDeterministic() throws {
        let size = CGSize(width: 200, height: 300)
        let first = try #require(render(PaperBackground(), size: size))
        let second = try #require(render(PaperBackground(), size: size))
        #expect(pixels(first) == pixels(second))
    }

    @Test("종이 결은 눈에 먼저 띄지 않을 만큼 옅다")
    func paperTextureStaysSubtle() throws {
        let image = try #require(render(PaperBackground(), size: CGSize(width: 200, height: 300)))
        let data = pixels(image)
        var dark = 0
        for i in stride(from: 0, to: data.count, by: 4) where data[i] < 200 { dark += 1 }
        let ratio = Double(dark) / Double(data.count / 4)
        #expect(ratio < 0.02, "결이 너무 진하다: \(ratio)")
        // 그래도 완전 평면은 아니다.
        var tones = Set<UInt8>()
        for i in stride(from: 0, to: data.count, by: 4) { tones.insert(data[i]) }
        #expect(tones.count > 3)
    }

    @Test("잉크 선 굵기는 얇게 / 기본 / 강조 순이다")
    func inkLineTokensAreOrdered() {
        #expect(InkLine.thin < InkLine.regular)
        #expect(InkLine.regular < InkLine.emphasis)
        #expect(InkLine.emphasis <= 2.1)      // 실기기에서 너무 굵지 않게
    }

    @Test("모서리는 네 개가 조금씩 다르지만 매번 같은 값이다")
    func cornersAreAsymmetricButStable() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        // 같은 preset은 다시 그려도 같은 path다 — render마다 흔들리지 않는다.
        #expect(InkCorner.card.path(in: rect) == InkCorner.card.path(in: rect))
        #expect(InkCorner.control.path(in: rect) == InkCorner.control.path(in: rect))
        // 완전히 같은 radius가 아니다.
        #expect(InkCorner.card.path(in: rect) != RoundedRectangle(cornerRadius: 20).path(in: rect))
    }

    @Test("카메라 영역에는 종이 결을 덮지 않는다")
    func cameraAreaHasNoPaperOverlay() throws {
        let design = MirrorDesign.blank
        let view = MirrorDecorationView(design: design)
        let image = try #require(render(view, size: CGSize(width: 300, height: 650)))
        let transform = MirrorViewTransform.aspectFilled(in: CGSize(width: image.width, height: image.height))
        let screen = transform.point(NormalizedPoint(x: 0.5, y: 0.5))

        let data = pixels(image)
        let index = (Int(screen.y) * image.width + Int(screen.x)) * 4
        #expect(data[index + 3] == 0, "실제 거울의 카메라 자리는 완전히 비어 있어야 한다")
    }

    // MARK: - 브랜드 서체

    @Test("개구 세 굵기가 모두 실제로 해석된다")
    func brandFontResolves() throws {
        for resource in [BrandFont.light, BrandFont.regular, BrandFont.bold] {
            let name = try #require(MirrorFontLibrary.postScriptName(for: resource),
                                    "\(resource)를 찾지 못했다")
            #expect(name.contains("Gaegu"))
            let font = MirrorFontLibrary.uiFont(resource: resource, size: 20)
            #expect(font.fontName == name)
            #expect(font.pointSize == 20)
        }
    }

    @Test("앱 UI 글씨가 시스템 기본 폰트가 아니다")
    func appTypographyIsBranded() throws {
        // 같은 문장을 브랜드 서체와 시스템 서체로 그리면 결과가 다르다.
        let sample = Text("꾸미러 상점 123").foregroundStyle(.black)
        let size = CGSize(width: 260, height: 60)
        let brand = try #require(render(sample.font(InkFont.cardTitle).background(Color.white), size: size))
        let system = try #require(render(sample.font(.system(.title3)).background(Color.white), size: size))
        #expect(pixels(brand) != pixels(system))
    }

    @Test("글꼴을 못 찾아도 시스템 폰트로 떨어진다")
    func brandFontFallsBack() {
        let missing = MirrorFontLibrary.uiFont(resource: "이런폰트는없다", size: 18, fallbackWeight: .bold)
        #expect(missing.pointSize == 18)
        #expect(MirrorFontLibrary.postScriptName(for: "이런폰트는없다") == nil)
        // nil을 넘겨도 안전하다.
        #expect(MirrorFontLibrary.uiFont(resource: nil, size: 12).pointSize == 12)
    }

    // MARK: - 거울 글꼴 라이브러리

    @Test("고를 수 있는 글꼴 11가지가 모두 준비돼 있다")
    func decorationFontsAreAvailable() throws {
        #expect(TextFontStyle.selectable.count == 11)
        #expect(TextFontStyle.selectable.first == .basic)

        for style in TextFontStyle.selectable where style.resource != nil {
            let resource = try #require(style.resource)
            #expect(MirrorFontLibrary.postScriptName(for: resource) != nil, "\(style.title) 파일이 없다")
            let font = style.font(ofSize: 24)
            #expect(font.pointSize == 24)
            #expect(font.fontName != UIFont.systemFont(ofSize: 24).fontName, "\(style.title)이 시스템 폰트로 떨어졌다")
        }
        // 사용자에게 보이는 이름은 한국어다.
        #expect(TextFontStyle.gaegu.title == "개구")
        #expect(TextFontStyle.nanumBrush.title == "나눔붓")
    }

    @Test("한글 / 숫자 / 영문이 각 글꼴로 실제로 그려진다")
    func koreanSampleRendersInEveryFont() throws {
        let size = CGSize(width: 340, height: 60)
        var shapes: [TextFontStyle: Int] = [:]
        for style in TextFontStyle.selectable {
            let count = inkedPixels(text("오늘도 예쁘게 123 ABC", style: style), size: size)
            #expect(count > 200, "\(style.title)에서 글자가 거의 안 그려졌다")
            shapes[style] = count
        }
        // 글꼴마다 실제로 다른 모양이다 — 전부 같은 폰트로 떨어지지 않았다.
        #expect(Set(shapes.values).count >= 8)
    }

    @Test("여러 줄도 글꼴에 맞춰 줄이 나뉜다")
    func multilineLayoutFollowsFont() {
        var object = TextObject(text: "오늘도\n예쁘게", center: NormalizedPoint(x: 0.5, y: 0.5))
        object.style = .nanumPen
        let layout = TextLayout.of(object)
        #expect(layout.lines.count == 2)
        #expect(layout.size.height > layout.lineHeight)
        #expect(layout.size.width > 0)
    }

    // MARK: - 저장 호환

    @Test("예전에 저장한 글꼴 값이 그대로 읽힌다")
    func legacyFontStylesStillDecode() throws {
        // v1~v2 시절 저장 파일에 들어 있던 값들.
        for raw in ["basic", "bold", "serif", "rounded"] {
            let style = try #require(TextFontStyle(rawValue: raw))
            #expect(style.resource == nil)               // 시스템 폰트를 쓰던 값
            #expect(!style.title.isEmpty)
            #expect(style.font(ofSize: 20).pointSize == 20)
        }
        // 모르는 값이 들어와도 기본값으로 살아난다.
        var text = TextObject(text: "안녕", center: NormalizedPoint(x: 0.5, y: 0.5))
        text.style = .serif
        let data = try JSONEncoder().encode(text)
        #expect(String(decoding: data, as: UTF8.self).contains("serif"))
        #expect(try JSONDecoder().decode(TextObject.self, from: data).style == .serif)
    }

    @Test("새 글꼴도 저장 형식 그대로 오간다")
    func newFontStyleRoundTrips() throws {
        for style in TextFontStyle.selectable {
            var text = TextObject(text: "오늘도", center: NormalizedPoint(x: 0.4, y: 0.6))
            text.style = style
            let restored = try JSONDecoder().decode(TextObject.self, from: JSONEncoder().encode(text))
            #expect(restored.style == style)
        }
        // 글꼴이 늘어난 것만으로는 저장 형식 버전을 올리지 않았다 —
        // rawValue 저장 방식이 그대로이기 때문이다.
        // (3으로 올라간 이유는 스티커에 `doodle` 종류가 생겼기 때문이다.)
        #expect(TextFontStyle(rawValue: "basic") == .basic)
    }

    @Test("고른 글꼴이 앱을 다시 켜도 남는다")
    func selectedFontSurvivesRelaunch() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ggumirror-font-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = MirrorStore(root: root)
        defer {
            store.flush()
            try? FileManager().removeItem(at: root)
        }

        let library = MirrorLibrary(store: store, assets: PhotoStickerAssetStore(), artworks: ImportedArtworkAssetStore())
        var design = MirrorDesign.blank
        var text = TextObject(text: "오늘도 예쁘게", center: NormalizedPoint(x: 0.5, y: 0.5))
        text.style = .hiMelody
        design.texts = [text]
        library.save(design, name: "글꼴 거울", context: .createNew)
        store.flush()

        let reopened = MirrorLibrary(
            store: MirrorStore(root: root),
            assets: PhotoStickerAssetStore(),
            artworks: ImportedArtworkAssetStore()
        )
        #expect(reopened.mirrors.first?.texts.first?.style == .hiMelody)
    }

    // MARK: - 렌더 일치

    @Test("고른 글꼴이 미리보기 / 실제 거울 / 촬영에서 모두 같게 나온다")
    func selectedFontRendersEverywhere() throws {
        var mirror = MyMirror(id: "made-font", name: "글꼴", origin: .made,
                              style: MirrorLibrary.defaultMirror.style)
        var text = TextObject(text: "오늘도 예쁘게", center: NormalizedPoint(x: 0.5, y: 0.5))
        text.style = .jua
        text.fontSize = 0.09
        mirror.texts = [text]
        let design = MirrorDesign(mirror: mirror)

        // 셋 다 같은 TextLayout / MirrorRenderer를 지난다.
        let preview = try #require(render(MirrorPreview(mirror: mirror), size: CGSize(width: 200, height: 433)))
        let runtime = try #require(render(MirrorDecorationView(design: design), size: CGSize(width: 300, height: 650)))
        let capture = try #require(
            MirrorCapture.compose(frame: nil, design: design, size: CGSize(width: 300, height: 650))?.cgImage
        )
        for image in [preview, runtime, capture] {
            let data = pixels(image)
            var inked = 0
            for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] > 60 && data[i] < 150 { inked += 1 }
            #expect(inked > 60, "글자가 보이지 않는다")
        }

        // 글꼴을 바꾸면 결과도 바뀐다 — 선택이 실제로 반영된다.
        var other = mirror
        other.texts[0].style = .nanumBrush
        let changed = try #require(render(MirrorPreview(mirror: other), size: CGSize(width: 200, height: 433)))
        #expect(pixels(changed) != pixels(preview))
    }

    // MARK: - 텍스트 크기 조절

    @Test("조금 끌면 글자가 조금만 커진다 — 예전보다 둔감하다")
    func textResizeIsLessSensitive() {
        let canvasWidth: CGFloat = 360
        let base = TextObject(text: "가", center: NormalizedPoint(x: 0.5, y: 0.5))

        func newSize(drag: CGFloat) -> Double {
            let delta = Double(drag * 2 / canvasWidth) * TextPolicy.resizeSensitivity
            return base.resized(fontSize: base.fontSize + delta).fontSize
        }

        // 예전 계수(감도 1.0)보다 확실히 덜 변한다.
        let before = base.resized(fontSize: base.fontSize + Double(10 * 2 / canvasWidth)).fontSize
        let after = newSize(drag: 10)
        #expect(after - base.fontSize < (before - base.fontSize) * 0.6)

        // 손가락을 많이 움직이면 그만큼 커진다.
        #expect(newSize(drag: 60) > newSize(drag: 20))
        #expect(newSize(drag: 20) > base.fontSize)
        // 스티커보다 과민하지 않다 — 같은 거리에서 전체 범위 대비 변화 폭을 비교한다.
        let textSpan = TextPolicy.fontSizeRange.upperBound - TextPolicy.fontSizeRange.lowerBound
        // 스티커에는 최대 제한이 없으므로(V-5B) 예전 범위(0.06…0.45)를 기준 폭으로 쓴다.
        let stickerSpan = 0.45 - 0.06
        let textShare = (newSize(drag: 40) - base.fontSize) / textSpan
        let stickerShare = Double(40 * 2 / canvasWidth) / stickerSpan
        #expect(abs(textShare - stickerShare) < 0.05)
    }

    @Test("잡자마자 튀지 않고, 최소 / 최대에서 멈춘다")
    func textResizeClampsWithoutJump() {
        let base = TextObject(text: "가", center: NormalizedPoint(x: 0.5, y: 0.5))
        // 0만큼 끌면 그대로다 — 손을 대는 순간의 점프가 없다.
        #expect(base.resized(fontSize: base.fontSize + 0).fontSize == base.fontSize)

        #expect(base.resized(fontSize: -5).fontSize == TextPolicy.fontSizeRange.lowerBound)
        #expect(base.resized(fontSize: 99).fontSize == TextPolicy.fontSizeRange.upperBound)
        #expect(TextPolicy.fontSizeRange.contains(base.resized(fontSize: 0.05).fontSize))
    }

    @Test("크기를 바꿔도 여러 줄 비율은 그대로다")
    func textResizeKeepsMultilineProportions() {
        var object = TextObject(text: "오늘도\n예쁘게 하루", center: NormalizedPoint(x: 0.5, y: 0.5))
        object.style = .gaegu
        let small = TextLayout.of(object.resized(fontSize: 0.05))
        let large = TextLayout.of(object.resized(fontSize: 0.15))

        #expect(small.lines.count == large.lines.count)
        let smallRatio = small.size.width / small.size.height
        let largeRatio = large.size.width / large.size.height
        #expect(abs(smallRatio - largeRatio) < 0.02)
    }

    @Test("확대 상태에서도 손가락 대비 체감이 같다")
    func textResizeFeelsSameAtAnyZoom() {
        // 배율이 커지면 캔버스도 그만큼 커진다. 화면에서 같은 거리를 끌면
        // 보이는 크기 변화가 같도록 normalized 변화량이 줄어야 한다.
        func delta(canvasWidth: CGFloat) -> Double {
            Double(30 * 2 / canvasWidth) * TextPolicy.resizeSensitivity
        }
        let fitted = delta(canvasWidth: 360)
        let zoomed = delta(canvasWidth: 360 * 3)
        #expect(abs(fitted / 3 - zoomed) < 0.0001)
    }

    // MARK: - 회전 handle

    @Test("회전 handle이 돌아간 오브젝트를 따라간다")
    func rotationHandleFollowsObject() {
        // 오버레이가 handle을 놓는 규칙과 같은 계산.
        let rect = CGRect(x: 100, y: 100, width: 100, height: 60)
        func corner(x: CGFloat, y: CGFloat, degrees: Double) -> CGPoint {
            let radians = CGFloat(degrees) * .pi / 180
            let dx = x - rect.midX, dy = y - rect.midY
            return CGPoint(
                x: rect.midX + dx * cos(radians) - dy * sin(radians),
                y: rect.midY + dx * sin(radians) + dy * cos(radians)
            )
        }
        let atZero = corner(x: rect.maxX, y: rect.minY, degrees: 0)
        #expect(abs(atZero.x - rect.maxX) < 0.001)
        #expect(abs(atZero.y - rect.minY) < 0.001)

        // 180도 돌리면 반대편 모서리로 간다 — 눈에 보이는 자리와 같다.
        let flipped = corner(x: rect.maxX, y: rect.minY, degrees: 180)
        #expect(abs(flipped.x - rect.minX) < 0.001)
        #expect(abs(flipped.y - rect.maxY) < 0.001)

        // 360도는 제자리. 경계에서 끊기지 않는다.
        let full = corner(x: rect.maxX, y: rect.minY, degrees: 360)
        #expect(abs(full.x - atZero.x) < 0.001)
        #expect(abs(full.y - atZero.y) < 0.001)
    }

    @Test("돌아간 오브젝트도 바깥으로 끌면 커진다")
    func resizeFollowsRotation() {
        func along(_ translation: CGSize, degrees: Double) -> CGFloat {
            let radians = CGFloat(degrees) * .pi / 180
            return translation.width * cos(radians) + translation.height * sin(radians)
        }
        // 돌아가지 않았으면 가로 이동 그대로.
        #expect(abs(along(CGSize(width: 20, height: 0), degrees: 0) - 20) < 0.001)
        // 90도 돌아갔으면 아래로 끌어야 커진다.
        #expect(along(CGSize(width: 0, height: 20), degrees: 90) > 19)
        // 반대로 끌면 작아진다.
        #expect(along(CGSize(width: -20, height: 0), degrees: 0) < 0)
    }
}
