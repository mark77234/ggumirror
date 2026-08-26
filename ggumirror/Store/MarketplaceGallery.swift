//
//  MarketplaceGallery.swift
//  ggumirror
//
//  사용자가 올린 상품 목록과 상세.
//
//  내장 템플릿(`StoreGalleryItem`)과 **생김새를 맞춘다** — 같은 글꼴 · 같은 간격 ·
//  같은 metadata 한 줄이다. 새 디자인 언어를 만들지 않는다.
//
//  다른 점은 하나뿐이다: 대표 이미지를 로컬에서 그리지 않고 서버에서 받는다.
//  내장 템플릿은 `style`과 번들 PNG가 있어 `MirrorPreview`로 그릴 수 있지만,
//  서버 상품은 그것을 공개하지 않는다(그게 맞다 — 사기 전에 원본을 주지 않는다).
//

import SwiftUI

// MARK: - 카드

struct MarketplaceGalleryItem: View {
    let listing: MarketplaceListing
    /// 서버에서 받은 대표 이미지. 아직 없으면 자리표시자를 둔다.
    let preview: Data?
    var isLiked = false
    /// 내가 올린 상품인가. 자기 상품에는 좋아요를 누를 수 없다(서버 정책).
    var isMine = false
    /// 좋아요 요청이 떠 있는가. 연타를 막는다.
    var isLiking = false
    /// 하트를 눌렀을 때. `nil`이면 하트를 그리지 않는다(상세 화면 등).
    var onToggleLike: (() -> Void)?

    var body: some View {
        card
            .accessibilityElement(children: .combine)
        .accessibilityLabel(
            """
            \(listing.title), \
            \(listing.priceShards == 0 ? "무료" : "\(listing.priceShards) 조각"), \
            다운로드 \(listing.downloadCount), 좋아요 \(listing.likeCount), \
            \(listing.publishedAtLabel) 업로드\(isLiked ? ", 좋아요 누름" : "")
            """
        )
    }

    /// 거울은 **내장 템플릿과 같은 카드**를 쓴다.
    ///
    /// 예전에는 사용자 상품만 작은 거울을 왼쪽에 붙이고 정보를 오른쪽에 세웠다 —
    /// 같은 상점의 같은 물건인데 다른 물건처럼 보였다. 기준은 원래 있던 내장 카드다.
    /// 스티커는 정사각 표현이 맞으므로 그대로 둔다.
    @ViewBuilder
    private var card: some View {
        if ListingPreviewStyle.isSticker(listing.contentType) {
            stickerCard
        } else {
            StoreMirrorCard(model: cardModel, like: cardLike) { previewImage }
        }
    }

    private var cardModel: StoreMirrorCardModel {
        StoreMirrorCardModel(
            title: listing.title,
            // 1.1.0부터 서버가 판매자 **이름**을 준다(내부 id는 여전히 주지 않는다).
            // 아직 이름을 정하지 않은 판매자와 1.0.7 시절 상품은 `nil`이고,
            // 그때는 가짜 이름을 지어내지 않고 자리만 비운다 —
            // 자리는 카드가 늘 잡고 있어 높이가 데이터에 따라 달라지지 않는다.
            subtitle: listing.sellerDisplayName,
            price: listing.priceShards,
            downloadCount: listing.downloadCount,
            footnote: listing.publishedAtLabel
        )
    }

    /// 하트를 넘길지. 상세 화면처럼 `onToggleLike`가 없으면 그리지 않는다.
    private var cardLike: StoreMirrorCardLike? {
        guard let onToggleLike else { return nil }
        return StoreMirrorCardLike(
            count: listing.likeCount, isLiked: isLiked,
            isMine: isMine, isBusy: isLiking, toggle: onToggleLike
        )
    }

    /// **칸 크기는 종류가 정하고 그림은 그 안에 들어간다.**
    /// 원본 픽셀 크기에 기대지 않으므로 작은 스티커 PNG가 카드를 찌그러뜨리지 않는다.
    private var previewImage: some View {
        let shape = UnevenRoundedRectangle.ink(20, 24, 25, 19)
        let type = listing.contentType
        return ZStack {
            if ListingPreviewStyle.showsTransparency(for: type) {
                // 투명한 것이 정상이라 바탕을 깔아야 보인다.
                TransparencyCheckerboard(cell: 10).clipShape(shape)
            } else {
                shape.fill(PaperTheme.subtleSurface)
            }

            if let preview, let image = UIImage(data: preview) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: ListingPreviewStyle.contentMode(for: type))
                    .clipShape(shape)
            } else {
                // 실패/대기 모두 같은 자리표시자다. 가짜 그림을 만들지 않는다.
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(PaperTheme.separator)
            }
        }
        .aspectRatio(ListingPreviewStyle.aspectRatio(for: type), contentMode: .fit)
        .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.regular))
    }

    /// 스티커는 정사각 그림 한 덩어리가 곧 상품이라 예전 표현을 그대로 쓴다.
    /// 거울처럼 세로로 긴 그림이 아니어서 카드가 밀리는 문제가 없었다.
    private var stickerCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            previewImage
                .overlay(alignment: .topTrailing) { heart }
                .padding(.bottom, 6)

            Text(listing.title)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                Spacer(minLength: 4)
                ShardAmount(amount: listing.priceShards)
            }

            metadata
        }
    }

    /// 스티커 카드 위 하트. 거울은 통계 줄 안에서 누른다(공통 카드).
    ///
    /// 자기 상품에서는 **숫자만 보이고 누를 수 없다.** 실패할 CTA를 일부러
    /// 보여 주지 않는다(서버가 self-like를 거절한다).
    ///
    /// 원래 주석: 상세로 들어가야만
    /// 누를 수 있으면 어디서 누르는지 알 수 없다는 것이 실기기에서 확인됐다.
    ///
    /// 자기 상품에서는 **숫자만 보이고 누를 수 없다.** 실패할 CTA를 일부러
    /// 보여 주지 않는다(서버가 self-like를 거절한다).
    @ViewBuilder
    private var heart: some View {
        if let onToggleLike {
            // 누른 상태가 **한눈에** 달라 보여야 한다. 속이 찬 하트와 빈 하트의 차이는
            // 이 글자 크기에서 너무 미묘해서, 눌렀는지 아닌지 알 수 없었다.
            // 눌리면 칩 전체가 뒤집힌다 — 기존 Ink 강조(먹지 + 종이 글자) 그대로다.
            let label = HStack(spacing: 4) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                Text("\(listing.likeCount)")
            }
            .font(InkFont.caption)
            .foregroundStyle(isLiked ? PaperTheme.subtleSurface : PaperTheme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                let shape = UnevenRoundedRectangle.ink(12, 10, 13, 11)
                shape.fill(isLiked ? PaperTheme.ink : PaperTheme.paper)
                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.4))
            }

            if isMine {
                label
                    .opacity(0.55)
                    .padding(8)
                    .accessibilityLabel("좋아요 \(listing.likeCount). 내 상품이라 누를 수 없어요")
            } else {
                Button(action: onToggleLike) {
                    label
                        // 칩이 작아도 손가락이 닿는 자리는 44pt 이상이어야 한다.
                        .frame(minWidth: 44, minHeight: 44, alignment: .center)
                        .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())
                .disabled(isLiking)
                .padding(4)
                .accessibilityLabel(isLiked ? "좋아요 취소" : "좋아요")
                .accessibilityValue("\(listing.likeCount)")
            }
        }
    }

    private var metadata: some View {
        HStack(spacing: 8) {
            Label("\(listing.downloadCount)", systemImage: "arrow.down")
            Label("\(listing.likeCount)", systemImage: isLiked ? "heart.fill" : "heart")
            Spacer(minLength: 2)
            Text(listing.publishedAtLabel)
        }
        .font(InkFont.caption)
        .foregroundStyle(PaperTheme.secondaryInk)
        .labelStyle(.titleAndIcon)
        .imageScale(.small)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

nonisolated extension MarketplaceListing {
    /// 내장 카드의 `uploadedAtLabel`과 같은 형식.
    var publishedAtLabel: String {
        publishedAt.formatted(.dateTime.year().month().day())
    }
}

// MARK: - 목록 구획

/// 상점 안의 "사용자 상품" 구획. 내장 목록 위에 붙는다.
struct MarketplaceSection: View {
    let contentType: String
    @Bindable var store: MarketplaceStore
    var sort: StoreSort
    var session: ServerSession?
    /// 상세로 넘어갈 때 부른다. navigation은 부모가 소유한다.
    var onSelect: (MarketplaceListing) -> Void
    /// 로그인이 필요할 때. 기존 gate를 그대로 쓴다.
    var onNeedsSignIn: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var listings: [MarketplaceListing] {
        // 내장 목록과 **같은 규칙**으로 정렬한다.
        sort.ordered(store.listings.filter { $0.contentType == contentType })
    }

    // **목록을 받아오는 일은 여기 없다.** 화면이 한다.
    //
    // 예전에는 이 view가 `.task`로 직접 받아왔는데, 목록이 비면 `EmptyView()`를 그리고
    // 그 위의 `.task`가 **한 번도 실행되지 않았다** — 그래서 상품이 하나도 없는 상태에서
    // 영원히 비어 있었다. 등록한 거울이 상점에 안 보이던 이유이고, 카드가 없으니
    // 하트도 없었다. 받아오는 책임은 언제나 그려지는 쪽에 있어야 한다.
    var body: some View {
        Group {
            if listings.isEmpty {
                // 상품이 없으면 아무것도 그리지 않는다 — **가짜 상품을 만들지 않는다.**
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("사용자 상품")
                        .font(InkFont.cardTitle)
                        .foregroundStyle(PaperTheme.ink)
                        .padding(.horizontal, 20)

                    LazyVGrid(columns: GalleryLayout.columns(for: dynamicTypeSize), spacing: 18) {
                        ForEach(listings) { listing in
                            Button {
                                onSelect(listing)
                            } label: {
                                MarketplaceGalleryItem(
                                    listing: listing,
                                    preview: store.previews[listing.id],
                                    isLiked: store.likedListingIDs.contains(listing.id),
                                    isMine: store.myListing(id: listing.id) != nil,
                                    isLiking: store.isBusy(.like(listing.id)),
                                    onToggleLike: {
                                        Task {
                                            // 로그인 전이면 요청을 보내지 않고 안내한다.
                                            let sent = await store.toggleLike(
                                                listingID: listing.id, session: session
                                            )
                                            if !sent { onNeedsSignIn() }
                                        }
                                    }
                                )
                            }
                            .buttonStyle(InkPressStyle())
                            .task { await store.loadPreview(listing.id) }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - 상세

/// 사용자 상품 상세. 구매 · 좋아요 · 받기.
struct MarketplaceListingDetailView: View {
    let listing: MarketplaceListing
    @Bindable var store: MarketplaceStore
    var session: ServerSession?
    var wallet: ShardWallet?
    var library: MirrorLibrary?
    var stickers: StickerLibrary?
    var mirrorStore: MirrorStore?
    var stickerStore: StickerProjectStore?
    /// 로그인이 필요할 때 부른다. 새 인증 흐름을 만들지 않는다.
    var onNeedsSignIn: () -> Void = {}

    @State private var importer = MarketplaceImporter()
    @State private var notice: String?
    /// 열려 있으면 미리보기 화면이 떠 있다. **경제 동작이 아니다** —
    /// 소유권 · 다운로드 수 · 조각 · 내 거울 저장 어느 것도 건드리지 않는다.
    @State private var preview: MirrorPreviewSubject?
    @State private var isImporting = false
    @State private var didImport = false
    /// 방금 산 거울을 내 거울로 가져올지 묻는 중.
    @State private var showsRegistrationPrompt = false

    private var isOwned: Bool { store.purchasedListingIDs.contains(listing.id) }
    private var isLiked: Bool { store.likedListingIDs.contains(listing.id) }
    private var isPurchasing: Bool { store.isBusy(.purchase(listing.id)) }
    private var isLiking: Bool { store.isBusy(.like(listing.id)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                MarketplaceGalleryItem(
                    listing: listing, preview: store.previews[listing.id], isLiked: isLiked
                )
                .frame(maxHeight: 420)
                .padding(.top, 8)

                Text(listing.title)
                    .font(InkFont.pageTitle)
                    .foregroundStyle(PaperTheme.ink)
                    .multilineTextAlignment(.center)

                // 누가 올렸는지. **이름뿐이다** — 내부 id는 서버가 주지도 않는다.
                // 이름이 없는 판매자는 줄 자체를 그리지 않는다(가짜 이름 금지).
                if let seller = listing.sellerDisplayName, !seller.isEmpty {
                    Text(seller)
                        .font(InkFont.secondary)
                        .foregroundStyle(PaperTheme.secondaryInk)
                        .accessibilityLabel("판매자 \(seller)")
                }

                if !listing.description.isEmpty {
                    Text(listing.description)
                        .font(InkFont.secondary)
                        .foregroundStyle(PaperTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 6) {
                    ShardIcon(size: 18)
                    Text(listing.priceShards == 0 ? "무료" : "\(listing.priceShards) 조각")
                        .font(InkFont.cardTitle)
                        .foregroundStyle(PaperTheme.ink)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(listing.priceShards == 0 ? "무료" : "\(listing.priceShards) 조각")

                actions
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .inkTabBarSafeContent()
        .paperBackground()
        .navigationTitle(listing.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadPreview(listing.id) }
        .mirrorLivePreview($preview, title: listing.title)
        .inkDialog(
            "알림",
            message: notice,
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
        .inkDialog(
            "구매 완료!",
            message: showsRegistrationPrompt
                ? "이 거울은 구매가 완료됐어요.\n실제로 사용하려면 내 거울에 등록해주세요."
                : nil,
            isPresented: $showsRegistrationPrompt
        ) {
            [
                // **기존 등록 흐름을 그대로 쓴다.** 새 복사 경로를 만들지 않는다 —
                // 보관 공간 확인도 실패 안내도 거기에 이미 있다.
                InkDialogAction("내 거울에 등록하기", role: .primary) {
                    Task { await runImport() }
                },
                // 누르지 않아도 산 것은 그대로 남는다. 몰래 등록하지 않는다.
                InkDialogAction("나중에", role: .secondary),
            ]
        }
    }

    /// 내장 템플릿과 **같은 상태 모델**을 쓴다. 화면마다 다른 문구를 만들지 않는다.
    private var cta: MirrorAcquireCTA {
        MirrorAcquireCTA.state(
            price: listing.priceShards,
            isSignedIn: session != nil,
            isMine: store.myListing(id: listing.id) != nil,
            ownsOnServer: isOwned,
            existsLocally: existsLocally
        )
    }

    /// 이 상품이 이미 이 기기에 있는가. **listing id로 맞춘다** — 제목으로 찾지 않는다.
    /// 상점에서 받은 거울은 `MyMirror.id == listingID`로 저장된다.
    private var existsLocally: Bool {
        if ListingPreviewStyle.isSticker(listing.contentType) {
            return stickers?.projects.contains { $0.id == listing.id } ?? false
        }
        return library?.mirrors.contains { $0.id == listing.id } ?? false
    }

    private var actions: some View {
        VStack(spacing: 10) {
            // 1순위 CTA. **받기보다 먼저다** — 내장 템플릿 상세와 같은 순서·같은 문구다.
            // 로그인하지 않아도 누를 수 있다.
            if canPreview {
                primaryButton("내 거울로 미리보기") { openPreview() }
                // 미리보기가 위로 가면 받기는 두 번째 버튼이 된다.
                secondaryButton(cta.title) { await runAcquire() }
                    .disabled(!cta.isEnabled || isPurchasing || isImporting)
            } else {
                primaryButton(cta.title) { await runAcquire() }
                    .disabled(!cta.isEnabled || isPurchasing || isImporting)
            }

            secondaryButton(isLiked ? "좋아요 취소" : "좋아요") {
                guard session != nil else { onNeedsSignIn(); return }
                await store.toggleLike(listingID: listing.id, session: session)
                if let failure = store.failure { notice = failure.message }
            }
            .disabled(isLiking)
        }
        .padding(.top, 4)
    }

    /// 스티커에는 카메라 자리가 없다 — 얹어 볼 것이 아니라 붙여 쓰는 것이다.
    /// 그림을 아직 못 받았으면 도려낼 것도 없으므로 버튼을 그리지 않는다.
    private var canPreview: Bool {
        !ListingPreviewStyle.isSticker(listing.contentType) && store.previews[listing.id] != nil
    }

    /// **공개 미리보기 그림 하나로 끝낸다.** 상품 manifest도 원본 asset도 받지 않는다 —
    /// 사기 전에 볼 수 있어야 하지만, 보는 것으로 상품을 손에 넣게 두지는 않는다.
    private func openPreview() {
        guard let png = store.previews[listing.id] else { return }
        guard let subject = MirrorPreviewSubject.overlay(fromListingPreview: png) else {
            // 카메라 자리를 못 찾으면 얼굴이 가려진 화면이 된다. 그건 미리보기가 아니다.
            notice = "이 상품은 미리보기를 만들 수 없어요."
            return
        }
        preview = subject
    }

    /// 버튼 하나가 상태에 따라 다른 일을 한다. 화면에 분기를 흩뿌리지 않는다.
    private func runAcquire() async {
        switch cta {
        case .needsSignIn:
            // **서버에 먼저 보내 401을 받지 않는다.** 로그인 전인 것은 이미 안다.
            onNeedsSignIn()
        case .acquireFree, .purchase:
            await runPurchase()
        case .addToLibrary:
            await runImport()
        case .alreadyInLibrary, .ownListing:
            break
        }
    }

    /// 구매. **조각은 서버가 옮긴다** — 성공 응답 전에 잔액을 바꾸지 않는다.
    private func runPurchase() async {
        guard session != nil else { onNeedsSignIn(); return }
        guard let result = await store.purchase(
            listingID: listing.id, session: session, wallet: wallet
        ) else {
            notice = store.failure?.message
            return
        }
        // 지갑을 서버 authority로 다시 맞춘다.
        await wallet?.refresh(session: session)

        // **산 것과 내 거울에 있는 것은 다른 일이다.**
        //
        // 구매는 소유권이고, 실제로 쓰려면 이 기기의 내 거울로 가져와야 한다.
        // 그 사실을 말해 주지 않으면 "샀는데 왜 목록에 없지?"가 된다.
        // 스티커에는 이 안내를 쓰지 않는다 — 거울과 쓰는 방식이 다르다.
        if !result.alreadyOwned, !ListingPreviewStyle.isSticker(listing.contentType) {
            showsRegistrationPrompt = true
            return
        }

        // 이미 산 것이면 실패가 아니다. 조각은 한 번만 빠졌다.
        notice = result.alreadyOwned
            ? "이미 가진 상품이에요. 조각은 다시 빠지지 않았어요."
            : "\(listing.title)을(를) 샀어요."
    }

    /// 산 것을 내 목록으로. **downloadCount는 오르지 않는다**(서버 규칙).
    private func runImport() async {
        isImporting = true
        defer { isImporting = false }
        do {
            if listing.contentType == "sticker" {
                guard let stickers else { notice = "내 스티커를 열지 못했어요."; return }
                _ = try await importer.importSticker(
                    listingID: listing.id, title: listing.title, session: session,
                    library: stickers, stickerStore: stickerStore, store: mirrorStore
                )
            } else {
                guard let library else { notice = "내 거울을 열지 못했어요."; return }
                _ = try await importer.importMirror(
                    listingID: listing.id, title: listing.title, session: session,
                    library: library, store: mirrorStore
                )
            }
            didImport = true
            notice = "\(listing.title)을(를) 내 목록에 담았어요."
        } catch let failure as MarketplaceImportFailure {
            notice = failure.message
        } catch {
            notice = "지금은 받을 수 없어요. 잠시 뒤 다시 시도해 주세요."
        }
    }

    // MARK: - 버튼

    private func primaryButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.subtleSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .frame(minHeight: 44)
                .background {
                    UnevenRoundedRectangle.ink(20, 24, 25, 19).fill(PaperTheme.ink)
                }
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
    }

    private func secondaryButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .frame(minHeight: 44)
                .background {
                    UnevenRoundedRectangle.ink(20, 24, 25, 19)
                        .stroke(PaperTheme.ink, lineWidth: 1.8)
                }
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
    }
}
