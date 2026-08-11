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
    let glyph: InkGlyph
    var size: CGFloat = 44
    var tint: Color = PaperTheme.ink

    /// 큰 글씨 설정에서도 아이콘이 텍스트와 함께 커지도록.
    @ScaledMetric(relativeTo: .title3) private var scale = 1

    private var side: CGFloat { size * scale }

    var body: some View {
        InkGlyphView(glyph: glyph, size: side * 0.45, tint: tint)
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
    let glyph: InkGlyph
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
                    InkIconBadge(glyph: glyph, tint: foreground)

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
            glyph: .mirror,
            title: "거울 보기",
            subtitle: "카메라를 거울처럼 사용",
            tilt: -0.22,
            action: {}
        )
        InkActionButton(
            glyph: .system("pencil"),
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

// MARK: - 조각 (currency)

// ShardShape / ShardIcon은 Shared/InkProductIcons.swift로 옮겼다 (제품 아이콘 두 개를 한곳에서 본다).

/// "12 조각"처럼 가격 / 잔액을 보여준다. 재화 이름은 항상 "조각".
struct ShardAmount: View {
    let amount: Int
    var font: Font = InkFont.caption
    var iconSize: CGFloat = 13

    var body: some View {
        HStack(spacing: 4) {
            ShardIcon(size: iconSize)
            Text(amount == 0 ? "무료" : "\(amount)")
                .font(font)
                .foregroundStyle(PaperTheme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(amount == 0 ? "무료" : "\(amount) 조각")
    }
}

// MARK: - Filter

/// 가로 스크롤 필터 칩. 상점 / 내 거울에서 함께 쓴다.
struct InkFilterBar<Item: Identifiable & Equatable>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(items) { item in
                    let isSelected = item == selection
                    Button {
                        selection = item
                    } label: {
                        Text(label(item))
                            .font(InkFont.secondary)
                            .foregroundStyle(isSelected ? PaperTheme.subtleSurface : PaperTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(minHeight: 44)
                            .background {
                                let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
                                shape
                                    .fill(isSelected ? PaperTheme.ink : .clear)
                                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.5))
                            }
                            .contentShape(.rect)
                    }
                    .buttonStyle(InkPressStyle())
                    .accessibilityLabel(label(item))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            // stroke가 frame 밖으로 0.75pt 나가므로 상하좌우 여백을 줘서 잘리지 않게 한다.
            .padding(.vertical, 4)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }
}

/// 여러 개를 고를 수 있는 태그 칩. 프로필 태그에 쓴다.
struct InkToggleChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(InkFont.secondary)
                .foregroundStyle(isOn ? PaperTheme.subtleSurface : PaperTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background {
                    let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
                    shape
                        .fill(isOn ? PaperTheme.ink : .clear)
                        .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.5))
                }
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - List row

/// 설정처럼 잉크 구분선으로 나뉜 줄. 오른쪽에 값 / chevron / 스위치를 놓을 수 있다.
struct InkListRow<Trailing: View>: View {
    let title: String
    var showsChevron = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(PaperTheme.ink)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 15)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}

extension InkListRow where Trailing == EmptyView {
    init(title: String, showsChevron: Bool = false) {
        self.init(title: title, showsChevron: showsChevron) { EmptyView() }
    }
}

/// 잉크 구분선.
struct InkSeparator: View {
    var body: some View {
        Rectangle()
            .fill(PaperTheme.separator)
            .frame(height: 1.2)
            .accessibilityHidden(true)
    }
}

// MARK: - Avatar

/// 손그림 느낌의 프로필 자리. 아직 실제 이미지는 없다.
struct InkAvatar: View {
    var size: CGFloat = 56

    var body: some View {
        Image(systemName: "person")
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(PaperTheme.ink)
            .frame(width: size, height: size)
            .background {
                let shape = UnevenRoundedRectangle.ink(size * 0.5, size * 0.46, size * 0.52, size * 0.47)
                shape
                    .fill(PaperTheme.subtleSurface)
                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.7))
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Mirror glyph

// MirrorIcon은 Shared/InkProductIcons.swift로 옮겼다.

/// 아이콘 자리에 SF Symbol이나 거울 아이콘을 같은 방식으로 넣기 위한 최소 추상화.
enum InkGlyph: Hashable {
    case system(String)
    case mirror
}

struct InkGlyphView: View {
    let glyph: InkGlyph
    var size: CGFloat
    var tint: Color = PaperTheme.ink

    var body: some View {
        switch glyph {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(tint)
        case .mirror:
            MirrorIcon(size: size * 1.15, tint: tint)
        }
    }
}

// MARK: - 조각 잔액

/// 실제 ledger가 생기기 전까지 Home / Store가 함께 보는 임시 잔액.
enum ShardWallet {
    static let temporaryBalance = 32
}
