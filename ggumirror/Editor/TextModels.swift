//
//  TextModels.swift
//  ggumirror
//
//  Text도 Drawing / Sticker와 같은 Master Canvas(1080 × 2340) normalized 좌표만 쓴다.
//  화면 pt는 모델에 저장하지 않는다.
//
//  글자 크기와 줄 배치는 Master Canvas 픽셀에서 한 번만 계산하고,
//  렌더러 / hit test / selection overlay가 **같은 계산 결과**를 쓴다.
//  화면마다 따로 재는 코드를 만들지 않는다.
//

import SwiftUI
import UIKit

// MARK: - 정책

enum TextPolicy {
    /// 한 오브젝트에 담을 수 있는 글자 수. 장식용이라 문단을 쓰는 도구가 아니다.
    static let maxLength = 100
    /// Master Canvas 폭 기준 normalized 글자 크기.
    static let fontSizeRange: ClosedRange<Double> = (28.0 / 1080.0)...(220.0 / 1080.0)
    static let defaultFontSize: Double = 96.0 / 1080.0
    /// 줄 간격 배수.
    static let lineSpacing: Double = 1.18

    /// 앞뒤 공백을 정리하고 길이를 제한한다. 내용이 없으면 nil.
    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }
}

/// 장식용 글꼴 preset. 새 폰트 파일을 넣지 않고 system font design만 쓴다.
/// 한글이 안정적으로 나오는 조합만 남겼다.
enum TextFontStyle: String, CaseIterable, Identifiable, Hashable {
    case basic, bold, serif, rounded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: "기본"
        case .bold: "굵게"
        case .serif: "명조"
        case .rounded: "둥근"
        }
    }

    var weight: UIFont.Weight {
        switch self {
        case .bold: .bold
        default: .regular
        }
    }

    var design: UIFontDescriptor.SystemDesign {
        switch self {
        case .serif: .serif
        case .rounded: .rounded
        default: .default
        }
    }

    /// 주어진 픽셀 크기의 실제 폰트. 측정과 렌더가 같은 값을 쓴다.
    func font(ofSize size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

enum TextAlignmentOption: String, CaseIterable, Identifiable, Hashable {
    case leading, center, trailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leading: "왼쪽"
        case .center: "가운데"
        case .trailing: "오른쪽"
        }
    }

    var icon: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }
}

// MARK: - Object

/// 사용자가 얹은 텍스트 하나.
/// 크기는 `fontSize` 하나로만 바뀐다 — 가로 / 세로를 따로 늘려 찌그러뜨리지 않는다.
struct TextObject: Identifiable, Hashable {
    var id = UUID()
    var text: String
    /// Master Canvas 기준 0...1 중심 좌표.
    var center: NormalizedPoint
    /// Master Canvas 폭 기준 normalized 글자 크기.
    var fontSize: Double = TextPolicy.defaultFontSize
    var style: TextFontStyle = .basic
    var alignment: TextAlignmentOption = .center
    var color: Color = PaperTheme.ink
    var rotation: Double = 0
    var opacity: Double = 1
    var zIndex: Int = 0
    var isLocked = false

    /// 손가락으로 다시 고를 수 있는 최소 크기(pt). 스티커와 같은 값을 쓴다.
    static let minimumTapTarget: CGFloat = StickerObject.minimumTapTarget

    /// 크기를 바꾼다. 중심과 종횡비(줄 배치)는 그대로 유지된다.
    func resized(fontSize newSize: Double) -> TextObject {
        var copy = self
        copy.fontSize = min(max(newSize, TextPolicy.fontSizeRange.lowerBound),
                            TextPolicy.fontSizeRange.upperBound)
        return copy
    }

    func moved(to point: NormalizedPoint) -> TextObject {
        var copy = self
        copy.center = point
        return copy
    }

    /// 캔버스 어디에나 놓을 수 있다 — 카메라 영역도 포함이다.
    /// 완전히 사라지지 않도록 중심만 Master Canvas 안에 붙잡는다.
    func constrained() -> TextObject {
        moved(to: NormalizedPoint(
            x: min(max(center.x, 0), 1),
            y: min(max(center.y, 0), 1)
        ))
    }

    /// 이 텍스트가 차지하는 Master Canvas 기준 사각형.
    var frame: NormalizedRect {
        let size = TextLayout.of(self).normalizedSize
        return NormalizedRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// 이 화면 좌표가 텍스트 위인지.
    /// 스티커와 같은 규칙 — 중심 기준 역회전 후 로컬 사각형 판정 + 최소 tap target.
    func contains(_ location: CGPoint, in transform: MirrorViewTransform) -> Bool {
        let rect = transform.rect(frame)
        let dx = location.x - rect.midX
        let dy = location.y - rect.midY
        let radians = -CGFloat(rotation) * .pi / 180
        let localX = dx * cos(radians) - dy * sin(radians)
        let localY = dx * sin(radians) + dy * cos(radians)

        let width = max(rect.width, Self.minimumTapTarget)
        let height = max(rect.height, Self.minimumTapTarget)
        return abs(localX) <= width / 2 && abs(localY) <= height / 2
    }
}

// MARK: - Layout

/// 줄 나눔과 크기를 Master Canvas 픽셀에서 한 번만 계산한다.
/// 렌더러 / hit test / selection overlay가 전부 이 결과를 공유한다.
struct TextLayout {
    let lines: [String]
    /// Master Canvas 픽셀 기준 각 줄 크기.
    let lineSizes: [CGSize]
    /// Master Canvas 픽셀 기준 전체 크기.
    let size: CGSize
    /// 줄 높이 (Master 픽셀).
    let lineHeight: CGFloat

    var normalizedSize: CGSize {
        CGSize(
            width: size.width / MirrorCanvas.size.width,
            height: size.height / MirrorCanvas.size.height
        )
    }

    static func of(_ object: TextObject) -> TextLayout {
        let pixelSize = CGFloat(object.fontSize) * MirrorCanvas.size.width
        let font = object.style.font(ofSize: pixelSize)
        let lines = object.text.isEmpty ? [""] : object.text.components(separatedBy: .newlines)

        let sizes = lines.map { line -> CGSize in
            (line as NSString).size(withAttributes: [.font: font])
        }
        let lineHeight = pixelSize * CGFloat(TextPolicy.lineSpacing)
        let width = sizes.map(\.width).max() ?? 0
        let height = lineHeight * CGFloat(lines.count)

        return TextLayout(
            lines: lines,
            lineSizes: sizes,
            size: CGSize(width: max(width, pixelSize * 0.4), height: height),
            lineHeight: lineHeight
        )
    }

    /// 블록 왼쪽 위를 (0,0)으로 봤을 때 각 줄의 시작 x. 정렬을 여기서 처리한다.
    func lineOrigin(_ index: Int, alignment: TextAlignmentOption) -> CGPoint {
        let lineWidth = lineSizes[index].width
        let x: CGFloat = switch alignment {
        case .leading: 0
        case .center: (size.width - lineWidth) / 2
        case .trailing: size.width - lineWidth
        }
        return CGPoint(x: x, y: CGFloat(index) * lineHeight)
    }
}

// MARK: - 배치

enum TextPlacement {
    /// 지금 보고 있는 화면 한가운데에 넣는다.
    /// 프레임이든 카메라 영역이든 사용자가 보고 있는 자리에 그대로 생긴다.
    static func insert(
        _ text: String,
        in design: MirrorDesign,
        visibleRect: NormalizedRect
    ) -> TextObject {
        let object = TextObject(
            text: text,
            center: NormalizedPoint(
                x: visibleRect.x + visibleRect.width / 2,
                y: visibleRect.y + visibleRect.height / 2
            ),
            zIndex: design.topDecorationZIndex + 1
        )
        return object.constrained()
    }
}
