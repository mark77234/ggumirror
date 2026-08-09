//
//  SettingsView.swift
//  ggumirror
//
//  Phase 1-5에서는 navigation placeholder까지만.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        ZStack {
            PaperBackground()
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Text("설정")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(PaperTheme.ink)
                Text("준비 중이에요")
                    .font(.system(size: 15))
                    .foregroundStyle(PaperTheme.muted)
            }
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
