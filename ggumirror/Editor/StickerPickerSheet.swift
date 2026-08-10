//
//  StickerPickerSheet.swift
//  ggumirror
//
//  기본 제공 스티커 고르기. 지금은 개발용 placeholder 세트다.
//  최종 hand-drawn asset library는 후속 Visual Content Polish에서 교체한다.
//

import SwiftUI

struct StickerPickerSheet: View {
    let onPick: (StickerSource) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("스티커")
                    .font(InkFont.caption.weight(.semibold))
                    .foregroundStyle(PaperTheme.secondaryInk)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(StickerSource.allCases) { source in
                        Button {
                            onPick(source)
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: source.symbolName)
                                    .font(.system(size: 34, weight: .light))
                                    .foregroundStyle(PaperTheme.ink)
                                    .frame(height: 44)
                                Text(source.title)
                                    .font(InkFont.caption)
                                    .foregroundStyle(PaperTheme.secondaryInk)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
                                shape
                                    .fill(PaperTheme.subtleSurface)
                                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.4))
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(InkPressStyle())
                        .accessibilityLabel(source.title)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

#Preview {
    StickerPickerSheet(onPick: { _ in })
        .paperBackground()
}
