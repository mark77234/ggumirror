//
//  HomeView.swift
//  ggumirror
//
//  Main Tab 컨테이너 + 홈 탭.
//  홈은 스크롤 없이 한 화면에 들어온다: 조각 / 설정 · 현재 거울 · 두 액션 · 탭바.
//

import SwiftUI

struct HomeView: View {
    var library: MirrorLibrary
    var onOpenMirror: () -> Void
    var onEditMirror: (MyMirror) -> Void

    @State private var tab: MainTab = .home
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack(alignment: .bottom) {
            switch tab {
            case .home:
                homeTab
            case .store:
                StoreView(library: library)
            case .mine:
                MyMirrorsView(
                    library: library,
                    onEditMirror: onEditMirror,
                    onBrowseStore: { tab = .store }
                )
            }

            InkTabBar(selection: $tab)
        }
        .paperBackground()
    }

    // MARK: - 홈 탭

    private var homeTab: some View {
        NavigationStack {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    // 큰 글씨에서는 한 화면에 물리적으로 담기지 않아 접근성을 우선한다.
                    // 미리보기 높이를 제한해 두 액션이 바로 아래에 오게 한다.
                    ScrollView { content(previewMaxHeight: 300) }
                        .scrollIndicators(.hidden)
                } else {
                    content(previewMaxHeight: nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, InkTabBar.reservedHeight)
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

    private func content(previewMaxHeight: CGFloat?) -> some View {
        VStack(spacing: 14) {
            header

            // 남는 공간을 미리보기가 차지한다. 비율은 다른 화면과 같은 9:19.5.
            currentMirror
                .frame(maxWidth: .infinity, maxHeight: previewMaxHeight ?? .infinity)

            actions
        }
    }

    private var header: some View {
        HStack {
            ShardAmount(
                amount: ShardWallet.temporaryBalance,
                font: InkFont.cardTitle,
                iconSize: 17
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                UnevenRoundedRectangle.ink(17, 14, 18, 13)
                    .stroke(PaperTheme.ink, lineWidth: 1.7)
                    .rotationEffect(.degrees(-0.35))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("보유 \(ShardWallet.temporaryBalance) 조각")

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
        .padding(.vertical, 2)
    }

    private var currentMirror: some View {
        let mirror = library.currentMirror
        return VStack(spacing: 8) {
            MirrorPreview(style: mirror.style, strokes: mirror.strokes)
            Text(mirror.name)
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("지금 쓰는 거울, \(mirror.name)")
    }

    private var actions: some View {
        VStack(spacing: 10) {
            InkActionButton(
                glyph: .mirror,
                title: "거울 보기",
                subtitle: "카메라를 거울처럼 사용",
                tilt: -0.22,
                action: onOpenMirror
            )
            InkActionButton(
                glyph: .system("pencil"),
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
