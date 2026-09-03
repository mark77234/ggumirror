//
//  MarketplaceListingPreview.swift
//  ggumirror
//
//  **같은 상품은 어느 화면에서든 같게 보인다.**
//
//  예전에는 화면마다 미리보기를 따로 그렸다. 그러다 보니 규칙이 갈라졌다 —
//  상점과 `내 판매`는 `ListingPreviewStyle`을 따랐지만, 관리자 화면과 `내 상품`은
//  `.fill`을 직접 적어 두고 종류를 보지 않았다. 그래서 **스티커가 거울 모양 칸에
//  꽉 채워져 좌우가 잘렸다.** `ListingPreviewStyle`이 막으려던 바로 그 증상이,
//  그것을 쓰지 않는 화면에서 되살아나 있었다.
//
//  이 view는 **그리는 규칙만** 갖는다. 크기 · 테두리 · 배치는 화면이 정한다 —
//  격자 칸과 상세 화면은 원래 다르게 생겼고, 그걸 억지로 합치면 I-5처럼
//  격자용 geometry가 상세로 새어 든다.
//
//  운영자 동작(내리기 · 복구)은 여기 없다. 카드가 관리 권한을 알 이유가 없다.
//

import SwiftUI

struct MarketplaceListingPreview: View {
    /// `"mirror"` / `"sticker"`. **판정은 `ListingPreviewStyle` 하나가 한다.**
    let contentType: String
    /// 받아 둔 PNG. 아직 없으면 `nil`이다.
    var data: Data?
    /// 불러오지 못했는가. 대기와 실패는 **다른 말**을 한다.
    var didFail = false
    /// 모서리 모양. 화면마다 다르므로 받는다.
    var shape: UnevenRoundedRectangle

    var body: some View {
        ZStack {
            background
            content
        }
        // 칸의 비율은 종류가 정한다 — 거울은 거울 모양, 스티커는 정사각.
        .aspectRatio(
            ListingPreviewStyle.aspectRatio(for: contentType), contentMode: .fit
        )
    }

    /// 투명한 것이 정상인 스티커는 바탕을 깔아야 보인다.
    @ViewBuilder
    private var background: some View {
        if ListingPreviewStyle.showsTransparency(for: contentType) {
            TransparencyCheckerboard(cell: 10).clipShape(shape)
        } else {
            shape.fill(PaperTheme.subtleSurface)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                // **잘라낼지 맞출지도 종류가 정한다.** 스티커를 자르면 스티커가 아니다.
                .aspectRatio(contentMode: ListingPreviewStyle.contentMode(for: contentType))
                .clipShape(shape)
        } else if didFail {
            // 실패는 실패라고 둔다 — 가짜 그림을 만들지 않는다.
            Label("미리보기를 불러오지 못했어요", systemImage: "photo")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .labelStyle(.titleAndIcon)
                .multilineTextAlignment(.center)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(PaperTheme.separator)
        }
    }
}
