//
//  StickerRenderer.swift
//  ggumirror
//
//  스티커 프로젝트 → **1024 × 1024 완전 투명 PNG**.
//
//  새 렌더러를 만들지 않았다. `MirrorRenderer.draw`를 그대로 부르고
//  `canvas: .sticker`로 바탕(프레임 색 · 종이 결 · 거울 면)만 건너뛴다.
//  덕분에 Creator에서 보는 것과 최종 PNG가 다를 수 없다 —
//  위치 / 크기 / 회전 / 투명도 / 순서 / 글꼴 / tint가 모두 같은 코드에서 나온다.
//
//  **편집 화면의 것은 아무것도 들어가지 않는다**: 체크무늬 · 안내선 · 선택 표시 · 툴바.
//  그것들은 Creator 화면이 캔버스 **밖에서** 그리고, 여기서는 장식만 그린다.
//

import CoreGraphics
import SwiftUI
import UIKit

enum StickerRenderer {
    /// 최종 출력 크기는 `StickerCanvas.size`(1024 × 1024)다.

    /// 스티커 한 장을 투명 배경 이미지로 만든다.
    ///
    /// 비어 있으면 **전체가 alpha 0인 이미지**를 돌려준다(nil이 아니다) —
    /// "빈 스티커"도 유효한 결과이고, 저장 여부는 부르는 쪽이 정한다.
    @MainActor
    static func render(_ design: MirrorDesign, size: CGSize? = nil) -> CGImage? {
        let size = size ?? StickerCanvas.size
        let canvas = Canvas { context, canvasSize in
            MirrorRenderer.draw(
                style: design.style,
                strokes: design.strokes,
                stickers: design.stickers,
                texts: design.texts,
                importedArtworks: design.importedArtworks,
                transform: .fitted(in: canvasSize),
                // 카메라 영역을 칠하지 않는다. 스티커에는 그런 것이 없다.
                mirrorAreaFill: nil,
                canvas: .sticker,
                in: context,
                viewport: canvasSize
            )
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        // **핵심**: 불투명하게 만들면 배경이 검게 채워진다.
        renderer.isOpaque = false
        return renderer.cgImage
    }

    /// 저장용 PNG. 투명도를 유지해야 하므로 항상 PNG다 — JPEG는 쓰지 않는다.
    @MainActor
    static func pngData(_ design: MirrorDesign) -> Data? {
        guard let image = render(design) else { return nil }
        return UIImage(cgImage: image).pngData()
    }
}
