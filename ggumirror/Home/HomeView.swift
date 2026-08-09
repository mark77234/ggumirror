//
//  HomeView.swift
//  ggumirror
//
//  Main Tab 컨테이너 + 홈 탭.
//  홈에는 보유 거울 개수 / 설정 / 거울 보기 / 거울 꾸미기 4개만 둔다.
//

import SwiftUI

struct HomeView: View {
    var library: MirrorLibrary
    var onOpenMirror: () -> Void
    var onEditMirror: (MyMirror) -> Void

    @State private var tab: MainTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            switch tab {
            case .home:
                homeTab
            case .store:
                StoreView()
            case .mine:
                MyMirrorsView(library: library, onEditMirror: onEditMirror)
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
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .settings: SettingsView()
                case .profile: ProfileView()
                case .privacy: ComingSoonView(title: "개인정보 처리방침", detail: "곧 내용을 채울게요.")
                case .terms: ComingSoonView(title: "이용약관", detail: "곧 내용을 채울게요.")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(PaperTheme.ink)
    }

    private var header: some View {
        HStack(alignment: .center) {
            InkChip(icon: "oval.portrait", text: "거울 \(library.mirrors.count)개", tilt: -0.35)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("보유 거울 \(library.mirrors.count)개")

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
                // 거울 선택 화면 없이 지금 쓰는 거울 Editor로 바로 들어간다.
                action: { onEditMirror(library.currentMirror) }
            )
        }
    }
}

#Preview {
    HomeView(library: MirrorLibrary(), onOpenMirror: {}, onEditMirror: { _ in })
}
