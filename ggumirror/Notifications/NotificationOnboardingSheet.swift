//
//  NotificationOnboardingSheet.swift
//  ggumirror
//
//  시스템 권한 창 **앞에** 나오는 우리 화면.
//
//  `알림 받기`를 누른 사람에게만 시스템 창이 뜬다. `나중에`는 아무것도 부르지
//  않는다 — 여기서 시스템 창을 띄우면 설명한 의미가 없다.
//

import SwiftUI

struct NotificationOnboardingSheet: View {
    let onAllow: () async -> Void
    let onLater: () -> Void

    @Environment(\.inkModalDismiss) private var dismiss
    @State private var isAsking = false

    private let benefits = [
        "내 거울이 판매되면 바로 알려드려요",
        "새로운 거울 소식을 받아볼 수 있어요",
        "꾸미러를 다시 둘러볼 만한 소식도 알려드려요",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("꾸미러 소식을 받아볼까요?")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(benefits, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(InkFont.body)
                            .foregroundStyle(PaperTheme.secondaryInk)
                        Text(line)
                            .font(InkFont.body)
                            .foregroundStyle(PaperTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("알림 설정은 나중에 언제든 변경할 수 있어요.")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)

            VStack(spacing: 10) {
                Button {
                    // **여기서만** 시스템 창이 뜬다.
                    isAsking = true
                    Task {
                        await onAllow()
                        isAsking = false
                        dismiss()
                    }
                } label: {
                    Text("알림 받기")
                        .font(InkFont.body.weight(.semibold))
                        .foregroundStyle(PaperTheme.subtleSurface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .frame(minHeight: InkTapTarget.minimum)
                        .background {
                            UnevenRoundedRectangle.ink(18, 22, 23, 17).fill(PaperTheme.ink)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())
                .disabled(isAsking)

                Button {
                    // 시스템 창을 부르지 않는다. 설정에서 언제든 켤 수 있다.
                    onLater()
                    dismiss()
                } label: {
                    Text("나중에")
                        .font(InkFont.body)
                        .foregroundStyle(PaperTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .frame(minHeight: InkTapTarget.minimum)
                        .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())
                .disabled(isAsking)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
