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
    @State private var showsStorageFull = false
    @Environment(CatalogStats.self) private var catalogStats
    @Environment(AuthSession.self) private var session

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
        .inkMirrorStorageFullDialog(
            "받으려면", isPresented: $showsStorageFull, library: library
        )
    }

    /// 카드보다 조금 더 또렷하게. 값의 출처는 카드와 **같은 model field**다.
    /// **서버가 세지 않는 값은 보여 주지 않는다**(카드와 같은 규칙).
    @ViewBuilder
    private var metadata: some View {
        VStack(spacing: 4) {
            if let count = catalogStats.downloadCount(template.id) {
                Label("다운로드 \(count)", systemImage: "arrow.down")
            }
            Text(uploadedLine)
        }
        .font(InkFont.caption)
        .foregroundStyle(PaperTheme.secondaryInk)
        .imageScale(.small)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            catalogStats.downloadCount(template.id)
                .map { "다운로드 \($0), \(uploadedLine)" } ?? uploadedLine
        )
    }

    private var uploadedLine: String {
        template.uploadedAt == nil ? "업로드 날짜 없음" : "\(template.uploadedAtLabel) 업로드"
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

            // 사용자 상품과 **같은 상태 모델**을 쓴다(`MirrorAcquireCTA`).
            // 출처가 내장인지 남이 올린 것인지 몰라도 같은 문구·같은 흐름이다.
            Button {
                acquire()
            } label: {
                Text(cta.title)
                    .font(InkFont.body)
                    .foregroundStyle(cta.isEnabled ? PaperTheme.ink : PaperTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .frame(minHeight: 44)
                    .background {
                        let shape = UnevenRoundedRectangle.ink(20, 24, 25, 19)
                        shape.stroke(
                            cta.isEnabled ? PaperTheme.ink : PaperTheme.separator, lineWidth: 1.8
                        )
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(InkPressStyle())
            .disabled(!cta.isEnabled)
        }
        .padding(.top, 4)
    }

    /// 사용자 상품과 공유하는 상태 모델. 내장에는 서버 소유권 개념이 없다.
    private var cta: MirrorAcquireCTA {
        MirrorAcquireCTA.state(
            price: template.price,
            isSignedIn: session.server != nil,
            existsLocally: isOwned
        )
    }

    /// 상태에 맞는 동작 하나. 화면에 분기를 흩뿌리지 않는다.
    private func acquire() {
        switch cta {
        case .needsSignIn:
            _ = session.requireSignIn(for: .shardTransaction)
        case .acquireFree:
            guard let library else { return }
            guard library.acquire(template) != nil else {
                showsStorageFull = true
                return
            }
            notice = "\(template.name)을(를) 내 거울에 담았어요."
            // **로컬 저장이 끝난 뒤에** 서버에 남긴다.
            Task { await catalogStats.recordAcquisition(template.id, session: session.server) }
        case .purchase:
            // 내장 유료 템플릿의 조각 결제는 아직 서버 경로가 없다.
            notice = "조각으로 받기는 다음 업데이트에서 열려요."
        case .addToLibrary, .alreadyInLibrary, .ownListing:
            break
        }
    }

    /// 이 템플릿이 이미 내 거울에 있는가. `acquire`가 `MyMirror.id = template.id`로
    /// 저장하므로 그대로 맞는다. **제목으로 찾지 않는다.**
    private var isOwned: Bool {
        library?.mirrors.contains { $0.id == template.id } ?? false
    }

}

#Preview {
    NavigationStack {
        TemplateDetailView(template: StoreCatalog.samples[0])
    }
}
