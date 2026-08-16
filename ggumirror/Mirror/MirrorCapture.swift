//
//  MirrorCapture.swift
//  ggumirror
//
//  Phase 1-4: 화면 스크린샷이 아니라 원본 프레임 + 장식을 직접 합성한다.
//

import Photos
import SwiftUI
import UIKit

enum MirrorCapture {
    enum SaveResult {
        case saved
        case denied
        case failed
    }

    /// 사용자가 보고 있는 "완성된 거울 화면"을 만든다.
    /// 화면 overlay와 **같은 MirrorRenderer / 같은 aspect-fill 변환**을 쓰므로
    /// 좌우 반전 방향 / 장식 위치 / 비율 / crop이 화면과 일치한다.
    @MainActor
    static func compose(frame: UIImage?, design: MirrorDesign, size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        let composition = ZStack {
            Color.black
            if let frame {
                // 화면과 **같은 규칙**(aspect fill)이다. 미리 보던 화각과 저장되는 화각이 같아야 한다.
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
            MirrorDecorationView(design: design)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: composition)
        renderer.scale = 1            // size를 이미 픽셀 단위로 받는다
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// 촬영한 거울 사진. 카메라 사진이라 JPEG로 충분하다.
    static func save(_ image: UIImage) async -> SaveResult {
        guard let data = image.jpegData(compressionQuality: 0.95) else { return .failed }
        return await save(data: data)
    }

    /// 이미 만들어 둔 이미지 데이터를 저장한다.
    ///
    /// 형식을 여기서 정하지 않는다 — 내보내기(D-1)는 **PNG 그대로** 넘긴다.
    /// JPEG로 바꾸면 투명 스티커의 alpha가 사라진다.
    ///
    /// 최소 권한(.addOnly)만 요청한다. 라이브러리를 읽지 않는다.
    static func save(data: Data) async -> SaveResult {
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
