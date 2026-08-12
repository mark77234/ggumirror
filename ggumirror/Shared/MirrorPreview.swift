//
//  MirrorPreview.swift
//  ggumirror
//
//  Gallery / Detail에서 쓰는 거울 미리보기.
//  기본 거울은 단색 프레임 + 종이 질감만, 상점 템플릿은 손그림 낙서가 얹힌다.
//

import SwiftUI

/// 거울 한 장의 생김새. 단색 프레임 + (선택적) 손그림 장식.
struct MirrorStyle: Hashable {
    var frame: Color
    /// 프레임 밴드 두께. 거울마다 다를 수 있어 고정값을 쓰지 않는다.
    var insets: MirrorFrameInsets = .standard
    /// 프레임 위에 얹히는 잉크 낙서. 기본 거울은 항상 비어 있다.
    var doodles: [Doodle] = []
    /// 프레임을 그리는가. `false`면 **투명 프레임** — 카메라만 보이고 장식은 그대로다.
    ///
    /// `frame`을 `Color.clear`로 바꾸지 않는다. 색을 지우면 사용자가 고른 색을 잃어버리고,
    /// 렌더러마다 "clear인지" 비교하는 magic value가 생긴다. 색은 그대로 두고
    /// **보이는지 여부만** 따로 담는다 — 다시 켜면 원래 색이 돌아온다.
    var isFrameVisible = true

    struct Doodle: Hashable, Codable {
        let symbol: String
        /// 미리보기 전체 기준 0...1 좌표.
        let x: Double
        let y: Double
        /// 미리보기 너비 대비 크기 비율.
        let size: Double
        var rotation: Double = 0
    }
}

extension MirrorStyle {
    /// 모든 미리보기가 쓰는 단일 비율. Master Canvas와 같은 값이다.
    static var aspectRatio: CGFloat { MirrorCanvas.aspectRatio }

    /// 프레임 밴드를 칠할 색. 투명 프레임이면 `nil`.
    ///
    /// **렌더러는 `frame`이 아니라 이 값만 본다.** 투명 판단이 한 곳에만 있어야
    /// 실제 Mirror · Capture · 미리보기가 어긋나지 않는다.
    var frameFill: Color? { isFrameVisible ? frame : nil }
}

struct MirrorPreview: View {
    let style: MirrorStyle
    /// 사용자가 그린 획. 중앙 Mirror Area에는 절대 그려지지 않는다.
    var strokes: [DrawingStroke] = []
    var stickers: [StickerObject] = []
    var texts: [TextObject] = []
    var importedArtworks: [ImportedArtworkObject] = []
    /// 두꺼운 테두리를 쓸지. Detail의 큰 미리보기에서 사용한다.
    var lineWidth: CGFloat = 1.8

    var body: some View {
        let shape = UnevenRoundedRectangle.ink(19, 22, 23, 18)
        Canvas { context, size in
            MirrorRenderer.draw(
                style: style,
                strokes: strokes,
                stickers: stickers,
                texts: texts,
                importedArtworks: importedArtworks,
                transform: .fitted(in: size),
                in: context,
                viewport: size
            )
        }
        .clipShape(shape)
        .overlay(shape.stroke(PaperTheme.ink, lineWidth: lineWidth))
        .aspectRatio(MirrorStyle.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

extension MirrorPreview {
    /// 상점 템플릿 한 장. 손그림 PNG가 있으면 그것까지 같이 그린다.
    /// 비율은 항상 9 : 19.5로 고정돼 있어 목록에서도 상세에서도 찌그러지지 않는다.
    init(template: MirrorTemplate, lineWidth: CGFloat = 1.8) {
        self.init(
            style: template.style,
            importedArtworks: StoreArtworkLibrary.artworks(for: template),
            lineWidth: lineWidth
        )
    }

    /// 거울 한 장을 통째로 넘긴다.
    /// 획이나 스티커를 빠뜨릴 수 없도록 개별 인자로 조립하지 않는다.
    init(mirror: MyMirror, lineWidth: CGFloat = 1.8) {
        self.init(
            style: mirror.style,
            strokes: mirror.strokes,
            stickers: mirror.stickers,
            texts: mirror.texts,
            importedArtworks: mirror.importedArtworks,
            lineWidth: lineWidth
        )
    }
}

#Preview {
    HStack(spacing: 12) {
        MirrorPreview(style: BasicMirror.softPink.style)
        MirrorPreview(style: StoreCatalog.samples[0].style)
    }
    .frame(height: 380)
    .padding(20)
    .paperBackground()
}
