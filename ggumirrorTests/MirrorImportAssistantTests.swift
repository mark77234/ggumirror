//
//  MirrorImportAssistantTests.swift
//  ggumirrorTests
//
//  I-9. 고칠 수 있는 실패를 앱 안에서 고친다.
//
//  지키는 것: **규격은 그대로**, 승인 없이는 아무 픽셀도 지우지 않는다,
//  미리보기와 저장 결과가 같다.
//

import Testing
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import ggumirror

private let W = Int(MirrorCanvas.size.width)
private let H = Int(MirrorCanvas.size.height)

private let RED: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)
private let GREEN: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 0, 255)
private let CLEAR: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)

private func makePixels(
    outside: (UInt8, UInt8, UInt8, UInt8),
    inside: (UInt8, UInt8, UInt8, UInt8)
) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: W * H * 4)
    let rect = MirrorImportNormalizer.openingBounds(width: W, height: H)
    for y in 0..<H {
        let row = y * W * 4
        for x in 0..<W {
            let i = row + x * 4
            let isInside = x >= rect.minX && x < rect.maxX && y >= rect.minY && y < rect.maxY
            let colour = isInside ? inside : outside
            (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]) = colour
        }
    }
    return pixels
}

private func cgImage(from pixels: [UInt8], width: Int = W, height: Int = H) -> CGImage {
    var buffer = pixels
    return CGContext(
        data: &buffer, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.makeImage()!
}

/// 임의 크기의 불투명 사진.
private func photo(width: Int, height: Int) -> CGImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for i in stride(from: 0, to: pixels.count, by: 4) {
        (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]) = (120, 90, 200, 255)
    }
    return cgImage(from: pixels, width: width, height: height)
}

private func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    CGContext(
        data: &pixels, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixels[(y * image.width + x) * 4 + 3]
}

private func rgb(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    CGContext(
        data: &pixels, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let i = (y * image.width + x) * 4
    return (pixels[i], pixels[i + 1], pixels[i + 2])
}

// MARK: - 실패 분류

@Suite("무엇이 잘못됐는지 픽셀이 말한다")
struct ImportFailureClassificationTests {

    @Test("보통의 사진은 fullyOpaque다")
    func opaquePhotoIsClassifiedSeparately() {
        // 투명한 곳이 한 곳도 없다 — 규격을 맞추려던 그림이 아니다.
        let image = cgImage(from: makePixels(outside: RED, inside: RED))
        #expect(throws: MirrorImportFailure.fullyOpaque) {
            try MirrorImportNormalizer.normalize(image: image)
        }
    }

    @Test("투명한 곳이 있는데 규격을 못 맞춘 것은 fullyOpaque가 아니다")
    func partiallyTransparentIsNotOpaque() {
        // 자리 **밖**이 뚫려 있다. 규격을 맞추려다 어긋난 그림이다 —
        // "카메라가 보일 공간이 없다"고 하면 틀린 말이 된다.
        let image = cgImage(from: makePixels(outside: CLEAR, inside: RED))
        #expect(throws: MirrorImportFailure.cameraOpeningNotMarked) {
            try MirrorImportNormalizer.normalize(image: image)
        }
    }

    @Test("고칠 수 있는 실패와 아닌 것을 도메인이 안다")
    func remedyIsADomainDecision() {
        // 화면이 문자열을 보고 판단하지 않는다.
        #expect(MirrorImportFailure.wrongAspectRatio(width: 1, height: 1).remedy == .crop)
        #expect(MirrorImportFailure.fullyOpaque.remedy == .openingRepair)
        #expect(MirrorImportFailure.cameraOpeningNotMarked.remedy == .openingRepair)
        #expect(MirrorImportFailure.nothingLeftAfterRemoval.remedy == nil)
        #expect(MirrorImportFailure.unreadable.remedy == nil)
    }

    @Test("고칠 수 없는 실패는 그대로 실패다")
    func hardFailuresStayHard() {
        // 지우고 나면 아무것도 남지 않는 그림.
        let image = cgImage(from: makePixels(outside: CLEAR, inside: GREEN))
        #expect(throws: MirrorImportFailure.nothingLeftAfterRemoval) {
            try MirrorImportNormalizer.normalize(image: image)
        }
        #expect(throws: MirrorImportFailure.unreadable) {
            try MirrorImportNormalizer.normalize(Data([0x00, 0x01]))
        }
    }

    @Test("두 실패에 서로 다른 말을 한다")
    func eachFailureExplainsItself() {
        #expect(MirrorImportFailure.fullyOpaque.remedyTitle != nil)
        #expect(MirrorImportFailure.cameraOpeningNotMarked.remedyTitle != nil)
        #expect(MirrorImportFailure.fullyOpaque.remedyTitle
            != MirrorImportFailure.cameraOpeningNotMarked.remedyTitle)
        // 고칠 수 없는 실패에는 고치는 버튼을 만들지 않는다.
        #expect(MirrorImportFailure.unreadable.remedyActionTitle == nil)
    }
}

// MARK: - 규격 보존

@Suite("규격은 그대로다")
struct ImportContractUnchangedTests {

    @Test("정상 이미지는 도우미를 거치지 않는다")
    func validImageTakesTheFastPath() throws {
        let image = cgImage(from: makePixels(outside: RED, inside: GREEN))
        let result = try MirrorImportNormalizer.normalize(image: image)
        #expect(result.width == W)
        #expect(result.height == H)
    }

    @Test("Phase C 값이 하나도 바뀌지 않았다")
    func canonicalNumbersAreUntouched() {
        #expect(MirrorCanvas.size == CGSize(width: 1080, height: 2340))
        #expect(ExternalMirrorImportContract.chromaHex == "#00FF00")
        #expect(ExternalMirrorImportContract.chromaTolerance == 40)
        #expect(MirrorImportNormalizer.requiredMarkedFraction == 0.6)

        // 규격의 authority는 **비율**이다. 픽셀 경계는 거기서 파생된다.
        let opening = ExternalMirrorImportContract.cameraOpening
        #expect(opening.x * 1080 == 108)
        #expect(opening.y * 2340 == 180)
        #expect((opening.width * 1080).rounded() == 864)
        #expect((opening.height * 2340).rounded() == 1940)

        // 파생된 픽셀 경계는 시작점이 정확하고, 끝은 **바깥으로만** 반올림한다
        // (`.rounded(.up)`). 그래서 세로가 1px 넓을 수 있다 — Phase C부터 그랬고,
        // 안쪽으로 깎여 테두리가 남는 것보다 낫다.
        let rect = MirrorImportNormalizer.openingBounds(width: W, height: H)
        #expect(rect.minX == 108)
        #expect(rect.minY == 180)
        #expect(rect.maxX - rect.minX == 864)
        #expect(abs((rect.maxY - rect.minY) - 1940) <= 1)
    }

    @Test("자르기가 두 번째 판정 기준을 만들지 않는다")
    func cropRoutesBackThroughTheNormalizer() throws {
        let assistant = try source("ggumirror/Shared/MirrorImportAssistant.swift")
        // 자른 뒤에도, 지운 뒤에도 판정은 normalizer가 한다.
        #expect(assistant.contains("MirrorImportNormalizer.normalize(image: image)"))
        let crop = try source("ggumirror/Shared/MirrorImportCrop.swift")
        #expect(!crop.contains("requiredMarkedFraction"))
        #expect(!crop.contains("isChroma"))
    }
}

// MARK: - 자르기

@Suite("자르기")
struct MirrorImportCropTests {

    @Test("비율이 다르면 자르기가 필요하다")
    func detectsWrongRatio() {
        #expect(MirrorImportCrop.needsCrop(photo(width: 1000, height: 1000)))
        #expect(!MirrorImportCrop.needsCrop(photo(width: W, height: H)))
    }

    @Test("자른 결과가 규격 비율이다")
    func cropOutputMatchesTheCanonicalRatio() throws {
        let image = photo(width: 2000, height: 1000)
        let window = MirrorImportCrop.centeredWindow(
            imageSize: CGSize(width: 2000, height: 1000)
        )
        let cropped = try MirrorImportCrop.cropped(image, to: window)

        let ratio = Double(cropped.width) / Double(cropped.height)
        #expect(abs(ratio - Double(MirrorImportCrop.aspectRatio)) < 0.01)
        // 늘리지 않았다 — 잘라낸 것이다.
        #expect(cropped.height <= image.height)
        #expect(cropped.width <= image.width)
    }

    @Test("최소 배율이 빈 자리를 막는다")
    func minimumScaleFillsTheWindow() {
        let window = CGSize(width: 270, height: 585)
        // 창보다 작은 그림은 키워야 채워진다.
        let small = MirrorImportCrop.minimumScale(
            imageSize: CGSize(width: 100, height: 100), windowSize: window
        )
        #expect(small > 1)
        // 그 배율로 키우면 두 변 모두 창 이상이다.
        #expect(100 * small >= window.width - 0.001)
        #expect(100 * small >= window.height - 0.001)
    }

    @Test("창이 그림 밖으로 나가지 않는다")
    func windowStaysInsideTheImage() {
        let size = CGSize(width: 1000, height: 2000)
        let pushed = CGRect(x: -500, y: 5000, width: 400, height: 866)
        let clamped = MirrorImportCrop.clamped(window: pushed, imageSize: size)

        #expect(clamped.minX >= 0)
        #expect(clamped.minY >= 0)
        #expect(clamped.maxX <= size.width)
        #expect(clamped.maxY <= size.height)
    }

    @Test("자르기가 원본을 바꾸지 않는다")
    func croppingDoesNotMutateTheSource() throws {
        let image = photo(width: 2000, height: 1000)
        let before = (image.width, image.height)
        _ = try MirrorImportCrop.cropped(
            image, to: CGRect(x: 0, y: 0, width: 400, height: 866)
        )
        #expect((image.width, image.height) == before)
    }
}

// MARK: - 가운데를 거울로 지정

@Suite("승인해야 지운다")
struct OpeningRepairTests {

    @Test("승인하면 규격 자리만 정확히 비워진다")
    func repairClearsExactlyTheCanonicalOpening() throws {
        let image = cgImage(from: makePixels(outside: RED, inside: RED))
        let repaired = try MirrorImportNormalizer.clearingCameraOpening(image)
        let rect = MirrorImportNormalizer.openingBounds(width: W, height: H)

        // 자리 안은 비었다.
        let insideX = (rect.minX + rect.maxX) / 2
        let insideY = (rect.minY + rect.maxY) / 2
        #expect(alpha(repaired, x: insideX, y: insideY) == 0)

        // **자리 밖은 원래 픽셀 그대로다.**
        let outsideX = rect.minX / 2
        #expect(alpha(repaired, x: outsideX, y: insideY) == 255)
        #expect(rgb(repaired, x: outsideX, y: insideY) == (255, 0, 0))
    }

    @Test("경계 바로 안팎이 갈린다")
    func theBoundaryIsExact() throws {
        let image = cgImage(from: makePixels(outside: RED, inside: RED))
        let repaired = try MirrorImportNormalizer.clearingCameraOpening(image)
        let rect = MirrorImportNormalizer.openingBounds(width: W, height: H)
        let y = (rect.minY + rect.maxY) / 2

        #expect(alpha(repaired, x: rect.minX, y: y) == 0)
        #expect(alpha(repaired, x: rect.minX - 1, y: y) == 255)
        #expect(alpha(repaired, x: rect.maxX - 1, y: y) == 0)
        #expect(alpha(repaired, x: rect.maxX, y: y) == 255)

        // **위아래도 본다.** 가로줄 하나만 보면 행을 한 줄 더 지워도 통과한다.
        let x = (rect.minX + rect.maxX) / 2
        #expect(alpha(repaired, x: x, y: rect.minY) == 0)
        #expect(alpha(repaired, x: x, y: rect.minY - 1) == 255)
        #expect(alpha(repaired, x: x, y: rect.maxY - 1) == 0)
    }

    @Test("지운 뒤 규격을 통과한다")
    func repairedImagePassesTheNormalizer() throws {
        let image = cgImage(from: makePixels(outside: RED, inside: RED))
        let repaired = try MirrorImportNormalizer.clearingCameraOpening(image)
        // 이제 정상으로 판정된다 — 두 번째 기준이 아니라 같은 기준이다.
        let result = try MirrorImportNormalizer.normalize(image: repaired)
        #expect(result.width == W)
    }

    @Test("승인 전에는 지우지 않는다")
    func nothingIsClearedWithoutApproval() throws {
        let assistant = try source("ggumirror/Shared/MirrorImportAssistant.swift")
        // 지우는 함수는 사용자가 누르는 자리에서만 불린다.
        let start = try #require(assistant.range(of: "func repairOpening()")).upperBound
        let elsewhere = assistant[..<assistant.range(of: "func repairOpening()")!.lowerBound]
        #expect(!elsewhere.contains("clearingCameraOpening"))
        #expect(assistant[start...].contains("clearingCameraOpening"))
    }

    @Test("사용자의 사진 원본에 쓰지 않는다")
    func sourcePhotoIsNeverWritten() throws {
        for path in ["ggumirror/Shared/MirrorImportAssistant.swift",
                     "ggumirror/Shared/MirrorImportCrop.swift",
                     "ggumirror/MyMirrors/MirrorImportAssistantView.swift"] {
            let code = try source(path)
            for banned in ["PHPhotoLibrary", "performChanges", "writeTo", "creationRequest"] {
                #expect(!code.contains(banned), "\(path): \(banned)")
            }
        }
    }
}

// MARK: - 흐름

@Suite("도우미 흐름")
@MainActor
struct ImportAssistantFlowTests {

    private func png(_ image: CGImage) -> Data {
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return out as Data
    }

    @Test("정상 이미지는 바로 최종 미리보기다")
    func validImageGoesStraightToPreview() async {
        let assistant = MirrorImportAssistant()
        await assistant.begin(data: png(cgImage(from: makePixels(outside: RED, inside: GREEN))))
        #expect(assistant.step == .preview)
        #expect(assistant.normalized != nil)
    }

    @Test("불투명 사진은 지정 단계로 간다")
    func opaquePhotoAsksBeforeClearing() async {
        let assistant = MirrorImportAssistant()
        await assistant.begin(data: png(cgImage(from: makePixels(outside: RED, inside: RED))))

        #expect(assistant.step == .openingRepair(.fullyOpaque))
        // **아직 아무것도 지우지 않았다.**
        #expect(assistant.normalized == nil)
    }

    @Test("승인하면 최종 미리보기로 간다")
    func approvingRepairReachesPreview() async {
        let assistant = MirrorImportAssistant()
        await assistant.begin(data: png(cgImage(from: makePixels(outside: RED, inside: RED))))
        await assistant.repairOpening()

        #expect(assistant.step == .preview)
        #expect(assistant.normalized != nil)
    }

    @Test("비율이 다르면 자르기 단계로 간다")
    func wrongRatioOpensCrop() async {
        let assistant = MirrorImportAssistant()
        await assistant.begin(data: png(photo(width: 1200, height: 1200)))
        #expect(assistant.step == .crop)
    }

    @Test("읽지 못하는 것은 그대로 실패다")
    func unreadableStaysFailed() async {
        let assistant = MirrorImportAssistant()
        await assistant.begin(data: Data([0x00, 0x01, 0x02]))
        #expect(assistant.step == .failed(.unreadable))
    }

    @Test("다시 수정하면 고치기 전으로 돌아간다")
    func startOverUndoesTheRepair() async {
        let assistant = MirrorImportAssistant()
        await assistant.begin(data: png(cgImage(from: makePixels(outside: RED, inside: RED))))
        await assistant.repairOpening()
        #expect(assistant.step == .preview)

        await assistant.startOver()

        // 지운 것이 되돌아왔다 — 다시 물어보는 자리로 온다.
        #expect(assistant.step == .openingRepair(.fullyOpaque))
        #expect(assistant.normalized == nil)
    }

    @Test("미리보기에 보이는 것이 저장될 그림이다")
    func previewIsTheSavedAsset() async throws {
        let assistant = MirrorImportAssistant()
        await assistant.begin(data: png(cgImage(from: makePixels(outside: RED, inside: RED))))
        await assistant.repairOpening()

        let shown = try #require(assistant.normalized)
        // 규격 크기이고, 카메라 자리가 비어 있다 — 저장 결과와 같은 조건이다.
        #expect(shown.width == W)
        #expect(shown.height == H)
        let rect = MirrorImportNormalizer.openingBounds(width: W, height: H)
        #expect(alpha(shown, x: (rect.minX + rect.maxX) / 2, y: (rect.minY + rect.maxY) / 2) == 0)
    }

    @Test("무거운 일을 main thread에서 하지 않는다")
    func heavyWorkIsOffTheMainThread() throws {
        let code = try source("ggumirror/Shared/MirrorImportAssistant.swift")
        // 디코드 · 자르기 · 지우기 · 판정 전부 detached다.
        #expect(code.components(separatedBy: "Task.detached").count - 1 >= 4)
        #expect(code.contains("isWorking"))
    }
}

private func source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}
