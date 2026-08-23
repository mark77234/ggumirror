//
//  InkButtons.swift
//  ggumirror
//
//  **보이는 만큼 눌린다.**
//
//  실기기에서 `저장`이 글자를 정확히 눌러야만 반응했다. 테두리와 여백은 보이는데
//  그 자리는 죽어 있었다. 원인은 SwiftUI의 규칙 하나다 —
//  **Button의 tap 영역은 label이 정한다.** 밖에 붙인 `.padding` · `.background` ·
//  `.frame`은 보이기만 하고 눌리지 않는다. 밖에서 `.contentShape`을 걸어도 그렇다.
//
//      Button("저장") { save() }          ← 글자만 눌린다
//          .frame(minHeight: 44)
//          .background { 테두리 }
//
//  그래서 **꾸미러의 잉크 버튼은 겉모습을 label 안에서 만든다.** 화면마다 여백을
//  덧붙여 고치지 않는다 — 그러면 다음 버튼에서 같은 일이 또 생긴다.
//

import SwiftUI

/// 손이 닿아야 하는 최소 크기. 잉크 버튼 전부가 이 값을 지킨다.
enum InkTapTarget {
    static let minimum: CGFloat = 44
}

/// 글자만 있는 버튼(도구 막대의 `취소` · `저장` · `완료`).
///
/// 글자는 작아도 **44pt가 실제로 눌린다.** 예전에는 그 44pt가 Button 밖에 있어서
/// 이름만 tap target이었다.
struct InkTextButton: View {
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(InkFont.button)
                .foregroundStyle(PaperTheme.ink)
                .frame(minHeight: InkTapTarget.minimum)
                // label 안이라 **이 모양 전체가** Button의 tap 영역이 된다.
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
    }
}

/// 테두리가 보이는 버튼. 시트의 주 동작과 목록의 작은 동작이 함께 쓴다.
///
/// `fillsWidth`가 참이면 가로를 꽉 채운다(시트 하단 CTA), 아니면 내용만큼이다(칩).
struct InkOutlineButton: View {
    let title: String
    var fillsWidth = true
    var isProminent = false
    let action: () -> Void

    init(
        _ title: String,
        fillsWidth: Bool = true,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.fillsWidth = fillsWidth
        self.isProminent = isProminent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(InkFont.button)
                .foregroundStyle(isProminent ? PaperTheme.paper : PaperTheme.ink)
                .padding(.horizontal, 14)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .frame(minHeight: InkTapTarget.minimum)
                .background {
                    let shape = UnevenRoundedRectangle.ink(16, 13, 17, 12)
                    if isProminent {
                        shape.fill(PaperTheme.ink)
                    } else {
                        shape.stroke(PaperTheme.ink, lineWidth: InkLine.regular)
                    }
                }
                // **겉모습 전체가 tap 영역이다.** 이 줄이 label 밖으로 나가면 안 된다.
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
    }
}
