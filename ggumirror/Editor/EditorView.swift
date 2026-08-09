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

    @State private var tool: EditorTool = .draw
    @State private var brush: EditorBrush = .pen
    @State private var brushWidth: Double = EditorBrush.pen.defaultWidth
    @State private var brushColor: Color = PaperTheme.ink
    @State private var history = DrawingHistory()
    /// Side별 보기 상태(zoom + pan). Editor session UI state이고 저장되지 않는다.
    @State private var viewports: [EditorSide: EditorViewportState] = [:]
    @State private var isEditingDrawSettings = false
    @State private var hintPulse = false
    /// 한 번 프레임을 눌러본 사용자에게는 다시 힌트를 보여주지 않는다.
    @AppStorage("editorSideHintSeen") private var hasSeenSideHint = false
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
                sideDetail(side)
            }

            InkSeparator()
            primaryToolBar
        }
        .paperBackground()
        .fullScreenCover(isPresented: $isPreviewing) {
            EditorPreviewView(design: design)
        }
        .sheet(isPresented: $isEditingDrawSettings) {
            DrawSettingsSheet(brush: $brush, width: $brushWidth, color: $brushColor)
                .presentationDetents([.height(380), .medium])
                .presentationBackground { PaperBackground() }
        }
        .sheet(isPresented: $isChoosingBackground) {
            BackgroundColorSheet(color: $design.backgroundColor)
                .presentationDetents([.height(320), .medium])
                .presentationBackground { PaperBackground() }
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
                MirrorCanvasView(
                    design: design,
                    showsBandGuides: true,
                    highlightsBands: !hasSeenSideHint
                )
                .opacity(hintPulse ? 0.92 : 1)

                // 네 밴드 전체가 tap target. 모서리는 45도로 나뉘어 겹치지 않는다.
                sideHitTargets

                if !hasSeenSideHint {
                    sideHint
                }
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
                    hasSeenSideHint = true
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

    /// 처음 들어온 사용자에게 무엇을 눌러야 하는지 알려준다.
    private var sideHint: some View {
        Text("꾸미고 싶은 프레임을 눌러보세요")
            .font(InkFont.caption)
            .foregroundStyle(PaperTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                UnevenRoundedRectangle.ink(15, 12, 16, 13)
                    .fill(PaperTheme.subtleSurface)
                    .overlay(
                        UnevenRoundedRectangle.ink(15, 12, 16, 13)
                            .stroke(PaperTheme.ink, lineWidth: 1.5)
                    )
            }
            .allowsHitTesting(false)
            .accessibilityLabel("꾸미고 싶은 프레임을 눌러보세요")
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

    // MARK: - Side Detail

    private func sideDetail(_ side: EditorSide) -> some View {
        SideDetailCanvas(
            design: design,
            side: side,
            tool: tool,
            brush: brush,
            brushWidth: brushWidth,
            brushColor: brushColor,
            viewport: viewportBinding(for: side),
            visibleRect: $detailViewport,
            onEdit: { history.apply($0, to: &design.strokes) }
        )
        .overlay(alignment: .topTrailing) { historyControls }
        .overlay(alignment: .bottomTrailing) { fitControl(side) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tool == .draw {
                drawContextBar
            }
        }
    }

    /// Undo / Redo는 그리기 설정과 분리된 작은 독립 컨트롤로 둔다.
    private var historyControls: some View {
        HStack(spacing: 6) {
            iconButton("실행 취소", icon: "arrow.uturn.backward", isEnabled: history.canUndo) {
                history.undo(&design.strokes)
            }
            iconButton("다시 실행", icon: "arrow.uturn.forward", isEnabled: history.canRedo) {
                history.redo(&design.strokes)
            }
        }
        .padding(10)
    }

    /// 위치를 잃었을 때 기본 fit 상태로 되돌린다.
    @ViewBuilder
    private func fitControl(_ side: EditorSide) -> some View {
        if !(viewports[side] ?? EditorViewportState()).isFitted {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { viewports[side] = EditorViewportState() }
            } label: {
                Label("맞춤", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background {
                        Capsule()
                            .fill(PaperTheme.subtleSurface)
                            .overlay(Capsule().stroke(PaperTheme.ink, lineWidth: 1.6))
                    }
                    .contentShape(.capsule)
            }
            .buttonStyle(InkPressStyle())
            .padding(10)
            .accessibilityLabel("보기 맞춤")
        }
    }

    /// 그리기일 때만 보이는 최소 설정 요약. 누르면 상세 시트가 열린다.
    private var drawContextBar: some View {
        Button {
            isEditingDrawSettings = true
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(brushColor)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(PaperTheme.ink, lineWidth: 1.4))
                Text(brush.title)
                    .font(InkFont.secondary)
                Text("\(Int((brushWidth * MirrorCanvas.size.width).rounded()))")
                    .font(InkFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(PaperTheme.secondaryInk)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(.system(.footnote, weight: .bold))
            }
            .foregroundStyle(PaperTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .background(PaperTheme.subtleSurface)
        .overlay(alignment: .top) { InkSeparator() }
        .accessibilityLabel("그리기 설정: \(brush.title), 색상, 굵기")
    }

    private func viewportBinding(for side: EditorSide) -> Binding<EditorViewportState> {
        Binding(
            get: { viewports[side] ?? EditorViewportState() },
            set: { viewports[side] = $0 }
        )
    }

    // MARK: - Primary tools

    /// 자주 바꾸는 큰 기능만. Undo/Redo와 색·굵기는 여기 넣지 않는다.
    private var primaryToolBar: some View {
        HStack(spacing: 10) {
            if mode.side != nil {
                ForEach(EditorTool.allCases) { item in
                    primaryButton(item.title, icon: item.icon, isActive: tool == item) {
                        tool = item
                    }
                }
            }
            primaryButton("배경", icon: "paintpalette") { isChoosingBackground = true }
            primaryButton("미리보기", icon: "eye") { isPreviewing = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func primaryButton(
        _ title: String,
        icon: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(InkFont.body)
                Text(title)
                    .font(InkFont.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? PaperTheme.subtleSurface : PaperTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background {
                let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
                shape
                    .fill(isActive ? PaperTheme.ink : PaperTheme.subtleSurface)
                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.6))
            }
            .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private func iconButton(
        _ label: String,
        icon: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(InkFont.body)
                .foregroundStyle(isEnabled ? PaperTheme.ink : PaperTheme.disabled)
                .frame(width: 44, height: 44)
                .background {
                    let shape = UnevenRoundedRectangle.ink(13, 16, 12, 15)
                    shape
                        .fill(PaperTheme.subtleSurface)
                        .overlay(shape.stroke(
                            isEnabled ? PaperTheme.ink : PaperTheme.disabled,
                            lineWidth: 1.6
                        ))
                }
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(label)
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
