//
//  InkKeyboard.swift
//  ggumirror
//
//  키보드를 닫는 공통 방법. 화면마다 다르게 만들지 않는다.
//
//  실기기에서: 제목을 입력하고 나면 키보드가 화면 절반을 덮은 채 남았다. 스크롤해도
//  안 닫히고, 빈 곳을 눌러도 안 닫혀서 등록 버튼까지 갈 방법이 없었다.
//

import SwiftUI
import UIKit

extension View {
    /// 빈 곳을 누르면 키보드가 닫힌다.
    ///
    /// **입력 칸과 버튼 위에서는 반응하지 않는다** — 이 층은 내용 뒤에 깔리므로
    /// 그 위의 요소가 탭을 먼저 가져간다. 앞에 겹치거나 `simultaneousGesture`로
    /// 붙이면 칸을 누르는 순간 방금 올라온 키보드를 도로 내리는 경주가 생긴다.
    ///
    /// 스크롤로 닫는 것은 native `.scrollDismissesKeyboard(.interactively)`가 한다.
    /// 둘은 서로 다른 동작이라 한쪽이 다른 쪽을 대신하지 않는다.
    func inkDismissesKeyboardOnTap() -> some View {
        background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { InkKeyboard.dismiss() }
                .accessibilityHidden(true)
        }
    }
}

enum InkKeyboard {
    /// 지금 입력 중인 곳이 어디든 닫는다. 화면이 `@FocusState`를 들고 있지 않아도 된다.
    @MainActor
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }
}
