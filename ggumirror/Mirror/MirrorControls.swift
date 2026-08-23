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

    /// 이 카메라가 실제로 낼 수 있는 배율만 온다. **하나뿐이면 고를 것이 없어 감춘다.**
    var zoomPresets: [CGFloat] = []
    /// 켜져 보일 배율. pinch로 사이 값에 있으면 `nil`이라 아무것도 켜지지 않는다.
    var selectedZoomPreset: CGFloat?
    /// 지금 실제 배율. 사이 값일 때만 숫자로 보여 준다.
    var logicalZoom: CGFloat = 1
    var onSelectZoom: (CGFloat) -> Void = { _ in }

    /// 화면에 담는 방법. **전면에서만 온다** — 비어 있으면 그리지 않는다.
    var framingOptions: [MirrorCamera.Framing] = []
    var framing: MirrorCamera.Framing = .fill
    var onSelectFraming: (MirrorCamera.Framing) -> Void = { _ in }

    /// Claude Design(Mirror App v2, 402 x 874 기준)의 배치를 0...1 normalized로 옮긴 값.
    /// 기기 크기가 달라져도 같은 비율로 놓인다.
    private enum Layout {
        static let shutterBottom = 118.0 / 874.0
        static let homeLeading = 60.0 / 402.0
        static let homeTop = 96.0 / 874.0
        static let scrimHeight = 58.0
        /// 배율은 촬영 버튼 **바로 위**다. 카메라 앱과 같은 자리라 배우지 않아도 알고,
        /// 한 손 엄지가 닿는다. 거울(화면 가운데)을 가리지 않는다.
        static let zoomAboveShutter = 74.0
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
                    // 촬영 버튼 위. 전환 칩과 겹치지 않게 가운데에만 둔다.
                    zoomSelector
                        .padding(.bottom, height * Layout.shutterBottom + Layout.zoomAboveShutter)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

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

    // MARK: - 배율

    /// 고를 것이 하나뿐이면 아무것도 그리지 않는다 — 누를 수 없는 버튼을 두지 않는다.
    @ViewBuilder
    private var zoomSelector: some View {
        // 배율이 하나뿐인 기기에서도 넓게/채우기는 고를 수 있어야 한다.
        if zoomPresets.count > 1 || framingOptions.count > 1 {
            VStack(spacing: 6) {
                // pinch로 preset 사이에 있으면 버튼이 하나도 켜지지 않는다.
                // 그때 지금 배율이 얼마인지는 알아야 하므로 값을 그대로 보여 준다.
                // **자리를 늘 차지한다** — 나타났다 사라지며 버튼 줄이 흔들리지 않게.
                Text(Self.zoomLabel(logicalZoom))
                    .font(InkFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(white: 0.11).opacity(0.5), in: .capsule)
                    .opacity(selectedZoomPreset == nil && zoomPresets.count > 1 ? 1 : 0)
                    .accessibilityHidden(selectedZoomPreset != nil)
                    .accessibilityLabel("현재 \(Self.zoomAccessibilityLabel(logicalZoom))")

                HStack(spacing: 10) {
                    // 배율과 **다른 묶음**이다. 섞어 두면 넓게 보기가 배율처럼 읽힌다.
                    framingSelector

                    if zoomPresets.count > 1 {
                        HStack(spacing: 4) {
                            ForEach(zoomPresets, id: \.self) { preset in
                                zoomChip(preset)
                            }
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 5)
                        .background(Color(white: 0.11).opacity(0.5), in: .capsule)
                    }
                }
            }
        }
    }

    /// 전면에서만. 배율이 아니라 **자를지 말지**를 고른다.
    @ViewBuilder
    private var framingSelector: some View {
        if framingOptions.count > 1 {
            HStack(spacing: 4) {
                ForEach(framingOptions, id: \.self) { option in
                    framingChip(option)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(Color(white: 0.11).opacity(0.5), in: .capsule)
        }
    }

    private func framingChip(_ option: MirrorCamera.Framing) -> some View {
        let isSelected = framing == option
        return Button {
            onInteraction()
            onSelectFraming(option)
        } label: {
            Text(option.title)
                .font(InkFont.caption)
                .foregroundStyle(isSelected ? Color(white: 0.11) : .white)
                .padding(.horizontal, 10)
                // 배율 칩과 같은 규칙 — 글자는 작아도 닿는 자리는 44pt다.
                .frame(minHeight: 44)
                .background(alignment: .center) {
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.92) : .clear)
                        .frame(height: 34)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.accessibilityTitle)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func zoomChip(_ preset: CGFloat) -> some View {
        let isSelected = selectedZoomPreset == preset
        return Button {
            onInteraction()
            onSelectZoom(preset)
        } label: {
            Text(Self.zoomLabel(preset))
                .font(InkFont.caption)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color(white: 0.11) : .white)
                .padding(.horizontal, 4)
                // 글자는 작아도 **손가락이 닿는 자리는 44pt**다.
                .frame(minWidth: 44, minHeight: 44)
                .background(alignment: .center) {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.92) : .clear)
                        .frame(width: 34, height: 34)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.zoomAccessibilityLabel(preset))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// `0.5x` · `1x` · `1.4x`. 정수는 소수점을 붙이지 않는다.
    static func zoomLabel(_ zoom: CGFloat) -> String {
        let rounded = (zoom * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded))x" }
        return String(format: "%.1fx", Double(rounded))
    }

    /// 낭독기는 `x`를 읽지 못한다. 기존 화면들과 같은 우리말 표기를 쓴다.
    static func zoomAccessibilityLabel(_ zoom: CGFloat) -> String {
        let rounded = (zoom * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded))배" }
        return String(format: "%.1f배", Double(rounded))
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
