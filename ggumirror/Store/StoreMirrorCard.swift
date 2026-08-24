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

import SwiftUI

/// 카드가 보여 주는 값. 두 출처가 같은 모양으로 바뀌어 들어온다.
struct StoreMirrorCardModel {
    let title: String
    /// 만든이 / 판매자. **없으면 비워 둔다** — 가짜 이름을 지어내지 않는다.
    /// 사용자 상품에는 공개 판매자 이름이 없다(공개 DTO에 담지 않는 값이다).
    var subtitle: String?
    let price: Int
    /// 서버가 센 값. **`nil`이면 아직 모르는 것이고 `0`이 아니다.**
    var downloadCount: Int?
    /// 업로드 날짜 라벨. 올라온 적 없으면 그렇게 말한다.
    let footnote: String
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
        VStack(alignment: .leading, spacing: 3) {
            preview()
                .padding(.bottom, 6)

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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
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
    @ViewBuilder
    private func heart(_ like: StoreMirrorCardLike) -> some View {
        let symbol = like.isLiked ? "heart.fill" : "heart"
        if like.isMine {
            // 서버가 거절할 버튼을 일부러 보여 주지 않는다.
            Label("\(like.count)", systemImage: symbol)
                .opacity(0.55)
        } else {
            Button(action: like.toggle) {
                Label("\(like.count)", systemImage: symbol)
                    // 글자는 작아도 손이 닿는 자리는 44pt다.
                    // **label 안에 있어야** Button이 이 영역을 갖는다.
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
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
