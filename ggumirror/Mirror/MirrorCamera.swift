//
//  MirrorCamera.swift
//  ggumirror
//
//  Phase 1-1: front camera capture session.
//

import AVFoundation

@Observable
@MainActor
final class MirrorCamera {
    enum Status {
        case idle
        case ready
        case denied
        case unavailable
    }

    /// 카메라를 화면에 붙일 수 있는 상태인지만 나타낸다.
    /// background에서 세션을 멈춰도 .ready를 유지해서 preview layer를 다시 만들지 않는다.
    private(set) var status: Status = .idle

    /// 거울 용도로 실용적인 최대 배율. 기기 지원 범위와 함께 clamp 된다.
    static let practicalMaxZoom: CGFloat = 2.5

    /// 현재 배율. 기기가 확대를 지원하지 않으면 1로 고정된다.
    private(set) var zoomFactor: CGFloat = 1
    private(set) var maxZoomFactor: CGFloat = 1

    // ponytail: AVCaptureSession is internally locked; every mutation below happens on sessionQueue only.
    nonisolated(unsafe) let session = AVCaptureSession()
    private nonisolated let sessionQueue = DispatchQueue(label: "com.mark77234.ggumirror.camera")
    @ObservationIgnored private nonisolated(unsafe) var isConfigured = false
    @ObservationIgnored private nonisolated(unsafe) var videoDevice: AVCaptureDevice?
    /// sessionQueue에서 읽는 목표 배율. UI의 zoomFactor와 같은 값을 따라간다.
    @ObservationIgnored private nonisolated(unsafe) var targetZoom: CGFloat = 1
    @ObservationIgnored private nonisolated(unsafe) var deviceMaxZoom: CGFloat = 1

    /// 권한 확인 → 세션 구성 → 실행. 구성이 끝난 뒤에만 status가 .ready가 되므로
    /// preview layer는 항상 connection이 준비된 상태에서 붙는다.
    func start() async {
        guard status != .denied, status != .unavailable else { return }
        guard await isAuthorized() else {
            status = .denied
            return
        }
        status = await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                configureIfNeeded()
                guard !session.inputs.isEmpty else {
                    continuation.resume(returning: .unavailable)
                    return
                }
                if !session.isRunning { session.startRunning() }
                applyZoom()   // 세션을 다시 켤 때도 배율을 유지한다.
                continuation.resume(returning: .ready)
            }
        }
        maxZoomFactor = min(Self.practicalMaxZoom, deviceMaxZoom)
        zoomFactor = min(zoomFactor, maxZoomFactor)
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// 기기 지원 범위 안으로 clamp 한 뒤 적용한다.
    func setZoom(_ factor: CGFloat) {
        let clamped = min(max(factor, 1), maxZoomFactor)
        guard clamped != zoomFactor else { return }
        zoomFactor = clamped
        targetZoom = clamped
        sessionQueue.async { [self] in applyZoom() }
    }

    private nonisolated func applyZoom() {
        guard let device = videoDevice else { return }
        let clamped = min(max(targetZoom, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        guard device.videoZoomFactor != clamped, (try? device.lockForConfiguration()) != nil else { return }
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
    }

    private func isAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    private nonisolated func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }

        session.addInput(input)
        videoDevice = device
        deviceMaxZoom = device.maxAvailableVideoZoomFactor
    }
}
