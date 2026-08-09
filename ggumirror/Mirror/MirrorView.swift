//
//  MirrorView.swift
//  ggumirror
//
//  앱 실행 직후 첫 화면. 카메라 + 거울 장식만 보이고, 탭하면 홈으로/촬영이 나타난다.
//

import SwiftUI

struct MirrorView: View {
    /// 마지막 interaction 이후 컨트롤이 사라지기까지의 시간. Prototype 기준값.
    private static let autoHideDelay = Duration.milliseconds(4200)

    @State private var camera = MirrorCamera()
    @Environment(\.scenePhase) private var scenePhase

    @State private var areControlsVisible = false
    /// 값이 바뀔 때마다 auto-hide 타이머를 처음부터 다시 돌린다.
    @State private var lastInteraction = 0

    @State private var flashOpacity = 0.0
    @State private var saveAlert: SaveAlert?

    private struct SaveAlert: Identifiable {
        let id = UUID()
        let message: String
        let showsSettings: Bool
    }

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

            // 순서 = 레이어 순서. 카메라 → 장식 → 컨트롤 → flash.
            if isMirrorLive {
                DecorationOverlay()

                if areControlsVisible {
                    MirrorControls(onInteraction: registerInteraction, onCapture: capture)
                        .transition(.opacity)
                }

                Color.white
                    .opacity(flashOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .contentShape(.rect)
        .onTapGesture { toggleControls() }
        .task { await camera.start() }
        .task(id: lastInteraction) { await autoHideControls() }
        .alert(
            "저장",
            isPresented: Binding(get: { saveAlert != nil }, set: { if !$0 { saveAlert = nil } }),
            presenting: saveAlert
        ) { alert in
            if alert.showsSettings {
                Button("설정 열기") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
            Button("닫기", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await camera.start() }
            case .background: camera.stop()
            default: break
            }
        }
    }

    private func capture() {
        // 화면 캡처가 아니라 원본 프레임 + 장식을 직접 합성한다.
        guard let image = MirrorCapture.compose(
            frame: camera.currentFrame(),
            decoration: UIImage(named: DecorationOverlay.sampleAssetName),
            size: screenPixelSize
        ) else {
            saveAlert = SaveAlert(message: "지금은 저장할 화면을 만들 수 없어요.", showsSettings: false)
            return
        }

        flash()
        Task {
            switch await MirrorCapture.save(image) {
            case .saved:
                break
            case .denied:
                saveAlert = SaveAlert(
                    message: "사진에 저장하려면 사진 추가 권한이 필요해요.",
                    showsSettings: true
                )
            case .failed:
                saveAlert = SaveAlert(message: "사진을 저장하지 못했어요.", showsSettings: false)
            }
        }
    }

    private func flash() {
        flashOpacity = 0.9
        withAnimation(.easeOut(duration: 0.45)) { flashOpacity = 0 }
    }

    /// 화면과 같은 비율, 화면 해상도 그대로 합성하기 위한 픽셀 크기.
    private var screenPixelSize: CGSize {
        guard let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen else {
            return CGSize(width: 1080, height: 2340)
        }
        return CGSize(
            width: screen.bounds.width * screen.scale,
            height: screen.bounds.height * screen.scale
        )
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
