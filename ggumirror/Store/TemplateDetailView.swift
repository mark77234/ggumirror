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
    /// 열려 있으면 미리보기 화면이 떠 있다. **받기와 무관하다** — 여기서는 아무것도 사지 않는다.
    @State private var preview: MirrorPreviewSubject?
    @State private var showsStorageFull = false
    @State private var isBuying = false
    /// 잔액은 서버가 authority다. 산 뒤 다시 읽기만 한다.
    @Environment(ShardWallet.self) private var wallet: ShardWallet?
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
        .mirrorLivePreview($preview, title: template.name)
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
                // 내장 템플릿은 모델을 그대로 갖고 있다 — 받을 필요가 없다.
                preview = .design(MirrorDesign(template: template))
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

    /// 사용자 상품과 **같은 상태 모델**을 쓴다. 1.1.0부터 내장에도 서버 소유권이 있다 —
    /// 사고 나서 기기에서 지운 사람에게 다시 사라고 하지 않기 위해서다.
    private var cta: MirrorAcquireCTA {
        MirrorAcquireCTA.state(
            price: template.price,
            isSignedIn: session.server != nil,
            ownsOnServer: catalogStats.isOwned(template.id),
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
            Task { await buy() }
        case .addToLibrary:
            // 이미 서버가 아는 내 것이다. **다시 사지 않는다** — 담기만 한다.
            addToLibrary()
        case .alreadyInLibrary, .ownListing:
            break
        }
    }

    /// 조각을 내고 산다. **잔액을 여기서 계산하지 않는다** — 서버가 옮기고,
    /// 우리는 서버가 준 값을 다시 읽는다.
    private func buy() async {
        guard !isBuying else { return }   // 연타로 두 번 보내지 않는다
        isBuying = true
        defer { isBuying = false }

        if let failure = await catalogStats.purchase(template.id, session: session.server) {
            notice = failure
            return
        }
        // 산 것과 담는 것은 별개다(사용자 상품과 같은 2단계) — 여기서 자동으로
        // 담지 않는다. 보관 공간이 없어도 소유권은 그대로 남는다.
        await wallet?.refresh(session: session.server)
        notice = "\(template.name)을(를) 샀어요. 내 거울에 추가할 수 있어요."
    }

    /// 산 것을 이 기기에 담는다. **조각이 빠지지 않는다.**
    private func addToLibrary() {
        guard let library else { return }
        guard library.acquire(template) != nil else {
            showsStorageFull = true
            return
        }
        notice = "\(template.name)을(를) 내 거울에 담았어요."
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
