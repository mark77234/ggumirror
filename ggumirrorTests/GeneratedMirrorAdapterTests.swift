//
//  GeneratedMirrorAdapterTests.swift
//  ggumirrorTests
//
//  **AI가 만든 것을 믿지 않는다.**
//
//  모델은 확률적이라 크기도 투명도도 초록색도 매번 정확하지 않다.
//  그래서 카메라 자리는 앱이 결정적으로 찍고, 결과는 Phase C 규격을 그대로 지난다.
//
//  이 파일에서 가장 중요한 test는 하나다:
//  **AI가 카메라 자리에 무엇을 그렸든 결과는 투명하다.**
//

import Testing
import CoreGraphics
import Foundation
@testable import ggumirror

private let canvas = ExternalMirrorImportContract.canvasSize
private let W = Int(canvas.width)
private let H = Int(canvas.height)

/// 임의 크기의 단색 그림. AI가 아무 비율로 돌려줄 수 있다는 뜻이다.
private func solidImage(
    width: Int, height: Int, colour: (UInt8, UInt8, UInt8, UInt8)
) -> CGImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for i in stride(from: 0, to: pixels.count, by: 4) {
        (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]) = colour
    }
    return CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.makeImage()!
}

/// 가운데에 다른 색 덩어리를 그린 그림. "AI가 카메라 자리에 뭔가 그렸다"를 흉내 낸다.
private func imageWithCentre(
    width: Int, height: Int,
    background: (UInt8, UInt8, UInt8, UInt8),
    centre: (UInt8, UInt8, UInt8, UInt8)
) -> CGImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        let row = y * width * 4
        for x in 0..<width {
            let i = row + x * 4
            let inCentre = x > width / 4 && x < width * 3 / 4
                && y > height / 4 && y < height * 3 / 4
            let colour = inCentre ? centre : background
            (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]) = colour
        }
    }
    return CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.makeImage()!
}

private func rgba(_ image: CGImage) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    CGContext(
        data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixels
}

private func samplePoints() -> (inside: Int, outside: Int) {
    let rect = MirrorImportNormalizer.openingBounds(width: W, height: H)
    let inside = ((rect.minY + rect.maxY) / 2) * W * 4 + ((rect.minX + rect.maxX) / 2) * 4
    let outside = ((rect.minY + rect.maxY) / 2) * W * 4 + (rect.minX / 2) * 4
    return (inside, outside)
}

private let RED: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)
private let BLUE: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
private let GREEN: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 0, 255)

@Suite("AI 결과를 규격으로 찍는다")
struct GeneratedMirrorAdapterTests {

    @Test("AI가 카메라 자리에 무엇을 그렸든 투명해진다")
    func whateverIsInTheOpeningBecomesTransparent() throws {
        // **이 phase에서 가장 중요한 test다.**
        // AI가 가운데에 파란 덩어리를 그렸다 — 그래도 결과는 비어 있어야 한다.
        let generated = imageWithCentre(width: 1024, height: 1536, background: RED, centre: BLUE)
        let result = try GeneratedMirrorAdapter.prepare(image: generated)
        let pixels = rgba(result)
        let point = samplePoints()

        #expect(pixels[point.inside + 3] == 0, "카메라 자리가 비지 않았다")
        #expect(pixels[point.outside + 3] == 255, "테두리 그림이 사라졌다")
    }

    @Test("AI가 만든 초록색을 믿지 않는다")
    func doesNotTrustAIGeneratedGreen() throws {
        // AI가 초록을 **엉뚱한 자리**에 칠했다. 그래도 자리는 우리가 정한다.
        let generated = imageWithCentre(width: 1024, height: 1024, background: GREEN, centre: RED)
        let result = try GeneratedMirrorAdapter.prepare(image: generated)
        let pixels = rgba(result)
        let point = samplePoints()

        // 우리가 찍은 자리가 비었다.
        #expect(pixels[point.inside + 3] == 0)
        // AI가 칠한 바깥 초록은 그대로 남는다 — 장식일 수 있다.
        #expect(pixels[point.outside + 3] == 255)
    }

    @Test("표시를 찍으면 정확히 그 자리다")
    func stampLandsOnTheContractRect() throws {
        let stamped = try GeneratedMirrorAdapter.stamped(
            solidImage(width: 1024, height: 1024, colour: RED)
        )
        #expect(stamped.width == W)
        #expect(stamped.height == H)

        let pixels = rgba(stamped)
        let point = samplePoints()
        // 자리 안은 표시색, 밖은 AI 그림.
        #expect(pixels[point.inside] == 0)
        #expect(pixels[point.inside + 1] == 255)
        #expect(pixels[point.inside + 2] == 0)
        #expect(pixels[point.outside] == 255)
    }

    @Test("위아래 여백이 달라도 어긋나지 않는다")
    func stampRespectsAsymmetricInsets() throws {
        // 위 180 / 아래 220이라 좌표를 뒤집지 않으면 40px 밀린다.
        let stamped = try GeneratedMirrorAdapter.stamped(
            solidImage(width: 1080, height: 2340, colour: RED)
        )
        let pixels = rgba(stamped)
        let rect = MirrorImportNormalizer.openingBounds(width: W, height: H)

        // 자리 바로 위(프레임)는 빨강이어야 한다.
        let aboveOpening = (rect.minY - 20) * W * 4 + (W / 2) * 4
        #expect(pixels[aboveOpening] == 255, "위쪽 프레임이 지워졌다")
        // 자리 안쪽 맨 위는 표시색이어야 한다.
        let insideTop = (rect.minY + 20) * W * 4 + (W / 2) * 4
        #expect(pixels[insideTop + 1] == 255, "자리가 밀렸다")
    }

    @Test("비율이 달라도 늘리지 않는다")
    func neverStretches() throws {
        // 정사각형을 세로로 길게 늘리면 사람이 그린 선이 뭉개진다.
        let square = solidImage(width: 1024, height: 1024, colour: RED)
        let filled = GeneratedMirrorAdapter.aspectFilled(source: square, into: canvas)
        // 채워 자른다 — 가로세로 배율이 같다.
        #expect(abs(filled.width / 1024 - filled.height / 1024) < 0.0001)
        // 캔버스를 덮는다.
        #expect(filled.width >= canvas.width - 0.5)
        #expect(filled.height >= canvas.height - 0.5)
    }

    @Test("가운데를 남기고 자른다")
    func cropsAroundTheCentre() {
        let wide = solidImage(width: 2048, height: 1024, colour: RED)
        let filled = GeneratedMirrorAdapter.aspectFilled(source: wide, into: canvas)
        // 넘치는 쪽이 좌우 대칭으로 잘린다.
        #expect(abs(filled.midX - canvas.width / 2) < 0.5)
        #expect(abs(filled.midY - canvas.height / 2) < 0.5)
    }

    @Test("어떤 크기로 와도 캔버스 크기로 나온다")
    func alwaysProducesTheCanonicalCanvas() throws {
        for size in [(512, 512), (1024, 1536), (2048, 1024), (1080, 2340)] {
            let result = try GeneratedMirrorAdapter.prepare(
                image: imageWithCentre(
                    width: size.0, height: size.1, background: RED, centre: BLUE
                )
            )
            #expect(result.width == W, "\(size)")
            #expect(result.height == H, "\(size)")
        }
    }

    @Test("읽을 수 없는 데이터는 거절한다")
    func unreadableDataIsRefused() {
        #expect(throws: MirrorImportFailure.unreadable) {
            try GeneratedMirrorAdapter.prepare(Data([0, 1, 2]))
        }
    }
}

@Suite("Phase D는 Phase C를 우회하지 않는다")
struct AdapterReusesPhaseCTests {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return codeWithoutComments(
            try String(contentsOf: root.appending(path: path), encoding: .utf8)
        )
    }

    @Test("반드시 Phase C 규격을 지난다")
    func alwaysGoesThroughTheImportNormalizer() throws {
        let code = try source("ggumirror/Shared/GeneratedMirrorAdapter.swift")
        #expect(code.contains("MirrorImportNormalizer.normalize(image:"))
    }

    @Test("AI 전용 지우개를 만들지 않았다")
    func noAISpecificRemover() throws {
        let code = try source("ggumirror/Shared/GeneratedMirrorAdapter.swift")
        // 투명하게 만드는 일은 Phase C 한 곳에서만 한다.
        for forbidden in ["alpha = 0", "clearCameraOpening", "dominantOpaqueColour"] {
            #expect(!code.contains(forbidden), "AI 쪽에서 따로 지운다: \(forbidden)")
        }
    }

    @Test("좌표를 다시 적지 않았다")
    func geometryComesFromTheContract() throws {
        let code = try source("ggumirror/Shared/GeneratedMirrorAdapter.swift")
        #expect(code.contains("ExternalMirrorImportContract.cameraOpening"))
        #expect(code.contains("ExternalMirrorImportContract.chroma"))
        for magic in ["108", "180.0", "864", "1940", "1080", "2340"] {
            #expect(!code.contains(magic), "좌표를 다시 적었다: \(magic)")
        }
    }

    @Test("Phase C 규격 자체는 그대로다")
    func phaseCContractIsUnchanged() {
        // AI 때문에 외부 제작 규격을 바꾸지 않았다.
        #expect(ExternalMirrorImportContract.chromaTolerance == 40)
        #expect(ExternalMirrorImportContract.canvasSize == MirrorCanvas.size)
        #expect(ExternalMirrorImportContract.cameraOpening == MirrorFrameInsets.standard.mirrorArea)
        #expect(MirrorImportNormalizer.requiredMarkedFraction == 0.6)
    }
}
