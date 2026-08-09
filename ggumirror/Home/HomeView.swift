//
//  HomeView.swift
//  ggumirror
//
//  Home. 보유 거울 개수 / 설정 / 거울 보기 / 거울 꾸미기 4개만 둔다.
//

import SwiftUI

struct HomeView: View {
    var onOpenMirror: () -> Void

    /// 아직 persistence가 없어 기본 거울 개수를 임시로 쓴다.
    /// White / Black / Cream / Soft Pink / Lavender / Sky / Mint / Gray
    private static let temporaryMirrorCount = 8

    @State private var tab: MainTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            switch tab {
            case .home:
                homeTab
            case .store:
                ComingSoonView(title: "상점", detail: "곧 다른 사람이 만든 거울을 둘러볼 수 있어요.")
            case .mine:
                ComingSoonView(title: "내 거울", detail: "내가 만들고 꾸민 거울이 여기에 모여요.")
            }

            InkTabBar(selection: $tab)
        }
        .paperBackground()
    }

    // MARK: - 홈 탭

    private var homeTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    header
                    actions
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, InkTabBar.reservedHeight + 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(PaperTheme.ink)
    }

    private var header: some View {
        HStack(alignment: .center) {
            InkChip(icon: "oval.portrait", text: "거울 \(Self.temporaryMirrorCount)개", tilt: -0.35)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("보유 거울 \(Self.temporaryMirrorCount)개")

            Spacer(minLength: 12)

            NavigationLink(value: SettingsRoute.settings) {
                Image(systemName: "gearshape")
                    .font(.system(.title3))
                    .foregroundStyle(PaperTheme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(InkPressStyle())
            .accessibilityLabel("설정")
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            InkActionButton(
                icon: "iphone",
                title: "거울 보기",
                subtitle: "카메라를 거울처럼 사용",
                tilt: -0.22,
                action: onOpenMirror
            )
            InkActionButton(
                icon: "pencil",
                title: "거울 꾸미기",
                subtitle: "지금 쓰는 거울을 바로 편집",
                tilt: 0.26,
                action: {}   // Editor는 Phase 3 — 여기서는 UI만 둔다.
            )
        }
    }
}

private enum SettingsRoute: Hashable {
    case settings
}

#Preview {
    HomeView(onOpenMirror: {})
}
