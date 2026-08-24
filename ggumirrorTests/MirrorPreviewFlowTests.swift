//
//  MirrorPreviewFlowTests.swift
//  ggumirrorTests
//
//  **미리보기는 경제 동작이 아니다.**
//
//  받기 전에 · 로그인 없이 · 아무것도 사지 않고 카메라 위에 얹어 볼 수 있어야 한다.
//  그러면서 사기 전 사용자에게 원본 manifest나 asset을 넘겨주지도 않아야 한다.
//  두 요구가 같이 서는 자리가 **이미 공개된 미리보기 그림 한 장**이다.
//

import Testing
import CoreGraphics
import Foundation
import ImageIO
@testable import ggumirror

private func previewFixture() throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures/legacy-mirror-preview.png")
    return try Data(contentsOf: url)
}

private func rgba(_ data: Data) throws -> (w: Int, h: Int, bytes: [UInt8]) {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = try #require(CGContext(
        data: &bytes, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return (image.width, image.height, bytes)
}

private func alpha(_ p: (w: Int, h: Int, bytes: [UInt8]), _ x: Int, _ y: Int) -> UInt8 {
    p.bytes[(y * p.w + x) * 4 + 3]
}

/// 카메라 자리 안의 표본 좌표.
private func openingSamples(_ w: Int, _ h: Int) -> [(Int, Int)] {
    let area = MirrorFrameInsets.standard.mirrorArea
    return (1...4).flatMap { i -> [(Int, Int)] in
        (1...4).map { j in
            (Int((area.x + area.width * Double(i) / 5) * Double(w)),
             Int((area.y + area.height * Double(j) / 5) * Double(h)))
        }
    }
}

private func source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

@Suite("사용자 상품도 카메라 위에 얹힌다")
struct ListingLivePreviewTests {

    @Test("카메라 자리가 비어 진짜 카메라가 비친다")
    func openingBecomesTransparent() throws {
        let png = try #require(
            MirrorThumbnailNormalizer.cameraOpeningRemoved(png: try previewFixture())
        )
        let out = try rgba(png)
        let clear = openingSamples(out.w, out.h).filter { alpha(out, $0.0, $0.1) == 0 }
        // 표본 대부분이 비었다 — 여기로 얼굴이 보인다.
        #expect(clear.count > openingSamples(out.w, out.h).count / 2)
    }

    @Test("장식과 프레임은 남는다")
    func decorationSurvives() throws {
        let before = try rgba(try previewFixture())
        let after = try rgba(try #require(
            MirrorThumbnailNormalizer.cameraOpeningRemoved(png: try previewFixture())
        ))
        #expect((before.w, before.h) == (after.w, after.h))

        // 프레임 밴드(카메라 자리 밖)는 한 픽셀도 바뀌지 않는다.
        let area = MirrorFrameInsets.standard.mirrorArea
        let outside: [(Int, Int)] = [
            (5, 5), (before.w - 5, 5), (5, before.h - 5),
            (before.w / 2, Int(area.y * Double(before.h)) / 2),
            (before.w / 2, before.h - 20),
        ]
        for (x, y) in outside {
            let i = (min(y, before.h - 1) * before.w + min(x, before.w - 1)) * 4
            #expect(Array(before.bytes[i..<i + 4]) == Array(after.bytes[i..<i + 4]),
                    "카메라 자리 밖 (\(x),\(y))이 바뀌었다")
        }
    }

    @Test("밝게 되돌린 그림에서도 도려낼 수 있다")
    func worksOnTheLightenedArtefact() throws {
        // 카드가 보여 주는 것은 이미 한 번 밝게 되돌린 그림이다.
        // 미리보기는 그 결과에서 다시 도려낸다 — 예전 상품이든 새 상품이든 같은 경로다.
        let lightened = try #require(
            MirrorThumbnailNormalizer.normalized(png: try previewFixture())
        )
        let knocked = try #require(
            MirrorThumbnailNormalizer.cameraOpeningRemoved(png: lightened)
        )
        let out = try rgba(knocked)
        let clear = openingSamples(out.w, out.h).filter { alpha(out, $0.0, $0.1) == 0 }
        #expect(clear.count > openingSamples(out.w, out.h).count / 2)
    }

    @Test("도려낼 수 없으면 미리보기를 만들지 않는다")
    func refusesWhenNothingCanBeCarvedOut() {
        // 그림이 아니면 조용히 빈 화면을 띄우지 않고 아예 만들지 않는다.
        #expect(MirrorPreviewSubject.overlay(fromListingPreview: Data([0, 1, 2])) == nil)
    }

    @Test("공개 미리보기 그림 하나로 끝낸다")
    func usesOnlyThePublicArtefact() throws {
        let gallery = try source("ggumirror/Store/MarketplaceGallery.swift")
        // 미리보기를 여는 자리가 읽는 것은 이미 받아 둔 공개 그림뿐이다.
        #expect(gallery.contains("store.previews[listing.id]"))
        // manifest · 원본 asset · 판매자 전용 경로를 새로 부르지 않는다.
        for forbidden in ["manifest", "downloadContent", "rawAsset", "loadMyPreview"] {
            #expect(!gallery.contains("openPreview") || !gallery.contains("\(forbidden)("),
                    "미리보기가 \(forbidden)를 부른다")
        }
    }

    @Test("스티커에는 미리보기가 없다")
    func stickersHaveNoLivePreview() throws {
        let gallery = try source("ggumirror/Store/MarketplaceGallery.swift")
        #expect(gallery.contains("!ListingPreviewStyle.isSticker(listing.contentType)"))
    }
}

@Suite("미리보기는 아무것도 바꾸지 않는다")
struct PreviewIsNotAnEconomicActionTests {

    @Test("미리보기 화면에 경제 동작이 없다")
    func nothingMutates() throws {
        let preview = try source("ggumirror/Mirror/MirrorLivePreview.swift")
        for forbidden in [
            // `.purchased`(출처 표시)는 값이라 걸리지 않게 호출 형태로 본다.
            "purchase(", "acquire(", "adopt(", "downloadCount", "balance",
            "persist(", "importMirror", "importSticker", "session",
        ] {
            #expect(!preview.contains(forbidden), "미리보기가 \(forbidden)를 건드린다")
        }
    }

    @Test("로그인을 묻지 않는다")
    func guestsCanPreview() throws {
        let gallery = try source("ggumirror/Store/MarketplaceGallery.swift")
        // 미리보기를 여는 함수 본문에 로그인 관문이 없다.
        let body = try #require(gallery.range(of: "private func openPreview()")).upperBound
        let end = try #require(gallery.range(of: "private func runAcquire", range: body..<gallery.endIndex)).lowerBound
        let openPreview = String(gallery[body..<end])
        #expect(!openPreview.contains("onNeedsSignIn"))
        #expect(!openPreview.contains("session"))
    }

    @Test("촬영도 저장도 없는 화면이다")
    func previewCannotCapture() throws {
        let preview = try source("ggumirror/Mirror/MirrorLivePreview.swift")
        // role 기본값(`.viewfinder`)이라 photo output 자체가 없다 — 구조로 막힌다.
        #expect(preview.contains("MirrorCamera()"))
        #expect(!preview.contains("role: .mirror"))
        for forbidden in ["capturePhoto", "MirrorCapture", "switchCamera", "flash"] {
            #expect(!preview.contains(forbidden), "미리보기에 \(forbidden)가 있다")
        }
    }
}

@Suite("두 상세가 같은 미리보기를 쓴다")
struct SharedPreviewEntryTests {

    @Test("문구와 표현 경로가 하나다")
    func oneEntryPoint() throws {
        let template = try source("ggumirror/Store/TemplateDetailView.swift")
        let gallery = try source("ggumirror/Store/MarketplaceGallery.swift")
        for file in [template, gallery] {
            #expect(file.contains("내 거울로 미리보기"))
            #expect(file.contains(".mirrorLivePreview($preview"))
        }
        // 미리보기 자리의 준비 중 안내가 사라졌다 — 실제로 열린다.
        // (내장 유료 템플릿의 **조각 결제**는 여전히 서버 경로가 없어 그대로다 —
        // 이번 작업은 미리보기이고 경제 transaction을 다시 설계하지 않는다.)
        #expect(!template.contains("내 거울로 미리보기는 다음 업데이트"))
    }

    @Test("내장 템플릿은 받지 않고 그대로 그린다")
    @MainActor
    func builtInPreviewNeedsNoDownload() throws {
        let template = StoreCatalog.samples[0]
        let design = MirrorDesign(template: template)
        let acquired = try #require(MirrorLibrary().acquire(template))
        // 미리보기와 실제로 받은 거울이 **같은 조립**이다.
        #expect(design.id == acquired.id)
        #expect(design.style == acquired.style)
        #expect(design.importedArtworks.count == acquired.importedArtworks.count)
    }

    @Test("미리보기가 받기보다 먼저 있다")
    func previewComesFirst() throws {
        for path in [
            "ggumirror/Store/TemplateDetailView.swift",
            "ggumirror/Store/MarketplaceGallery.swift",
        ] {
            let file = try source(path)
            let preview = try #require(file.range(of: "내 거울로 미리보기")).lowerBound
            let acquire = try #require(file.range(of: "cta.title")).lowerBound
            #expect(preview < acquire, "\(path)에서 받기가 미리보기보다 먼저다")
        }
    }
}
