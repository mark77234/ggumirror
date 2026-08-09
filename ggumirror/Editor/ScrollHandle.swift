//
//  ScrollHandle.swift
//  ggumirror
//
//  한 손가락으로 프레임을 위/아래 탐색하는 명시적 컨트롤.
//  두 손가락 Pan / Pinch는 그대로 두고, 발견하기 쉬운 대안을 하나 더 주는 것이다.
//

import SwiftUI

struct ScrollHandle: View {
    let side: EditorSide
    /// 현재 세로 위치 0(맨 위) ... 1(맨 아래). visibleRect에서 계산된 값이다.
    let progress: Double
    /// 화면 기준 세로 이동량.
    let onDrag: (CGFloat) -> Void

    @State private var lastTranslation: CGFloat = 0

    /// 편집 중인 프레임을 손가락이 가리지 않도록 항상 반대쪽에 둔다.
    private var alignment: Alignment {
        switch side {
        case .left: .trailing
        case .right: .leading
        case .top, .bottom: .trailing
        }
    }

    private let width: CGFloat = 44
    private let height: CGFloat = 132

    var body: some View {
        if side == .left || side == .right {
            handle
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .padding(.horizontal, 8)
        }
    }

    private var handle: some View {
        let shape = Capsule()
        return VStack(spacing: 0) {
            Image(systemName: "chevron.up")
                .font(.system(size: 11, weight: .bold))
                .padding(.top, 8)
            Spacer(minLength: 0)
            thumb
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .padding(.bottom, 8)
        }
        .foregroundStyle(PaperTheme.ink)
        .frame(width: width, height: height)
        .background {
            shape
                .fill(PaperTheme.subtleSurface.opacity(0.95))
                .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.6))
        }
        .contentShape(shape)
        // Handle 위에서는 절대 그림이 그려지지 않는다.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    onDrag(value.translation.height - lastTranslation)
                    lastTranslation = value.translation.height
                }
                .onEnded { _ in lastTranslation = 0 }
        )
        .accessibilityLabel("프레임 위아래로 이동")
        .accessibilityValue("\(Int(progress * 100))%")
        .accessibilityAdjustableAction { direction in
            onDrag(direction == .increment ? -40 : 40)
        }
    }

    /// 지금 위치를 알려주는 작은 표시. 두 손가락으로 움직여도 함께 이동한다.
    private var thumb: some View {
        GeometryReader { proxy in
            let travel = proxy.size.height - 26
            Capsule()
                .fill(PaperTheme.ink)
                .frame(width: 5, height: 26)
                .offset(y: travel * progress)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 5, height: 74)
        .padding(.vertical, 2)
    }
}

#Preview {
    ZStack {
        Color.gray
        ScrollHandle(side: .left, progress: 0.3, onDrag: { _ in })
    }
    .frame(height: 400)
}
