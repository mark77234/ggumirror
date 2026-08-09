//
//  RootView.swift
//  ggumirror
//
//  Mirror ↔ Home 라우팅. 첫 화면은 항상 Mirror다.
//  Mirror는 immersive full-screen이라 Tab Bar를 두지 않는다.
//

import SwiftUI

struct RootView: View {
    @State private var screen: Screen = .mirror

    private enum Screen {
        case mirror
        case home
    }

    var body: some View {
        switch screen {
        case .mirror:
            MirrorView(onGoHome: { screen = .home })
        case .home:
            HomeView(onOpenMirror: { screen = .mirror })
        }
    }
}

#Preview {
    RootView()
}
