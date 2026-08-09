//
//  EditorGeometryTests.swift
//  ggumirrorTests
//
//  터치로 확인하기 어려운 Editor 좌표 변환 / mask / history를 검증한다.
//

import Testing
import SwiftUI
@testable import ggumirror

@MainActor
struct EditorGeometryTests {

    private let viewport = CGSize(width: 320, height: 520)
    /// 제품에서는 쓰지 않지만 engine이 frameInsets를 따르는지 확인하기 위한 값.
    private static let thickInsets = MirrorFrameInsets(top: 0.115, right: 0.17, bottom: 0.115, left: 0.17)

    // MARK: - 좌표 변환

    @Test("화면 좌표 → Master normalized → 화면 좌표 왕복이 일치한다", arguments: EditorSide.allCases)
    func screenToMasterRoundTrip(side: EditorSide) {
        let transform = SideDetailTransform(side: side, insets: .standard, viewport: viewport)
        let screenPoint = CGPoint(x: 137, y: 209)

        let master = transform.masterPoint(from: screenPoint)
        let backX = master.x * transform.canvasSize.width + transform.offset.x
        let backY = master.y * transform.canvasSize.height + transform.offset.y

        #expect(abs(backX - screenPoint.x) < 0.001)
        #expect(abs(backY - screenPoint.y) < 0.001)
    }

    @Test("frameInsets가 다르면 같은 화면 좌표가 다른 Master 좌표가 된다")
    func transformFollowsInsets() {
        let standard = SideDetailTransform(side: .left, insets: .standard, viewport: viewport)
        let thick = SideDetailTransform(side: .left, insets: Self.thickInsets, viewport: viewport)
        let screenPoint = CGPoint(x: 40, y: 120)

        #expect(standard.masterPoint(from: screenPoint) != thick.masterPoint(from: screenPoint))
    }

    @Test("선택한 밴드가 화면 안에 들어온다", arguments: EditorSide.allCases)
    func bandIsVisible(side: EditorSide) {
        let insets = MirrorFrameInsets.standard
        let transform = SideDetailTransform(side: side, insets: insets, viewport: viewport)
        let band = side.boundingBox(with: insets).rect(in: transform.canvasSize)
        let center = CGPoint(x: band.midX + transform.offset.x, y: band.midY + transform.offset.y)

        #expect(center.x >= 0 && center.x <= viewport.width)
        #expect(center.y >= 0 && center.y <= viewport.height)
    }

    // MARK: - Frame mask

    @Test("중앙 Mirror Area 안쪽은 그릴 수 없다")
    func mirrorAreaIsNotDrawable() {
        let insets = MirrorFrameInsets.standard
        #expect(insets.isInsideMirrorArea(NormalizedPoint(x: 0.5, y: 0.5)))
        #expect(!insets.isInsideMirrorArea(NormalizedPoint(x: 0.5, y: 0.02)))
        #expect(!insets.isInsideMirrorArea(NormalizedPoint(x: 0.03, y: 0.5)))
    }

    @Test("frameInsets가 달라지면 mask 경계도 달라진다")
    func maskFollowsInsets() {
        let point = NormalizedPoint(x: 0.5, y: 0.09)
        // standard(상하 0.0769)에서는 이미 거울 영역, 더 두꺼운 값에서는 아직 프레임
        #expect(MirrorFrameInsets.standard.isInsideMirrorArea(point))
        #expect(!Self.thickInsets.isInsideMirrorArea(point))
    }

    // MARK: - 밴드 분할

    @Test("모서리 점은 정확히 한 밴드에만 속한다")
    func cornersBelongToExactlyOneBand() {
        let insets = MirrorFrameInsets.standard
        let rect = CGRect(origin: .zero, size: MirrorCanvas.size)
        let probes = [
            CGPoint(x: 20, y: 20),                                     // 좌상단 모서리
            CGPoint(x: MirrorCanvas.size.width - 20, y: 20),           // 우상단
            CGPoint(x: 20, y: MirrorCanvas.size.height - 20),          // 좌하단
            CGPoint(x: MirrorCanvas.size.width - 20, y: MirrorCanvas.size.height - 20)
        ]

        for probe in probes {
            let matches = EditorSide.allCases.filter {
                SideBandShape(side: $0, insets: insets).path(in: rect).contains(probe)
            }
            #expect(matches.count == 1, "모서리에서 밴드가 \(matches.count)개 잡힘")
        }
    }

    // MARK: - Undo / Redo

    @Test("Undo / Redo가 순서대로 동작한다")
    func undoRedoOrder() {
        var strokes: [DrawingStroke] = []
        var history = DrawingHistory()

        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.05)], width: 0.01)
        let b = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.9)], width: 0.01)

        history.commit([a], to: &strokes)
        history.commit([a, b], to: &strokes)
        #expect(strokes.map(\.id) == [a.id, b.id])

        history.undo(&strokes)
        #expect(strokes.map(\.id) == [a.id])
        history.undo(&strokes)
        #expect(strokes.isEmpty)
        #expect(!history.canUndo)

        history.redo(&strokes)
        #expect(strokes.map(\.id) == [a.id])
        history.redo(&strokes)
        #expect(strokes.map(\.id) == [a.id, b.id])
        #expect(!history.canRedo)
    }

    @Test("새 작업이 생기면 Redo는 비워진다")
    func newWorkClearsRedo() {
        var strokes: [DrawingStroke] = []
        var history = DrawingHistory()
        let a = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.05)], width: 0.01)
        let b = DrawingStroke(points: [NormalizedPoint(x: 0.05, y: 0.5)], width: 0.01)

        history.commit([a], to: &strokes)
        history.undo(&strokes)
        #expect(history.canRedo)

        history.commit([b], to: &strokes)
        #expect(!history.canRedo)
    }

    // MARK: - 지우개

    @Test("지우개는 반경 안의 획만 지운다")
    func eraserHitTest() {
        let stroke = DrawingStroke(
            points: [NormalizedPoint(x: 0.05, y: 0.20), NormalizedPoint(x: 0.05, y: 0.30)],
            width: 10 / MirrorCanvas.size.width
        )

        #expect(stroke.isHit(by: NormalizedPoint(x: 0.05, y: 0.20), radius: 20))
        #expect(!stroke.isHit(by: NormalizedPoint(x: 0.9, y: 0.9), radius: 20))
    }
}
