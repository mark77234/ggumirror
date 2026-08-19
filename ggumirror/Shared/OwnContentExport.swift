//
//  OwnContentExport.swift
//  ggumirror
//
//  **내가 만든 것만** 앱 밖으로 내보낸다.
//
//  새 렌더러를 만들지 않았다. 거울도 스티커도 화면에서 쓰는 `MirrorRenderer.draw`를
//  그대로 부른다 — 그래야 사용자가 본 것과 파일이 다를 수 없다.
//  **화면을 스크린샷하지 않는다.** 1080 × 2340 master canvas에 직접 그리므로
//  기기 크기 · Dynamic Type · scale이 결과를 바꾸지 못한다.
//
//  편집 화면의 것(안내선 · 선택 표시 · 핸들 · 툴바)은 애초에 들어올 수 없다 —
//  그것들은 Editor가 캔버스 **밖에서** 그리고, 여기서 부르는 것은 장식 렌더뿐이다.
//

import Photos
import SwiftUI
import UIKit

// MARK: - 무엇을 내보낼 수 있나

/// 앱 밖으로 파일을 꺼낼 수 있는 콘텐츠인가.
///
/// **`MirrorPublishPolicy`와 일부러 분리했다.** "팔아도 되는가"와
/// "앱 밖으로 가져가도 되는가"는 다른 질문이다. 지금은 답이 같지만,
/// 한쪽 정책이 바뀔 때 다른 쪽이 조용히 따라 바뀌면 안 된다.
enum OwnContentExportPolicy {
    /// 내가 만든 거울만. **상점에서 받은 기본 / 구매 거울은 내보내지 않는다** —
    /// 다른 사람이 그린 artwork를 원본 파일로 꺼내가는 통로가 되기 때문이다.
    static func canExport(_ mirror: MyMirror) -> Bool { mirror.origin == .made }

    /// 스티커 프로젝트는 Sticker Creator에서 사용자가 직접 만든 것뿐이다
    /// (상점 스티커를 프로젝트로 들여오는 경로가 없다).
    /// 그런 경로가 생기면 **여기에 출처 조건을 추가한다.**
    static func canExport(_ project: StickerProject) -> Bool { true }
}

// MARK: - 실패

enum OwnContentExportFailure: Error, Equatable {
    case notExportable
    case renderingFailed
    case temporaryFileFailed
    case photosPermissionDenied
    case photosSaveFailed
    case sharePreparationFailed

    /// 사용자에게 보여줄 말. 무엇을 하면 되는지까지 알려준다.
    var message: String {
        switch self {
        case .notExportable:
            "내가 만든 거울과 스티커만 내보낼 수 있어요."
        case .renderingFailed:
            "이미지를 만들지 못했어요. 잠시 뒤 다시 시도해 주세요."
        case .temporaryFileFailed:
            "파일을 준비하지 못했어요. 저장 공간을 확인해 주세요."
        case .photosPermissionDenied:
            "사진 앱에 저장할 권한이 없어요. 설정 → 꾸미러에서 사진 추가를 허용해 주세요."
        case .photosSaveFailed:
            "사진 앱에 저장하지 못했어요. 잠시 뒤 다시 시도해 주세요."
        case .sharePreparationFailed:
            "공유를 준비하지 못했어요. 잠시 뒤 다시 시도해 주세요."
        }
    }
}

// MARK: - 렌더

enum OwnContentExport {
    /// 거울 한 장 → **1080 × 2340 PNG**.
    ///
    /// 크기는 `MirrorCanvas.size` 하나에서만 온다. 화면 크기를 보지 않는다.
    /// 투명 프레임(`isFrameVisible == false`)이면 렌더러가 프레임 밴드를 통째로 건너뛴다 —
    /// 여기서 따로 분기하지 않는다(판단이 두 곳에 있으면 언젠가 어긋난다).
    @MainActor
    static func mirrorPNG(_ mirror: MyMirror) throws -> Data {
        guard OwnContentExportPolicy.canExport(mirror) else {
            throw OwnContentExportFailure.notExportable
        }
        return try mirrorPNG(
            style: mirror.style,
            strokes: mirror.strokes,
            stickers: mirror.stickers,
            texts: mirror.texts,
            importedArtworks: mirror.importedArtworks
        )
    }

    /// 소유권 확인을 이미 마친 뒤의 순수 렌더. test가 직접 부른다.
    @MainActor
    static func mirrorPNG(
        style: MirrorStyle,
        strokes: [DrawingStroke] = [],
        stickers: [StickerObject] = [],
        texts: [TextObject] = [],
        importedArtworks: [ImportedArtworkObject] = []
    ) throws -> Data {
        let size = MirrorCanvas.size
        let canvas = Canvas { context, canvasSize in
            MirrorRenderer.draw(
                style: style,
                strokes: strokes,
                stickers: stickers,
                texts: texts,
                importedArtworks: importedArtworks,
                transform: .fitted(in: canvasSize),
                in: context,
                viewport: canvasSize
            )
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: canvas)
        // master canvas를 픽셀 그대로 그린다. 기기 scale을 곱하지 않는다.
        renderer.scale = 1
        // 투명 프레임 거울은 프레임 밴드가 비어 있어야 한다. 불투명으로 만들면 검게 찬다.
        renderer.isOpaque = false

        guard let image = renderer.uiImage, let data = image.pngData() else {
            throw OwnContentExportFailure.renderingFailed
        }
        return data
    }

    /// 내가 만든 스티커 → **원본 alpha 그대로인 투명 PNG**.
    ///
    /// `StickerRenderer`가 이미 하던 일이다. 크기 규칙(`StickerCanvas.size`)도 그쪽이 정한다 —
    /// 내보내기가 별도 해상도를 정하면 Creator에서 본 것과 달라진다.
    @MainActor
    static func stickerPNG(_ project: StickerProject) throws -> Data {
        guard OwnContentExportPolicy.canExport(project) else {
            throw OwnContentExportFailure.notExportable
        }
        guard let data = StickerRenderer.pngData(project.design) else {
            throw OwnContentExportFailure.renderingFailed
        }
        return data
    }
}

// MARK: - 사진 앱에 저장

extension OwnContentExport {
    /// PNG 그대로 저장한다. **JPEG로 바꾸지 않는다** — 스티커의 투명 영역이 사라진다.
    ///
    /// 권한은 `MirrorCapture`가 이미 쓰는 **add-only** 그대로다. 라이브러리를 읽지 않는다.
    static func saveToPhotos(png: Data) async -> OwnContentExportFailure? {
        switch await MirrorCapture.save(data: png) {
        case .saved: nil
        case .denied: .photosPermissionDenied
        case .failed: .photosSaveFailed
        }
    }
}

// MARK: - 공유용 임시 파일

/// 공유 시트에 넘길 파일 하나. **사용자 원본 데이터와 섞이지 않는다** —
/// Application Support가 아니라 temporary directory에 쓰고, 다 쓰면 지운다.
@MainActor
final class ExportedFile {
    let url: URL

    private init(url: URL) { self.url = url }

    /// `name`은 파일 이름에 쓸 수 있게 다듬는다. 경로 구분자나 빈 이름이 들어와도 안전하다.
    static func png(_ data: Data, name: String) throws -> ExportedFile {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "ggumirror-export", directoryHint: .isDirectory)
        let url = folder.appending(path: "\(safeName(name)).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            // 경로를 로그에 남기지 않는다. 실패했다는 사실만 위로 올린다.
            throw OwnContentExportFailure.temporaryFileFailed
        }
        return ExportedFile(url: url)
    }

    /// 공유가 끝나면 지운다. 남겨두면 임시 폴더에 사용자 콘텐츠가 쌓인다.
    func cleanUp() {
        try? FileManager.default.removeItem(at: url)
    }

    /// 앱을 다시 켰을 때 예전에 남은 것을 정리한다(공유 중 강제 종료 등).
    static func cleanUpLeftovers() {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "ggumirror-export", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
    }

    /// 파일 이름으로 쓸 수 없는 글자를 걷어낸다. 비면 기본 이름을 쓴다.
    static func safeName(_ raw: String) -> String {
        let cleaned = raw
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\0"))
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "ggumirror" : String(cleaned.prefix(60))
    }
}

// 공유 시트는 UI-P3에서 제거했다 — 거울/스티커 공유하기 action이 사라져 부를 곳이 없다.
// `ExportedFile`은 남긴다: 이전 빌드가 남긴 임시 파일을 `cleanUpLeftovers()`가 치운다.
