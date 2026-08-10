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
}

struct MirrorPreview: View {
    let style: MirrorStyle
    /// 사용자가 그린 획. 중앙 Mirror Area에는 절대 그려지지 않는다.
    var strokes: [DrawingStroke] = []
    var stickers: [StickerObject] = []
    var texts: [TextObject] = []
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
    /// 거울 한 장을 통째로 넘긴다.
    /// 획이나 스티커를 빠뜨릴 수 없도록 개별 인자로 조립하지 않는다.
    init(mirror: MyMirror, lineWidth: CGFloat = 1.8) {
        self.init(
            style: mirror.style,
            strokes: mirror.strokes,
            stickers: mirror.stickers,
            texts: mirror.texts,
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
