//
//  ShapePickerSheet.swift
//  ggumirror
//
//  도형 / 꾸미기 요소 고르기. 스티커 고르기와 같은 디자인 언어를 쓴다.
//

import SwiftUI

struct ShapePickerSheet: View {
    let onPick: (ShapeKind) -> Void

    @State private var category: ShapeCategory = .all
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            InkFilterBar(items: ShapeCategory.allCases, selection: $category) { $0.rawValue }
                .padding(.top, 14)
                .padding(.bottom, 8)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ShapeKind.all(in: category)) { kind in
                        Button {
                            onPick(kind)
                        } label: {
                            VStack(spacing: 8) {
                                // 실제 렌더와 같은 path를 그대로 미리 보여준다.
                                ShapeKindPreview(kind: kind)
                                    .frame(height: 44)
                                Text(kind.title)
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
                        .accessibilityLabel(kind.title)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// Picker 썸네일. `ShapeKind.path`를 그대로 써서 실제 결과와 어긋나지 않는다.
private struct ShapeKindPreview: View {
    let kind: ShapeKind

    var body: some View {
        Canvas { context, size in
            let box = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
            let ratio = kind.defaultAspectRatio
            // 종류마다 비율이 달라 썸네일 안에 맞춰 넣는다.
            let width = min(box.width, box.height * ratio)
            let height = width / ratio
            let rect = CGRect(
                x: box.midX - width / 2, y: box.midY - height / 2,
                width: width, height: height
            )
            let path = kind.path(in: rect)

            if !kind.isStrokeOnly {
                context.fill(path, with: .color(PaperTheme.ink.opacity(0.12)))
            }
            context.stroke(
                path,
                with: .color(PaperTheme.ink),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ShapePickerSheet(onPick: { _ in })
        .paperBackground()
}
