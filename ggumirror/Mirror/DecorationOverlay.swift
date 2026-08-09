//
//  DecorationOverlay.swift
//  ggumirror
//
//  Phase 1-2: 카메라 위에 얹는 거울 장식 레이어.
//

import SwiftUI

struct DecorationOverlay: View {
    /// Phase 1-2에서는 로컬 샘플 1개만 사용한다.
    /// MIRROR_CREATOR_TEMPLATE_GUIDE 규격(1080 x 2340, 중앙 투명)으로 만든 마스터 이미지.
    static let sampleAssetName = "MirrorSampleFrame"

    var assetName: String = sampleAssetName

    var body: some View {
        // 원본 비율을 유지한 채 화면을 채우고 넘치는 부분만 잘라낸다(Uniform Scale + Crop).
        // 가로/세로를 따로 늘리지 않으므로 원·리본 같은 장식이 찌그러지지 않는다.
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)   // 장식은 절대 터치를 가로채지 않는다
            .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Color.gray
        DecorationOverlay()
    }
    .ignoresSafeArea()
}
