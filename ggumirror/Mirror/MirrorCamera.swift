//
//  MirrorCamera.swift
//  ggumirror
//
//  Phase 1-1: front camera capture session.
//

import AVFoundation
import UIKit

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

    /// Portrait 전용. AVCaptureConnection에서 세로 방향에 해당하는 각도.
    nonisolated static let portraitRotationAngle: CGFloat = 90

    // ponytail: AVCaptureSession is internally locked; every mutation below happens on sessionQueue only.
    nonisolated(unsafe) let session = AVCaptureSession()
    private nonisolated let sessionQueue = DispatchQueue(label: "com.mark77234.ggumirror.camera")
    @ObservationIgnored private nonisolated(unsafe) var isConfigured = false

    /// Capture용 최신 프레임 보관소.
    @ObservationIgnored private nonisolated let frames = LatestFrameStore()
    private nonisolated let videoQueue = DispatchQueue(label: "com.mark77234.ggumirror.frames")

    /// 지금 화면에 보이는 것과 같은 최신 프레임.
    /// preview와 동일하게 좌우 반전 + Portrait 회전이 적용된 상태로 나온다.
    func currentFrame() -> UIImage? { frames.snapshot() }

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
        addFrameOutput()
    }

    /// preview와 같은 그림을 얻기 위한 video data output.
    /// 좌우 반전과 회전을 connection에 직접 걸어두면 나오는 프레임이 곧 화면에 보이는 그림이 된다.
    private nonisolated func addFrameOutput() {
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(frames, queue: videoQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        guard let connection = output.connection(with: .video) else { return }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        // Portrait 전용 앱이므로 90도로 고정한다. 버퍼 픽셀 자체가 세로로 회전되어 나온다.
        // (RotationCoordinator는 세션 구성 시점에 초기값이 0으로 잡히고 기기를 돌리지 않으면
        //  갱신되지 않아서, 프레임이 landscape로 남는 원인이었다.)
        if connection.isVideoRotationAngleSupported(Self.portraitRotationAngle) {
            connection.videoRotationAngle = Self.portraitRotationAngle
        }
    }
}

/// 최신 프레임 1장만 붙잡아 두는 delegate.
private nonisolated final class LatestFrameStore:
    NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable
{
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private let context = CIContext()

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        latest = buffer
        lock.unlock()
    }

    func snapshot() -> UIImage? {
        lock.lock()
        let buffer = latest
        lock.unlock()
        guard let buffer else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
