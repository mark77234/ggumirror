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

    /// 세션 큐가 읽어 둔 지금 카메라의 배율 범위. `activePosition`과 같은 규칙이다 —
    /// 그 큐에서만 쓰고, 화면 상태는 결과를 받아 따라간다.
    @ObservationIgnored private nonisolated(unsafe) var activeCapability: ZoomCapability = .none

    /// 전환이 진행 중인가. 연타를 막는 데 쓴다.
    private(set) var isSwitching = false

    /// 지금 붙어 있는 카메라가 낼 수 있는 배율. **카메라를 바꾸면 다시 읽는다.**
    private(set) var zoomCapability: ZoomCapability = .none

    /// 지금 보고 있는 배율(사용자 기준). 화면 표시와 항상 같은 값이다.
    private(set) var logicalZoom: CGFloat = 1

    /// pinch가 시작될 때의 배율. 손가락 배수를 여기에 곱한다.
    @ObservationIgnored private var pinchBaseline: CGFloat?

    /// 이 카메라에서 실제로 고를 수 있는 배율 버튼.
    var zoomPresets: [CGFloat] { Self.zoomPresets(for: zoomCapability) }

    /// 지금 켜져 보일 버튼. pinch 중 사이 값이면 `nil`이다.
    var selectedZoomPreset: CGFloat? {
        Self.selectedPreset(logical: logicalZoom, presets: zoomPresets)
    }

    /// 배율을 바꿀 수 있는가. 잠금화면 viewfinder에는 줌 UI가 없다.
    var canZoom: Bool { role == .mirror && status == .ready && zoomPresets.count > 1 }

    let role: Role

    init(role: Role = .viewfinder, preferences: UserDefaults = .standard) {
        self.role = role
        self.preferences = preferences
        self.frontFraming = Self.storedFraming(in: preferences) ?? .default
    }

    /// 저장된 선택. 고른 적이 없거나 모르는 값이면 `nil`이고 기본값으로 간다.
    nonisolated static func storedFraming(in preferences: UserDefaults) -> Framing? {
        guard let raw = preferences.string(forKey: framingKey) else { return nil }
        return Framing(rawValue: raw)
    }

    /// 전환 버튼을 쓸 수 있는가.
    var canSwitchCamera: Bool {
        role == .mirror && status == .ready && !isSwitching
    }

    /// Portrait 전용. AVCaptureConnection에서 세로 방향에 해당하는 각도.
    nonisolated static let portraitRotationAngle: CGFloat = 90

    // MARK: - 줌
    //
    // 사용자가 보는 배율(**logical**)과 기기가 쓰는 배율(**device factor**)은 다르다.
    // ultra-wide를 품은 virtual 카메라에서 `videoZoomFactor == 1`은 1x가 아니라 **0.5x**다.
    // 그 차이를 모르고 `videoZoomFactor = 0.5`를 쓰면 어떤 기기에서도 실패하고
    // (`minAvailableVideoZoomFactor`가 1이다), `= 1`을 쓰면 0.5x 화면이 1x라고 표시된다.
    //
    // 아래 계산은 전부 순수 함수다 — 기기 없이 시험한다. **기기 이름을 적지 않는다.**

    /// 지금 카메라가 낼 수 있는 배율 범위. `baseFactor`가 logical ↔ device 변환의 전부다.
    nonisolated struct ZoomCapability: Equatable, Sendable {
        /// logical 1x에 해당하는 device factor.
        /// 일반 wide 카메라는 `1`, ultra-wide로 시작하는 virtual 카메라는 그 전환 지점(보통 `2`)이다.
        let baseFactor: CGFloat
        let minDeviceFactor: CGFloat
        let maxDeviceFactor: CGFloat

        /// 아무 카메라도 없을 때. 1x 하나만 있는 것으로 본다.
        static let none = ZoomCapability(baseFactor: 1, minDeviceFactor: 1, maxDeviceFactor: 1)

        var minLogical: CGFloat { minDeviceFactor / baseFactor }
        var maxLogical: CGFloat { maxDeviceFactor / baseFactor }

        /// 부동소수 비교 여유. `0.5 * 2 == 1`이 정확히 떨어지지 않는 기기가 있다.
        static let epsilon: CGFloat = 0.0001

        func supports(logical: CGFloat) -> Bool {
            logical >= minLogical - Self.epsilon && logical <= maxLogical + Self.epsilon
        }

        /// 이 logical 배율을 기기에 넣을 값으로. **언제나 실제 범위 안으로 자른다.**
        func deviceFactor(forLogical logical: CGFloat) -> CGFloat {
            min(max(logical * baseFactor, minDeviceFactor), maxDeviceFactor)
        }

        func logical(forDeviceFactor factor: CGFloat) -> CGFloat { factor / baseFactor }

        /// 범위 안으로 자른 logical 값.
        func clampedLogical(_ wanted: CGFloat) -> CGFloat {
            logical(forDeviceFactor: deviceFactor(forLogical: wanted))
        }
    }

    /// UI가 고를 수 있는 배율 후보. **여기 있다고 다 보이지 않는다** — 기기가 낼 수
    /// 있는 것만 남는다. 나중에 3x · 5x를 더하려면 이 줄에 추가한다.
    nonisolated static let zoomPresetCandidates: [CGFloat] = [0.5, 1, 2]

    /// logical 1x에 해당하는 device factor를 **기기가 알려주는 값만으로** 구한다.
    ///
    /// virtual 카메라의 첫 렌즈가 ultra-wide면 device factor 1은 사용자가 보기에 0.5x다.
    /// 그때 사용자가 아는 1x는 **첫 렌즈 전환 지점**이다. 그 외에는 1이 곧 1x다.
    nonisolated static func baseZoomFactor(
        constituentTypes: [AVCaptureDevice.DeviceType],
        switchOverFactors: [CGFloat]
    ) -> CGFloat {
        guard constituentTypes.first == .builtInUltraWideCamera,
              let firstSwitchOver = switchOverFactors.first,
              firstSwitchOver > 0
        else { return 1 }
        return firstSwitchOver
    }

    /// 이 카메라에서 실제로 쓸 수 있는 배율만 남긴다.
    ///
    /// 0.5x를 지원하지 않는 카메라에서 **software로 화각을 넓힐 수는 없다** —
    /// 없는 렌즈를 흉내 내지 않고 버튼을 감춘다.
    nonisolated static func zoomPresets(
        for capability: ZoomCapability,
        candidates: [CGFloat] = zoomPresetCandidates
    ) -> [CGFloat] {
        candidates.filter(capability.supports(logical:))
    }

    /// preset 버튼이 켜져 보일지. pinch로 사이 값(예: 1.37x)에 있으면 **아무것도 켜지 않는다** —
    /// 화면이 말하는 것과 실제 배율이 달라지면 안 된다.
    nonisolated static let zoomPresetTolerance: CGFloat = 0.05

    nonisolated static func selectedPreset(
        logical: CGFloat,
        presets: [CGFloat],
        tolerance: CGFloat = zoomPresetTolerance
    ) -> CGFloat? {
        presets.first { abs($0 - logical) <= tolerance }
    }

    // MARK: - 화면에 담는 방법 (framing)

    /// 카메라가 보내 준 그림을 **세로로 긴 화면에 어떻게 놓을 것인가.**
    ///
    /// 전면 센서는 4:3에 가깝고 화면은 9:19.5쯤이다. 꽉 채우려면 **좌우를 크게 잘라야**
    /// 하고, 그래서 얼굴이 기본 카메라 앱보다 훨씬 크게 보였다. 잘라낸 화각은
    /// 돌아오지 않는다 — software로 넓힐 수 없으므로 **자르지 않는 선택지**를 준다.
    ///
    /// 이건 **배율이 아니다.** 기기 zoom factor는 어느 쪽에서도 그대로다.
    nonisolated enum Framing: String, CaseIterable, Sendable {
        /// 센서가 보내 준 화각을 **하나도 자르지 않는다.** 위아래가 남는 것이 정상이다.
        case wide
        /// 화면을 꽉 채운다. 좌우가 잘린다. (기존 동작)
        case fill

        /// 아무것도 고른 적이 없을 때. **화면을 꽉 채운다.**
        ///
        /// 처음에는 `wide`였다 — 잘라낸 화각은 되돌릴 수 없으니 자르지 않는 쪽을
        /// 기본으로 두는 것이 안전하다고 봤다. 실기기 QA에서 뒤집혔다: 거울을 보는
        /// 사람은 위아래에 남는 검은 띠보다 **화면을 채운 거울**을 기대한다.
        /// 고르는 기능은 그대로다 — 기본값만 바뀐다.
        static let `default`: Framing = .fill

        /// 예전 이름. 기본값을 가리키던 호출부가 그대로 동작한다.
        static var initial: Framing { .default }

        var previewGravity: AVLayerVideoGravity {
            self == .wide ? .resizeAspect : .resizeAspectFill
        }

        var title: String { self == .wide ? "넓게" : "채우기" }
        var accessibilityTitle: String { self == .wide ? "넓게 보기" : "화면 채우기" }
    }

    /// 전면에서 고른 방법. 후면으로 갔다 돌아와도 살아 있다.
    ///
    /// **사용자가 고른 값은 앱을 다시 켜도 남는다.** 매번 다시 고르게 하면 그건
    /// 설정이 아니라 매번 묻는 질문이다. 고른 적이 없으면 `Framing.default`다 —
    /// 기본값이 바뀌어도 **이미 고른 사람의 선택을 덮지 않는다.**
    var frontFraming: Framing

    /// 고른 값을 적어 두는 곳. 기기 하나의 표시 설정이라 서버에 보내지 않는다.
    @ObservationIgnored private let preferences: UserDefaults
    private static let framingKey = "ggumirror.camera.frontFraming"

    /// 지금 실제로 쓰는 방법. **후면은 언제나 꽉 채운다** — 후면 UX는 그대로다.
    var framing: Framing { position == .front ? frontFraming : .fill }

    /// 전면에서만 고를 수 있다. 후면에는 이 버튼이 없다.
    var canChooseFraming: Bool {
        role == .mirror && status == .ready && position == .front
    }

    /// 지금 카메라가 보내 주는 그림의 비율(세로 기준 가로/세로).
    ///
    /// **4:3을 코드에 적지 않는다** — `activeFormat`이 실제로 무엇을 주는지 읽는다.
    /// 화면 회전(90도)을 이미 걸어 두었으므로 가로/세로를 뒤집어 본다.
    private(set) var sourceAspectRatio: CGFloat?

    /// 세션 큐가 읽어 둔 값. `activeCapability`와 같은 규칙이다.
    @ObservationIgnored private nonisolated(unsafe) var activeSourceAspect: CGFloat?

    /// 원본에서 **실제로 화면에 남는 넓이의 비율**(0...1). 1이면 하나도 자르지 않았다.
    ///
    /// 순수 함수라 기기 없이 시험한다. 여기가 "넓게 보기가 정말 덜 자르는가"의 근거다.
    nonisolated static func visibleSourceFraction(
        source: CGSize, viewport: CGSize, framing: Framing
    ) -> CGFloat {
        guard source.width > 0, source.height > 0,
              viewport.width > 0, viewport.height > 0
        else { return 1 }

        switch framing {
        case .wide:
            // 통째로 넣는다. 남는 자리는 화면 쪽에 생기지 원본이 잘리지 않는다.
            return 1
        case .fill:
            // 짧은 쪽을 기준으로 키우므로 긴 쪽이 잘린다.
            let scale = max(viewport.width / source.width, viewport.height / source.height)
            let visible = CGSize(width: viewport.width / scale, height: viewport.height / scale)
            return (visible.width * visible.height) / (source.width * source.height)
        }
    }

    /// 화면에 놓는 방법의 예전 기본값. `Framing.fill`과 같다 —
    /// 기존 호출부와 테스트가 가리키던 상수를 유지한다.
    nonisolated static let previewGravity: AVLayerVideoGravity = .resizeAspectFill

    /// 전면 framing을 바꾼다. **기기 배율은 건드리지 않는다** — 다른 문제다.
    func setFrontFraming(_ next: Framing) {
        guard canChooseFraming else { return }
        frontFraming = next
        // **명시적으로 고른 것만 적는다.** 기본값을 미리 적어 두면 나중에 기본값을
        // 바꿔도 "이미 고른 사람"으로 취급되어 아무도 새 기본값을 받지 못한다.
        preferences.set(next.rawValue, forKey: Self.framingKey)
        CameraLog.event("front framing \(next.rawValue)")
    }

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
        if status == .ready { adoptActiveCapability() }
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

        activeCapability = configure(device)

        session.addInput(input)
        addFrameOutput()
        if role == .mirror { addPhotoOutput() }
        applyConnections(for: activePosition)

        // 실제로 붙은 뒤에만 "구성 완료"다.
        isConfigured = true
        CameraLog.event("position \(activePosition.rawValue) configured role=\(role)")
    }

    /// **전면은 언제나 물리 wide 하나다.** virtual 전면 카메라를 가진 iPhone이 없다 —
    /// 그래서 전면에는 0.5x가 없고, 그것이 정상이다(software로 만들어내지 않는다).
    ///
    /// 후면은 ultra-wide를 품은 virtual 카메라를 **먼저** 찾는다. 0.5x는 렌즈가 있어야 나온다.
    /// 없으면 예전과 같은 일반 wide로 떨어진다 — 그 기기에는 0.5x 버튼이 없다.
    /// 기기 이름을 적지 않는다. 어떤 조합이 있는지는 `DiscoverySession`이 알려준다.
    private nonisolated static func device(at position: Position) -> AVCaptureDevice? {
        guard position == .back else {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
        // DiscoverySession은 우리가 적은 순서대로 돌려준다.
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        ).devices.first
    }

    /// 기기가 알려주는 값만으로 배율 범위를 읽는다.
    ///
    /// **`activeFormat`을 정한 뒤에 읽어야 한다** — format에 따라 쓸 수 있는 렌즈와
    /// 전환 지점이 달라진다. 순서가 바뀌면 없는 0.5x를 있다고 말하게 된다.
    private nonisolated static func capability(of device: AVCaptureDevice) -> ZoomCapability {
        let base = baseZoomFactor(
            constituentTypes: device.constituentDevices.map(\.deviceType),
            switchOverFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        )
        return ZoomCapability(
            baseFactor: base,
            minDeviceFactor: device.minAvailableVideoZoomFactor,
            maxDeviceFactor: device.maxAvailableVideoZoomFactor
        )
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
        // 카메라가 바뀌면 배율 범위도 바뀐다. 전면에는 0.5x가 없다.
        adoptActiveCapability()
        CameraLog.event("position \(landed.rawValue) ready presets=\(zoomPresets)")
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

        activeCapability = configure(device)
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

    /// 쓸 수 있는 format 중 화각이 가장 넓은 것을 고르고, 배율을 1x로 맞춘다.
    ///
    /// 여기서 말하는 1x는 **사용자가 아는 1x**다 — virtual 카메라에서는
    /// `videoZoomFactor = 1`이 0.5x이므로 그 값을 쓰지 않는다.
    ///
    /// 배율 범위를 돌려준다. 실패하면 `.none`이라 줌 UI가 나오지 않는다 —
    /// 설정 실패가 카메라를 못 쓰게 만들지는 않는다.
    @discardableResult
    private nonisolated func configure(_ device: AVCaptureDevice) -> ZoomCapability {
        guard (try? device.lockForConfiguration()) != nil else { return .none }
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
        // **고른 format이 실제로 주는 비율**을 읽는다. 세로로 세워서 본다(회전 90도 고정).
        let active = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        activeSourceAspect = active.height > 0
            ? CGFloat(active.height) / CGFloat(active.width)
            : nil

        // **format을 정한 뒤에** 범위를 읽는다 — format이 쓸 수 있는 렌즈를 정한다.
        let capability = Self.capability(of: device)
        // 다른 앱이 남긴 값이 있을 수 있으므로 1x를 명시적으로 넣는다.
        device.videoZoomFactor = capability.deviceFactor(forLogical: 1)
        CameraLog.event(
            "zoom base=\(capability.baseFactor) "
            + "range=\(capability.minLogical)...\(capability.maxLogical) logical"
        )
        return capability
    }

    // MARK: - 배율 바꾸기

    /// preset 버튼. 짧게 미끄러지듯 옮긴다 — 거울은 즉시성이 더 중요하므로 길게 끌지 않는다.
    ///
    /// `2^rate` 배/초. 0.5x → 2x(2옥타브)가 0.25초쯤 걸린다.
    nonisolated static let zoomRampRate: Float = 8

    /// preset을 눌렀을 때. **누른 배율로 정확히 간다** — pinch로 1.43x에 있었어도
    /// `1x`를 누르면 정확히 1x다.
    func selectZoom(logical: CGFloat) {
        guard role == .mirror, zoomCapability.supports(logical: logical) else { return }
        apply(logical: logical, ramps: true)
    }

    /// pinch 진행. 손가락을 따라가야 하므로 ramp를 쓰지 않고 곧바로 넣는다.
    ///
    /// **첫 호출이 기준점을 잡는다.** `MagnifyGesture`에는 시작 callback이 없고,
    /// `magnification`은 gesture 시작 시점 대비 배수라 기준점이 딱 그 순간의 배율이다.
    /// `endPinch`가 지우므로 다음 gesture는 새 기준점에서 시작한다.
    func updatePinch(magnification: CGFloat) {
        guard role == .mirror else { return }
        let baseline = pinchBaseline ?? logicalZoom
        pinchBaseline = baseline
        apply(logical: baseline * magnification, ramps: false)
    }

    /// pinch 끝. 다음 gesture는 지금 배율에서 새로 시작한다.
    func endPinch() { pinchBaseline = nil }

    /// 화면 표시와 기기 값을 **함께** 옮긴다. 둘이 어긋나면 UI가 거짓말을 한다.
    private func apply(logical: CGFloat, ramps: Bool) {
        let clamped = zoomCapability.clampedLogical(logical)
        let factor = zoomCapability.deviceFactor(forLogical: clamped)
        logicalZoom = clamped
        sessionQueue.async { [self] in setDeviceZoom(factor, ramps: ramps) }
    }

    /// 세션 큐에서만 기기를 만진다. 실패해도 카메라를 죽이지 않는다.
    private nonisolated func setDeviceZoom(_ factor: CGFloat, ramps: Bool) {
        guard let device = (session.inputs.compactMap { $0 as? AVCaptureDeviceInput }).first?.device,
              (try? device.lockForConfiguration()) != nil
        else { return }
        defer { device.unlockForConfiguration() }

        let safe = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        if ramps {
            device.ramp(toVideoZoomFactor: safe, withRate: Self.zoomRampRate)
        } else {
            // 손가락을 따라가는 중이다. 진행 중이던 ramp가 있으면 멈추고 바로 놓는다.
            device.cancelVideoZoomRamp()
            device.videoZoomFactor = safe
        }
    }

    /// 세션 큐가 읽어 둔 배율 범위를 화면 상태로 옮긴다.
    /// **카메라가 바뀔 때마다 부른다** — 전면으로 가면 0.5x 버튼이 사라져야 한다.
    private func adoptActiveCapability() {
        zoomCapability = activeCapability
        sourceAspectRatio = activeSourceAspect
        pinchBaseline = nil
        // 새 카메라의 범위 밖이면 잘라 넣는다. 1x는 언제나 범위 안이다.
        logicalZoom = zoomCapability.clampedLogical(1)
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
