//
//  ExternalArtworkGuide.swift
//  ggumirror
//
//  외부 그림 앱으로 나가는 작업 가이드와, 돌아온 PNG를 받는 검사.
//
//  가이드는 최종 결과물이 아니라 **밑에 깔고 그리는 참고선**이다.
//  그래서 배경을 채우지 않는다 — 그림 앱에서 레이어로 얹어 쓸 수 있어야 한다.
//
//  가이드의 거울 규격은 실제 거울과 같은 곳(MirrorFrameInsets / MirrorGeometry)에서 온다.
//  여기에 108 / 180 / 220 같은 숫자를 다시 적지 않는다.
//

import CoreGraphics
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 작업 가이드

enum MirrorArtworkGuide {
    /// 가이드도 결과물도 같은 Master Canvas 크기다.
    static var size: CGSize { MirrorCanvas.size }

    static let fileName = "꾸미러-작업-가이드.png"

    /// 투명 배경 위에 거울 외곽선 + 카메라 영역 점선만 그린다.
    static func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false            // 배경은 비워 둔다

        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            let bounds = CGRect(origin: .zero, size: size)
            let insets = MirrorFrameInsets.standard

            context.setStrokeColor(UIColor(PaperTheme.ink).withAlphaComponent(0.5).cgColor)
            context.setLineWidth(4)
            context.stroke(bounds.insetBy(dx: 2, dy: 2))

            // 실제 거울에서 카메라가 보이는 영역. 같은 rounded geometry를 쓴다.
            context.setLineWidth(3)
            context.setLineDash(phase: 0, lengths: [24, 18])
            context.addPath(insets.mirrorAreaPath(in: bounds).cgPath)
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
        }
    }

    /// 공유용 임시 파일. 사용자 콘텐츠가 아니라 매번 새로 만드는 참고 자료라
    /// Application Support(persistence)에 넣지 않는다.
    static func exportPNG() throws -> URL {
        guard let data = makeImage().pngData() else { throw ArtworkImportError.unreadable }
        let url = FileManager.default.temporaryDirectory.appending(path: fileName)
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - 가져오기

enum ArtworkImportError: Error, Equatable {
    /// 이미지를 읽지 못했다.
    case unreadable
    /// 작업 가이드와 비율이 다르다. 늘려서 왜곡시키지 않고 사용자에게 묻는다.
    case wrongAspectRatio(width: Int, height: Int)
}

enum MirrorArtworkImporter {
    /// 9 : 19.5. 소수점 반올림을 감안해 아주 좁은 허용치만 둔다.
    static let aspectTolerance = 0.005

    /// 가져온 PNG를 Master Canvas 크기로 정규화한다.
    /// - 정확히 1080 × 2340이면 그대로 쓴다.
    /// - 비율이 같고 더 크면 고품질로 줄인다.
    /// - 비율이 다르면 던진다. 조용히 늘려 왜곡시키지 않는다.
    static func normalize(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ArtworkImportError.unreadable
        }
        // EXIF 회전을 반영해 실제 픽셀 방향으로 편다. 큰 원본을 통째로 올리지 않는다.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(MirrorCanvas.size.height)
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ArtworkImportError.unreadable
        }

        let ratio = Double(decoded.width) / Double(max(decoded.height, 1))
        let expected = MirrorCanvas.size.width / MirrorCanvas.size.height
        guard abs(ratio - expected) <= aspectTolerance else {
            throw ArtworkImportError.wrongAspectRatio(width: decoded.width, height: decoded.height)
        }

        let target = MirrorCanvas.size
        guard decoded.width != Int(target.width) || decoded.height != Int(target.height) else {
            return decoded          // 정확히 맞으면 다시 그리지 않는다
        }
        return resized(decoded, to: target) ?? decoded
    }

    /// 카메라 영역이 거의 다 불투명한지. 막지는 않고 경고만 하기 위한 판단이다.
    /// 사용자가 일부러 카메라를 가리는 디자인을 만들 수도 있다.
    static func coversCamera(_ image: CGImage) -> Bool {
        // 작게 줄여 세어도 "대부분 불투명한가"를 판단하는 데는 충분하다.
        let width = 54, height = 117
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let area = MirrorFrameInsets.standard.mirrorArea
        var total = 0, opaque = 0
        for row in 0..<height {
            // CGContext는 아래가 0이라 뒤집어 본다.
            let y = Double(height - 1 - row) / Double(height)
            guard y >= area.y, y <= area.y + area.height else { continue }
            for column in 0..<width {
                let x = Double(column) / Double(width)
                guard x >= area.x, x <= area.x + area.width else { continue }
                total += 1
                if pixels[(row * width + column) * 4 + 3] > 200 { opaque += 1 }
            }
        }
        guard total > 0 else { return false }
        return Double(opaque) / Double(total) > 0.9
    }

    private static func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.clear(CGRect(origin: .zero, size: size))
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}
