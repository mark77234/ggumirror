//
//  MirrorStorageFullDialog.swift
//  ggumirror
//
//  보관 공간이 가득 찼을 때 하는 말과, 조각으로 늘리는 흐름.
//  **화면마다 다르게 만들지 않는다.**
//
//  거울이 늘어나는 길은 셋이다 — 만들기 · 내장 템플릿 받기 · 상점에서 받기.
//  한 곳만 막으면 나머지로 계속 늘어나므로 셋 다 같은 문을 지나고,
//  그 문에서 바로 공간을 늘릴 수 있다(별도 시트를 새로 만들지 않는다).
//
//  가격과 칸 수는 **서버가 알려준 값**이다. 앱에 `10`과 `5`를 적어 두지 않는다.
//

import SwiftUI

extension View {
    /// - Parameters:
    ///   - action: `"만들려면"` · `"저장하려면"` · `"받으려면"`처럼 이 화면의 동작.
    ///   - isPresented: `가득 찼어요` 안내를 띄울지.
    ///   - isConfirmingExpansion: 확인 창을 **밖에서도** 열 수 있는 통로.
    ///     `내 거울`의 `+칸 늘리기` 버튼이 쓴다. 없으면 안내에서만 연다.
    func inkMirrorStorageFullDialog(
        _ action: String,
        isPresented: Binding<Bool>,
        library: MirrorLibrary?,
        isConfirmingExpansion: Binding<Bool>? = nil
    ) -> some View {
        modifier(
            MirrorStorageExpansion(
                action: action,
                isShowingFull: isPresented,
                library: library,
                externalConfirm: isConfirmingExpansion
            )
        )
    }
}

private struct MirrorStorageExpansion: ViewModifier {
    let action: String
    @Binding var isShowingFull: Bool
    /// 늘어난 칸을 옮겨 적을 곳. 화면이 쓰는 그 라이브러리다 — 전역을 몰래 잡지 않는다.
    var library: MirrorLibrary?
    var externalConfirm: Binding<Bool>?

    // **optional로 읽는다.** 이 modifier는 Editor · 상점 상세에도 붙는데, 그 화면들을
    // 따로 그리는 곳(테스트 · 미리보기)에는 이 환경값이 없다. 필수로 읽으면 그 자리에서
    // 죽는다 — 실제로 테스트 절반이 그렇게 무너졌다.
    @Environment(MirrorCapacityStore.self) private var capacity: MirrorCapacityStore?
    @Environment(AuthSession.self) private var session: AuthSession?
    @Environment(ShardWallet.self) private var shards: ShardWallet?

    @State private var ownConfirm = false
    @State private var notice: String?

    /// 밖에서 준 통로가 있으면 그것을, 없으면 내 것을 쓴다.
    private var isConfirming: Binding<Bool> { externalConfirm ?? $ownConfirm }

    /// 살 수 있는 상품이 있을 때만 CTA를 만든다.
    /// 로그인 전이거나 서버를 못 읽었으면 **누를 수 없는 버튼을 두지 않는다.**
    private var pack: MirrorSlotPack? { capacity?.pack }

    func body(content: Content) -> some View {
        content
            .inkDialog(
                "거울 보관 공간이 가득 찼어요",
                message: "거울을 \(action) 기존 거울을 삭제하거나 보관 공간을 늘려 주세요.",
                isPresented: $isShowingFull
            ) {
                var actions = [InkDialogAction("취소")]
                if pack != nil {
                    actions.append(
                        InkDialogAction("공간 늘리기", role: .primary) {
                            isConfirming.wrappedValue = true
                        }
                    )
                }
                return actions
            }
            // 되돌릴 수 없는 조각 사용이라 반드시 확인을 받는다.
            .inkDialog(
                "거울 보관 공간을 늘릴까요?",
                message: pack.map {
                    """
                    \($0.costShards)조각을 사용해 보관 공간을 \($0.slotDelta)칸 늘려요.
                    늘어난 공간은 계속 사용할 수 있어요.
                    """
                },
                isPresented: isConfirming
            ) {
                var actions = [InkDialogAction("취소")]
                if let pack {
                    actions.append(
                        InkDialogAction("\(pack.costShards)조각 사용하기", role: .primary) {
                            Task { await expand() }
                        }
                    )
                }
                return actions
            }
            .inkDialog(
                "보관 공간",
                message: notice,
                isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
            ) {
                [InkDialogAction("확인", role: .primary)]
            }
    }

    /// **client가 잔액도 칸도 계산하지 않는다** — 서버 응답을 옮겨 적기만 한다.
    private func expand() async {
        guard let capacity else { return }
        switch await capacity.purchase(
            session: session?.server, wallet: shards, library: library
        ) {
        case .purchased(let result):
            notice = """
                보관 공간이 \(result.effectiveSlots)칸이 됐어요.
                남은 조각 \(result.balance)개.
                """
        case .alreadyApplied(let result):
            // 응답을 잃었던 요청이 이미 처리돼 있었다. 오류가 아니다.
            notice = "보관 공간은 이미 \(result.effectiveSlots)칸이에요."
        case .insufficientShards:
            notice = pack.map {
                "조각이 부족해요. 보관 공간을 늘리려면 \($0.costShards)조각이 필요해요."
            } ?? "조각이 부족해요."
        case .needsSignIn:
            _ = session?.requireSignIn(for: .shardTransaction)
        case .failed(let message):
            notice = message
        }
    }
}
