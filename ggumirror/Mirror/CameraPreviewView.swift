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
    /// 화면에 담는 방법. **`camera.framing`을 그대로 넘긴다** —
    /// 값으로 받아야 SwiftUI가 바뀐 것을 알고 `updateUIView`를 부른다.
    var framing: MirrorCamera.Framing = .fill

    func makeUIView(context: Context) -> PreviewLayerView {
        PreviewLayerView(camera: camera, framing: framing)
    }

    func updateUIView(_ uiView: PreviewLayerView, context: Context) {
        uiView.apply(framing)
    }
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
    init(camera: MirrorCamera, framing: MirrorCamera.Framing) {
        super.init(frame: .zero)
        backgroundColor = .black
        apply(framing)
        previewLayer.session = camera.session

        // preview connection은 지금 막 생겼다. 지금 카메라 기준으로 정책을 건다.
        camera.applyCurrentConnectionPolicy()
    }

    /// 자르는 방법을 바꾼다. **layer의 gravity 하나뿐이다** —
    /// 우리가 화면 크기를 계산해서 확대/축소하지 않으므로 가짜 화각이 생길 수 없다.
    ///
    /// `.resizeAspect`(넓게)에서는 위아래가 남는다. 그것이 센서가 준 전부다.
    func apply(_ framing: MirrorCamera.Framing) {
        let gravity = framing.previewGravity
        guard previewLayer.videoGravity != gravity else { return }
        // 자르는 방식이 바뀌는 것이라 위치를 애니메이션하지 않는다 — 화면이 미끄러져 보인다.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.videoGravity = gravity
        CATransaction.commit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
