//
//  InkComponents.swift
//  ggumirror
//
//  Clean Pen Sketch 공통 component.
//  손그림 느낌은 시각 레이어(테두리 기울임 · 비대칭 모서리)에만 준다.
//  레이아웃과 hit target은 항상 반듯하게 유지한다.
//

import SwiftUI

// MARK: - Icon container

/// SF Symbol을 잉크 테두리 안에 담아 종이 위에서 겉돌지 않게 한다.
struct InkIconBadge: View {
    let systemName: String
    var size: CGFloat = 44
    var tint: Color = PaperTheme.ink

    /// 큰 글씨 설정에서도 아이콘이 텍스트와 함께 커지도록.
    @ScaledMetric(relativeTo: .title3) private var scale = 1

    private var side: CGFloat { size * scale }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: side * 0.45, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .overlay(
                UnevenRoundedRectangle.ink(15, 12, 13, 16)
                    .stroke(tint, lineWidth: 1.6)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Surface

/// 잉크 테두리를 두른 종이 면. 다른 ink component의 바탕이 된다.
struct InkCard<Content: View>: View {
    /// 손그림 느낌을 위한 아주 미세한 기울임. 시각 레이어에만 적용된다.
    var tilt: Double = 0
    var lineWidth: CGFloat = 1.9
    var padding = EdgeInsets(top: 20, leading: 18, bottom: 20, trailing: 18)
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                InkOutline(lineWidth: lineWidth)
                    .rotationEffect(.degrees(tilt))
            }
    }
}

private struct InkOutline: View {
    var lineWidth: CGFloat

    var body: some View {
        let shape = UnevenRoundedRectangle.ink(20, 24, 25, 19)
        shape
            .fill(PaperTheme.subtleSurface)
            .overlay(shape.stroke(PaperTheme.ink, lineWidth: lineWidth))
    }
}

// MARK: - Action

/// Home의 주요 액션 줄. 아이콘 + 제목 + 설명 + chevron.
struct InkActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    var tilt: Double = 0
    var isEnabled = true
    let action: () -> Void

    @Environment(\.isEnabled) private var environmentEnabled

    private var foreground: Color { isEnabled ? PaperTheme.ink : PaperTheme.disabled }

    var body: some View {
        Button(action: action) {
            InkCard(tilt: tilt) {
                HStack(spacing: 14) {
                    InkIconBadge(systemName: icon, tint: foreground)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(InkFont.cardTitle)
                            .foregroundStyle(foreground)
                        Text(subtitle)
                            .font(InkFont.secondary)
                            .foregroundStyle(isEnabled ? PaperTheme.secondaryInk : PaperTheme.disabled)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(foreground)
                        .accessibilityHidden(true)
                }
            }
            // 기울인 테두리가 잘리지 않도록 여유를 준다.
            .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

/// 눌렀을 때 종이가 살짝 눌리는 정도의 피드백. 그림자 / 그라디언트 없음.
struct InkPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.62 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Chip

/// "거울 8개"처럼 짧은 정보를 담는 잉크 라벨.
struct InkChip: View {
    let icon: String
    let text: String
    var tilt: Double = 0

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(InkFont.secondary)
            Text(text)
                .font(InkFont.cardTitle)
        }
        .foregroundStyle(PaperTheme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background {
            UnevenRoundedRectangle.ink(17, 14, 18, 13)
                .stroke(PaperTheme.ink, lineWidth: 1.7)
                .rotationEffect(.degrees(tilt))
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        InkChip(icon: "oval.portrait", text: "거울 8개", tilt: -0.35)
        InkActionButton(
            icon: "iphone",
            title: "거울 보기",
            subtitle: "카메라를 거울처럼 사용",
            tilt: -0.22,
            action: {}
        )
        InkActionButton(
            icon: "pencil",
            title: "거울 꾸미기",
            subtitle: "지금 쓰는 거울을 바로 편집",
            tilt: 0.26,
            action: {}
        )
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .paperBackground()
}
