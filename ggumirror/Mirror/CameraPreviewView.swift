//
//  CameraPreviewView.swift
//  ggumirror
//
//  Phase 1-1: mirrored, edge-to-edge preview layer.
//

import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewLayerView {
        PreviewLayerView(session: session)
    }

    func updateUIView(_ uiView: PreviewLayerView, context: Context) {}
}

final class PreviewLayerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        backgroundColor = .black
        // Camera Area를 꽉 채운다. 거울 프레임 두께와 카메라 영역 크기는 확정값이라 건드리지 않는다.
        previewLayer.videoGravity = MirrorCamera.previewGravity
        previewLayer.session = session

        guard let connection = previewLayer.connection else { return }

        // 전면 카메라 좌우 반전. 세션 재구성과 무관하게 유지되도록 자동 조정은 끈다.
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        // Portrait 전용 앱. capture pipeline과 같은 각도를 써서 화면과 사진이 어긋나지 않게 한다.
        if connection.isVideoRotationAngleSupported(MirrorCamera.portraitRotationAngle) {
            connection.videoRotationAngle = MirrorCamera.portraitRotationAngle
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
