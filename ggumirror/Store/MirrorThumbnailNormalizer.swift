//
//  MirrorThumbnailNormalizer.swift
//  ggumirror
//
//  상점에서 받은 거울 미리보기의 **카메라 자리를 밝게 되돌린다.**
//
//  내장 템플릿은 카드가 모델을 직접 그리므로 지금 정책(`MirrorRenderer.glass`)을 따른다.
//  사용자 상품은 **등록 시점에 구워진 PNG**를 그대로 보여 준다 — 그때의 색이 박혀 있다.
//  그래서 어두운 유리색으로 굽힌 예전 상품은 카드에서 검게 보였고,
//  **검은 글씨와 검은 그림이 그 위에서 보이지 않았다.**
//
//  고치는 방법은 하나뿐이다: 이미 구워진 그림에서 그 색만 되돌린다.
//  - **정확히 그 색인 픽셀만** 바꾼다. 사용자의 글씨 · 그림 · 스티커 색은 손대지 않는다
//  - **카메라 자리 안에서만** 바꾼다(거울 geometry는 확정값이다).
//    프레임 밴드와 그 위의 장식은 후보에서 아예 빠진다
//  - 바뀐 것이 없으면 원본을 그대로 돌려준다 — 새로 등록된 상품은 이미 밝다
//
//  GCS의 기존 object를 다시 쓰지 않는다. 재등록을 요구하지도 않는다 —
//  이미 팔고 있는 사람의 상품이 앱 업데이트 때문에 검게 남으면 안 된다.
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum MirrorThumbnailNormalizer {
    /// 예전 정지 미리보기의 카메라 자리 색(`#212025`).
    ///
    /// 그때 `MirrorRenderer.glass`가 이 값이었다. 지금은 밝은 종이색이라
    /// **새로 구워지는 그림에는 이 색이 없다.**
    static let legacyGlass: (r: UInt8, g: UInt8, b: UInt8) = (33, 32, 37)

    /// 카메라 자리를 **투명하게 비운** PNG. 실제 카메라 위에 얹기 위한 것이다.
    ///
    /// `내 거울로 미리보기`가 쓴다. 납작하게 구워진 그림에서 카메라 자리만 도려내면
    /// **장식은 그대로 남고** 그 아래로 진짜 카메라가 비친다 —
    /// 원본 manifest나 asset을 내려받지 않고도 "내 거울에 얹으면 이렇다"를 보여 준다.
    ///
    /// 도려내지 못하면 `nil`이다(그때는 미리보기를 열지 않는다).
    static func cameraOpeningRemoved(png: Data) -> Data? {
        recolored(png: png) { _ in (0, 0, 0, 0) }
    }

    /// 카메라 자리를 지금 정책 색으로 되돌린 PNG. 바꿀 것이 없으면 `nil`이다.
    ///
    /// 거울이 아닌 상품(스티커)에는 부르지 않는다 — 카메라 자리가 없다.
    static func normalized(png: Data) -> Data? {
        let target = target()
        return recolored(png: png) { _ in (target.r, target.g, target.b, 255) }
    }

    /// 카메라 자리의 **바탕색 픽셀만** 다른 값으로 바꾼다.
    ///
    /// 바탕색은 그때그때 구워진 값이라 하나로 정해져 있지 않다(예전 어두운 유리색,
    /// 지금 밝은 종이색). 그래서 **카메라 자리에서 가장 많이 나온 불투명 색**을
    /// 바탕으로 본다 — 장식이 그 자리를 전부 덮는 일은 없다.
    private static func recolored(
        png: Data, to replacement: ((UInt8, UInt8, UInt8)) -> (UInt8, UInt8, UInt8, UInt8)
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let area = MirrorFrameInsets.standard.mirrorArea
        // 카메라 자리만 훑는다. 프레임 밴드와 그 위 장식은 건드릴 수 없다.
        let minX = max(0, Int((area.x * Double(width)).rounded(.down)))
        let maxX = min(width, Int(((area.x + area.width) * Double(width)).rounded(.up)))
        let minY = max(0, Int((area.y * Double(height)).rounded(.down)))
        let maxY = min(height, Int(((area.y + area.height) * Double(height)).rounded(.up)))
        guard minX < maxX, minY < maxY else { return nil }

        guard let background = dominantOpaqueColour(
            pixels, width: width, minX: minX, maxX: maxX, minY: minY, maxY: maxY
        ) else { return nil }

        let new = replacement(background)
        // 이미 그 값이면 할 일이 없다.
        if new == (background.0, background.1, background.2, 255) { return nil }

        var changed = false
        for y in minY..<maxY {
            let row = y * width * 4
            for x in minX..<maxX {
                let i = row + x * 4
                // 불투명하고 **정확히** 바탕색일 때만. 반투명 경계는 손대지 않는다.
                guard pixels[i + 3] == 255,
                      pixels[i] == background.0,
                      pixels[i + 1] == background.1,
                      pixels[i + 2] == background.2
                else { continue }
                (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]) = new
                changed = true
            }
        }
        guard changed, let output = context.makeImage() else { return nil }
        return encoded(output)
    }

    /// 카메라 자리에서 가장 많이 나온 불투명 색 = 바탕.
    ///
    /// 굽힌 시점마다 값이 달라서(예전 어두운 유리색 · 지금 밝은 종이색) 하나로
    /// 정해 두지 않는다. 장식이 카메라 자리를 **전부** 덮는 일은 없으므로
    /// 최빈색이 곧 바탕이다.
    private static func dominantOpaqueColour(
        _ pixels: [UInt8], width: Int,
        minX: Int, maxX: Int, minY: Int, maxY: Int
    ) -> (UInt8, UInt8, UInt8)? {
        var tally: [UInt32: Int] = [:]
        // 전부 세지 않는다 — 성긴 표본으로 충분하고 훨씬 빠르다.
        let step = max(1, (maxX - minX) / 64)
        for y in stride(from: minY, to: maxY, by: step) {
            let row = y * width * 4
            for x in stride(from: minX, to: maxX, by: step) {
                let i = row + x * 4
                guard pixels[i + 3] == 255 else { continue }
                let key = UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2])
                tally[key, default: 0] += 1
            }
        }
        guard let (key, count) = tally.max(by: { $0.value < $1.value }), count > 0 else { return nil }
        return (UInt8(key >> 16 & 255), UInt8(key >> 8 & 255), UInt8(key & 255))
    }

    /// 지금 정책 색을 8bit로. **새 색을 여기서 고르지 않는다** —
    /// 정지 썸네일의 카메라 자리는 `PaperTheme.thumbnailGlass` 하나가 정한다.
    static func target() -> (r: UInt8, g: UInt8, b: UInt8) {
        let resolved = PaperTheme.thumbnailGlass.resolve(in: .init())
        func byte(_ value: Float) -> UInt8 {
            UInt8(max(0, min(255, (value * 255).rounded())))
        }
        return (byte(resolved.red), byte(resolved.green), byte(resolved.blue))
    }

    private static func encoded(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
