//
//  MirrorStorageFullDialog.swift
//  ggumirror
//
//  보관 공간이 가득 찼을 때 하는 말. 화면마다 다르게 만들지 않는다.
//
//  거울이 늘어나는 길은 셋이다 — 만들기 · 내장 템플릿 받기 · 상점에서 받기.
//  한 곳만 막으면 나머지로 계속 늘어나므로 셋 다 같은 문을 지난다.
//

import SwiftUI

extension View {
    /// - Parameter action: `"만들려면"` · `"저장하려면"` · `"받으려면"`처럼 이 화면의 동작.
    ///
    /// **가격을 적지 않는다.** 확장 가격이 아직 정해지지 않았고,
    /// 임의 숫자로 조각을 차감하는 버튼을 만들지 않는다.
    func inkMirrorStorageFullDialog(_ action: String, isPresented: Binding<Bool>) -> some View {
        inkDialog(
            "거울 보관 공간이 가득 찼어요",
            message: "거울을 \(action) 보관 공간을 늘려주세요. 보관 공간 확장은 준비 중이에요.",
            isPresented: isPresented
        ) {
            [
                InkDialogAction("취소"),
                InkDialogAction("보관 공간 늘리기", role: .primary),
            ]
        }
    }
}
