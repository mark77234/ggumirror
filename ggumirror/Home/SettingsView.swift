//
//  SettingsView.swift
//  ggumirror
//
//  MVP 설정: 프로필 / 알림 / 개인정보 / 이용약관.
//  실제 로직이 없는 항목은 UI와 navigation까지만 둔다.
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AuthSession.self) private var session
    @Environment(AdsConsent.self) private var adsConsent
    /// 이름의 authority는 **서버**다. `UserDefaults`에 두지 않는다 —
    /// 계정을 바꿔도 남아서 A의 이름이 B에게 보였다.
    @Environment(ProfileSession.self) private var profile: ProfileSession?
    // optional로 받는다 — 이 화면을 따로 그리는 미리보기·테스트에 환경값이 없을 수 있다.
    @Environment(MarketplaceStore.self) private var marketplace: MarketplaceStore?

    private var profileDisplayName: String? { profile?.displayName }
    /// 매일 알림. **기기 설정이라 계정별로 두지 않는다.**
    @Environment(DailyReminderScheduler.self) private var reminder: DailyReminderScheduler?
    /// 알림 종류별 설정. **서버가 authority다.**
    @Environment(NotificationPreferenceSession.self)
    private var notificationPreferences: NotificationPreferenceSession?

    /// 토글은 값을 바로 쓰지 않는다 — 켤 때는 권한을 먼저 물어야 하고,
    /// 끌 때는 예약을 지워야 한다.
    /// 설정은 **서버가 authority다.** 화면을 먼저 바꾸고 실패하면 되돌린다.
    private var salesBinding: Binding<Bool> {
        Binding(
            get: { notificationPreferences?.preferences.salesEnabled ?? true },
            set: { value in
                Task { await notificationPreferences?.setSales(value, session: session.server) }
            }
        )
    }

    private var recommendationBinding: Binding<Bool> {
        Binding(
            get: { notificationPreferences?.preferences.recommendationEnabled ?? false },
            set: { value in
                Task {
                    await notificationPreferences?.setRecommendation(
                        value, session: session.server
                    )
                }
            }
        )
    }

    /// 새 거울 소식은 켜고 끄는 것이 아니라 **얼마나 자주**다.
    private var digestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("새 거울 소식")
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
            Text("새로운 거울이 등록되면 모아서 알려드려요.")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)

            HStack(spacing: 8) {
                ForEach(DigestFrequency.allCases, id: \.self) { option in
                    let isSelected =
                        notificationPreferences?.preferences.mirrorDigestFrequency == option
                    Button(option.label) {
                        Task {
                            await notificationPreferences?.setDigest(
                                option, session: session.server
                            )
                        }
                    }
                    .font(InkFont.caption)
                    .foregroundStyle(isSelected ? PaperTheme.ink : PaperTheme.secondaryInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .frame(minHeight: InkTapTarget.minimum)
                    .background {
                        Capsule().stroke(
                            isSelected ? PaperTheme.ink : PaperTheme.separator, lineWidth: 1.4
                        )
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 12)
    }

    private var dailyReminderBinding: Binding<Bool> {
        Binding(
            get: { reminder?.isOn ?? false },
            set: { wants in
                Task {
                    if wants { await reminder?.enable() } else { await reminder?.disable() }
                }
            }
        )
    }

    @State private var notice: String?
    @State private var isConfirmingAccountDeletion = false
    @State private var isDeletingAccount = false
    /// 운영자인가. **서버에 물어본 답이다** — 앱이 판단하지 않는다.
    /// 확인 전에는 `nil`이고, 그동안 항목은 보이지 않는다.
    @State private var isAdmin: Bool?
    @Environment(MirrorLibrary.self) private var library: MirrorLibrary?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AccountSection(session: session)
                    .padding(.top, 8)
                    .padding(.bottom, 22)

                NavigationLink(value: SettingsRoute.profile) {
                    profileRow
                }
                .buttonStyle(InkPressStyle())

                InkSeparator()

                NavigationLink(value: SettingsRoute.notificationCenter) {
                    InkListRow(title: "알림", showsChevron: true)
                }
                .buttonStyle(InkPressStyle())

                InkSeparator()

                Text("알림을 켜두면 판매 소식과 새로운 거울 소식을 놓치지 않을 수 있어요. "
                     + "알림은 언제든 바꿀 수 있어요.")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)

                InkListRow(title: "판매 알림", subtitle: "내 거울이 판매되면 알려드려요.") {
                    Toggle("판매 알림", isOn: salesBinding)
                        .labelsHidden()
                        .tint(PaperTheme.ink)
                }

                InkSeparator()

                digestSection

                InkSeparator()

                InkListRow(
                    title: "꾸미러 추천 소식",
                    subtitle: "새로운 기능이나 다시 둘러볼 만한 소식을 알려드려요."
                ) {
                    Toggle("꾸미러 추천 소식", isOn: recommendationBinding)
                        .labelsHidden()
                        .tint(PaperTheme.ink)
                }

                InkSeparator()

                InkListRow(title: "매일 거울 소식 받기") {
                    Toggle("매일 거울 소식 받기", isOn: dailyReminderBinding)
                        .labelsHidden()
                        .tint(PaperTheme.ink)
                }

                // 거부한 사람에게 토글만 보여 주면 켜지지 않는 이유를 알 수 없다.
                // **다시 조르지 않고** 어디서 켤 수 있는지 알려 준다.
                if reminder?.permission == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        InkListRow(
                            title: "알림이 꺼져 있어요. 설정 앱에서 켜주세요.",
                            showsChevron: true
                        )
                        .foregroundStyle(PaperTheme.secondaryInk)
                    }
                    .buttonStyle(InkPressStyle())
                    .accessibilityIdentifier("openSystemNotificationSettings")
                }

                InkSeparator()

                // UMP가 "이 사용자에게는 설정 진입점이 필요하다"고 할 때만 보인다.
                // 필요 없는 지역에서 빈 항목을 보여주지 않는다 — 새 화면도 만들지 않고,
                // 탭하면 Google이 관리하는 양식이 그대로 뜬다.
                if adsConsent.showsPrivacyOptions {
                    Button {
                        Task { await adsConsent.presentPrivacyOptions() }
                    } label: {
                        InkListRow(title: "광고 개인정보 설정", showsChevron: true)
                    }
                    .buttonStyle(InkPressStyle())
                    .accessibilityIdentifier("adsPrivacyOptions")

                    InkSeparator()
                }

                legalRow("개인정보 처리방침", url: LegalLinks.privacyPolicy)

                InkSeparator()

                legalRow("이용약관", url: LegalLinks.termsOfService)

                // 운영자에게만 보인다. **보인다고 권한이 생기는 것이 아니다** —
                // 화면을 강제로 열어도 서버가 모든 요청을 다시 판단한다.
                if isAdmin == true {
                    InkSeparator()

                    NavigationLink(value: SettingsRoute.adminStore) {
                        InkListRow(title: "상점 관리", showsChevron: true)
                    }
                    .buttonStyle(InkPressStyle())
                    .accessibilityIdentifier("adminStore")
                }

                // 계정을 만들 수 있으면 지울 수도 있어야 한다. 로그인한 사람에게만 보인다.
                if session.account != nil {
                    InkSeparator()

                    Button {
                        isConfirmingAccountDeletion = true
                    } label: {
                        InkListRow(title: "계정 삭제", showsChevron: true)
                            .foregroundStyle(PaperTheme.ink)
                    }
                    .buttonStyle(InkPressStyle())
                    .disabled(isDeletingAccount)
                }

                InkSeparator()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        // 탭 막대에 가리지 않게 아래를 띄운다. 숫자는 막대가 정한다.
        .inkTabBarSafeContent()
        .paperBackground()
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
        // 실패하면 항목이 보이지 않는다. **일반 사용자의 설정을 깨뜨리지 않는다** —
        // 대부분에게 403이 정상 답이고, 그것으로 화면이 흔들리면 안 된다.
        .task(id: session.server?.userID) { await checkAdmin() }
        // 설정 앱에서 권한을 바꾸고 돌아왔을 수 있다. **여기서 창을 띄우지 않는다.**
        .task { await reminder?.refreshPermission() }
        .task(id: session.server?.userID) {
            await notificationPreferences?.refresh(session: session.server)
        }
        .inkDialog(
            "계정 삭제",
            message: isConfirmingAccountDeletion ? accountDeletionMessage : nil,
            isPresented: $isConfirmingAccountDeletion
        ) {
            [
                InkDialogAction("취소", role: .secondary),
                InkDialogAction("계정 삭제", role: .destructive) {
                    Task { await deleteAccount() }
                },
            ]
        }
        .inkDialog(
            "준비 중",
            message: notice,
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
    }

    /// 계정을 지운다. **되돌릴 수 없다** — 그래서 무엇이 사라지는지 먼저 말한다.
    ///
    /// 이미 다른 사람이 산 상품은 그 사람에게 계속 제공된다는 것도 함께 알린다.
    /// 판 사람이 떠난다고 산 사람의 권리가 사라지지 않기 때문이다.
    private var accountDeletionMessage: String {
        """
        계정을 삭제하면 복구할 수 없어요.

        • 남은 조각은 복구되지 않아요.
        • 구매해서 보관 중인 콘텐츠에 더 이상 접근할 수 없어요.
        • 판매 중인 상품은 상점에서 내려가요.
        • 이미 다른 사람이 구매한 상품은 그 사람에게 계속 제공돼요.

        Apple 계정 연결은 설정 > Apple 계정 > 로그인 관련 항목에서 직접 해제할 수 있어요.
        """
    }

    private func deleteAccount() async {
        guard let library else {
            notice = "지금은 계정을 삭제할 수 없어요."
            return
        }
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        switch await AccountDeletion.run(
            session: session, library: library, stickers: StickerLibrary.live,
            profile: profile, marketplace: marketplace
        ) {
        case .deleted:
            // 로그아웃까지 끝났다. 화면은 자연히 로그인 전 상태로 돌아간다.
            notice = "계정을 삭제했어요."
        case .notSignedIn:
            notice = "로그인이 필요해요."
        case .failed(let message):
            // **로컬은 하나도 지우지 않았다.** 그대로 다시 시도할 수 있다.
            notice = message
        }
    }

    /// 법적 문서 한 줄. 주소가 아직 없으면 **열지 않고** 준비 중이라고 말한다.
    /// 운영자인지 서버에 물어본다. **답이 아니면 항목을 보이지 않는다.**
    ///
    /// 네트워크가 안 되거나 로그인하지 않았으면 그냥 없는 것으로 둔다 —
    /// 여기서 오류창을 띄우면 일반 사용자가 설정을 열 때마다 경고를 본다.
    private func checkAdmin() async {
        guard let token = session.server?.accessToken else {
            isAdmin = false
            return
        }
        isAdmin = (try? await BackendClient().isAdmin(accessToken: token)) ?? false
    }

    private func legalRow(_ title: String, url: URL?) -> some View {
        Button {
            guard let url else {
                notice = LegalLinks.notReadyMessage
                return
            }
            // 앱 안에 WebView를 새로 만들지 않는다 — 시스템 브라우저로 보낸다.
            openURL(url)
        } label: {
            InkListRow(title: title, showsChevron: true)
        }
        .buttonStyle(InkPressStyle())
    }

    private var profileRow: some View {
        HStack(spacing: 14) {
            InkAvatar(size: 56)

            VStack(alignment: .leading, spacing: 3) {
                // **모두에게 같은 기본 이름을 보여 주지 않는다.** 아직 정하지 않았으면
                // 그렇게 말하고, 그 문구는 저장되는 값이 아니다.
                Text(profileDisplayName ?? DisplayNamePolicy.placeholder)
                    .font(InkFont.cardTitle)
                    .foregroundStyle(
                        profileDisplayName == nil ? PaperTheme.secondaryInk : PaperTheme.ink
                    )
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(PaperTheme.ink)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 16)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("프로필, \(profileDisplayName ?? DisplayNamePolicy.placeholder)")
    }
}

enum SettingsRoute: Hashable {
    case settings
    case profile
    case privacy
    case terms
    /// 운영자 전용. 이 경로가 있다고 권한이 생기지 않는다 — 화면 안의 모든
    /// 요청을 서버가 다시 판단한다.
    case adminStore
    /// 판매 알림 목록. 로그인하지 않아도 열리고, 그때는 안내만 보인다.
    case notificationCenter
}

/// 예전 프로필 저장소. **더 이상 읽지 않는다.**
///
/// 이름은 서버가 authority이고(`ProfileSession`), 태그 기능은 없앴다.
/// 여기 남아 있던 `profileName` · `profileTags` 값을 **지우지 않는다** —
/// 지울 이유가 없고, 지우는 코드가 곧 새 버그다. 그냥 읽지 않는다.

#Preview {
    NavigationStack { SettingsView() }
        .environment(AuthSession(store: InMemoryIdentityStore(), sessions: InMemoryServerSessionStore()))
}
