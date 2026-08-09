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

    struct Doodle: Hashable {
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
    /// 두꺼운 테두리를 쓸지. Detail의 큰 미리보기에서 사용한다.
    var lineWidth: CGFloat = 1.8

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let shape = UnevenRoundedRectangle.ink(19, 22, 23, 18)

            ZStack {
                // 프레임: 단색 + 은은한 종이 질감
                PaperBackground(color: style.frame)

                // 중앙 Mirror Area. 실제 카메라에서는 투명하게 유지되는 영역이다.
                UnevenRoundedRectangle.ink(10, 10, 10, 10)
                    .fill(Self.glass)
                    .padding(.top, size.height * style.insets.top)
                    .padding(.bottom, size.height * style.insets.bottom)
                    .padding(.leading, size.width * style.insets.left)
                    .padding(.trailing, size.width * style.insets.right)

                if !strokes.isEmpty {
                    Canvas { context, canvasSize in
                        for stroke in strokes.sorted(by: { $0.zIndex < $1.zIndex }) {
                            StrokeRenderer.draw(stroke, in: context, size: canvasSize)
                        }
                    }
                    .clipShape(FrameMaskShape(insets: style.insets), style: FrameMaskShape.fillStyle)
                    .allowsHitTesting(false)
                }

                ForEach(Array(style.doodles.enumerated()), id: \.offset) { _, doodle in
                    Image(systemName: doodle.symbol)
                        .font(.system(size: size.width * doodle.size, weight: .light))
                        .foregroundStyle(PaperTheme.ink.opacity(0.75))
                        .rotationEffect(.degrees(doodle.rotation))
                        .position(x: size.width * doodle.x, y: size.height * doodle.y)
                }
            }
            .clipShape(shape)
            .overlay(shape.stroke(PaperTheme.ink, lineWidth: lineWidth))
        }
        .aspectRatio(MirrorStyle.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// 거울 면. 그라디언트 없이 평평한 톤으로만 표현한다.
    static let glass = Color(red: 0.129, green: 0.125, blue: 0.145)
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
