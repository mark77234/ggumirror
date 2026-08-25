//
//  SettingsView.swift
//  ggumirror
//
//  MVP 설정: 프로필 / 구매 복원 / 알림 / 개인정보 / 이용약관.
//  실제 로직이 없는 항목은 UI와 navigation까지만 둔다.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthSession.self) private var session
    @Environment(AdsConsent.self) private var adsConsent
    /// 이름의 authority는 **서버**다. `UserDefaults`에 두지 않는다 —
    /// 계정을 바꿔도 남아서 A의 이름이 B에게 보였다.
    @Environment(ProfileSession.self) private var profile: ProfileSession?

    private var profileDisplayName: String? { profile?.displayName }
    @AppStorage("notificationsOn") private var notificationsOn = true

    @State private var notice: String?

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

                Button {
                    notice = "구매 복원은 상점 기능과 함께 열려요."
                } label: {
                    InkListRow(title: "구매 복원", showsChevron: true)
                }
                .buttonStyle(InkPressStyle())

                InkSeparator()

                InkListRow(title: "알림") {
                    Toggle("알림", isOn: $notificationsOn)
                        .labelsHidden()
                        .tint(PaperTheme.ink)
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

                NavigationLink(value: SettingsRoute.privacy) {
                    InkListRow(title: "개인정보 처리방침", showsChevron: true)
                }
                .buttonStyle(InkPressStyle())

                InkSeparator()

                NavigationLink(value: SettingsRoute.terms) {
                    InkListRow(title: "이용약관", showsChevron: true)
                }
                .buttonStyle(InkPressStyle())

                InkSeparator()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .paperBackground()
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
        .inkDialog(
            "준비 중",
            message: notice,
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
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
