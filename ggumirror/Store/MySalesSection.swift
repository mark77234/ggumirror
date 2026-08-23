//
//  MySalesSection.swift
//  ggumirror
//
//  상점의 `내 판매` 탭. 내가 올린 상품을 관리한다.
//
//  **공개 목록과 섞지 않는다.** 섞여 있으면 아직 안 올린 것(등록 미완료)과 실제
//  판매 중인 것을 구분할 수 없었다 — 실기기에서 사용자가 바로 헷갈렸다.
//
//  authority는 서버다: `GET /users/me/marketplace/listings`.
//  앱이 기억해 둔 id는 힌트일 뿐이라 앱을 지우거나 기기를 바꾸면 사라진다.
//
//  삭제는 **되살릴 수 없다.** 그래서 누르면 바로 실행하지 않고 확인을 받는다.
//  서버는 실제로 지우지 않는다(이미 산 사람은 계속 받는다) — 하지만 판매자에게는
//  끝난 일이므로 "잠시 내림"처럼 말하지 않는다.
//

import SwiftUI
import UIKit

struct MySalesSection: View {
    @Bindable var store: MarketplaceStore
    var session: ServerSession?
    var wallet: ShardWallet?

    @State private var notice: String?
    /// 삭제 확인을 기다리는 상품. 누르자마자 지우지 않는다.
    @State private var pendingDelete: MarketplaceOwnedListing?

    /// 판매 중인 것. `published`만.
    private var selling: [MarketplaceOwnedListing] {
        store.myListings.filter(\.isPublished)
    }

    /// 등록을 마치지 못한 것. `draft`만.
    ///
    /// 등록 도중 실패해 남은 것도 여기로 온다 — 사용자가 이어서 올릴 수 있어야 한다.
    private var incomplete: [MarketplaceOwnedListing] {
        store.myListings.filter(\.isDraft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if session == nil {
                signInNotice
            } else if selling.isEmpty && incomplete.isEmpty {
                empty
            } else {
                if !selling.isEmpty {
                    group("판매 중", listings: selling)
                }
                if !incomplete.isEmpty {
                    group("등록 미완료", listings: incomplete)
                        .padding(.top, selling.isEmpty ? 0 : 22)
                }
            }
        }
        .padding(.bottom, 12)
        .task(id: session?.userID) {
            await store.refreshMyListings(session: session)
        }
        .inkDialog(
            "내 판매",
            message: notice,
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
        // **되살릴 수 없는 동작이라 반드시 확인을 받는다.**
        .inkDialog(isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            if let listing = pendingDelete {
                InkDialogBody(
                    title: listing.contentType == "sticker"
                        ? "이 스티커를 상점에서 삭제할까요?"
                        : "이 거울을 상점에서 삭제할까요?",
                    message: """
                    삭제하면 상점에서 더 이상 보이지 않아요.
                    등록할 때 사용한 \(listing.publishFeeShards)조각은 환불되지 않아요.
                    이미 받은 사용자는 계속 사용할 수 있어요.
                    """,
                    actions: [
                        InkDialogAction("취소"),
                        InkDialogAction("삭제", role: .destructive) {
                            let target = listing
                            Task { await delete(target) }
                        },
                    ],
                    onAction: { pendingDelete = nil }
                )
            }
        }
    }

    // MARK: - 구획

    private func group(_ title: String, listings: [MarketplaceOwnedListing]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(InkFont.cardTitle)
                    .foregroundStyle(PaperTheme.ink)
                Text("\(listings.count)")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
            }
            ForEach(listings) { listing in
                card(listing)
            }
        }
        .padding(.horizontal, 20)
    }

    private var signInNotice: some View {
        placeholder(
            title: "로그인하면 내 상품을 관리할 수 있어요",
            detail: "상점 구경은 로그인 없이도 됩니다."
        )
    }

    private var empty: some View {
        placeholder(
            title: "아직 상점에 올린 상품이 없어요",
            detail: "내 거울이나 내 스티커에서 상점에 올려 보세요."
        )
    }

    private func placeholder(title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
            Text(detail)
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .background {
            UnevenRoundedRectangle.ink(18, 15, 19, 16)
                .stroke(PaperTheme.separator, style: StrokeStyle(lineWidth: 1.4, dash: [6, 5]))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 카드

    private func card(_ listing: MarketplaceOwnedListing) -> some View {
        let isBusy = store.isBusy(.delete(listing.id)) || store.isBusy(.publish(listing.id))
        return VStack(alignment: .leading, spacing: 8) {
            // 판매자 전용 미리보기 — draft도 보인다(공개 미리보기는 published만).
            preview(listing)
                .task { await store.loadMyPreview(listing.id, session: session) }

            HStack(spacing: 8) {
                Text(listing.title)
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(listing.statusLabel)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
            }

            HStack(spacing: 10) {
                Text(listing.contentType == "sticker" ? "스티커" : "거울")
                ShardAmount(amount: listing.priceShards, font: InkFont.caption, iconSize: 14)
                Label("\(listing.downloadCount)", systemImage: "arrow.down")
                Label("\(listing.likeCount)", systemImage: "heart")
                Spacer(minLength: 4)
            }
            .font(InkFont.caption)
            .foregroundStyle(PaperTheme.secondaryInk)
            .labelStyle(.titleAndIcon)
            .imageScale(.small)

            HStack(spacing: 8) {
                if listing.isPublished {
                    // **"내리기"가 아니라 "삭제"다.** 사용자가 원한 것은 되돌릴 수 있는
                    // 숨김이 아니라 끝내는 것이다. 누르면 확인을 먼저 받는다.
                    action("삭제") { pendingDelete = listing }
                }
                if listing.isDraft {
                    // 이 draft가 이미 가리키는 불변 snapshot을 그대로 올린다.
                    action("상점에 올리기") { Task { await resume(listing) } }
                }
                Spacer(minLength: 0)
            }
            .disabled(isBusy)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background {
            UnevenRoundedRectangle.ink(18, 15, 19, 16)
                .stroke(PaperTheme.separator, lineWidth: 1.4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            """
            \(listing.title), \(listing.statusLabel), \
            \(listing.contentType == "sticker" ? "스티커" : "거울"), \
            \(listing.priceShards == 0 ? "무료" : "\(listing.priceShards) 조각"), \
            다운로드 \(listing.downloadCount), 좋아요 \(listing.likeCount)
            """
        )
    }

    private func preview(_ listing: MarketplaceOwnedListing) -> some View {
        let shape = UnevenRoundedRectangle.ink(18, 15, 19, 16)
        return ZStack {
            shape.fill(PaperTheme.subtleSurface)
            if let data = store.myPreviews[listing.id], let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(shape)
            } else if store.myPreviewFailures.contains(listing.id) {
                Label("미리보기를 불러오지 못했어요", systemImage: "photo")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(PaperTheme.separator)
            }
        }
        .aspectRatio(MirrorStyle.aspectRatio, contentMode: .fit)
        .frame(maxHeight: 220)
        .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.regular))
        .accessibilityHidden(true)
    }

    private func action(_ title: String, work: @escaping () -> Void) -> some View {
        Button(title, action: work)
            .font(InkFont.caption)
            .foregroundStyle(PaperTheme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background {
                UnevenRoundedRectangle.ink(14, 12, 15, 13)
                    .stroke(PaperTheme.ink, lineWidth: 1.6)
            }
            .buttonStyle(InkPressStyle())
            .contentShape(.rect)
    }

    // MARK: - 동작

    /// 삭제. **앱이 조각을 건드리지 않는다** — 환불이 없으므로 서버 상태만 다시 받는다.
    private func delete(_ listing: MarketplaceOwnedListing) async {
        guard await store.delete(listingID: listing.id, session: session) != nil else {
            notice = store.failure?.message
            return
        }
        notice = "상점에서 삭제했어요. 이미 받은 분은 계속 사용할 수 있어요."
    }

    /// 등록 미완료를 이어서 올린다. 새 snapshot도 새 listing도 만들지 않는다.
    private func resume(_ listing: MarketplaceOwnedListing) async {
        switch await store.resumePublish(
            listingID: listing.id, session: session, wallet: wallet
        ) {
        case .published(let result):
            notice = result.feeCharged
                ? "등록비 \(result.feeShards) 조각이 차감됐어요. 남은 조각 \(result.balance)개."
                : "추가 등록비 없이 등록을 마쳤어요."
            await wallet?.refresh(session: session)
        case .alreadyPublished:
            notice = "이미 상점에 올라가 있어요."
        case .missing:
            notice = "상품을 찾지 못했어요."
        case .needsSignIn:
            notice = "로그인이 필요해요."
        case .failed(let failure):
            notice = failure.message
        }
    }
}

// MARK: - 등록비

nonisolated extension MarketplaceOwnedListing {
    /// 이 종류의 등록비. **삭제 안내 문구에만** 쓴다 — 실제 차감은 서버가 한다.
    ///
    /// 화면에 숫자를 적지 않고 기존 정책 상수를 읽는다(UI-P3 규칙).
    var publishFeeShards: Int {
        contentType == "sticker"
            ? StickerPublishPolicy.feeInShards
            : MirrorPublishPolicy.feeInShards
    }
}
