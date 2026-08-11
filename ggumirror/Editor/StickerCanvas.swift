//
//  StickerCanvas.swift
//  ggumirror
//
//  스티커를 만드는 캔버스. **거울 캔버스와 다른 것은 크기와 바탕뿐이다.**
//
//  Editor 엔진(EditorSnapshot / EditorHistory / 제스처 / renderer)을 그대로 쓰기 위해
//  새 편집기를 만들지 않고 `CanvasKind` 하나만 더했다. 비율에 의존하는 계산
//  (스티커 높이 · 텍스트 레이아웃 · viewport 변환)만 이 값을 본다.
//

import SwiftUI

/// 지금 편집 중인 것이 거울인지 스티커인지.
enum CanvasKind: String, Hashable, Codable {
    /// 거울 한 장. 1080 × 2340, 프레임 + 카메라 영역이 있다.
    case mirror
    /// 스티커 한 장. **정사각 1024 × 1024, 배경이 없다.**
    case sticker

    var size: CGSize {
        switch self {
        case .mirror: MirrorCanvas.size
        case .sticker: StickerCanvas.size
        }
    }

    var aspectRatio: CGFloat { size.width / size.height }

    /// 바탕(프레임 색 · 종이 결 · 거울 면)을 그리는가.
    /// 스티커는 **투명해야 하므로 아무 바탕도 그리지 않는다.**
    var drawsBackground: Bool { self == .mirror }
}

/// 스티커 캔버스 규격. 최종 PNG도 이 크기다.
enum StickerCanvas {
    /// 논리 기준 캔버스. 정사각형이라 어느 앱에 붙여도 비율이 어긋나지 않는다.
    static let size = CGSize(width: 1024, height: 1024)
}

// MARK: - 투명 표시

/// 투명한 자리를 사용자가 알아볼 수 있게 하는 아주 옅은 체크무늬.
///
/// **최종 PNG에는 절대 들어가지 않는다** — 이건 편집 화면의 바탕이고,
/// 저장은 `StickerRenderer`가 완전히 투명한 컨텍스트에 따로 그린다.
/// 회색 체크가 강하면 종이·잉크 UI와 싸우므로 잉크를 아주 옅게만 쓴다.
struct TransparencyCheckerboard: View {
    /// 한 칸 크기(pt). 화면에서 무늬가 어지럽지 않을 만큼 크게 둔다.
    var cell: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(PaperTheme.paper))

            let columns = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for row in 0..<max(rows, 1) {
                for column in 0..<max(columns, 1) where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                            width: cell, height: cell
                        )),
                        // 아주 옅게. 잉크 선보다 눈에 먼저 들어오면 실패다.
                        with: .color(PaperTheme.ink.opacity(0.045))
                    )
                }
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}
