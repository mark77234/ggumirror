//
//  ProfileView.swift
//  ggumirror
//
//  프로필 편집. backend가 없어 UserDefaults에만 저장한다.
//

import SwiftUI

struct ProfileView: View {
    @AppStorage(ProfileStore.nameKey) private var storedName = ProfileStore.defaultName
    @AppStorage(ProfileStore.tagsKey) private var storedTags = ""

    @State private var name = ""
    @State private var tags: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                avatar

                fieldLabel("이름")
                TextField("이름", text: $name)
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { isNameFocused = false }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .frame(minHeight: 44)
                    .background {
                        let shape = UnevenRoundedRectangle.ink(15, 18, 19, 14)
                        shape
                            .fill(PaperTheme.subtleSurface)
                            .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.8))
                    }

                fieldLabel("태그")
                    .padding(.top, 24)

                // 여러 개 고를 수 있다. 줄바꿈되어 긴 태그도 잘리지 않는다.
                FlowLayout(spacing: 7) {
                    ForEach(ProfileTag.allCases) { tag in
                        InkToggleChip(label: tag.rawValue, isOn: tags.contains(tag.rawValue)) {
                            if tags.contains(tag.rawValue) {
                                tags.remove(tag.rawValue)
                            } else {
                                tags.insert(tag.rawValue)
                            }
                        }
                    }
                }

                Text("태그는 나중에 크리에이터 프로필에서 내 거울 스타일을 소개할 때 쓰여요.")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
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
                Button("저장") {
                    storedName = name.trimmingCharacters(in: .whitespaces)
                    storedTags = ProfileStore.raw(from: tags)
                    dismiss()
                }
                .font(InkFont.body.weight(.semibold))
                .tint(PaperTheme.ink)
            }
        }
        .onAppear {
            name = storedName
            tags = ProfileStore.tags(from: storedTags)
        }
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
