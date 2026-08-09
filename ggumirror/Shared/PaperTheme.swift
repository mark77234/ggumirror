//
//  PaperTheme.swift
//  ggumirror
//
//  Clean Pen Sketch — 따뜻한 종이 배경 + 검은 잉크 라인.
//  카메라 영상 위에는 쓰지 않는다(DESIGN.md).
//

import SwiftUI

enum PaperTheme {
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let paper = Color(red: 0.976, green: 0.973, blue: 0.957)     // #F9F8F4
    static let raisedPaper = Color(red: 0.988, green: 0.984, blue: 0.973) // #FCFBF8
    static let subtitle = Color(red: 0.341, green: 0.329, blue: 0.306)  // #57544E
    static let muted = Color(red: 0.431, green: 0.416, blue: 0.384)     // #6E6A62
    static let pressed = Color(red: 0.969, green: 0.957, blue: 0.929)   // #F7F4ED
}

/// 손으로 그린 듯 네 모서리 반지름이 조금씩 다른 사각형.
extension UnevenRoundedRectangle {
    static func ink(
        _ topLeading: CGFloat,
        _ topTrailing: CGFloat,
        _ bottomTrailing: CGFloat,
        _ bottomLeading: CGFloat
    ) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topLeading,
            bottomLeadingRadius: bottomLeading,
            bottomTrailingRadius: bottomTrailing,
            topTrailingRadius: topTrailing
        )
    }
}

/// 은은한 종이 질감. 결정적 speckle이라 매번 같은 결이 나온다.
struct PaperBackground: View {
    var color: Color = PaperTheme.paper

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))

            var seed: UInt64 = 20_260_809
            func random() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 33) / Double(UInt32.max)
            }

            let count = Int(size.width * size.height / 700)
            for _ in 0..<count {
                let radius = 0.4 + random() * 0.9
                let dot = CGRect(
                    x: random() * size.width,
                    y: random() * size.height,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(
                    Path(ellipseIn: dot),
                    with: .color(PaperTheme.ink.opacity(0.03 + random() * 0.05))
                )
            }
        }
        .drawingGroup()
    }
}
