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
    /// 프레임 밴드 두께. 앱 기본값은 좌우 10% / 상하 7.7%.
    /// 상점 템플릿은 장식을 담기 위해 더 넓은 밴드를 쓸 수 있다.
    var sideBand: Double = 0.10
    var endBand: Double = 0.077
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
    /// 템플릿 규격과 같은 세로 비율 (1080 x 2340).
    static let aspectRatio: CGFloat = 1080.0 / 2340.0
}

struct MirrorPreview: View {
    let style: MirrorStyle
    /// 두꺼운 테두리를 쓸지. Detail의 큰 미리보기에서 사용한다.
    var lineWidth: CGFloat = 1.8

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let shape = UnevenRoundedRectangle.ink(19, 22, 23, 18)

            ZStack {
                // 프레임: 단색 + 은은한 종이 질감
                PaperBackground(color: style.frame)

                // 중앙 거울 영역. 실제 앱과 같은 밴드 비율(좌우 10%, 상하 7.7%).
                UnevenRoundedRectangle.ink(10, 10, 10, 10)
                    .fill(Self.glass)
                    .padding(.horizontal, size.width * style.sideBand)
                    .padding(.vertical, size.height * style.endBand)

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
    private static let glass = Color(red: 0.129, green: 0.125, blue: 0.145)
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
