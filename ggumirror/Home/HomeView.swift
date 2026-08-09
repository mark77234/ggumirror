//
//  HomeView.swift
//  ggumirror
//
//  Home. 보유 거울 개수 / 설정 / 거울 보기 / 거울 꾸미기 4개만 둔다.
//

import SwiftUI

struct HomeView: View {
    var onOpenMirror: () -> Void

    /// Phase 1-5에서는 실제 데이터가 없어 기본 거울 개수를 임시로 쓴다.
    /// White / Black / Cream / Soft Pink / Lavender / Sky / Mint / Gray
    private static let temporaryMirrorCount = 8

    @State private var tab: Tab = .home

    private enum Tab: CaseIterable {
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

    var body: some View {
        ZStack(alignment: .bottom) {
            PaperBackground()
                .ignoresSafeArea()

            switch tab {
            case .home: homeTab
            case .store: placeholder("상점", detail: "곧 거울 디자인을 둘러볼 수 있어요.")
            case .mine: placeholder("내 거울", detail: "내가 만든 거울이 여기에 모여요.")
            }

            tabBar
        }
    }

    // MARK: - 홈 탭

    private var homeTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, 44)

                    VStack(spacing: 10) {
                        InkCard(
                            icon: "iphone",
                            title: "거울 보기",
                            subtitle: "카메라를 거울처럼 사용",
                            tilt: -0.22,
                            action: onOpenMirror
                        )
                        InkCard(
                            icon: "pencil",
                            title: "거울 꾸미기",
                            subtitle: "지금 쓰는 거울을 바로 편집",
                            tilt: 0.26,
                            action: {}   // Editor는 아직 범위 밖 — UI만 둔다.
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 132)   // floating tab bar 자리
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.clear)
            .navigationDestination(for: String.self) { _ in SettingsView() }
        }
        .tint(PaperTheme.ink)
    }

    private var header: some View {
        HStack {
            Text("거울 \(Self.temporaryMirrorCount)개")
                .font(.system(size: 17.5, weight: .bold))
                .foregroundStyle(PaperTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .overlay(
                    UnevenRoundedRectangle.ink(17, 14, 18, 13)
                        .stroke(PaperTheme.ink, lineWidth: 1.7)
                )
                .rotationEffect(.degrees(-0.35))

            Spacer()

            NavigationLink(value: "settings") {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(PaperTheme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("설정")
        }
    }

    private func placeholder(_ title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(PaperTheme.ink)
            Text(detail)
                .font(.system(size: 15))
                .foregroundStyle(PaperTheme.muted)
            Text("준비 중이에요")
                .font(.system(size: 13))
                .foregroundStyle(PaperTheme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .overlay(
                    UnevenRoundedRectangle.ink(14, 12, 15, 13)
                        .stroke(PaperTheme.ink.opacity(0.5), lineWidth: 1.4)
                )
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: .regular))
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(tab == item ? PaperTheme.paper : PaperTheme.ink)
                    .opacity(tab == item ? 1 : 0.62)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        UnevenRoundedRectangle.ink(19, 22, 23, 18)
                            .fill(tab == item ? PaperTheme.ink : .clear)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(7)
        .background(
            UnevenRoundedRectangle.ink(25, 27, 28, 24)
                .fill(PaperTheme.raisedPaper)
                .overlay(
                    UnevenRoundedRectangle.ink(25, 27, 28, 24)
                        .stroke(PaperTheme.ink, lineWidth: 1.7)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }
}

/// Home의 잉크 카드. 살짝 기울고 모서리가 고르지 않아 손그림 느낌을 낸다.
private struct InkCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let tilt: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(PaperTheme.ink)
                    .frame(width: 44, height: 44)
                    .overlay(
                        UnevenRoundedRectangle.ink(15, 12, 13, 16)
                            .stroke(PaperTheme.ink, lineWidth: 1.6)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18.5, weight: .semibold))
                        .foregroundStyle(PaperTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(PaperTheme.subtitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PaperTheme.ink)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .overlay(
                UnevenRoundedRectangle.ink(20, 24, 25, 19)
                    .stroke(PaperTheme.ink, lineWidth: 1.9)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(tilt))
    }
}

#Preview {
    HomeView(onOpenMirror: {})
}
