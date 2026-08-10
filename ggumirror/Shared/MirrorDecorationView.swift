//
//  MirrorDecorationView.swift
//  ggumirror
//
//  실제 Mirror Camera 위에 얹는 거울 장식.
//  Editor / 미리보기와 같은 MirrorRenderer, 같은 Master Canvas 좌표를 쓴다.
//  중앙 Mirror Area는 칠하지 않아 카메라 영상이 그대로 비친다.
//

import SwiftUI

struct MirrorDecorationView: View {
    let design: MirrorDesign

    var body: some View {
        Canvas { context, size in
            MirrorRenderer.draw(
                style: design.style,
                strokes: design.strokes,
                stickers: design.stickers,
                // 카메라 preview의 resizeAspectFill과 같은 규칙.
                transform: .aspectFilled(in: size),
                // 중앙은 비워둔다 — 얼굴 위에 프레임 색 / 종이 / 그림이 올라가면 안 된다.
                mirrorAreaFill: nil,
                in: context,
                viewport: size
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension MirrorDesign {
    /// "+ 거울 만들기"의 시작점. 가장 단순한 프레임 하나뿐이다.
    /// 상점 템플릿을 몰래 복사해 오지 않는다.
    static var blank: MirrorDesign {
        MirrorDesign(
            mirror: MyMirror(
                id: "new-\(UUID().uuidString)",
                name: "새 거울",
                origin: .made,
                style: MirrorLibrary.defaultMirror.style
            )
        )
    }

    /// 라이브러리가 비어 있는 비정상 상태에서 쓰는 안전한 기본값.
    /// 정상 흐름에서는 노출되지 않는다.
    static var fallback: MirrorDesign {
        MirrorDesign(
            mirror: MyMirror(
                id: BasicMirror.white.id,
                name: BasicMirror.white.name,
                origin: .basic,
                style: BasicMirror.white.style
            )
        )
    }
}

#Preview {
    ZStack {
        Color.gray
        MirrorDecorationView(design: MirrorDesign(mirror: MirrorLibrary().mirrors[3]))
    }
    .ignoresSafeArea()
}
