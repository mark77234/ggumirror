//
//  ExternalMirrorImport.swift
//  ggumirror
//
//  **바깥에서 만든 거울을 받아들이는 규격 하나.**
//
//  Figma · Canva · Photoshop에서 만들든, 나중에 AI가 만들든 같은 규격을 쓴다.
//  그래서 값이 여기 한 곳에 있다 — 화면마다 비율과 좌표를 다시 적으면
//  하나만 고쳐도 나머지가 조용히 어긋난다.
//
//  숫자를 **여기서 새로 정하지 않는다.** 비율은 `MirrorCanvas`, 카메라 자리는
//  `MirrorFrameInsets.standard`가 정한 것을 그대로 읽는다. 실제 거울과 제작
//  규격이 갈라질 수 없는 이유가 그것이다.
//

import CoreGraphics
import Foundation

nonisolated enum ExternalMirrorImportContract {
    // MARK: - 캔버스

    /// 작업 크기. 실제 거울과 같은 Master Canvas다.
    static var canvasSize: CGSize { MirrorCanvas.size }

    /// 가로 ÷ 세로. 9 : 19.5쯤이다.
    static var aspectRatio: CGFloat { MirrorCanvas.aspectRatio }

    /// 사람에게 보여 줄 비율 표기.
    static let aspectRatioLabel = "9 : 19.5"

    /// 권장 크기. 이 크기로 만들면 줄이거나 늘리지 않는다.
    static var recommendedPixelSize: CGSize { canvasSize }

    /// 더 크게 작업해도 된다. 비율만 같으면 앱이 고품질로 줄인다.
    static var highResolutionPixelSize: CGSize {
        CGSize(width: canvasSize.width * 2, height: canvasSize.height * 2)
    }

    // MARK: - 카메라 자리

    /// 카메라가 보일 자리. **0...1 좌표**라 어떤 해상도로 작업해도 같다.
    static var cameraOpening: NormalizedRect { MirrorFrameInsets.standard.mirrorArea }

    /// 권장 크기에서의 픽셀 좌표. 가이드 문서가 쓴다.
    static var cameraOpeningPixels: CGRect {
        let size = recommendedPixelSize
        let rect = cameraOpening
        return CGRect(
            x: rect.x * size.width, y: rect.y * size.height,
            width: rect.width * size.width, height: rect.height * size.height
        )
    }

    // MARK: - 표시 색

    /// 카메라 자리를 칠하는 색. **순수 초록**이라 사람이 손으로 찍기 쉽고
    /// 사진이나 그림에 우연히 정확히 이 값이 나오는 일이 드물다.
    static let chroma: (r: UInt8, g: UInt8, b: UInt8) = (0, 255, 0)
    static let chromaHex = "#00FF00"

    /// JPEG처럼 압축을 거치면 정확한 값이 유지되지 않는다. 그래서 조금 봐준다.
    /// **넓게 잡지 않는다** — 넓히면 연두색 장식까지 초록으로 본다.
    static let chromaTolerance = 40

    static func isChroma(r: UInt8, g: UInt8, b: UInt8) -> Bool {
        Int(r) <= chromaTolerance
            && Int(g) >= 255 - chromaTolerance
            && Int(b) <= chromaTolerance
    }

    // MARK: - 파일

    static let recommendedFormat = "PNG"
    static let acceptedFormats = ["PNG", "JPEG", "HEIC"]
}

/// 가져오기 결과. **실패는 조용하지 않다** — 무엇이 잘못됐는지 말한다.
nonisolated enum MirrorImportFailure: Error, Equatable {
    /// 이미지를 읽지 못했다.
    case unreadable
    /// 비율이 다르다. 늘려서 왜곡시키지 않는다.
    case wrongAspectRatio(width: Int, height: Int)
    /// 카메라 자리를 확인하지 못했다. **그림을 함부로 지우지 않는다.**
    ///
    /// 투명하거나 초록인 흔적은 있는데 규격을 만족하지 못한 경우다 —
    /// 다른 도구로 만들었거나 초록이 우리 값과 다를 때 여기로 온다.
    case cameraOpeningNotMarked
    /// 투명한 곳이 **한 곳도 없다.** 보통의 사진이다.
    ///
    /// `cameraOpeningNotMarked`와 나눠 둔 이유: 두 경우에 할 말이 다르다.
    /// 사진에게 "초록이 규격과 다르다"고 하면 무슨 소리인지 알 수 없고,
    /// 규격을 맞추려던 사람에게 "카메라 자리가 없다"고 하면 틀린 말이다.
    case fullyOpaque
    /// 지우고 나니 거울이 거의 남지 않았다. 규격이 어긋난 그림이다.
    case nothingLeftAfterRemoval

    /// 사용자가 고칠 수 있는 실패인가. **화면이 문자열을 보고 판단하지 않는다.**
    var remedy: MirrorImportRemedy? {
        switch self {
        case .wrongAspectRatio: .crop
        // 둘 다 "가운데를 거울로 지정"으로 고칠 수 있다. 안내 문구만 다르다.
        case .fullyOpaque, .cameraOpeningNotMarked: .openingRepair
        // 규격이 근본적으로 어긋났거나 읽지 못한 것이다. 물어볼 것이 없다.
        case .nothingLeftAfterRemoval, .unreadable: nil
        }
    }

    var message: String {
        switch self {
        case .unreadable:
            "이미지를 읽지 못했어요."
        case .wrongAspectRatio(let width, let height):
            "\(ExternalMirrorImportContract.aspectRatioLabel) 비율로 만들어 주세요. "
                + "가져온 그림은 \(width) × \(height)예요."
        case .cameraOpeningNotMarked:
            "카메라가 보일 자리를 찾지 못했어요. "
                + "그 부분을 \(ExternalMirrorImportContract.chromaHex) 초록색으로 "
                + "채웠는지 제작 가이드를 확인해 주세요."
        case .fullyOpaque:
            "이 이미지에는 카메라가 보일 공간이 없어요."
        case .nothingLeftAfterRemoval:
            "거울 테두리가 남지 않았어요. 제작 가이드의 크기와 위치를 확인해 주세요."
        }
    }
}


/// 실패를 사용자가 고칠 수 있는 방법.
nonisolated enum MirrorImportRemedy: Equatable {
    /// 비율이 다르다 — 잘라내면 된다.
    case crop
    /// 카메라 자리를 못 찾았다 — 가운데를 거울로 **지정하면** 된다.
    case openingRepair
}
