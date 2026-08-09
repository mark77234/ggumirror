//
//  ComingSoonView.swift
//  ggumirror
//
//  아직 만들지 않은 화면의 자리. 기능은 다음 Phase에서 붙인다.
//

import SwiftUI

struct ComingSoonView: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(InkFont.pageTitle)
                .foregroundStyle(PaperTheme.ink)
            Text(detail)
                .font(InkFont.secondary)
                .foregroundStyle(PaperTheme.secondaryInk)
                .multilineTextAlignment(.center)
            Text("준비 중이에요")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    UnevenRoundedRectangle.ink(14, 12, 15, 13)
                        .stroke(PaperTheme.separator, lineWidth: 1.4)
                }
                .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ComingSoonView(title: "상점", detail: "곧 거울 디자인을 둘러볼 수 있어요.")
        .paperBackground()
}
