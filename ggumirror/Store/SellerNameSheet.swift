//
//  SellerNameSheet.swift
//  ggumirror
//
//  상점에 올리기 전에 **판매자 이름을 정한다.**
//
//  상품 카드에는 판매자 이름이 보인다. 비어 있으면 사는 사람은 누가 올린 것인지
//  알 수 없고, 판매자도 자기 상품을 남의 것과 구분할 수 없다. 그래서 등록 앞에
//  이 한 걸음을 둔다 — 나중에 정하라고 하면 대부분 정하지 않는다.
//
//  **Apple 계정 이름이 아니다.** 꾸미러 안에서 쓰는 판매자 표시 이름이고,
//  이름의 authority는 서버다(`ProfileSession` → `PATCH /users/me/profile`).
//  겹치는 이름은 서버 transaction이 거절한다 — 화면이 "찾아보니 없더라"로 정하지 않는다.
//

import SwiftUI

struct SellerNameSheet: View {
    @Environment(ProfileSession.self) private var profile: ProfileSession?
    @Environment(AuthSession.self) private var session
    @Environment(\.inkModalDismiss) private var dismiss

    @State private var name = ""
    @State private var problem: String?
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmed.isEmpty && profile?.isSaving != true }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("사용자 이름을 정해 주세요")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)

            Text("상점에 등록하려면 사용자 이름이 필요해요.\n올린 상품에 이 이름이 보여요.")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            TextField(DisplayNamePolicy.placeholder, text: $name)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { Task { await save() } }
                .onChange(of: name) { _, value in
                    // 길이 규칙은 **기존 정책 하나**에서 온다. 새 숫자를 적지 않는다.
                    if value.count > DisplayNamePolicy.maxLength {
                        name = String(value.prefix(DisplayNamePolicy.maxLength))
                    }
                    problem = nil
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(minHeight: 44)
                .background {
                    let shape = UnevenRoundedRectangle.ink(15, 18, 19, 14)
                    shape.fill(PaperTheme.subtleSurface)
                        .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.8))
                }

            // **막힌 이유를 말한다.** `오류가 발생했어요`로 숨기지 않는다.
            if let problem {
                Text(problem)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("한 번 정하면 30일에 한 번 바꿀 수 있어요.")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)

            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Text("나중에")
                        .font(InkFont.body)
                        .foregroundStyle(PaperTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background {
                            UnevenRoundedRectangle.ink(15, 12, 16, 13)
                                .stroke(PaperTheme.ink, lineWidth: 1.6)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())

                Button { Task { await save() } } label: {
                    Text(profile?.isSaving == true ? "저장하는 중…" : "저장")
                        .font(InkFont.body.weight(.semibold))
                        .foregroundStyle(PaperTheme.subtleSurface)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background {
                            UnevenRoundedRectangle.ink(15, 12, 16, 13)
                                .fill(canSave ? PaperTheme.ink : PaperTheme.disabled)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { isFocused = true }
    }

    /// **서버가 받아 준 뒤에만** 닫는다. 저장되지 않은 이름을 정해진 것처럼 두지 않는다.
    private func save() async {
        guard canSave else { return }
        if let failure = await profile?.setDisplayName(name, session: session.server) {
            problem = failure
            return
        }
        dismiss()
    }
}
