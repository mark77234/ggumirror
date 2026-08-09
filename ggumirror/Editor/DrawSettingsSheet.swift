//
//  DrawSettingsSheet.swift
//  ggumirror
//
//  그리기 설정만 모아둔 시트. 도구 바에 색·굵기·브러시를 늘어놓지 않기 위해 분리했다.
//  종이 질감 연필 / 크레용 같은 texture brush는 후속 Advanced Drawing Phase.
//

import SwiftUI

struct DrawSettingsSheet: View {
    @Binding var brush: EditorBrush
    @Binding var width: Double
    @Binding var color: Color

    private static let palette: [Color] = [
        PaperTheme.ink,
        Color(red: 0.78, green: 0.31, blue: 0.33),
        Color(red: 0.36, green: 0.47, blue: 0.71),
        Color(red: 0.44, green: 0.60, blue: 0.47),
        Color(red: 0.85, green: 0.68, blue: 0.32),
        Color(red: 0.62, green: 0.45, blue: 0.71)
    ]

    private let swatchColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("그리기 도구") {
                    VStack(spacing: 8) {
                        ForEach(EditorBrush.allCases) { item in
                            ToolPresetRow(
                                brush: item,
                                color: color,
                                isSelected: item == brush
                            ) {
                                brush = item
                                width = item.defaultWidth
                            }
                        }
                    }
                }

                section("굵기") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            StrokeSample(brush: brush, color: color, width: width)
                                .frame(height: 22)
                            Spacer(minLength: 12)
                            Text("\(Int((width * MirrorCanvas.size.width).rounded()))")
                                .font(InkFont.caption)
                                .foregroundStyle(PaperTheme.ink)
                                .monospacedDigit()
                        }
                        Slider(value: $width, in: EditorBrush.widthRange)
                            .tint(PaperTheme.ink)
                            .accessibilityLabel("선 굵기")
                    }
                }

                section("색상") {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: swatchColumns, spacing: 12) {
                            ForEach(Self.palette, id: \.self) { swatch in
                                Button {
                                    color = swatch
                                } label: {
                                    Circle()
                                        .fill(swatch)
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle().stroke(
                                                PaperTheme.ink,
                                                lineWidth: swatch == color ? 2.8 : 1.4
                                            )
                                        )
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(.circle)
                                }
                                .buttonStyle(InkPressStyle())
                                .accessibilityLabel("색 선택")
                            }
                        }

                        ColorPicker("직접 고르기", selection: $color, supportsOpacity: false)
                            .font(InkFont.body)
                            .foregroundStyle(PaperTheme.ink)
                            .frame(minHeight: 44)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(InkFont.caption.weight(.semibold))
                .foregroundStyle(PaperTheme.secondaryInk)
            content()
        }
    }
}

/// 도구 한 줄. 실제 선 모양을 미리 보여줘 이름만 읽지 않아도 차이를 알 수 있다.
private struct ToolPresetRow: View {
    let brush: EditorBrush
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                StrokeSample(brush: brush, color: color, width: brush.defaultWidth)
                    .frame(width: 76, height: 24)

                Text(brush.title)
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(PaperTheme.ink)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background {
                let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
                shape
                    .fill(isSelected ? PaperTheme.pressed : PaperTheme.subtleSurface)
                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: isSelected ? 2 : 1.4))
            }
            .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel(brush.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// 실제 렌더러와 같은 규칙으로 그린 짧은 선 미리보기.
struct StrokeSample: View {
    let brush: EditorBrush
    let color: Color
    let width: Double

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 4, y: size.height * 0.72))
            path.addQuadCurve(
                to: CGPoint(x: size.width - 4, y: size.height * 0.32),
                control: CGPoint(x: size.width * 0.5, y: -size.height * 0.15)
            )
            context.stroke(
                path,
                with: .color(color.opacity(brush.opacity)),
                style: StrokeStyle(
                    lineWidth: min(width * MirrorCanvas.size.width * 0.55, size.height * 0.9),
                    lineCap: brush.lineCap,
                    lineJoin: .round
                )
            )
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    DrawSettingsSheet(
        brush: .constant(.pen),
        width: .constant(EditorBrush.pen.defaultWidth),
        color: .constant(PaperTheme.ink)
    )
    .paperBackground()
}
