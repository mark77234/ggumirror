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

    /// 카메라 자리를 지금 정책 색으로 되돌린 PNG. 바꿀 것이 없으면 `nil`이다.
    ///
    /// 거울이 아닌 상품(스티커)에는 부르지 않는다 — 카메라 자리가 없다.
    static func normalized(png: Data) -> Data? {
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

        let replacement = target()
        let area = MirrorFrameInsets.standard.mirrorArea
        // 카메라 자리만 훑는다. 프레임 밴드와 그 위 장식은 건드릴 수 없다.
        let minX = Int((area.x * Double(width)).rounded(.down))
        let maxX = Int(((area.x + area.width) * Double(width)).rounded(.up))
        let minY = Int((area.y * Double(height)).rounded(.down))
        let maxY = Int(((area.y + area.height) * Double(height)).rounded(.up))

        var changed = false
        for y in max(0, minY)..<min(height, maxY) {
            let row = y * width * 4
            for x in max(0, minX)..<min(width, maxX) {
                let i = row + x * 4
                // 불투명하고 **정확히** 그 색일 때만. 반투명 경계는 손대지 않는다.
                guard pixels[i + 3] == 255,
                      pixels[i] == legacyGlass.r,
                      pixels[i + 1] == legacyGlass.g,
                      pixels[i + 2] == legacyGlass.b
                else { continue }
                pixels[i] = replacement.r
                pixels[i + 1] = replacement.g
                pixels[i + 2] = replacement.b
                changed = true
            }
        }
        guard changed, let output = context.makeImage() else { return nil }
        return encoded(output)
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
