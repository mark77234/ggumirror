//
//  ExternalMirrorImportTests.swift
//  ggumirrorTests
//
//  바깥에서 만든 거울 가져오기.
//
//  가장 중요한 두 가지:
//
//  1. **초록을 카메라 자리 안에서만 본다.** 그림 전체에서 지우면 초록 꽃도
//     초록 글씨도 사라진다.
//  2. **확신이 없으면 지우지 않는다.** 규격을 모르고 만든 그림에서 사용자가
//     그린 것이 조용히 사라지는 것이 최악이다.
//

import Testing
import CoreGraphics
import Foundation
@testable import ggumirror

// MARK: - 그림 만들기

private let canvas = ExternalMirrorImportContract.canvasSize
private let W = Int(canvas.width)
private let H = Int(canvas.height)

/// 픽셀 버퍼 하나. 카메라 자리와 그 밖을 따로 칠할 수 있다.
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

private func cgImage(from pixels: [UInt8]) -> CGImage {
    var buffer = pixels
    return CGContext(
        data: &buffer, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.makeImage()!
}

private func rgba(_ image: CGImage) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(
        data: &pixels, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixels
}

private let GREEN: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 0, 255)
private let RED: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)
private let CLEAR: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)

/// 카메라 자리 한가운데와, 자리 밖 한 점.
private func samples() -> (inside: Int, outside: Int) {
    let rect = MirrorImportNormalizer.openingBounds(width: W, height: H)
    let inside = ((rect.minY + rect.maxY) / 2) * W * 4 + ((rect.minX + rect.maxX) / 2) * 4
    // 왼쪽 프레임 밴드 한가운데.
    let outside = ((rect.minY + rect.maxY) / 2) * W * 4 + (rect.minX / 2) * 4
    return (inside, outside)
}

// MARK: - 규격

@Suite("제작 규격")
struct ExternalMirrorContractTests {

    @Test("비율은 실제 거울에서 온다")
    func ratioComesFromTheRealMirror() {
        // 규격이 여기서 숫자를 새로 정하면 실제 거울과 갈라진다.
        #expect(ExternalMirrorImportContract.canvasSize == MirrorCanvas.size)
        #expect(ExternalMirrorImportContract.aspectRatio == MirrorCanvas.aspectRatio)
        #expect(ExternalMirrorImportContract.canvasSize == CGSize(width: 1080, height: 2340))
    }

    @Test("카메라 자리도 실제 거울에서 온다")
    func openingComesFromTheRealMirror() {
        let rect = ExternalMirrorImportContract.cameraOpening
        #expect(rect == MirrorFrameInsets.standard.mirrorArea)
        // 1080 × 2340에서 864 × 1940. 실제 거울과 같은 값이다.
        let pixels = ExternalMirrorImportContract.cameraOpeningPixels
        #expect(Int(pixels.width.rounded()) == 864)
        #expect(Int(pixels.height.rounded()) == 1940)
        #expect(Int(pixels.origin.x.rounded()) == 108)
        #expect(Int(pixels.origin.y.rounded()) == 180)
    }

    @Test("표시 색은 순수 초록이다")
    func chromaIsPureGreen() {
        #expect(ExternalMirrorImportContract.chroma == (0, 255, 0))
        #expect(ExternalMirrorImportContract.chromaHex == "#00FF00")
        #expect(ExternalMirrorImportContract.isChroma(r: 0, g: 255, b: 0))
    }

    @Test("허용치를 넓게 잡지 않는다")
    func toleranceStaysNarrow() {
        // 넓히면 연두색 장식까지 초록으로 본다.
        #expect(ExternalMirrorImportContract.isChroma(r: 10, g: 250, b: 10))
        #expect(!ExternalMirrorImportContract.isChroma(r: 120, g: 255, b: 120))
        #expect(!ExternalMirrorImportContract.isChroma(r: 0, g: 128, b: 0))
        #expect(!ExternalMirrorImportContract.isChroma(r: 0, g: 255, b: 255))
    }
}

// MARK: - 지우기

@Suite("카메라 자리만 비운다")
struct CameraOpeningRemovalTests {

    @Test("초록으로 칠한 자리가 투명해진다")
    func chromaOpeningBecomesTransparent() throws {
        let image = cgImage(from: makePixels(outside: RED, inside: GREEN))
        let result = try MirrorImportNormalizer.normalize(image: image)
        let pixels = rgba(result)
        let point = samples()
        #expect(pixels[point.inside + 3] == 0)
    }

    @Test("자리 밖 초록은 살아남는다")
    func greenOutsideTheOpeningSurvives() throws {
        // **가장 중요한 test다.** 초록 꽃·초록 글씨가 사라지면 안 된다.
        let image = cgImage(from: makePixels(outside: GREEN, inside: GREEN))
        let result = try MirrorImportNormalizer.normalize(image: image)
        let pixels = rgba(result)
        let point = samples()

        #expect(pixels[point.inside + 3] == 0, "카메라 자리가 비지 않았다")
        #expect(pixels[point.outside + 3] == 255, "자리 밖 초록이 지워졌다")
        #expect(pixels[point.outside + 1] == 255)
    }

    @Test("자리 밖 그림은 그대로다")
    func artworkOutsideIsPreserved() throws {
        let image = cgImage(from: makePixels(outside: RED, inside: GREEN))
        let pixels = rgba(try MirrorImportNormalizer.normalize(image: image))
        let point = samples()
        #expect(pixels[point.outside] == 255)      // R
        #expect(pixels[point.outside + 1] == 0)    // G
        #expect(pixels[point.outside + 3] == 255)  // A
    }

    @Test("이미 비어 있으면 그대로 통과한다")
    func alreadyTransparentPasses() throws {
        // 앱이 준 작업 가이드로 만들면 이렇게 온다. 다시 표시를 요구하지 않는다.
        let image = cgImage(from: makePixels(outside: RED, inside: CLEAR))
        let pixels = rgba(try MirrorImportNormalizer.normalize(image: image))
        let point = samples()
        #expect(pixels[point.inside + 3] == 0)
        #expect(pixels[point.outside + 3] == 255)
    }

    @Test("압축으로 색이 흔들려도 알아본다")
    func nearGreenIsAccepted() throws {
        // JPEG를 지나면 정확한 값이 유지되지 않는다.
        let nearly: (UInt8, UInt8, UInt8, UInt8) = (12, 246, 8, 255)
        let image = cgImage(from: makePixels(outside: RED, inside: nearly))
        let pixels = rgba(try MirrorImportNormalizer.normalize(image: image))
        #expect(pixels[samples().inside + 3] == 0)
    }
}

// MARK: - 안전한 실패

@Suite("확신이 없으면 지우지 않는다")
struct SafeImportFailureTests {

    @Test("표시가 없으면 거절한다")
    func unmarkedOpeningIsRefused() {
        // 규격을 모르고 만든 그림이다. 사용자가 그린 것을 지우지 않는다.
        let image = cgImage(from: makePixels(outside: RED, inside: RED))
        #expect(throws: MirrorImportFailure.cameraOpeningNotMarked) {
            try MirrorImportNormalizer.normalize(image: image)
        }
    }

    @Test("거절 문구가 무엇을 해야 하는지 말한다")
    func failureExplainsTheFix() {
        let message = MirrorImportFailure.cameraOpeningNotMarked.message
        #expect(message.contains("#00FF00"))
        #expect(message.contains("제작 가이드"))
    }

    @Test("비율이 다르면 늘리지 않고 거절한다")
    func wrongRatioIsRefused() {
        var square = [UInt8](repeating: 255, count: 100 * 100 * 4)
        let image = CGContext(
            data: &square, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!.makeImage()!

        #expect(throws: MirrorImportFailure.wrongAspectRatio(width: 100, height: 100)) {
            try MirrorImportNormalizer.normalize(image: image)
        }
    }

    @Test("테두리가 없으면 거울이 아니라고 거절한다")
    func imageWithoutAFrameIsRefused() {
        // 카메라 자리 표시는 맞지만 그 밖이 비어 있다 — 지우고 나면 아무것도 없다.
        let image = cgImage(from: makePixels(outside: CLEAR, inside: GREEN))
        #expect(throws: MirrorImportFailure.nothingLeftAfterRemoval) {
            try MirrorImportNormalizer.normalize(image: image)
        }
    }

    @Test("초록 테두리 자체는 정상이다")
    func aGreenFrameIsStillAMirror() throws {
        // 밖이 전부 초록이어도 테두리가 있으면 거울이다 — 지우는 것은 안쪽뿐이다.
        let image = cgImage(from: makePixels(outside: GREEN, inside: GREEN))
        let pixels = rgba(try MirrorImportNormalizer.normalize(image: image))
        #expect(pixels[samples().outside + 3] == 255)
    }

    @Test("읽을 수 없는 파일은 거절한다")
    func unreadableDataIsRefused() {
        #expect(throws: MirrorImportFailure.unreadable) {
            try MirrorImportNormalizer.normalize(Data([0, 1, 2, 3]))
        }
    }

    @Test("실패하면 거울을 만들지 않는다")
    func failureSavesNothing() throws {
        let view = codeWithoutComments(try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "ggumirror/MyMirrors/ExternalArtworkView.swift"),
            encoding: .utf8
        ))
        // 실패는 `problem`으로만 간다 — `candidate`를 만들지 않는다.
        let start = try #require(view.range(of: "catch let failure as MirrorImportFailure")).upperBound
        let end = try #require(view.range(of: "private static func title", range: start..<view.endIndex)).lowerBound
        #expect(!view[start..<end].contains("candidate ="))
    }
}

// MARK: - 표시 판정

@Suite("표시 판정")
struct MarkingDetectionTests {

    @Test("초록이 조금뿐이면 표시로 보지 않는다")
    func aFewGreenPixelsAreNotAMarking() {
        var pixels = makePixels(outside: RED, inside: RED)
        // 카메라 자리 한가운데 몇 픽셀만 초록으로.
        let rect = MirrorImportNormalizer.openingBounds(width: W, height: H)
        let y = (rect.minY + rect.maxY) / 2
        for x in rect.minX..<(rect.minX + 20) {
            let i = y * W * 4 + x * 4
            (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]) = GREEN
        }
        #expect(MirrorImportNormalizer.marking(in: pixels, width: W, height: H) == .unmarked)
    }

    @Test("자리를 채우면 표시로 본다")
    func filledOpeningIsAMarking() {
        let pixels = makePixels(outside: RED, inside: GREEN)
        #expect(MirrorImportNormalizer.marking(in: pixels, width: W, height: H) == .chroma)
    }

    @Test("비어 있으면 이미 준비된 것으로 본다")
    func emptyOpeningIsAlreadyTransparent() {
        let pixels = makePixels(outside: RED, inside: CLEAR)
        #expect(MirrorImportNormalizer.marking(in: pixels, width: W, height: H) == .alreadyTransparent)
    }

    @Test("자리 밖 초록은 판정에 끼어들지 않는다")
    func greenOutsideDoesNotAffectDetection() {
        // 밖이 전부 초록이어도 안이 빨강이면 표시가 없는 것이다.
        let pixels = makePixels(outside: GREEN, inside: RED)
        #expect(MirrorImportNormalizer.marking(in: pixels, width: W, height: H) == .unmarked)
    }
}

// MARK: - 규격이 흩어지지 않는다

@Suite("규격 drift 방지")
struct ImportContractDriftTests {

    private func file(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    @Test("규격 파일에 숫자를 다시 적지 않았다")
    func contractDoesNotRestateNumbers() throws {
        let code = codeWithoutComments(try file("ggumirror/Shared/ExternalMirrorImport.swift"))
        // 108 · 180 · 220 · 1080 · 2340을 여기서 다시 적으면 실제 거울과 갈라진다.
        for magic in ["108", "180.0", "220", "1080", "2340"] {
            #expect(!code.contains(magic), "규격이 \(magic)을 다시 적었다")
        }
        #expect(code.contains("MirrorCanvas.size"))
        #expect(code.contains("MirrorFrameInsets.standard.mirrorArea"))
    }

    @Test("문서의 값이 코드와 같다")
    func documentMatchesTheCode() throws {
        let doc = try file("docs/external-mirror-creator-guide-ko.md")
        let pixels = ExternalMirrorImportContract.cameraOpeningPixels
        let size = ExternalMirrorImportContract.recommendedPixelSize

        #expect(doc.contains("\(Int(size.width)) × \(Int(size.height))"))
        #expect(doc.contains("\(Int(pixels.width.rounded())) × \(Int(pixels.height.rounded()))"))
        #expect(doc.contains(ExternalMirrorImportContract.chromaHex))
        #expect(doc.contains(ExternalMirrorImportContract.aspectRatioLabel))
    }

    @Test("Phase D가 다시 만들 필요가 없다")
    func contractIsSourceAgnostic() throws {
        let code = codeWithoutComments(try file("ggumirror/Shared/MirrorImportNormalizer.swift"))
        // 메모리에 있는 그림을 그대로 받는 문이 있어야 AI 결과가 같은 길을 지난다.
        #expect(code.contains("static func normalize(image: CGImage)"))
        // 사진 앱·파일에 묶여 있지 않다.
        #expect(!code.contains("PhotosPicker"))
        #expect(!code.contains("UIImagePicker"))
    }

    @Test("서버를 부르지 않는다")
    func importCostsNothing() throws {
        let code = codeWithoutComments(try file("ggumirror/Shared/MirrorImportNormalizer.swift"))
        for forbidden in ["URLSession", "backend", "await ", "Vision", "OpenAI"] {
            #expect(!code.contains(forbidden), "가져오기가 \(forbidden)를 쓴다")
        }
    }

    @Test("상점 썸네일 처리는 그대로다")
    func storeThumbnailPipelineUntouched() throws {
        // 기존 normalizer를 건드리지 않았다 — Store 그림 모양이 바뀌면 안 된다.
        let code = codeWithoutComments(try file("ggumirror/Store/MirrorThumbnailNormalizer.swift"))
        #expect(code.contains("cameraOpeningRemoved"))
        #expect(code.contains("dominantOpaqueColour"))
        // 새 chroma 규격이 상점 쪽으로 새어 들어가지 않았다.
        #expect(!code.contains("ExternalMirrorImportContract"))
    }
}
