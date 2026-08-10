//
//  PaperTheme.swift
//  ggumirror
//
//  Clean Pen Sketch의 바탕 — 따뜻한 종이 + 검은 잉크.
//  카메라 화면에는 적용하지 않는다(DESIGN.md).
//

import SwiftUI

// MARK: - Color

enum PaperTheme {
    /// 일반 앱 화면의 기본 배경.
    static let paper = Color(red: 0.976, green: 0.973, blue: 0.957)         // #F9F8F4
    /// 본문 텍스트와 모든 잉크 라인.
    static let ink = Color(red: 0.102, green: 0.102, blue: 0.102)           // #1A1A1A
    /// 보조 설명 텍스트.
    static let secondaryInk = Color(red: 0.341, green: 0.329, blue: 0.306)  // #57544E
    /// 카드 / 탭바처럼 배경 위로 살짝 올라온 면.
    static let subtleSurface = Color(red: 0.988, green: 0.984, blue: 0.973) // #FCFBF8
    /// 구분선. 잉크 라인 감성을 유지하되 본문보다 약하게.
    static let separator = Color(red: 0.102, green: 0.102, blue: 0.102).opacity(0.55)
    /// 아직 쓸 수 없는 요소.
    static let disabled = Color(red: 0.659, green: 0.643, blue: 0.608)      // #A8A49B
    /// 눌린 상태의 종이 면.
    static let pressed = Color(red: 0.969, green: 0.957, blue: 0.929)       // #F7F4ED
}

// MARK: - Typography

/// 한국어 가독성 우선. 손글씨 폰트를 본문에 강제하지 않고 시스템 한글 폰트를 쓴다.
/// 전부 text style 기반이라 Dynamic Type을 그대로 따라간다.
enum InkFont {
    static let pageTitle = Font.system(.largeTitle, weight: .bold)
    static let cardTitle = Font.system(.title3, weight: .semibold)
    static let body = Font.system(.body)
    static let secondary = Font.system(.subheadline)
    static let caption = Font.system(.caption)
}

// MARK: - Shape

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

// MARK: - Background

/// 은은한 종이 질감. 결정적 speckle이라 매번 같은 결이 나온다.
/// SVG filter / WebView 없이 Canvas로만 그린다.
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
                // 글자 가독성을 해치지 않을 만큼만.
                context.fill(
                    Path(ellipseIn: dot),
                    with: .color(PaperTheme.ink.opacity(0.03 + random() * 0.04))
                )
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

extension View {
    /// 일반 앱 화면의 기본 배경. 화면마다 다시 구현하지 않는다.
    func paperBackground(_ color: Color = PaperTheme.paper) -> some View {
        background {
            PaperBackground(color: color).ignoresSafeArea()
        }
    }

    /// 시트 배경. **표시 표면 전체**를 덮는다 — 좌·우·아래 safe area까지.
    ///
    /// 배경 뷰가 safe area 안쪽에만 그려지면 홈 인디케이터 쪽에 종이가 닿지 않아
    /// 아래 모서리에 빈 자리가 생긴다. 그래서 여기서 한 번만 `ignoresSafeArea`를 건다 —
    /// 시트마다 따로 padding을 덧대지 않는다.
    func paperSheet() -> some View {
        presentationBackground {
            PaperBackground().ignoresSafeArea()
        }
    }
}
