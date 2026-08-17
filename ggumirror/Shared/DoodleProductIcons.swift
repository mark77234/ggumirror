//
//  DoodleProductIcons.swift
//  ggumirror
//
//  제품을 가리키는 아이콘 **네 개**만 여기 있다 — 거울 · 거울조각 · 홈 · 상점.
//  나머지 아이콘(도구 / undo / chevron …)은 지금 쓰는 것을 그대로 둔다.
//
//  스티커와 **같은 펜**을 쓴다: 좌표는 `DoodleStroke`, 굵기·끝모양은 `DoodleInk`.
//  덕분에 아이콘과 스티커가 서로 다른 세트처럼 보이지 않는다.
//
//  좌표는 전부 고정값이다. 난수로 흔들지 않는다 — 다시 그려도 같은 모양이어야 하고,
//  hit target도 흔들리면 안 된다 (DESIGN.md).
//

import SwiftUI

/// 짧게 쓰기 위한 좌표 helper.
private func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// 제품 아이콘 네 개.
enum DoodleProductIcon: String, CaseIterable, Identifiable, Hashable {
    case mirror, shard, home, store

    var id: String { rawValue }

    /// 아이콘만 있는 버튼에서 쓰는 낭독기 이름.
    var accessibilityLabel: String {
        switch self {
        case .mirror: "거울"
        case .shard: "조각"
        case .home: "홈"
        case .store: "상점"
        }
    }

    var strokes: [DoodleStroke] {
        switch self {

        /// 손거울. 세로로 긴 프레임 + 유리에 비친 빛 두 줄.
        /// **비친 빛이 "거울"을 만든다** — 없으면 그냥 둥근 사각형이고,
        /// 프레임만 있으면 스마트폰으로 읽힌다.
        case .mirror: [
            .loop([p(0.30, 0.09), p(0.68, 0.07), p(0.79, 0.24), p(0.80, 0.62),
                   p(0.66, 0.78), p(0.32, 0.79), p(0.20, 0.61), p(0.21, 0.24)]),
            .line([p(0.36, 0.52), p(0.44, 0.36), p(0.57, 0.22)]),
            .line([p(0.37, 0.66), p(0.45, 0.56)]),
            // 손잡이. 프레임과 붙어 있어 손거울로 읽힌다.
            .poly([p(0.50, 0.79), p(0.50, 0.93)]),
            .poly([p(0.40, 0.93), p(0.61, 0.92)]),
        ]

        /// 깨진 거울 조각.
        ///
        /// ⚠️ **재화 아이콘이 아니다.** 조각(재화)을 뜻하는 자리에는 공식 asset을 쓰는
        /// `ShardIcon`(`InkComponents.swift`)을 쓴다. 이 획은 두들 세트의 일원으로만 남아 있다 —
        /// 여기로 되돌려 쓰지 마라.
        ///
        /// 실패 사례를 여러 번 지났다 — 톱니를 반복하면 **깃발**, 아래를 V로 파면 **커서**,
        /// 위를 두 번 파면 **왕관**, 네 점을 등거리로 두면 **다이아몬드**로 읽힌다.
        /// 파편은 모양이 아니라 **변 길이의 불균형**으로 만든다:
        /// 긴 위쪽 변 + 아래로 모이는 뾰족한 끝 + 한 번 꺾인 왼쪽 변. 대칭축이 없다.
        case .shard: [
            .shape([p(0.14, 0.27), p(0.86, 0.16), p(0.90, 0.38), p(0.50, 0.92), p(0.24, 0.59)]),
            .line([p(0.35, 0.45), p(0.54, 0.28)]),
        ]

        /// 집. 지붕이 반듯하지 않고 문이 조금 삐뚤다 — 시스템 house 심볼처럼 보이지 않게.
        case .home: [
            .poly([p(0.08, 0.47), p(0.51, 0.11), p(0.93, 0.49)]),
            .poly([p(0.19, 0.40), p(0.18, 0.88), p(0.83, 0.86), p(0.82, 0.42)]),
            .poly([p(0.41, 0.87), p(0.42, 0.60), p(0.60, 0.59), p(0.59, 0.86)]),
        ]

        /// 작은 상점. 차양(awning) + 간판 + 문.
        /// 카트가 아니라 **가게**다 — 꾸미러 상점은 크리에이터의 가게다.
        case .store: [
            // 차양. 아래쪽을 물결로 만들어 천처럼 보인다.
            .poly([p(0.06, 0.22), p(0.94, 0.19)]),
            .line([p(0.06, 0.22), p(0.10, 0.40), p(0.26, 0.44), p(0.30, 0.26),
                   p(0.36, 0.44), p(0.52, 0.45), p(0.56, 0.25), p(0.62, 0.44),
                   p(0.78, 0.43), p(0.82, 0.24), p(0.90, 0.41), p(0.94, 0.19)]),
            // 가게 몸통.
            .poly([p(0.13, 0.44), p(0.14, 0.90), p(0.87, 0.88), p(0.86, 0.43)]),
            // 문.
            .poly([p(0.55, 0.89), p(0.56, 0.62), p(0.78, 0.61), p(0.77, 0.88)]),
        ]
        }
    }
}

/// 제품 아이콘 하나. 스티커와 같은 펜을 통과한다.
struct DoodleProductIconView: View {
    let icon: DoodleProductIcon
    var size: CGFloat = 24
    var tint: Color = PaperTheme.ink

    var body: some View {
        Canvas { context, canvasSize in
            let box = min(canvasSize.width, canvasSize.height)
            let rect = CGRect(
                x: (canvasSize.width - box) / 2,
                y: (canvasSize.height - box) / 2,
                width: box, height: box
            )
            DoodleInk.draw(icon.strokes, in: rect, tint: tint, context: context)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 기존 이름으로 쓰는 자리

/// 거울 아이콘. 예전 이름 그대로 두어 쓰는 곳을 고치지 않는다.
struct MirrorIcon: View {
    var size: CGFloat
    var tint: Color = PaperTheme.ink

    var body: some View {
        DoodleProductIconView(icon: .mirror, size: size, tint: tint)
    }
}

// 조각(재화) 아이콘 `ShardIcon`은 두들이 아니라 공식 asset이라
// `InkComponents.swift`의 "조각 (currency)" 절에 있다.

#Preview("제품 아이콘") {
    VStack(spacing: 22) {
        ForEach([16, 20, 24, 28, 32, 62], id: \.self) { size in
            HStack(spacing: 22) {
                ForEach(DoodleProductIcon.allCases) { icon in
                    DoodleProductIconView(icon: icon, size: CGFloat(size))
                }
                Text("\(size)pt")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
            }
        }
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .paperBackground()
}
