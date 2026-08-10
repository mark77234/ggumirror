//
//  PaperSurfaceTests.swift
//  ggumirrorTests
//
//  종이 배경이 **모서리까지** 칠해지는지. 시트 아래쪽에 빈 자리가 생기던 문제의 회귀 방지다.
//
//  시트 표시 표면 자체는 단위 테스트로 띄울 수 없으므로,
//  그 위에 올라가는 배경 뷰가 자기 영역을 남김없이 채우는지를 확인한다.
//  (safe area까지 넓히는 일은 `paperSheet()` 한 곳에서만 한다.)
//

import Testing
import SwiftUI
import UIKit
@testable import ggumirror

@MainActor
struct PaperSurfaceTests {

    private func render(_ view: some View, size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.cgImage
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.draw(
            image,
            in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height)
        )
        return (data[0], data[1], data[2], data[3])
    }

    @Test("종이 배경은 네 모서리까지 빈틈 없이 칠한다")
    func paperFillsEveryCorner() throws {
        let size = CGSize(width: 320, height: 480)
        let image = try #require(render(PaperBackground(), size: size))

        let corners = [
            (0, 0), (image.width - 1, 0),
            (0, image.height - 1), (image.width - 1, image.height - 1)   // 좌하단 포함
        ]
        for (x, y) in corners {
            let point = pixel(image, x: x, y: y)
            #expect(point.alpha > 250, "모서리 (\(x), \(y))가 비어 있다")
            #expect(point.red > 200)     // 종이색
        }
    }

    @Test("종이 배경은 화면 비율이 달라도 아래 가장자리를 채운다")
    func paperFillsBottomEdgeAtAnySize() throws {
        for size in [CGSize(width: 390, height: 260), CGSize(width: 320, height: 700)] {
            let image = try #require(render(PaperBackground(), size: size))
            for x in stride(from: 0, to: image.width, by: max(image.width / 12, 1)) {
                #expect(pixel(image, x: x, y: image.height - 1).alpha > 250)
            }
        }
    }
}
