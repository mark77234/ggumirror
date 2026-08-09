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
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = session

        // 전면 카메라 좌우 반전. 세션 재구성과 무관하게 유지되도록 자동 조정은 끈다.
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            MainActor.assumeIsolated {
                self?.apply(rotationAngle: coordinator.videoRotationAngleForHorizonLevelPreview)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func apply(rotationAngle: CGFloat) {
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(rotationAngle)
        else { return }
        connection.videoRotationAngle = rotationAngle
    }
}
