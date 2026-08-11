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
    /// 앱 전체가 쓰는 단 하나의 거울 목록. 시작할 때 기기에서 읽어 온다.
    @State private var library = MirrorLibrary.live
    /// 앱 전체가 쓰는 단 하나의 로그인 상태. 거울 목록과 서로 아무 관계도 없다.
    @State private var session = AuthSession.live
    @State private var editing: EditorRequest?

    /// Editor를 열 때 필요한 것: 무엇을 편집할지 + 어떤 의도로 들어왔는지.
    struct EditorRequest: Identifiable {
        let id = UUID()
        let design: MirrorDesign
        let context: MirrorEditorContext
    }

    private enum Screen {
        case mirror
        case home
    }

    var body: some View {
        // ZStack은 화면이 바뀌어도 정체성이 유지된다 — 아래 task가 매번 다시 돌지 않는다.
        ZStack { content }
            .environment(session)
            .task {
                // 첫 화면은 언제나 Mirror다. 로그인 확인은 화면이 뜬 뒤 비동기로 하고,
                // 결과가 무엇이든 Mirror 진입을 막지 않는다.
                session.watchRevocation()
                await session.refreshCredentialState()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .mirror:
            MirrorView(library: library, onGoHome: { screen = .home })
        case .home:
            HomeView(
                library: library,
                onOpenMirror: { screen = .mirror },
                onEdit: { editing = $0 }
            )
            .fullScreenCover(item: $editing) { request in
                EditorView(
                    design: request.design,
                    library: library,
                    context: request.context,
                    onSaved: { editing = nil }
                )
            }
        }
    }
}

#Preview {
    RootView()
}
