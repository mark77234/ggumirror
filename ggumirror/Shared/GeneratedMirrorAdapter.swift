//
//  GeneratedMirrorAdapter.swift
//  ggumirror
//
//  AI가 그려 준 그림을 **거울 규격으로 찍어 내린다.**
//
//  모델은 확률적이다. "1080 × 2340으로 그려라", "가운데를 #00FF00으로 칠해라"를
//  매번 정확히 지키지 않는다. 그래서 **AI가 만든 것을 믿지 않는다** —
//  크기도, 투명도도, 초록색도.
//
//  대신 여기서 결정적으로 정한다:
//
//      AI 그림
//      → 방향 펴기 · 1080 × 2340으로 맞추기
//      → 카메라 자리를 #00FF00으로 **강제로 칠하기**
//      → Phase C 규격(`MirrorImportNormalizer`)
//      → 카메라 자리 투명
//
//  마지막 줄이 중요하다. Phase D는 Phase C를 **우회하지 않는다** —
//  바깥에서 가져온 거울과 AI가 만든 거울이 같은 문을 지나야
//  한쪽만 조용히 규격이 어긋나는 일이 없다.
//

import CoreGraphics
import Foundation
import ImageIO

nonisolated enum GeneratedMirrorAdapter {

    /// AI 결과 PNG → 거울로 쓸 수 있는 그림.
    static func prepare(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw MirrorImportFailure.unreadable
        }
        // 방향을 펴고, 큰 그림은 줄여서 받는다.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(
                ExternalMirrorImportContract.canvasSize.height
            ),
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else {
            throw MirrorImportFailure.unreadable
        }
        return try prepare(image: decoded)
    }

    /// 이미 메모리에 있는 그림을 규격으로 찍는다.
    static func prepare(image: CGImage) throws -> CGImage {
        let stamped = try stamped(image)
        // **Phase C를 그대로 지난다.** AI 전용 지우개를 만들지 않는다.
        return try MirrorImportNormalizer.normalize(image: stamped)
    }

    // MARK: - 내부

    /// 캔버스에 맞춰 놓고 카메라 자리를 표시색으로 칠한다.
    ///
    /// 비율이 다르면 **늘리지 않는다.** 가운데를 기준으로 채워 자른다 —
    /// 늘리면 사람이 그린 선이 뭉개지고, 무엇보다 거울 테두리가 휘어 보인다.
    static func stamped(_ image: CGImage) throws -> CGImage {
        let size = ExternalMirrorImportContract.canvasSize
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw MirrorImportFailure.unreadable }

        context.interpolationQuality = .high
        context.clear(CGRect(origin: .zero, size: size))
        context.draw(image, in: aspectFilled(source: image, into: size))

        // **카메라 자리를 덮어 칠한다.** AI가 거기 무엇을 그렸든 상관없다 —
        // 규격은 우리가 정하고, 다음 단계가 이 색을 보고 자리를 비운다.
        let chroma = ExternalMirrorImportContract.chroma
        context.setFillColor(
            red: CGFloat(chroma.r) / 255, green: CGFloat(chroma.g) / 255,
            blue: CGFloat(chroma.b) / 255, alpha: 1
        )
        context.fill(openingRect(in: size))

        guard let output = context.makeImage() else { throw MirrorImportFailure.unreadable }
        return output
    }

    /// 짧은 쪽을 기준으로 키워 캔버스를 덮는다. 넘치는 쪽은 가운데를 남기고 잘린다.
    static func aspectFilled(source: CGImage, into size: CGSize) -> CGRect {
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        guard width > 0, height > 0 else { return CGRect(origin: .zero, size: size) }

        let scale = max(size.width / width, size.height / height)
        let scaled = CGSize(width: width * scale, height: height * scale)
        return CGRect(
            x: (size.width - scaled.width) / 2,
            y: (size.height - scaled.height) / 2,
            width: scaled.width, height: scaled.height
        )
    }

    /// 카메라 자리. **좌표를 여기서 새로 계산하지 않는다** — 규격이 정한 것을 읽는다.
    ///
    /// bitmap context는 아래가 0이고 규격의 `y`는 위에서부터라 뒤집어 준다.
    /// 위 180 / 아래 220으로 두께가 달라 뒤집지 않으면 40px 어긋난다.
    static func openingRect(in size: CGSize) -> CGRect {
        let rect = ExternalMirrorImportContract.cameraOpening
        let top = rect.y * size.height
        let height = rect.height * size.height
        return CGRect(
            x: rect.x * size.width,
            y: size.height - top - height,
            width: rect.width * size.width,
            height: height
        )
    }
}
