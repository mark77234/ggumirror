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

    /// 크기 조절 감도.
    ///
    /// 스티커는 폭 0.06...0.45(폭 0.39), 글자는 0.026...0.204(폭 0.178)로
    /// 값의 범위가 절반도 안 된다. 같은 계수를 쓰면 같은 거리를 끌어도
    /// 글자만 두 배 넘게 변해서 원하는 크기를 맞추기 어렵다.
    /// 범위 비율만큼 낮춰 스티커와 체감을 맞춘다.
    static let resizeSensitivity: Double = 0.45

    /// 앞뒤 공백을 정리하고 길이를 제한한다. 내용이 없으면 nil.
    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }
}

/// 거울에 넣는 글씨의 서체. **앱 UI 서체(`InkFont`)와는 별개**다.
///
/// rawValue가 그대로 저장되므로 **기존 case를 지우거나 이름을 바꾸지 않는다.**
/// basic / bold / serif / rounded는 예전에 저장된 텍스트가 쓰고 있어 계속 남긴다.
/// case가 늘어난 것뿐이라 저장 형식은 그대로다 — schemaVersion을 올리지 않는다.
enum TextFontStyle: String, CaseIterable, Identifiable, Hashable, Codable {
    // 예전 값 (지우지 말 것)
    case basic, bold, serif, rounded
    // 손글씨 라이브러리
    case gaeguLight, gaegu, gaeguBold
    case gamjaFlower, hiMelody, jua
    case nanumBrush, nanumPen, poorStory, singleDay

    var id: String { rawValue }

    /// 새로 고를 수 있는 목록. 예전 값(굵게 / 명조 / 둥근)은 계속 렌더되지만 새로 권하지 않는다.
    static let selectable: [TextFontStyle] = [
        .basic,
        .gaegu, .gaeguBold, .gaeguLight,
        .gamjaFlower, .hiMelody, .jua,
        .nanumBrush, .nanumPen, .poorStory, .singleDay,
    ]

    var title: String {
        switch self {
        case .basic: "기본"
        case .bold: "굵게"
        case .serif: "명조"
        case .rounded: "둥근"
        case .gaeguLight: "개구 가늘게"
        case .gaegu: "개구"
        case .gaeguBold: "개구 굵게"
        case .gamjaFlower: "감자꽃"
        case .hiMelody: "하이멜로디"
        case .jua: "주아"
        case .nanumBrush: "나눔붓"
        case .nanumPen: "나눔펜"
        case .poorStory: "푸어스토리"
        case .singleDay: "싱글데이"
        }
    }

    /// 번들 폰트 파일 이름. nil이면 시스템 폰트를 쓴다.
    var resource: String? {
        switch self {
        case .basic, .bold, .serif, .rounded: nil
        case .gaeguLight: "Gaegu-Light"
        case .gaegu: "Gaegu-Regular"
        case .gaeguBold: "Gaegu-Bold"
        case .gamjaFlower: "GamjaFlower-Regular"
        case .hiMelody: "HiMelody-Regular"
        case .jua: "Jua-Regular"
        case .nanumBrush: "NanumBrushScript-Regular"
        case .nanumPen: "NanumPenScript-Regular"
        case .poorStory: "PoorStory-Regular"
        case .singleDay: "SingleDay-Regular"
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
    /// 폰트 파일을 못 찾으면 시스템 한글 폰트로 떨어진다 — 글씨가 사라지지 않는다.
    func font(ofSize size: CGFloat) -> UIFont {
        if let resource {
            return MirrorFontLibrary.uiFont(resource: resource, size: size, fallbackWeight: weight)
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

/// 글꼴 고르기 화면의 묶음. 너무 잘게 나누지 않는다.
enum TextFontGroup: String, CaseIterable, Identifiable {
    case recommended = "추천"
    case handwriting = "손글씨"
    case emphasis = "강조"

    var id: String { rawValue }

    var styles: [TextFontStyle] {
        switch self {
        case .recommended: [.gaegu, .gamjaFlower, .nanumPen]
        case .handwriting: [.hiMelody, .poorStory, .singleDay, .nanumBrush, .gaeguLight]
        case .emphasis: [.jua, .gaeguBold]
        }
    }
}

enum TextAlignmentOption: String, CaseIterable, Identifiable, Hashable, Codable {
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
    /// tap target을 넓히는 것도 스티커와 같이 **제자리 tap에서만**이다.
    func contains(
        _ location: CGPoint,
        in transform: MirrorViewTransform,
        minimumTapTarget: CGFloat = TextObject.minimumTapTarget
    ) -> Bool {
        let rect = transform.rect(frame)
        let dx = location.x - rect.midX
        let dy = location.y - rect.midY
        let radians = -CGFloat(rotation) * .pi / 180
        let localX = dx * cos(radians) - dy * sin(radians)
        let localY = dx * sin(radians) + dy * cos(radians)

        let width = max(rect.width, minimumTapTarget)
        let height = max(rect.height, minimumTapTarget)
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

    /// 이 레이아웃이 어떤 캔버스 기준인가. 정규화 크기가 이 값을 본다.
    let canvas: CanvasKind

    var normalizedSize: CGSize {
        CGSize(
            width: size.width / canvas.size.width,
            height: size.height / canvas.size.height
        )
    }

    /// 글자 크기는 **캔버스 폭 기준 정규화 값**이라 캔버스가 바뀌면 픽셀 크기도 함께 바뀐다.
    /// 거울과 스티커가 같은 렌더 코드를 쓰되 결과 비율이 어긋나지 않게 하는 지점이다.
    static func of(_ object: TextObject, canvas: CanvasKind = .mirror) -> TextLayout {
        let pixelSize = CGFloat(object.fontSize) * canvas.size.width
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
            lineHeight: lineHeight,
            canvas: canvas
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
