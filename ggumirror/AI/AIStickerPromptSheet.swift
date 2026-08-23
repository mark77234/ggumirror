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
    /// 조각이 모자랄 때 충전 화면으로. **여기서 상점 UI를 다시 만들지 않는다.**
    var onBuyShards: (() -> Void)?

    @Environment(\.inkModalDismiss) private var dismiss
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAfford: Bool { balance >= price }
    private var canGenerate: Bool { !trimmed.isEmpty && canAfford && !isGenerating }

    /// 입력창이 있는 시트라 **키보드가 올라오면 남는 높이가 절반 이하**가 된다.
    /// 그래서 설명·입력·가격은 스크롤로 흘리고, 만들기/취소는 `safeAreaInset`으로 바닥에 고정한다.
    /// 예전에는 통짜 `VStack`이라 큰 글꼴이나 키보드에서 "만들기"가 시트 밖으로 밀렸다.
    var body: some View {
        ScrollView {
            fields
                .inkDismissesKeyboardOnTap()
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        // 키보드는 아래로 쓸어 내려 닫는다. 닫기 버튼을 따로 만들지 않는다.
        .scrollDismissesKeyboard(.interactively)
        .inkSheetActions { actions }
        .onAppear { isFocused = true }
    }

    private var fields: some View {
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
                ShardIcon(size: 16)
                Text(canAfford ? "\(price)조각을 써요" : "\(price)조각이 필요해요 (지금 \(balance)조각)")
                    .font(InkFont.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(canAfford ? PaperTheme.secondaryInk : PaperTheme.ink)

            // 부족할 때만 충전으로 가는 길을 낸다. 문구는 그대로 두고 CTA만 더한다.
            if !canAfford, let onBuyShards {
                Button("조각 채우기") { onBuyShards() }
                    .font(InkFont.body.weight(.semibold))
                    .foregroundStyle(PaperTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background {
                        UnevenRoundedRectangle.ink(15, 12, 16, 13)
                            .stroke(PaperTheme.ink, lineWidth: 1.6)
                    }
                    .buttonStyle(InkPressStyle())
                    .disabled(isGenerating)
                    .accessibilityIdentifier("buyShardsFromAI")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 조각을 쓰는 결정이다. 어떤 글꼴 크기에서도, 키보드가 올라와 있어도 눌릴 수 있어야 한다.
    private var actions: some View {
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
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}
