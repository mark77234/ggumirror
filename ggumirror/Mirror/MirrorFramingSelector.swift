//
//  MirrorFramingSelector.swift
//  ggumirror
//
//  `넓게` / `채우기` 칩 한 줄.
//
//  **실제 Mirror Camera와 상점 미리보기가 이것 하나를 공유한다.** 예전에는
//  `MirrorControls` 안에 private으로 있었고, 미리보기에 같은 것이 필요해졌다 —
//  두 번째 사본을 만들면 두 화면의 생김새와 tap 규칙이 반드시 갈라진다.
//
//  자르는 방법의 authority는 여기가 아니라 `MirrorCamera.Framing`이다.
//  이 파일에는 비율 계산이 **없다** — 무엇을 고를 수 있는지 그리기만 한다.
//

import SwiftUI

struct MirrorFramingSelector: View {
    let options: [MirrorCamera.Framing]
    let selected: MirrorCamera.Framing
    /// 고르기 전에 부른다. 실제 거울에서는 auto-hide 타이머를 다시 돌리는 데 쓴다.
    var onInteraction: () -> Void = {}
    let onSelect: (MirrorCamera.Framing) -> Void

    var body: some View {
        // 고를 것이 하나뿐이면 아무것도 그리지 않는다 — 누를 수 없는 버튼을 두지 않는다.
        if options.count > 1 {
            HStack(spacing: 4) {
                ForEach(options, id: \.self) { chip($0) }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(Color(white: 0.11).opacity(0.5), in: .capsule)
        }
    }

    private func chip(_ option: MirrorCamera.Framing) -> some View {
        let isSelected = selected == option
        return Button {
            onInteraction()
            onSelect(option)
        } label: {
            Text(option.title)
                .font(InkFont.caption)
                .foregroundStyle(isSelected ? Color(white: 0.11) : .white)
                .padding(.horizontal, 10)
                // 배율 칩과 같은 규칙 — 글자는 작아도 닿는 자리는 44pt다.
                .frame(minHeight: InkTapTarget.minimum)
                .background(alignment: .center) {
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.92) : .clear)
                        .frame(height: 34)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.accessibilityTitle)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
