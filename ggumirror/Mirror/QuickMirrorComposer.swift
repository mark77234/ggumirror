//
//  QuickMirrorComposer.swift
//  ggumirror
//
//  촬영 결과에 프레임을 합성한다. **본 것 = 저장된 것**(WYSIWYG).
//
//  화면 전체를 스크린샷으로 찍지 않는다 — 촬영 버튼과 "꾸미러 열기"까지 사진에 남는다.
//  카메라 이미지 + 프레임, **딱 둘만** 합친다.
//
//  미리보기와 같아 보이게 만드는 핵심 두 가지:
//  1. 카메라 버퍼 비율과 화면 비율이 다르므로, 화면과 같은 비율로 **가운데를 잘라낸다**
//     (`resizeAspectFill` 미리보기와 같은 규칙).
//  2. 프레임은 `QuickMirrorFrame`의 **같은 계산**을 쓴다 — 숫자를 따로 쓰지 않는다.
//

import CoreGraphics
import SwiftUI
import UIKit

nonisolated enum QuickMirrorComposer {
    /// 미리보기에서 본 그대로 한 장을 만든다.
    ///
    /// - Parameters:
    ///   - camera: 이미 좌우 반전 + Portrait 회전된 카메라 프레임.
    ///   - preset: 그릴 프레임. `none`이면 카메라만 잘라서 돌려준다.
    ///   - previewAspect: 화면(미리보기)의 크기. 비율만 쓴다.
    static func compose(
        camera: UIImage,
        preset: QuickMirrorPresetID,
        previewAspect: CGSize
    ) -> UIImage {
        let cropped = cropToAspect(camera, aspect: previewAspect)
        guard preset.drawsFrame, let color = preset.frameColor else { return cropped }

        let size = cropped.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = cropped.scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            cropped.draw(in: CGRect(origin: .zero, size: size))

            let cgContext = context.cgContext
            let hole = QuickMirrorFrame.hole(in: size)
            let radius = QuickMirrorFrame.cornerRadius(in: size)

            // 바깥 전체 → 안쪽 둥근 구멍을 빼고 칠한다. 미리보기의 even-odd와 같은 결과다.
            cgContext.addRect(CGRect(origin: .zero, size: size))
            cgContext.addPath(UIBezierPath(roundedRect: hole, cornerRadius: radius).cgPath)
            cgContext.setFillColor(UIColor(color).cgColor)
            cgContext.fillPath(using: .evenOdd)

            // 구멍 경계의 옅은 선도 미리보기와 같게.
            cgContext.addPath(UIBezierPath(roundedRect: hole, cornerRadius: radius).cgPath)
            cgContext.setStrokeColor(UIColor.black.withAlphaComponent(0.12).cgColor)
            cgContext.setLineWidth(1)
            cgContext.strokePath()
        }
    }

    /// 화면과 같은 비율로 가운데를 잘라낸다 — `resizeAspectFill` 미리보기가 보여주는 영역.
    ///
    /// 비율이 이미 같거나 계산할 수 없으면 원본을 그대로 둔다.
    static func cropToAspect(_ image: UIImage, aspect: CGSize) -> UIImage {
        guard aspect.width > 0, aspect.height > 0, let cgImage = image.cgImage else { return image }

        let target = aspect.width / aspect.height
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let current = width / height
        guard abs(current - target) > 0.001 else { return image }

        let crop: CGRect = if current > target {
            // 원본이 더 넓다 → 좌우를 자른다.
            CGRect(x: (width - height * target) / 2, y: 0, width: height * target, height: height)
        } else {
            // 원본이 더 높다 → 위아래를 자른다.
            CGRect(x: 0, y: (height - width / target) / 2, width: width, height: width / target)
        }

        guard let cropped = cgImage.cropping(to: crop.integral) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
