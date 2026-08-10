//
//  StickerSelectionOverlay.swift
//  ggumirror
//
//  선택된 스티커의 얇은 잉크 점선 + 크기 / 회전 handle.
//  이 UI는 Editor에서만 보이고 실제 Mirror / Preview / Capture에는 렌더하지 않는다.
//

import SwiftUI

struct StickerSelectionOverlay: View {
    let sticker: StickerObject
    let transform: MirrorViewTransform
    /// 화면 기준 크기 조절. 폭 변화량을 넘긴다.
    let onResize: (CGFloat, _ isEnded: Bool) -> Void
    /// 화면 기준 회전. 손가락 위치로 각도를 계산한다.
    let onRotate: (CGPoint, _ isEnded: Bool) -> Void

    private var rect: CGRect { transform.rect(sticker.frame) }
    private let handleSize: CGFloat = 30

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(
                    PaperTheme.ink.opacity(0.75),
                    style: StrokeStyle(lineWidth: 1.4, dash: [5, 4])
                )
                .frame(width: rect.width, height: rect.height)
                .rotationEffect(.degrees(sticker.rotation))
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)

            if !sticker.isLocked {
                handle(icon: "arrow.up.left.and.arrow.down.right")
                    .position(x: rect.maxX, y: rect.maxY)
                    .gesture(
                        DragGesture()
                            .onChanged { onResize($0.translation.width, false) }
                            .onEnded { onResize($0.translation.width, true) }
                    )
                    .accessibilityLabel("스티커 크기 조절")

                handle(icon: "arrow.trianglehead.clockwise")
                    .position(x: rect.maxX, y: rect.minY)
                    .gesture(
                        DragGesture()
                            .onChanged { onRotate($0.location, false) }
                            .onEnded { onRotate($0.location, true) }
                    )
                    .accessibilityLabel("스티커 회전")
            } else {
                Image(systemName: "lock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PaperTheme.ink)
                    .padding(5)
                    .background(Circle().fill(PaperTheme.subtleSurface))
                    .position(x: rect.maxX, y: rect.minY)
                    .allowsHitTesting(false)
            }
        }
    }

    private func handle(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PaperTheme.ink)
            .frame(width: handleSize, height: handleSize)
            .background {
                Circle()
                    .fill(PaperTheme.subtleSurface)
                    .overlay(Circle().stroke(PaperTheme.ink, lineWidth: 1.4))
            }
            .contentShape(.circle)
    }
}
