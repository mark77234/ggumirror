//
//  ScrollHandle.swift
//  ggumirror
//
//  프레임을 위/아래로 빠르게 훑는 컨트롤.
//  track 위치가 곧 viewport 위치다(absolute scrub) — 여러 번 swipe 할 필요가 없다.
//  두 손가락 Pan / Pinch는 그대로 유지된다.
//

import SwiftUI

struct ScrollHandle: View {
    let side: EditorSide
    /// 현재 세로 위치 0(맨 위) ... 1(맨 아래). visibleRect에서 계산된 값이다.
    let progress: Double
    /// 전체 대비 보이는 세로 비율. thumb 크기에 반영한다.
    let visibleFraction: Double
    /// track 위치를 그대로 viewport 위치로 바꾼다.
    let onScrub: (Double) -> Void

    /// 편집 중인 프레임을 손가락이 가리지 않도록 항상 반대쪽에 둔다.
    private var alignment: Alignment {
        side == .right ? .leading : .trailing
    }

    private let width: CGFloat = 44
    private let trackHeight: CGFloat = 240
    private let minimumThumbHeight: CGFloat = 34

    var body: some View {
        if side == .left || side == .right {
            handle
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .padding(.horizontal, 8)
        }
    }

    private var handle: some View {
        VStack(spacing: 4) {
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .bold))
            track
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(PaperTheme.ink)
        .padding(.vertical, 8)
        .frame(width: width)
        .background {
            Capsule()
                .fill(PaperTheme.subtleSurface.opacity(0.95))
                .overlay(Capsule().stroke(PaperTheme.ink, lineWidth: 1.6))
        }
        .accessibilityElement()
        .accessibilityLabel("프레임 위아래로 이동")
        .accessibilityValue("\(Int(progress * 100))%")
        .accessibilityAdjustableAction { direction in
            onScrub(min(max(progress + (direction == .increment ? 0.1 : -0.1), 0), 1))
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let thumbHeight = max(minimumThumbHeight, height * visibleFraction)
            let travel = max(height - thumbHeight, 1)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(PaperTheme.ink.opacity(0.12))
                    .frame(width: 4)
                    .frame(maxWidth: .infinity)

                Capsule()
                    .fill(PaperTheme.ink)
                    .frame(width: 8, height: thumbHeight)
                    .frame(maxWidth: .infinity)
                    .offset(y: travel * progress)
            }
            .frame(width: proxy.size.width, height: height)
            .contentShape(.rect)
            // 누른 지점이 곧 위치. 한 번의 drag로 위 끝에서 아래 끝까지 간다.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let y = value.location.y - thumbHeight / 2
                        onScrub(Double(min(max(y / travel, 0), 1)))
                    }
            )
        }
        .frame(height: trackHeight)
    }
}

#Preview {
    ZStack {
        Color.gray
        ScrollHandle(side: .left, progress: 0.3, visibleFraction: 0.25, onScrub: { _ in })
    }
    .frame(height: 460)
}

/// Side Detail에 처음 들어왔을 때 한 번만 보여주는 조작 힌트.
struct GestureHint: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("두 손가락으로 확대·축소할 수 있어요")
            Text("↕ 스크롤바로 위치를 빠르게 이동해보세요")
                .foregroundStyle(PaperTheme.secondaryInk)
        }
        .font(InkFont.caption)
        .foregroundStyle(PaperTheme.ink)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            UnevenRoundedRectangle.ink(15, 12, 16, 13)
                .fill(PaperTheme.subtleSurface)
                .overlay(
                    UnevenRoundedRectangle.ink(15, 12, 16, 13)
                        .stroke(PaperTheme.ink, lineWidth: 1.5)
                )
        }
        // Undo/Redo(우상단)와 겹치지 않도록 캔버스 아래쪽에 둔다.
        .padding(.horizontal, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 12)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("두 손가락으로 확대·축소하고, 스크롤바로 위치를 이동할 수 있어요")
    }
}
