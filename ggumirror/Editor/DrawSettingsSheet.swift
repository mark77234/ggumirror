//
//  DrawSettingsSheet.swift
//  ggumirror
//
//  그리기 설정만 모아둔 시트. 도구 바에 색·굵기·브러시를 늘어놓지 않기 위해 분리했다.
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("그리기 설정")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)

            Picker("브러시", selection: $brush) {
                ForEach(EditorBrush.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: brush) { _, newValue in width = newValue.defaultWidth }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("굵기")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                    Spacer()
                    Text("\(Int((width * MirrorCanvas.size.width).rounded()))")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.ink)
                        .monospacedDigit()
                }
                Slider(value: $width, in: EditorBrush.widthRange)
                    .tint(PaperTheme.ink)
                    .accessibilityLabel("선 굵기")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("색")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)

                LazyVGrid(columns: columns, spacing: 12) {
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

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    DrawSettingsSheet(
        brush: .constant(.pen),
        width: .constant(EditorBrush.pen.defaultWidth),
        color: .constant(PaperTheme.ink)
    )
}
