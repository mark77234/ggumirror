//
//  MirrorImportAssistant.swift
//  ggumirror
//
//  실패를 **막다른 길로 두지 않는다.**
//
//  예전에는 규격에 맞지 않는 그림을 고르면 "이렇게 만들어 주세요"라는 문구
//  하나로 끝났다. 사용자가 할 수 있는 일이 앱 밖에 있었다 — 다른 도구로 다시
//  만들어 오라는 뜻이다. 대부분은 거기서 그만둔다.
//
//  이제 고칠 수 있는 실패는 **앱 안에서 고친다.** 다만 고치는 방법은 하나뿐이고
//  (`MirrorImportNormalizer`), 이 파일은 무엇을 물어볼지와 어떤 순서로 물어볼지만
//  정한다. 두 번째 판정 기준을 만들지 않는다.
//
//  창을 겹쳐 띄우지 않는다. 상태 하나가 바뀌고 같은 자리에서 화면만 달라진다.
//

import CoreGraphics
import Foundation

@MainActor
@Observable
final class MirrorImportAssistant {

    /// 지금 무엇을 하고 있는가. **한 번에 하나다.**
    enum Step: Equatable {
        /// 그림을 보고 있다. 오래 걸릴 수 있다.
        case checking
        /// 비율이 맞지 않는다. 사용자가 잘라야 한다.
        case crop
        /// 카메라 자리를 못 찾았다. 가운데를 거울로 지정할지 묻는다.
        case openingRepair(MirrorImportFailure)
        /// 이대로 등록할지 마지막으로 보여 준다.
        case preview
        /// 고칠 수 없는 실패다.
        case failed(MirrorImportFailure)
    }

    private(set) var step: Step = .checking
    /// 지금 다루고 있는 **작업용 사본**. 사용자의 사진 원본이 아니다.
    private(set) var working: CGImage?
    /// 최종 미리보기이자 저장될 그림. **미리보기와 저장 결과가 같다.**
    private(set) var normalized: CGImage?
    /// 무거운 일을 하는 중인가. CTA를 잠그는 데 쓴다.
    private(set) var isWorking = false

    /// 잘라내기 전의 그림. `뒤로`가 여기로 돌아온다.
    private var original: CGImage?
    /// 마지막으로 확정한 잘라내기 창(원본 픽셀 좌표). `뒤로`가 이 자리에서 다시 시작한다 —
    /// 처음부터 자리를 다시 잡게 하지 않는다.
    private(set) var lastCropWindow: CGRect?

    // MARK: - 진입

    /// 고른 그림 하나로 시작한다.
    func begin(data: Data) async {
        step = .checking
        isWorking = true
        defer { isWorking = false }

        // 큰 사진을 펴는 일이다. **main thread에서 하지 않는다.**
        let decoded = await Task.detached(priority: .userInitiated) {
            MirrorImportNormalizer.decode(data)
        }.value
        guard let decoded else {
            step = .failed(.unreadable)
            return
        }
        original = decoded
        working = decoded
        await evaluate(decoded)
    }

    // MARK: - 사용자 결정

    /// 사용자가 자를 자리를 정했다.
    func applyCrop(window: CGRect) async {
        guard let source = working else { return }
        isWorking = true
        defer { isWorking = false }

        let cropped = await Task.detached(priority: .userInitiated) {
            try? MirrorImportCrop.cropped(source, to: window)
        }.value
        guard let cropped else {
            step = .failed(.unreadable)
            return
        }
        working = cropped
        lastCropWindow = window
        await evaluate(cropped)
    }

    /// 사용자가 "가운데를 거울 영역으로" 승인했다.
    ///
    /// **여기서만 지운다.** 승인 전에는 어떤 픽셀도 건드리지 않는다.
    func repairOpening() async {
        guard let source = working else { return }
        isWorking = true
        defer { isWorking = false }

        let repaired = await Task.detached(priority: .userInitiated) {
            try? MirrorImportNormalizer.clearingCameraOpening(source)
        }.value
        guard let repaired else {
            step = .failed(.unreadable)
            return
        }
        working = repaired
        await evaluate(repaired)
    }

    /// `뒤로`. 최종 미리보기에서 **자르기 단계로** 돌아간다.
    ///
    /// 흐름을 끝내지도, 사진을 다시 고르게 하지도 않는다. 지금 다루던 그림
    /// 그대로 자를 자리만 다시 잡는다.
    ///
    /// **정규화된 그림을 다시 자르지 않는다.** 자르기는 언제나 `original`에서
    /// 시작한다 — 자른 것 위에 또 자르면 사용자가 고른 그림이 두 번 줄어든다.
    /// 지운 것(opening repair)도 함께 버린다. 새 자르기 결과는 새 판정을
    /// 받아야 하고, 지난 판정을 물려받으면 안 된다.
    func backToCrop() {
        guard let original else { return }
        working = original
        normalized = nil
        step = .crop
    }

    // MARK: - 판정

    /// **판정은 언제나 `MirrorImportNormalizer`가 한다.**
    ///
    /// 미리보기로 갈 때도 여기를 지나므로, 화면에 보이는 그림이 곧 저장될 그림이다.
    private func evaluate(_ image: CGImage) async {
        let outcome = await Task.detached(priority: .userInitiated) {
            Result { try MirrorImportNormalizer.normalize(image: image) }
        }.value

        switch outcome {
        case .success(let result):
            normalized = result
            step = .preview
        case .failure(let error):
            let failure = (error as? MirrorImportFailure) ?? .unreadable
            switch failure.remedy {
            case .crop:
                step = .crop
            case .openingRepair:
                step = .openingRepair(failure)
            case nil:
                step = .failed(failure)
            }
        }
    }
}

// MARK: - 안내 문구

nonisolated extension MirrorImportFailure {
    /// 고칠 수 있는 실패에 보여 줄 제목. **실패마다 할 말이 다르다.**
    var remedyTitle: String? {
        switch self {
        case .wrongAspectRatio: "이 이미지는 거울 비율과 맞지 않아요."
        case .fullyOpaque: "이 이미지에는 카메라가 보일 공간이 없어요."
        case .cameraOpeningNotMarked: "거울 영역을 정확히 찾지 못했어요."
        case .nothingLeftAfterRemoval, .unreadable: nil
        }
    }

    var remedyDetail: String? {
        switch self {
        case .wrongAspectRatio: "꾸미러에 맞게 잘라볼까요?"
        case .fullyOpaque: "가운데 영역을 거울 화면으로 만들 수 있어요."
        case .cameraOpeningNotMarked:
            "이미지의 표시 방식이 꾸미러 규격과 다른 것 같아요.\n"
                + "가운데 영역을 거울 화면으로 다시 지정할 수 있어요."
        case .nothingLeftAfterRemoval, .unreadable: nil
        }
    }

    /// 고치는 버튼의 문구.
    var remedyActionTitle: String? {
        switch self {
        case .wrongAspectRatio: "이미지 자르기"
        case .fullyOpaque: "가운데를 거울 영역으로 만들기"
        case .cameraOpeningNotMarked: "가운데 영역을 거울 영역으로 지정"
        case .nothingLeftAfterRemoval, .unreadable: nil
        }
    }
}
