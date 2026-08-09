//
//  MirrorView.swift
//  ggumirror
//
//  Phase 1-1: app launches straight into the mirror camera.
//

import SwiftUI

struct MirrorView: View {
    /// 마지막 interaction 이후 컨트롤이 사라지기까지의 시간. Prototype 기준값.
    private static let autoHideDelay = Duration.milliseconds(4200)

    @State private var camera = MirrorCamera()
    @State private var screenBrightness = ScreenBrightness()
    @Environment(\.scenePhase) private var scenePhase

    @State private var isDecorationOn = true
    @State private var areControlsVisible = false
    /// 값이 바뀔 때마다 auto-hide 타이머를 처음부터 다시 돌린다.
    @State private var lastInteraction = 0

    private var isMirrorLive: Bool {
        if case .ready = camera.status { true } else { false }
    }

    var body: some View {
        ZStack {
            Color.black

            switch camera.status {
            case .ready:
                CameraPreviewView(session: camera.session)
                    .accessibilityLabel("거울")
            case .denied:
                message("카메라 권한이 필요해요", detail: "설정에서 카메라를 켜면 거울을 볼 수 있어요.", showsSettings: true)
            case .unavailable:
                message("카메라를 사용할 수 없어요", detail: "이 기기에서는 전면 카메라를 찾을 수 없어요.", showsSettings: false)
            case .idle:
                EmptyView()
            }

            // 순서 = 레이어 순서. 카메라 → 장식 → 컨트롤.
            if isMirrorLive {
                if isDecorationOn {
                    DecorationOverlay()
                }
                if areControlsVisible {
                    MirrorControls(
                        isDecorationOn: isDecorationOn,
                        zoom: camera.zoomFactor,
                        maxZoom: camera.maxZoomFactor,
                        brightness: screenBrightness.level,
                        onInteraction: registerInteraction,
                        onToggleDecoration: { isDecorationOn.toggle() },
                        onZoomChange: camera.setZoom,
                        onBrightnessChange: screenBrightness.set
                    )
                    .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .contentShape(.rect)
        .onTapGesture { toggleControls() }
        .task { await camera.start() }
        .task(id: lastInteraction) { await autoHideControls() }
        .onAppear { screenBrightness.takeOver() }
        .onDisappear { screenBrightness.release() }   // Mirror를 완전히 벗어나면 원래 밝기로
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await camera.start() }
                screenBrightness.takeOver()
            case .background:
                camera.stop()
                screenBrightness.restoreUserLevel()   // 앱 밖에 밝기가 남지 않게
            default:
                break
            }
        }
    }

    private func toggleControls() {
        guard isMirrorLive else { return }
        withAnimation(.easeOut(duration: 0.18)) { areControlsVisible.toggle() }
        registerInteraction()
    }

    /// 컨트롤을 건드린 시점부터 다시 4.2초를 센다.
    private func registerInteraction() {
        lastInteraction &+= 1
    }

    /// lastInteraction이 바뀌면 이 task가 취소되고 새로 시작하므로,
    /// 컨트롤을 조작하는 동안에는 숨김이 발동하지 않는다.
    private func autoHideControls() async {
        guard areControlsVisible else { return }
        try? await Task.sleep(for: Self.autoHideDelay)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.22)) { areControlsVisible = false }
    }

    private func message(_ title: String, detail: String, showsSettings: Bool) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if showsSettings {
                Button("설정 열기") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}

#Preview {
    MirrorView()
}
