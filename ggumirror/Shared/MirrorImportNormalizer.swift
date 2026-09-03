//
//  MirrorImportNormalizer.swift
//  ggumirror
//
//  바깥에서 온 그림 하나를 **거울로 쓸 수 있는 모양**으로 바꾼다.
//
//  어디서 왔는지 묻지 않는다 — 사진 앱이든, 파일이든, 나중에 AI가 만든 것이든
//  같은 길을 지난다. Phase D가 자기만의 규격을 다시 만들지 않아도 되는 이유다.
//
//  하는 일은 셋이다:
//
//      1. 방향을 펴고 Master Canvas 크기로 맞춘다(비율이 다르면 거절한다)
//      2. 카메라 자리가 제대로 표시됐는지 **확인한다**
//      3. 그 자리를 투명하게 비운다
//
//  2번이 이 파일의 핵심이다. 예전에는 확인 없이 그냥 지웠다 — 규격을 모르고
//  만든 그림에서 **사용자가 그린 것이 조용히 사라졌다.** 이제 확신이 없으면
//  지우지 않고 묻는다.
//
//  그리고 초록색을 **카메라 자리 안에서만** 본다. 그림 전체에서 초록을 지우면
//  초록 꽃도 초록 글씨도 함께 사라진다.
//

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

nonisolated enum MirrorImportNormalizer {

    /// 카메라 자리로 인정하는 최소 비율. 표시가 있긴 한데 몇 픽셀뿐인 경우를 거른다.
    static let requiredMarkedFraction = 0.6

    /// 지운 뒤 거울 테두리에 남아 있어야 하는 최소 비율.
    /// 전부 지워져 빈 그림이 저장되는 것을 막는다.
    static let requiredRemainingFraction = 0.1

    /// 카메라 자리가 어떻게 표시돼 있는가.
    enum Marking: Equatable {
        /// 이미 비어 있다. 앱이 준 작업 가이드로 만들면 이렇게 온다.
        case alreadyTransparent
        /// 지정한 초록으로 칠해져 있다.
        case chroma
        /// 알 수 없다. **지우지 않는다.**
        case unmarked
    }

    // MARK: - 공개

    /// 파일에서 읽어 정규화한다.
    static func normalize(_ data: Data) throws -> CGImage {
        guard let decoded = decode(data) else { throw MirrorImportFailure.unreadable }
        return try normalize(image: decoded)
    }

    /// 바이트를 그림으로 편다. **규격 검사는 하지 않는다.**
    ///
    /// 자르기 도우미가 규격에 맞지 않는 그림도 먼저 보여 줘야 해서 나눠 두었다.
    /// 읽는 방법은 한 곳뿐이다 — `normalize(_:)`도 이것을 쓴다.
    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // EXIF 회전을 반영해 실제 픽셀 방향으로 편다.
        // **원본을 통째로 올리지 않는다** — 큰 사진에서 메모리가 터진다.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(ExternalMirrorImportContract.canvasSize.height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 이미 메모리에 있는 그림을 정규화한다. **AI 결과가 이 문으로 들어온다.**
    static func normalize(image: CGImage) throws -> CGImage {
        let ratio = Double(image.width) / Double(max(image.height, 1))
        let expected = Double(ExternalMirrorImportContract.aspectRatio)
        guard abs(ratio - expected) <= MirrorArtworkImporter.aspectTolerance else {
            throw MirrorImportFailure.wrongAspectRatio(width: image.width, height: image.height)
        }

        // Master Canvas 크기의 RGBA로 한 번만 편다. 이후 검사와 지우기가 같은 버퍼를 본다.
        guard var pixels = rasterized(image) else { throw MirrorImportFailure.unreadable }
        let size = ExternalMirrorImportContract.canvasSize
        let width = Int(size.width)
        let height = Int(size.height)

        switch marking(in: pixels, width: width, height: height) {
        case .unmarked:
            // **그림을 지우지 않는다.** 규격을 모르고 만든 것일 수 있다.
            //
            // 다만 무엇을 모르는지는 픽셀이 말해 준다. 투명한 곳이 한 곳도 없으면
            // 규격을 맞추려던 그림이 아니라 **보통의 사진**이다 — 할 말이 다르다.
            throw isFullyOpaque(pixels, width: width, height: height)
                ? MirrorImportFailure.fullyOpaque
                : MirrorImportFailure.cameraOpeningNotMarked
        case .alreadyTransparent, .chroma:
            break
        }

        clearCameraOpening(&pixels, width: width, height: height)
        guard hasRemainingFrame(pixels, width: width, height: height) else {
            throw MirrorImportFailure.nothingLeftAfterRemoval
        }
        guard let output = makeImage(pixels, width: width, height: height) else {
            throw MirrorImportFailure.unreadable
        }
        return output
    }

    // MARK: - 검사

    /// 카메라 자리가 어떻게 표시돼 있는가. **그 자리 안에서만 본다.**
    static func marking(in pixels: [UInt8], width: Int, height: Int) -> Marking {
        let rect = openingBounds(width: width, height: height)
        var transparent = 0
        var chroma = 0
        var total = 0

        // 전부 세지 않는다 — 성긴 표본으로 충분하고 훨씬 빠르다.
        let step = max(1, (rect.maxX - rect.minX) / 64)
        for y in stride(from: rect.minY, to: rect.maxY, by: step) {
            let row = y * width * 4
            for x in stride(from: rect.minX, to: rect.maxX, by: step) {
                let i = row + x * 4
                total += 1
                if pixels[i + 3] == 0 {
                    transparent += 1
                } else if ExternalMirrorImportContract.isChroma(
                    r: pixels[i], g: pixels[i + 1], b: pixels[i + 2]
                ) {
                    chroma += 1
                }
            }
        }
        guard total > 0 else { return .unmarked }

        let needed = Double(total) * requiredMarkedFraction
        if Double(transparent) >= needed { return .alreadyTransparent }
        if Double(transparent + chroma) >= needed { return .chroma }
        return .unmarked
    }

    /// 그림 전체에 투명한 곳이 하나도 없는가.
    ///
    /// **문자열이 아니라 픽셀로 판단한다.** 보통의 사진은 여기서 참이고,
    /// 규격을 맞추려다 실패한 그림(어딘가는 뚫려 있다)은 거짓이다.
    static func isFullyOpaque(_ pixels: [UInt8], width: Int, height: Int) -> Bool {
        // 성긴 표본으로 충분하다 — 한 곳이라도 뚫려 있으면 사진이 아니다.
        let step = max(1, width / 64)
        for y in stride(from: 0, to: height, by: step) {
            let row = y * width * 4
            for x in stride(from: 0, to: width, by: step) {
                if pixels[row + x * 4 + 3] < 255 { return false }
            }
        }
        return true
    }

    /// 카메라 자리를 **비운 사본**을 만든다. 원본은 그대로 둔다.
    ///
    /// 사용자가 명시적으로 승인했을 때만 부른다 — 이 함수가 곧 "가운데를 거울로
    /// 지정한다"는 동작이고, 좌표는 규격에서 그대로 온다.
    static func clearingCameraOpening(_ image: CGImage) throws -> CGImage {
        guard var pixels = rasterized(image) else { throw MirrorImportFailure.unreadable }
        let size = ExternalMirrorImportContract.canvasSize
        let width = Int(size.width)
        let height = Int(size.height)
        clearCameraOpening(&pixels, width: width, height: height)
        guard let output = makeImage(pixels, width: width, height: height) else {
            throw MirrorImportFailure.unreadable
        }
        return output
    }

    /// 지운 뒤에도 거울 테두리가 남아 있는가. **카메라 자리 밖만 본다.**
    static func hasRemainingFrame(_ pixels: [UInt8], width: Int, height: Int) -> Bool {
        let rect = openingBounds(width: width, height: height)
        var opaque = 0
        var total = 0
        let step = max(1, width / 48)
        for y in stride(from: 0, to: height, by: step) {
            let row = y * width * 4
            for x in stride(from: 0, to: width, by: step) {
                let inside = x >= rect.minX && x < rect.maxX && y >= rect.minY && y < rect.maxY
                if inside { continue }
                total += 1
                if pixels[row + x * 4 + 3] > 0 { opaque += 1 }
            }
        }
        guard total > 0 else { return false }
        return Double(opaque) / Double(total) >= requiredRemainingFraction
    }

    // MARK: - 내부

    /// 카메라 자리의 픽셀 범위. **좌표를 여기서 새로 계산하지 않는다.**
    static func openingBounds(
        width: Int, height: Int
    ) -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        let rect = ExternalMirrorImportContract.cameraOpening
        return (
            minX: max(0, Int((rect.x * Double(width)).rounded(.down))),
            maxX: min(width, Int(((rect.x + rect.width) * Double(width)).rounded(.up))),
            minY: max(0, Int((rect.y * Double(height)).rounded(.down))),
            maxY: min(height, Int(((rect.y + rect.height) * Double(height)).rounded(.up)))
        )
    }

    private static func clearCameraOpening(_ pixels: inout [UInt8], width: Int, height: Int) {
        let rect = openingBounds(width: width, height: height)
        for y in rect.minY..<rect.maxY {
            let row = y * width * 4
            for x in rect.minX..<rect.maxX {
                let i = row + x * 4
                pixels[i] = 0
                pixels[i + 1] = 0
                pixels[i + 2] = 0
                pixels[i + 3] = 0
            }
        }
    }

    private static func rasterized(_ image: CGImage) -> [UInt8]? {
        let size = ExternalMirrorImportContract.canvasSize
        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.clear(CGRect(origin: .zero, size: size))
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return pixels
    }

    private static func makeImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        var buffer = pixels
        return CGContext(
            data: &buffer, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }
}
