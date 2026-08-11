//
//  GgumirrorCaptureViewFinder.swift
//  GgumirrorCapture
//
//  잠금화면에서 바로 쓰는 **Quick Mirror**.
//
//  본앱의 `MirrorCamera` / `CameraPreviewView`를 그대로 쓴다(target membership으로만 공유).
//  그래서 전면 · 좌우 반전 · 1x · 가장 넓은 화각 · Portrait 정책이 본앱과 자동으로 같다.
//
//  이 화면이 하지 않는 것 (sandbox 제약과 C-1A 범위):
//  - network / backend 호출 (extension은 network를 쓸 수 없다)
//  - App Group · MirrorStore · StickerStore · Keychain · 로그인 정보 접근
//  - 사용자의 거울 장식 렌더링 (C-1B)
//
//  잠금 상태에서 열리는 화면이라 **카메라를 최우선으로 띄운다.**
//  splash / 홈 / 로그인 / 상점 같은 중간 화면을 두지 않는다.
//

import AVFoundation
import AVKit
import LockedCameraCapture
import SwiftUI
import UIKit

struct GgumirrorCaptureViewFinder: View {
    let session: LockedCameraCaptureSession

    @State private var camera = MirrorCamera()
    @State private var notice: String?
    @State private var isSaving = false
    @Environment(\.scenePhase) private var scenePhase

    /// 지금 찍을 수 있는지. **화면 버튼과 하드웨어 버튼이 같은 조건을 쓴다.**
    /// 찍을 수 없을 때 하드웨어 버튼을 켜두면 눌러도 아무 일이 없는 버튼이 된다.
    private var canCapture: Bool { camera.status == .ready && !isSaving }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.status {
            case .ready:
                // edge-to-edge. 거울이므로 화면을 꽉 채운다.
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
            case .denied, .unavailable:
                unavailable
            case .idle:
                // 카메라가 붙기 전 아주 짧은 순간. 문구를 띄우지 않는다.
                EmptyView()
            }

            controls
        }
        // 시스템 하드웨어 촬영 버튼(전원/볼륨/Action button, AirPods stem 등).
        // **화면의 흰 버튼과 완전히 같은 `capture()`를 부른다** — 별도 촬영 경로를 만들지 않는다.
        //
        // `.ended`에서만 찍는다:
        //   - `.began`은 누르기 시작일 뿐이고 `.cancelled`로 취소될 수 있다.
        //     취소가 존재한다는 것은 **끝났을 때** 실행하라는 뜻이다.
        //   - 그래서 한 번 누르면 한 장이다. `.began`과 함께 잡으면 두 장이 된다.
        //
        // 촬영 소리는 시스템 기본값을 그대로 둔다(`defaultSoundDisabled`를 건드리지 않는다).
        .onCameraCaptureEvent(isEnabled: canCapture) { event in
            guard event.phase == .ended else { return }
            capture()
        }
        .task {
            // 열리자마자 카메라부터.
            QuickMirrorLog.event("camera starting")
            await camera.start()
            QuickMirrorLog.event("camera \(camera.status)")
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await camera.start() }
            case .background: camera.stop()
            default: break
            }
        }
        .alert("알림", isPresented: .init(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("확인") { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    // MARK: - 조작

    private var controls: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    openApp()
                } label: {
                    Text("꾸미러 열기")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.45), in: Capsule())
                }
                .accessibilityLabel("꾸미러 앱 열기")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            Button {
                capture()
            } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 68, height: 68)
                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 4).padding(-6))
                    .opacity(canCapture ? 1 : 0.4)
            }
            .disabled(!canCapture)
            .padding(.bottom, 36)
            .accessibilityLabel("사진 찍기")
        }
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34))
            Text(camera.status == .denied ? "카메라 권한이 필요해요" : "지금은 카메라를 쓸 수 없어요")
                .font(.system(size: 16, weight: .semibold))
            Text("설정에서 꾸미러의 카메라 권한을 확인해 주세요.")
                .font(.system(size: 13))
                .opacity(0.7)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(24)
    }

    // MARK: - 촬영

    /// **화면 버튼과 하드웨어 버튼이 함께 쓰는 유일한 촬영 경로.**
    ///
    /// 화면에 보이는 그대로 저장한다 — `currentFrame()`은 이미 좌우 반전 + Portrait 회전된 프레임이다.
    /// 저장 위치는 **`session.sessionContentURL`뿐이다.** extension이 자기 영구 저장소를 만들지 않는다.
    ///
    /// 이벤트가 몰려 들어와도 `isSaving`이 한 번에 한 장만 통과시킨다.
    /// 파일 이름에 시간 + 무작위 조각이 붙으므로 이름이 겹치지도 않는다.
    private func capture() {
        guard canCapture, let image = camera.currentFrame() else {
            notice = "사진을 찍지 못했어요. 다시 시도해 주세요."
            return
        }
        isSaving = true
        defer { isSaving = false }

        do {
            try QuickMirrorCaptureStore.save(image, in: session)
            QuickMirrorLog.event("capture saved")
        } catch {
            // 실패해도 화면은 살아 있어야 한다. 이유는 사용자에게 옮기지 않는다.
            notice = "사진을 저장하지 못했어요."
        }
    }

    // MARK: - 본앱으로

    /// 공식 경로. custom URL scheme을 쓰지 않는다.
    /// 잠긴 상태면 시스템이 인증을 요구한 뒤 본앱을 연다.
    private func openApp() {
        Task {
            do {
                QuickMirrorLog.event("opening app")
                try await session.openApplication(for: QuickMirrorActivity.openMirror())
            } catch {
                notice = "꾸미러를 열지 못했어요."
            }
        }
    }
}
