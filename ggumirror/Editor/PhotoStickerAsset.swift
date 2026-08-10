//
//  PhotoStickerAsset.swift
//  ggumirror
//
//  사진 스티커의 이미지 보관소 + 온디바이스 배경 제거.
//
//  중요: 이미지 binary는 여기에만 있다.
//  MirrorDesign / StickerObject / EditorSnapshot / Undo 스택에는 assetID와 비율만 들어간다.
//  덕분에 Undo 한 번에 사진이 통째로 복사되는 일이 없다.
//
//  네트워크를 쓰지 않는다. 모든 처리는 기기 안에서 끝난다.
//

import CoreImage
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import Vision

// MARK: - 보관소

/// 사진 스티커 이미지 1회 보관. 메모리 캐시 + 디스크(PNG) 뒷받침.
///
/// 렌더러는 준비된 CGImage만 본다 — 그리는 도중에 파일을 읽지 않도록
/// 앱이 시작할 때 `preload`로 필요한 사진을 미리 올려둔다.
///
/// 관찰 대상으로 두지 않는다. 캐시에 채워 넣는 일이 화면 갱신을 다시 부르면 안 된다.
@MainActor
final class PhotoStickerAssetStore {
    /// 렌더러(MirrorRenderer)가 화면마다 store를 넘겨받지 않고 바로 볼 수 있도록 하나만 둔다.
    static let shared = PhotoStickerAssetStore()

    private var assets: [UUID: CGImage] = [:]
    /// 디스크에도 없던 것. 매 프레임 같은 파일을 다시 찾지 않게 한다.
    private var missing: Set<UUID> = []
    /// 디스크 저장소. 앱이 시작할 때 MirrorLibrary가 연결한다.
    /// 연결 전에는 메모리만 쓴다 — 단위 테스트가 실제 앱 폴더를 건드리지 않는다.
    private var storage: MirrorStore?

    init(storage: MirrorStore? = nil) {
        self.storage = storage
    }

    func attach(_ store: MirrorStore) {
        storage = store
        missing.removeAll()
    }

    /// 보관하고 참조용 source를 돌려준다. 비율은 잘라낸 결과 그대로다.
    func register(_ image: CGImage) -> StickerSource {
        let id = UUID()
        assets[id] = image
        missing.remove(id)
        // 사진 1장당 1회. 배경 제거(수 초) 직후라 여기서 PNG 한 장 굽는 비용은 묻힌다.
        if let storage, let data = storage.encodePNG(image) {
            storage.writeAsset(data, id: id)
        }
        return .photo(assetID: id, aspectRatio: Double(image.width) / Double(max(image.height, 1)))
    }

    /// 없으면 nil. 렌더러는 조용히 건너뛴다 — 사진이 사라져도 앱이 깨지지 않는다.
    func image(for id: UUID) -> CGImage? {
        if let cached = assets[id] { return cached }
        guard let storage, !missing.contains(id) else { return nil }
        guard let loaded = storage.readAsset(id) else {
            missing.insert(id)
            return nil
        }
        assets[id] = loaded
        return loaded
    }

    /// 저장된 거울이 쓰는 사진을 미리 메모리에 올린다. 앱 시작 때 한 번.
    func preload(_ ids: Set<UUID>) {
        for id in ids { _ = image(for: id) }
    }

    var count: Int { assets.count }

    /// 복제는 같은 asset을 참조하므로 이미지가 늘지 않는다.
    func isRegistered(_ source: StickerSource) -> Bool {
        guard let id = source.photoAssetID else { return false }
        return image(for: id) != nil
    }
}

// MARK: - 배경 제거

enum PhotoStickerError: Error, Equatable {
    /// 사진에서 주 피사체를 찾지 못했다.
    case noSubject
    /// 이미지를 읽지 못했다.
    case unreadable
}

/// 사진 → 배경이 지워진 스티커 이미지.
enum PhotoStickerMaker {
    /// 원본이 아무리 커도 이 크기로 줄여서 처리한다. 메모리와 처리 시간을 함께 잡는다.
    static let maximumPixelSize = 1600
    /// 잘라낸 뒤 남기는 투명 여백 (긴 변 기준 비율). 스티커가 프레임에 딱 붙어 보이지 않게 한다.
    static let transparentPadding = 0.04

    /// 피사체만 남긴 투명 배경 이미지.
    /// 실패하면 던지고, 호출부가 "다시 고르기 / 원본으로 추가 / 취소"를 물어본다.
    static func makeSticker(from data: Data) async throws -> CGImage {
        let source = try downsample(data)
        try Task.checkCancellation()

        let handler = ImageRequestHandler(source)
        guard let observation = try await handler.perform(GenerateForegroundInstanceMaskRequest()),
              !observation.allInstances.isEmpty
        else { throw PhotoStickerError.noSubject }

        try Task.checkCancellation()

        // 피사체 영역까지 한 번에 잘라준다 — 별도 bounds 계산이 필요 없다.
        let masked = try observation.generateMaskedImage(
            for: observation.allInstances,
            imageFrom: handler,
            croppedToInstancesExtent: true
        )
        guard let cropped = CIContext().createCGImage(
            CIImage(cvPixelBuffer: masked),
            from: CIImage(cvPixelBuffer: masked).extent
        ) else { throw PhotoStickerError.unreadable }

        return padded(cropped)
    }

    /// 배경 제거에 실패했을 때 "원본으로 추가"에 쓰는 이미지. 축소만 한다.
    static func makeOriginal(from data: Data) throws -> CGImage {
        try downsample(data)
    }

    // MARK: - 내부

    /// ImageIO thumbnail로 디코드 단계에서 바로 줄인다. 원본 전체를 메모리에 올리지 않는다.
    private static func downsample(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw PhotoStickerError.unreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // EXIF 회전 반영
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoStickerError.unreadable
        }
        return image
    }

    /// 사방에 투명 여백을 더한다. (테스트에서 직접 확인할 수 있도록 internal)
    static func padded(_ image: CGImage) -> CGImage {
        let inset = Int((Double(max(image.width, image.height)) * transparentPadding).rounded())
        guard inset > 0 else { return image }

        let width = image.width + inset * 2
        let height = image.height + inset * 2
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: inset, y: inset, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }
}
