//
//  EditorView.swift
//  ggumirror
//
//  Editor 기반. Overview ↔ Side Detail은 같은 Master Canvas를 보는 두 가지 방식이다.
//  Drawing / Sticker / Text는 Phase 3-2.
//

import SwiftUI

struct EditorView: View {
    @State var design: MirrorDesign
    var onSave: (MirrorDesign) -> Void

    @State private var mode: EditorMode = .overview
    /// Side Detail에서 실제로 보이는 영역. Mini Map이 이 값을 그린다.
    @State private var detailViewport = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
    @State private var isPreviewing = false
    @State private var isChoosingBackground = false
    @Environment(\.dismiss) private var dismiss

    enum EditorMode: Hashable {
        case overview
        case side(EditorSide)

        var side: EditorSide? {
            if case .side(let side) = self { side } else { nil }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            InkSeparator()

            switch mode {
            case .overview:
                overviewCanvas
            case .side(let side):
                SideDetailCanvas(design: design, side: side, visibleRect: $detailViewport)
            }

            InkSeparator()
            toolbar
        }
        .paperBackground()
        .fullScreenCover(isPresented: $isPreviewing) {
            EditorPreviewView(design: design)
        }
        .sheet(isPresented: $isChoosingBackground) {
            BackgroundColorSheet(color: $design.backgroundColor)
                .presentationDetents([.height(320), .medium])
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        switch mode {
        case .overview:
            HStack {
                Button("취소") { dismiss() }
                    .frame(minWidth: 44, minHeight: 44)

                Spacer()

                Text(design.name)
                    .font(InkFont.body.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Button("저장") {
                    onSave(design)
                    dismiss()
                }
                .font(InkFont.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
            }
            .foregroundStyle(PaperTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

        case .side(let side):
            HStack(spacing: 11) {
                EditorMiniMap(insets: design.insets, side: side, viewport: detailViewport)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(side.title) 프레임")
                        .font(InkFont.body.weight(.semibold))
                        .foregroundStyle(PaperTheme.ink)
                    Text("같은 거울의 \(side.title) 부분을 확대해서 보고 있어요")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("완료") {
                    withAnimation(.easeOut(duration: 0.2)) { mode = .overview }
                }
                .font(InkFont.body.weight(.semibold))
                .foregroundStyle(PaperTheme.ink)
                .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Overview

    private var overviewCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                MirrorCanvasView(design: design, showsBandGuides: true)

                // 네 밴드 전체가 tap target. 모서리는 45도로 나뉘어 겹치지 않는다.
                sideHitTargets
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private var sideHitTargets: some View {
        GeometryReader { geometry in
            let canvas = canvasRect(in: geometry.size)
            ForEach(EditorSide.allCases) { side in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { mode = .side(side) }
                } label: {
                    Color.clear
                }
                .frame(width: canvas.width, height: canvas.height)
                .contentShape(SideBandShape(side: side, insets: design.insets))
                .position(x: canvas.midX, y: canvas.midY)
                .accessibilityLabel("\(side.title) 프레임 편집")
            }
        }
    }

    /// 캔버스는 aspect fit으로 놓이므로 실제 그려진 사각형을 다시 계산한다.
    private func canvasRect(in size: CGSize) -> CGRect {
        let scale = min(size.width / MirrorCanvas.size.width, size.height / MirrorCanvas.size.height)
        let drawn = CGSize(
            width: MirrorCanvas.size.width * scale,
            height: MirrorCanvas.size.height * scale
        )
        return CGRect(
            x: (size.width - drawn.width) / 2,
            y: (size.height - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            toolbarButton("배경", icon: "paintpalette") { isChoosingBackground = true }
            toolbarButton("미리보기", icon: "eye") { isPreviewing = true }
            toolbarButton("저장", icon: "tray.and.arrow.down") {
                onSave(design)
                dismiss()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func toolbarButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(InkFont.body)
                Text(title)
                    .font(InkFont.caption)
            }
            .foregroundStyle(PaperTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background {
                let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
                shape
                    .fill(PaperTheme.subtleSurface)
                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.6))
            }
            .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - Side Detail

/// 같은 Master Canvas를 uniform scale + translation으로만 확대해서 보여준다.
/// 좌표계를 회전시키거나 side별 데이터를 새로 만들지 않는다.
private struct SideDetailCanvas: View {
    let design: MirrorDesign
    let side: EditorSide
    @Binding var visibleRect: NormalizedRect

    var body: some View {
        GeometryReader { proxy in
            let transform = SideDetailTransform(
                side: side,
                insets: design.insets,
                viewport: proxy.size
            )

            MirrorCanvasView(design: design, showsBandGuides: true)
                .frame(width: transform.canvasSize.width, height: transform.canvasSize.height)
                .offset(x: transform.offset.x, y: transform.offset.y)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
                .onChange(of: proxy.size, initial: true) { _, _ in
                    visibleRect = transform.visibleRect
                }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Background

private struct BackgroundColorSheet: View {
    @Binding var color: Color
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("배경 색")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(EditorBackground.options, id: \.name) { option in
                    Button {
                        color = option.color
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(option.color)
                                .frame(width: 40, height: 40)
                                .overlay(Circle().stroke(PaperTheme.ink, lineWidth: 1.6))
                            Text(option.name)
                                .font(InkFont.caption)
                                .foregroundStyle(PaperTheme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(InkPressStyle())
                    .accessibilityLabel(option.name)
                }
            }

            ColorPicker("직접 고르기", selection: $color, supportsOpacity: false)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .frame(minHeight: 44)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperBackground()
    }
}

// MARK: - Preview

/// Editor chrome 없이 거울 디자인만 확인한다. 카메라는 연결하지 않는다.
private struct EditorPreviewView: View {
    let design: MirrorDesign
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MirrorCanvasView(design: design)
                .padding(24)

            Button("닫기") { dismiss() }
                .font(InkFont.body.weight(.semibold))
                .foregroundStyle(PaperTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background {
                    Capsule().fill(PaperTheme.subtleSurface)
                        .overlay(Capsule().stroke(PaperTheme.ink, lineWidth: 1.6))
                }
                .padding(16)
        }
        .paperBackground()
    }
}

#Preview {
    EditorView(design: MirrorDesign(mirror: MirrorLibrary().mirrors[3]), onSave: { _ in })
}
