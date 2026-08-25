//
//  ProfileView.swift
//  ggumirror
//
//  프로필 편집. **이름 하나뿐이다.**
//
//  이름의 authority는 서버다 — 이 화면은 서버가 준 값을 보여 주고, 저장은 서버가
//  받아 준 뒤에만 반영한다. 저장되지 않은 이름을 화면에 남기지 않는다.
//
//  태그는 없앴다. 크리에이터 프로필 계획에서 나온 것이었는데 실제로 쓰이는 곳이
//  없었고, 사용자에게는 고르라고만 하고 아무 데도 보이지 않는 값이었다.
//  **예전에 저장된 값은 지우지 않는다** — 그냥 읽지 않는다.
//

import SwiftUI

struct ProfileView: View {
    @Environment(ProfileSession.self) private var profile: ProfileSession?
    @Environment(AuthSession.self) private var session

    @State private var name = ""
    @State private var notice: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool

    /// 지금 이름을 바꿀 수 있는가. **서버가 판단한 값을 그대로 쓴다** —
    /// 기기 시계로 30일을 세지 않는다.
    private var canChange: Bool {
        profile?.profile?.canChangeDisplayName ?? true
    }

    private var nextChangeLabel: String? {
        profile?.profile?.nextDisplayNameChangeAt.map(DisplayNamePolicy.nextChangeLabel)
    }

    private var isFirstName: Bool { profile?.profile?.hasName != true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                avatar

                fieldLabel("이름")
                TextField(DisplayNamePolicy.placeholder, text: $name)
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { isNameFocused = false }
                    .onChange(of: name) { _, value in
                        // 지나치게 긴 이름은 입력 단계에서 막는다(서버도 막는다).
                        if value.count > DisplayNamePolicy.maxLength {
                            name = String(value.prefix(DisplayNamePolicy.maxLength))
                        }
                    }
                    .disabled(!canChange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .frame(minHeight: 44)
                    .background {
                        let shape = UnevenRoundedRectangle.ink(15, 18, 19, 14)
                        shape
                            .fill(PaperTheme.subtleSurface)
                            .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.8))
                    }

                Text(guidance)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .inkDismissesKeyboardOnTap()
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .paperBackground()
        .navigationTitle("프로필")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isFirstName ? "설정" : "저장") { Task { await save() } }
                    .font(InkFont.body.weight(.semibold))
                    .tint(PaperTheme.ink)
                    .disabled(!canChange || profile?.isSaving == true)
            }
        }
        .inkDialog(
            "이름",
            message: notice,
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
        .task {
            await profile?.refresh(session: session.server)
            name = profile?.displayName ?? ""
        }
    }

    /// 지금 상태를 한 줄로 설명한다. 30일 규칙을 숨기지 않는다.
    private var guidance: String {
        if !canChange, let next = nextChangeLabel {
            return "이름은 30일에 한 번 변경할 수 있어요. 다음 변경 가능: \(next)"
        }
        return isFirstName
            ? "상점에 올린 상품에 이 이름이 보여요. 한 번 정하면 30일에 한 번 바꿀 수 있어요."
            : "이름을 바꾸면 30일 동안 다시 바꿀 수 없어요."
    }

    private func save() async {
        // 서버가 거절할 요청을 보내지 않는다 — 이미 아는 사실이다.
        guard canChange else {
            notice = guidance
            return
        }
        if let failure = await profile?.setDisplayName(name, session: session.server) {
            notice = failure
            return
        }
        dismiss()
    }

    private var avatar: some View {
        VStack(spacing: 10) {
            InkAvatar(size: 84)
            Button {} label: {
                Text("사진 변경")
                    .font(InkFont.secondary)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
                .tint(PaperTheme.ink)
                .disabled(true)   // 사진 선택은 다음 Phase
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 26)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(InkFont.caption.weight(.semibold))
            .foregroundStyle(PaperTheme.secondaryInk)
            .padding(.bottom, 8)
    }
}

/// 태그처럼 개수가 유동적인 칩을 줄바꿈해서 배치한다.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layout(subviews: subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, x + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
                x = 0
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
            current.width = x - spacing
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

#Preview {
    NavigationStack { ProfileView() }
}
