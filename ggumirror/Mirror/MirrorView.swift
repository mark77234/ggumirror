//
//  MirrorView.swift
//  ggumirror
//
//  Phase 1-1: app launches straight into the mirror camera.
//

import SwiftUI

struct MirrorView: View {
    @State private var camera = MirrorCamera()
    @Environment(\.scenePhase) private var scenePhase

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
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .task { await camera.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await camera.start() }
            case .background: camera.stop()
            default: break
            }
        }
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
