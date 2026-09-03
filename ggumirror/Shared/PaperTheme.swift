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
    static let paper = Color(red: 0.988, green: 0.984, blue: 0.965)         // #FCFBF6
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

    /// **목록 썸네일의 카메라 자리.** 실제 카메라가 없는 정지 그림에서만 쓴다.
    ///
    /// 예전에는 어두운 유리색이라 검은 글씨·검은 그림·어두운 장식이 그 위에서
    /// 보이지 않았다. 종이 계열의 밝은 중간톤이라 검은 요소가 드러난다.
    /// **실제 Mirror Camera와 저장되는 사진에는 쓰지 않는다** — 거기는 진짜 카메라다.
    static let thumbnailGlass = Color(red: 0.933, green: 0.925, blue: 0.898)  // #EEECE5
}

// MARK: - Typography

/// 앱 UI의 글씨. **개구(Gaegu) 하나로 고정된 브랜드 서체**다.
/// 거울에 넣는 장식 텍스트(`TextFontStyle`)와는 별개다 — 사용자가 그걸 바꿔도 UI는 그대로다.
///
/// 화면에서 `.font(.system(...))`을 직접 쓰지 않는다. 여기 semantic 이름만 쓴다.
/// 모든 값이 `relativeTo`를 갖고 있어 Dynamic Type을 그대로 따라간다.
/// 폰트를 못 찾으면 같은 semantic의 시스템 한글 폰트로 떨어진다.
enum InkFont {
    /// 화면 최상단 큰 제목. "상점", "내 거울".
    static var pageTitle: Font { BrandFont.scaled(BrandFont.bold, 34, .largeTitle, fallback: .bold) }
    /// 그다음 크기의 제목. 상세 화면 이름.
    static var title: Font { BrandFont.scaled(BrandFont.bold, 28, .title, fallback: .bold) }
    /// 카드 / 시트 제목.
    static var cardTitle: Font { BrandFont.scaled(BrandFont.bold, 22, .title3, fallback: .semibold) }
    /// 구역 이름. 목록 머리말.
    static var sectionTitle: Font { BrandFont.scaled(BrandFont.bold, 19, .headline, fallback: .semibold) }
    /// 본문.
    static var body: Font { BrandFont.scaled(BrandFont.regular, 19, .body) }
    /// 버튼 글씨. 본문보다 살짝 굵게.
    static var button: Font { BrandFont.scaled(BrandFont.bold, 19, .body, fallback: .semibold) }
    /// 보조 설명.
    static var secondary: Font { BrandFont.scaled(BrandFont.regular, 17, .subheadline) }
    /// 작은 라벨 / 캡션.
    static var caption: Font { BrandFont.scaled(BrandFont.regular, 15, .caption) }
    /// 탭바처럼 아주 좁은 자리.
    static var tab: Font { BrandFont.scaled(BrandFont.regular, 14, .caption2) }
    /// 가격 · 개수처럼 자리 맞춤이 필요한 숫자.
    static var numeric: Font { BrandFont.scaled(BrandFont.bold, 18, .body, fallback: .semibold) }
    /// 아주 옅은 보조 표현.
    static var whisper: Font { BrandFont.scaled(BrandFont.light, 16, .footnote, fallback: .light) }
}

// MARK: - Ink line

/// 잉크 선 굵기. 화면마다 1.4 / 1.6 / 1.9를 직접 적지 않는다.
/// 손그림 느낌은 굵기를 흔들어서가 아니라 **모양**으로 낸다 — 굵기는 안정적이어야 한다.
enum InkLine {
    /// 구분선 · 작은 아이콘 테두리.
    static let thin: CGFloat = 1.3
    /// 기본. 버튼 · 칩 · 입력.
    static let regular: CGFloat = 1.6
    /// 카드 · 시트처럼 면을 크게 잡는 곳.
    static let emphasis: CGFloat = 1.9
}

// MARK: - Shape

/// 자주 쓰는 모서리 조합. 값을 화면마다 다시 적지 않는다.
/// 네 모서리를 일부러 조금씩 다르게 둔다 — "손으로 상자를 그렸다" 정도의 어긋남이고,
/// **매번 같은 값**이라 다시 그려도 모양이 흔들리지 않는다.
enum InkCorner {
    /// 카드 · 시트처럼 큰 면.
    static var card: UnevenRoundedRectangle { .ink(20, 24, 25, 19) }
    /// 버튼 · 입력처럼 손이 닿는 것.
    static var control: UnevenRoundedRectangle { .ink(16, 13, 17, 12) }
    /// 칩 · 작은 라벨.
    static var chip: UnevenRoundedRectangle { .ink(15, 12, 16, 13) }
    /// 아이콘 배지처럼 작은 정사각.
    static var badge: UnevenRoundedRectangle { .ink(13, 16, 12, 15) }
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

}

// 시스템 시트용 `paperSheet()`는 없앴다. 앱 안의 시트 / 다이얼로그는 전부
// `inkBottomSheet` / `inkDialog`가 띄우고, 종이 면은 그 안에서 그린다 (Shared/InkModal.swift).
// 아래 safe area까지 종이가 닿게 하는 일도 거기서 한 번만 한다.
