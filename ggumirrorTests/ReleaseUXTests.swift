//
//  ReleaseUXTests.swift
//  ggumirrorTests
//
//  Phase I. 실기기 QA에서 나온 것만 다룬다.
//

import Testing
import Foundation
@testable import ggumirror

private func uxSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

@Suite("타이핑이 거울을 다시 그리지 않는다")
struct TextInputCostTests {

    @Test("입력 중인 글자는 시트가 들고 있다")
    func sheetsOwnTheirDraft() throws {
        // 부모(`EditorView`)의 body에는 `MirrorEditorCanvas`가 있다. 거기에 바로 쓰면
        // 한 글자마다 canvas 전체가 다시 평가된다 — 실기기 입력 지연의 원인이었다.
        for path in ["ggumirror/Editor/TextEditorSheets.swift",
                     "ggumirror/Editor/MirrorSaveSheets.swift"] {
            let code = try uxSource(path)
            #expect(!code.contains("@Binding var text"), "\(path): 부모 state에 직접 쓴다")
            #expect(!code.contains("@Binding var name"), "\(path): 부모 state에 직접 쓴다")
        }
        #expect(try uxSource("ggumirror/Editor/TextEditorSheets.swift")
            .contains("@State private var text"))
        #expect(try uxSource("ggumirror/Editor/MirrorSaveSheets.swift")
            .contains("@State private var name"))
    }

    @Test("완성된 값만 한 번 넘긴다")
    func commitPassesTheValue() throws {
        let editor = try uxSource("ggumirror/Editor/EditorView.swift")
        // 값이 인자로 넘어온다 — 부모가 타이핑 도중의 상태를 들고 있지 않다는 뜻이다.
        #expect(editor.contains("commitText($0)"))
        #expect(editor.contains("saveMirror(named: $0)"))
        #expect(editor.contains("private func commitText(_ draft: String)"))
        #expect(editor.contains("private func saveMirror(named name: String)"))
    }

    @Test("타이핑 경로에 서버도 디스크도 없다")
    func typingTouchesNothingExpensive() throws {
        // 이름 입력은 이미 local draft다. 저장은 툴바 버튼에서만 일어난다.
        let profile = try uxSource("ggumirror/Home/ProfileView.swift")
        let start = try #require(profile.range(of: "onChange(of: name)")).upperBound
        let window = profile[start...].prefix(220)
        for expensive in ["await", "save(", "backend", "library."] {
            #expect(!window.contains(expensive), "이름 한 글자마다 \(expensive)")
        }
    }
}

@Suite("운영 목록 기본 상태")
struct AdminStatusFilterTests {

    private func listing(moderation: String, status: String) -> AdminListing {
        let json = """
        {"id":"L","contentType":"mirror","title":"거울","description":"",
         "priceShards":3,"status":"\(status)","moderationStatus":"\(moderation)",
         "moderationReason":null,"downloadCount":0,"likeCount":0,
         "createdAt":"2026-08-01T00:00:00Z","publishedAt":"2026-08-01T00:00:00Z",
         "sellerDisplayName":"판매자"}
        """
        return try! JSONDecoder.backend.decode(AdminListing.self, from: Data(json.utf8))
    }

    @Test("기본 목록에 판매자가 삭제한 상품이 섞이지 않는다")
    func sellerDeletedIsNotInTheDefaultList() {
        // 되살릴 수 없어 운영자가 할 일이 없다. 판매 중인 것과 같은 줄에 있으면
        // 무엇을 조치해야 하는지 읽히지 않는다.
        let deleted = listing(moderation: "active", status: "deleted")
        #expect(!AdminStatusFilter.live.includes(deleted))
        #expect(!AdminStatusFilter.removed.includes(deleted))
        #expect(AdminStatusFilter.all.includes(deleted))
    }

    @Test("판매 중과 내려간 것이 갈린다")
    func liveAndRemovedAreSeparate() {
        let live = listing(moderation: "active", status: "published")
        let removed = listing(moderation: "removed", status: "published")

        #expect(AdminStatusFilter.live.includes(live))
        #expect(!AdminStatusFilter.live.includes(removed))
        #expect(AdminStatusFilter.removed.includes(removed))
        #expect(!AdminStatusFilter.removed.includes(live))
    }

    @Test("기본값은 판매 중이다")
    func defaultIsLive() throws {
        let code = try uxSource("ggumirror/Admin/AdminStoreView.swift")
        #expect(code.contains("var statusFilter: AdminStatusFilter = .live"))
        // 종류 필터와 다른 축이다 — 합치면 "스티커이면서 내려간 것"을 고를 수 없다.
        #expect(code.contains("var contentType: String?"))
    }

    @Test("공개 상점은 서버 목록을 그대로 쓴다")
    func publicStoreNeverMergesLocally() throws {
        let store = try uxSource("ggumirror/Store/MarketplaceStore.swift")
        // 통째로 바꿔 넣는다. 합치거나 쌓으면 내려간 상품이 화면에 남는다.
        #expect(store.contains("listings = try await backend.listings("))
        #expect(!store.contains("listings +="))
        #expect(!store.contains("listings.append"))
    }
}
