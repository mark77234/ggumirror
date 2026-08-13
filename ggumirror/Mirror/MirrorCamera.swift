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

    /// 앞/뒤. AVFoundation 값을 UI까지 흘리지 않기 위해 작은 모델 하나만 둔다.
    nonisolated enum Position: String, CaseIterable, Sendable {
        case front
        case back

        var av: AVCaptureDevice.Position { self == .front ? .front : .back }

        /// 거울은 전면일 때만 좌우를 뒤집는다. 후면은 눈으로 보는 것과 같아야 한다.
        var isMirrored: Bool { self == .front }

        var flipped: Position { self == .front ? .back : .front }

        /// 앱을 새로 켜면 항상 전면이다 — 꾸미러는 거울 앱이다.
        /// 후면 선택을 앱 재실행까지 저장하지 않는다.
        static let initial: Position = .front
    }

    /// 이 카메라가 무엇까지 할 수 있는가.
    ///
    /// **잠금화면 extension은 `.viewfinder`다** — 전면 고정, 사진 output 없음, 전환 없음.
    /// 기본값이 `.viewfinder`라서 본앱 기능을 추가해도 extension 동작이 따라 바뀌지 않는다.
    nonisolated enum Role: Sendable {
        case viewfinder
        case mirror
    }

    /// 카메라를 화면에 붙일 수 있는 상태인지만 나타낸다.
    /// background에서 세션을 멈춰도 .ready를 유지해서 preview layer를 다시 만들지 않는다.
    private(set) var status: Status = .idle

    /// 지금 실제로 붙어 있는 카메라. **성공한 전환만 반영된다** —
    /// UI가 후면이라고 표시하는데 실제로는 전면인 상태를 만들지 않는다.
    private(set) var position: Position = .initial

    /// 세션 쪽에서 보는 같은 값. 세션 변경은 `sessionQueue`에서만 일어나므로
    /// 이 값도 그 큐에서만 바뀐다. UI용 `position`은 성공한 결과를 받아 따라간다.
    @ObservationIgnored private nonisolated(unsafe) var activePosition: Position = .initial

    /// 전환이 진행 중인가. 연타를 막는 데 쓴다.
    private(set) var isSwitching = false

    let role: Role

    init(role: Role = .viewfinder) {
        self.role = role
    }

    /// 전환 버튼을 쓸 수 있는가.
    var canSwitchCamera: Bool {
        role == .mirror && status == .ready && !isSwitching
    }

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

    /// 실제 still photo(하드웨어 flash 포함)를 찍는 output. **`.mirror` role에서만 만든다.**
    /// 잠금화면 extension은 이걸 갖지 않는다 — 시작이 느려질 이유를 만들지 않는다.
    @ObservationIgnored private nonisolated(unsafe) var photoOutput: AVCapturePhotoOutput?

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
        guard let device = Self.device(at: activePosition),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }

        configure(device)

        session.addInput(input)
        addFrameOutput()
        if role == .mirror { addPhotoOutput() }
        applyConnections(for: activePosition)

        // 실제로 붙은 뒤에만 "구성 완료"다.
        isConfigured = true
        CameraLog.event("position \(activePosition.rawValue) configured role=\(role)")
    }

    /// 후면도 **일반 1x wide** 하나만 쓴다. ultra-wide / tele를 임의로 고르지 않는다.
    private nonisolated static func device(at position: Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position.av)
    }

    // MARK: - 전환

    /// 앞 ↔ 뒤. 실패하면 **원래 카메라가 그대로 살아 있다.**
    ///
    /// 세션 변경은 전부 `sessionQueue`에서만 일어나므로 retry(`start()`)와 자연히 직렬화된다.
    /// 여기서 별도 lock을 만들지 않는다.
    func switchCamera() async {
        guard canSwitchCamera else { return }
        let target = position.flipped
        isSwitching = true
        defer { isSwitching = false }

        CameraLog.event("switching \(position.rawValue) -> \(target.rawValue)")
        let landed: Position = await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                continuation.resume(returning: swapInput(to: target))
            }
        }
        position = landed
        CameraLog.event("position \(landed.rawValue) ready")
    }

    /// 성공하면 새 position, 실패하면 **바꾸기 전 position**을 돌려준다.
    private nonisolated func swapInput(to target: Position) -> Position {
        let current = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
        guard let existing = current.first,
              let device = Self.device(at: target),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            CameraLog.event("switch failed: no device")
            return target.flipped
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // input을 갈아 끼우면 output connection이 새로 만들어지므로 반전/회전을 다시 걸어야 한다.
        session.removeInput(existing)
        guard session.canAddInput(input) else {
            // 새 input을 붙일 수 없다. **원래 것을 되돌려 놓는다** — 작동하던 카메라를 잃지 않는다.
            if session.canAddInput(existing) {
                session.addInput(existing)
                applyConnections(for: target.flipped)
                CameraLog.event("switch failed: restored previous input")
            } else {
                // 되돌리기도 실패했다. 다음 start()가 처음부터 다시 구성할 수 있게 비운다.
                session.inputs.forEach(session.removeInput)
                session.outputs.forEach(session.removeOutput)
                photoOutput = nil
                isConfigured = false
                CameraLog.event("switch failed: session reset for retry")
            }
            return target.flipped
        }

        configure(device)
        session.addInput(input)
        activePosition = target
        applyConnections(for: target)
        return target
    }

    /// 지금 붙어 있는 카메라에 맞춰 **세션의 모든 video connection**을 다시 맞춘다.
    ///
    /// `session.connections`를 쓴다 — `session.outputs`만 돌면
    /// **preview layer의 connection이 빠진다.** preview는 output이 아니라
    /// `AVCaptureVideoPreviewLayer`가 세션에 직접 만드는 connection이라서,
    /// 전면↔후면을 바꿔도 아무도 다시 설정해 주지 않는 자리가 생긴다.
    /// 그 자리가 rear → front에서 화면이 뒤집혀 보이던 원인이다.
    ///
    /// preview layer는 세션 구성보다 늦게 붙기도 하므로
    /// `PreviewLayerView`가 붙은 직후에도 이 함수를 한 번 부른다.
    nonisolated func applyConnections(for position: Position) {
        for connection in session.connections
        where connection.inputPorts.contains(where: { $0.mediaType == .video }) {
            // 반전은 **우리가 정한다.** 자동 조정을 켜 두면 input이 바뀔 때 system이
            // `isVideoMirrored`를 임의로 되돌려 놓는다.
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position.isMirrored
            }
            // Portrait 전용 앱이므로 90도로 고정한다. 버퍼 픽셀 자체가 세로로 회전되어 나온다.
            // 전면/후면에 다른 숫자를 쓰지 않는다 — 같은 값이 두 카메라 모두에서 정방향이다.
            if connection.isVideoRotationAngleSupported(Self.portraitRotationAngle) {
                connection.videoRotationAngle = Self.portraitRotationAngle
            }
            CameraLog.event(
                "connection position=\(position.rawValue) "
                + "rotation=\(connection.videoRotationAngle) "
                + "mirrored=\(connection.isVideoMirrored) "
                + "auto=\(connection.automaticallyAdjustsVideoMirroring)"
            )
        }
    }

    /// preview layer가 세션에 붙은 뒤 호출된다. 붙는 시점이 구성보다 늦어도
    /// **초기 front와 재전환 front가 같은 경로**를 타게 하는 자리다.
    nonisolated func applyCurrentConnectionPolicy() {
        sessionQueue.async { [self] in
            applyConnections(for: activePosition)
        }
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
            CameraLog.event("format \(choices[index]) / 후보 \(choices.count)개 중 화각 최대")
        }

        // 다른 앱이 남긴 값이 있을 수 있으므로 1x임을 명시적으로 확인한다.
        device.videoZoomFactor = Self.zoomFactor
    }

    /// preview와 같은 그림을 얻기 위한 video data output.
    /// 좌우 반전과 회전은 `applyConnections`가 걸어준다 — 규칙이 한 곳에만 있어야
    /// 카메라를 바꿔도 어긋나지 않는다.
    ///
    /// (RotationCoordinator는 세션 구성 시점에 초기값이 0으로 잡히고 기기를 돌리지 않으면
    ///  갱신되지 않아서, 프레임이 landscape로 남는 원인이었다.)
    private nonisolated func addFrameOutput() {
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(frames, queue: videoQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
    }

    private nonisolated func addPhotoOutput() {
        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        photoOutput = output
    }

    // MARK: - Flash

    /// 요청과 기기 능력에서 실제로 쓸 mode를 정한다. **지원하지 않는 mode를 settings에 넣지 않는다.**
    /// 순수 함수라 기기 없이 시험할 수 있다.
    nonisolated static func flashMode(
        wantsFlash: Bool,
        supported: [AVCaptureDevice.FlashMode]
    ) -> AVCaptureDevice.FlashMode? {
        if wantsFlash, supported.contains(.on) { return .on }
        if supported.contains(.off) { return .off }
        // 둘 다 못 쓰면 건드리지 않는다 — 기본값 그대로 찍는다.
        return nil
    }

    /// 공식 flash가 없을 때만 화면 flash로 대신한다. 꺼져 있으면 어느 쪽도 하지 않는다.
    nonisolated static func needsScreenFlash(wantsFlash: Bool, officialSupported: Bool) -> Bool {
        wantsFlash && !officialSupported
    }

    /// 지금 카메라에서 **공식 flash**(후면 LED · 전면 Retina Flash)를 쓸 수 있는가.
    ///
    /// 기기·SDK가 알려주는 값을 그대로 쓴다. 어떤 기기가 전면 flash를 지원하는지
    /// 우리가 표로 적어두지 않는다. `false`면 화면 flash로 대신한다.
    var isOfficialFlashSupported: Bool {
        photoOutput?.supportedFlashModes.contains(.on) ?? false
    }

    // MARK: - 촬영

    /// 실제 still photo 한 장. 화면에서 보던 것과 **같은 방향**으로 나온다.
    ///
    /// - Parameter flash: 공식 flash를 요청할지. 지원하지 않으면 조용히 끈 채로 찍는다 —
    ///   flash를 못 쓴다고 사진을 못 찍게 만들지 않는다.
    ///
    /// photo output이 없거나(role이 viewfinder) 실패하면 마지막 preview 프레임으로 떨어진다.
    func capturePhoto(flash: Bool) async -> UIImage? {
        guard let output = photoOutput else { return currentFrame() }

        // 요청마다 새 settings를 만든다. 재사용하면 AVFoundation이 예외를 던진다.
        let settings = AVCapturePhotoSettings()
        if let mode = Self.flashMode(wantsFlash: flash, supported: output.supportedFlashModes) {
            settings.flashMode = mode
            if flash {
                CameraLog.event(mode == .on ? "flash on hardware" : "flash unsupported fallback off")
            }
        }

        let receiver = PhotoReceiver()
        let image = await withCheckedContinuation { continuation in
            receiver.onFinish = { continuation.resume(returning: $0) }
            // delegate는 완료까지 살아 있어야 한다. receiver가 스스로를 붙잡는다.
            receiver.retain()
            output.capturePhoto(with: settings, delegate: receiver)
        }
        // 사진을 못 얻어도 사용자가 촬영을 못 하게 만들지 않는다.
        return image ?? currentFrame()
    }
}

// MARK: - 사진 delegate

/// `capturePhoto` 한 번에 대응하는 delegate. AVFoundation은 delegate를 소유하지 않으므로
/// 완료될 때까지 스스로를 붙잡는다.
private nonisolated final class PhotoReceiver: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    var onFinish: ((UIImage?) -> Void)?
    private var selfReference: PhotoReceiver?

    func retain() { selfReference = self }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        defer { selfReference = nil }
        guard error == nil, let data = photo.fileDataRepresentation() else {
            CameraLog.event("photo capture failed")
            onFinish?(nil)
            return
        }
        onFinish?(UIImage(data: data))
    }
}

// MARK: - 로그

/// DEBUG 빌드에만, **상태만.** 파일 경로 · 사진 데이터 · 사용자 정보는 남기지 않는다.
nonisolated enum CameraLog {
    static func event(_ message: String) {
        #if DEBUG
        print("[MirrorCamera] \(message)")
        #endif
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
