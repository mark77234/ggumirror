//
//  MirrorControls.swift
//  ggumirror
//
//  Phase 1-2: 탭하면 나타나는 Mirror 컨트롤 레이어.
//  Decoration On/Off 외의 버튼은 아직 placeholder다.
//

import SwiftUI

struct MirrorControls: View {
    var isDecorationOn: Bool
    /// 컨트롤을 건드릴 때마다 호출 — auto-hide 타이머를 다시 시작한다.
    var onInteraction: () -> Void
    var onToggleDecoration: () -> Void

    /// Claude Design(Mirror App v2, 402 x 874 기준)의 배치를 0...1 normalized로 옮긴 값.
    /// 기기 크기가 달라져도 같은 비율로 놓인다.
    private enum Layout {
        static let sideInset = 52.0 / 402.0
        static let barBottom = 118.0 / 874.0
        static let backLeading = 60.0 / 402.0
        static let backTop = 96.0 / 874.0
        static let barHeight = 64.0
        static let scrimHeight = 58.0
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.06).opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Layout.scrimHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

                backButton
                    .padding(.leading, width * Layout.backLeading)
                    .padding(.top, height * Layout.backTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                bottomBar
                    .padding(.horizontal, width * Layout.sideInset)
                    .padding(.bottom, height * Layout.barBottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .ignoresSafeArea()
    }

    private var backButton: some View {
        Button {
            onInteraction()   // Home은 Phase 1-2 범위 밖 — 아직 이동하지 않는다.
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                Text("뒤로")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.leading, 9)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .background(Color(white: 0.11).opacity(0.5), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            controlButton("snowflake", label: "화면 고정")
            controlButton("sun.max", label: "밝기")
            captureButton
            controlButton("plus.magnifyingglass", label: "확대")
            controlButton(
                "sparkles",
                label: isDecorationOn ? "장식 끄기" : "장식 켜기",
                isActive: isDecorationOn,
                isOff: !isDecorationOn,
                action: onToggleDecoration
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.barHeight)
        .background(Color(white: 0.11).opacity(0.66), in: .rect(cornerRadius: 20))
    }

    private func controlButton(
        _ systemImage: String,
        label: String,
        isActive: Bool = false,
        isOff: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            onInteraction()
            action?()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isOff ? Color.white.opacity(0.45) : .white)
                .frame(width: 44, height: 44)
                .background(
                    Color.white.opacity(isActive && !isOff ? 0.22 : 0),
                    in: .rect(cornerRadius: 13)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1.6)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(label)
    }

    private var captureButton: some View {
        Button {
            onInteraction()   // 실제 캡처는 Phase 1-2 범위 밖.
        } label: {
            Circle()
                .fill(.white)
                .frame(width: 52, height: 52)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.18), lineWidth: 2)
                        .padding(5)
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("촬영")
    }
}

#Preview {
    ZStack {
        Color.gray
        MirrorControls(isDecorationOn: true, onInteraction: {}, onToggleDecoration: {})
    }
    .ignoresSafeArea()
}
