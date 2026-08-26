//
//  AdminStoreView.swift
//  ggumirror
//
//  운영자 상점 관리. **화면 하나에서 거울과 스티커를 모두 다룬다.**
//
//  이 화면이 보인다고 권한이 있는 것이 아니다. 여기서 나가는 모든 요청은
//  서버가 다시 판단한다 — 화면을 강제로 열어도 403이 온다.
//
//  새 관리자 웹을 만들지 않았다. 새 hosting도 새 로그인도 필요 없고,
//  이미 있는 인증을 그대로 쓴다.
//

import SwiftUI

// MARK: - 상태

/// 운영 목록에서 무엇을 볼 것인가.
///
/// 종류(거울/스티커) 필터와 **다른 축이다** — 하나로 합치면 "스티커이면서
/// 내려간 것"을 고를 수 없다.
nonisolated enum AdminStatusFilter: String, CaseIterable, Sendable {
    /// 지금 상점에 있거나 판매자가 손볼 수 있는 것. **기본값.**
    case live
    /// 운영자가 내린 것. 복구할지 판단하는 화면이다.
    case removed
    /// 판매자가 삭제한 것까지 전부. 되살릴 수 없어 조치할 것은 없고, 기록을 볼 때만 쓴다.
    case all

    var label: String {
        switch self {
        case .live: "판매 중"
        case .removed: "내려감"
        case .all: "전체"
        }
    }

    func includes(_ listing: AdminListing) -> Bool {
        switch self {
        case .all: true
        case .removed: listing.isRemoved && !listing.isDeletedBySeller
        // 판매자가 삭제한 것은 끝 상태라 여기 오지 않는다.
        case .live: !listing.isRemoved && !listing.isDeletedBySeller
        }
    }
}

@MainActor
@Observable
final class AdminStore {
    private(set) var listings: [AdminListing] = []
    private(set) var isLoading = false
    private(set) var failure: AdminFailure?
    /// 지금 조치 중인 상품. **연타를 막는다** — 두 번 눌러도 요청은 한 번이다.
    private(set) var busyListingID: String?
    private var cursor: String?
    /// 다음 장이 남아 있는가. 첫 조회 전에는 아직 모른다.
    private(set) var hasMore = false

    var contentType: String?
    var query = ""
    /// 어떤 상태를 볼 것인가. **기본은 "지금 상점에 있는 것"이다.**
    ///
    /// 판매자가 삭제한 상품은 되살릴 수 없고 운영자가 할 일도 없다. 그것이
    /// 판매 중인 상품과 같은 목록에 섞여 있으면, 훑어보는 사람이 무엇을
    /// 조치해야 하는지 알 수 없다.
    var statusFilter: AdminStatusFilter = .live

    private let backend: any AdminBackend
    private var previews: [String: Data] = [:]

    init(backend: any AdminBackend = BackendClient()) {
        self.backend = backend
    }

    /// 화면에 보일 목록. 검색은 **받아 온 장 안에서만** 한다 —
    /// 전체 검색 색인을 만들 규모가 아니다.
    var visible: [AdminListing] {
        let matching = listings.filter { statusFilter.includes($0) }
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return matching }
        return matching.filter {
            $0.title.localizedCaseInsensitiveContains(text)
                || ($0.sellerDisplayName ?? "").localizedCaseInsensitiveContains(text)
        }
    }

    func reload(session: ServerSession?) async {
        cursor = nil
        listings = []
        hasMore = false
        await loadMore(session: session)
    }

    func loadMore(session: ServerSession?) async {
        guard !isLoading, let token = session?.accessToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await backend.adminListings(
                contentType: contentType, moderationStatus: nil,
                cursor: cursor, accessToken: token
            )
            // 같은 상품을 두 번 넣지 않는다 — 새로고침과 다음 장이 겹칠 수 있다.
            let known = Set(listings.map(\.id))
            listings += page.listings.filter { !known.contains($0.id) }
            cursor = page.cursor
            hasMore = page.cursor != nil
            failure = nil
        } catch let error as AdminFailure {
            failure = error
        } catch {
            failure = .network
        }
    }

    func preview(_ listingID: String) -> Data? { previews[listingID] }

    func loadPreview(_ listingID: String, session: ServerSession?) async {
        guard previews[listingID] == nil, let token = session?.accessToken else { return }
        previews[listingID] = try? await backend.adminPreview(
            listingID: listingID, accessToken: token
        )
    }

    /// 내린다. 성공하면 **그 자리에서 바꿔 넣는다** — 목록 전체를 다시 받지 않는다.
    func takedown(
        _ listingID: String, reason: AdminModerationReason, session: ServerSession?
    ) async -> Bool {
        await change(listingID, session: session) { backend, token in
            try await backend.takedown(listingID: listingID, reason: reason, accessToken: token)
        }
    }

    func restore(_ listingID: String, session: ServerSession?) async -> Bool {
        await change(listingID, session: session) { backend, token in
            try await backend.restore(listingID: listingID, accessToken: token)
        }
    }

    private func change(
        _ listingID: String,
        session: ServerSession?,
        _ call: (any AdminBackend, String) async throws -> AdminListing
    ) async -> Bool {
        // **이미 처리 중이면 두 번째 요청을 만들지 않는다.**
        guard busyListingID == nil, let token = session?.accessToken else { return false }
        busyListingID = listingID
        defer { busyListingID = nil }
        do {
            let updated = try await call(backend, token)
            if let index = listings.firstIndex(where: { $0.id == listingID }) {
                listings[index] = updated
            }
            failure = nil
            return true
        } catch let error as AdminFailure {
            // **실패하면 목록을 건드리지 않는다.** 화면이 거짓 상태를 보여주지 않는다.
            failure = error
            return false
        } catch {
            failure = .network
            return false
        }
    }
}

// MARK: - 화면

struct AdminStoreView: View {
    @Environment(AuthSession.self) private var session
    @State private var store = AdminStore()
    @State private var pendingTakedown: AdminListing?
    @State private var pendingRestore: AdminListing?
    @State private var notice: String?

    private let filters: [(label: String, value: String?)] = [
        ("전체", nil), ("거울", "mirror"), ("스티커", "sticker"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterRow
                statusRow
                    .padding(.bottom, 14)

                if store.visible.isEmpty && !store.isLoading {
                    Text(store.listings.isEmpty ? "상품이 없어요." : "이 조건에 맞는 상품이 없어요.")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                        .padding(.top, 40)
                }

                ForEach(store.visible) { listing in
                    row(listing)
                    InkSeparator()
                }

                if store.hasMore {
                    Button("더 보기") {
                        Task { await store.loadMore(session: session.server) }
                    }
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .padding(.vertical, 18)
                    .disabled(store.isLoading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        // 탭 막대에 가리지 않게 아래를 띄운다. 숫자는 막대가 정한다.
        .inkTabBarSafeContent()
        .paperBackground()
        .navigationTitle("상점 관리")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.query, prompt: "상품명 또는 판매자")
        .task { await store.reload(session: session.server) }
        .inkDialog(
            "상점에서 내리기",
            message: pendingTakedown.map {
                """
                \($0.title)

                새로운 사용자는 더 이상 이 상품을 구매할 수 없어요.
                이미 구매한 사용자는 계속 사용할 수 있어요.
                """
            },
            isPresented: Binding(
                get: { pendingTakedown != nil },
                set: { if !$0 { pendingTakedown = nil } }
            )
        ) {
            takedownActions
        }
        .inkDialog(
            "다시 공개하기",
            message: pendingRestore.map { "\($0.title)\n\n이 상품을 다시 공개할까요?" },
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            )
        ) {
            [
                InkDialogAction("취소", role: .secondary),
                InkDialogAction("다시 공개하기", role: .primary) {
                    if let listing = pendingRestore {
                        Task { await restore(listing) }
                    }
                },
            ]
        }
        .inkDialog(
            "상점 관리",
            message: notice,
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
    }

    /// 사유를 고르는 것이 곧 확인이다 — 확인창을 두 번 띄우지 않는다.
    private var takedownActions: [InkDialogAction] {
        AdminModerationReason.allCases.map { reason in
            InkDialogAction(reason.label) {
                if let listing = pendingTakedown {
                    Task { await takedown(listing, reason: reason) }
                }
            }
        } + [InkDialogAction("취소", role: .secondary)]
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(filters, id: \.label) { filter in
                Button(filter.label) {
                    guard store.contentType != filter.value else { return }
                    store.contentType = filter.value
                    Task { await store.reload(session: session.server) }
                }
                .font(InkFont.caption)
                .foregroundStyle(
                    store.contentType == filter.value ? PaperTheme.ink : PaperTheme.secondaryInk
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    Capsule().stroke(
                        store.contentType == filter.value
                            ? PaperTheme.ink : PaperTheme.separator,
                        lineWidth: 1.4
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    /// 상태 줄. 종류 칩과 **같은 생김새**를 쓴다 — 두 줄이 다르게 보이면
    /// 둘이 같은 종류의 선택이라는 것이 읽히지 않는다.
    private var statusRow: some View {
        HStack(spacing: 8) {
            ForEach(AdminStatusFilter.allCases, id: \.self) { option in
                Button(option.label) {
                    guard store.statusFilter != option else { return }
                    store.statusFilter = option
                }
                .font(InkFont.caption)
                .foregroundStyle(
                    store.statusFilter == option ? PaperTheme.ink : PaperTheme.secondaryInk
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    Capsule().stroke(
                        store.statusFilter == option ? PaperTheme.ink : PaperTheme.separator,
                        lineWidth: 1.4
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private func row(_ listing: AdminListing) -> some View {
        let isBusy = store.busyListingID == listing.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // **생김새를 보여준다** — 제목만 보고 내릴지 판단할 수 없다.
                preview(listing)

                VStack(alignment: .leading, spacing: 5) {
                    Text(listing.title)
                        .font(InkFont.body)
                        .foregroundStyle(PaperTheme.ink)
                        .lineLimit(2)
                    Text("\(listing.sellerLabel) · \(listing.isMirror ? "거울" : "스티커")")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                    HStack(spacing: 10) {
                        ShardAmount(amount: listing.priceShards, font: InkFont.caption, iconSize: 13)
                        Label("\(listing.downloadCount)", systemImage: "arrow.down")
                        Label("\(listing.likeCount)", systemImage: "heart")
                    }
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .labelStyle(.titleAndIcon)
                    .imageScale(.small)
                    Text(listing.statusLabel)
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                }
                Spacer(minLength: 0)
            }

            if listing.isRemoved, let reason = listing.reasonLabel {
                Text("운영자에 의해 내려간 상품 · 사유: \(reason)")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
            }

            HStack(spacing: 8) {
                if listing.isRemoved {
                    // 판매자가 삭제한 것은 되살릴 수 없다 — 버튼을 주지 않는다.
                    if !listing.isDeletedBySeller {
                        action("다시 공개하기") { pendingRestore = listing }
                    }
                } else if !listing.isDeletedBySeller {
                    action("상점에서 내리기") { pendingTakedown = listing }
                }
                Spacer(minLength: 0)
            }
            .disabled(isBusy)
        }
        .padding(.vertical, 12)
        .task { await store.loadPreview(listing.id, session: session.server) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(listing.title), \(listing.sellerLabel), \(listing.statusLabel)"
        )
    }

    private func preview(_ listing: AdminListing) -> some View {
        let shape = UnevenRoundedRectangle.ink(14, 12, 15, 13)
        return Group {
            if let data = store.preview(listing.id), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                PaperTheme.subtleSurface
            }
        }
        .frame(width: 62, height: 62 * MirrorCanvas.aspectRatio)
        .clipShape(shape)
        .overlay { shape.stroke(PaperTheme.separator, lineWidth: 1.2) }
    }

    private func action(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background { Capsule().stroke(PaperTheme.separator, lineWidth: 1.4) }
        }
        .buttonStyle(InkPressStyle())
    }

    private func takedown(_ listing: AdminListing, reason: AdminModerationReason) async {
        if await store.takedown(listing.id, reason: reason, session: session.server) {
            notice = "상점에서 내렸어요. 이미 구매한 사용자는 계속 사용할 수 있어요."
        } else {
            notice = store.failure?.message
        }
    }

    private func restore(_ listing: AdminListing) async {
        if await store.restore(listing.id, session: session.server) {
            notice = "다시 공개했어요."
        } else {
            notice = store.failure?.message
        }
    }
}
