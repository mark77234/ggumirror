//
//  StoreMirrorCard.swift
//  ggumirror
//
//  **상점의 거울 카드는 하나뿐이다.**
//
//  사용자 상품과 내장 템플릿이 서로 다른 카드처럼 보였다 — 사용자 상품만 작은 거울을
//  왼쪽에 붙이고 정보를 오른쪽에 세웠고, 하트는 카드 밖에 따로 떠 있었다.
//  같은 상점에서 같은 종류의 물건인데 **다른 물건처럼** 보였다.
//
//  기준은 **원래 있던 내장 템플릿 카드**다. 사용자 상품을 그쪽에 맞춘다 —
//  예쁘게 만들겠다고 멀쩡한 쪽을 갈아엎지 않는다.
//
//      ┌──────────┐
//      │   거울    │   ← 카드의 주인공
//      └──────────┘
//      제목
//      만든이            ◇ 가격
//      ↓ N   ♡ N              날짜
//
//  차이는 **데이터뿐**이다. 내장 템플릿에는 좋아요 domain이 없으므로 하트 자리를
//  비운다 — 똑같아 보이게 하려고 `♡ 0`을 지어내지 않는다.
//
//  스티커도 **이 카드를 쓴다.** 예전에는 스티커만 자기 카드를 따로 갖고 있었는데,
//  이유는 디자인이 아니라 이 파일이 거울 비율을 못 박아 두었기 때문이다 —
//  정사각 스티커를 세로로 긴 칸에 넣을 수 없으니 카드를 하나 더 만든 것이다.
//  칸 비율을 `ListingPreviewStyle`에서 받아오면 그 이유가 사라진다.
//

import SwiftUI

/// **카드 하나의 자리 규칙.** 모든 거울 카드가 이 값만 쓴다.
///
/// 같은 component를 쓴다고 해서 실제로 같은 크기가 되지는 않았다 — 실기기에서
/// 사용자 상품과 내장 템플릿, 심지어 **내 상품과 남의 상품**이 서로 다른 높이로
/// 보였다. 원인은 통계 줄이었다: 남의 상품에만 하트 Button이 있고 그 tap target이
/// 44pt라서 그 카드만 줄이 44pt로 부풀었다. 내장 템플릿(하트 없음)과 내 상품
/// (하트 있지만 누를 수 없어 44pt frame 없음)은 caption 높이였다.
///
/// 그래서 **높이를 데이터가 정하지 않게** 한다 — 자리를 미리 잡아 두고 내용이
/// 없으면 비워 둔다. 화면을 보고 padding을 더하는 방식이 아니다.
enum StoreMirrorCardMetrics {
    /// 칸의 모서리. **상점 · 내 판매 · 상점 관리가 같은 모양을 쓴다.**
    static let previewShape = UnevenRoundedRectangle.ink(20, 24, 25, 19)
    /// 칸과 제목 사이.
    static let previewSpacing: CGFloat = 6
    /// 글자 줄 사이.
    static let rowSpacing: CGFloat = 3
    /// 통계 줄의 **고정** 높이. 하트가 있든 없든 같다.
    ///
    /// 값이 44pt인 이유는 하트가 눌리는 자리가 44pt여야 하기 때문이다
    /// (`InkTapTarget.minimum`). 하트가 없는 카드도 같은 자리를 비워 둔다 —
    /// 없는 값을 `♡ 0`으로 지어내는 대신 **자리만** 맞춘다.
    static let metadataHeight = InkTapTarget.minimum
}

/// 카드가 보여 주는 값. 두 출처가 같은 모양으로 바뀌어 들어온다.
struct StoreMirrorCardModel {
    /// `"mirror"` / `"sticker"`. **판정은 `ListingPreviewStyle` 하나가 한다** —
    /// 카드가 종류를 다시 해석하지 않고 칸 비율만 그것에게 묻는다.
    /// 내장 템플릿은 언제나 거울이라 기본값이 있다.
    var contentType: String = "mirror"
    let title: String
    /// 만든이 / 판매자. **없으면 비워 둔다** — 가짜 이름을 지어내지 않는다.
    /// 사용자 상품에는 공개 판매자 이름이 없다(공개 DTO에 담지 않는 값이다).
    var subtitle: String?
    let price: Int
    /// 서버가 센 값. **`nil`이면 아직 모르는 것이고 `0`이 아니다.**
    var downloadCount: Int?
    /// 업로드 날짜 라벨. 올라온 적 없으면 그렇게 말한다.
    /// 관리 화면에서는 여기에 판매 상태가 온다 — 판매자와 운영자에게는 날짜보다
    /// "지금 팔리고 있는가"가 먼저다.
    let footnote: String
    /// 칸 위에 얹는 작은 상태 표시. 공개 상점에서는 `nil`이다.
    ///
    /// **글자 줄을 늘리지 않는다** — 늘리면 화면마다 카드 높이가 달라지고,
    /// 그러면 세 화면이 같은 카드를 쓴다는 사실이 눈에 보이지 않는다.
    var status: String?
}

/// 하트가 있는 카드만 넘긴다. 내장 템플릿은 `nil`이다.
struct StoreMirrorCardLike {
    let count: Int
    let isLiked: Bool
    /// 내가 올린 상품이면 숫자만 보이고 누를 수 없다(서버가 self-like를 거절한다).
    let isMine: Bool
    let isBusy: Bool
    let toggle: () -> Void
}

struct StoreMirrorCard<Preview: View>: View {
    let model: StoreMirrorCardModel
    var like: StoreMirrorCardLike?
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        VStack(alignment: .leading, spacing: StoreMirrorCardMetrics.rowSpacing) {
            // **칸 크기는 카드가 정한다.** 넘겨받은 그림의 원본 픽셀 크기가
            // 카드 높이를 정하면 상품마다 카드가 달라진다 — legacy `preview.png`는
            // 크기가 제각각이라 그대로 두면 목록이 들쭉날쭉해진다.
            preview()
                .frame(maxWidth: .infinity)
                // **칸 비율은 종류가 정한다.** 거울은 거울 모양, 스티커는 정사각 —
                // 여기에 거울 비율을 못 박아 두었던 것이 스티커 카드를 따로
                // 만들게 한 원인이었다.
                .aspectRatio(
                    ListingPreviewStyle.aspectRatio(for: model.contentType), contentMode: .fit
                )
                // **맞춘 뒤 다시 가운데로 놓는다.**
                //
                // `.aspectRatio(.fit)`는 맞춘 크기 그대로를 내놓는다. 목록에서는
                // 칸 너비를 꽉 채우니 차이가 없지만, 상세처럼 **높이가 제한되면**
                // 그림이 좁아지고 — 이 VStack이 `.leading`이라 그대로 왼쪽에 붙었다.
                // 비율도 content mode도 그대로 두고 놓이는 자리만 고친다.
                .frame(maxWidth: .infinity, alignment: .center)
                .clipped()
                .overlay(alignment: .topLeading) { statusBadge }
                .padding(.bottom, StoreMirrorCardMetrics.previewSpacing)

            Text(model.title)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                Text(model.subtitle ?? "")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                ShardAmount(amount: model.price)
            }

            metadata
                // 자리를 늘 차지한다 — 하트 유무로 카드 높이가 달라지지 않는다.
                .frame(height: StoreMirrorCardMetrics.metadataHeight)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// 판매 상태 표시. **없으면 아무 자리도 차지하지 않는다.**
    @ViewBuilder
    private var statusBadge: some View {
        if let status = model.status, !status.isEmpty {
            Text(status)
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    let shape = UnevenRoundedRectangle.ink(11, 9, 12, 10)
                    shape.fill(PaperTheme.paper)
                        .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.3))
                }
                .padding(7)
        }
    }

    /// 통계 한 줄. **세지 않는 값은 숫자로 말하지 않는다** —
    /// 자리를 비우는 것도 정직한 표현이다.
    private var metadata: some View {
        HStack(spacing: 8) {
            if let downloadCount = model.downloadCount {
                Label("\(downloadCount)", systemImage: "arrow.down")
            }
            if let like {
                heart(like)
            }
            Spacer(minLength: 2)
            Text(model.footnote)
        }
        .font(InkFont.caption)
        .foregroundStyle(PaperTheme.secondaryInk)
        .labelStyle(.titleAndIcon)
        .imageScale(.small)
        .lineLimit(1)
        // 작은 화면에서 줄이 깨지기보다 줄어들게 한다.
        .minimumScaleFactor(0.8)
    }

    /// **카드 밖에 따로 떠 있지 않는다.** 통계 줄 안에 다른 숫자와 나란히 있다.
    ///
    /// 눌린 상태는 **속이 찬 하트 + 진한 먹지**다. 예전 스티커 카드는 칩 전체를
    /// 뒤집었는데, 이유는 caption 크기에서 빈 하트와 찬 하트의 차이가 너무 미묘했기
    /// 때문이다. 카드를 하나로 합치면서 그 이유를 색으로 살렸다 —
    /// 상점 카드 생김새는 그대로 두고 눌린 것만 눈에 띄게 한다.
    @ViewBuilder
    private func heart(_ like: StoreMirrorCardLike) -> some View {
        let symbol = like.isLiked ? "heart.fill" : "heart"
        if like.isMine {
            // 서버가 거절할 버튼을 일부러 보여 주지 않는다.
            Label("\(like.count)", systemImage: symbol)
                .opacity(0.55)
                .accessibilityLabel("좋아요 \(like.count). 내 상품이라 누를 수 없어요")
        } else {
            Button(action: like.toggle) {
                Label("\(like.count)", systemImage: symbol)
                    .foregroundStyle(like.isLiked ? PaperTheme.ink : PaperTheme.secondaryInk)
                    // 글자는 작아도 손이 닿는 자리는 44pt다.
                    // **label 안에 있어야** Button이 이 영역을 갖는다.
                    // 높이는 줄이 이미 44pt로 잡아 두었으므로 그것을 꽉 채운다 —
                    // 여기서 다시 minHeight를 주면 그 카드만 줄이 부푼다.
                    .frame(
                        minWidth: InkTapTarget.minimum,
                        maxHeight: .infinity,
                        alignment: .leading
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(InkPressStyle())
            .disabled(like.isBusy)
            .accessibilityLabel(like.isLiked ? "좋아요 취소" : "좋아요")
            .accessibilityValue("\(like.count)")
        }
    }

    private var accessibilityLabel: String {
        var parts = [model.title]
        if let status = model.status, !status.isEmpty { parts.append(status) }
        if let subtitle = model.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        parts.append(model.price == 0 ? "무료" : "\(model.price) 조각")
        if let downloadCount = model.downloadCount { parts.append("다운로드 \(downloadCount)") }
        if let like {
            parts.append("좋아요 \(like.count)" + (like.isLiked ? ", 좋아요 누름" : ""))
        }
        parts.append(model.footnote)
        return parts.joined(separator: ", ")
    }
}
