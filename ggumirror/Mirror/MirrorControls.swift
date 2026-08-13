//
//  MirrorControls.swift
//  ggumirror
//
//  탭하면 나타나는 Mirror 컨트롤. 액션은 "홈으로"와 "촬영" 둘뿐이다.
//

import SwiftUI

struct MirrorControls: View {
    /// 컨트롤을 건드릴 때마다 호출 — auto-hide 타이머를 다시 시작한다.
    var onInteraction: () -> Void
    var onGoHome: () -> Void
    var onCapture: () -> Void
    /// 카메라가 살아 있을 때만 촬영 버튼을 보여준다. 홈으로는 항상 필요하다.
    var showsCapture: Bool = true
    /// 플래시 ON/OFF. 같은 Mirror session 동안만 유지된다.
    var isFlashOn: Bool = false
    var onToggleFlash: () -> Void = {}
    /// 전/후면 전환. 촬영 중이거나 카메라가 준비되지 않았으면 비활성이다.
    var canSwitchCamera: Bool = false
    var onSwitchCamera: () -> Void = {}

    /// Claude Design(Mirror App v2, 402 x 874 기준)의 배치를 0...1 normalized로 옮긴 값.
    /// 기기 크기가 달라져도 같은 비율로 놓인다.
    private enum Layout {
        static let shutterBottom = 118.0 / 874.0
        static let homeLeading = 60.0 / 402.0
        static let homeTop = 96.0 / 874.0
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

                homeButton
                    .padding(.leading, width * Layout.homeLeading)
                    .padding(.top, height * Layout.homeTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // 플래시는 홈으로와 같은 높이, 반대쪽. 새 UI 언어를 만들지 않는다.
                if showsCapture {
                    flashButton
                        .padding(.trailing, width * Layout.homeLeading)
                        .padding(.top, height * Layout.homeTop)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                // 촬영 버튼 자리는 그대로다. 전환은 그 오른쪽에 얹기만 한다 —
                // 카메라 앱과 같은 자리라 배우지 않아도 안다.
                if showsCapture {
                    captureButton
                        .padding(.bottom, height * Layout.shutterBottom)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                    switchButton
                        .padding(.trailing, width * Layout.homeLeading)
                        .padding(.bottom, height * Layout.shutterBottom + 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// 카메라 전환 / 플래시가 공유하는 잉크 칩. 홈으로 버튼과 같은 재질이다.
    private func chip(
        symbol: String,
        label: String,
        isActive: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            onInteraction()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isActive ? Color(white: 0.11) : .white)
                .frame(width: 40, height: 40)
                .background(
                    isActive ? Color.white.opacity(0.92) : Color(white: 0.11).opacity(0.5),
                    in: .circle
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    private var flashButton: some View {
        chip(
            // 켜져 있는지가 아이콘만 봐도 보여야 한다.
            symbol: isFlashOn ? "bolt.fill" : "bolt.slash.fill",
            label: isFlashOn ? "플래시 끄기" : "플래시 켜기",
            isActive: isFlashOn,
            action: onToggleFlash
        )
    }

    private var switchButton: some View {
        chip(
            symbol: Self.switchSymbol,
            label: "카메라 전환",
            isEnabled: canSwitchCamera,
            action: onSwitchCamera
        )
    }

    /// 현재 SDK에 실제로 있는 이름이다. 예전 `camera.rotate` /
    /// `arrow.triangle.2.circlepath.camera`가 아니라 iOS 18에서 정리된 trianglehead 계열이다.
    /// 테스트가 실제로 존재하는지 확인한다 — 없는 symbol은 빈 자리로 보인다.
    static let switchSymbol = "arrow.trianglehead.2.clockwise.rotate.90.camera"

    private var homeButton: some View {
        Button {
            onInteraction()
            onGoHome()
        } label: {
            HStack(spacing: 6) {
                // iOS 기본 back처럼 보이지 않게 chevron 대신 집 아이콘을 쓴다.
                // 탭바의 홈과 **같은 아이콘**이다 (DoodleProductIcons.swift).
                DoodleProductIconView(icon: .home, size: 16, tint: .white)
                Text("홈으로")
                    .font(InkFont.secondary)
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

    private var captureButton: some View {
        Button {
            onInteraction()
            onCapture()
        } label: {
            Circle()
                .fill(.white)
                .frame(width: 64, height: 64)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.18), lineWidth: 2)
                        .padding(6)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("촬영")
    }
}

#Preview {
    ZStack {
        Color.gray
        MirrorControls(onInteraction: {}, onGoHome: {}, onCapture: {})
    }
    .ignoresSafeArea()
}
