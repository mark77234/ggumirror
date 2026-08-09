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

    var icon: String {
        switch self {
        case .home: "house"
        case .store: "bag"
        case .mine: "rectangle.split.2x1"
        }
    }
}

struct InkTabBar: View {
    @Binding var selection: MainTab

    /// 콘텐츠가 탭바에 가리지 않도록 스크롤 뷰가 비워둬야 하는 높이.
    static let reservedHeight: CGFloat = 108

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
            Image(systemName: tab.icon)
                .font(InkFont.body)
            Text(tab.title)
                .font(InkFont.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        // 선택 상태는 색 대비로만 구분한다. 그라디언트 없음.
        .foregroundStyle(isSelected ? PaperTheme.subtleSurface : PaperTheme.ink)
        .opacity(isSelected ? 1 : 0.62)
        .frame(maxWidth: .infinity)
        .frame(minHeight: max(itemHeight, 44))
        .background {
            UnevenRoundedRectangle.ink(19, 22, 23, 18)
                .fill(isSelected ? PaperTheme.ink : .clear)
        }
        .contentShape(.rect)
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
