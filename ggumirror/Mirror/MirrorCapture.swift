//
//  MirrorCapture.swift
//  ggumirror
//
//  Phase 1-4: 화면 스크린샷이 아니라 원본 프레임 + 장식을 직접 합성한다.
//

import Photos
import UIKit

enum MirrorCapture {
    enum SaveResult {
        case saved
        case denied
        case failed
    }

    /// 사용자가 보고 있는 "완성된 거울 화면"을 만든다.
    /// Mirror 화면과 같은 규칙(Uniform Scale + Crop, 중앙 정렬)으로 그리기 때문에
    /// 좌우 반전 방향 / 장식 정렬 / 비율 / crop이 화면과 일치한다.
    static func compose(frame: UIImage?, decoration: UIImage?, size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0, frame != nil || decoration != nil else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1              // size를 이미 픽셀 단위로 받는다
        format.opaque = true

        let bounds = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(bounds)
            frame?.drawAspectFill(in: bounds)
            decoration?.drawAspectFill(in: bounds)
        }
    }

    /// 최소 권한(.addOnly)만 요청한다. 라이브러리를 읽지 않는다.
    static func save(_ image: UIImage) async -> SaveResult {
        guard let data = image.jpegData(compressionQuality: 0.95) else { return .failed }
        guard await isAddAuthorized() else { return .denied }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            return .saved
        } catch {
            return .failed
        }
    }

    private static func isAddAuthorized() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return status == .authorized || status == .limited
        default:
            return false
        }
    }
}

private extension UIImage {
    /// 비율을 유지한 채 rect를 채우고 넘치는 부분은 잘린다. 가로/세로를 따로 늘리지 않는다.
    func drawAspectFill(in rect: CGRect) {
        guard size.width > 0, size.height > 0 else { return }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let scaled = CGSize(width: size.width * scale, height: size.height * scale)
        draw(in: CGRect(
            x: rect.midX - scaled.width / 2,
            y: rect.midY - scaled.height / 2,
            width: scaled.width,
            height: scaled.height
        ))
    }
}
