//
//  MarketplaceListingCard.swift
//  ggumirror
//
//  **상품 카드는 하나뿐이다.** 어느 화면에서 보든 같은 물건은 같게 생겼다.
//
//  세 화면이 같은 상품을 서로 다른 모양으로 보여 주고 있었다:
//
//      공개 상점      2열 격자 + 카드
//      내 판매        가로로 꽉 찬 줄
//      상점 관리      작은 썸네일 왼쪽 + 글자 오른쪽
//
//  `MarketplaceListingPreview`(그림 그리는 규칙)는 이미 셋이 공유하고 있었지만,
//  **그 그림을 감싼 카드**는 화면마다 따로 있었다. 그래서 규칙이 갈라질 자리가
//  셋이었고, 실제로 갈라졌다 — 판매자와 운영자는 상점에서 보던 것과 다른 화면을 봤다.
//
//  이 파일이 그 카드 하나다. 화면이 정하는 것은 **무엇을 담을지와 무엇을 할지**뿐이다:
//  칸 비율 · content mode · 투명 바탕 · 자리표시자 · 실패 표시는 여기서 한 번만 정해지고,
//  그 판단은 전부 `ListingPreviewStyle`에게 묻는다. 화면이 `.fill`을 직접 적는 길이 없다.
//
//  운영 정책은 여기 없다. 카드는 누가 내릴 수 있는지도, 무엇이 끝 상태인지도 모른다 —
//  버튼을 줄지는 화면이 정하고, 실제 판단은 서버가 한다.
//

import SwiftUI

/// **격자 하나의 규칙.** 상점 · 내 판매 · 상점 관리가 이 값만 쓴다.
///
/// 예전에는 화면마다 `GridItem(...)`과 간격 숫자를 따로 적었다. 값이 같아 보여도
/// 한 곳을 고치면 나머지가 따라오지 않아, 세 화면이 조금씩 다른 격자로 갈라진다.
///
/// 2열이 기본이고 큰 글씨 설정에서는 이름이 뭉개지지 않게 1열로 바꾼다.
enum GalleryLayout {
    static func columns(for size: DynamicTypeSize) -> [GridItem] {
        let count = size.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    /// 줄 사이 간격.
    static let spacing: CGFloat = 18
    /// 격자 좌우 여백. 화면마다 따로 적지 않는다.
    static let horizontalPadding: CGFloat = 20
}

/// 카드 아래에 붙는 **하나뿐인** 동작.
///
/// 격자 칸은 좁다. 관리 버튼을 여러 개 붙이면 상품이 아니라 버튼 목록이 된다.
/// 다행히 상태마다 할 수 있는 일은 실제로 하나씩이다 —
/// 판매 중이면 삭제, 등록 미완료면 올리기, 내려간 것이면 다시 공개.
struct MarketplaceCardAction {
    let title: String
    var isEnabled = true
    let run: () -> Void
}

/// 서버에서 받은 상품 하나를 격자 칸 하나로 그린다.
struct MarketplaceListingCard: View {
    let model: StoreMirrorCardModel
    /// 받아 둔 미리보기 PNG. 아직 없으면 `nil`이다.
    var preview: Data?
    /// 불러오지 못했는가. 대기와 실패는 다른 말을 한다.
    var didFail = false
    /// 하트. 공개 상점에서만 넘긴다 — 관리 화면에는 누를 하트가 없다.
    var like: StoreMirrorCardLike?
    /// 관리 동작. 공개 상점은 `nil`이다(카드 전체가 이미 상세로 가는 버튼이다).
    var action: MarketplaceCardAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StoreMirrorCard(model: model, like: like) {
                let shape = StoreMirrorCardMetrics.previewShape
                MarketplaceListingPreview(
                    contentType: model.contentType,
                    data: preview,
                    didFail: didFail,
                    shape: shape
                )
                .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.regular))
            }

            if let action {
                actionButton(action)
            }
        }
    }

    /// 칸 폭을 꽉 채우는 버튼 하나. 카드가 이미 `Button`(공개 상점) 안에 있을 때는
    /// `action`이 `nil`이라 **버튼이 버튼 안에 들어가는 일이 없다.**
    private func actionButton(_ action: MarketplaceCardAction) -> some View {
        Button(action: action.run) {
            Text(action.title)
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: InkTapTarget.minimum)
                .background {
                    UnevenRoundedRectangle.ink(14, 12, 15, 13)
                        .stroke(PaperTheme.ink, lineWidth: 1.6)
                }
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .disabled(!action.isEnabled)
    }
}
