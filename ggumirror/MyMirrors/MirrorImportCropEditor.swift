//
//  MirrorImportCropEditor.swift
//  ggumirror
//
//  규격 비율로 **잘라낼 자리**를 사용자가 고른다.
//
//  비율은 고정이다. 자유 비율을 주면 결국 늘려야 하고, 늘리면 그건 사용자가
//  고른 그림이 아니다. 어디를 버릴지만 사용자가 정한다.
//
//  빈 자리가 생기지 않게 최소 배율을 계산한다 — 창보다 작게 줄이면 거울에
//  구멍이 뚫린 채로 저장된다.
//

import SwiftUI

struct MirrorImportCropEditor: View {
    let image: CGImage
    var isBusy: Bool = false
    /// 지난번에 확정한 창. 최종 미리보기에서 `뒤로`로 돌아왔을 때 **그 자리에서**
    /// 다시 시작한다 — 자리를 처음부터 다시 잡게 하지 않는다.
    var initialWindow: CGRect?
    /// 마지막 확인을 보고 돌아온 길인가. 문구가 달라진다 —
    /// 비율이 맞는 그림을 두고 "비율이 맞지 않아요"라고 말하지 않는다.
    var isRevisiting = false
    let onConfirm: (CGRect) -> Void
    let onCancel: () -> Void

    /// 지금 배율. 1이면 그림이 창을 꼭 채운다(= 최소 배율).
    @State private var scale: CGFloat = 1
    /// 손을 뗀 뒤 확정된 배율.
    @State private var committedScale: CGFloat = 1
    /// 창 기준 이동량(pt).
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private var imageSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(isRevisiting ? "자를 자리를 다시 정해 주세요." : "이 이미지는 거울 비율과 맞지 않아요.")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)
                .multilineTextAlignment(.center)
            Text("손가락으로 옮기고 크기를 바꿀 수 있어요.")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geometry in
                let window = windowSize(in: geometry.size)
                ZStack {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: window.width, height: window.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .clipped()
                        .frame(width: window.width, height: window.height)
                        .overlay {
                            Rectangle().strokeBorder(PaperTheme.ink, lineWidth: 2)
                        }
                        .contentShape(.rect)
                        .gesture(drag(window: window))
                        .simultaneousGesture(zoom(window: window))
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .aspectRatio(MirrorImportCrop.aspectRatio, contentMode: .fit)
            .frame(maxHeight: 340)

            if isBusy {
                ProgressView().tint(PaperTheme.ink)
            } else {
                HStack(spacing: 10) {
                    action("처음으로") { reset() }
                    action("취소") { onCancel() }
                }
                Button {
                    onConfirm(window(in: currentWindowSize))
                } label: {
                    Text("이미지 자르기")
                        .font(InkFont.body.weight(.semibold))
                        .foregroundStyle(PaperTheme.subtleSurface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .frame(minHeight: InkTapTarget.minimum)
                        .background {
                            UnevenRoundedRectangle.ink(18, 22, 23, 17).fill(PaperTheme.ink)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())
            }
        }
        .onAppear { reset() }
        // 창 크기는 layout 뒤에야 알 수 있다. 지난 자리를 되살리려면 그 값이 필요하다.
        .onChange(of: currentWindowSize) { _, size in
            guard !didRestore, size.width > 0, let initialWindow else { return }
            didRestore = true
            restore(initialWindow, window: size)
        }
    }

    // MARK: - 제스처

    private func drag(window: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clampedOffset(
                    CGSize(
                        width: committedOffset.width + value.translation.width,
                        height: committedOffset.height + value.translation.height
                    ),
                    window: window
                )
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func zoom(window: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // **1 아래로 내려가지 않는다** — 그 아래는 곧 빈 자리다.
                scale = max(1, committedScale * value.magnification)
                offset = clampedOffset(offset, window: window)
            }
            .onEnded { _ in
                committedScale = scale
                committedOffset = offset
            }
    }

    /// 그림이 창 밖으로 밀려나 빈 자리가 생기지 않게 이동량을 가둔다.
    private func clampedOffset(_ proposed: CGSize, window: CGSize) -> CGSize {
        // 배율이 1이면 그림이 창과 같은 크기라 움직일 여유가 없다.
        let slackX = max(0, (window.width * scale - window.width) / 2)
        let slackY = max(0, (window.height * scale - window.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -slackX), slackX),
            height: min(max(proposed.height, -slackY), slackY)
        )
    }

    private func reset() {
        scale = 1
        committedScale = 1
        offset = .zero
        committedOffset = .zero
    }

    /// 지난번 창을 화면의 배율/이동량으로 되돌린다. `window(in:)`의 역이다 —
    /// **좌표 규칙을 두 벌 만들지 않는다.**
    private func restore(_ rect: CGRect, window: CGSize) {
        let base = MirrorImportCrop.minimumScale(imageSize: imageSize, windowSize: window)
        let effective = window.width / max(rect.width, 1)
        guard base > 0, rect.width > 0, rect.height > 0 else { return }
        scale = max(1, effective / base)
        committedScale = scale
        offset = clampedOffset(
            CGSize(
                width: (imageSize.width / 2 - rect.midX) * effective,
                height: (imageSize.height / 2 - rect.midY) * effective
            ),
            window: window
        )
        committedOffset = offset
    }

    // MARK: - 창 계산

    @State private var currentWindowSize: CGSize = .zero
    /// 지난 자리를 되살리는 것은 **한 번뿐이다.** 매 layout마다 하면 사용자가
    /// 그 뒤에 움직인 것을 되돌려 버린다.
    @State private var didRestore = false

    private func windowSize(in available: CGSize) -> CGSize {
        let ratio = MirrorImportCrop.aspectRatio
        var width = available.width
        var height = width / ratio
        if height > available.height {
            height = available.height
            width = height * ratio
        }
        let size = CGSize(width: width, height: height)
        // 화면이 바뀌어도 확정 계산이 같은 값을 쓰게 기억해 둔다.
        Task { @MainActor in currentWindowSize = size }
        return size
    }

    /// 화면에서의 이동/배율을 **그림 픽셀 좌표의 창**으로 옮긴다.
    ///
    /// 화면 크기가 달라져도 결과가 같아야 하므로 비율로만 계산한다.
    private func window(in windowSize: CGSize) -> CGRect {
        // 그림이 창을 꽉 채우도록(aspect fill) 놓였을 때의 배율.
        let base = MirrorImportCrop.minimumScale(imageSize: imageSize, windowSize: windowSize)
        let effective = base * scale
        guard effective > 0, windowSize.width > 0 else {
            return MirrorImportCrop.centeredWindow(imageSize: imageSize)
        }

        // 창이 그림 위에서 차지하는 크기(그림 픽셀 기준).
        let cropWidth = windowSize.width / effective
        let cropHeight = windowSize.height / effective

        // 화면 이동량을 그림 픽셀로 되돌린다. 손가락을 오른쪽으로 끌면
        // 그림이 오른쪽으로 가므로 창은 왼쪽으로 간다 — 부호가 반대다.
        let centerX = imageSize.width / 2 - offset.width / effective
        let centerY = imageSize.height / 2 - offset.height / effective

        return MirrorImportCrop.clamped(
            window: CGRect(
                x: centerX - cropWidth / 2,
                y: centerY - cropHeight / 2,
                width: cropWidth, height: cropHeight
            ),
            imageSize: imageSize
        )
    }

    private func action(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .frame(minHeight: InkTapTarget.minimum)
                .background {
                    UnevenRoundedRectangle.ink(18, 22, 23, 17)
                        .stroke(PaperTheme.ink, lineWidth: 1.6)
                }
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
    }
}
