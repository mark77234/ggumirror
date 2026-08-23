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
    /// 화면 overlay와 **같은 MirrorRenderer / 같은 framing 규칙**을 쓰므로
    /// 좌우 반전 방향 / 장식 위치 / 비율 / crop이 화면과 일치한다.
    ///
    /// - Parameter framing: 화면에서 쓰던 것과 **같은 값**이어야 한다.
    ///   preview는 넓게 보는데 저장은 잘려 나오면 사용자가 본 것과 다른 사진이 된다.
    @MainActor
    static func compose(
        frame: UIImage?,
        design: MirrorDesign,
        size: CGSize,
        framing: MirrorCamera.Framing = .fill
    ) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        let composition = ZStack {
            Color.black
            if let frame {
                // preview layer의 `videoGravity`와 **같은 규칙**이다.
                // `.resizeAspect` ↔ `scaledToFit`, `.resizeAspectFill` ↔ `scaledToFill`.
                mirrorFrame(frame, framing: framing)
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

    /// 화면과 같은 방법으로 그림을 놓는다. **두 방법이 한 곳에만 있다.**
    ///
    /// 넓게 보기에서 위아래에 남는 검은 자리는 화면에서 보던 그대로다 —
    /// 사진에서만 지우면 거울 장식(전체 화면 기준 확정 geometry)이 잘린다.
    @ViewBuilder
    private static func mirrorFrame(
        _ image: UIImage, framing: MirrorCamera.Framing
    ) -> some View {
        switch framing {
        case .wide:
            Image(uiImage: image).resizable().scaledToFit()
        case .fill:
            Image(uiImage: image).resizable().scaledToFill()
        }
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
