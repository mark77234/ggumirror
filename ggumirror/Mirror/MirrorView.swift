//
//  MirrorView.swift
//  ggumirror
//
//  앱 실행 직후 첫 화면. 카메라 + 거울 장식만 보이고, 탭하면 홈으로/촬영이 나타난다.
//

import SwiftUI

struct MirrorView: View {
    /// 현재 적용 중인 거울의 단일 source of truth.
    var library: MirrorLibrary
    var onGoHome: () -> Void

    /// 마지막 interaction 이후 컨트롤이 사라지기까지의 시간. Prototype 기준값.
    private static let autoHideDelay = Duration.milliseconds(4200)

    /// 본앱 거울은 전/후면 전환과 실제 사진 촬영을 한다. 잠금화면 extension은 하지 않는다.
    @State private var camera = MirrorCamera(role: .mirror)
    @Environment(\.scenePhase) private var scenePhase

    @State private var areControlsVisible = false
    /// 값이 바뀔 때마다 auto-hide 타이머를 처음부터 다시 돌린다.
    @State private var lastInteraction = 0

    @State private var flashOpacity = 0.0
    @State private var saveAlert: SaveAlert?

    /// 사용자의 플래시 의도. **앱을 다시 켜면 꺼진 상태로 시작한다** — 저장하지 않는다.
    /// 카메라를 전환해도 이 값은 유지된다(실제 구현 방식만 기기 능력에 따라 달라진다).
    @State private var isFlashOn = false
    /// 촬영이 진행 중인가. 중복 촬영과 촬영 중 전환을 막는다.
    @State private var isCapturing = false

    /// 전면 하드웨어 flash가 없는 기기의 대체 수단 — 촬영 순간에만 화면을 밝힌다.
    @State private var screenFlashOpacity = 0.0
    /// 화면 flash 동안 잠시 올린 밝기를 되돌리기 위한 원래 값.
    @State private var brightnessBeforeFlash: CGFloat?

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
                CameraPreviewView(camera: camera)
                    .accessibilityLabel("거울")
            case .denied:
                message("카메라 권한이 필요해요", detail: "설정에서 카메라를 켜면 거울을 볼 수 있어요.", showsSettings: true)
            case .unavailable:
                message("카메라를 사용할 수 없어요", detail: "지금은 카메라를 쓸 수 없어요. 잠시 뒤 다시 시도해 주세요.", showsSettings: false)
            case .idle:
                EmptyView()
            }

            // 순서 = 레이어 순서. 카메라 → 장식 → 컨트롤 → flash.
            if isMirrorLive {
                MirrorDecorationView(design: currentDesign)
            }

            // 카메라를 못 쓰는 상태에서도 Home으로는 나갈 수 있어야 한다.
            // 전환 / 플래시도 같은 auto-hide 시스템 안에 있다.
            if areControlsVisible {
                MirrorControls(
                    onInteraction: registerInteraction,
                    onGoHome: onGoHome,
                    onCapture: capture,
                    showsCapture: isMirrorLive,
                    isFlashOn: isFlashOn,
                    onToggleFlash: { isFlashOn.toggle() },
                    canSwitchCamera: camera.canSwitchCamera && !isCapturing,
                    onSwitchCamera: switchCamera,
                    // 배율도 같은 control set이다 — 함께 나타나고 함께 숨는다.
                    zoomPresets: camera.zoomPresets,
                    selectedZoomPreset: camera.selectedZoomPreset,
                    logicalZoom: camera.logicalZoom,
                    onSelectZoom: { camera.selectZoom(logical: $0) }
                )
                .transition(.opacity)
            }

            // 화면 플래시. 촬영 순간에만 얼굴을 밝힌다 — **저장되는 사진에는 들어가지 않는다**
            // (사진은 화면 스냅샷이 아니라 카메라 사진 + 장식을 따로 합성한다).
            Color.white
                .opacity(screenFlashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .contentShape(.rect)
        .onTapGesture { toggleControls() }
        // 손가락 두 개라 한 손가락 탭(컨트롤 열기/닫기)과 섞이지 않는다.
        // 배율을 바꾸는 동안에는 컨트롤이 보여야 하므로 auto-hide 타이머도 같이 민다.
        .gesture(
            MagnifyGesture(minimumScaleDelta: 0)
                .onChanged { value in
                    if !areControlsVisible {
                        withAnimation(.easeOut(duration: 0.18)) { areControlsVisible = true }
                    }
                    camera.updatePinch(magnification: value.magnification)
                    registerInteraction()
                }
                .onEnded { _ in
                    camera.endPinch()
                    registerInteraction()
                }
        )
        .task { await camera.start() }
        .task(id: lastInteraction) { await autoHideControls() }
        // 거울 화면에도 같은 종이 Dialog를 쓴다. 카메라 영상 위에 잠깐 떠 있다 사라지는 카드다.
        .inkDialog(
            "저장",
            message: saveAlert?.message,
            isPresented: Binding(get: { saveAlert != nil }, set: { if !$0 { saveAlert = nil } })
        ) {
            // 닫히면서 saveAlert가 비워지므로 버튼을 만들 때 값을 잡아 둔다.
            let showsSettings = saveAlert?.showsSettings == true
            var actions = [InkDialogAction("닫기", role: showsSettings ? .secondary : .primary)]
            if showsSettings {
                actions.append(InkDialogAction("설정 열기", role: .primary) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                })
            }
            return actions
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await camera.start() }
            case .background:
                camera.stop()
                // 밝기를 올린 채로 앱을 떠나지 않는다.
                endScreenFlash()
            default: break
            }
        }
        .onDisappear { endScreenFlash() }
    }

    /// 매번 라이브러리에서 읽으므로 Editor 저장 / 적용이 즉시 반영된다.
    private var currentDesign: MirrorDesign {
        library.mirrors.isEmpty ? .fallback : MirrorDesign(mirror: library.currentMirror)
    }

    private func capture() {
        // 한 번에 하나만. 연타로 같은 순간을 여러 장 저장하지 않는다.
        guard !isCapturing else { return }
        isCapturing = true

        // **요청이 시작될 때 의도를 고정한다.** 촬영 도중 사용자가 플래시를 눌러도
        // 이 사진의 설정이 중간에 바뀌지 않는다.
        let wantsFlash = isFlashOn
        // 공식 flash(후면 LED · 전면 Retina Flash)가 없으면 화면 flash로 대신한다.
        let usesScreenFlash = MirrorCamera.needsScreenFlash(
            wantsFlash: wantsFlash,
            officialSupported: camera.isOfficialFlashSupported
        )

        Task {
            defer {
                endScreenFlash()
                isCapturing = false
            }

            if usesScreenFlash {
                await beginScreenFlash()
            }

            // 화면 캡처가 아니라 카메라 사진 + 현재 거울 디자인을 직접 합성한다.
            let photo = await camera.capturePhoto(flash: wantsFlash && !usesScreenFlash)
            guard let image = MirrorCapture.compose(
                frame: photo,
                design: currentDesign,
                size: screenPixelSize
            ) else {
                saveAlert = SaveAlert(message: "지금은 저장할 화면을 만들 수 없어요.", showsSettings: false)
                return
            }

            flash()
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

    private func switchCamera() {
        // 촬영 중에는 카메라를 바꾸지 않는다. 연타는 카메라 쪽 guard가 막는다.
        guard !isCapturing else { return }
        Task { await camera.switchCamera() }
    }

    // MARK: - 화면 플래시

    /// 흰 화면을 띄우고 **그 빛이 실제로 카메라에 들어올 시간까지** 기다린다.
    /// overlay만 깜빡이고 이전 프레임을 저장하면 플래시를 쓴 척하는 가짜가 된다.
    private func beginScreenFlash() async {
        brightnessBeforeFlash = activeScreen?.brightness
        activeScreen?.brightness = 1
        screenFlashOpacity = 1
        CameraLog.event("flash on screen")

        // 노출이 새 밝기에 맞춰질 만큼만. sleep을 늘려 감으로 맞추지 않는다.
        try? await Task.sleep(for: .milliseconds(220))
    }

    /// 성공 · 실패 · 취소 · 백그라운드 · 화면 이탈 — **어느 경로에서도** 되돌린다.
    private func endScreenFlash() {
        screenFlashOpacity = 0
        if let brightness = brightnessBeforeFlash {
            activeScreen?.brightness = brightness
            brightnessBeforeFlash = nil
        }
    }

    private func flash() {
        flashOpacity = 0.9
        withAnimation(.easeOut(duration: 0.45)) { flashOpacity = 0 }
    }

    /// 지금 앱이 올라가 있는 화면. `UIScreen.main`은 iOS 26에서 deprecated다.
    private var activeScreen: UIScreen? {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
    }

    /// 화면과 같은 비율, 화면 해상도 그대로 합성하기 위한 픽셀 크기.
    private var screenPixelSize: CGSize {
        guard let screen = activeScreen else {
            return CGSize(width: 1080, height: 2340)
        }
        return CGSize(
            width: screen.bounds.width * screen.scale,
            height: screen.bounds.height * screen.scale
        )
    }

    private func toggleControls() {
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
                .font(InkFont.cardTitle)
            Text(detail)
                .font(InkFont.secondary)
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
    MirrorView(library: MirrorLibrary(), onGoHome: {})
}
