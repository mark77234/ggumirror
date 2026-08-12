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

    var id: String { rawValue }
}

struct StoreView: View {
    @Environment(ShardWallet.self) private var shards
    var library: MirrorLibrary?
    /// 내가 만든 스티커. 저장하면 이 화면이 바로 갱신된다(@Observable).
    var stickers: StickerLibrary = .live

    @State private var section: StoreSection = .mirror
    @State private var category: StoreCategory = .all
    @State private var tag: TagFilter = .all
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var templates: [MirrorTemplate] {
        StoreCatalog.samples.filter { template in
            template.matches(category) && (tag.tag.map(template.tags.contains) ?? true)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                sectionSwitch

                switch section {
                case .mirror:
                    // 거울 상점은 그대로다 — 템플릿 24개 · 갈래 · 가격 · 무료 수령 전부 유지.
                    filters
                    gallery
                case .sticker:
                    StickerStoreView(library: stickers, mirrors: library)
                }
            }
            .animation(InkMotion.modal, value: section)
            .navigationDestination(for: MirrorTemplate.self) { template in
                TemplateDetailView(template: template, library: library)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(PaperTheme.ink)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("상점")
                .font(InkFont.pageTitle)
                .foregroundStyle(PaperTheme.ink)

            Spacer(minLength: 12)

            // 조각 잔액 (표시 전용)
            HStack(spacing: 6) {
                ShardIcon(size: 15)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("보유 \(shards.balance) 조각")
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

    private var filters: some View {
        VStack(spacing: 8) {
            InkFilterBar(items: StoreCategory.allCases, selection: $category) { $0.rawValue }
            InkFilterBar(items: TagFilter.allCases, selection: $tag) { $0.label }
        }
        .padding(.bottom, 14)
    }

    private var gallery: some View {
        ScrollView {
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
                            StoreGalleryItem(template: template)
                        }
                        .buttonStyle(InkPressStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, InkTabBar.reservedHeight + 24, for: .scrollContent)
    }
}

/// Preview가 텍스트보다 훨씬 크게 보이도록, 카드 장식 없이 미리보기 + 최소 정보만 둔다.
private struct StoreGalleryItem: View {
    let template: MirrorTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            MirrorPreview(template: template)
                .padding(.bottom, 6)

            Text(template.name)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                Text(template.creator)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                ShardAmount(amount: template.price)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(template.name), \(template.creator), \(template.price == 0 ? "무료" : "\(template.price) 조각")"
        )
    }
}

/// 두 번째 필터 줄. "전체"를 포함하기 위해 StoreTag를 감싼다.
enum TagFilter: Identifiable, Equatable, CaseIterable {
    case all
    case tagged(StoreTag)

    static var allCases: [TagFilter] { [.all] + StoreTag.allCases.map(TagFilter.tagged) }

    var id: String { label }

    var label: String {
        switch self {
        case .all: "전체"
        case .tagged(let tag): tag.rawValue
        }
    }

    var tag: StoreTag? {
        switch self {
        case .all: nil
        case .tagged(let tag): tag
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
