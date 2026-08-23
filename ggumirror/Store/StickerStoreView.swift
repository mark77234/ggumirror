//
//  StickerStoreView.swift
//  ggumirror
//
//  상점의 **스티커** 칸. 세 부분이다.
//
//  1. 스티커 만들기 (V-5A Creator로 들어간다)
//  2. 내 스티커 — `StickerLibrary`가 유일한 진실이다. 가짜 배열을 만들지 않는다
//  3. 스티커 상점 — 서버가 없으므로 **정직하게 빈 상태**다. 가짜 판매자 / 가짜 listing을 만들지 않는다
//
//  로그인 없이 전부 쓸 수 있다. 로그인 wall을 만들지 않는다.
//

import SwiftUI

struct StickerStoreView: View {
    var library: StickerLibrary
    /// 거울 라이브러리는 스티커를 거울에 바로 적용하는 데 쓰인다(이번 Phase에서는 안내만).
    var mirrors: MirrorLibrary?

    @State private var actionTarget: StickerProject?
    @State private var creatorRequest: StickerCreatorRequest?
    /// 다이얼로그가 닫히면 Creator를 연다. 둘을 같은 순간에 갈아 끼우지 않는다.
    @State private var pendingCreatorRequest: StickerCreatorRequest?
    @State private var publishTarget: StickerProject?
    @State private var isChoosingStart = false
    @State private var notice: String?
    /// 상점에 들어오면 언제나 최신 순이다. 거울 상점과 같은 규칙·같은 enum이다.
    @State private var sort: StoreSort = .default
    @Environment(MarketplaceStore.self) private var store
    @Environment(AuthSession.self) private var session
    @Environment(ShardWallet.self) private var wallet
    /// 고른 사용자 상품. 상세는 sheet로 띄운다 — 스티커 상점은 상점 탭 안쪽
    /// 화면이라 자기 NavigationStack이 없다.
    @State private var selected: MarketplaceListing?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// **자기 ScrollView를 갖지 않는다.** 상점 탭의 단일 scroll 안에 들어가므로
    /// 여기서 또 감싸면 세로 scroll이 중첩되고, 상단 제어부가 함께 밀려 올라가지 않는다.
    /// scroll · scrollIndicators · contentMargins는 `StoreView`가 한 곳에서 소유한다.
    var body: some View {
        content
            // **공개 목록은 여기서 받아온다.** 상품 구획 안에 두면 목록이 비었을 때
            // 그 view가 그려지지 않아 영원히 요청이 나가지 않는다.
            .task(id: "sticker-\(sort.rawValue)-\(store.publicFeedVersion)") {
                await store.refresh(
                    contentType: "sticker", sort: sort, session: session.server
                )
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
                createButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)

                sectionTitle("내 스티커", count: library.projects.count)
                if library.projects.isEmpty {
                    emptyStickers
                } else {
                    grid
                }

                // **판매자 관리는 여기 없다.** 상점의 `내 판매` 탭으로 갔다 —
                // 공개 목록에 draft가 섞이면 무엇이 팔리는 중인지 알 수 없다.
                sectionTitle("스티커 상점", count: nil)
                    .padding(.top, 26)
                // **상품이 0개여도 정렬 UI를 보여준다** — 거울 상점과 같은 세 가지다.
                // 실제 listing이 들어오면 같은 `StoreSort`가 그대로 목록에 걸린다.
                InkFilterBar(items: StoreSort.allCases, selection: $sort) { $0.label }
                    .padding(.bottom, 12)
                marketplace
            }
            .padding(.bottom, 12)
        .navigationDestination(item: $selected) { listing in
            MarketplaceListingDetailView(
                listing: listing,
                store: store,
                session: session.server,
                wallet: wallet,
                library: mirrors,
                stickers: library,
                mirrorStore: mirrors?.assetStore,
                stickerStore: library.assetStore,
                onNeedsSignIn: { _ = session.requireSignIn(for: .shardTransaction) }
            )
        }
        // 만들기 시작 방식. 커스텀 다이얼로그를 쓴다.
        .inkDialog(
            "스티커 만들기",
            message: "빈 캔버스에서 그리거나, 사진에서 배경을 지워 시작할 수 있어요.",
            isPresented: $isChoosingStart,
            // 다이얼로그가 **완전히 닫힌 뒤** Creator를 연다.
            onDismiss: {
                creatorRequest = pendingCreatorRequest
                pendingCreatorRequest = nil
            }
        ) {
            [
                InkDialogAction("빈 캔버스에서 만들기", role: .primary) {
                    pendingCreatorRequest = StickerCreatorRequest(startsWithPhoto: false)
                },
                InkDialogAction("사진으로 시작하기") {
                    pendingCreatorRequest = StickerCreatorRequest(startsWithPhoto: true)
                },
                InkDialogAction("취소"),
            ]
        }
        // 스티커 하나를 골랐을 때의 동작 목록.
        .inkDialog(isPresented: Binding(
            get: { actionTarget != nil },
            set: { if !$0 { actionTarget = nil } }
        )) {
            if let project = actionTarget {
                InkDialogBody(
                    title: project.name,
                    message: nil,
                    actions: actions(for: project),
                    onAction: { actionTarget = nil }
                )
            }
        }
        .inkDialog(
            "안내",
            message: notice,
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
        .fullScreenCover(item: $creatorRequest) { request in
            StickerCreatorView(
                design: request.design ?? .blankSticker(
                    id: UUID().uuidString, name: library.suggestedName
                ),
                library: library,
                context: request.context,
                startsWithPhoto: request.startsWithPhoto,
                onSaved: { creatorRequest = nil }
            )
        }
        .inkBottomSheet(item: $publishTarget, size: .fraction(0.92)) { project in
            PublishStickerView(project: project, library: library)
        }
    }

    // MARK: - 구역

    private func sectionTitle(_ title: String, count: Int?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(InkFont.sectionTitle)
                .foregroundStyle(PaperTheme.ink)
            if let count {
                Text("\(count)")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var createButton: some View {
        Button { isChoosingStart = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("스티커 만들기")
                        .font(InkFont.cardTitle)
                    Text("직접 그리거나 사진으로 만들어요")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .bold))
            }
            .foregroundStyle(PaperTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .background {
                let shape = UnevenRoundedRectangle.ink(18, 15, 19, 16)
                shape
                    .fill(PaperTheme.subtleSurface)
                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.emphasis))
            }
            .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel("스티커 만들기")
    }

    private var emptyStickers: some View {
        VStack(spacing: 10) {
            DoodleStickerView(sticker: .sparkle, size: 40, tint: PaperTheme.secondaryInk)
            Text("아직 만든 스티커가 없어요")
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
            Text("직접 만든 스티커는 거울을 꾸밀 때 바로 쓸 수 있어요")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
    }

    private var grid: some View {
        LazyVGrid(columns: GalleryLayout.columns(for: dynamicTypeSize), spacing: 18) {
            ForEach(library.projects.reversed()) { project in
                VStack(spacing: 6) {
                    Button { actionTarget = project } label: {
                        StickerGalleryItem(project: project, library: library)
                    }
                    .buttonStyle(InkPressStyle())

                    publishButton(for: project)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    /// 실제 서버 목록. 상품이 없으면 **비어 있다고 말한다** — 가짜 목록을 만들지 않는다.
    private var marketplace: some View {
        Group {
            if store.listings.contains(where: { $0.contentType == "sticker" }) {
                MarketplaceSection(
                    contentType: "sticker",
                    store: store,
                    sort: sort,
                    session: session.server,
                    onSelect: { selected = $0 },
                    onNeedsSignIn: { _ = session.requireSignIn(for: .shardTransaction) }
                )
            } else {
                VStack(spacing: 8) {
                    Text("아직 등록된 스티커가 없어요")
                        .font(InkFont.body)
                        .foregroundStyle(PaperTheme.ink)
                    Text("누군가 스티커를 올리면 여기에 보여요")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .padding(.horizontal, 20)
                .background {
                    let shape = UnevenRoundedRectangle.ink(18, 15, 19, 16)
                    shape.stroke(PaperTheme.separator, style: StrokeStyle(lineWidth: 1.4, dash: [6, 5]))
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - 동작

    // MARK: - 내보내기


    /// 투명 PNG 그대로 사진 앱에 저장한다. JPEG로 바꾸면 투명 영역이 사라진다.
    private func saveSticker(_ project: StickerProject) {
        Task {
            do {
                let png = try OwnContentExport.stickerPNG(project)
                if let failure = await OwnContentExport.saveToPhotos(png: png) {
                    notice = failure.message
                } else {
                    notice = "사진 앱에 저장했어요."
                }
            } catch {
                notice = (error as? OwnContentExportFailure)?.message
                    ?? OwnContentExportFailure.renderingFailed.message
            }
        }
    }

    /// 카드 아래에 **바로 보이는** 상점 등록 CTA. 거울과 같은 모양·같은 규칙이다.
    ///
    /// 등록할 수 없는 스티커(AI 포함)라도 조용히 감추지 않고 이유를 알려준다.
    private func publishButton(for project: StickerProject) -> some View {
        let isEligible = project.canPublishToStore
        return Button {
            if isEligible {
                publishTarget = project
            } else {
                notice = "AI로 만든 스티커는 아직 상점에 등록할 수 없어요. 사진에 저장은 할 수 있어요."
            }
        } label: {
            Label("상점에 등록", systemImage: "tray.and.arrow.up")
                .font(InkFont.caption.weight(.semibold))
                .foregroundStyle(isEligible ? PaperTheme.ink : PaperTheme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 32)
                .background {
                    let shape = UnevenRoundedRectangle.ink(12, 10, 13, 11)
                    shape.stroke(
                        isEligible ? PaperTheme.ink : PaperTheme.separator,
                        lineWidth: InkLine.regular
                    )
                }
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel("\(project.name) 상점에 등록")
    }

    private func actions(for project: StickerProject) -> [InkDialogAction] {
        [
            InkDialogAction("사용하기", role: .primary) {
                notice = "거울 꾸미기 → 스티커 → 내 스티커에서 이 스티커를 놓을 수 있어요."
            },
            InkDialogAction("꾸미기") {
                // 같은 스티커를 고친다. 새 스티커가 생기지 않는다.
                creatorRequest = StickerCreatorRequest(
                    design: project.design,
                    context: .editExisting(project.id)
                )
            },
            InkDialogAction("사진에 저장") { saveSticker(project) },
            // 상점 등록은 **카드 아래 CTA 한 곳**에서만 한다 — 같은 동작을 두 곳에 두지 않는다.
            InkDialogAction("삭제", role: .destructive) { library.delete(project) },
            InkDialogAction("닫기"),
        ]
    }
}

// MARK: - 카드

/// 내 스티커 카드. 투명 PNG라 뒤에 아주 옅은 체크무늬를 깐다 —
/// **미리보기 배경일 뿐이고 최종 PNG는 그대로 투명하다.**
struct StickerGalleryItem: View {
    let project: StickerProject
    var library: StickerLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                TransparencyCheckerboard(cell: 12)
                if let image = library.finalImage(for: project) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(UnevenRoundedRectangle.ink(16, 13, 17, 14))
            .overlay(
                UnevenRoundedRectangle.ink(16, 13, 17, 14)
                    .stroke(PaperTheme.ink, lineWidth: InkLine.regular)
            )

            Text(project.name)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("스티커, \(project.name)")
    }
}
