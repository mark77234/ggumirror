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
//  **판매자가 내림 · 판매자가 삭제 · 운영자가 내림은 서로 다른 것이다.**
//
//      상점에서 내리기   `unlisted`. 다시 올릴 수 있고 등록비를 또 내지 않는다
//      삭제              끝 상태. 되돌릴 수 없다 — 확인을 받고 나서만 실행한다
//      운영 정책으로 내려감  판매자가 할 수 있는 것이 없다(서버가 409로 거절한다)
//
//  예전에는 판매 중인 상품의 유일한 동작이 `삭제`였다. "잠깐 내려 두려고" 그것을
//  누른 판매자가 다시 올릴 수 없게 됐다 — 실기기에서 보고된 문제가 정확히 이것이다.
//  서버는 삭제해도 실제로 지우지 않는다(이미 산 사람은 계속 받는다) — 하지만
//  판매자에게는 끝난 일이므로 "잠시 내림"처럼 말하지 않는다.
//
//  **상점과 같은 카드 · 같은 격자를 쓴다.** 예전에는 여기만 가로로 꽉 찬 줄이었다 —
//  판매자가 상점에서 보던 자기 상품을 여기서는 다른 물건처럼 봤다.
//  구획(판매 중 / 등록 미완료 / 운영 정책으로 내려감 / 판매 중지)은 그대로 둔다. 그것은 격자가 갈라진
//  것이 아니라 **판매자가 실제로 나눠서 봐야 하는 것**이고, 섞으면 아직 안 올린 것과
//  팔리는 중인 것을 구분할 수 없다(실기기에서 확인된 문제다).
//

import SwiftUI
import UIKit

struct MySalesSection: View {
    @Bindable var store: MarketplaceStore
    var session: ServerSession?
    var wallet: ShardWallet?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var notice: String?
    /// 삭제 확인을 기다리는 상품. 누르자마자 지우지 않는다.
    @State private var pendingDelete: MarketplaceOwnedListing?

    /// 판매 중인 것. **실제로 공개 상점에 있는 것만이다.**
    ///
    /// `status == "published"`만 보면 운영자가 내린 상품이 여기 남는다 —
    /// 판매자는 상점에 없는 자기 상품을 `판매 중`으로 보게 된다(실기기 문제).
    /// 판단은 `isPubliclyVisible` 하나이고 운영 화면과 같은 조건이다.
    private var selling: [MarketplaceOwnedListing] {
        store.myListings.filter(\.isPubliclyVisible)
    }

    /// 운영자가 내린 것. **판매자가 되돌릴 수 없다.**
    ///
    /// 판매자가 스스로 내린 것(`판매 중지`)과 **같은 칸에 두지 않는다** — 하나는
    /// 다시 올릴 수 있고 하나는 그럴 수 없어서, 섞이면 왜 버튼이 없는지 알 수 없다.
    /// 판매자가 삭제한 것은 여기 오지 않는다(끝났고 되살릴 수도 없다).
    private var moderated: [MarketplaceOwnedListing] {
        store.myListings.filter { $0.isModerated && !$0.isDeleted }
    }

    /// 판매자가 스스로 내린 것. `unlisted`만. **다시 올릴 수 있다.**
    private var retired: [MarketplaceOwnedListing] {
        store.myListings.filter(\.isUnlisted)
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
            } else if groups.isEmpty {
                empty
            } else {
                // 구획 순서는 고정이다. 사이 여백을 각 구획이 자기 앞을 보고 정하면
                // 구획을 하나 더할 때마다 조건이 늘어난다 — 목록으로 만든다.
                ForEach(Array(groups.enumerated()), id: \.offset) { index, section in
                    group(section.title, note: section.note, listings: section.listings)
                        .padding(.top, index == 0 ? 0 : 22)
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
                    삭제하면 되돌릴 수 없어요. 다시 올리려면 처음부터 등록해야 해요.
                    잠시만 내려 두려면 `상점에서 내리기`를 눌러 주세요.
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

    /// 판매자가 실제로 나눠서 봐야 하는 것들. **세 상태를 섞지 않는다** —
    /// 스스로 내린 것 · 운영자가 내린 것 · 아직 못 올린 것은 할 수 있는 일이 다르다.
    private var groups: [(title: String, note: String?, listings: [MarketplaceOwnedListing])] {
        [
            ("판매 중", nil, selling),
            ("등록 미완료", "등록을 마치지 못했어요. 이어서 올릴 수 있어요.", incomplete),
            ("운영 정책으로 내려감", "운영 정책으로 내려간 상품이에요. 다시 올릴 수 없어요.", moderated),
            ("판매 중지", "내가 상점에서 내린 상품이에요. 다시 올릴 수 있어요.", retired),
        ].filter { !$0.2.isEmpty }
    }

    private func group(
        _ title: String, note: String? = nil, listings: [MarketplaceOwnedListing]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(InkFont.cardTitle)
                    .foregroundStyle(PaperTheme.ink)
                Text("\(listings.count)")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
            }
            // **왜 여기 있는지 한 줄로 말한다.** 구획 이름만으로는 다시 올릴 수
            // 있는지 없는지 알 수 없다 — 실기기에서 그것을 물었다.
            if let note {
                Text(note)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // **상점과 같은 격자다.** 열 수 · 간격을 여기서 다시 정하지 않는다.
            LazyVGrid(
                columns: GalleryLayout.columns(for: dynamicTypeSize),
                spacing: GalleryLayout.spacing
            ) {
                ForEach(listings) { listing in
                    card(listing)
                }
            }
        }
        .padding(.horizontal, GalleryLayout.horizontalPadding)
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

    /// 격자 칸 하나. **상점 카드와 같은 component다** — 그림 그리는 코드가 여기 없다.
    ///
    /// 판매자에게 필요한 값은 하나도 빠지지 않는다: 가격 · 다운로드 · 좋아요는 카드가
    /// 늘 그리고, 판매 상태는 칸 위 배지와 통계 줄 끝에 온다.
    private func card(_ listing: MarketplaceOwnedListing) -> some View {
        MarketplaceListingCard(
            model: StoreMirrorCardModel(
                contentType: listing.contentType,
                title: listing.title,
                subtitle: listing.contentType == "sticker" ? "스티커" : "거울",
                price: listing.priceShards,
                downloadCount: listing.downloadCount,
                // **왜 못 올렸는지 말한다.** `등록 미완료`만으로는 이름이 겹친
                // 것인지 조각이 모자란 것인지 알 수 없다 — 실기기에서 그것을 물었다.
                footnote: store.publishFailure(for: listing.id)?.message ?? listing.statusLabel,
                status: listing.statusLabel
            ),
            preview: store.myPreviews[listing.id],
            didFail: store.myPreviewFailures.contains(listing.id),
            // 좋아요 수는 보여 주되 **누를 수 없다.** 자기 상품이라 서버가 거절한다.
            like: StoreMirrorCardLike(
                count: listing.likeCount, isLiked: false,
                isMine: true, isBusy: false, toggle: {}
            ),
            action: action(for: listing),
            destructive: deleteAction(for: listing)
        )
        // 판매자 전용 미리보기 — draft도 보인다(공개 미리보기는 published만).
        .task { await store.loadMyPreview(listing.id, session: session) }
    }

    /// 이 상태에서 할 수 있는 **하나뿐인** 동작.
    ///
    /// **세 가지를 하나로 합치지 않는다:**
    ///
    ///     판매자가 내림   `상점에서 내리기` → `unlisted`. 되돌릴 수 있다
    ///     판매자가 삭제   `삭제` → 끝 상태. 되돌릴 수 없다
    ///     운영자가 내림   판매자가 할 수 있는 것이 없다
    ///
    /// 예전에는 판매 중인 상품의 유일한 동작이 `삭제`였다. 사용자가 "잠깐 내려
    /// 두려고" 그것을 눌렀고, 그래서 **다시 올릴 수 없게 됐다** — 실기기에서
    /// "내린 상품이 다시 안 올라간다"로 보고된 것이 정확히 이것이다.
    /// 삭제는 남기되 **주 동작이 아니다** — 카드 아래 작은 글자 하나로 내려갔다.
    private func action(for listing: MarketplaceOwnedListing) -> MarketplaceCardAction? {
        let isBusy = store.isBusy(.delete(listing.id))
            || store.isBusy(.publish(listing.id))
            || store.isBusy(.unpublish(listing.id))

        // 운영자가 내렸다. **판매자 쪽 동작으로 풀 수 없다** — 서버가 409로 거절한다.
        // 눌러도 실패할 버튼을 보여 주지 않는다.
        if listing.isModerated && !listing.isDeleted { return nil }

        if listing.isPubliclyVisible {
            return MarketplaceCardAction(title: "상점에서 내리기", isEnabled: !isBusy) {
                Task { await unpublish(listing) }
            }
        }
        if listing.isUnlisted {
            // 같은 listing을 그대로 다시 올린다 — 새 snapshot도 새 listing도 없고,
            // 등록비도 다시 받지 않는다(`publishFeePaid`가 서버에 남아 있다).
            return MarketplaceCardAction(title: "다시 상점에 올리기", isEnabled: !isBusy) {
                Task { await resume(listing) }
            }
        }
        if listing.isDraft {
            // 이 draft가 이미 가리키는 불변 snapshot을 그대로 올린다.
            return MarketplaceCardAction(title: "상점에 올리기", isEnabled: !isBusy) {
                Task { await resume(listing) }
            }
        }
        return nil
    }

    /// 삭제. 끝 상태라 **되돌릴 수 없다.** 이미 삭제된 것에는 주지 않는다.
    private func deleteAction(for listing: MarketplaceOwnedListing) -> MarketplaceCardAction? {
        guard !listing.isDeleted else { return nil }
        let isBusy = store.isBusy(.delete(listing.id))
        return MarketplaceCardAction(title: "삭제", isEnabled: !isBusy) {
            pendingDelete = listing
        }
    }

    /// 상점에서 내린다. **삭제가 아니다** — 다시 올릴 수 있다.
    private func unpublish(_ listing: MarketplaceOwnedListing) async {
        guard await store.unpublish(listingID: listing.id, session: session) != nil else {
            notice = store.failure?.message
            return
        }
        notice = """
        상점에서 내렸어요. `판매 중지`에서 다시 올릴 수 있어요.
        등록비는 이미 냈으므로 다시 올릴 때 더 내지 않아요.
        """
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
