//
//  SettingsView.swift
//  ggumirror
//
//  navigation placeholder. 실제 설정 항목은 다음 Phase에서.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        ComingSoonView(title: "설정", detail: "알림, 계정 같은 설정이 여기에 들어와요.")
            .paperBackground()
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
