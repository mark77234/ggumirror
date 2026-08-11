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
    @AppStorage(ProfileStore.nameKey) private var profileName = ProfileStore.defaultName
    @AppStorage(ProfileStore.tagsKey) private var profileTags = ""
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
        .alert("준비 중", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private var profileRow: some View {
        HStack(spacing: 14) {
            InkAvatar(size: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(profileName.isEmpty ? ProfileStore.defaultName : profileName)
                    .font(InkFont.cardTitle)
                    .foregroundStyle(PaperTheme.ink)
                    .lineLimit(1)
                Text(ProfileStore.tagLine(from: profileTags))
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
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
        .accessibilityLabel("프로필, \(profileName)")
    }
}

enum SettingsRoute: Hashable {
    case settings
    case profile
    case privacy
    case terms
}

/// 아직 backend가 없어 프로필은 UserDefaults에만 저장한다.
enum ProfileStore {
    static let nameKey = "profileName"
    static let tagsKey = "profileTags"
    static let defaultName = "거울지기"

    static func tags(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init))
    }

    static func raw(from tags: Set<String>) -> String {
        ProfileTag.allCases.map(\.rawValue).filter(tags.contains).joined(separator: ",")
    }

    static func tagLine(from raw: String) -> String {
        let selected = ProfileTag.allCases.map(\.rawValue).filter(tags(from: raw).contains)
        return selected.isEmpty ? "태그를 골라 스타일을 소개해 보세요" : selected.joined(separator: " · ")
    }
}

enum ProfileTag: String, CaseIterable, Identifiable {
    case y2k = "Y2K"
    case ribbon = "리본"
    case cute = "큐트"
    case minimal = "미니멀"
    case vintage = "빈티지"
    case fashion = "패션"

    var id: String { rawValue }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AuthSession(store: InMemoryIdentityStore()))
}
