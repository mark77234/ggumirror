//
//  DoodleStickers.swift
//  ggumirror
//
//  손으로 그린 두들 스티커 한 벌. 꾸미러의 최종 기본 제공 스티커다.
//
//  스티커 하나 = **0…1 단위 상자 안의 점 몇 개**(`DoodleStroke`)뿐이다.
//  굵기 / 둥근 끝 / 여백은 `DoodleInk`가 한 곳에서 똑같이 입힌다 —
//  그래서 스티커를 더해도 "같은 사람이 같은 펜으로 그린" 결이 유지된다.
//
//  Reference에서 가져온 문법 (docs/DESIGN.md "Doodle Asset Visual Grammar"):
//  - 검은 잉크 단일 굵기, 자로 그은 직선 없음, 마주보는 변이 평행하지 않음
//  - 이음은 둥글지만 **모서리는 살아 있다**
//  - 채움은 아주 작은 강조에만. 기본은 outline
//  - 획 2~5개. 작아지면 실루엣으로 읽힌다
//  - 좌표는 **고정값**이다. render마다 흔들지 않는다 (hit target도 흔들리면 안 된다)
//
//  PNG로 굽지 않는다 — 스티커는 캔버스에서 크게도 작게도 쓰이므로
//  어느 배율에서나 같은 선이어야 한다. 렌더는 `MirrorRenderer`와 picker가 같은 함수를 쓴다.
//

import SwiftUI

// MARK: - 획

/// 0…1 단위 상자 안의 획 하나. y는 아래로 자란다.
enum DoodleStroke: Hashable {
    /// 부드럽게 이어지는 열린 선.
    case line([CGPoint])
    /// 부드럽게 이어지는 닫힌 모양.
    case loop([CGPoint])
    /// 각이 살아 있는 열린 선.
    case poly([CGPoint])
    /// 각이 살아 있는 닫힌 모양.
    case shape([CGPoint])
    /// 속을 채운 닫힌 모양(직선).
    case fill([CGPoint])
    /// 속을 채운 닫힌 모양(곡선).
    case blob([CGPoint])
    case circle(CGPoint, Double)
    /// 채운 원.
    case disc(CGPoint, Double)

    var isFilled: Bool {
        switch self {
        case .fill, .blob, .disc: true
        default: false
        }
    }

    /// 내부 디테일은 조금 얇게 그린다. 실루엣이 먼저 읽혀야 한다.
    var isDetail: Bool {
        switch self {
        case .line, .poly, .circle: true
        default: false
        }
    }

    func path(in rect: CGRect) -> Path {
        func scaled(_ points: [CGPoint]) -> [CGPoint] {
            points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        }
        func oval(_ center: CGPoint, _ radius: Double) -> Path {
            Path(ellipseIn: CGRect(
                x: rect.minX + (center.x - radius) * rect.width,
                y: rect.minY + (center.y - radius) * rect.height,
                width: radius * 2 * rect.width,
                height: radius * 2 * rect.height
            ))
        }

        switch self {
        case .line(let points): return Self.smooth(scaled(points), closed: false)
        case .loop(let points), .blob(let points): return Self.smooth(scaled(points), closed: true)
        case .poly(let points): return Self.straight(scaled(points), closed: false)
        case .shape(let points), .fill(let points): return Self.straight(scaled(points), closed: true)
        case .circle(let center, let radius), .disc(let center, let radius): return oval(center, radius)
        }
    }

    /// 직선으로 잇는다. 손그림 느낌은 둥근 이음이 낸다 —
    /// 모서리까지 곡선으로 만들면 상자가 콩처럼 보인다.
    private static func straight(_ points: [CGPoint], closed: Bool) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        if closed { path.closeSubpath() }
        return path
    }

    /// 점을 중점끼리 이어 곡선으로 만든다.
    private static func smooth(_ points: [CGPoint], closed: Bool) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        guard points.count > 2 else {
            path.move(to: points[0])
            path.addLine(to: points[1])
            return path
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        if closed {
            path.move(to: mid(points[points.count - 1], points[0]))
            for index in points.indices {
                let next = points[(index + 1) % points.count]
                path.addQuadCurve(to: mid(points[index], next), control: points[index])
            }
            path.closeSubpath()
        } else {
            path.move(to: points[0])
            for index in 1..<(points.count - 1) {
                path.addQuadCurve(to: mid(points[index], points[index + 1]), control: points[index])
            }
            path.addLine(to: points[points.count - 1])
        }
        return path
    }
}

/// 짧게 쓰기 위한 좌표 helper. 이 파일 안에서만 쓴다.
private func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

// MARK: - 펜

/// 두들 한 벌이 공유하는 펜. 굵기와 여백을 화면마다 다시 정하지 않는다.
enum DoodleInk {
    /// 상자 크기에 대한 바깥선 굵기 비율. Reference의 7~10% 구간을 따른다.
    static let outlineRatio = 0.075
    /// 내부 디테일은 조금 얇게.
    static let detailRatio = 0.055
    /// 아주 작게 그려도 선이 사라지지 않게 하는 최소 굵기.
    static let minimumWidth: CGFloat = 1.1

    static func width(for stroke: DoodleStroke, box: CGFloat) -> CGFloat {
        max(box * (stroke.isDetail ? detailRatio : outlineRatio), minimumWidth)
    }

    /// 스티커 · 제품 아이콘이 함께 쓰는 단 하나의 그리기 경로.
    /// `MirrorRenderer`(실제 거울 / Capture)와 picker 미리보기가 이 함수를 공유한다.
    static func draw(
        _ strokes: [DoodleStroke],
        in rect: CGRect,
        tint: Color,
        accent: Color? = nil,
        context: GraphicsContext
    ) {
        let box = min(rect.width, rect.height)
        for stroke in strokes {
            let path = stroke.path(in: rect)
            if stroke.isFilled {
                // 채움은 강조색이 있으면 그것으로. 없으면 잉크.
                context.fill(path, with: .color(accent ?? tint))
            } else {
                context.stroke(
                    path,
                    with: .color(tint),
                    style: StrokeStyle(
                        lineWidth: width(for: stroke, box: box),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
    }
}

// MARK: - 강조색

/// 두들에 쓰는 제한된 강조색. 무지개처럼 제각각인 팔레트를 쓰지 않는다.
/// 종이·잉크 위에서 튀지 않는 muted 계열만 둔다.
enum DoodleAccent: String, Hashable, Codable {
    case pink, red, blue, lavender, yellow

    var color: Color {
        switch self {
        case .pink: Color(red: 0.902, green: 0.643, blue: 0.667)
        case .red: Color(red: 0.812, green: 0.376, blue: 0.322)
        case .blue: Color(red: 0.639, green: 0.756, blue: 0.851)
        case .lavender: Color(red: 0.729, green: 0.702, blue: 0.859)
        case .yellow: Color(red: 0.933, green: 0.855, blue: 0.612)
        }
    }
}

// MARK: - 갈래

/// Sticker Picker의 갈래. 갈래 때문에 새 navigation을 만들지 않는다.
enum DoodleCategory: String, CaseIterable, Identifiable, Hashable {
    case all = "전체"
    case lovely = "러블리"
    case sparkle = "반짝"
    case diary = "다이어리"
    case fun = "재미"
    case symbol = "심볼"

    var id: String { rawValue }
}

// MARK: - 화면에 그리기

/// 두들 하나를 SwiftUI에서 그린다. picker 썸네일 · 레이어 목록이 쓴다.
/// **실제 거울과 같은 함수**(`DoodleInk.draw`)를 통과하므로 미리보기와 결과가 다르지 않다.
struct DoodleStickerView: View {
    let sticker: DoodleSticker
    var size: CGFloat = 34
    var tint: Color = PaperTheme.ink

    var body: some View {
        Canvas { context, canvasSize in
            let box = min(canvasSize.width, canvasSize.height)
            let rect = CGRect(
                x: (canvasSize.width - box) / 2,
                y: (canvasSize.height - box) / 2,
                width: box, height: box
            )
            DoodleInk.draw(
                sticker.strokes,
                in: rect,
                tint: sticker.supportsTint ? tint : PaperTheme.ink,
                accent: sticker.accent?.color,
                context: context
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview("두들 스티커") {
    ScrollView {
        VStack(spacing: 20) {
            ForEach(DoodleCategory.allCases.dropFirst()) { category in
                VStack(alignment: .leading, spacing: 10) {
                    Text(category.rawValue)
                        .font(InkFont.sectionTitle)
                        .foregroundStyle(PaperTheme.secondaryInk)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(DoodleSticker.all(in: category)) { sticker in
                            VStack(spacing: 4) {
                                DoodleStickerView(sticker: sticker, size: 34)
                                Text(sticker.title)
                                    .font(.system(size: 8))
                                    .foregroundStyle(PaperTheme.secondaryInk)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
    }
    .paperBackground()
}
