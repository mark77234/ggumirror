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
import SwiftUI
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

    /// 이미지의 한 점 색. 프레임이 실제로 그려졌는지 볼 때 쓴다.
    private func pixel(_ image: UIImage, at point: CGPoint) -> [UInt8] {
        guard let cgImage = image.cgImage else { return [] }
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: -point.x, y: -point.y,
                                         width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return data
    }

    private func corner(of image: UIImage) -> [UInt8] { pixel(image, at: CGPoint(x: 2, y: 2)) }

    private func center(of image: UIImage) -> [UInt8] {
        guard let cgImage = image.cgImage else { return [] }
        return pixel(image, at: CGPoint(x: cgImage.width / 2, y: cgImage.height / 2))
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

    @Test("intent는 작은 preset 설정만 넘긴다")
    func intentCarriesOnlySmallContext() throws {
        let source = try repoFile("ggumirror/Mirror/QuickMirrorIntent.swift")
        // C-1B에서 Never → QuickMirrorContext(schemaVersion + presetID)로 바뀌었다.
        #expect(source.contains("typealias AppContext = QuickMirrorContext"))
        #expect(source.contains("CameraCaptureIntent"))
        // 큰 값을 넘기는 통로를 만들지 않았다.
        for forbidden in ["Data", "UIImage", "base64", "MirrorDesign"] {
            #expect(!source.contains(forbidden))
        }
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


    // MARK: - C-1B: AppContext

    @Test("context가 Codable로 왕복한다")
    func contextRoundTrip() throws {
        for preset in QuickMirrorPresetID.allCases {
            let context = QuickMirrorContext(presetID: preset)
            let data = try JSONEncoder().encode(context)
            #expect(try JSONDecoder().decode(QuickMirrorContext.self, from: data) == context)
        }
    }

    @Test("context는 4KB 제한에 한참 못 미친다")
    func contextIsTiny() throws {
        // Apple 제한은 JSON 4096 byte. 실제로는 수십 byte여야 한다.
        for preset in QuickMirrorPresetID.allCases {
            let size = try JSONEncoder().encode(QuickMirrorContext(presetID: preset)).count
            #expect(size < 4096)
            #expect(size < 128, "\(preset.rawValue) context가 \(size)byte — 너무 크다")
        }
    }

    @Test("context에 이미지 / 인증 / 서버 값이 들어갈 자리가 없다")
    func contextHasNoForbiddenFields() throws {
        let json = String(decoding: try JSONEncoder().encode(QuickMirrorContext(presetID: .cream)), as: UTF8.self)
        // 필드는 딱 둘이다.
        #expect(json.contains("schemaVersion"))
        #expect(json.contains("presetID"))
        for forbidden in ["image", "png", "data", "base64", "token", "userID", "mirrorID", "asset", "url"] {
            #expect(!json.lowercased().contains(forbidden.lowercased()))
        }

        let source = codeOnly(try repoFile("ggumirror/Mirror/QuickMirrorPreset.swift"))
        for forbidden in ["Data", "UIImage", "pngData", "base64"] {
            #expect(!source.contains(forbidden), "preset 모델에 \(forbidden)이 있다")
        }
    }

    @Test("context가 없거나 모르는 버전이면 기본 preset으로 떨어진다")
    func contextFallback() {
        #expect(QuickMirrorContext.preset(from: nil) == QuickMirrorPresetID.fallback)

        let future = QuickMirrorContext(presetID: .black, schemaVersion: 99)
        #expect(QuickMirrorContext.preset(from: future) == QuickMirrorPresetID.fallback)

        let old = QuickMirrorContext(presetID: .black, schemaVersion: 0)
        #expect(QuickMirrorContext.preset(from: old) == QuickMirrorPresetID.fallback)
    }

    @Test("정상 context는 그 preset을 쓴다")
    func contextHonoursPreset() {
        for preset in QuickMirrorPresetID.allCases {
            #expect(QuickMirrorContext.preset(from: QuickMirrorContext(presetID: preset)) == preset)
        }
    }

    @Test("모르는 presetID 문자열은 decode에서 걸러진다")
    func unknownPresetIDRejected() {
        let json = #"{"schemaVersion":1,"presetID":"neon-dragon"}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(QuickMirrorContext.self, from: Data(json.utf8))
        }
    }

    // MARK: - C-1B: 거울 → preset 매핑

    @MainActor
    @Test("기본 거울 8종은 같은 이름의 preset이 된다")
    func basicMirrorsMapToPresets() {
        for basic in BasicMirror.allCases {
            let mirror = MyMirror(id: basic.id, name: basic.name, origin: .basic, style: basic.style)
            #expect(QuickMirrorSync.preset(for: mirror) == basic.quickMirrorPreset)
        }
    }

    @MainActor
    @Test("preset 색은 기본 거울 색과 정확히 같다")
    func presetColorsMatchBasicMirrors() {
        for basic in BasicMirror.allCases {
            #expect(basic.quickMirrorPreset.frameColor == basic.style.frame,
                    "\(basic.name) 색이 preset과 다르다")
        }
    }

    @MainActor
    @Test("장식이 있어도 표현할 수 있는 프레임 색은 그대로 지킨다")
    func decorationsKeepFrameColor() {
        // 지금 쓰는 거울이 소프트 핑크면 잠금화면도 소프트 핑크여야 한다.
        // 크림으로 떨어지면 관계없는 디자인처럼 느껴진다.
        var withSticker = MyMirror(id: "m", name: "내 거울", origin: .made, style: BasicMirror.softPink.style)
        withSticker.stickers = [
            StickerObject(source: .doodle(.heart), frame: NormalizedRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        ]
        #expect(QuickMirrorSync.preset(for: withSticker) == .softPink)

        var withArtwork = MyMirror(id: "m", name: "내 거울", origin: .made, style: BasicMirror.black.style)
        withArtwork.importedArtworks = [ImportedArtworkObject(assetID: UUID())]
        #expect(QuickMirrorSync.preset(for: withArtwork) == .black)

        var withDrawingAndText = MyMirror(id: "m", name: "내 거울", origin: .made, style: BasicMirror.mint.style)
        withDrawingAndText.texts = [TextObject(text: "안녕", center: NormalizedPoint(x: 0.5, y: 0.5))]
        withDrawingAndText.style.doodles = [MirrorStyle.Doodle(symbol: "heart", x: 0.5, y: 0.1, size: 0.1)]
        #expect(QuickMirrorSync.preset(for: withDrawingAndText) == .mint)
    }

    @MainActor
    @Test("표현할 수 없는 프레임 색만 기본값으로 간다")
    func unsupportedFrameColorFallsBack() {
        var custom = MyMirror(id: "m", name: "내 거울", origin: .made,
                              style: MirrorStyle(frame: Color(red: 0.1, green: 0.7, blue: 0.3)))
        #expect(QuickMirrorSync.preset(for: custom) == QuickMirrorPresetID.fallback)

        // 장식이 없어도 마찬가지다 — 판단 기준은 프레임 색 하나뿐이다.
        custom.stickers = []
        #expect(QuickMirrorSync.preset(for: custom) == QuickMirrorPresetID.fallback)
    }

    @MainActor
    @Test("장식 데이터는 context에 들어가지 않는다")
    func decorationsNeverEnterContext() throws {
        var mirror = MyMirror(id: "m", name: "내 거울", origin: .made, style: BasicMirror.lavender.style)
        mirror.texts = [TextObject(text: "비밀 메모", center: NormalizedPoint(x: 0.5, y: 0.5))]
        mirror.stickers = [
            StickerObject(source: .doodle(.heart), frame: NormalizedRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        ]

        let preset = QuickMirrorSync.preset(for: mirror)
        let json = String(decoding: try JSONEncoder().encode(QuickMirrorContext(presetID: preset)), as: UTF8.self)

        #expect(preset == .lavender)
        // 프레임 색만 간다. 장식 · 거울 이름 · id는 가지 않는다.
        #expect(!json.contains("비밀 메모"))
        #expect(!json.contains("내 거울"))
        #expect(!json.contains("heart"))
        #expect(try JSONEncoder().encode(QuickMirrorContext(presetID: preset)).count < 128)
    }

    @MainActor
    @Test("매핑이 거울 모델을 바꾸지 않는다")
    func mappingDoesNotMutateMirror() {
        let mirror = MyMirror(id: "m", name: "거울", origin: .basic, style: BasicMirror.mint.style)
        let before = mirror
        _ = QuickMirrorSync.preset(for: mirror)
        #expect(mirror == before)
    }

    // MARK: - C-1B: 프레임 / 합성

    @Test("프레임 비율이 본앱 거울과 같다")
    func frameGeometryMatchesMainMirror() {
        // 숫자를 따로 적었으므로 어긋나지 않는지 여기서 비교한다.
        #expect(QuickMirrorFrame.insetLeft == MirrorFrameInsets.standard.left)
        #expect(QuickMirrorFrame.insetRight == MirrorFrameInsets.standard.right)
        #expect(QuickMirrorFrame.insetTop == MirrorFrameInsets.standard.top)
        #expect(QuickMirrorFrame.insetBottom == MirrorFrameInsets.standard.bottom)
        let expectedRadius = MirrorGeometry.innerCornerRadius / Double(MirrorCanvas.size.width)
        #expect(abs(QuickMirrorFrame.cornerRadiusRatio - expectedRadius) < 1e-12)
    }

    @Test("프레임 구멍은 크기가 달라도 같은 비율이다")
    func frameGeometryIsDeterministic() {
        for size in [CGSize(width: 393, height: 852), CGSize(width: 1179, height: 2556)] {
            let hole = QuickMirrorFrame.hole(in: size)
            #expect(abs(hole.minX / size.width - QuickMirrorFrame.insetLeft) < 0.0001)
            #expect(abs(hole.minY / size.height - QuickMirrorFrame.insetTop) < 0.0001)
            #expect(hole.width > 0 && hole.height > 0)
            // 카메라가 화면 대부분을 차지해야 한다 — 프레임이 얼굴을 가리지 않는다.
            #expect(hole.width / size.width > 0.75)
            #expect(hole.height / size.height > 0.8)
        }
    }

    @Test("none preset은 프레임을 그리지 않는다")
    func nonePresetDrawsNothing() {
        #expect(QuickMirrorPresetID.none.frameColor == nil)
        #expect(!QuickMirrorPresetID.none.drawsFrame)
        for preset in QuickMirrorPresetID.allCases where preset != .none {
            #expect(preset.drawsFrame)
            #expect(preset.frameColor != nil)
        }
    }

    @Test("촬영 결과는 화면 비율로 잘린다 — 미리보기와 같은 영역")
    func captureCropsToPreviewAspect() {
        // 4:3 카메라 버퍼 → 9:19.5 화면.
        let camera = image(CGSize(width: 400, height: 300))
        let preview = CGSize(width: 393, height: 852)
        let cropped = QuickMirrorComposer.cropToAspect(camera, aspect: preview)

        let target = preview.width / preview.height
        let result = cropped.size.width / cropped.size.height
        #expect(abs(result - target) < 0.01, "잘린 비율이 화면과 다르다: \(result) vs \(target)")
        #expect(cropped.size.width <= camera.size.width)
    }

    @Test("촬영 결과에 프레임이 들어간다")
    func captureIncludesFrame() {
        let camera = image(CGSize(width: 200, height: 400))
        let preview = CGSize(width: 200, height: 400)

        let framed = QuickMirrorComposer.compose(camera: camera, preset: .black, previewAspect: preview)
        let bare = QuickMirrorComposer.compose(camera: camera, preset: .none, previewAspect: preview)

        // 프레임이 있는 쪽은 모서리 픽셀이 프레임 색(검정)에 가깝고, 없는 쪽은 원본(빨강)이다.
        #expect(corner(of: framed) != corner(of: bare))
        // 가운데는 둘 다 카메라다.
        #expect(center(of: framed) == center(of: bare))
    }

    @Test("촬영 결과에 조작 버튼이 들어가지 않는다")
    func captureExcludesControls() throws {
        let source = codeOnly(try repoFile("GgumirrorCapture/GgumirrorCaptureViewFinder.swift"))
        // 화면 전체 스냅샷을 쓰지 않는다.
        for forbidden in ["ImageRenderer", "drawHierarchy", "snapshot(", "UIGraphicsImageRenderer"] {
            #expect(!source.contains(forbidden), "화면 스냅샷 방식(\(forbidden))을 쓰고 있다")
        }
        // 합성은 composer 한 곳에서만.
        #expect(source.contains("QuickMirrorComposer.compose"))
    }

    @Test("미리보기와 촬영이 같은 프레임 정의를 쓴다")
    func previewAndCaptureShareFrameDefinition() throws {
        let view = try repoFile("ggumirror/Mirror/QuickMirrorFrameView.swift")
        let composer = try repoFile("ggumirror/Mirror/QuickMirrorComposer.swift")
        for source in [view, composer] {
            #expect(source.contains("QuickMirrorFrame.hole(in:"))
            #expect(source.contains("QuickMirrorFrame.cornerRadius(in:"))
        }
    }

    @Test("프레임 overlay가 조작을 막지 않는다")
    func frameDoesNotBlockTouches() throws {
        let source = try repoFile("ggumirror/Mirror/QuickMirrorFrameView.swift")
        #expect(source.contains("allowsHitTesting(false)"))

        // 카메라 위 · 조작 아래 순서.
        let view = try repoFile("GgumirrorCapture/GgumirrorCaptureViewFinder.swift")
        let frame = try #require(view.range(of: "QuickMirrorFrameView(preset:"))
        let controls = try #require(view.range(of: "\n            controls"))
        let camera = try #require(view.range(of: "CameraPreviewView(camera:"))
        #expect(camera.lowerBound < frame.lowerBound)
        #expect(frame.lowerBound < controls.lowerBound)
    }

    @Test("프레임 렌더러가 저장소 / network를 쓰지 않는다")
    func frameRendererIsPure() throws {
        for path in ["ggumirror/Mirror/QuickMirrorPreset.swift",
                     "ggumirror/Mirror/QuickMirrorFrameView.swift",
                     "ggumirror/Mirror/QuickMirrorComposer.swift"] {
            let source = codeOnly(try repoFile(path))
            for forbidden in ["MirrorStore", "StickerProjectStore", "URLSession", "Bundle.main",
                              "AuthSession", "BackendClient", "FileManager"] {
                #expect(!source.contains(forbidden), "\(path)에 \(forbidden)이 있다")
            }
        }
    }

    // MARK: - C-1B: 잠금화면 진입 안정성 (실기기에서 간헐 실패했던 문제)

    @Test("카메라를 못 잡은 상태는 최종이 아니다 — 다시 시도할 수 있다")
    func unavailableCameraIsRetryable() {
        // 이게 "한 번씩 바로 안 들어가던" 원인이었다:
        // 첫 시도가 실패하면 .unavailable로 굳어 재시도가 전부 막혔다.
        #expect(MirrorCamera.canRetry(.unavailable))
        #expect(MirrorCamera.canRetry(.idle))
        #expect(MirrorCamera.canRetry(.ready))
        // 권한 거부만 최종이다 — 설정에서 바꿔야 한다.
        #expect(!MirrorCamera.canRetry(.denied))
    }

    @Test("구성 실패가 영구히 굳지 않는다")
    func failedConfigurationIsNotLatched() throws {
        let source = codeOnly(try repoFile("ggumirror/Mirror/MirrorCamera.swift"))
        // isConfigured는 입력을 실제로 붙인 **뒤에** 세워야 한다.
        let guardIndex = try #require(source.range(of: "guard !isConfigured else { return }"))
        let addInput = try #require(source.range(of: "session.addInput(input)"))
        let latch = try #require(source.range(of: "isConfigured = true"))
        #expect(guardIndex.lowerBound < addInput.lowerBound)
        #expect(addInput.lowerBound < latch.lowerBound, "실패한 구성이 영구히 굳는다")
    }

    @Test("extension이 카메라 시작을 짧게 재시도한다")
    func extensionRetriesCameraStart() throws {
        let source = codeOnly(try repoFile("GgumirrorCapture/GgumirrorCaptureViewFinder.swift"))
        #expect(source.contains("for attempt in 1...3"))
        #expect(source.contains("MirrorCamera.canRetry"))
        // 무한 재시도가 아니다.
        #expect(!source.contains("while true"))
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

    // extension ↔ 본앱 버전 parity는 `AppConfigTests.extensionsMatchTheApp`이 지킨다.
    //
    // 여기 있던 test는 extension 버전이 `3` / `1.0.2`인지를 **숫자로 박아** 확인했다.
    // 본앱만 `4` / `1.0.3`으로 올라갔을 때 그 test는 그대로 통과했고,
    // 정작 지키려던 "본앱과 같다"는 규칙만 조용히 깨졌다.
    // 기대값을 상수로 적지 않고 **본앱 설정과 비교**해야 이런 일이 생기지 않는다.


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
        // 잠금화면은 `.viewfinder`라 배율 UI도 배율 변경도 없다 — 언제나 1x다.
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
