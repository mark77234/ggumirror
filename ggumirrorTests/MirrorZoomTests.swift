//
//  MirrorZoomTests.swift
//  ggumirrorTests
//
//  거울 카메라 배율. **기기 이름을 쓰지 않는다** — capability 값으로만 시험한다.
//
//  가장 위험한 회귀는 0.5x다. ultra-wide를 품은 virtual 카메라에서
//  `videoZoomFactor == 1`은 1x가 아니라 0.5x라서, 그 차이를 모르면
//  0.5x 화면을 1x라고 표시하거나 없는 0.5x 버튼을 보여 주게 된다.
//

import Testing
import AVFoundation
import Foundation
import CoreGraphics
@testable import ggumirror

private typealias Capability = MirrorCamera.ZoomCapability

/// repo 소스 한 파일. 주석은 걷어낸다 — 설명 문구가 규칙 검사에 걸리면 안 된다.
private func zoomSource(_ path: String) throws -> String {
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

/// 일반 wide 카메라 하나. `1`이 곧 1x다. (전면이 언제나 이 모양이다.)
private func wideOnly(max: CGFloat = 16) -> Capability {
    Capability(baseFactor: 1, minDeviceFactor: 1, maxDeviceFactor: max)
}

/// ultra-wide + wide. `1`이 0.5x이고 사용자가 아는 1x는 전환 지점 `2`다.
private func withUltraWide(base: CGFloat = 2, max: CGFloat = 64) -> Capability {
    Capability(baseFactor: base, minDeviceFactor: 1, maxDeviceFactor: max)
}

@Suite("logical ↔ device 배율 변환")
struct ZoomMappingTests {

    @Test("ultra-wide로 시작하는 렌즈에서만 1x가 device 2다")
    func baseFactorComesFromHardware() {
        // 첫 렌즈가 ultra-wide → 첫 전환 지점이 1x다.
        #expect(MirrorCamera.baseZoomFactor(
            constituentTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera],
            switchOverFactors: [2]
        ) == 2)

        // 3개짜리도 같다 — 두 번째 전환(tele)은 1x 위치를 바꾸지 않는다.
        #expect(MirrorCamera.baseZoomFactor(
            constituentTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            switchOverFactors: [2, 10]
        ) == 2)

        // 첫 렌즈가 wide면 1이 곧 1x다. 전환 지점이 있어도 마찬가지다.
        #expect(MirrorCamera.baseZoomFactor(
            constituentTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera],
            switchOverFactors: [3]
        ) == 1)

        // 물리 카메라 하나(전면). 알려주는 것이 아무것도 없다.
        #expect(MirrorCamera.baseZoomFactor(constituentTypes: [], switchOverFactors: []) == 1)

        // 값이 깨져 있어도 0으로 나누지 않는다.
        #expect(MirrorCamera.baseZoomFactor(
            constituentTypes: [.builtInUltraWideCamera], switchOverFactors: [0]
        ) == 1)
    }

    @Test("0.5x는 실제 ultra-wide device factor로 간다")
    func halfMapsToTheUltraWideLens() {
        let capability = withUltraWide()
        // **여기가 회귀 지점이다.** 0.5x는 device 0.5가 아니라 device 1이다.
        #expect(capability.deviceFactor(forLogical: 0.5) == 1)
        #expect(capability.deviceFactor(forLogical: 1) == 2)
        #expect(capability.deviceFactor(forLogical: 2) == 4)
        #expect(capability.logical(forDeviceFactor: 1) == 0.5)
    }

    @Test("wide 하나뿐이면 logical과 device가 같다")
    func wideOnlyMapsOneToOne() {
        let capability = wideOnly()
        #expect(capability.deviceFactor(forLogical: 1) == 1)
        #expect(capability.deviceFactor(forLogical: 2) == 2)
        #expect(capability.minLogical == 1)
    }

    @Test("변환은 언제나 실제 범위 안이다")
    func mappingNeverLeavesTheRange() {
        let capability = withUltraWide(max: 8)
        // 0.5x 아래를 요구해도 렌즈 한계에서 멈춘다.
        #expect(capability.deviceFactor(forLogical: 0.1) == 1)
        #expect(capability.deviceFactor(forLogical: 99) == 8)
        #expect(capability.clampedLogical(0.1) == 0.5)
        #expect(capability.clampedLogical(99) == 4)
    }
}

@Suite("배율 버튼은 기기가 정한다")
struct ZoomPresetTests {

    @Test("후보 셋은 0.5 · 1 · 2다")
    func candidatesAreDataDriven() {
        #expect(MirrorCamera.zoomPresetCandidates == [0.5, 1, 2])
    }

    @Test("0.5x는 ultra-wide가 있을 때만 나온다")
    func halfNeedsTheLens() {
        #expect(MirrorCamera.zoomPresets(for: withUltraWide()) == [0.5, 1, 2])
        // 전면처럼 wide 하나뿐이면 감춘다 — software로 만들어내지 않는다.
        #expect(MirrorCamera.zoomPresets(for: wideOnly()) == [1, 2])
    }

    @Test("최대가 2x에 못 미치면 2x를 감춘다")
    func twoDisappearsBelowItsRange() {
        #expect(MirrorCamera.zoomPresets(for: wideOnly(max: 1.5)) == [1])
        #expect(MirrorCamera.zoomPresets(for: wideOnly(max: 2)) == [1, 2])
        // ultra-wide 기기도 같은 규칙이다(device 4 = logical 2).
        #expect(MirrorCamera.zoomPresets(for: withUltraWide(max: 3)) == [0.5, 1])
        #expect(MirrorCamera.zoomPresets(for: withUltraWide(max: 4)) == [0.5, 1, 2])
    }

    @Test("아무것도 없으면 1x 하나다")
    func noCameraKeepsOnePreset() {
        #expect(MirrorCamera.zoomPresets(for: .none) == [1])
    }

    @Test("나중에 3x를 더하려면 후보 목록에만 더한다")
    func candidatesExtendWithoutNewLogic() {
        let tele = Capability(baseFactor: 1, minDeviceFactor: 1, maxDeviceFactor: 10)
        #expect(
            MirrorCamera.zoomPresets(for: tele, candidates: [0.5, 1, 2, 3, 5]) == [1, 2, 3, 5]
        )
    }

    @Test("반올림 오차가 preset을 지우지 않는다")
    func epsilonKeepsExactBoundaries() {
        // 기기가 0.5를 정확히 못 맞춰 device 최대가 3.9999로 오는 경우.
        #expect(MirrorCamera.zoomPresets(for: withUltraWide(max: 3.99999)).contains(2))
    }
}

@Suite("켜져 보이는 버튼과 실제 배율은 같다")
struct ZoomSelectionTests {
    private let presets: [CGFloat] = [0.5, 1, 2]

    @Test("preset 위에 있으면 그 버튼이 켜진다")
    func exactValueSelectsItsPreset() {
        #expect(MirrorCamera.selectedPreset(logical: 1, presets: presets) == 1)
        #expect(MirrorCamera.selectedPreset(logical: 0.5, presets: presets) == 0.5)
        #expect(MirrorCamera.selectedPreset(logical: 2, presets: presets) == 2)
    }

    @Test("사이 값이면 아무 버튼도 켜지지 않는다")
    func inBetweenSelectsNothing() {
        // pinch로 1.37x에 있는데 `2x`가 켜져 보이면 화면이 거짓말을 한다.
        #expect(MirrorCamera.selectedPreset(logical: 1.37, presets: presets) == nil)
        #expect(MirrorCamera.selectedPreset(logical: 1.43, presets: presets) == nil)
        #expect(MirrorCamera.selectedPreset(logical: 0.72, presets: presets) == nil)
    }

    @Test("아주 가까우면 그 preset으로 본다")
    func nearlyExactStillSelects() {
        #expect(MirrorCamera.selectedPreset(logical: 1.02, presets: presets) == 1)
        #expect(MirrorCamera.selectedPreset(logical: 1.06, presets: presets) == nil)
    }

    @Test("감춰진 preset은 켜지지 않는다")
    func hiddenPresetNeverSelects() {
        // 전면(0.5x 없음)에서 어떤 값이 와도 0.5가 켜질 수 없다.
        #expect(MirrorCamera.selectedPreset(logical: 0.5, presets: [1, 2]) == nil)
    }
}

@Suite("pinch")
struct ZoomPinchTests {

    /// gesture 하나를 흉내 낸다. `magnification`은 **시작 시점 대비 배수**다.
    private func pinch(from start: CGFloat, by magnification: CGFloat, in capability: Capability) -> CGFloat {
        capability.clampedLogical(start * magnification)
    }

    @Test("확대 · 축소")
    func pinchMovesBothWays() {
        let capability = withUltraWide()
        #expect(pinch(from: 1, by: 2, in: capability) == 2)
        #expect(pinch(from: 2, by: 0.5, in: capability) == 1)
        #expect(pinch(from: 1, by: 1.37, in: capability) == 1.37)
    }

    @Test("최소 · 최대에서 멈춘다")
    func pinchClampsAtBothEnds() {
        let capability = withUltraWide(max: 8)
        // 0.5x 아래로는 갈 수 없다 — 없는 화각을 만들어내지 않는다.
        #expect(pinch(from: 1, by: 0.01, in: capability) == 0.5)
        #expect(pinch(from: 1, by: 1000, in: capability) == 4)

        // wide 하나뿐이면 1x 아래가 없다.
        #expect(pinch(from: 1, by: 0.2, in: wideOnly()) == 1)
    }

    @Test("한 gesture 안에서는 시작 배율이 기준이다")
    func baselineHoldsThroughTheGesture() {
        let capability = withUltraWide()
        let baseline: CGFloat = 1.5
        // 같은 gesture가 계속 오는 동안 기준은 바뀌지 않는다.
        #expect(abs(pinch(from: baseline, by: 1.2, in: capability) - 1.8) < 0.0001)
        #expect(abs(pinch(from: baseline, by: 0.8, in: capability) - 1.2) < 0.0001)
        #expect(pinch(from: baseline, by: 1, in: capability) == baseline)
    }

    @Test("다음 gesture는 끝난 자리에서 시작한다")
    func consecutiveGesturesCompound() {
        let capability = withUltraWide()
        let afterFirst = pinch(from: 1, by: 1.5, in: capability)
        #expect(afterFirst == 1.5)
        // 두 번째 gesture의 magnification도 1부터 시작하지만 기준은 1.5다.
        #expect(pinch(from: afterFirst, by: 2, in: capability) == 3)
    }

    @Test("pinch 뒤 preset을 누르면 정확히 그 값이다")
    func presetAfterPinchIsExact() {
        let capability = withUltraWide()
        let pinched = pinch(from: 1, by: 1.43, in: capability)
        #expect(MirrorCamera.selectedPreset(logical: pinched, presets: [0.5, 1, 2]) == nil)

        // `1x` 버튼 → 정확히 1x, 기기 값은 전환 지점이다.
        #expect(capability.clampedLogical(1) == 1)
        #expect(capability.deviceFactor(forLogical: 1) == 2)
        // `2x` 버튼 → 정확히 2x.
        #expect(capability.deviceFactor(forLogical: 2) == 4)
    }

    @Test("pinch는 ramp를 쓰지 않고 손가락을 따라간다")
    func pinchDoesNotRamp() throws {
        let source = try zoomSource("ggumirror/Mirror/MirrorCamera.swift")
        #expect(source.contains("apply(logical: baseline * magnification, ramps: false)"))
        #expect(source.contains("device.cancelVideoZoomRamp()"))
        // preset은 짧게 미끄러진다.
        #expect(source.contains("device.ramp(toVideoZoomFactor: safe, withRate: Self.zoomRampRate)"))
        #expect(MirrorCamera.zoomRampRate >= 6, "cinematic ramp는 거울에 느리다")
    }
}

@Suite("배율 표시")
struct ZoomLabelTests {

    @Test("정수는 소수점을 붙이지 않는다")
    func labelFormatting() {
        #expect(MirrorControls.zoomLabel(0.5) == "0.5x")
        #expect(MirrorControls.zoomLabel(1) == "1x")
        #expect(MirrorControls.zoomLabel(2) == "2x")
        #expect(MirrorControls.zoomLabel(1.37) == "1.4x")
    }

    @Test("낭독기는 우리말로 읽는다")
    func accessibilityLabels() {
        #expect(MirrorControls.zoomAccessibilityLabel(0.5) == "0.5배")
        #expect(MirrorControls.zoomAccessibilityLabel(1) == "1배")
        #expect(MirrorControls.zoomAccessibilityLabel(2) == "2배")
    }
}

@Suite("배율 UI는 기존 control set의 일부다")
struct ZoomControlIntegrationTests {

    private func source(_ path: String) throws -> String { try zoomSource(path) }

    @Test("고를 것이 하나뿐이면 그리지 않는다")
    func singlePresetHidesTheSelector() throws {
        #expect(try source("ggumirror/Mirror/MirrorControls.swift").contains("if zoomPresets.count > 1"))
    }

    @Test("손가락이 닿는 자리는 44pt다")
    func tapTargetIsBigEnough() throws {
        #expect(try source("ggumirror/Mirror/MirrorControls.swift")
            .contains("frame(minWidth: 44, minHeight: 44)"))
    }

    @Test("배율 버튼도 auto-hide 타이머를 다시 돌린다")
    func zoomKeepsControlsAlive() throws {
        // 새 timer를 만들지 않고 기존 `onInteraction`을 쓴다.
        let controls = try source("ggumirror/Mirror/MirrorControls.swift")
        #expect(controls.contains("onInteraction()\n            onSelectZoom(preset)"))

        let view = try source("ggumirror/Mirror/MirrorView.swift")
        // pinch도 같은 타이머를 민다.
        #expect(view.contains("camera.updatePinch(magnification: value.magnification)"))
        #expect(view.contains("camera.endPinch()"))
        #expect(view.components(separatedBy: "registerInteraction()").count - 1 >= 3)
        // 새 타이머 체계를 만들지 않았다.
        #expect(view.components(separatedBy: "Duration.milliseconds").count - 1 == 1)
    }

    @Test("배율 UI는 컨트롤이 보일 때만 있다")
    func zoomLivesInsideTheControlSet() throws {
        let view = try source("ggumirror/Mirror/MirrorView.swift")
        let controlsBlock = try #require(view.range(of: "if areControlsVisible {"))
        let zoom = try #require(view.range(of: "zoomPresets: camera.zoomPresets"))
        #expect(controlsBlock.lowerBound < zoom.lowerBound)
    }

    @Test("두 손가락 pinch는 한 손가락 탭과 섞이지 않는다")
    func pinchDoesNotFightTheTapGesture() throws {
        let view = try source("ggumirror/Mirror/MirrorView.swift")
        #expect(view.contains("MagnifyGesture"))
        // 탭으로 컨트롤을 여닫는 기존 동작은 그대로다.
        #expect(view.contains(".onTapGesture { toggleControls() }"))
    }

    @Test("잠금화면 viewfinder에는 배율이 없다")
    func lockScreenHasNoZoom() throws {
        let camera = try source("ggumirror/Mirror/MirrorCamera.swift")
        // 세 곳 모두 role을 확인한다 — extension에서 배율이 움직이면 안 된다.
        #expect(camera.contains("guard role == .mirror, zoomCapability.supports(logical: logical)"))
        #expect(camera.contains("var canZoom: Bool { role == .mirror"))
        #expect(camera.components(separatedBy: "guard role == .mirror").count - 1 >= 2)
    }
}
