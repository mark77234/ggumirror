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
    /// 아직 persistence가 없어 앱이 살아 있는 동안만 유지되는 로컬 데이터.
    @State private var library = MirrorLibrary()
    @State private var editing: MyMirror?

    private enum Screen {
        case mirror
        case home
    }

    var body: some View {
        switch screen {
        case .mirror:
            MirrorView(library: library, onGoHome: { screen = .home })
        case .home:
            HomeView(
                library: library,
                onOpenMirror: { screen = .mirror },
                onEditMirror: { editing = $0 }
            )
            .fullScreenCover(item: $editing) { mirror in
                EditorView(
                    design: MirrorDesign(mirror: mirror),
                    library: library,
                    onSaved: { editing = nil }
                )
            }
        }
    }
}

#Preview {
    RootView()
}
