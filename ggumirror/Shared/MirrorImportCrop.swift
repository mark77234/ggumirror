//
//  MirrorImportCrop.swift
//  ggumirror
//
//  비율이 맞지 않는 그림을 **잘라서** 규격 비율로 만든다.
//
//  늘리지 않는다. 늘리면 얼굴도 선도 뭉개지고, 그건 사용자가 고른 그림이 아니다.
//  잘라낼 자리는 사용자가 정한다 — 어디를 버릴지는 우리가 정할 일이 아니다.
//
//  **여기서 규격 검사를 하지 않는다.** 자른 결과는 반드시 `MirrorImportNormalizer`를
//  다시 지난다. 두 번째 판정 기준을 만들지 않는다.
//

import CoreGraphics

nonisolated enum MirrorImportCrop {

    /// 잘라낼 창의 비율. **규격에서 그대로 온다** — 여기서 숫자를 다시 적지 않는다.
    static var aspectRatio: CGFloat { ExternalMirrorImportContract.aspectRatio }

    /// 이 그림에 이미 규격 비율이면 자를 필요가 없다.
    static func needsCrop(_ image: CGImage) -> Bool {
        let ratio = Double(image.width) / Double(max(image.height, 1))
        return abs(ratio - Double(aspectRatio)) > MirrorArtworkImporter.aspectTolerance
    }

    /// 그림을 창에 **꽉 채우려면** 최소 몇 배로 키워야 하는가.
    ///
    /// 이 값보다 작게 두면 창 안에 빈 자리가 생긴다 — 저장하면 거울에 구멍이 난다.
    /// 그래서 화면의 zoom 하한이 곧 이 값이다.
    static func minimumScale(imageSize: CGSize, windowSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return max(windowSize.width / imageSize.width, windowSize.height / imageSize.height)
    }

    /// 창을 그림 좌표계 안에 가둔다. **창이 그림 밖으로 나가지 않는다.**
    ///
    /// 손가락을 아무리 끌어도 빈 자리가 생기지 않는 이유다.
    static func clamped(
        window: CGRect, imageSize: CGSize
    ) -> CGRect {
        var rect = window
        rect.origin.x = min(max(0, rect.origin.x), max(0, imageSize.width - rect.width))
        rect.origin.y = min(max(0, rect.origin.y), max(0, imageSize.height - rect.height))
        return rect
    }

    /// 그림 좌표계의 창 하나를 잘라낸다.
    ///
    /// 창은 이미 규격 비율이어야 한다(화면이 그렇게만 만든다). 크기를 여기서
    /// 규격 픽셀로 맞추지 않는다 — 그건 normalizer가 한다.
    static func cropped(_ image: CGImage, to window: CGRect) throws -> CGImage {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = window.integral.intersection(bounds)
        guard rect.width >= 1, rect.height >= 1, let output = image.cropping(to: rect) else {
            throw MirrorImportFailure.unreadable
        }
        return output
    }

    /// 그림 한가운데에서 규격 비율로 잡은 창. 사용자가 손대기 전의 시작 자리다.
    static func centeredWindow(imageSize: CGSize) -> CGRect {
        let ratio = aspectRatio
        var width = imageSize.width
        var height = width / ratio
        if height > imageSize.height {
            height = imageSize.height
            width = height * ratio
        }
        return CGRect(
            x: (imageSize.width - width) / 2,
            y: (imageSize.height - height) / 2,
            width: width, height: height
        )
    }
}
