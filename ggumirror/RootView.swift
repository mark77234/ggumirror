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
    /// 조각 잔액. 서버가 정한 값을 보여주기만 한다.
    @State private var shards = ShardWallet.live
    /// 광고 흐름만 맡는다. 조각을 지급하지 않는다 — 지급은 서버가 SSV로 확인한 뒤에만 한다.
    @State private var rewardedAds = RewardedAdController()
    /// 광고 동의(UMP). 광고를 요청해도 되는지 정하는 유일한 근거다.
    @State private var adsConsent = AdsConsent.live
    /// AI 스티커. 쓸 수 있는지와 몇 조각인지를 **서버에서 받아온다** — 앱에 적지 않는다.
    @State private var aiStickers = AIStickerService.live
    /// 조각 충전. StoreKit 거래 수신은 앱 수명 동안 하나만 돈다.
    @State private var shardStore = ShardPurchaseController.live
    /// 상점 서버 상태. **하나만 둔다** — 화면마다 목록을 따로 받아오면
    /// 같은 상품의 좋아요 수가 화면마다 달라 보인다.
    @State private var marketplace = MarketplaceStore.live
    /// 내장 템플릿 다운로드 수. **서버가 센다.**
    @State private var catalogStats = CatalogStats.live
    /// 거울 보관 칸. **서버가 authority다** — 산 칸은 이 기기가 아니라 서버에 있다.
    @State private var mirrorCapacity = MirrorCapacityStore.live
    @Environment(\.scenePhase) private var scenePhase

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
            .environment(shards)
            .environment(rewardedAds)
            .environment(adsConsent)
            .environment(aiStickers)
            .environment(shardStore)
            .environment(marketplace)
            .environment(catalogStats)
            .environment(mirrorCapacity)
            // 잠금화면 Quick Mirror에서 "꾸미러 열기"로 들어온 경우.
            // 첫 화면이 이미 Mirror이므로 **화면을 옮기지 않는다** — 홈/상점으로 끌고 가지 않는다.
            .onContinueUserActivity(QuickMirrorActivity.openMirrorType) { _ in
                showMirrorScreen()
                quickMirror.refresh()
            }
            // 시스템이 capture extension 대신 본앱을 고른 경우(잠금 해제 상태).
            // 홈에 있었더라도 Mirror로 되돌린다.
            .onChange(of: quickMirrorRequest.token) { _, _ in
                showMirrorScreen()
            }
            // 로그인 / 로그아웃에 따라 지갑을 다시 읽거나 화면에서 지운다.
            // **서버 지갑은 그대로 있다** — 이 기기의 표시만 바뀐다.
            .onChange(of: session.server) { _, server in
                Task {
                    await shards.refresh(session: server)
                    // 산 보관 칸도 서버에 있다. 로그아웃하면 무료 기본값으로 돌아간다
                    // (서버 값은 그대로 남는다 — 이 기기의 표시만 바뀐다).
                    // **내 거울 서랍을 계정에 맞춘다.** 로그아웃하면 guest(비어 있음)로,
                    // 로그인하면 그 사용자 서랍으로 간다. 파일은 지우지 않는다.
                    let owner = MirrorLibraryOwner(userID: server?.userID)
                    library.activate(owner: owner)
                    // 스티커도 같은 서랍이다. EditorView가 쓰는 그 하나를 바꾼다.
                    StickerLibrary.live.activate(owner: owner)
                    if server == nil {
                        mirrorCapacity.clear(library: library)
                    } else {
                        await mirrorCapacity.refresh(session: server, library: library)
                    }
                    // **개인화 상태는 계정을 따라간다.** 공개 목록은 그대로 두고
                    // 좋아요 · 구매 · 판매 목록만 다시 맞춘다 — 로그아웃하면 비워진다.
                    //
                    // 공개 목록 `.task`는 정렬과 갈래로만 다시 도는지라, 상점 화면에
                    // 머문 채 로그아웃하면 **이전 계정의 하트가 채워진 채 남아 있었다.**
                    await marketplace.refreshMine(session: server)
                    await marketplace.refreshMyListings(session: server)
                    // 다음 사용자가 자기 내장 템플릿을 다시 맞춰 볼 수 있게 한다.
                    if server == nil { catalogStats.clear() }
                    // AI 스티커도 로그인 상태에 따라 켜지고 꺼진다. 로그아웃하면 CTA가 사라진다.
                    await aiStickers.refresh(session: server)
                    // 로그인 직후 광고를 미리 받아 둔다. 로그아웃하면 받지 않는다.
                    if server != nil, shards.remainingAdsToday > 0 {
                        await rewardedAds.prepare()
                    }
                    // 로그인이 준비되면 못 끝낸 결제를 되찾는다. 서버 멱등이라 여러 번 와도 한 번만 지급된다.
                    await shardStore.recoverUnfinished(session: server, wallet: shards)
                }
            }
            // 앱을 켜 둔 채 KST 자정을 넘겨도 다음 날 출석이 열린다.
            // 되돌아올 때 한 번 물어볼 뿐이고, 주기적으로 서버를 두드리지 않는다.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await shards.refresh(session: session.server) }
            }
            // 현재 거울이 바뀌면(다른 거울 선택 · 꾸미기 저장) 잠금화면 프레임도 따라간다.
            // 사용자가 "동기화"를 누를 일은 없다.
            .onChange(of: library.currentMirror) { _, mirror in
                Task { await QuickMirrorSync.update(for: mirror) }
            }
            .task {
                // 첫 화면은 언제나 Mirror다. 로그인 확인은 화면이 뜬 뒤 비동기로 하고,
                // 결과가 무엇이든 Mirror 진입을 막지 않는다.
                // ── 거울에 필요한 것만 여기서 한다. 짧고 network가 아니다. ──
                session.watchRevocation()
                // 공유하다 앱이 죽으면 임시 파일이 남는다. 시작할 때 한 번 치운다.
                ExportedFile.cleanUpLeftovers()
                // 잠금화면에서 찍은 사진이 있으면 여기서 알게 된다.
                quickMirror.refresh()

                // ── 나머지는 **거울과 독립**이다. ──
                //
                // 예전에는 이 전부가 하나의 `await` 체인이었다: 세션 → 지갑 → AI config →
                // UMP 동의 → 광고 preload → StoreKit 복구. 앞이 느리면 뒤가 전부 밀리고,
                // 그 사이 화면은 이미 거울이라 사용자는 "왜 안 눌리지"를 겪는다.
                //
                // 이제 **서로 기다리지 않는다.** 하나가 느리거나 실패해도 나머지가 진행되고,
                // 무엇도 거울 조작을 막지 않는다. 순서에 의존하는 것만 한 갈래로 묶는다.
                Task { await session.refreshCredentialState() }
                Task { await QuickMirrorSync.update(for: library.currentMirror) }
                Task {
                    // 세션 확인 → 그 결과로 지갑/AI/복구. 이 셋은 순서가 의미 있다.
                    await session.refreshServerSession()
                    // **세션이 확정된 뒤에 서랍을 연다.** `onChange`만 믿으면 시작할 때
                    // 이미 복구돼 있던 세션에서는 변화가 없어 guest로 남는다.
                    let owner = MirrorLibraryOwner(userID: session.server?.userID)
                    library.activate(owner: owner)
                    // 스티커도 같은 서랍이다. EditorView가 쓰는 그 하나를 바꾼다.
                    StickerLibrary.live.activate(owner: owner)
                    await mirrorCapacity.refresh(session: session.server, library: library)
                    await shards.refresh(session: session.server)
                    await aiStickers.refresh(session: session.server)
                    // StoreKit 거래 수신은 **한 번만** 시작한다(내부에서 보장).
                    shardStore.startListening(session: { session.server }, wallet: shards)
                    // 못 끝낸 결제 되찾기. 서버 멱등이라 여러 번 와도 한 번만 지급된다.
                    // **상품 조회(`Product.products`)는 여기서 하지 않는다** —
                    // 조각 상점을 열 때만 한다(거울 시작을 StoreKit에 묶지 않는다).
                    await shardStore.recoverUnfinished(session: session.server, wallet: shards)
                }
                Task {
                    // 광고는 가장 무겁고(UMP 양식 · SDK 초기화 · ad load) 가장 덜 급하다.
                    // 별도 갈래라 이게 느려도 지갑·AI·결제 복구가 기다리지 않는다.
                    await adsConsent.bootstrap()
                    rewardedAds.consentChanged(canRequestAds: adsConsent.canRequestAds)
                    if session.server != nil, shards.remainingAdsToday > 0 {
                        await rewardedAds.prepare()
                    }
                }
            }
    }

    /// 거울 화면으로 보낸다. **이미 거울이면 아무것도 쓰지 않는다.**
    ///
    /// 잠금화면 촬영 inbox와 Quick Mirror intent가 **같은 frame에 함께** 도착할 수 있고,
    /// 그때 `screen`을 두 번 쓰면 SwiftUI가
    /// "onChange(of: Int) action tried to update multiple times per frame"으로 경고한다
    /// (`QuickMirrorRequest.token`이 Int counter다). 중복 write 자체를 없앤다.
    private func showMirrorScreen() {
        guard screen != .mirror else { return }
        screen = .mirror
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .mirror:
            MirrorView(library: library, onGoHome: { screen = .home })
        case .home:
            HomeView(
                library: library,
                onOpenMirror: { showMirrorScreen() },
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
