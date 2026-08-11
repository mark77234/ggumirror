//
//  QuickMirrorTests.swift
//  ggumirrorTests
//
//  잠금화면 Quick Mirror(C-1A)에서 **자동화할 수 있는 부분만** 검증한다.
//
//  시스템의 잠금화면 control 호출 자체는 실기기에서만 확인된다 —
//  그걸 가짜로 성공시키는 테스트는 만들지 않는다.
//
//  대신 여기서 지키는 것:
//  1. capture extension이 Backend / Auth / Store에 절대 의존하지 않는가 (sandbox 경계)
//  2. 촬영 파일 이름·수거 규칙이 본앱과 extension에서 같은가
//  3. 본앱 전환 activity가 사용자 정보를 담지 않는가
//

import AVFoundation
import Foundation
import LockedCameraCapture
import Testing
import UIKit
@testable import ggumirror

struct QuickMirrorTests {

    // MARK: - 도구

    private func repoFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    private func projectFile() throws -> String {
        try repoFile("ggumirror.xcodeproj/project.pbxproj")
    }

    /// 주석을 걷어낸 코드만. 주석에는 "이건 쓰지 않는다"처럼 금지 단어가 정당하게 나온다.
    private func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "quick-mirror-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func image(_ size: CGSize = CGSize(width: 8, height: 12)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - 촬영 파일

    @Test("촬영 파일은 sessionContentURL 폴더에 PNG로 저장된다")
    func savesPNG() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try QuickMirrorCaptureStore.save(image(), into: directory)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension == "png")
        #expect(url.deletingLastPathComponent().path == directory.path)

        let data = try #require(try? Data(contentsOf: url))
        #expect(UIImage(data: data) != nil)
    }

    @Test("파일 이름이 겹치지 않는다")
    func fileNamesAreUnique() {
        let moment = Date(timeIntervalSince1970: 1_780_000_000)
        let names = (0..<50).map { _ in QuickMirrorCaptureStore.fileName(at: moment) }
        #expect(Set(names).count == 50)
    }

    @Test("파일 이름에 사용자 정보가 없다")
    func fileNameHasNoUserInfo() {
        let name = QuickMirrorCaptureStore.fileName()
        #expect(name.hasPrefix("quick-mirror-"))
        #expect(name.hasSuffix(".png"))
        // 이름은 시간 + 무작위 조각뿐이다.
        for forbidden in ["apple", "user", "token", "@", "session"] {
            #expect(!name.lowercased().contains(forbidden))
        }
    }

    @Test("여러 장 찍어도 전부 수거된다")
    func collectsEveryCapture() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for _ in 0..<3 { _ = try QuickMirrorCaptureStore.save(image(), into: directory) }
        #expect(QuickMirrorCaptureStore.captures(in: directory).count == 3)
    }

    @Test("관계없는 파일은 수거하지 않는다")
    func ignoresUnrelatedFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try Data("x".utf8).write(to: directory.appending(path: "메모.txt"))
        try Data("x".utf8).write(to: directory.appending(path: "other.png"))
        _ = try QuickMirrorCaptureStore.save(image(), into: directory)

        let found = QuickMirrorCaptureStore.captures(in: directory)
        #expect(found.count == 1)
        #expect(found[0].lastPathComponent.hasPrefix("quick-mirror-"))
    }

    @Test("없는 폴더를 물어도 죽지 않는다")
    func missingDirectoryIsSafe() {
        #expect(QuickMirrorCaptureStore.captures(in: temporaryDirectory()).isEmpty)
    }

    // MARK: - 본앱 수거

    @Test("여러 session 폴더를 한꺼번에 수거한다")
    func inboxCollectsAcrossSessions() throws {
        let first = temporaryDirectory()
        let second = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        _ = try QuickMirrorCaptureStore.save(image(), into: first)
        _ = try QuickMirrorCaptureStore.save(image(), into: second)
        _ = try QuickMirrorCaptureStore.save(image(), into: second)

        #expect(QuickMirrorInbox.collect(from: [first, second]).count == 3)
        #expect(QuickMirrorInbox.collect(from: []).isEmpty)
    }

    // MARK: - 본앱 전환 activity

    @Test("activity는 거울을 열라는 사실만 담는다")
    func activityCarriesNoUserInfo() {
        let activity = QuickMirrorActivity.openMirror()
        // Apple 공식 상수를 쓴다 — 커스텀 타입이 아니다.
        #expect(activity.activityType == NSUserActivityTypeLockedCameraCapture)
        #expect(QuickMirrorActivity.isOpenMirror(activity))
        // userInfo에 아무것도 담지 않는다.
        #expect(activity.userInfo?.isEmpty ?? true)
    }

    @Test("다른 activity는 거울 열기로 보지 않는다")
    func rejectsOtherActivity() {
        #expect(!QuickMirrorActivity.isOpenMirror(NSUserActivity(activityType: "com.other.thing")))
    }

    // MARK: - intent / control

    @Test("control은 CameraCaptureIntent를 쓴다 — 앱 열기 shortcut이 아니다")
    func controlUsesCameraCaptureIntent() throws {
        let source = try repoFile("GgumirrorControls/GgumirrorControls.swift")
        #expect(source.contains("ControlWidget"))
        #expect(source.contains("QuickMirrorCaptureIntent"))
        // OpenIntent / URL scheme 우회로를 쓰지 않는다.
        #expect(!source.contains("OpenIntent"))
        #expect(!source.contains("openURL"))
        #expect(!source.contains("URL(string:"))
    }

    @Test("intent는 큰 상태를 넘기지 않는다 (appContext = Never)")
    func intentCarriesNoContext() throws {
        let source = try repoFile("ggumirror/Mirror/QuickMirrorIntent.swift")
        #expect(source.contains("typealias AppContext = Never"))
        #expect(source.contains("CameraCaptureIntent"))
    }

    @Test("control kind는 고정이다 — 바꾸면 사용자가 배치한 control이 사라진다")
    func controlKindIsStable() throws {
        let source = try repoFile("GgumirrorControls/GgumirrorControls.swift")
        #expect(source.contains("com.mark77234.ggumirror.quick-mirror"))
    }


    // MARK: - Apple 3-target invariant (control이 실행되지 않은 원인)

    @Test("intent는 세 target 모두에 있어야 한다 — 하나라도 빠지면 control이 실행되지 않는다")
    func intentIsInAllThreeTargets() throws {
        let project = try projectFile()

        // 앱 target: ggumirror/ 폴더 전체가 기본 멤버라 파일 존재로 확인한다.
        #expect(!(try repoFile("ggumirror/Mirror/QuickMirrorIntent.swift")).isEmpty)

        // 두 extension target: membership exception에 명시돼 있어야 한다.
        for label in ["GgumirrorCapture", "GgumirrorControls"] {
            let marker = "Exceptions for \"ggumirror\" folder in \"\(label)\" target"
            let start = try #require(project.range(of: marker))
            let tail = project[start.upperBound...]
            let end = try #require(tail.range(of: "};"))
            let shared = String(tail[..<end.lowerBound])
            #expect(shared.contains("Mirror/QuickMirrorIntent.swift"),
                    "\(label)에 intent가 없다 — control이 목록에는 보이지만 실행되지 않는다")
        }
    }

    @Test("capture extension도 AppIntents를 쓴다")
    func captureUsesAppIntents() throws {
        // intent 파일이 capture target에 들어가므로 AppIntents가 링크되고
        // metadata도 생성된다. "capture는 AppIntents를 안 쓴다"는 판단은 틀렸다.
        let intent = try repoFile("ggumirror/Mirror/QuickMirrorIntent.swift")
        #expect(intent.contains("import AppIntents"))
        #expect(intent.contains("CameraCaptureIntent"))
    }

    @Test("본앱이 열린 경우에도 Mirror를 보여준다")
    func appPathShowsMirror() throws {
        let intent = codeOnly(try repoFile("ggumirror/Mirror/QuickMirrorIntent.swift"))
        #expect(intent.contains("QuickMirrorRequest.shared.showMirror()"))

        let root = codeOnly(try repoFile("ggumirror/RootView.swift"))
        #expect(root.contains("quickMirrorRequest.token"))
        #expect(root.contains("screen = .mirror"))
        // 홈/상점으로 끌고 가지 않는다.
        #expect(!root.contains("screen = .home\n            }"))
    }

    @Test("본앱 전환은 Apple 공식 activity type을 쓴다")
    func usesOfficialActivityType() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/QuickMirrorActivity.swift"))
        #expect(source.contains("NSUserActivityTypeLockedCameraCapture"))
        // 커스텀 타입을 쓰지 않는다 — 시스템이 그 흐름으로 인정하지 않을 수 있다.
        #expect(!source.contains("com.mark77234.ggumirror.open-mirror"))
        #expect(QuickMirrorActivity.openMirrorType == NSUserActivityTypeLockedCameraCapture)
    }

    // MARK: - Control 정의 / 아이콘

    @Test("ControlWidget 정의는 정확히 1개다")
    func exactlyOneControlWidget() throws {
        let source = codeOnly(try repoFile("GgumirrorControls/GgumirrorControls.swift"))
        #expect(source.components(separatedBy: ": ControlWidget").count - 1 == 1)
        #expect(source.components(separatedBy: "StaticControlConfiguration").count - 1 == 1)
        // WidgetBundle body에 등록된 것도 하나뿐이다.
        #expect(source.components(separatedBy: "QuickMirrorControl()").count - 1 == 1)
    }

    @Test("control 아이콘이 꾸미러에 맞는 symbol이다")
    func controlIconIsBrandAppropriate() throws {
        let source = try repoFile("GgumirrorControls/GgumirrorControls.swift")
        // 사람 + 액자 = 꾸민 거울. SF Symbols 카탈로그에서 존재와 iOS 15.0+ 가용성을 확인했다.
        #expect(source.contains("person.crop.artframe"))
        // generic 아이콘으로 돌아가지 않는다.
        #expect(!source.contains("person.crop.square\""))
        // full-color 앱 아이콘 PNG를 control 아이콘으로 쓰지 않는다.
        #expect(!source.contains("AppIcon"))
        #expect(!source.contains("Image(\""))
    }

    @Test("표시명은 그대로 꾸미러 거울이다")
    func displayNameUnchanged() throws {
        let source = try repoFile("GgumirrorControls/GgumirrorControls.swift")
        #expect(source.contains("꾸미러 거울"))
    }

    // MARK: - 실기기 추적 로그

    @Test("process 추적 로그가 DEBUG에만 나오고 민감정보가 없다")
    func traceLogsAreSafe() throws {
        let log = try repoFile("ggumirror/Mirror/QuickMirrorRequest.swift")
        #expect(log.contains("#if DEBUG"))

        // 로그 문구에 경로 · token · 사용자 정보를 넣지 않는다.
        for path in ["GgumirrorCapture/GgumirrorCapture.swift",
                     "GgumirrorCapture/GgumirrorCaptureViewFinder.swift",
                     "ggumirror/Mirror/QuickMirrorIntent.swift"] {
            let source = try repoFile(path)
            for line in source.split(separator: "\n") where line.contains("QuickMirrorLog.event(") {
                for forbidden in ["sessionContentURL", "url", "accessToken", "email", "subject", "path"] {
                    #expect(!line.contains(forbidden), "\(path) 로그에 \(forbidden)이 있다")
                }
            }
        }
    }

    // MARK: - Capture extension 경계 (이 Phase의 핵심 위험)

    @Test("capture extension이 Backend / Auth / Store에 의존하지 않는다")
    func captureHasNoForbiddenDependency() throws {
        let sources = ["GgumirrorCapture/GgumirrorCapture.swift",
                       "GgumirrorCapture/GgumirrorCaptureViewFinder.swift"]
        for path in sources {
            let source = codeOnly(try repoFile(path))
            for forbidden in [
                "BackendClient", "AppConfig", "AuthSession", "ServerSession", "AuthIdentityStore",
                "MirrorStore", "StickerProjectStore", "MirrorLibrary", "StickerLibrary",
                "URLSession", "Keychain", "RevenueCat", "Firebase", "Firestore",
            ] {
                #expect(!source.contains(forbidden), "\(path)에 \(forbidden)이 있다")
            }
        }
    }

    @Test("capture target에는 카메라 파일만 공유돼 있다")
    func captureSharesOnlyCameraFiles() throws {
        let project = try projectFile()
        let block = try #require(project.range(of: #"Exceptions for "ggumirror" folder in "GgumirrorCapture" target"#))
        let tail = project[block.upperBound...]
        let end = try #require(tail.range(of: "};"))
        let shared = String(tail[..<end.lowerBound])

        // 들어와야 하는 것.
        for expected in ["Mirror/MirrorCamera.swift", "Mirror/CameraPreviewView.swift",
                         "Mirror/QuickMirrorActivity.swift", "Mirror/QuickMirrorCaptureStore.swift"] {
            #expect(shared.contains(expected))
        }
        // 절대 들어오면 안 되는 것.
        for forbidden in ["Backend/", "Auth/", "Store/", "Editor/", "Home/", "Shared/MirrorStore"] {
            #expect(!shared.contains(forbidden), "capture target에 \(forbidden)이 들어갔다")
        }
    }

    @Test("App Group을 추가하지 않았다")
    func noAppGroup() throws {
        let project = try projectFile()
        #expect(!project.contains("com.apple.security.application-groups"))
        for entitlements in ["ggumirror/ggumirror.entitlements"] {
            let text = try repoFile(entitlements)
            #expect(!text.contains("application-groups"))
        }
        // extension용 entitlements 파일을 만들지 않았다 (공식 template도 만들지 않았다).
        #expect(!project.contains("GgumirrorCapture/GgumirrorCapture.entitlements"))
    }

    @Test("공식 extension point를 쓴다 — 추측한 식별자가 아니다")
    func usesOfficialExtensionPoints() throws {
        let capture = try repoFile("GgumirrorCapture/Info.plist")
        #expect(capture.contains("com.apple.securecapture"))
        // 내가 런타임 바이너리에서 추론했던 값은 틀렸다. 다시 쓰지 않는다.
        #expect(!capture.contains("com.apple.LockedCameraCapture"))

        let controls = try repoFile("GgumirrorControls/Info.plist")
        #expect(controls.contains("com.apple.widgetkit-extension"))
    }

    @Test("extension bundle id가 꾸미러 namespace 아래에 있다")
    func bundleIdentifiers() throws {
        let project = try projectFile()
        #expect(project.contains("com.mark77234.ggumirror.capture"))
        #expect(project.contains("com.mark77234.ggumirror.controls"))
        // 다른 제품 identifier를 재사용하지 않는다.
        #expect(!project.lowercased().contains("dailyopic"))
        #expect(!project.lowercased().contains("opicmobile"))
    }

    @Test("extension 버전이 본앱과 같다 — 다르면 App Store 검증에서 막힌다")
    func extensionVersionsMatchApp() throws {
        let project = try projectFile()

        // extension target의 build config 안에서만 확인한다(test target은 무관하다).
        for bundleID in ["com.mark77234.ggumirror.capture", "com.mark77234.ggumirror.controls"] {
            var searched = project[...]
            var found = 0
            while let hit = searched.range(of: "PRODUCT_BUNDLE_IDENTIFIER = \(bundleID);") {
                // 이 config block의 시작으로 되짚어 올라간다.
                let blockStart = project[..<hit.lowerBound].range(of: "buildSettings = {", options: .backwards)
                let block = String(project[(blockStart?.upperBound ?? hit.lowerBound)..<hit.upperBound])
                #expect(block.contains("CURRENT_PROJECT_VERSION = 3;"), "\(bundleID) 버전이 본앱과 다르다")
                #expect(block.contains("MARKETING_VERSION = 1.0.2;"), "\(bundleID) marketing 버전이 다르다")
                found += 1
                searched = project[hit.upperBound...]
            }
            #expect(found == 2, "\(bundleID)의 Debug/Release config를 찾지 못했다")
        }
    }


    // MARK: - 하드웨어 촬영 버튼 (Apple 요구사항)

    @Test("공식 onCameraCaptureEvent로 하드웨어 촬영 이벤트를 처리한다")
    func handlesHardwareCaptureEvent() throws {
        let source = try repoFile("GgumirrorCapture/GgumirrorCaptureViewFinder.swift")
        // 처리하지 않으면 extension이 실행 직후 종료될 수 있다.
        #expect(source.contains(".onCameraCaptureEvent("))
        #expect(source.contains("import AVKit"))
        // SwiftUI 화면이므로 UIKit interaction을 억지로 감싸지 않는다.
        #expect(!source.contains("AVCaptureEventInteraction"))
    }

    @Test("ended phase에서만 찍는다 — 한 번 누르면 한 장")
    func capturesOnEndedPhaseOnly() throws {
        let source = codeOnly(try repoFile("GgumirrorCapture/GgumirrorCaptureViewFinder.swift"))
        #expect(source.contains("event.phase == .ended"))
        // began / cancelled에서 찍지 않는다 — 그러면 한 번 눌러 두 장이 되거나
        // 취소한 조작에도 사진이 남는다.
        #expect(!source.contains(".began"))
        #expect(!source.contains("phase != .cancelled"))
    }

    @Test("화면 버튼과 하드웨어 버튼이 같은 촬영 경로를 쓴다")
    func bothInputsShareOneCapturePath() throws {
        let source = codeOnly(try repoFile("GgumirrorCapture/GgumirrorCaptureViewFinder.swift"))
        // capture()는 한 번만 정의된다.
        #expect(source.components(separatedBy: "private func capture()").count - 1 == 1)
        // 두 곳에서 부른다: 화면 버튼 + 하드웨어 이벤트.
        #expect(source.components(separatedBy: "capture()").count - 1 >= 3)
        // 별도 촬영/저장 경로를 만들지 않았다 — 저장은 store 한 곳뿐이다.
        #expect(source.components(separatedBy: "QuickMirrorCaptureStore.save").count - 1 == 1)
        #expect(!source.contains("pngData()"))
    }

    @Test("찍을 수 없는 상태에서는 하드웨어 버튼도 꺼둔다")
    func hardwareDisabledWhenNotCapturable() throws {
        let source = codeOnly(try repoFile("GgumirrorCapture/GgumirrorCaptureViewFinder.swift"))
        // 화면 버튼과 하드웨어 이벤트가 같은 조건 하나를 공유한다.
        #expect(source.contains("isEnabled: canCapture"))
        #expect(source.contains("disabled(!canCapture)"))
        #expect(source.contains("camera.status == .ready && !isSaving"))
        // 눌러도 아무 일이 없는 하드웨어 버튼을 만들지 않는다.
        #expect(!source.contains("isEnabled: true"))
    }

    @Test("촬영 소리를 임의로 끄지 않았다")
    func keepsDefaultCaptureSound() throws {
        let source = try repoFile("GgumirrorCapture/GgumirrorCaptureViewFinder.swift")
        #expect(!source.contains("defaultSoundDisabled: true"))
    }

    @Test("본앱 Mirror에는 하드웨어 이벤트를 넣지 않았다")
    func mainMirrorHasNoCaptureEvent() throws {
        for path in ["ggumirror/Mirror/MirrorCamera.swift",
                     "ggumirror/Mirror/CameraPreviewView.swift",
                     "ggumirror/RootView.swift"] {
            let source = try repoFile(path)
            #expect(!source.contains("onCameraCaptureEvent"), "\(path)에 들어갔다")
            #expect(!source.contains("AVCaptureEventInteraction"))
        }
    }

    @Test("이벤트가 몰려도 파일이 겹치지 않는다")
    func rapidCapturesDoNotCollide() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // 같은 순간에 여러 장이 들어와도 이름이 겹치지 않아야 한다.
        let moment = Date(timeIntervalSince1970: 1_780_000_000)
        for _ in 0..<10 { _ = try QuickMirrorCaptureStore.save(image(), into: directory, at: moment) }
        #expect(QuickMirrorCaptureStore.captures(in: directory).count == 10)
    }

    // MARK: - 본앱 Mirror 정책 (regression)

    @Test("Quick Mirror가 본앱 카메라 정책을 그대로 쓴다")
    func sharesMainCameraPolicy() throws {
        // 같은 파일을 공유하므로 정책이 갈라질 수 없다.
        #expect(MirrorCamera.zoomFactor == 1)
        #expect(MirrorCamera.previewGravity == .resizeAspectFill)
        #expect(MirrorCamera.portraitRotationAngle == 90)

        let viewFinder = try repoFile("GgumirrorCapture/GgumirrorCaptureViewFinder.swift")
        #expect(viewFinder.contains("CameraPreviewView"))
        #expect(viewFinder.contains("MirrorCamera"))
        // 별도 카메라 세션을 새로 만들지 않았다.
        #expect(!viewFinder.contains("AVCaptureSession("))
        // template 기본값(뒷면 카메라 UIImagePicker)을 그대로 두지 않았다.
        #expect(!viewFinder.contains("UIImagePickerController"))
        #expect(!viewFinder.contains(".rear"))
    }

    @Test("본앱 Mirror 파일은 C-1 때문에 바뀌지 않았다")
    func mainMirrorUntouched() throws {
        let camera = try repoFile("ggumirror/Mirror/MirrorCamera.swift")
        let preview = try repoFile("ggumirror/Mirror/CameraPreviewView.swift")
        // 잠금화면 사정이 본앱 카메라 코드에 스며들지 않았다.
        for leak in ["LockedCameraCapture", "sessionContentURL", "ControlWidget", "CameraCaptureIntent"] {
            #expect(!camera.contains(leak))
            #expect(!preview.contains(leak))
        }
    }
}
