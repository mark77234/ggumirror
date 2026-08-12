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
    nonisolated enum Status {
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

    // MARK: - 줌 없음 정책
    //
    // 꾸미러 거울에는 줌이 없다. 사용자 줌 / pinch / 프로그램 줌 / digital crop 전부 없다.
    //
    // 주의: 아래 둘은 다른 문제다.
    //   A. 기기의 실제 zoom(videoZoomFactor) — 여기서 1x로 못박는다.
    //   B. 비율이 다른 화면에 맞추면서 생기는 crop — 거울 geometry가 확정값이라 피할 수 없다.
    // B를 없애겠다고 Camera Area를 줄이거나 프레임을 두껍게 만들지 않는다.

    /// 기기 줌 배율. 항상 1x다.
    nonisolated static let zoomFactor: CGFloat = 1

    /// 화면에 놓는 방법. **Camera Area를 꽉 채운다.**
    ///
    /// 거울 프레임 두께(108 / 108 / 180 / 220)와 Camera Area(864 × 1940)는 확정값이다.
    /// 카메라 화각을 넓히겠다고 이걸 `.resizeAspect`로 바꾸면 영상이 작아지고
    /// 남는 자리만큼 프레임이 두꺼워 보인다 — 디자인이 바뀌므로 하지 않는다.
    nonisolated static let previewGravity: AVLayerVideoGravity = .resizeAspectFill

    // MARK: - 가장 넓은 화각 고르기

    /// format 하나를 고르는 데 필요한 것만 뽑은 값. 순수 함수로 시험할 수 있게 분리했다.
    nonisolated struct FormatChoice: Equatable {
        let fieldOfView: Float
        let width: Int32
        let height: Int32

        var pixels: Int { Int(width) * Int(height) }
    }

    /// 화면 세로가 길어 소스의 **가로 일부는 어차피 잘린다.**
    /// 반대로 세로로 보이는 화각은 format의 `videoFieldOfView`(가로 화각)가 그대로 살아난다.
    /// 그래서 화각이 가장 큰 format이 곧 가장 넓게 보이는 format이다.
    ///
    /// 화각이 같다면 필요 이상으로 큰 버퍼를 받지 않도록 **작은 쪽**을 고른다.
    /// (화면보다 작아지지 않을 만큼은 남긴다.)
    nonisolated static func bestFormatIndex(_ candidates: [FormatChoice], minimumWidth: Int32 = 1080) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let widest = candidates.map(\.fieldOfView).max() ?? 0
        let sameFieldOfView = candidates.enumerated().filter { $0.element.fieldOfView == widest }

        // 화면 해상도를 채울 만한 것 중 가장 작은 것. 없으면 그중 가장 큰 것.
        let bigEnough = sameFieldOfView.filter { min($0.element.width, $0.element.height) >= minimumWidth }
        if let pick = bigEnough.min(by: { $0.element.pixels < $1.element.pixels }) { return pick.offset }
        return sameFieldOfView.max(by: { $0.element.pixels < $1.element.pixels })?.offset
    }

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

    /// 다시 시도해 볼 만한 상태인가.
    ///
    /// `.denied`만 최종이다 — 설정에서 권한을 바꿔야 하므로 여기서 할 수 있는 게 없다.
    /// **`.unavailable`은 최종이 아니다**: 잠금화면 extension이 뜨는 순간 다른 프로세스가
    /// 아직 카메라를 놓지 않았을 수 있다. 그때 한 번 실패한 것을 영구 실패로 굳히면
    /// 앱/extension을 다시 띄울 때까지 검은 화면이 남는다.
    nonisolated static func canRetry(_ status: Status) -> Bool { status != .denied }

    /// 권한 확인 → 세션 구성 → 실행. 구성이 끝난 뒤에만 status가 .ready가 되므로
    /// preview layer는 항상 connection이 준비된 상태에서 붙는다.
    func start() async {
        guard Self.canRetry(status) else { return }
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

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 카메라를 못 잡는 경우가 있다 — 다른 프로세스가 아직 놓지 않았거나 일시적으로 막혔을 때.
        // **여기서 `isConfigured`를 세우지 않는다.** 세우면 그 실패가 영구히 굳어
        // 다시 시도해도 입력 없는 세션이 남는다(잠금화면에서 검은 화면으로 보였던 원인).
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }

        configure(device)

        session.addInput(input)
        addFrameOutput()

        // 실제로 붙은 뒤에만 "구성 완료"다.
        isConfigured = true
    }

    /// 줌은 1x로 못박고, 쓸 수 있는 format 중 화각이 가장 넓은 것을 고른다.
    /// **디지털 줌을 쓰지 않고** 화각을 넓히는 유일한 정상 경로다.
    private nonisolated func configure(_ device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }

        // 30fps 이상 나오는 format만 후보로 본다.
        let candidates = device.formats.filter { format in
            format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }
        let choices = candidates.map { format -> FormatChoice in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return FormatChoice(
                fieldOfView: format.videoFieldOfView,
                width: size.width,
                height: size.height
            )
        }
        if let index = Self.bestFormatIndex(choices) {
            device.activeFormat = candidates[index]
            #if DEBUG
            print("[MirrorCamera] format \(choices[index]) / 후보 \(choices.count)개 중 화각 최대")
            #endif
        }

        // 다른 앱이 남긴 값이 있을 수 있으므로 1x임을 명시적으로 확인한다.
        device.videoZoomFactor = Self.zoomFactor
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
