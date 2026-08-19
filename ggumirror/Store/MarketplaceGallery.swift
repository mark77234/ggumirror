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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            previewImage
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
                                    isLiked: store.likedListingIDs.contains(listing.id)
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
