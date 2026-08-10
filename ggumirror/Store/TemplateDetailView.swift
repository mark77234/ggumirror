//
//  TemplateDetailView.swift
//  ggumirror
//
//  템플릿 상세. 이번 Phase는 UI와 flow만 — 실제 미리보기 연결/구매는 없다.
//

import SwiftUI

struct TemplateDetailView: View {
    let template: MirrorTemplate
    var library: MirrorLibrary?

    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                MirrorPreview(style: template.style, lineWidth: 2.1)
                    .frame(maxHeight: 420)
                    .padding(.top, 8)

                VStack(spacing: 6) {
                    Text(template.name)
                        .font(InkFont.pageTitle)
                        .foregroundStyle(PaperTheme.ink)
                        .multilineTextAlignment(.center)
                    Text(template.creator)
                        .font(InkFont.secondary)
                        .foregroundStyle(PaperTheme.secondaryInk)
                }

                tags

                HStack(spacing: 6) {
                    ShardIcon(size: 17)
                    Text(template.price == 0 ? "무료" : "\(template.price) 조각")
                        .font(InkFont.cardTitle)
                        .foregroundStyle(PaperTheme.ink)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(template.price == 0 ? "무료" : "\(template.price) 조각")

                actions
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, InkTabBar.reservedHeight + 24, for: .scrollContent)
        .paperBackground()
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("준비 중", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private var tags: some View {
        HStack(spacing: 7) {
            ForEach(template.tags) { tag in
                Text(tag.rawValue)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        UnevenRoundedRectangle.ink(14, 12, 15, 13)
                            .stroke(PaperTheme.separator, lineWidth: 1.4)
                    }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            // 1순위 CTA. 구매보다 먼저 보여야 한다(PRODUCT.md).
            Button {
                notice = "내 거울로 미리보기는 다음 업데이트에서 열려요."
            } label: {
                Text("내 거울로 미리보기")
                    .font(InkFont.cardTitle)
                    .foregroundStyle(PaperTheme.subtleSurface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .frame(minHeight: 44)
                    .background {
                        let shape = UnevenRoundedRectangle.ink(20, 24, 25, 19)
                        shape.fill(PaperTheme.ink)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(InkPressStyle())

            // 무료 템플릿은 지금 바로 받을 수 있다. 조각 결제는 아직 없다.
            Button {
                guard template.price == 0, let library else {
                    notice = "조각으로 받기는 다음 업데이트에서 열려요."
                    return
                }
                library.acquire(template)
                notice = "\(template.name)을(를) 내 거울에 담았어요."
            } label: {
                Text(template.price == 0 ? "무료로 받기" : "조각으로 받기")
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .frame(minHeight: 44)
                    .background {
                        let shape = UnevenRoundedRectangle.ink(20, 24, 25, 19)
                        shape.stroke(PaperTheme.ink, lineWidth: 1.8)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(InkPressStyle())
        }
        .padding(.top, 4)
    }
}

#Preview {
    NavigationStack {
        TemplateDetailView(template: StoreCatalog.samples[0])
    }
}
