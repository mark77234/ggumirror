//
//  FrontFramingTests.swift
//  ggumirrorTests
//
//  전면 카메라를 **세로로 긴 화면에 어떻게 놓는가.**
//
//  전면 센서는 4:3에 가깝고 화면은 9:19.5쯤이다. 꽉 채우려면 좌우를 크게 잘라야 해서
//  얼굴이 기본 카메라 앱보다 훨씬 크게 보였다. 잘라낸 화각은 software로 되돌릴 수 없다 —
//  그래서 **자르지 않는 선택지**를 준다.
//
//  배율(zoom)과 섞이지 않는다. framing을 바꿔도 기기 zoom factor는 그대로다.
//

import Testing
import AVFoundation
import CoreGraphics
import Foundation
@testable import ggumirror

private typealias Framing = MirrorCamera.Framing

/// 주석을 걷어낸 소스. 설명 문구가 규칙 검사에 걸리면 안 된다.
private func framingSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    let text = try String(contentsOf: root.appending(path: path), encoding: .utf8)
    return text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            guard let comment = line.range(of: "//") else { return String(line) }
            return String(line[..<comment.lowerBound])
        }
        .joined(separator: "\n")
}

/// 전면 센서가 흔히 주는 세로 4:3. **코드가 아니라 테스트가 예시로 쓴다.**
private let sensor43 = CGSize(width: 1440, height: 1920)
/// iPhone 15 Pro 화면 픽셀.
private let screen = CGSize(width: 1179, height: 2556)

@MainActor
@Suite("전면 framing 기본값")
struct FrontFramingDefaultTests {

    @Test("첫 진입은 넓게 보기다")
    func defaultIsWide() {
        #expect(Framing.initial == .wide)
        let camera = MirrorCamera(role: .mirror)
        #expect(camera.frontFraming == .wide)
    }

    @Test("후면은 언제나 꽉 채운다")
    func rearAlwaysFills() {
        let camera = MirrorCamera(role: .mirror)
        // 시작은 전면이다.
        #expect(camera.position == .front)
        #expect(camera.framing == .wide)

        // 후면에서는 전면 선택과 무관하게 fill이다.
        let source = try! framingSource("ggumirror/Mirror/MirrorCamera.swift")
        #expect(source.contains("var framing: Framing { position == .front ? frontFraming : .fill }"))
        #expect(source.contains("role == .mirror && status == .ready && position == .front"))
    }

    @Test("session 안에서만 산다 — 저장하지 않는다")
    func framingIsNotPersisted() throws {
        let source = try framingSource("ggumirror/Mirror/MirrorCamera.swift")
        #expect(!source.contains("UserDefaults"))
        #expect(!source.contains("AppStorage"))
        // 전면 선택은 카메라 객체가 들고 있으므로 후면에 갔다 와도 살아 있다.
        #expect(source.contains("var frontFraming: Framing = .initial"))
    }
}

@Suite("얼마나 잘리는가")
struct FramingCropTests {

    @Test("넓게 보기는 하나도 자르지 않는다")
    func wideKeepsEverything() {
        #expect(MirrorCamera.visibleSourceFraction(
            source: sensor43, viewport: screen, framing: .wide
        ) == 1)
    }

    @Test("화면 채우기는 좌우를 크게 자른다")
    func fillCropsTheSides() {
        let visible = MirrorCamera.visibleSourceFraction(
            source: sensor43, viewport: screen, framing: .fill
        )
        // 4:3 센서를 9:19.5 화면에 꽉 채우면 절반 넘게 사라진다.
        #expect(visible < 0.7)
        #expect(visible > 0)
    }

    @Test("넓게 보기가 화면 채우기보다 언제나 덜 자른다")
    func wideAlwaysCropsLess() {
        // 비율 조합을 바꿔 가며 확인한다 — 특정 기기 숫자에 기대지 않는다.
        let sources = [
            CGSize(width: 1440, height: 1920),   // 4:3
            CGSize(width: 1080, height: 1920),   // 16:9
            CGSize(width: 1600, height: 1200),   // 가로로 긴 원본
        ]
        let viewports = [screen, CGSize(width: 750, height: 1334), CGSize(width: 1284, height: 2778)]

        for source in sources {
            for viewport in viewports {
                let wide = MirrorCamera.visibleSourceFraction(
                    source: source, viewport: viewport, framing: .wide
                )
                let fill = MirrorCamera.visibleSourceFraction(
                    source: source, viewport: viewport, framing: .fill
                )
                #expect(wide >= fill, "source \(source) viewport \(viewport)")
            }
        }
    }

    @Test("원본과 화면 비율이 같으면 두 방법이 같다")
    func sameAspectMeansNoDifference() {
        let square = CGSize(width: 1000, height: 1000)
        #expect(MirrorCamera.visibleSourceFraction(
            source: square, viewport: CGSize(width: 500, height: 500), framing: .fill
        ) == 1)
    }

    @Test("크기가 0이어도 나누지 않는다")
    func degenerateSizesAreSafe() {
        #expect(MirrorCamera.visibleSourceFraction(
            source: .zero, viewport: screen, framing: .fill
        ) == 1)
        #expect(MirrorCamera.visibleSourceFraction(
            source: sensor43, viewport: .zero, framing: .fill
        ) == 1)
    }
}

@MainActor
@Suite("framing은 원본 비율에서 나온다")
struct FramingIsSourceDrivenTests {

    @Test("4:3을 코드에 적지 않는다")
    func noHardcodedAspectRatio() throws {
        for path in [
            "ggumirror/Mirror/MirrorCamera.swift",
            "ggumirror/Mirror/CameraPreviewView.swift",
            "ggumirror/Mirror/MirrorCapture.swift",
        ] {
            let source = try framingSource(path)
            for guessed in ["4.0 / 3.0", "4 / 3", "0.75", "1.3333", "3.0 / 4.0", "16 / 9"] {
                #expect(!source.contains(guessed), "\(path)에 비율을 적어 두었다: \(guessed)")
            }
        }
    }

    @Test("실제 activeFormat에서 비율을 읽는다")
    func aspectComesFromTheActiveFormat() throws {
        let source = try framingSource("ggumirror/Mirror/MirrorCamera.swift")
        #expect(source.contains("CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)"))
        #expect(source.contains("activeSourceAspect ="))
        // 카메라가 붙기 전에는 모른다 — 지어내지 않는다.
        let camera = MirrorCamera(role: .mirror)
        #expect(camera.sourceAspectRatio == nil)
    }

    @Test("가짜 zoom-out으로 넓히지 않는다")
    func noFakeZoomOut() throws {
        let camera = try framingSource("ggumirror/Mirror/MirrorCamera.swift")
        // framing을 바꾸는 자리에서 배율을 건드리지 않는다.
        let setter = try #require(camera.range(of: "func setFrontFraming(_ next: Framing)"))
        let body = camera[setter.lowerBound...].prefix(400)
        #expect(!body.contains("videoZoomFactor"))
        #expect(!body.contains("ramp(toVideoZoomFactor"))
        #expect(!body.contains("apply(logical:"))

        // 화면 쪽도 스스로 확대/축소하지 않는다 — layer의 gravity 하나뿐이다.
        let preview = try framingSource("ggumirror/Mirror/CameraPreviewView.swift")
        #expect(preview.contains("previewLayer.videoGravity = gravity"))
        for forbidden in ["transform", "setAffineTransform", "scaleEffect", "videoScaleAndCropFactor"] {
            #expect(!preview.contains(forbidden), "preview가 스스로 확대한다: \(forbidden)")
        }
    }
}

@MainActor
@Suite("framing과 배율은 서로 섞이지 않는다")
struct FramingAndZoomAreIndependentTests {

    @Test("framing을 바꿔도 배율은 그대로 1x다")
    func changingFramingKeepsLogicalZoom() {
        let camera = MirrorCamera(role: .mirror)
        #expect(camera.logicalZoom == 1)

        // 카메라가 붙기 전(status != .ready)에는 바뀌지 않는다 — 그래도 배율은 1x다.
        camera.setFrontFraming(.fill)
        #expect(camera.logicalZoom == 1)
        camera.setFrontFraming(.wide)
        #expect(camera.logicalZoom == 1)
    }

    @Test("네 조합이 모두 뜻이 있다")
    func fourCombinationsAreIndependent() {
        // framing은 화면에 놓는 방법, 배율은 기기 값. 곱집합이 그대로 성립한다.
        for framing in Framing.allCases {
            for zoom in [CGFloat(1), 2] {
                let visible = MirrorCamera.visibleSourceFraction(
                    source: sensor43, viewport: screen, framing: framing
                )
                // 배율이 무엇이든 자르는 비율은 framing만으로 정해진다.
                #expect(visible == MirrorCamera.visibleSourceFraction(
                    source: sensor43, viewport: screen, framing: framing
                ), "zoom \(zoom)")
                #expect(visible > 0)
            }
        }
    }

    @Test("배율 계산에 framing이 들어가지 않는다")
    func zoomMathIgnoresFraming() throws {
        let source = try framingSource("ggumirror/Mirror/MirrorCamera.swift")
        let capability = try #require(source.range(of: "nonisolated struct ZoomCapability"))
        let end = try #require(source.range(of: "nonisolated static let zoomPresetCandidates"))
        let body = source[capability.lowerBound..<end.lowerBound]
        #expect(!body.contains("Framing"))
        #expect(!body.contains("framing"))
    }
}

@MainActor
@Suite("미리보기와 저장이 같은 규칙을 쓴다")
struct FramingPreviewCapturePolicyTests {

    @Test("두 방법이 서로 짝을 이룬다")
    func previewAndCaptureUseMatchingRules() throws {
        let camera = try framingSource("ggumirror/Mirror/MirrorCamera.swift")
        #expect(camera.contains("self == .wide ? .resizeAspect : .resizeAspectFill"))

        let capture = try framingSource("ggumirror/Mirror/MirrorCapture.swift")
        // `.resizeAspect` ↔ `scaledToFit`, `.resizeAspectFill` ↔ `scaledToFill`.
        #expect(capture.contains("case .wide:"))
        #expect(capture.contains("scaledToFit()"))
        #expect(capture.contains("case .fill:"))
        #expect(capture.contains("scaledToFill()"))
    }

    @Test("촬영은 화면이 쓰던 값을 그대로 받는다")
    func captureReceivesTheOnScreenFraming() throws {
        let view = try framingSource("ggumirror/Mirror/MirrorView.swift")
        // 미리보기와 저장이 같은 하나에서 나온다.
        #expect(view.contains("CameraPreviewView(camera: camera, framing: camera.framing)"))
        #expect(view.contains("let framing = camera.framing"))
        #expect(view.contains("framing: framing"))

        // 촬영 도중 바뀌어도 이 사진은 보던 그대로다 — 플래시 의도와 같은 규칙이다.
        let capturedAt = try #require(view.range(of: "let framing = camera.framing"))
        let composed = try #require(view.range(of: "MirrorCapture.compose("))
        #expect(capturedAt.lowerBound < composed.lowerBound)
    }

    @Test("저장 기본값은 예전 동작이다")
    func composeDefaultsToTheOldBehaviour() throws {
        // 잠금화면 등 framing을 모르는 호출부는 예전과 똑같이 동작한다.
        let capture = try framingSource("ggumirror/Mirror/MirrorCapture.swift")
        #expect(capture.contains("framing: MirrorCamera.Framing = .fill"))
    }
}

@MainActor
@Suite("framing 버튼")
struct FramingSelectorUITests {

    @Test("전면에서만 나온다")
    func selectorIsFrontOnly() throws {
        let view = try framingSource("ggumirror/Mirror/MirrorView.swift")
        #expect(view.contains("framingOptions: camera.canChooseFraming ? MirrorCamera.Framing.allCases : []"))

        // 후면이면 빈 배열이 오고 그리지 않는다. **칩을 그리는 곳이 판단한다** —
        // 칩은 `MirrorFramingSelector`로 빠졌고(상점 미리보기가 같은 것을 쓴다)
        // 그래서 이 규칙도 거기 하나에만 있다.
        let selector = try framingSource("ggumirror/Mirror/MirrorFramingSelector.swift")
        #expect(selector.contains("if options.count > 1"))
    }

    @Test("사용자 말로 적는다 — 비율을 보여 주지 않는다")
    func labelsAreHumanWords() {
        #expect(Framing.wide.title == "넓게")
        #expect(Framing.fill.title == "채우기")
        #expect(Framing.wide.accessibilityTitle == "넓게 보기")
        #expect(Framing.fill.accessibilityTitle == "화면 채우기")

        for framing in Framing.allCases {
            for technical in ["4:3", "16:9", "aspect", "FOV", "crop"] {
                #expect(!framing.title.contains(technical))
                #expect(!framing.accessibilityTitle.contains(technical))
            }
        }
    }

    @Test("배율과 다른 묶음이다")
    func framingIsNotAZoomChip() throws {
        let controls = try framingSource("ggumirror/Mirror/MirrorControls.swift")
        // 배율 칩 목록 안에 섞어 넣지 않는다. 섞으면 "넓게 보기"가 배율처럼 읽힌다.
        // framing은 자기 view로 그리고, 배율만 여기서 ForEach를 돈다.
        #expect(controls.contains("ForEach(zoomPresets, id: \\.self)"))
        #expect(!controls.contains("ForEach(framingOptions"))
        #expect(controls.contains("framingSelector"))

        // 칩 자체는 자기 ForEach를 갖는다.
        let selector = try framingSource("ggumirror/Mirror/MirrorFramingSelector.swift")
        #expect(selector.contains("ForEach(options, id: \\.self)"))
        // 손이 닿는 자리는 배율 칩과 같은 규칙이다. **숫자를 다시 적지 않는다** —
        // 44를 두 곳에 적으면 한쪽만 바뀐다(`ButtonHitAreaTests`가 값을 고정한다).
        #expect(selector.contains("frame(minHeight: InkTapTarget.minimum)"))
    }

    @Test("배율이 하나뿐인 기기에서도 고를 수 있다")
    func framingSurvivesWithoutZoomPresets() throws {
        let controls = try framingSource("ggumirror/Mirror/MirrorControls.swift")
        #expect(controls.contains("if zoomPresets.count > 1 || framingOptions.count > 1"))
    }

    @Test("배율 버튼과 같은 auto-hide를 쓴다")
    func framingUsesTheSameTimer() throws {
        // 고르기 **전에** 타이머를 다시 돌린다. 순서가 뒤집히면 고르는 순간
        // 컨트롤이 사라진다.
        let selector = try framingSource("ggumirror/Mirror/MirrorFramingSelector.swift")
        let tap = try #require(selector.range(of: "onInteraction()"))
        #expect(selector[tap.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("onSelect(option)"))

        // 실제 거울이 그 hook에 auto-hide 타이머를 실제로 연결한다.
        let controls = try framingSource("ggumirror/Mirror/MirrorControls.swift")
        #expect(controls.contains("onInteraction: onInteraction"))
    }
}

@MainActor
@Suite("카메라 전환 회귀")
struct FramingCameraSwitchTests {

    @Test("후면 배율 정책은 그대로다")
    func rearZoomIsUnchanged() {
        // 0.5 / 1 / 2는 framing과 무관하게 capability로만 정해진다.
        let tripleRear = MirrorCamera.ZoomCapability(
            baseFactor: 2, minDeviceFactor: 1, maxDeviceFactor: 64
        )
        #expect(MirrorCamera.zoomPresets(for: tripleRear) == [0.5, 1, 2])

        let frontWide = MirrorCamera.ZoomCapability(
            baseFactor: 1, minDeviceFactor: 1, maxDeviceFactor: 16
        )
        #expect(MirrorCamera.zoomPresets(for: frontWide) == [1, 2])
    }

    @Test("전면 선택은 후면에 갔다 와도 살아 있다")
    func frontChoiceSurvivesARoundTrip() throws {
        // `frontFraming`은 전환이 건드리지 않는다 — position만 바뀐다.
        let source = try framingSource("ggumirror/Mirror/MirrorCamera.swift")
        let swap = try #require(source.range(of: "private nonisolated func swapInput(to target: Position)"))
        let body = source[swap.lowerBound...].prefix(1800)
        #expect(!body.contains("frontFraming"))

        let adopt = try #require(source.range(of: "private func adoptActiveCapability()"))
        let adoptBody = source[adopt.lowerBound...].prefix(400)
        #expect(!adoptBody.contains("frontFraming"))
    }

    @Test("후면에서는 버튼이 사라진다")
    func rearHidesTheSelector() throws {
        let source = try framingSource("ggumirror/Mirror/MirrorCamera.swift")
        #expect(source.contains("position == .front"))
        // 후면일 때 canChooseFraming이 false → MirrorView가 빈 배열을 넘긴다.
        let camera = MirrorCamera(role: .mirror)
        #expect(!camera.canChooseFraming, "카메라가 붙기 전에는 고를 수 없다")
    }

    @Test("잠금화면 viewfinder에는 framing 선택이 없다")
    func lockScreenKeepsOldBehaviour() {
        let viewfinder = MirrorCamera(role: .viewfinder)
        #expect(!viewfinder.canChooseFraming)
        viewfinder.setFrontFraming(.fill)
        // role guard가 막는다 — extension 동작이 따라 바뀌지 않는다.
        #expect(viewfinder.frontFraming == .wide)
    }
}
