//
//  SignInRequiredDialog.swift
//  ggumirror
//
//  로그인이 필요한 동작을 눌렀을 때 하는 말. **한 곳에서만 한다.**
//
//  상점 구경 자체에는 로그인 벽이 없다(Core Product Policy). 좋아요 · 구매 · 받기 ·
//  판매 관리처럼 **서버에 사람이 필요한 동작**을 누를 때만 이 창이 뜬다.
//
//  `AuthSession.requireSignIn(for:)`이 예전부터 `pendingAction`을 세워 두었는데
//  **그 값을 보는 곳이 아무데도 없었다** — 눌러도 아무 일이 없었다는 뜻이다.
//  새 auth 체계를 만들지 않고 그 값을 화면에 잇는다.
//
//  서버 요청을 먼저 보내 401을 받고 나서 안내하지 않는다. 로그인하지 않은 것은
//  **이미 아는 사실**이라 요청 없이 바로 말한다(경제 요청이 새어 나가지도 않는다).
//

import SwiftUI

extension View {
    /// - Parameter onSignIn: `로그인`을 눌렀을 때. 기존 Apple 로그인 화면으로 보낸다 —
    ///   **두 번째 auth flow를 만들지 않는다.**
    ///
    /// 로그인에 성공해도 누르려던 경제 동작을 **자동으로 실행하지 않는다.**
    /// 사용자가 다시 고른다.
    func inkSignInRequiredDialog(onSignIn: @escaping () -> Void) -> some View {
        modifier(SignInRequiredDialog(onSignIn: onSignIn))
    }
}

private struct SignInRequiredDialog: ViewModifier {
    let onSignIn: () -> Void

    @Environment(AuthSession.self) private var session: AuthSession?

    private var isPresented: Binding<Bool> {
        Binding(
            get: { session?.pendingAction != nil },
            set: { if !$0 { session?.clearPendingAction() } }
        )
    }

    func body(content: Content) -> some View {
        content.inkDialog(
            "로그인이 필요해요",
            message: "이 기능을 사용하려면 Apple로 로그인해 주세요.",
            isPresented: isPresented
        ) {
            [
                InkDialogAction("취소"),
                InkDialogAction("로그인", role: .primary) { onSignIn() },
            ]
        }
    }
}
