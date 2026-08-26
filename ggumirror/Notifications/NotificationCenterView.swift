//
//  NotificationCenterView.swift
//  ggumirror
//
//  알림센터. **push가 실패해도 여기서는 보인다** — 기록과 전달은 다른 것이다.
//
//  판매 현황의 숫자는 알림 개수를 센 것이 아니다. 서버가 구매와 같은 transaction
//  에서 올린 값이라, 목록을 몇 장 불러왔는지와 무관하게 정확한 총계다.
//

import SwiftUI

@MainActor
@Observable
final class NotificationSession {
    private(set) var notifications: [SaleNotification] = []
    private(set) var stats: [SaleStat] = []
    private(set) var isLoading = false
    private(set) var failure: NotificationFailure?
    private(set) var hasMore = false

    private var cursor: String?
    /// 지금 담겨 있는 것이 **누구의** 알림인가.
    ///
    /// 계정이 바뀌면 지운다 — A의 판매 소식이 B의 화면에 남으면 안 된다.
    private var ownerID: String?

    private let backend: any NotificationBackend

    init(backend: any NotificationBackend = BackendClient()) {
        self.backend = backend
    }

    var unreadCount: Int { notifications.count { !$0.read } }

    /// 계정이 바뀌었으면 비운다. **로그아웃도 여기로 온다.**
    func adopt(_ session: ServerSession?) {
        guard ownerID != session?.userID else { return }
        ownerID = session?.userID
        notifications = []
        stats = []
        cursor = nil
        hasMore = false
        failure = nil
    }

    func reload(session: ServerSession?) async {
        adopt(session)
        cursor = nil
        notifications = []
        stats = []
        await loadMore(session: session)
        await loadStats(session: session)
    }

    func loadMore(session: ServerSession?) async {
        guard !isLoading, let session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await backend.notifications(
                cursor: cursor, accessToken: session.accessToken
            )
            let known = Set(notifications.map(\.id))
            notifications += page.notifications.filter { !known.contains($0.id) }
            cursor = page.cursor
            hasMore = page.cursor != nil
            failure = nil
        } catch let error as NotificationFailure {
            failure = error
        } catch {
            failure = .network
        }
    }

    private func loadStats(session: ServerSession?) async {
        guard let session else { return }
        stats = (try? await backend.saleStats(accessToken: session.accessToken)) ?? []
    }

    /// 읽음으로 바꾼다. 실패하면 **화면을 바꾸지 않는다.**
    func markRead(_ id: String, session: ServerSession?) async {
        guard let session,
              let index = notifications.firstIndex(where: { $0.id == id }),
              !notifications[index].read
        else { return }
        guard let updated = try? await backend.markNotificationRead(
            id: id, accessToken: session.accessToken
        ) else { return }
        notifications[index] = updated
    }
}

struct NotificationCenterView: View {
    /// 모아 보기를 눌렀을 때 상점으로 보내는 길. 없으면 읽음 처리만 한다.
    var onOpenStore: (() -> Void)?

    @Environment(AuthSession.self) private var session
    @State private var store = NotificationSession()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if session.server == nil {
                    signedOut
                } else {
                    if !store.stats.isEmpty {
                        salesSection
                        InkSeparator()
                            .padding(.vertical, 6)
                    }

                    if store.notifications.isEmpty && !store.isLoading {
                        Text("아직 판매 소식이 없어요.")
                            .font(InkFont.caption)
                            .foregroundStyle(PaperTheme.secondaryInk)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }

                    ForEach(store.notifications) { item in
                        row(item)
                        InkSeparator()
                    }

                    if store.hasMore {
                        Button("더 보기") {
                            Task { await store.loadMore(session: session.server) }
                        }
                        .font(InkFont.body)
                        .foregroundStyle(PaperTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .disabled(store.isLoading)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        // 탭 막대에 가리지 않게 아래를 띄운다. 숫자는 막대가 정한다.
        .inkTabBarSafeContent()
        .paperBackground()
        .navigationTitle("알림")
        .navigationBarTitleDisplayMode(.inline)
        // 계정이 바뀌면 다시 받는다 — `id:`라 로그아웃에도 걸린다.
        .task(id: session.server?.userID) { await store.reload(session: session.server) }
    }

    private var signedOut: some View {
        VStack(spacing: 10) {
            Text("로그인하면 판매 소식을 볼 수 있어요.")
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
            Text("거울과 스티커를 만들고 꾸미는 건 로그인 없이도 계속할 수 있어요.")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var salesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("판매 현황")
                .font(InkFont.sectionTitle)
                .foregroundStyle(PaperTheme.ink)
                .padding(.top, 14)

            ForEach(store.stats) { stat in
                HStack(spacing: 8) {
                    Text(stat.title)
                        .font(InkFont.body)
                        .foregroundStyle(PaperTheme.ink)
                        .lineLimit(1)
                    Text(stat.isMirror ? "거울" : "스티커")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                    Spacer(minLength: 6)
                    Text("\(stat.saleCount)회")
                        .font(InkFont.body)
                        .foregroundStyle(PaperTheme.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(stat.title), \(stat.saleCount)회 판매")
            }
        }
    }

    private func row(_ item: SaleNotification) -> some View {
        Button {
            Task { await store.markRead(item.id, session: session.server) }
            // 모아 보기는 상품 하나가 아니라 **상점**으로 간다.
            if item.kind == .mirrorDigest { onOpenStore?() }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // 안 읽은 것에만 점을 찍는다. 배지 체계를 만들지 않는다.
                Circle()
                    .fill(item.read ? Color.clear : PaperTheme.ink)
                    .frame(width: 7, height: 7)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 4) {
                    // 문구는 model이 정한다 — 종류마다 화면이 분기하지 않는다.
                    Text(item.displayTitle)
                        .font(InkFont.body)
                        .foregroundStyle(PaperTheme.ink)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        Text(item.displayBody)
                            .font(InkFont.caption)
                            .foregroundStyle(
                                item.kind == .sale ? PaperTheme.ink : PaperTheme.secondaryInk
                            )
                        // 판매 알림에만 종류가 있다. 모아 보기는 상품 하나가 아니다.
                        if item.kind == .sale {
                            Text(item.isMirror ? "거울" : "스티커")
                        }
                        Text(Self.when.string(for: item.createdAt) ?? "")
                    }
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel(
            "\(item.displayTitle), \(item.displayBody), \(item.read ? "읽음" : "안 읽음")"
        )
    }

    private static let when: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
