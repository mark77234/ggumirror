//
//  MirrorPreviewFramingTests.swift
//  ggumirrorTests
//
//  **상점 미리보기의 `넓게` / `채우기`는 새 기능이 아니라 기존 것의 재사용이다.**
//
//  자르는 방법의 authority는 `MirrorCamera.Framing` 하나다. 미리보기가 자기만의
//  비율 계산을 갖는 순간 실제 거울과 다르게 보이기 시작하므로, 그 일이 일어나지
//  않는다는 것을 소스 레벨로 고정한다.
//

import Testing
import AVFoundation
import CoreGraphics
import Foundation
@testable import ggumirror

private func source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

private let previewPath = "ggumirror/Mirror/MirrorLivePreview.swift"
private let selectorPath = "ggumirror/Mirror/MirrorFramingSelector.swift"
private let controlsPath = "ggumirror/Mirror/MirrorControls.swift"

@Suite("미리보기와 실제 거울이 같은 authority를 쓴다")
struct PreviewFramingAuthorityTests {

    @Test("미리보기에 자기만의 비율 계산이 없다")
    func noPreviewOnlyFramingMath() throws {
        let preview = try source(previewPath)
        // 자르는 방법은 enum이 정한다 — 여기서 gravity를 직접 고르지 않는다.
        #expect(preview.contains("MirrorCamera.Framing"))
        for forbidden in [
            "resizeAspect", "videoGravity", "previewGravity",
            "0.75", "4.0 / 3.0", "4 / 3", "aspectRatio(1",
        ] {
            #expect(!preview.contains(forbidden), "미리보기가 \(forbidden)를 직접 정한다")
        }
    }

    @Test("gravity 매핑은 한 곳에만 있다")
    func oneGravityMapping() throws {
        // 실제 거울과 미리보기가 같은 함수를 지난다.
        #expect(MirrorCamera.Framing.wide.previewGravity == .resizeAspect)
        #expect(MirrorCamera.Framing.fill.previewGravity == .resizeAspectFill)
        let camera = try source("ggumirror/Mirror/MirrorCamera.swift")
        // `previewGravity`를 계산하는 자리는 `MirrorCamera` 하나다.
        #expect(camera.contains("self == .wide ? .resizeAspect : .resizeAspectFill"))
    }

    @Test("칩도 한 곳에서만 그린다")
    func oneSelectorComponent() throws {
        let controls = try source(controlsPath)
        let preview = try source(previewPath)
        // 실제 거울과 미리보기가 같은 component를 쓴다.
        #expect(controls.contains("MirrorFramingSelector("))
        #expect(preview.contains("MirrorFramingSelector("))
        // 사본이 남아 있지 않다.
        #expect(!controls.contains("private func framingChip"))
    }

    @Test("칩의 닿는 자리는 44pt다")
    func hitTargetIsKept() throws {
        let selector = try source(selectorPath)
        #expect(selector.contains("minHeight: InkTapTarget.minimum"))
        // chrome이 label 안에 있고 `.contentShape`이 걸려 있다.
        #expect(selector.contains(".contentShape(.rect)"))
        #expect(InkTapTarget.minimum >= 44)
    }

    @Test("고를 것이 하나뿐이면 그리지 않는다")
    func noDeadSelector() throws {
        #expect(try source(selectorPath).contains("options.count > 1"))
    }
}

@Suite("기본값은 화면 채우기")
struct PreviewFramingDefaultTests {

    @Test("첫 진입은 채우기다")
    func defaultFills() throws {
        // 실제 거울과 **같은 상수**를 읽으므로 거울 기본값이 바뀌면 함께 바뀐다.
        #expect(MirrorCamera.Framing.initial == .fill)
        // 미리보기가 자기 기본값을 따로 적지 않는다 — 같은 상수를 읽는다.
        #expect(try source(previewPath).contains("MirrorCamera.Framing.initial"))
    }

    @Test("넓게가 실제로 덜 자른다")
    func wideCropsLess() {
        // 전면 센서(4:3에 가까움)를 세로로 긴 화면에 놓는 상황.
        let source = CGSize(width: 1080, height: 1440)
        let viewport = CGSize(width: 1080, height: 2340)
        let wide = MirrorCamera.visibleSourceFraction(
            source: source, viewport: viewport, framing: .wide
        )
        let fill = MirrorCamera.visibleSourceFraction(
            source: source, viewport: viewport, framing: .fill
        )
        #expect(wide == 1)
        #expect(fill < wide, "채우기가 넓게보다 덜 자른다")
    }
}

@Suite("자르는 방법만 바뀐다")
struct PreviewFramingSwitchingTests {

    @Test("장식은 자르는 방법을 읽지 않는다")
    func decorationIgnoresFraming() throws {
        let preview = try source(previewPath)
        // 장식 layer를 그리는 자리에 framing이 들어가지 않는다 —
        // 그래서 칩을 눌러도 프레임·글씨·스티커가 움직일 수 없다.
        let start = try #require(preview.range(of: "private var decoration")).upperBound
        let end = try #require(
            preview.range(of: "private var framingSelector", range: start..<preview.endIndex)
        ).lowerBound
        #expect(!preview[start..<end].contains("framing"))
    }

    @Test("자르는 방법은 카메라 layer 하나에만 걸린다")
    func onlyTheCameraLayerTakesIt() throws {
        let preview = try source(previewPath)
        #expect(preview.contains("CameraPreviewView(camera: camera, framing: framing)"))
        // 넘기는 자리가 하나뿐이다.
        #expect(preview.components(separatedBy: "framing: framing").count - 1 == 1)
    }

    @Test("세션을 다시 시작하지 않는다")
    func switchingDoesNotRestartTheSession() throws {
        let layer = try source("ggumirror/Mirror/CameraPreviewView.swift")
        // 자르는 방법이 바뀌면 layer의 gravity 하나만 바뀐다.
        #expect(layer.contains("previewLayer.videoGravity = gravity"))
        // 같은 값이면 아무 일도 하지 않는다 — 연속으로 눌러도 깜빡이지 않는다.
        #expect(layer.contains("guard previewLayer.videoGravity != gravity else { return }"))
        // 세션을 다시 붙이거나 멈추지 않는다.
        let apply = layer.range(of: "func apply(_ framing:")!.upperBound
        #expect(!layer[apply...].contains("session ="))
        #expect(!layer[apply...].contains(".start()"))
    }
}

@Suite("미리보기가 무엇도 다시 만들지 않는다")
struct PreviewFramingCostTests {

    @Test("도려내기를 다시 돌리지 않는다")
    func knockoutNeverReruns() throws {
        let file = try source(previewPath)
        // 도려내기는 상세 화면이 미리보기를 **열기 전에** 한 번 부르는 factory에 있다.
        // 미리보기 화면(`MirrorLivePreviewView`) 안에서는 부르는 자리가 없어야 한다 —
        // 그래야 칩을 눌러도 2.5M 픽셀을 다시 훑지 않는다.
        let screen = try #require(file.range(of: "struct MirrorLivePreviewView")).lowerBound
        let body = String(file[screen...])
        #expect(!body.contains("cameraOpeningRemoved"))
        #expect(!body.contains("MirrorThumbnailNormalizer"))
        // factory는 그대로 파일 앞쪽에 있다.
        #expect(file.contains("cameraOpeningRemoved"))
    }

    @Test("그림도 한 번만 해독한다")
    func overlayIsDecodedOnce() throws {
        let preview = try source(previewPath)
        // 자르는 방법을 바꿀 때마다 1.66MB PNG를 다시 풀지 않는다.
        #expect(preview.contains("overlayImage == nil"))
        #expect(preview.components(separatedBy: "UIImage(data:").count - 1 == 1)
    }

    @Test("실제 거울 설정을 바꾸지 않는다")
    func actualCameraPreferenceIsUntouched() throws {
        let preview = try source(previewPath)
        // `setFrontFraming`은 실제 거울 화면의 사용자 설정이다.
        #expect(!preview.contains("setFrontFraming"))
        #expect(!preview.contains("frontFraming"))
    }

    @Test("미리보기는 여전히 아무것도 바꾸지 않는다")
    func stillNoMutation() throws {
        let preview = try source(previewPath)
        for forbidden in [
            "purchase(", "acquire(", "adopt(", "downloadCount", "balance",
            "persist(", "importMirror", "importSticker", "session",
            "UserDefaults", "AppStorage",
        ] {
            #expect(!preview.contains(forbidden), "미리보기가 \(forbidden)를 건드린다")
        }
    }

    @Test("카메라 조작은 늘지 않았다")
    func noNewCameraControls() throws {
        let preview = try source(previewPath)
        for forbidden in [
            "capturePhoto", "MirrorCapture", "switchCamera", "flash",
            "selectZoom", "updatePinch", "MagnifyGesture", "zoomPresets",
        ] {
            #expect(!preview.contains(forbidden), "미리보기에 \(forbidden)가 생겼다")
        }
    }
}
