//
//  CameraPreviewView.swift
//  ggumirror
//
//  Phase 1-1: mirrored, edge-to-edge preview layer.
//

import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let camera: MirrorCamera

    func makeUIView(context: Context) -> PreviewLayerView {
        PreviewLayerView(camera: camera)
    }

    func updateUIView(_ uiView: PreviewLayerView, context: Context) {}
}

final class PreviewLayerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    /// **반전 / 회전을 여기서 정하지 않는다.**
    ///
    /// 예전에는 이 초기화에서 `isVideoMirrored = true`를 한 번 박아 두었다.
    /// 그런데 preview layer의 connection은 output이 아니라 세션이 직접 들고 있는 것이라
    /// 카메라를 바꿀 때 아무도 다시 설정해 주지 않았다 — rear → front에서 화면이
    /// 뒤집혀 보이던 이유다. 지금은 `MirrorCamera` 한 곳이 세션의 **모든** video connection을
    /// 책임지고, 여기서는 붙었다는 사실만 알린다.
    init(camera: MirrorCamera) {
        super.init(frame: .zero)
        backgroundColor = .black
        // Camera Area를 꽉 채운다. 거울 프레임 두께와 카메라 영역 크기는 확정값이라 건드리지 않는다.
        previewLayer.videoGravity = MirrorCamera.previewGravity
        previewLayer.session = camera.session

        // preview connection은 지금 막 생겼다. 지금 카메라 기준으로 정책을 건다.
        camera.applyCurrentConnectionPolicy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
