//
//  QuickMirrorCaptureStore.swift
//  ggumirror
//
//  촬영 결과를 두는 곳. **`LockedCameraCaptureSession.sessionContentURL`뿐이다.**
//
//  extension은 자기 영구 저장소를 source of truth로 쓰지 않는다.
//  본앱이 `LockedCameraCaptureManager`로 이 폴더를 수거한다.
//
//  **본앱과 Capture extension이 함께 쓴다** — 파일 이름 규칙의 진실이 한 곳에 있어야
//  extension이 쓴 것을 본앱이 정확히 찾을 수 있다.
//

import Foundation
import LockedCameraCapture
import UIKit

nonisolated enum QuickMirrorCaptureStore {
    enum Failure: Error {
        case cannotEncode
    }

    /// 파일 이름 규칙. 잠금화면에서 여러 장 찍어도 겹치지 않게 시간 + 무작위 조각을 붙인다.
    /// 사용자 정보를 이름에 담지 않는다.
    static func fileName(at moment: Date = Date(), suffix: String = UUID().uuidString) -> String {
        let stamp = Int(moment.timeIntervalSince1970 * 1000)
        let short = suffix.prefix(8)
        return "quick-mirror-\(stamp)-\(short).png"
    }

    @discardableResult
    static func save(
        _ image: UIImage,
        in session: LockedCameraCaptureSession,
        at moment: Date = Date()
    ) throws -> URL {
        try save(image, into: session.sessionContentURL, at: moment)
    }

    /// 테스트가 직접 부를 수 있도록 폴더를 받는 형태로 분리했다.
    @discardableResult
    static func save(_ image: UIImage, into directory: URL, at moment: Date = Date()) throws -> URL {
        guard let data = image.pngData() else { throw Failure.cannotEncode }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: fileName(at: moment))
        // 잠금 상태에서 쓰므로 잠금 해제 후에만 읽히도록 둔다.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return url
    }

    /// 이 폴더에 들어 있는 Quick Mirror 결과들. 본앱이 수거할 때 쓴다.
    static func captures(in directory: URL) -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        return (contents ?? [])
            .filter { $0.lastPathComponent.hasPrefix("quick-mirror-") && $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
