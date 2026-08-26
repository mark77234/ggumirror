//
//  MirrorImportAssistantView.swift
//  ggumirror
//
//  고칠 수 있는 실패를 **앱 안에서** 고치는 자리.
//
//  창을 겹쳐 띄우지 않는다 — 상태 하나가 바뀌고 같은 자리에서 화면만 달라진다.
//  판정은 언제나 `MirrorImportNormalizer`가 하고, 이 파일은 무엇을 보여 줄지만 정한다.
//

import SwiftUI

struct MirrorImportAssistantView: View {
    let source: Data
    let onUse: (CGImage) -> Void

    @State private var assistant = MirrorImportAssistant()
    @Environment(\.inkModalDismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            switch assistant.step {
            case .checking:
                working("거울 이미지를 준비하고 있어요…")
            case .crop:
                if let image = assistant.working {
                    MirrorImportCropEditor(image: image, isBusy: assistant.isWorking) { window in
                        Task { await assistant.applyCrop(window: window) }
                    } onCancel: {
                        dismiss()
                    }
                }
            case .openingRepair(let failure):
                repair(failure)
            case .preview:
                finalPreview
            case .failed(let failure):
                failed(failure)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .task { await assistant.begin(data: source) }
    }

    // MARK: - 상태별 화면

    private func working(_ label: String) -> some View {
        VStack(spacing: 12) {
            ProgressView().tint(PaperTheme.ink)
            Text(label)
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    /// 가운데를 거울로 지정할지 묻는다. **승인 전에는 아무 픽셀도 건드리지 않는다.**
    @ViewBuilder
    private func repair(_ failure: MirrorImportFailure) -> some View {
        VStack(spacing: 14) {
            Text(failure.remedyTitle ?? "")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)
                .multilineTextAlignment(.center)

            if let detail = failure.remedyDetail {
                Text(detail)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // **어디가 거울이 될지 실제로 보여 준다.** 말로만 설명하지 않는다.
            if let image = assistant.working {
                MirrorOpeningPreview(image: image)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 320)
            }

            if assistant.isWorking {
                ProgressView().tint(PaperTheme.ink)
            } else {
                primary(failure.remedyActionTitle ?? "가운데를 거울 영역으로 만들기") {
                    Task { await assistant.repairOpening() }
                }
                secondary("취소") { dismiss() }
            }
        }
    }

    /// 마지막 확인. **여기 보이는 그림이 곧 저장될 그림이다.**
    @ViewBuilder
    private var finalPreview: some View {
        VStack(spacing: 14) {
            Text("이렇게 거울로 등록돼요")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)

            if let image = assistant.normalized {
                // 실제 거울 화면과 같은 방식으로 그린다 — 카메라가 보일 자리가
                // 비어 있는 것이 한눈에 보인다.
                MirrorPreview(
                    style: MirrorLibrary.defaultMirror.style,
                    importedArtworks: [
                        ImportedArtworkObject(
                            assetID: ImportedArtworkAssetStore.shared.register(image)
                        )
                    ],
                    lineWidth: 2.1
                )
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360)
            }

            primary("이대로 등록") {
                guard let image = assistant.normalized else { return }
                onUse(image)
                dismiss()
            }
            secondary("다시 수정") { Task { await assistant.startOver() } }
        }
    }

    @ViewBuilder
    private func failed(_ failure: MirrorImportFailure) -> some View {
        VStack(spacing: 12) {
            Text("거울로 만들지 못했어요")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)
            Text(failure.message)
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            secondary("확인") { dismiss() }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 버튼

    private func primary(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .font(InkFont.body.weight(.semibold))
                .foregroundStyle(PaperTheme.subtleSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .frame(minHeight: InkTapTarget.minimum)
                .background { UnevenRoundedRectangle.ink(18, 22, 23, 17).fill(PaperTheme.ink) }
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        // 무거운 일이 도는 동안 두 번 눌러 두 번 처리하지 않는다.
        .disabled(assistant.isWorking)
    }

    private func secondary(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .frame(minHeight: InkTapTarget.minimum)
                .background {
                    UnevenRoundedRectangle.ink(18, 22, 23, 17)
                        .stroke(PaperTheme.ink, lineWidth: 1.6)
                }
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .disabled(assistant.isWorking)
    }
}

/// 그림 위에 **규격 카메라 자리**를 그대로 겹쳐 보여 준다.
///
/// 좌표는 규격에서 온다 — 여기서 숫자를 다시 적지 않는다.
struct MirrorOpeningPreview: View {
    let image: CGImage

    var body: some View {
        GeometryReader { geometry in
            let box = fitted(in: geometry.size)
            let opening = ExternalMirrorImportContract.cameraOpening

            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: box.width, height: box.height)

                Rectangle()
                    .fill(PaperTheme.ink.opacity(0.28))
                    .frame(
                        width: box.width * opening.width,
                        height: box.height * opening.height
                    )
                    .overlay {
                        Rectangle().strokeBorder(PaperTheme.subtleSurface, lineWidth: 2)
                    }
                    .offset(
                        x: box.width * opening.x,
                        y: box.height * opening.y
                    )
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .aspectRatio(ExternalMirrorImportContract.aspectRatio, contentMode: .fit)
    }

    private func fitted(in size: CGSize) -> CGSize {
        let ratio = ExternalMirrorImportContract.aspectRatio
        var width = size.width
        var height = width / ratio
        if height > size.height {
            height = size.height
            width = height * ratio
        }
        return CGSize(width: width, height: height)
    }
}
