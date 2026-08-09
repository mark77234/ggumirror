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

    // ponytail: AVCaptureSession is internally locked; every mutation below happens on sessionQueue only.
    nonisolated(unsafe) let session = AVCaptureSession()
    private nonisolated let sessionQueue = DispatchQueue(label: "com.mark77234.ggumirror.camera")
    @ObservationIgnored private nonisolated(unsafe) var isConfigured = false

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
                continuation.resume(returning: .ready)
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
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
    }
}
