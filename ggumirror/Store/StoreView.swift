//
//  StoreView.swift
//  ggumirror
//
//  상점. 2열 Gallery가 주인공이다.
//  실제 구매 / 로그인 / 서버 데이터는 아직 없다.
//

import SwiftUI

/// 상점 안의 두 칸. **새 Bottom Tab을 만들지 않는다** — 상점 내부만 나눈다.
enum StoreSection: String, CaseIterable, Identifiable, Hashable {
    case mirror = "거울"
    case sticker = "스티커"
    /// 내가 올린 상품 관리. **공개 목록과 섞지 않는다** —
    /// 섞여 있으면 아직 안 올린 것과 실제 판매 중인 것을 구분할 수 없다.
    case mySales = "내 판매"

    var id: String { rawValue }
}

struct StoreView: View {
    @Environment(ShardWallet.self) private var shards
    // 조각 상점은 **RootView가 소유한 하나**를 그대로 쓴다 — 새 controller를 만들지 않는다.
    @Environment(ShardPurchaseController.self) private var shardStore
    @Environment(AuthSession.self) private var session
    // 상점 서버 상태는 RootView가 소유한 하나를 쓴다.
    @Environment(MarketplaceStore.self) private var marketplace
    @Environment(CatalogStats.self) private var catalogStats
    var library: MirrorLibrary?
    /// 내가 만든 스티커. 저장하면 이 화면이 바로 갱신된다(@Observable).
    var stickers: StickerLibrary = .live

    @State private var section: StoreSection = .mirror
    /// 조각 충전. Home · AI와 **같은 시트**다.
    @State private var isShowingShardStore = false
    /// 공개 상점의 유일한 필터. 디자인 갈래는 없앴다.
    @State private var priceFilter: StorePriceFilter = .default
    /// 상점에 들어오면 언제나 최신 순이다. 선택은 저장하지 않는다.
    @State private var sort: StoreSort = .default
    /// 사용자 상품 카드는 `NavigationLink(value:)`가 아니라 Button이라(카드 안에서
    /// preview를 받아오기 때문에) 경로를 직접 밀어 넣는다.
    @State private var path = NavigationPath()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var templates: [MirrorTemplate] {
        // 걸러낸 뒤 정렬한다. 정렬은 **로컬 목록 기준**이라 네트워크를 다시 부르지 않는다.
        // 필터와 정렬은 독립이다 — `무료 + 인기 순`이 그대로 성립한다.
        sort.sorted(StoreCatalog.samples.filter { priceFilter.includes(price: $0.price) })
    }

    var body: some View {
        NavigationStack(path: $path) {
            // **상단 제어부를 고정하지 않는다.** 제목 · 잔액 · 거울/스티커 · 갈래 · 꼬리표 ·
            // 정렬이 모두 상품과 같은 scroll content 안에 있어서, 아래로 내리면 함께
            // 위로 사라진다. 고정해 두면 실제 상품이 보이는 세로 공간이 너무 좁았다.
            //
            // scroll은 **여기 하나뿐**이다. 안쪽(거울 grid · 스티커 화면)에 또 만들면
            // 세로 scroll이 중첩되고 상단이 따라 올라가지 않는다.
            ScrollView {
                VStack(spacing: 0) {
                    header
                    sectionSwitch

                    switch section {
                    case .mirror:
                        // 거울 상점은 그대로다 — 템플릿 24개 · 갈래 · 가격 · 무료 수령 전부 유지.
                        filters
                        mirrorContent
                    case .sticker:
                        StickerStoreView(library: stickers, mirrors: library)
                    case .mySales:
                        MySalesSection(
                            store: marketplace,
                            session: session.server,
                            wallet: shards
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            // UI-P2 그대로 — tab bar가 마지막 상품을 덮지 않게 한다.
            .inkTabBarSafeContent()
            // 내장 템플릿 다운로드 수는 **한 번에** 받는다(카드마다 부르지 않는다).
            .task {
                await catalogStats.refresh()
                // 예전 버전 · 로그아웃 상태에서 받은 것을 한 번 따라잡는다.
                await catalogStats.reconcile(
                    ownedTemplateIDs: StoreCatalog.ownedTemplateIDs(
                        in: library?.mirrors ?? []
                    ),
                    session: session.server
                )
            }
            .animation(InkMotion.modal, value: section)
            .navigationDestination(for: MirrorTemplate.self) { template in
                TemplateDetailView(template: template, library: library)
            }
            .navigationDestination(for: MarketplaceListing.self) { listing in
                MarketplaceListingDetailView(
                    listing: listing,
                    store: marketplace,
                    session: session.server,
                    wallet: shards,
                    library: library,
                    stickers: stickers,
                    mirrorStore: library?.assetStore,
                    stickerStore: stickers.assetStore,
                    onNeedsSignIn: { _ = session.requireSignIn(for: .shardTransaction) }
                )
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(PaperTheme.ink)
        // Home · AI와 **같은 시트**, 같은 controller/wallet. 상점 UI를 또 만들지 않는다.
        .inkBottomSheet(isPresented: $isShowingShardStore, size: .fraction(0.7)) {
            ShardStoreSheet(
                controller: shardStore,
                wallet: shards,
                session: session.server,
                onNeedsSignIn: { _ = session.requireSignIn(for: .shardTransaction) }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("상점")
                .font(InkFont.pageTitle)
                .foregroundStyle(PaperTheme.ink)

            Spacer(minLength: 12)

            // 조각 잔액. 탭하면 충전 — **생김새는 그대로 둔다.**
            Button {
                isShowingShardStore = true
            } label: {
                HStack(spacing: 6) {
                    ShardIcon(size: 16)
                    Text("\(shards.balance) 조각")
                        .font(InkFont.secondary)
                        .foregroundStyle(PaperTheme.ink)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background {
                    UnevenRoundedRectangle.ink(16, 13, 17, 12)
                        .stroke(PaperTheme.ink, lineWidth: 1.7)
                        .rotationEffect(.degrees(0.3))
                }
                // 칩이 작아도 손가락이 닿는 자리는 44pt 이상이어야 한다.
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(InkPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("보유 \(shards.balance) 조각. 조각 구매")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("openShardStoreFromStore")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    /// 거울 / 스티커 전환. 시스템 세그먼트 대신 잉크 칩 두 개를 쓴다.
    private var sectionSwitch: some View {
        HStack(spacing: 8) {
            ForEach(StoreSection.allCases) { item in
                let isActive = section == item
                Button {
                    // **판매 관리는 로그인이 필요하다.** 빈 목록이나 401을 보여 주지 않고
                    // 바로 안내한다 — 취소하면 보고 있던 갈래가 그대로 남는다.
                    guard item != .mySales || session.server != nil else {
                        _ = session.requireSignIn(for: .shardTransaction)
                        return
                    }
                    section = item
                } label: {
                    Text(item.rawValue)
                        .font(InkFont.button)
                        .foregroundStyle(isActive ? PaperTheme.paper : PaperTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background {
                            let shape = UnevenRoundedRectangle.ink(16, 13, 17, 12)
                            shape
                                .fill(isActive ? PaperTheme.ink : PaperTheme.subtleSurface)
                                .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.regular))
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    /// 상단 제어부. **두 줄뿐이다** — 무엇을 보여 줄지(가격)와 어떤 순서인지.
    ///
    /// 예전에는 디자인 갈래와 꼬리표까지 네 줄이었다. 고를수록 상품이 사라졌고,
    /// 사용자 상품에는 그 값이 아예 없어서 갈래를 고르면 통째로 안 보였다.
    private var filters: some View {
        VStack(spacing: 8) {
            InkFilterBar(items: StorePriceFilter.allCases, selection: $priceFilter) { $0.rawValue }
            // 정렬도 같은 칩 줄을 쓴다 — 새 UI 언어를 만들지 않는다.
            InkFilterBar(items: StoreSort.allCases, selection: $sort) { $0.label }
        }
        .padding(.bottom, 14)
    }

    /// 거울 상점의 상품 부분. **자기 ScrollView를 갖지 않는다** —
    /// 상단 제어부와 같은 scroll 안에 있어야 함께 밀려 올라간다.
    ///
    /// 순서: 내 상점 상품 → 사용자 상품 → 내장 템플릿.
    /// 판매자가 자기 것을 먼저 찾을 수 있어야 한다.
    private var mirrorContent: some View {
        VStack(spacing: 0) {
            // **판매자 관리는 여기 없다.** `내 판매` 탭으로 갔다 —
            // 공개 목록에 draft가 섞이면 무엇이 실제로 팔리는 중인지 알 수 없다.
            MarketplaceSection(
                contentType: "mirror",
                store: marketplace,
                sort: sort,
                session: session.server,
                onSelect: { path.append($0) },
                onNeedsSignIn: { _ = session.requireSignIn(for: .shardTransaction) }
            )

            if templates.isEmpty {
                Text("이 조건에 맞는 거울이 아직 없어요.")
                    .font(InkFont.secondary)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: GalleryLayout.columns(for: dynamicTypeSize), spacing: 18) {
                    ForEach(templates) { template in
                        NavigationLink(value: template) {
                            // **서버가 센 값**을 넘긴다. 모르면 nil이고 카드가 숫자를
                            // 만들어내지 않는다.
                            StoreGalleryItem(
                                template: template,
                                downloadCount: catalogStats.downloadCount(template.id)
                            )
                        }
                        .buttonStyle(InkPressStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        // **공개 목록은 여기서 받아온다.** 상품 구획 안에 두면 목록이 비었을 때
        // 그 view가 그려지지 않아 영원히 요청이 나가지 않는다.
        .task(id: "mirror-\(sort.rawValue)-\(marketplace.publicFeedVersion)") {
            await marketplace.refresh(
                contentType: "mirror", sort: sort, session: session.server
            )
        }
    }
}

/// Preview가 텍스트보다 훨씬 크게 보이도록, 카드 장식 없이 미리보기 + 최소 정보만 둔다.
private struct StoreGalleryItem: View {
    let template: MirrorTemplate
    /// 서버가 센 다운로드 수. **`nil`이면 아직 모르는 것이고 `0`이 아니다** —
    /// 받아오기 전에 0을 보여 주면 "아무도 안 받았다"는 거짓말이 된다.
    var downloadCount: Int?

    /// 사용자 상품과 **같은 카드**를 쓴다(`StoreMirrorCard`). 이 카드가 기준이었고,
    /// 사용자 상품을 여기에 맞췄다 — 모양이 다시 갈라지지 않게 컴포넌트를 공유한다.
    ///
    /// 하트를 넘기지 않는다: 내장 템플릿에는 좋아요를 세는 서버 domain이 없다.
    /// 똑같아 보이게 하려고 `♡ 0`을 지어내지 않는다.
    var body: some View {
        StoreMirrorCard(
            model: StoreMirrorCardModel(
                title: template.name,
                subtitle: template.creator,
                price: template.price,
                downloadCount: downloadCount,
                footnote: template.uploadedAtLabel
            )
        ) {
            MirrorPreview(template: template)
        }
    }
}

/// Gallery는 2열이 기본. 큰 글씨 설정에서는 이름이 뭉개지지 않게 1열로 바꾼다.
enum GalleryLayout {
    static func columns(for size: DynamicTypeSize) -> [GridItem] {
        let count = size.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }
}

#Preview {
    StoreView()
        .paperBackground()
}
