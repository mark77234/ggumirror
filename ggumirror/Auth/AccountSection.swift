//
//  AccountSection.swift
//  ggumirror
//
//  설정의 계정 칸.
//
//  로그인 버튼만은 Apple 공식 control(`SignInWithAppleButton`)을 그대로 쓴다 —
//  손그림으로 흉내 내는 것은 Apple 지침 위반이고, 사용자도 못 알아본다.
//  버튼 **바깥**의 카드 / 설명 / 줄만 종이·잉크 스타일이다.
//

import AuthenticationServices
import SwiftUI

struct AccountSection: View {
    let session: AuthSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("계정")
                .font(InkFont.sectionTitle)
                .foregroundStyle(PaperTheme.ink)

            InkCard(tilt: -0.2) {
                switch session.state {
                case .signedOut: signedOut
                case .signedIn(let identity): signedIn(identity)
                }
            }
        }
        .inkDialog(
            "로그인하지 못했어요",
            message: session.failureMessage,
            isPresented: Binding(
                get: { session.failureMessage != nil },
                set: { if !$0 { session.failureMessage = nil } }
            )
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
    }

    // MARK: - 로그아웃 상태

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("꾸미기 · 조각 충전 · 상점에서 사기는 로그인 없이 쓸 수 있어요.")
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            // **사는 데는 계정이 필요 없다.** 계정이 필요한 것은 판매자 신원처럼
            // 정말로 사람에 묶이는 일뿐이다. 로그인하면 지금 지갑을 그대로 가져간다.
            Text("상점에 거울을 올려 팔거나 판매를 관리할 때 계정이 필요해요. 로그인해도 지금 갖고 있는 조각은 그대로 이어져요.")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            SignInWithAppleButton(.signIn) { request in
                // 사용자가 직접 버튼을 눌렀을 때만 요청한다. 둘 다 nil로 와도 정상이다.
                request.requestedScopes = [.fullName, .email]
                // 이 시도에만 쓰는 nonce. Apple에는 해시만 가고 원본은 서버 검증용으로 남는다.
                request.nonce = session.beginSignIn()
            } onCompletion: { result in
                // Apple UI 통과가 곧 로그인은 아니다 — 서버가 token을 검증해야 끝난다.
                Task { await session.complete(AppleSignInOutcome(result)) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .accessibilityIdentifier("signInWithApple")
        }
    }

    // MARK: - 로그인 상태

    private func signedIn(_ identity: AppleIdentity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                InkAvatar(size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(identity.accountLabel)
                        .font(InkFont.cardTitle)
                        .foregroundStyle(PaperTheme.ink)
                        .lineLimit(1)

                    if let email = identity.email {
                        Text(email)
                            .font(InkFont.caption)
                            .foregroundStyle(PaperTheme.secondaryInk)
                            .lineLimit(1)
                    }

                    Text("Apple 계정으로 로그인됨")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                }
            }

            InkSeparator()

            Button {
                Task { await session.signOut() }
            } label: {
                Text("로그아웃")
                    .font(InkFont.button)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
                .tint(PaperTheme.ink)
                .accessibilityIdentifier("signOut")
        }
    }
}

#Preview("로그아웃") {
    NavigationStack {
        AccountSection(session: AuthSession(store: InMemoryIdentityStore(), sessions: InMemoryServerSessionStore()))
            .padding(20)
            .paperBackground()
    }
}

#Preview("로그인됨") {
    NavigationStack {
        AccountSection(
            session: AuthSession(
                store: InMemoryIdentityStore(
                    AppleIdentity(userID: "preview", displayName: "병찬", email: "mirror@example.com")
                ),
                sessions: InMemoryServerSessionStore(
                    ServerSession(
                        accessToken: "preview",
                        expiresAt: .now.addingTimeInterval(86_400),
                        userID: "preview-user"
                    )
                )
            )
        )
        .padding(20)
        .paperBackground()
    }
}
