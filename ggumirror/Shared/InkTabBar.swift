//
//  InkTabBar.swift
//  ggumirror
//
//  Main Tab: 홈 / 상점 / 내 거울.
//  Mirror는 immersive full-screen이라 이 탭바를 쓰지 않는다.
//

import SwiftUI

enum MainTab: CaseIterable {
    case home, store, mine

    var title: String {
        switch self {
        case .home: "홈"
        case .store: "상점"
        case .mine: "내 거울"
        }
    }

    /// 제품 아이콘 셋은 손그림 두들을 쓴다 (DoodleProductIcons.swift).
    var productIcon: DoodleProductIcon {
        switch self {
        case .home: .home
        case .store: .store
        case .mine: .mirror
        }
    }
}

struct InkTabBar: View {
    @Binding var selection: MainTab

    /// 콘텐츠가 탭바에 가리지 않도록 스크롤 뷰가 비워둬야 하는 높이.
    static let reservedHeight: CGFloat = 108

    /// 막대 위에 남겨 두는 숨 쉴 자리. 마지막 줄이 막대에 딱 붙지 않게 한다.
    static let contentBreathingRoom: CGFloat = 24

    @ScaledMetric(relativeTo: .caption) private var itemHeight: CGFloat = 52

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    item(for: tab)
                }
                .buttonStyle(InkPressStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(7)
        .background {
            let shape = UnevenRoundedRectangle.ink(25, 27, 28, 24)
            shape
                .fill(PaperTheme.subtleSurface)
                .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.7))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func item(for tab: MainTab) -> some View {
        let isSelected = selection == tab
        return VStack(spacing: 3) {
            DoodleProductIconView(icon: tab.productIcon, size: 22)
            Text(tab.title)
                .font(InkFont.tab)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // 선택 표시는 큰 알약이 아니라 손으로 그은 짧은 밑줄이다.
            InkUnderline()
                .stroke(PaperTheme.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 26, height: 4)
                .opacity(isSelected ? 1 : 0)
        }
        .foregroundStyle(PaperTheme.ink)
        .opacity(isSelected ? 1 : 0.5)
        .frame(maxWidth: .infinity)
        .frame(minHeight: max(itemHeight, 44))
        .contentShape(.rect)
    }
}

/// 손으로 그은 듯 살짝 휜 짧은 밑줄. 매번 같은 모양이다.
struct InkUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.18))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.12),
            control: CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.6)
        )
        return path
    }
}

#Preview {
    @Previewable @State var tab: MainTab = .home
    return VStack {
        Spacer()
        InkTabBar(selection: $tab)
    }
    .paperBackground()
}


// MARK: - 스크롤 화면의 아래 여백

extension View {
    /// 탭 막대에 가리지 않도록 스크롤 내용 **아래를 띄운다.**
    ///
    /// 막대는 `ZStack`의 형제라 화면 위에 겹쳐 그려진다 — 홈 탭 자신은 아래 여백을
    /// 갖고 있지만, 거기서 밀어 올린 화면(설정 · 프로필 · 알림 · 상점 관리)은
    /// 그 여백을 물려받지 않는다. 그래서 마지막 줄이 막대 밑으로 들어갔다.
    ///
    /// 화면마다 숫자를 적지 않는다. 막대 높이가 바뀌면 여기 한 곳만 바뀐다.
    func inkTabBarSafeContent() -> some View {
        contentMargins(
            .bottom,
            InkTabBar.reservedHeight + InkTabBar.contentBreathingRoom,
            for: .scrollContent
        )
    }
}
