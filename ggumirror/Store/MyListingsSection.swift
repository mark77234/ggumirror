//
//  MyListingsSection.swift
//  ggumirror
//
//  내가 상점에 올린 상품 목록.
//
//  **서버가 authority다.** `GET /users/me/marketplace/listings`가 draft · published ·
//  unlisted를 전부 준다. 앱이 기억해 둔 listing id는 힌트일 뿐이라 앱을 지웠거나
//  기기를 바꾸면 사라진다 — 그때도 자기 상품을 내릴 수 있어야 한다.
//
//  그래서 관리(내리기 / 다시 올리기)는 **이 구획**에서 완결된다.
//  등록 시트의 관리 버튼은 편의이고, 없어도 여기서 다 된다.
//
//  등록비 차감 여부는 서버가 알려 준다 — 앱이 "두 번째니까 무료"를 계산하지 않는다.
//

import SwiftUI

struct MyListingsSection: View {
    /// `mirror` 또는 `sticker`. 해당 종류만 보여 준다.
    let contentType: String
    @Bindable var store: MarketplaceStore
    var session: ServerSession?
    var wallet: ShardWallet?

    @State private var notice: String?

    private var mine: [MarketplaceOwnedListing] {
        store.myListings.filter { $0.contentType == contentType }
    }

    var body: some View {
        Group {
            if session == nil || mine.isEmpty {
                // 로그인 전이거나 올린 것이 없으면 **아무것도 그리지 않는다.**
                // 빈 자리를 만들어 "여기에 뭔가 있어야 하는데"처럼 보이게 하지 않는다.
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("내 상점 상품")
                        .font(InkFont.cardTitle)
                        .foregroundStyle(PaperTheme.ink)

                    ForEach(mine) { listing in
                        row(listing)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .task(id: session?.userID) {
            await store.refreshMyListings(session: session)
        }
        .inkDialog(
            "내 상점 상품",
            message: notice,
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
    }

    private func row(_ listing: MarketplaceOwnedListing) -> some View {
        let isBusy = store.isBusy(.unpublish(listing.id)) || store.isBusy(.publish(listing.id))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(listing.title)
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                // 상태는 **서버 문자열**에서 온다. 앱이 추측하지 않는다.
                Text(listing.statusLabel)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
            }

            HStack(spacing: 10) {
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
                    action("상점에서 내리기") { await unpublish(listing) }
                }
                if listing.isUnlisted {
                    action("다시 올리기") { await republish(listing) }
                }
                if listing.isDraft {
                    action("상점에 올리기") { await republish(listing) }
                }
                Spacer(minLength: 0)
            }
            .disabled(isBusy)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background {
            let shape = UnevenRoundedRectangle.ink(18, 15, 19, 16)
            shape.stroke(PaperTheme.separator, lineWidth: 1.4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            """
            \(listing.title), \(listing.statusLabel), \
            \(listing.priceShards == 0 ? "무료" : "\(listing.priceShards) 조각"), \
            다운로드 \(listing.downloadCount), 좋아요 \(listing.likeCount)
            """
        )
    }

    private func action(_ title: String, work: @escaping () async -> Void) -> some View {
        Button(title) { Task { await work() } }
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

    /// 내린다. **snapshot을 지우지 않는다** — 이미 산 사람은 계속 받는다.
    private func unpublish(_ listing: MarketplaceOwnedListing) async {
        guard await store.unpublish(listingID: listing.id, session: session) != nil else {
            notice = store.failure?.message
            return
        }
        notice = "상점에서 내렸어요. 이미 산 사람은 계속 받을 수 있어요."
    }

    /// 다시 올린다. **추가 등록비는 서버가 판단한다.**
    private func republish(_ listing: MarketplaceOwnedListing) async {
        guard let result = await store.republish(
            listingID: listing.id, session: session, wallet: wallet
        ) else {
            notice = store.failure?.message
            return
        }
        notice = result.feeCharged
            ? "등록비 \(result.feeShards) 조각이 차감됐어요. 남은 조각 \(result.balance)개."
            : "추가 등록비 없이 다시 올렸어요."
        await wallet?.refresh(session: session)
    }
}
