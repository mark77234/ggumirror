//
//  ListingPreviewStyle.swift
//  ggumirror
//
//  상품 미리보기를 **콘텐츠 종류에 맞게** 놓는 규칙. 한 곳에만 있다.
//
//  실기기에서 스티커를 등록하자 상점과 `내 판매`가 무너졌다. 원인은 카드가
//  **거울 비율(1080 × 2340 ≈ 0.46)로 고정**돼 있었던 것이다. 세로로 길쭉한 칸에
//  거의 정사각인 스티커를 `.fill`로 넣으니 좌우가 잘려 나가고, 원본이 작은 투명
//  PNG면 늘어나 뭉개졌다. 거울 전용 가정이 스티커에 그대로 적용된 것이다.
//
//  **원본 픽셀 크기에 기대지 않는다.** 칸 크기는 종류가 정하고 그림은 그 안에 들어간다.
//

import SwiftUI

enum ListingPreviewStyle {
    /// 칸의 가로/세로 비율. 거울은 실제 거울 모양, 스티커는 정사각이다.
    static func aspectRatio(for contentType: String) -> CGFloat {
        isSticker(contentType) ? 1 : MirrorStyle.aspectRatio
    }

    /// 그림을 칸에 놓는 방법.
    ///
    /// 거울은 화면을 꽉 채우는 것이 곧 그 거울의 모습이라 `.fill`이다.
    /// **스티커는 `.fit`이다** — 잘라내면 스티커가 아니게 된다.
    static func contentMode(for contentType: String) -> ContentMode {
        isSticker(contentType) ? .fit : .fill
    }

    /// 투명 배경을 보여 줄지. 스티커는 투명한 것이 정상이라 바탕을 깔아야 보인다.
    static func showsTransparency(for contentType: String) -> Bool {
        isSticker(contentType)
    }

    static func isSticker(_ contentType: String) -> Bool { contentType == "sticker" }
}
