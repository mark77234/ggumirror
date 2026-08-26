//
//  TextEditorSheets.swift
//  ggumirror
//
//  텍스트 입력과 글꼴 고르기. 거울 이름 짓기 시트와 같은 디자인 언어를 쓴다.
//

import SwiftUI

/// 새 텍스트 추가 / 기존 텍스트 내용 수정. 두 경우 모두 이 시트 하나를 쓴다.
///
/// **입력 중인 글자는 이 시트만 안다.** 예전에는 부모(`EditorView`)의 `@State`에
/// 바로 썼는데, 그 부모의 body에는 거울 canvas가 들어 있다 — 한 글자마다
/// `MirrorEditorCanvas` 전체가 다시 평가돼서 실기기에서 입력이 눈에 띄게 밀렸다.
///
/// 이제 완성된 값만 `onCommit`으로 한 번 넘긴다. 타이핑은 이 작은 시트 안에서 끝난다.
struct TextInputSheet: View {
    /// 새로 추가하는 중인지. 버튼 문구만 달라진다.
    let isNew: Bool
    let onCommit: (String) -> Void

    @State private var text: String

    init(initialText: String = "", isNew: Bool, onCommit: @escaping (String) -> Void) {
        self.isNew = isNew
        self.onCommit = onCommit
        _text = State(initialValue: initialText)
    }

    @Environment(\.inkModalDismiss) private var dismiss
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(isNew ? "텍스트 추가" : "내용 수정")
                    .font(InkFont.cardTitle)
                    .foregroundStyle(PaperTheme.ink)
                Spacer()
                Text("\(trimmed.count) / \(TextPolicy.maxLength)")
                    .font(InkFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(PaperTheme.secondaryInk)
            }

            // 여러 줄을 그대로 받는다. 줄바꿈이 곧 텍스트 줄이 된다.
            TextField("오늘도\n예쁘게", text: $text, axis: .vertical)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .lineLimit(3...6)
                .focused($isFocused)
                .onChange(of: text) { _, newValue in
                    if newValue.count > TextPolicy.maxLength {
                        text = String(newValue.prefix(TextPolicy.maxLength))
                    }
                }
                .padding(14)
                .background {
                    let shape = UnevenRoundedRectangle.ink(15, 18, 19, 14)
                    shape
                        .fill(PaperTheme.subtleSurface)
                        .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.8))
                }

            HStack(spacing: 10) {
                // 겉모습을 label 안에 둔다 — 밖에 두면 글자만 눌린다.
                Button {
                    dismiss()
                } label: {
                    Text("취소")
                        .font(InkFont.body)
                        .foregroundStyle(PaperTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background {
                            UnevenRoundedRectangle.ink(15, 12, 16, 13)
                                .stroke(PaperTheme.ink, lineWidth: 1.6)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())

                Button {
                    onCommit(text)
                } label: {
                    Text(isNew ? "추가" : "저장")
                        .font(InkFont.body.weight(.semibold))
                        .foregroundStyle(PaperTheme.subtleSurface)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background {
                            UnevenRoundedRectangle.ink(15, 12, 16, 13)
                                .fill(trimmed.isEmpty ? PaperTheme.disabled : PaperTheme.ink)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())
                    // 빈 문자열 / 공백만으로는 만들 수 없다.
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { isFocused = true }
    }
}

/// 글꼴 preset 고르기. 새 폰트 파일 없이 system font design만 쓴다.
struct TextFontSheet: View {
    let style: TextFontStyle
    let onPick: (TextFontStyle) -> Void

    @Environment(\.inkModalDismiss) private var dismiss

    /// 이름만 늘어놓지 않는다. 각 줄이 **그 글꼴로** 쓰여 있어 눈으로 고른다.
    private let sample = "오늘도 예쁘게"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("글꼴")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section(title: "기본", styles: [.basic])
                    ForEach(TextFontGroup.allCases) { group in
                        section(title: group.rawValue, styles: group.styles)
                    }
                    // 예전에 저장해 둔 글꼴을 쓰고 있으면 그것도 보여준다.
                    if !TextFontStyle.selectable.contains(style) {
                        section(title: "지금 글꼴", styles: [style])
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(title: String, styles: [TextFontStyle]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)

            ForEach(styles) { option in
                row(option)
            }
        }
    }

    private func row(_ option: TextFontStyle) -> some View {
        let isSelected = option == style
        return Button {
            onPick(option)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(sample)
                    .font(Font(option.font(ofSize: 21)))
                    .foregroundStyle(PaperTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(option.title)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(PaperTheme.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background {
                let shape = InkCorner.chip
                shape
                    .fill(PaperTheme.subtleSurface)
                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: isSelected ? 2.2 : InkLine.thin))
            }
            .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel("\(option.title) 글꼴")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    TextInputSheet(initialText: "오늘도\n예쁘게", isNew: true) { _ in }
        .paperBackground()
}
