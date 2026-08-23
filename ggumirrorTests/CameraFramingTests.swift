//
//  CameraFramingTests.swift
//  ggumirrorTests
//
//  거울 카메라에는 줌이 없다.
//  기본 카메라 앱의 1x 시야를 그대로 보여주고, 화면을 채우려고 잘라내지 않는다.
//
//  화각 자체는 실기기로만 확인할 수 있으므로, 여기서는 그 정책이 코드에 박혀 있는지와
//  **미리보기와 촬영이 같은 규칙을 쓰는지**를 고정한다.
//

import AVFoundation
import Testing
import SwiftUI
import UIKit
@testable import ggumirror

@MainActor
struct CameraFramingTests {

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y),
                                       width: image.width, height: image.height))
        return (data[0], data[1], data[2], data[3])
    }

    /// 카메라 프레임을 흉내 낸 그림. 네 귀퉁이에 색을 박아 잘렸는지 볼 수 있게 한다.
    private func cameraFrame(width: Int, height: Int) -> UIImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let mark = Double(width) * 0.08
        let corners: [(Double, Double, CGColor)] = [
            (0, 0, CGColor(red: 1, green: 0, blue: 0, alpha: 1)),                                  // CG 기준 왼쪽 아래
            (Double(width) - mark, 0, CGColor(red: 0, green: 1, blue: 0, alpha: 1)),
            (0, Double(height) - mark, CGColor(red: 0, green: 0, blue: 1, alpha: 1)),
            (Double(width) - mark, Double(height) - mark, CGColor(red: 1, green: 1, blue: 0, alpha: 1)),
        ]
        for (x, y, color) in corners {
            context.setFillColor(color)
            context.fill(CGRect(x: x, y: y, width: mark, height: mark))
        }
        return UIImage(cgImage: context.makeImage()!)
    }

    // MARK: - 시작 배율

    @Test("거울은 1x로 시작한다")
    func mirrorStartsAtOneX() {
        // 배율은 session 안에서만 산다 — 앱을 다시 켜면 1x다.
        let camera = MirrorCamera(role: .mirror)
        #expect(camera.logicalZoom == 1)
        #expect(!camera.canZoom, "카메라가 붙기 전에는 고를 것이 없다")

        // 카메라가 없으면 고를 배율도 하나뿐이다.
        #expect(camera.zoomPresets == [1])
        #expect(camera.selectedZoomPreset == 1)
    }

    @Test("Camera Area를 꽉 채우는 배치를 그대로 쓴다")
    func previewFillsCameraArea() {
        // 거울 프레임 두께와 Camera Area 크기는 확정값이다.
        // 화각을 넓히겠다고 .resizeAspect로 바꾸면 영상이 작아지고 프레임이 두꺼워 보인다.
        #expect(MirrorCamera.previewGravity == .resizeAspectFill)
    }

    @Test("화각이 가장 넓은 format을 고른다")
    func picksWidestFieldOfView() {
        typealias Choice = MirrorCamera.FormatChoice
        let formats = [
            Choice(fieldOfView: 54, width: 1920, height: 1080),   // 좁다
            Choice(fieldOfView: 68, width: 1280, height: 960),    // 가장 넓지만 화면보다 작다
            Choice(fieldOfView: 68, width: 3088, height: 2320),   // 가장 넓고 충분히 크다
            Choice(fieldOfView: 68, width: 4032, height: 3024),   // 가장 넓지만 과하게 크다
            Choice(fieldOfView: 62, width: 4032, height: 3024),   // 크지만 화각이 좁다
        ]
        let index = MirrorCamera.bestFormatIndex(formats)
        #expect(index == 2, "화각 최대 + 화면을 채울 만한 것 중 가장 작은 것")
        #expect(formats[index!].fieldOfView == 68)
    }

    @Test("format이 하나뿐이거나 전부 작아도 고른다")
    func formatChoiceHandlesEdgeCases() {
        typealias Choice = MirrorCamera.FormatChoice
        #expect(MirrorCamera.bestFormatIndex([]) == nil)

        let onlySmall = [
            Choice(fieldOfView: 70, width: 640, height: 480),
            Choice(fieldOfView: 70, width: 960, height: 720),
        ]
        // 화면을 채울 만한 게 없으면 그중 가장 큰 것.
        #expect(MirrorCamera.bestFormatIndex(onlySmall) == 1)

        let one = [Choice(fieldOfView: 60, width: 1920, height: 1080)]
        #expect(MirrorCamera.bestFormatIndex(one) == 0)
    }

    @Test("배율은 device factor 한 곳에서만 움직인다")
    func zoomIsWrittenInOnePlace() throws {
        // 배율을 바꾸는 자리가 여기저기 생기면 화면 표시와 실제 값이 갈라진다.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // ggumirrorTests
            .deletingLastPathComponent()      // 프로젝트 루트
            .appending(path: "ggumirror/Mirror")
        let files = try FileManager().contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            // crop으로 흉내 내지 않는다 — 실제 렌즈/센서 배율만 쓴다.
            #expect(!source.contains("videoScaleAndCropFactor"), "\(file.lastPathComponent)")
            // iOS 17에서 대체된 옛 gesture를 되살리지 않는다.
            #expect(!source.contains("MagnificationGesture"), "\(file.lastPathComponent)")

            let assignments = source.components(separatedBy: ".videoZoomFactor =").count - 1
            #expect(assignments <= 2, "\(file.lastPathComponent)에서 배율을 여러 곳에서 만진다")
        }

        let camera = try String(
            contentsOf: root.appending(path: "MirrorCamera.swift"), encoding: .utf8
        )
        // 시작 1x와 실제 변경, 딱 두 곳이다.
        #expect(camera.contains("device.videoZoomFactor = capability.deviceFactor(forLogical: 1)"))
        #expect(camera.contains("device.videoZoomFactor = safe"))
        // 기기를 만지는 것은 세션 큐 위 한 함수뿐이다.
        #expect(camera.contains("private nonisolated func setDeviceZoom(_ factor: CGFloat, ramps: Bool)"))
        #expect(camera.contains("sessionQueue.async { [self] in setDeviceZoom(factor, ramps: ramps) }"))
        // lock/unlock 짝을 지킨다. (`unlock`도 `lock`을 품으므로 앞을 붙여 센다)
        #expect(camera.components(separatedBy: "device.lockForConfiguration()").count - 1
                == camera.components(separatedBy: "device.unlockForConfiguration()").count - 1)
    }

    // MARK: - 촬영이 화면과 같은가

    @Test("촬영도 화면과 같은 규칙으로 Camera Area를 꽉 채운다")
    func captureFillsLikeThePreview() throws {
        // 세로 4:3 소스를 세로로 긴 화면에 넣는다.
        // 화면과 같은 aspect fill이면 카메라가 세로를 끝까지 채운다.
        // (여기서 위아래가 남으면 실기기에서 프레임이 두꺼워 보인다.)
        let size = CGSize(width: 300, height: 650)
        let captured = try #require(
            MirrorCapture.compose(frame: cameraFrame(width: 300, height: 400), design: .blank, size: size)
        )
        let image = try #require(captured.cgImage)

        // 거울 프레임 안쪽(카메라 영역) 맨 위와 맨 아래에 카메라가 닿아 있어야 한다.
        let area = MirrorFrameInsets.standard.mirrorArea
        let x = image.width / 2
        for y in [Int(Double(image.height) * (area.y + 0.01)),
                  Int(Double(image.height) * (area.y + area.height - 0.01))] {
            let point = pixel(image, x: x, y: y)
            let isCamera = abs(Int(point.red) - Int(point.green)) < 14
                && abs(Int(point.green) - Int(point.blue)) < 14
                && point.red > 60 && point.red < 150
            #expect(isCamera, "카메라 영역 y=\(y)가 카메라로 채워지지 않았다")
        }
    }

    @Test("촬영은 여전히 화면과 같은 크기 / 방향으로 나온다")
    func captureKeepsSizeAndOrientation() throws {
        let size = CGSize(width: 300, height: 650)
        let captured = try #require(
            MirrorCapture.compose(frame: cameraFrame(width: 300, height: 400), design: .blank, size: size)
        )
        #expect(captured.size.width == size.width)
        #expect(captured.size.height == size.height)
        #expect(captured.size.height > captured.size.width)   // 항상 세로
        // 카메라가 없어도 죽지 않는다.
        #expect(MirrorCapture.compose(frame: nil, design: .blank, size: size) != nil)
    }

    @Test("좌우 반전과 세로 고정은 그대로다")
    func mirroringPolicyUnchanged() {
        #expect(MirrorCamera.portraitRotationAngle == 90)
    }

    // MARK: - 장식은 그대로

    @Test("장식 위치는 카메라 배치와 무관하게 그대로다")
    func decorationAlignmentUnchanged() throws {
        // 장식은 예전과 같은 aspect-fill 변환을 쓴다. 카메라만 fit으로 바뀌었다.
        var design = MirrorDesign.blank
        design.texts = [TextObject(text: "가", center: NormalizedPoint(x: 0.5, y: 0.5))]

        let size = CGSize(width: 300, height: 650)
        let view = MirrorDecorationView(design: design).frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = false
        let image = try #require(renderer.cgImage)

        let transform = MirrorViewTransform.aspectFilled(in: CGSize(width: image.width, height: image.height))
        let center = transform.point(NormalizedPoint(x: 0.5, y: 0.5))
        #expect(abs(center.x - CGFloat(image.width) / 2) < 1)
        #expect(abs(center.y - CGFloat(image.height) / 2) < 1)

        // 카메라 자리는 여전히 완전히 비어 있다 — 그 위에 종이를 덮지 않는다.
        let corner = transform.point(NormalizedPoint(x: 0.5, y: 0.5))
        #expect(pixel(image, x: Int(corner.x), y: Int(corner.y)).alpha == 0)
    }
}
