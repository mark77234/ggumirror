//
//  CameraSwitchFlashTests.swift
//  ggumirrorTests
//
//  C-2B — 전/후면 전환 + 플래시 ON/OFF.
//
//  여기서 고정하는 것:
//  1. 앱은 항상 전면에서 시작한다. 후면 선택을 저장하지 않는다
//  2. 전면만 좌우를 뒤집는다. 후면은 그대로다
//  3. 전환 실패는 **작동하던 카메라를 잃지 않는다**
//  4. 플래시는 OFF/ON 둘뿐이고, 지원하지 않는 mode를 요청하지 않는다
//  5. 잠금화면 extension은 전면 고정 · 전환 없음 · 플래시 없음 — 하나도 안 바뀐다
//

import AVFoundation
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ggumirror

@MainActor
struct CameraSwitchFlashTests {

    private func repoFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    private func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - 카메라 위치

    @Test("기본은 전면이다 — 후면 선택을 앱 재실행까지 저장하지 않는다")
    func defaultIsFront() throws {
        #expect(MirrorCamera.Position.initial == .front)
        #expect(MirrorCamera(role: .mirror).position == .front)

        // 저장소에 카메라 위치를 남기는 코드가 없다.
        let camera = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        for forbidden in ["UserDefaults", "AppStorage", "MirrorStore", "@AppStorage"] {
            #expect(!camera.contains(forbidden), "카메라 위치를 저장하고 있다: \(forbidden)")
        }
        let view = codeOnly(try repoFile("ggumirror/Mirror/MirrorView.swift"))
        #expect(!view.contains("UserDefaults"))
        #expect(!view.contains("AppStorage"))
    }

    @Test("전면 ↔ 후면은 서로를 가리킨다")
    func positionsFlip() {
        #expect(MirrorCamera.Position.front.flipped == .back)
        #expect(MirrorCamera.Position.back.flipped == .front)
        #expect(MirrorCamera.Position.front.av == .front)
        #expect(MirrorCamera.Position.back.av == .back)
    }

    @Test("전면만 좌우를 뒤집는다")
    func onlyFrontIsMirrored() {
        #expect(MirrorCamera.Position.front.isMirrored)
        #expect(!MirrorCamera.Position.back.isMirrored, "후면이 뒤집히면 글씨가 거꾸로 보인다")
    }

    @Test("전환은 성공한 결과만 반영한다")
    func switchOnlyReportsWhatLanded() throws {
        // swapInput은 실패하면 **바꾸기 전 position**을 돌려주고, position은 그 값을 받는다.
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        #expect(source.contains("position = landed"))
        #expect(source.contains("return target.flipped"), "실패 시 이전 position을 돌려주지 않는다")
        // 성공 경로에서만 세션 쪽 진실이 바뀐다.
        #expect(source.contains("activePosition = target"))
    }

    @Test("전환 실패는 이전 input을 되살린다")
    func failedSwitchRestoresPreviousInput() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        // canAddInput이 거부되면 원래 input을 다시 붙이고 반전도 다시 건다.
        #expect(source.contains("if session.canAddInput(existing)"))
        #expect(source.contains("session.addInput(existing)"))
        // 되돌리기까지 실패하면 다음 start()가 처음부터 구성할 수 있게 비운다.
        #expect(source.contains("isConfigured = false"))
    }

    @Test("전환 중에는 다시 전환하지 않는다 — 연타 안전")
    func rapidSwitchingIsGuarded() throws {
        let camera = MirrorCamera(role: .mirror)
        // 아직 준비되지 않았으면 전환 자체를 시작하지 않는다.
        #expect(!camera.canSwitchCamera)
        #expect(!camera.isSwitching)

        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        #expect(source.contains("guard canSwitchCamera else { return }"))
        #expect(source.contains("isSwitching = true"))
        #expect(source.contains("defer { isSwitching = false }"))
        // 대기 큐를 만들지 않는다.
        #expect(!source.contains("pendingSwitch"))
    }

    @Test("전환은 세션 큐에서만 일어난다 — retry와 자연히 직렬화된다")
    func switchingSerializesWithRetry() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        // 세션을 바꾸는 곳은 sessionQueue 안이다. 별도 lock을 만들지 않았다.
        #expect(source.contains("sessionQueue.async"))
        #expect(!source.contains("NSLock()") || source.contains("LatestFrameStore"))
        // .denied만 최종이라는 retry 정책은 그대로다 (C-1A 회귀 금지).
        #expect(source.contains("status != .denied"))
    }

    @Test("전환은 거울 디자인을 건드리지 않는다")
    func switchingDoesNotTouchDesign() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        for forbidden in ["MirrorDesign", "MirrorLibrary", "MirrorStyle", "StickerObject", "TextObject"] {
            #expect(!source.contains(forbidden), "카메라가 거울 데이터를 알고 있다: \(forbidden)")
        }
    }

    @Test("전면은 물리 wide 하나, 후면만 ultra-wide를 품은 렌즈를 찾는다")
    func lensSelectionFollowsHardware() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        #expect(source.contains(".builtInWideAngleCamera"))
        // 0.5x는 렌즈가 있어야 나온다 — 후면에서만 찾는다.
        #expect(source.contains(".builtInDualWideCamera"))
        #expect(source.contains(".builtInTripleCamera"))
        #expect(source.contains("position == .back"))

        // tele 단독 · ultra-wide 없는 dual을 고르지 않는다. 그러면 0.5x가 없으면서
        // 화각만 좁아진다.
        for forbidden in [".builtInTelephotoCamera", ".builtInDualCamera,"] {
            #expect(!source.contains(forbidden), "\(forbidden)를 고른다")
        }

        // 배율은 **사용자가 아는 1x**로 시작한다. virtual 카메라에서 `= 1`은 0.5x다.
        #expect(source.contains("device.videoZoomFactor = capability.deviceFactor(forLogical: 1)"))
        #expect(!source.contains("device.videoZoomFactor = 1"))

        // 기기 이름으로 분기하지 않는다.
        for forbidden in ["iPhone1", "utsname", "modelIdentifier", "machine"] {
            #expect(!source.contains(forbidden), "기기 이름을 본다: \(forbidden)")
        }
    }

    @Test("Portrait 고정과 화각 정책은 그대로다")
    func orientationAndFormatPolicyUnchanged() throws {
        #expect(MirrorCamera.portraitRotationAngle == 90)
        #expect(MirrorCamera.previewGravity == .resizeAspectFill)

        // 전환 후에도 같은 규칙을 다시 건다 — 반전/회전이 한 함수에만 있다.
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        #expect(source.contains("applyConnections(for: target)"))
        #expect(source.contains("applyConnections(for: activePosition)"))
        #expect(source.contains("videoRotationAngle = Self.portraitRotationAngle"))

        // 화각 선택 로직은 손대지 않았다.
        let choices = [
            MirrorCamera.FormatChoice(fieldOfView: 60, width: 1920, height: 1080),
            MirrorCamera.FormatChoice(fieldOfView: 75, width: 1280, height: 720),
            MirrorCamera.FormatChoice(fieldOfView: 75, width: 1920, height: 1080),
        ]
        #expect(MirrorCamera.bestFormatIndex(choices) == 2)
    }

    // MARK: - 플래시

    @Test("플래시 기본은 OFF고 AUTO는 없다")
    func flashDefaultsOff() throws {
        let view = codeOnly(try repoFile("ggumirror/Mirror/MirrorView.swift"))
        #expect(view.contains("var isFlashOn = false"))
        // AUTO 상태를 만들지 않았다 — 사용자에게 보이는 상태는 ON/OFF 둘뿐이다.
        let camera = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        for forbidden in ["flashMode = .auto", "FlashMode.auto", "isFlashAuto", "case auto"] {
            #expect(!view.contains(forbidden))
            #expect(!camera.contains(forbidden))
        }
        // torch를 켜두는 방식이 아니다.
        #expect(!camera.contains("torchMode"))
        #expect(!camera.contains("setTorchModeOn"))
    }

    @Test("지원하는 mode만 요청한다")
    func onlyRequestsSupportedModes() {
        // 후면 LED: on/off 둘 다 지원
        #expect(MirrorCamera.flashMode(wantsFlash: true, supported: [.off, .on, .auto]) == .on)
        #expect(MirrorCamera.flashMode(wantsFlash: false, supported: [.off, .on, .auto]) == .off)

        // flash가 없는 카메라: on을 요청하지 않는다
        #expect(MirrorCamera.flashMode(wantsFlash: true, supported: [.off]) == .off)
        #expect(MirrorCamera.flashMode(wantsFlash: false, supported: [.off]) == .off)

        // 아무것도 지원하지 않으면 settings를 건드리지 않는다
        #expect(MirrorCamera.flashMode(wantsFlash: true, supported: []) == nil)
    }

    @Test("공식 flash가 없을 때만 화면 flash로 대신한다")
    func screenFlashOnlyWhenNoOfficialFlash() {
        #expect(MirrorCamera.needsScreenFlash(wantsFlash: true, officialSupported: false))
        #expect(!MirrorCamera.needsScreenFlash(wantsFlash: true, officialSupported: true))
        // OFF면 어느 쪽도 하지 않는다.
        #expect(!MirrorCamera.needsScreenFlash(wantsFlash: false, officialSupported: false))
        #expect(!MirrorCamera.needsScreenFlash(wantsFlash: false, officialSupported: true))
    }

    @Test("촬영마다 새 AVCapturePhotoSettings를 만든다")
    func settingsAreFreshEachCapture() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        #expect(source.contains("let settings = AVCapturePhotoSettings()"))
        // 재사용할 저장 프로퍼티를 두지 않았다 (재사용하면 AVFoundation이 예외를 던진다).
        #expect(!source.contains("var settings: AVCapturePhotoSettings"))
        // deprecated device flashMode를 쓰지 않는다.
        #expect(!source.contains("device.flashMode"))
    }

    @Test("촬영 요청은 시작 시점의 의도를 그대로 쓴다")
    func captureSnapshotsIntent() throws {
        let view = codeOnly(try repoFile("ggumirror/Mirror/MirrorView.swift"))
        // 요청 시작에서 한 번 읽어 상수로 잡는다 — 도중에 토글해도 이 사진은 바뀌지 않는다.
        #expect(view.contains("let wantsFlash = isFlashOn"))
        #expect(view.contains("let usesScreenFlash = MirrorCamera.needsScreenFlash("))
        // 중복 촬영을 막는다.
        #expect(view.contains("guard !isCapturing else { return }"))
        #expect(view.contains("isCapturing = true"))
        // 촬영 중에는 전환하지 않는다.
        #expect(view.contains("canSwitchCamera: camera.canSwitchCamera && !isCapturing"))
    }

    @Test("flash를 못 써도 촬영은 계속된다")
    func flashFailureNeverBlocksCapture() throws {
        let camera = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        // 사진을 못 얻으면 마지막 preview 프레임으로 떨어진다.
        #expect(camera.contains("return image ?? currentFrame()"))
        // photo output이 없으면(=extension) 예전 경로 그대로다.
        #expect(camera.contains("guard let output = photoOutput else { return currentFrame() }"))
    }

    // MARK: - 화면 flash

    @Test("화면 flash는 빛이 들어온 뒤에 찍는다")
    func screenFlashIlluminatesBeforeCapture() throws {
        let view = repoFile
        let source = codeOnly(try view("ggumirror/Mirror/MirrorView.swift"))
        // 순서: 밝히기 → 잠깐 기다리기 → 촬영.
        let begin = try #require(source.range(of: "await beginScreenFlash()"))
        let capture = try #require(source.range(of: "await camera.capturePhoto("))
        #expect(begin.lowerBound < capture.lowerBound, "밝아지기 전에 찍고 있다")
        #expect(source.contains("Task.sleep(for: .milliseconds(220))"))
    }

    @Test("밝기는 어느 경로에서도 되돌린다")
    func brightnessAlwaysRestored() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorView.swift"))
        #expect(source.contains("brightnessBeforeFlash = activeScreen?.brightness"))
        // 성공 / 실패 / 취소는 defer, 백그라운드와 화면 이탈은 따로.
        #expect(source.contains("defer {") && source.contains("endScreenFlash()"))
        #expect(source.contains(".onDisappear { endScreenFlash() }"))
        #expect(source.contains("camera.stop()"))
        // deprecated UIScreen.main을 쓰지 않는다.
        #expect(!source.contains("UIScreen.main"))
    }

    @Test("화면 flash 흰 화면은 저장되는 사진에 들어가지 않는다")
    func screenFlashIsNotComposedIntoPhoto() throws {
        let capture = codeOnly(try repoFile("ggumirror/Mirror/MirrorCapture.swift"))
        // 합성에 들어가는 것은 카메라 사진 + 장식뿐이다.
        #expect(capture.contains("MirrorDecorationView(design: design)"))
        for forbidden in ["screenFlash", "flashOpacity", "MirrorControls", "UIGraphicsImageRenderer(bounds"] {
            #expect(!capture.contains(forbidden), "촬영 결과에 화면 요소가 섞인다: \(forbidden)")
        }
    }

    @Test("촬영 결과에 UI 컨트롤이 없다 — 화면 스냅샷을 쓰지 않는다")
    func captureHasNoControls() throws {
        let capture = codeOnly(try repoFile("ggumirror/Mirror/MirrorCapture.swift"))
        for forbidden in ["MirrorControls", "captureButton", "switchButton", "flashButton",
                          "homeButton", "snapshotView", "drawHierarchy"] {
            #expect(!capture.contains(forbidden))
        }
    }

    // MARK: - preview ↔ 저장 결과 일치

    @Test("고해상도 사진으로 합성해도 장식 위치가 그대로다")
    func decorationsLandInTheSamePlaceAtAnyResolution() throws {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        let width = 0.3
        let source = StickerSource.builtIn(.heart)
        design.stickers = [StickerObject(
            source: source,
            frame: NormalizedRect(
                x: 0.5 - width / 2,
                y: 0.25,
                width: width,
                height: StickerObject.height(for: width, aspectRatio: source.aspectRatio)
            )
        )]

        // 같은 디자인을 화면 크기와 사진 크기로 합성한다.
        let small = try #require(MirrorCapture.compose(
            frame: nil, design: design, size: CGSize(width: 270, height: 585)
        ))
        let large = try #require(MirrorCapture.compose(
            frame: nil, design: design, size: CGSize(width: 540, height: 1170)
        ))

        // 비율이 같으면 정규화 좌표계가 같다는 뜻이다.
        #expect(abs(small.size.width / small.size.height - large.size.width / large.size.height) < 0.001)
        #expect(large.size.width == small.size.width * 2)
    }

    // MARK: - UI

    @Test("쓰는 SF Symbol이 실제로 존재한다")
    func symbolsExist() {
        // 없는 symbol은 빈 자리로 보인다 — 이름을 추측해서 쓰지 않는다.
        #expect(UIImage(systemName: MirrorControls.switchSymbol) != nil,
                "\(MirrorControls.switchSymbol) 가 이 SDK에 없다")
        #expect(UIImage(systemName: "bolt.fill") != nil)
        #expect(UIImage(systemName: "bolt.slash.fill") != nil)
    }

    @Test("전환 / 플래시 버튼에 한국어 접근성 이름이 있다")
    func controlsHaveKoreanLabels() throws {
        let source = try repoFile("ggumirror/Mirror/MirrorControls.swift")
        #expect(source.contains("\"카메라 전환\""))
        #expect(source.contains("\"플래시 켜기\""))
        #expect(source.contains("\"플래시 끄기\""))
        // 기존 것도 그대로다.
        #expect(source.contains("\"촬영\""))
        #expect(source.contains("\"홈으로\""))
    }

    @Test("전환 / 플래시도 같은 auto-hide 컨트롤 안에 있다")
    func newControlsFollowAutoHide() throws {
        let view = codeOnly(try repoFile("ggumirror/Mirror/MirrorView.swift"))
        // 컨트롤은 areControlsVisible 안에서만 그려진다.
        let controls = try #require(view.range(of: "MirrorControls("))
        let visible = try #require(view.range(of: "if areControlsVisible {"))
        #expect(visible.lowerBound < controls.lowerBound)
        // 버튼을 누르면 타이머가 다시 시작된다.
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorControls.swift"))
        #expect(source.contains("onInteraction()"))
        #expect(view.contains("onToggleFlash:"))
        #expect(view.contains("onSwitchCamera:"))
    }

    // MARK: - orientation (rear → front 뒤집힘 회귀 금지)

    @Test("연결 정책을 거는 곳은 MirrorCamera 한 곳뿐이다")
    func onlyTheCameraConfiguresConnections() throws {
        let preview = codeOnly(try repoFile("ggumirror/Mirror/CameraPreviewView.swift"))

        // preview layer가 스스로 반전/회전을 정하지 않는다. 예전에는 여기서
        // isVideoMirrored = true를 박아 두고 전환 때 아무도 갱신하지 않았다.
        for forbidden in ["isVideoMirrored", "videoRotationAngle", "automaticallyAdjustsVideoMirroring"] {
            #expect(!preview.contains(forbidden), "preview가 연결 정책을 따로 정한다: \(forbidden)")
        }
        // 붙은 직후 카메라에게 지금 기준으로 걸어 달라고만 한다.
        #expect(preview.contains("camera.applyCurrentConnectionPolicy()"))
    }

    @Test("preview connection도 정책 대상이다 — outputs만 돌지 않는다")
    func previewConnectionIsCovered() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))

        // session.connections에는 preview layer의 connection도 들어 있다.
        // session.outputs만 돌면 그 자리가 영원히 갱신되지 않는다.
        #expect(source.contains("for connection in session.connections"))
        #expect(!source.contains("for output in session.outputs {"),
                "outputs만 돌면 preview connection이 빠진다")
    }

    @Test("초기 front와 재전환 front가 같은 경로를 탄다")
    func initialAndReswitchedFrontShareOnePath() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))

        // 구성 · 전환 성공 · 전환 실패 복원 · preview 부착 — 전부 같은 함수 하나로 간다.
        let calls = source.components(separatedBy: "applyConnections(for:").count - 1
        #expect(calls >= 4, "연결 정책 경로가 갈라져 있다 (호출 \(calls)곳)")
        #expect(source.contains("func applyCurrentConnectionPolicy()"))
        // 정책 함수는 하나뿐이다.
        #expect(source.components(separatedBy: "func applyConnections(").count - 1 == 1)
    }

    @Test("반전은 지금 붙어 있는 카메라 기준으로 정한다")
    func mirroringFollowsTheActiveCamera() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))

        // 인자로 받은 position에서 바로 계산한다. 이전 device 값을 재사용하지 않는다.
        #expect(source.contains("connection.isVideoMirrored = position.isMirrored"))
        // 성공한 전환 뒤에 activePosition을 먼저 갱신하고 그 값으로 건다.
        let update = try #require(source.range(of: "activePosition = target"))
        let apply = try #require(source.range(of: "applyConnections(for: target)"))
        #expect(update.lowerBound < apply.lowerBound)
    }

    @Test("자동 반전 조정을 끈다 — system이 되돌려 놓지 못하게")
    func automaticMirroringIsOff() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        #expect(source.contains("connection.automaticallyAdjustsVideoMirroring = false"))
        // 켜는 코드가 없다.
        #expect(!source.contains("automaticallyAdjustsVideoMirroring = true"))
    }

    @Test("전면 / 후면에 다른 회전 각을 쓰지 않는다")
    func rotationHasNoPerDeviceMagicNumber() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        // 각도는 상수 하나에서만 온다.
        #expect(source.components(separatedBy: "videoRotationAngle =").count - 1 == 1)
        #expect(source.contains("videoRotationAngle = Self.portraitRotationAngle"))
        for magic in ["= 270", "= 180", "position == .front ? 90", "isMirrored ? 90"] {
            #expect(!source.contains(magic), "device별 magic number가 들어왔다: \(magic)")
        }
    }

    @Test("전환 로그가 실제 값을 남긴다 — 다음에 또 추측하지 않도록")
    func connectionValuesAreLogged() throws {
        let source = try repoFile("ggumirror/Mirror/MirrorCamera.swift")
        #expect(source.contains("connection position="))
        #expect(source.contains("rotation="))
        #expect(source.contains("mirrored="))
        #expect(source.contains("auto="))
        #expect(source.contains("#if DEBUG"))
    }

    // MARK: - 잠금화면 회귀 금지

    @Test("잠금화면 extension은 전면 고정이고 photo output이 없다")
    func lockScreenIsUnchanged() throws {
        let finder = codeOnly(try repoFile("GgumirrorCapture/GgumirrorCaptureViewFinder.swift"))

        // role을 주지 않는다 → .viewfinder → 전환 없음, photo output 없음.
        #expect(finder.contains("MirrorCamera()"))
        #expect(!finder.contains("role: .mirror"))

        // 전환 / 플래시 UI가 없다.
        for forbidden in ["switchCamera", "canSwitchCamera", "isFlashOn", "flashMode",
                          "capturePhoto", "AVCapturePhotoOutput", "brightness"] {
            #expect(!finder.contains(forbidden), "잠금화면에 본앱 기능이 새어 들어갔다: \(forbidden)")
        }

        // 기존 촬영 경로(currentFrame → composer)를 그대로 쓴다.
        #expect(finder.contains("camera.currentFrame()"))
        // preview도 본앱과 같은 하나의 정책 경로를 탄다 (front 고정이라 결과는 그대로다).
        #expect(finder.contains("CameraPreviewView(camera: camera)"))
        #expect(finder.contains("MirrorCamera.canRetry(camera.status)"))
    }

    @Test("viewfinder role은 전환도 공식 flash도 없다")
    func viewfinderRoleHasNoExtras() {
        let camera = MirrorCamera()
        #expect(camera.role == .viewfinder)
        #expect(camera.position == .front)
        #expect(!camera.canSwitchCamera)
        // photo output을 만들지 않았으므로 공식 flash도 없다.
        #expect(!camera.isOfficialFlashSupported)
    }

    @Test("photo output은 mirror role에서만 붙는다")
    func photoOutputIsMainAppOnly() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        #expect(source.contains("if role == .mirror { addPhotoOutput() }"))
        // 기본 role이 viewfinder라 extension이 따라 바뀌지 않는다.
        #expect(source.contains("init(role: Role = .viewfinder)"))
    }

    // MARK: - C-2A / C-1 회귀

    @Test("카메라를 바꿔도 투명 프레임 상태는 그대로다")
    func switchingKeepsTransparentFrame() {
        var design = MirrorDesign(mirror: MirrorLibrary.defaultMirror)
        design.style.isFrameVisible = false
        let before = design

        // 카메라는 거울 모델을 알지 못한다 — 전환이 디자인을 바꿀 통로가 없다.
        #expect(design.style.frameFill == nil)
        #expect(design.style == before.style)
        #expect(design.stickers == before.stickers)
    }

    @Test("잠금화면 preset 매핑은 그대로다")
    func quickMirrorMappingUnchanged() {
        #expect(QuickMirrorPresetID.allCases.count == 9)
        for basic in BasicMirror.allCases {
            let mirror = MyMirror(id: "m", name: "n", origin: .made, style: basic.style)
            #expect(QuickMirrorSync.preset(for: mirror) == basic.quickMirrorPreset)
        }
    }

    @Test("로그에 민감정보가 없다")
    func logsAreSafe() throws {
        let source = try repoFile("ggumirror/Mirror/MirrorCamera.swift")
        #expect(source.contains("#if DEBUG"))
        // 상태만 남긴다.
        for forbidden in ["fileDataRepresentation())", "print(photo", "\\(image", "URL", "token"] {
            #expect(!source.contains("CameraLog.event(\"\\(\(forbidden)"))
        }
        #expect(source.contains("CameraLog.event(\"switching"))
        #expect(source.contains("\"flash on hardware\""))
        #expect(source.contains("\"flash unsupported fallback off\""))
    }
}
