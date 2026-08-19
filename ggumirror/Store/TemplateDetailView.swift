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
                MirrorPreview(template: template, lineWidth: 2.1)
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
                    ShardIcon(size: 18)
                    Text(template.price == 0 ? "무료" : "\(template.price) 조각")
                        .font(InkFont.cardTitle)
                        .foregroundStyle(PaperTheme.ink)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(template.price == 0 ? "무료" : "\(template.price) 조각")

                metadata

                actions
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, InkTabBar.reservedHeight + 24, for: .scrollContent)
        .paperBackground()
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .inkDialog(
            "준비 중",
            message: notice,
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
    }

    /// 카드보다 조금 더 또렷하게. 값의 출처는 카드와 **같은 model field**다.
    private var metadata: some View {
        VStack(spacing: 4) {
            HStack(spacing: 14) {
                Label("다운로드 \(template.downloadCount)", systemImage: "arrow.down")
                Label("좋아요 \(template.likeCount)", systemImage: "heart")
            }
            Text(uploadedLine)
        }
        .font(InkFont.caption)
        .foregroundStyle(PaperTheme.secondaryInk)
        .imageScale(.small)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "다운로드 \(template.downloadCount), 좋아요 \(template.likeCount), \(uploadedLine)"
        )
    }

    private var uploadedLine: String {
        template.uploadedAt == nil ? "업로드 날짜 없음" : "\(template.uploadedAtLabel) 업로드"
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
