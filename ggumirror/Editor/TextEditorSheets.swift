//
//  TextEditorSheets.swift
//  ggumirror
//
//  텍스트 입력과 글꼴 고르기. 거울 이름 짓기 시트와 같은 디자인 언어를 쓴다.
//

import SwiftUI

/// 새 텍스트 추가 / 기존 텍스트 내용 수정. 두 경우 모두 이 시트 하나를 쓴다.
struct TextInputSheet: View {
    @Binding var text: String
    /// 새로 추가하는 중인지. 버튼 문구만 달라진다.
    let isNew: Bool
    let onCommit: () -> Void

    @Environment(\.dismiss) private var dismiss
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
                Button("취소") { dismiss() }
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background {
                        UnevenRoundedRectangle.ink(15, 12, 16, 13)
                            .stroke(PaperTheme.ink, lineWidth: 1.6)
                    }
                    .buttonStyle(InkPressStyle())

                Button(isNew ? "추가" : "저장") { onCommit() }
                    .font(InkFont.body.weight(.semibold))
                    .foregroundStyle(PaperTheme.subtleSurface)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background {
                        UnevenRoundedRectangle.ink(15, 12, 16, 13)
                            .fill(trimmed.isEmpty ? PaperTheme.disabled : PaperTheme.ink)
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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("글꼴")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)

            ForEach(TextFontStyle.allCases) { option in
                Button {
                    onPick(option)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text("오늘도 예쁘게")
                            .font(Font(option.font(ofSize: 19)))
                            .foregroundStyle(PaperTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(option.title)
                            .font(InkFont.caption)
                            .foregroundStyle(PaperTheme.secondaryInk)
                        if option == style {
                            Image(systemName: "checkmark")
                                .font(.system(.footnote, weight: .bold))
                                .foregroundStyle(PaperTheme.ink)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background {
                        let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
                        shape
                            .fill(PaperTheme.subtleSurface)
                            .overlay(shape.stroke(PaperTheme.ink, lineWidth: option == style ? 2.2 : 1.4))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())
                .accessibilityLabel("\(option.title) 글꼴")
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    TextInputSheet(text: .constant("오늘도\n예쁘게"), isNew: true, onCommit: {})
        .paperBackground()
}
