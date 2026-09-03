//
//  MirrorThumbnailBackgroundTests.swift
//  ggumirrorTests
//
//  **정지 썸네일의 카메라 자리는 밝다.**
//
//  내장 템플릿은 카드가 모델을 직접 그려 지금 색을 쓰는데, 사용자 상품은 등록 시점에
//  구워진 PNG를 그대로 보여 준다. 그래서 예전에 등록된 상품만 카드에서 검게 보였고
//  **검은 글씨와 검은 그림이 그 위에서 보이지 않았다.**
//
//  아래 fixture는 **실제 production에 올라가 있는 미리보기**다(`찬찡`, 1aabc2ce…).
//  흉내 낸 그림이 아니라 진짜 legacy 상품으로 검증한다.
//

import Testing
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
@testable import ggumirror

private func fixture(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures/\(name)")
    return try Data(contentsOf: url)
}

/// PNG를 RGBA로 펼친다.
private func pixels(_ data: Data) throws -> (w: Int, h: Int, bytes: [UInt8]) {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = try #require(CGContext(
        data: &bytes, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return (image.width, image.height, bytes)
}

private func pixel(_ p: (w: Int, h: Int, bytes: [UInt8]), _ x: Int, _ y: Int)
    -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
{
    let i = (y * p.w + x) * 4
    return (p.bytes[i], p.bytes[i + 1], p.bytes[i + 2], p.bytes[i + 3])
}

/// 카메라 자리 안의 표본 좌표.
private func cameraSamples(_ w: Int, _ h: Int) -> [(Int, Int)] {
    let area = MirrorFrameInsets.standard.mirrorArea
    return (1...4).flatMap { i -> [(Int, Int)] in
        (1...4).map { j in
            (Int((area.x + area.width * Double(i) / 5) * Double(w)),
             Int((area.y + area.height * Double(j) / 5) * Double(h)))
        }
    }
}

@Suite("예전 상품 썸네일이 밝아진다")
struct LegacyThumbnailTests {

    @Test("production legacy 미리보기의 카메라 자리가 어둡다 (수정 전 사실)")
    func legacyFixtureIsDark() throws {
        let raw = try pixels(try fixture("legacy-mirror-preview.png"))
        let legacy = MirrorThumbnailNormalizer.legacyGlass
        let dark = cameraSamples(raw.w, raw.h).filter { x, y in
            let p = pixel(raw, x, y)
            return p.r == legacy.r && p.g == legacy.g && p.b == legacy.b
        }
        // 표본 대부분이 그 색이다 — 카드가 검게 보이던 이유다.
        #expect(dark.count > cameraSamples(raw.w, raw.h).count / 2)
    }

    @Test("되돌리면 밝은 종이색이 된다")
    func normalizedBecomesLight() throws {
        let normalized = try #require(
            MirrorThumbnailNormalizer.normalized(png: try fixture("legacy-mirror-preview.png"))
        )
        let out = try pixels(normalized)
        let target = MirrorThumbnailNormalizer.target()
        let legacy = MirrorThumbnailNormalizer.legacyGlass

        for (x, y) in cameraSamples(out.w, out.h) {
            let p = pixel(out, x, y)
            // 예전 어두운 색이 남아 있지 않다.
            #expect(!(p.r == legacy.r && p.g == legacy.g && p.b == legacy.b),
                    "(\(x),\(y))에 어두운 유리색이 남았다")
        }
        // 표본 대부분이 지금 정책 색이다.
        let light = cameraSamples(out.w, out.h).filter { x, y in
            let p = pixel(out, x, y)
            return p.r == target.r && p.g == target.g && p.b == target.b
        }
        #expect(light.count > cameraSamples(out.w, out.h).count / 2)
    }

    @Test("검은 요소가 배경과 합쳐지지 않는다")
    func darkContentStaysVisible() throws {
        // 되돌린 배경은 충분히 밝아 검은 글씨(#1A1A1A)와 확실히 갈린다.
        let target = MirrorThumbnailNormalizer.target()
        let ink = PaperTheme.ink.resolve(in: .init())
        let inkLuma = 0.299 * Double(ink.red) + 0.587 * Double(ink.green) + 0.114 * Double(ink.blue)
        let bgLuma = (0.299 * Double(target.r) + 0.587 * Double(target.g)
                      + 0.114 * Double(target.b)) / 255
        #expect(bgLuma > 0.8, "배경이 밝지 않다")
        #expect(bgLuma - inkLuma > 0.5, "검은 글씨와 배경이 너무 비슷하다")
    }

    @Test("프레임 밖과 장식은 건드리지 않는다")
    func onlyTheCameraAreaChanges() throws {
        let before = try pixels(try fixture("legacy-mirror-preview.png"))
        let normalized = try #require(
            MirrorThumbnailNormalizer.normalized(png: try fixture("legacy-mirror-preview.png"))
        )
        let after = try pixels(normalized)
        #expect((before.w, before.h) == (after.w, after.h))

        // 프레임 밴드(카메라 자리 밖)는 한 픽셀도 바뀌지 않는다.
        let area = MirrorFrameInsets.standard.mirrorArea
        let outside: [(Int, Int)] = [
            (5, 5), (before.w - 5, 5), (5, before.h - 5),
            (before.w / 2, Int(area.y * Double(before.h)) / 2),
            (before.w / 2, before.h - 20),
        ]
        for (x, y) in outside {
            let a = pixel(before, min(x, before.w - 1), min(y, before.h - 1))
            let b = pixel(after, min(x, after.w - 1), min(y, after.h - 1))
            #expect(a == b, "카메라 자리 밖 (\(x),\(y))이 바뀌었다")
        }
    }

    @Test("정확히 그 색만 바꾼다 — 사용자 색은 보존한다")
    func onlyTheExactColourIsReplaced() throws {
        let before = try pixels(try fixture("legacy-mirror-preview.png"))
        let after = try pixels(try #require(
            MirrorThumbnailNormalizer.normalized(png: try fixture("legacy-mirror-preview.png"))
        ))
        let legacy = MirrorThumbnailNormalizer.legacyGlass
        var checked = 0
        // 카메라 자리 안에서 **그 색이 아니었던** 픽셀은 그대로여야 한다.
        for y in stride(from: 0, to: before.h, by: 53) {
            for x in stride(from: 0, to: before.w, by: 47) {
                let a = pixel(before, x, y)
                guard !(a.r == legacy.r && a.g == legacy.g && a.b == legacy.b && a.a == 255)
                else { continue }
                #expect(pixel(after, x, y) == a, "(\(x),\(y)) 사용자 색이 바뀌었다")
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    @Test("이미 밝은 그림은 손대지 않는다")
    func alreadyLightIsLeftAlone() throws {
        // 새로 등록되는 상품은 이미 지금 색으로 구워진다 — 두 번 고치지 않는다.
        let normalized = try #require(
            MirrorThumbnailNormalizer.normalized(png: try fixture("legacy-mirror-preview.png"))
        )
        #expect(MirrorThumbnailNormalizer.normalized(png: normalized) == nil)
    }
}

@Suite("출처가 달라도 같은 정책")
struct ThumbnailBackgroundPolicyTests {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return codeWithoutComments(
            try String(contentsOf: root.appending(path: path), encoding: .utf8)
        )
    }

    @Test("배경 색은 한 곳에서만 정해진다")
    func oneAuthorityForTheColour() throws {
        #expect(MirrorRenderer.glass == PaperTheme.thumbnailGlass)
        let normalizer = try source("ggumirror/Store/MirrorThumbnailNormalizer.swift")
        // 새 hex를 하드코딩하지 않는다.
        #expect(normalizer.contains("PaperTheme.thumbnailGlass"))
        #expect(!normalizer.contains("0xEE"))
    }

    @Test("두 미리보기 경로가 모두 지난다")
    func bothPreviewCachesAreNormalized() throws {
        let store = try source("ggumirror/Store/MarketplaceStore.swift")
        // 공개 카드와 `내 판매`가 같은 처리를 거친다.
        #expect(store.components(separatedBy: "lightenedIfMirror(").count - 1 >= 3)
    }

    @Test("스티커에는 적용하지 않는다")
    func stickersAreSkipped() throws {
        let store = try source("ggumirror/Store/MarketplaceStore.swift")
        #expect(store.contains("ListingPreviewStyle.isSticker"))
    }

    @Test("카메라 자리는 확정 geometry에서 온다")
    func openingComesFromSharedGeometry() throws {
        let normalizer = try source("ggumirror/Store/MirrorThumbnailNormalizer.swift")
        #expect(normalizer.contains("MirrorFrameInsets.standard.mirrorArea"))
        // 좌표를 손으로 적지 않는다.
        for guessed in ["108", "180", "220", "1080", "2340"] {
            #expect(!normalizer.contains(guessed), "geometry를 손으로 적었다: \(guessed)")
        }
    }

    @Test("실제 카메라와 저장되는 사진은 건드리지 않는다")
    func liveCameraAndCaptureUntouched() throws {
        for path in ["ggumirror/Mirror/CameraPreviewView.swift",
                     "ggumirror/Mirror/MirrorCamera.swift",
                     "ggumirror/Mirror/MirrorCapture.swift"] {
            let code = try source(path)
            #expect(!code.contains("MirrorThumbnailNormalizer"), "\(path)")
            #expect(!code.contains("thumbnailGlass"), "\(path)")
        }
        // 실제 카메라는 카메라 자리를 비운다.
        #expect(try source("ggumirror/Shared/MirrorRenderer.swift")
            .contains("mirrorAreaFill: Color? = glass"))
    }
}
