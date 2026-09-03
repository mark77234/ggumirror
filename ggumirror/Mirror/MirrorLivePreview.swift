//
//  MirrorLivePreview.swift
//  ggumirror
//
//  `내 거울로 미리보기` — 받기 전에, 진짜 카메라 위에 얹어 본다.
//
//  **경제 동작이 아니다.** 소유권 · 다운로드 수 · 조각 · 내 거울 저장 어느 것도
//  건드리지 않는다. 로그인하지 않아도 볼 수 있다.
//

import SwiftUI

/// 카메라 위에 무엇을 얹을 것인가.
///
/// 내장 템플릿은 모델을 그대로 갖고 있어 **그리면 되고**, 사용자 상품은 모델을
/// 내려받을 권한이 없어 **이미 공개된 미리보기 그림**을 쓴다. 상품을 사기 전에
/// 원본 manifest나 asset을 받아 오지 않는다 — 목적은 "얹으면 이렇다"를 보는 것이지
/// 상품을 손에 넣는 것이 아니다.
enum MirrorPreviewSubject: Equatable {
    /// 내장 템플릿. 실제 거울과 **같은 renderer**를 지난다.
    case design(MirrorDesign)
    /// 카메라 자리를 도려낸 납작한 PNG. 장식만 남고 그 아래로 카메라가 비친다.
    case overlay(Data)

    /// 공개 미리보기 PNG에서 만든다. 도려낼 수 없으면 `nil` — 그때는 열지 않는다.
    ///
    /// 카메라 자리까지 칠해진 그림을 그대로 얹으면 **자기 얼굴이 안 보이는**
    /// 미리보기가 된다. 그건 미리보기가 아니라 카드 확대다.
    static func overlay(fromListingPreview png: Data) -> MirrorPreviewSubject? {
        MirrorThumbnailNormalizer.cameraOpeningRemoved(png: png).map { .overlay($0) }
    }
}

extension MirrorDesign {
    /// 내장 템플릿 한 장. `MirrorLibrary.acquire`와 **같은 조립**이라
    /// 미리보기와 실제로 받은 거울이 다르게 보일 수 없다.
    init(template: MirrorTemplate) {
        self.init(mirror: MyMirror(
            id: template.id,
            name: template.name,
            origin: template.isBasic ? .basic : .purchased,
            style: template.style,
            importedArtworks: StoreArtworkLibrary.artworks(for: template)
        ))
    }
}

/// 전체 화면 미리보기. 카메라 + 장식 + 닫기뿐이다.
///
/// 촬영 · 전환 · 배율 · 플래시가 없다 — role이 `.viewfinder`라 **구조적으로** 없다.
/// 이 화면에서 사진이 나가거나 무언가 저장될 길이 아예 없다.
struct MirrorLivePreviewView: View {
    let subject: MirrorPreviewSubject
    let title: String
    var onClose: () -> Void

    @State private var camera = MirrorCamera()
    @Environment(\.scenePhase) private var scenePhase

    /// 자르는 방법. **이 미리보기 하나 동안만 산다.**
    ///
    /// `camera.setFrontFraming(_:)`을 부르지 않는다 — 그것은 실제 거울 화면의
    /// 사용자 설정이다. 상점에서 `채우기`를 골랐다고 홈 거울까지 따라 바뀌면 안 된다.
    /// authority는 그대로 `MirrorCamera.Framing`이고, 여기서는 어느 값을 쓸지만 고른다.
    @State private var framing = MirrorCamera.Framing.initial

    /// 납작한 overlay를 **한 번만** 풀어 둔다.
    ///
    /// 자르는 방법을 바꿀 때마다 1.66MB PNG를 다시 해독하면 칩이 무거워진다.
    /// 도려내기(`cameraOpeningRemoved`)는 이미 이 화면에 오기 전에 끝났고,
    /// 여기서 다시 돌아가는 일은 없다.
    @State private var overlayImage: UIImage?

    var body: some View {
        ZStack {
            Color.black

            switch camera.status {
            case .ready:
                // 자르는 방법은 **여기 한 layer에만** 걸린다.
                CameraPreviewView(camera: camera, framing: framing)
                    .accessibilityLabel("거울")
            case .denied:
                message("카메라 권한이 필요해요", detail: "설정에서 카메라를 켜면 미리보기를 볼 수 있어요.")
            case .unavailable:
                message("카메라를 사용할 수 없어요", detail: "지금은 카메라를 쓸 수 없어요. 잠시 뒤 다시 시도해 주세요.")
            case .idle:
                EmptyView()
            }

            decoration

            closeButton

            framingSelector
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .task { await camera.start() }
        .task { decodeOverlay() }
        .onChange(of: scenePhase) { _, phase in
            // 미리보기를 열어 둔 채 앱을 떠나면 카메라를 놓는다.
            if phase == .active { Task { await camera.start() } }
            if phase == .background { camera.stop() }
        }
    }

    @ViewBuilder
    private var decoration: some View {
        // 카메라가 없을 때 장식만 떠 있으면 무엇을 보는 건지 알 수 없다.
        if case .ready = camera.status {
            switch subject {
            case .design(let design):
                MirrorDecorationView(design: design)
            case .overlay:
                // 자르는 방법을 바꿔도 이 그림은 **다시 만들지 않는다.**
                if let image = overlayImage {
                    Image(uiImage: image)
                        .resizable()
                        // 실제 거울 장식(`.aspectFilled`)과 같은 규칙으로 놓는다.
                        .aspectRatio(contentMode: .fill)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// 거울 가운데를 가리지 않게 아래 safe area 안에 둔다 —
    /// 실제 거울에서 칩이 앉는 자리와 같은 규칙이다.
    @ViewBuilder
    private var framingSelector: some View {
        if case .ready = camera.status {
            VStack {
                Spacer()
                MirrorFramingSelector(
                    options: MirrorCamera.Framing.allCases, selected: framing
                ) { framing = $0 }
            }
            .padding(.bottom, 44)
        }
    }

    /// 얹을 그림이 있으면 한 번 풀어 둔다. 없으면 할 일이 없다(내장 템플릿).
    private func decodeOverlay() {
        guard case .overlay(let png) = subject, overlayImage == nil else { return }
        overlayImage = UIImage(data: png)
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Text("닫기")
                        .font(InkFont.body)
                        .foregroundStyle(PaperTheme.ink)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .frame(minWidth: InkTapTarget.minimum, minHeight: InkTapTarget.minimum)
                        .background {
                            UnevenRoundedRectangle.ink(18, 21, 20, 17)
                                .fill(PaperTheme.paper)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())
                .accessibilityLabel("\(title) 미리보기 닫기")
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Text(title).font(InkFont.cardTitle)
            Text(detail)
                .font(InkFont.secondary)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}

extension View {
    /// `내 거울로 미리보기`를 여는 **한 곳**. 내장 템플릿과 사용자 상품이 같은 화면을 쓴다.
    ///
    /// `fullScreenCover`인 이유: 거울은 화면 전체 좌표(1080 × 2340)로 그려진다.
    /// 시트 안에 넣으면 장식과 카메라가 실제 거울과 다른 자리에 놓인다.
    func mirrorLivePreview(
        _ subject: Binding<MirrorPreviewSubject?>, title: String
    ) -> some View {
        fullScreenCover(isPresented: Binding(
            get: { subject.wrappedValue != nil },
            set: { if !$0 { subject.wrappedValue = nil } }
        )) {
            if let value = subject.wrappedValue {
                MirrorLivePreviewView(subject: value, title: title) {
                    subject.wrappedValue = nil
                }
            }
        }
    }
}
