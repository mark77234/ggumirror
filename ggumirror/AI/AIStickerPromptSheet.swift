//
//  AIStickerPromptSheet.swift
//  ggumirror
//
//  "무엇을 만들까"를 한 줄로 받는 자리.
//
//  **가격을 여기에 적지 않는다** — 서버가 알려준 `price`를 그대로 보여준다.
//  글자 수 상한도 서버와 같은 값(`AIStickerPromptPolicy.maxLength`) 하나에서 온다.
//

import SwiftUI

enum AIStickerPromptPolicy {
    /// 서버 `MAX_PROMPT_LENGTH`와 같은 값. 화면에서 미리 막아 조각이 헛되이 나가지 않게 한다.
    /// (서버가 최종 판단을 한다 — 여기는 사용자를 위한 안내지 보안 경계가 아니다.)
    static let maxLength = 200
}

struct AIStickerPromptSheet: View {
    @Binding var prompt: String
    /// 몇 조각이 드는지. **서버가 준 값이다.**
    let price: Int
    /// 지금 가진 조각. 부족하면 버튼을 눌러도 서버가 거절하므로 미리 알려준다.
    let balance: Int
    let isGenerating: Bool
    let onGenerate: () -> Void

    @Environment(\.inkModalDismiss) private var dismiss
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAfford: Bool { balance >= price }
    private var canGenerate: Bool { !trimmed.isEmpty && canAfford && !isGenerating }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("AI로 스티커 만들기")
                    .font(InkFont.cardTitle)
                    .foregroundStyle(PaperTheme.ink)
                Spacer()
                Text("\(trimmed.count) / \(AIStickerPromptPolicy.maxLength)")
                    .font(InkFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(PaperTheme.secondaryInk)
            }

            TextField("웃고 있는 딸기 케이크", text: $prompt, axis: .vertical)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .lineLimit(2...4)
                .focused($isFocused)
                .disabled(isGenerating)
                .onChange(of: prompt) { _, newValue in
                    if newValue.count > AIStickerPromptPolicy.maxLength {
                        prompt = String(newValue.prefix(AIStickerPromptPolicy.maxLength))
                    }
                }
                .padding(14)
                .background {
                    let shape = UnevenRoundedRectangle.ink(15, 18, 19, 14)
                    shape
                        .fill(PaperTheme.subtleSurface)
                        .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.8))
                }

            HStack(spacing: 6) {
                Image(systemName: "diamond")
                    .font(InkFont.caption)
                Text(canAfford ? "\(price)조각을 써요" : "\(price)조각이 필요해요 (지금 \(balance)조각)")
                    .font(InkFont.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(canAfford ? PaperTheme.secondaryInk : PaperTheme.ink)

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
                    .disabled(isGenerating)

                Button(isGenerating ? "만드는 중..." : "만들기") { onGenerate() }
                    .font(InkFont.body.weight(.semibold))
                    .foregroundStyle(PaperTheme.subtleSurface)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background {
                        UnevenRoundedRectangle.ink(15, 12, 16, 13)
                            .fill(canGenerate ? PaperTheme.ink : PaperTheme.disabled)
                    }
                    .buttonStyle(InkPressStyle())
                    .disabled(!canGenerate)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { isFocused = true }
    }
}
