//
//  OwnContentExportTests.swift
//  ggumirrorTests
//
//  내보내기는 **내가 만든 것만**, 그리고 **화면이 아니라 master canvas에서** 나온다.
//
//  여기서 지키는 것:
//  1. 거울 export는 언제나 1080 × 2340 — 기기 / Dynamic Type / scale과 무관하다
//  2. 편집 화면의 것(안내선 · 선택 표시)이 절대 들어가지 않는다
//  3. 스티커는 투명도를 유지한다 — JPEG로 납작해지지 않는다
//  4. 상점에서 받은 거울은 파일로 나가지 않는다
//  5. 임시 파일은 사용자 원본 데이터와 섞이지 않고, 쓰고 나면 지운다
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import ggumirror

@MainActor
struct OwnContentExportTests {

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

    /// PNG 데이터에서 실제 픽셀 크기와 alpha 유무를 읽는다.
    private func pixels(_ data: Data) throws -> (width: Int, height: Int, hasAlpha: Bool) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let alpha = image.alphaInfo
        let hasAlpha = !(alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast)
        return (image.width, image.height, hasAlpha)
    }

    private func mirror(origin: MirrorOrigin, name: String = "내 거울") -> MyMirror {
        MyMirror(id: "export-test", name: name, origin: origin, style: MirrorStyle(frame: .pink))
    }

    private func sticker(_ source: StickerSource, x: Double) -> StickerObject {
        let width = 0.4
        let height = StickerObject.height(for: width, aspectRatio: source.aspectRatio)
        return StickerObject(
            source: source,
            frame: NormalizedRect(x: x, y: 0.4, width: width, height: height)
        )
    }

    // MARK: - 거울 export

    @Test("거울 export는 언제나 1080 × 2340이다")
    func mirrorExportIsMasterCanvas() throws {
        let data = try OwnContentExport.mirrorPNG(mirror(origin: .made))
        let size = try pixels(data)

        #expect(size.width == Int(MirrorCanvas.size.width))
        #expect(size.height == Int(MirrorCanvas.size.height))
        #expect((size.width, size.height) == (1080, 2340))
    }

    @Test("장식이 늘어도 캔버스 크기는 변하지 않는다")
    func decorationsDoNotChangeCanvas() throws {
        var decorated = mirror(origin: .made)
        decorated.texts = [TextObject(text: "안녕", center: NormalizedPoint(x: 0.5, y: 0.3))]
        let data = try OwnContentExport.mirrorPNG(decorated)
        let size = try pixels(data)

        #expect((size.width, size.height) == (1080, 2340))
    }

    @Test("투명 프레임 상태가 export에 반영된다")
    func transparentFrameIsPreserved() throws {
        var visible = MirrorStyle(frame: .pink)
        visible.isFrameVisible = true
        var invisible = visible
        invisible.isFrameVisible = false

        let withFrame = try OwnContentExport.mirrorPNG(style: visible)
        let withoutFrame = try OwnContentExport.mirrorPNG(style: invisible)

        // 프레임 밴드를 그리는 것과 안 그리는 것이 같은 그림일 수 없다.
        #expect(withFrame != withoutFrame, "투명 프레임이 export에 반영되지 않았다")
        // 둘 다 크기는 같다.
        #expect(try pixels(withFrame).width == 1080)
        #expect(try pixels(withoutFrame).width == 1080)
    }

    @Test("layer 순서가 결과를 바꾼다")
    func layerOrderingMatters() throws {
        let first = sticker(.doodle(DoodleSticker.allCases[0]), x: 0.2)
        var second = sticker(.doodle(DoodleSticker.allCases[1]), x: 0.25)
        second.zIndex = 1

        var front = second
        front.zIndex = -1

        let a = try OwnContentExport.mirrorPNG(style: MirrorStyle(frame: .pink), stickers: [first, second])
        let b = try OwnContentExport.mirrorPNG(style: MirrorStyle(frame: .pink), stickers: [first, front])

        #expect(a != b, "겹친 스티커의 순서가 결과에 반영되지 않는다")
    }

    @Test("편집 화면의 안내선 / 선택 표시가 들어갈 수 없다")
    func editorChromeCannotLeak() throws {
        let source = codeOnly(try repoFile("ggumirror/Shared/OwnContentExport.swift"))

        // 렌더 입력이 장식뿐이다. guide를 켤 인자 자체가 없다.
        #expect(!source.contains("showsCameraGuide"))
        #expect(!source.contains("MirrorCanvasView"))
        #expect(!source.contains("selection"))
        // 화면을 찍지 않는다.
        #expect(!source.contains("UIScreen"))
        #expect(!source.contains("snapshot"))
        #expect(!source.contains("drawHierarchy"))
        // 크기는 master canvas 하나에서만 온다.
        #expect(source.contains("MirrorCanvas.size"))
    }

    // MARK: - 스티커 export

    @Test("스티커는 투명 PNG로 나간다")
    func stickerKeepsAlpha() throws {
        var project = StickerProject(name: "내 스티커", design: .blank)
        project.design.texts = [TextObject(text: "하이", center: NormalizedPoint(x: 0.5, y: 0.5))]

        let data = try OwnContentExport.stickerPNG(project)
        let image = try pixels(data)

        #expect(image.hasAlpha, "스티커가 불투명하게 납작해졌다")
        #expect(image.width == Int(StickerCanvas.size.width))
        #expect(image.height == Int(StickerCanvas.size.height))
    }

    @Test("스티커 해상도 규칙은 StickerCanvas가 정한다")
    func stickerSizeComesFromCanonicalRule() throws {
        let source = codeOnly(try repoFile("ggumirror/Shared/OwnContentExport.swift"))
        // export가 자기만의 해상도를 정하지 않는다 — Creator에서 본 것과 달라진다.
        #expect(source.contains("StickerRenderer.pngData"))
        #expect(!source.contains("StickerCanvas.size"))
    }

    @Test("PNG로 저장한다 — JPEG로 바꾸지 않는다")
    func alwaysPNG() throws {
        let source = codeOnly(try repoFile("ggumirror/Shared/OwnContentExport.swift"))
        #expect(source.contains("pngData"))
        #expect(!source.contains("jpegData"), "투명도가 사라진다")
    }

    // MARK: - 소유권

    @Test("상점에서 받은 거울은 내보낼 수 없다")
    func purchasedContentIsBlocked() throws {
        for origin in [MirrorOrigin.purchased, .basic] {
            let blocked = mirror(origin: origin)
            #expect(!OwnContentExportPolicy.canExport(blocked), "\(origin.rawValue) 거울이 내보내진다")
            #expect(throws: OwnContentExportFailure.notExportable) {
                _ = try OwnContentExport.mirrorPNG(blocked)
            }
        }
    }

    @Test("내가 만든 거울만 내보낼 수 있다")
    func ownContentIsAllowed() {
        #expect(OwnContentExportPolicy.canExport(mirror(origin: .made)))
    }

    @Test("UI도 같은 정책으로 항목을 감춘다")
    func uiHidesExportForPurchased() throws {
        let view = codeOnly(try repoFile("ggumirror/MyMirrors/MyMirrorsView.swift"))
        #expect(view.contains("OwnContentExportPolicy.canExport(mirror)"))
        #expect(view.contains("사진에 저장"))
        #expect(view.contains("공유하기"))
    }

    @Test("내보내기 정책은 판매 정책과 별개다")
    func exportPolicyIsSeparateFromPublish() throws {
        let source = codeOnly(try repoFile("ggumirror/Shared/OwnContentExport.swift"))
        // 같은 답을 내더라도 한쪽이 바뀔 때 다른 쪽이 조용히 따라가면 안 된다.
        #expect(!source.contains("MirrorPublishPolicy"))
    }

    // MARK: - 임시 파일

    @Test("임시 파일은 사용자 원본 데이터와 섞이지 않는다")
    func temporaryFileStaysInTemporaryDirectory() throws {
        let file = try ExportedFile.png(Data([0x89, 0x50, 0x4E, 0x47]), name: "테스트 거울")
        defer { file.cleanUp() }

        let path = file.url.path
        #expect(path.hasPrefix(FileManager.default.temporaryDirectory.path))
        // Application Support(사용자 원본)에 쓰지 않는다.
        #expect(!path.contains("Application Support"))
        #expect(file.url.pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test("공유가 끝나면 임시 파일을 지운다")
    func temporaryFileIsCleanedUp() throws {
        let file = try ExportedFile.png(Data([0x89, 0x50]), name: "지워질 파일")
        #expect(FileManager.default.fileExists(atPath: file.url.path))

        file.cleanUp()

        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test("파일 이름에 경로 구분자가 들어와도 안전하다")
    func fileNameIsSanitised() throws {
        #expect(ExportedFile.safeName("../../etc/passwd") == "....etcpasswd")
        #expect(ExportedFile.safeName("   ") == "ggumirror")
        #expect(ExportedFile.safeName("") == "ggumirror")
        #expect(!ExportedFile.safeName("a/b:c").contains("/"))
        #expect(!ExportedFile.safeName("a/b:c").contains(":"))
    }

    @Test("남은 임시 파일을 앱 시작 때 치운다")
    func leftoversAreCleanedOnLaunch() throws {
        let file = try ExportedFile.png(Data([0x89]), name: "남은 파일")
        #expect(FileManager.default.fileExists(atPath: file.url.path))

        ExportedFile.cleanUpLeftovers()

        #expect(!FileManager.default.fileExists(atPath: file.url.path))

        let root = codeOnly(try repoFile("ggumirror/RootView.swift"))
        #expect(root.contains("ExportedFile.cleanUpLeftovers()"))
    }

    // MARK: - 권한 / 실패 안내

    @Test("사진 권한은 add-only만 쓴다")
    func photosPermissionIsAddOnly() throws {
        let capture = codeOnly(try repoFile("ggumirror/Mirror/MirrorCapture.swift"))
        #expect(capture.contains(".addOnly"))
        // 라이브러리를 읽지 않으므로 읽기 권한을 요구하지 않는다.
        #expect(!capture.contains("NSPhotoLibraryUsageDescription"))
        #expect(!capture.contains(".readWrite"))

        let project = try repoFile("ggumirror.xcodeproj/project.pbxproj")
        #expect(project.contains("INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription"))
        #expect(!project.contains("INFOPLIST_KEY_NSPhotoLibraryUsageDescription"))
    }

    @Test("실패를 구분해서 알려준다")
    func failuresAreDistinguishable() {
        let all: [OwnContentExportFailure] = [
            .notExportable, .renderingFailed, .temporaryFileFailed,
            .photosPermissionDenied, .photosSaveFailed, .sharePreparationFailed,
        ]
        // 메시지가 서로 다르다 — "실패했어요" 하나로 뭉뚱그리지 않는다.
        #expect(Set(all.map(\.message)).count == all.count)
        // 권한 거부는 무엇을 해야 하는지까지 알려준다.
        #expect(OwnContentExportFailure.photosPermissionDenied.message.contains("설정"))
    }

    @Test("로그에 파일 경로나 콘텐츠를 남기지 않는다")
    func exportNeverLogsPaths() throws {
        let source = codeOnly(try repoFile("ggumirror/Shared/OwnContentExport.swift"))
        #expect(!source.contains("print("))
        #expect(!source.contains("NSLog"))
        #expect(!source.contains("Logger("))
    }
}
