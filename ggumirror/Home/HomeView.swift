//
//  HomeView.swift
//  ggumirror
//
//  Main Tab 컨테이너 + 홈 탭.
//  홈은 스크롤 없이 한 화면에 들어온다: 조각 / 설정 · 현재 거울 · 두 액션 · 탭바.
//

import SwiftUI

struct HomeView: View {
    @Environment(ShardWallet.self) private var shards
    @Environment(AuthSession.self) private var session
    @Environment(RewardedAdController.self) private var rewardedAds
    @Environment(ShardPurchaseController.self) private var shardStore
    var library: MirrorLibrary
    var onOpenMirror: () -> Void
    var onEdit: (RootView.EditorRequest) -> Void

    @State private var tab: MainTab = .home
    /// 조각 충전 sheet. 홈 잔액과 AI 부족 안내가 같은 화면을 연다.
    @State private var isShowingShardStore = false
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
                    // 내 거울에서 고르면 원본을 두고 새 거울로 저장한다.
                    // 꾸미기는 **그 거울을 고치는 것**이다. 복제는 목록의 `복제` 동작이 따로 한다.
                    onEditMirror: { onEdit(.init(design: MirrorDesign(mirror: $0), context: .editCurrent)) },
                    onCreateMirror: { onEdit(.init(design: $0, context: .createNew)) },
                    onBrowseStore: { tab = .store }
                )
            }

            InkTabBar(selection: $tab)
        }
        .paperBackground()
        // 조각 충전. 홈 잔액과 AI 부족 안내가 **같은 화면**을 연다 — 상점 UI를 두 번 만들지 않는다.
        .inkBottomSheet(isPresented: $isShowingShardStore, size: .fraction(0.7)) {
            ShardStoreSheet(
                controller: shardStore,
                wallet: shards,
                session: session.server,
                // 기존 gate를 그대로 쓴다 — 새 auth flow도, 새 로그인 UI도 만들지 않는다.
                // 로그인 뒤 결제를 자동으로 이어가지 않는다(사용자가 상품을 다시 고른다).
                onNeedsSignIn: { _ = session.requireSignIn(for: .shardTransaction) }
            )
        }
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

            // 조각 영역: 출석 · 광고. 새 화면을 만들지 않고 홈에 얹는다.
            dailyShard
            rewardedAd

            // 남는 공간을 미리보기가 차지한다. 비율은 다른 화면과 같은 9:19.5.
            currentMirror
                .frame(maxWidth: .infinity, maxHeight: previewMaxHeight ?? .infinity)

            actions
        }
    }

    private var header: some View {
        HStack {
            // 여기는 **가격이 아니라 보유 잔액**이다. 0은 "무료"가 아니라 0이다.
            // 탭하면 조각을 충전한다. **생김새는 그대로 둔다** — 잔액 표시가
            // 갑자기 버튼처럼 보이면 화면의 무게중심이 바뀐다.
            Button {
                isShowingShardStore = true
            } label: {
                ShardAmount(
                    amount: shards.balance,
                    font: InkFont.cardTitle,
                    iconSize: 22,
                    treatsZeroAsFree: false
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                    UnevenRoundedRectangle.ink(17, 14, 18, 13)
                        .stroke(PaperTheme.ink, lineWidth: 1.7)
                        .rotationEffect(.degrees(-0.35))
                }
            }
            .buttonStyle(InkPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("보유 \(shards.balance) 조각. 조각 구매")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("openShardStore")

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

    // MARK: - 오늘의 조각

    /// 하루 한 번 출석 +1. **client는 잔액을 올리지 않는다** —
    /// 눌러도 서버가 지급하고, 화면에 반영되는 숫자는 서버가 준 잔액뿐이다.
    ///
    /// 로그인하지 않았으면 **설정의 기존 Apple 로그인**으로 보낸다.
    /// 조각 때문에 거울 · 촬영 · 꾸미기 앞에 로그인 벽을 세우지 않는다.
    private var isSignedIn: Bool {
        session.state.isSignedIn && session.server?.isValid() == true
    }

    @ViewBuilder
    private var dailyShard: some View {
        if isSignedIn {
            let isDone = shards.attendance == .claimed
            Button {
                Task { await shards.claimAttendance(session: session.server) }
            } label: {
                dailyShardLabel(isDone ? "오늘 출석 완료" : "오늘의 조각 받기 · +1", isDone: isDone)
            }
            .buttonStyle(InkPressStyle())
            .disabled(isDone || shards.isClaiming)
            .opacity(shards.isClaiming ? 0.6 : 1)
            .accessibilityIdentifier("claimAttendance")
        } else {
            NavigationLink(value: SettingsRoute.settings) {
                dailyShardLabel("로그인하고 오늘의 조각 받기", isDone: false)
            }
            .buttonStyle(InkPressStyle())
            .accessibilityIdentifier("attendanceSignIn")
        }
    }

    // MARK: - 광고 보고 조각 받기

    /// **client는 지급하지 않는다.** 광고를 끝까지 봐도 조각은 서버가 준다 —
    /// 여기서는 서버가 센 `rewardedToday`만 보여주고, 광고가 끝나면 다시 물어본다.
    ///
    /// ad unit이 없는 빌드(현재 Release)에서는 CTA 자체를 보여주지 않는다.
    @ViewBuilder
    private var rewardedAd: some View {
        if rewardedAds.isConfigured {
            let isDone = shards.remainingAdsToday == 0 && shards.dailyAdLimit > 0
            let isBusy = rewardedAds.phase == .presenting || rewardedAds.phase == .verifying

            if isSignedIn {
                Button {
                    Task { await rewardedAds.watch(session: session.server, wallet: shards) }
                } label: {
                    rewardedAdLabel(isDone: isDone, isBusy: isBusy)
                }
                .buttonStyle(InkPressStyle())
                .disabled(isDone || isBusy || rewardedAds.phase == .unavailable)
                .opacity(isBusy ? 0.6 : 1)
                .accessibilityIdentifier("watchRewardedAd")
            } else {
                NavigationLink(value: SettingsRoute.settings) {
                    rewardedAdLabel(isDone: false, isBusy: false)
                }
                .buttonStyle(InkPressStyle())
                .accessibilityIdentifier("rewardedAdSignIn")
            }
        }
    }

    private func rewardedAdLabel(isDone: Bool, isBusy: Bool) -> some View {
        Text(rewardedAdTitle(isDone: isDone, isBusy: isBusy))
            .font(InkFont.body)
            .foregroundStyle(isDone ? PaperTheme.disabled : PaperTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 3)
            .background {
                let shape = UnevenRoundedRectangle.ink(21, 18, 22, 17)
                shape
                    .fill(PaperTheme.subtleSurface)
                    .overlay(shape.stroke(isDone ? PaperTheme.disabled : PaperTheme.ink, lineWidth: 1.7))
                    .rotationEffect(.degrees(0.3))
            }
            .contentShape(.rect)
    }

    private func rewardedAdTitle(isDone: Bool, isBusy: Bool) -> String {
        guard isSignedIn else { return "로그인하고 광고 보고 조각 받기" }
        // 광고가 끝나도 서버 확인 전까지는 받았다고 말하지 않는다.
        if rewardedAds.phase == .verifying { return "보상을 확인하고 있어요" }
        if rewardedAds.phase == .unavailable { return "광고를 불러오지 못했어요" }
        if isBusy { return "광고를 준비하고 있어요" }
        if isDone { return "오늘 광고 보상 완료 \(shards.dailyAdLimit) / \(shards.dailyAdLimit)" }
        return "광고 보고 조각 받기 · +1 · 오늘 \(shards.rewardedToday) / \(shards.dailyAdLimit)"
    }

    private func dailyShardLabel(_ title: String, isDone: Bool) -> some View {
        Text(title)
            .font(InkFont.button)
            .foregroundStyle(isDone ? PaperTheme.disabled : PaperTheme.paper)
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.vertical, 4)
            .background {
                let shape = UnevenRoundedRectangle.ink(18, 21, 17, 22)
                Group {
                    if isDone {
                        shape
                            .fill(PaperTheme.pressed)
                            .overlay(shape.stroke(PaperTheme.disabled, lineWidth: 1.8))
                    } else {
                        shape.fill(PaperTheme.ink)
                    }
                }
                .rotationEffect(.degrees(-0.3))
            }
            .contentShape(.rect)
    }

    private var currentMirror: some View {
        let mirror = library.currentMirror
        return VStack(spacing: 8) {
            MirrorPreview(mirror: mirror)
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
                // 거울 선택 화면 없이 지금 쓰는 거울을 그 자리에서 고친다.
                action: {
                    onEdit(.init(
                        design: MirrorDesign(mirror: library.currentMirror),
                        context: .editCurrent
                    ))
                }
            )
        }
    }
}

#Preview {
    HomeView(library: MirrorLibrary(), onOpenMirror: {}, onEdit: { _ in })
        .environment(ShardWallet())
        .environment(AuthSession(store: InMemoryIdentityStore(), sessions: InMemoryServerSessionStore()))
        .environment(RewardedAdController())
}
