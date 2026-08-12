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
    /// 잠금화면 Quick Mirror가 찍은 사진을 받는 곳. 첫 화면을 막지 않는다.
    @State private var quickMirror = QuickMirrorInbox()
    /// 잠금이 풀린 상태에서 control을 눌러 **본앱**이 열린 경우의 신호.
    @State private var quickMirrorRequest = QuickMirrorRequest.shared

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
            // 잠금화면 Quick Mirror에서 "꾸미러 열기"로 들어온 경우.
            // 첫 화면이 이미 Mirror이므로 **화면을 옮기지 않는다** — 홈/상점으로 끌고 가지 않는다.
            .onContinueUserActivity(QuickMirrorActivity.openMirrorType) { _ in
                screen = .mirror
                quickMirror.refresh()
            }
            // 시스템이 capture extension 대신 본앱을 고른 경우(잠금 해제 상태).
            // 홈에 있었더라도 Mirror로 되돌린다.
            .onChange(of: quickMirrorRequest.token) { _, _ in
                screen = .mirror
            }
            // 현재 거울이 바뀌면(다른 거울 선택 · 꾸미기 저장) 잠금화면 프레임도 따라간다.
            // 사용자가 "동기화"를 누를 일은 없다.
            .onChange(of: library.currentMirror) { _, mirror in
                Task { await QuickMirrorSync.update(for: mirror) }
            }
            .task {
                // 첫 화면은 언제나 Mirror다. 로그인 확인은 화면이 뜬 뒤 비동기로 하고,
                // 결과가 무엇이든 Mirror 진입을 막지 않는다.
                session.watchRevocation()
                await session.refreshCredentialState()
                // 저장된 서버 세션이 아직 살아 있는지 확인한다. 실패해도 화면을 막지 않는다.
                await session.refreshServerSession()
                // 잠금화면에서 찍은 사진이 있으면 여기서 알게 된다.
                quickMirror.refresh()
                // 잠금화면 Quick Mirror가 쓸 프레임을 등록한다. 실패해도 앱은 그대로다.
                await QuickMirrorSync.update(for: library.currentMirror)
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
