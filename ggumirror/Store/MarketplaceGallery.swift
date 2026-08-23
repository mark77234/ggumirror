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

    /// 내장 카드의 `MirrorPreview`와 같은 비율 · 같은 테두리를 쓴다.
    private var previewImage: some View {
        let shape = UnevenRoundedRectangle.ink(20, 24, 25, 19)
        return ZStack {
            shape.fill(PaperTheme.subtleSurface)
            if let preview, let image = UIImage(data: preview) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(shape)
            } else {
                // 실패/대기 모두 같은 자리표시자다. 가짜 그림을 만들지 않는다.
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(PaperTheme.separator)
            }
        }
        .aspectRatio(MirrorStyle.aspectRatio, contentMode: .fit)
        .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.regular))
    }

    /// 카드 위 하트. **여기가 좋아요를 누르는 자리다** — 상세로 들어가야만
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var listings: [MarketplaceListing] {
        // 내장 목록과 **같은 규칙**으로 정렬한다.
        sort.ordered(store.listings.filter { $0.contentType == contentType })
    }

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
                                            await store.toggleLike(
                                                listingID: listing.id, session: session
                                            )
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
        .task(id: "\(contentType)-\(sort.rawValue)") {
            await store.refresh(contentType: contentType, sort: sort, session: session)
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
    @State private var isImporting = false
    @State private var didImport = false

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
        .contentMargins(.bottom, InkTabBar.reservedHeight + 24, for: .scrollContent)
        .paperBackground()
        .navigationTitle(listing.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadPreview(listing.id) }
        .inkDialog(
            "알림",
            message: notice,
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if isOwned {
                primaryButton(didImport ? "내 목록에 담았어요" : "내 것으로 받기") {
                    await runImport()
                }
                .disabled(isImporting || didImport)
            } else {
                primaryButton(listing.priceShards == 0 ? "무료로 받기" : "\(listing.priceShards) 조각으로 구매") {
                    await runPurchase()
                }
                .disabled(isPurchasing)
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

    /// 구매. **조각은 서버가 옮긴다** — 성공 응답 전에 잔액을 바꾸지 않는다.
    private func runPurchase() async {
        guard session != nil else { onNeedsSignIn(); return }
        guard let result = await store.purchase(
            listingID: listing.id, session: session, wallet: wallet
        ) else {
            notice = store.failure?.message
            return
        }
        // 이미 산 것이면 실패가 아니다. 조각은 한 번만 빠졌다.
        notice = result.alreadyOwned
            ? "이미 가진 상품이에요. 조각은 다시 빠지지 않았어요."
            : "\(listing.title)을(를) 샀어요."
        // 지갑을 서버 authority로 다시 맞춘다.
        await wallet?.refresh(session: session)
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
