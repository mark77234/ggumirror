//
//  StickerCreatorView.swift
//  ggumirror
//
//  스티커 만들기 화면.
//
//  **새 편집기를 만들지 않았다.** 캔버스는 거울과 같은 `MirrorEditorCanvas`이고
//  캔버스 종류만 `.sticker`다(1024 × 1024, 바탕 없음). 도구 시트 · history ·
//  제스처 · 사진 배경 제거 · 두들 42종 · 텍스트 · 그리기 전부 기존 것을 그대로 쓴다.
//
//  저장하면 두 가지가 남는다:
//  1. 다시 편집할 수 있는 `StickerProject`(레이어 그대로)
//  2. 완전히 투명한 1024 × 1024 PNG
//

import PhotosUI
import SwiftUI

struct StickerCreatorView: View {
    /// 편집 중인 사본. 저장할 때만 라이브러리에 반영된다 —
    /// 취소하면 원본 프로젝트도 완성 PNG도 그대로다.
    @State var design: MirrorDesign
    var library: StickerLibrary
    var context: StickerSaveContext
    /// 처음 열 때 바로 사진을 고르게 할지.
    var startsWithPhoto = false
    var onSaved: () -> Void

    @State private var tool: EditorTool = .sticker
    @State private var drawingMode: DrawingInteractionMode = .draw
    @State private var brush: EditorBrush = .pen
    @State private var brushWidth: Double = EditorBrush.pen.defaultWidth
    @State private var brushColor: Color = PaperTheme.ink
    @State private var history = EditorHistory()

    @State private var viewport = EditorViewportState()
    @State private var visibleRect = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
    @State private var selectedStickerID: UUID?
    @State private var selectedTextID: UUID?
    @State private var selectedArtworkID: UUID?

    @State private var isPickingSticker = false
    @State private var isEditingText = false
    @State private var isAddingText = false
    @State private var draftText = ""
    @State private var isChoosingTextColor = false
    @State private var isChoosingTextFont = false
    @State private var isChoosingStickerColor = false
    @State private var isShowingLayers = false
    @State private var isEditingDrawSettings = false

    @State private var photoItem: PhotosPickerItem?
    @State private var photoTask: Task<Void, Never>?
    @State private var isMakingPhotoSticker = false
    @State private var photoFailure: String?

    @State private var isNaming = false
    @State private var draftName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            InkSeparator()
            canvas
            InkSeparator()
            toolBar
        }
        .paperBackground()
        .overlay { if isMakingPhotoSticker { photoProgress } }
        .onAppear {
            draftName = context.existingID == nil ? library.suggestedName : design.name
            if startsWithPhoto { isPickingPhoto = true }
        }
        .onDisappear {
            photoTask?.cancel()
            photoTask = nil
        }
        // 사진은 시스템 PhotosPicker 그대로 쓴다 — 흉내 내지 않는다.
        .photosPicker(isPresented: $isPickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            photoItem = nil
            makePhotoLayer(from: newValue)
        }
        .inkBottomSheet(isPresented: $isPickingSticker, size: .fraction(0.62)) {
            // 두들 42종을 그대로 쓴다. 카탈로그를 복사하지 않았다.
            StickerPickerSheet(
                onPick: { source in
                    addSticker(source)
                    isPickingSticker = false
                },
                showsPhotoEntry: false
            )
        }
        .inkBottomSheet(isPresented: $isEditingText) {
            TextInputSheet(text: $draftText, isNew: isAddingText) { commitText() }
        }
        .inkBottomSheet(isPresented: $isChoosingTextColor) {
            if let text = selectedText {
                StickerColorSheet(color: text.color) { color in
                    apply(text) { $0.color = color }
                }
            }
        }
        .inkBottomSheet(isPresented: $isChoosingTextFont, size: .fraction(0.72)) {
            if let text = selectedText {
                TextFontSheet(style: text.style) { style in
                    apply(text) { $0.style = style }
                }
            }
        }
        .inkBottomSheet(isPresented: $isChoosingStickerColor) {
            if let sticker = selectedSticker {
                StickerColorSheet(color: sticker.tintColor ?? PaperTheme.ink) { color in
                    apply(sticker) { $0.tintColor = color }
                }
            }
        }
        .inkBottomSheet(isPresented: $isShowingLayers, size: .fraction(0.72)) {
            LayersSheet(
                design: design,
                onReorder: { history.apply(.reorderDecorations(frontToBack: $0), to: &design.snapshot) },
                onSelect: { select($0) }
            )
        }
        .inkBottomSheet(isPresented: $isEditingDrawSettings, size: .fraction(0.66)) {
            DrawSettingsSheet(brush: $brush, width: $brushWidth, color: $brushColor)
        }
        .inkBottomSheet(isPresented: $isNaming) {
            MirrorNameSheet(name: $draftName, isNewMirror: true, onSave: { saveProject() })
        }
        .inkDialog(
            "사진에서 피사체를 찾지 못했어요",
            message: photoFailure,
            isPresented: Binding(get: { photoFailure != nil }, set: { if !$0 { photoFailure = nil } })
        ) {
            // 스티커는 배경 제거가 기본 정책이다 — 원본 그대로 넣는 길을 주지 않는다.
            [InkDialogAction("다시 고르기", role: .primary) { isPickingPhoto = true }, InkDialogAction("취소")]
        }
    }

    @State private var isPickingPhoto = false

    // MARK: - Header

    private var header: some View {
        HStack {
            // 취소는 원본을 건드리지 않는다. 사본에서만 작업했다.
            Button("취소") { dismiss() }
                .font(InkFont.body)
                .frame(minWidth: 44, minHeight: 44)

            Spacer(minLength: 8)

            Text("스티커 만들기")
                .font(InkFont.cardTitle)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("저장") { beginSave() }
                .font(InkFont.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .disabled(isEmpty)
        }
        .foregroundStyle(PaperTheme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// 아무것도 없는 스티커는 저장할 이유가 없다.
    private var isEmpty: Bool {
        design.strokes.isEmpty && design.stickers.isEmpty && design.texts.isEmpty
    }

    // MARK: - Canvas

    private var canvas: some View {
        MirrorEditorCanvas(
            design: design,
            tool: tool,
            drawingMode: drawingMode,
            brush: brush,
            brushWidth: brushWidth,
            brushColor: brushColor,
            viewport: $viewport,
            visibleRect: $visibleRect,
            selectedStickerID: $selectedStickerID,
            selectedTextID: $selectedTextID,
            selectedArtworkID: $selectedArtworkID,
            onEdit: { history.apply($0, to: &design.snapshot) }
        )
        .overlay(alignment: .topTrailing) { historyControls }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tool == .sticker, let sticker = selectedSticker {
                objectBar(
                    opacity: sticker.opacity,
                    onOpacity: { value in apply(sticker) { $0.opacity = value } },
                    showsColor: sticker.source.supportsTint,
                    onColor: { isChoosingStickerColor = true },
                    isLocked: sticker.isLocked,
                    onLock: { apply(sticker) { $0.isLocked.toggle() } },
                    onFlip: { apply(sticker) { $0.isFlippedHorizontally.toggle() } },
                    onDuplicate: { duplicate(sticker) },
                    onDelete: {
                        history.apply(.deleteSticker(sticker.id), to: &design.snapshot)
                        selectedStickerID = nil
                    },
                    onDone: { selectedStickerID = nil }
                )
            } else if tool == .text, let text = selectedText {
                objectBar(
                    opacity: text.opacity,
                    onOpacity: { value in apply(text) { $0.opacity = value } },
                    showsColor: true,
                    onColor: { isChoosingTextColor = true },
                    isLocked: text.isLocked,
                    onLock: { apply(text) { $0.isLocked.toggle() } },
                    onFont: { isChoosingTextFont = true },
                    onEditText: {
                        draftText = text.text
                        isAddingText = false
                        isEditingText = true
                    },
                    onDuplicate: { duplicate(text) },
                    onDelete: {
                        history.apply(.deleteText(text.id), to: &design.snapshot)
                        selectedTextID = nil
                    },
                    onDone: { selectedTextID = nil }
                )
            } else if tool == .draw {
                drawBar
            }
        }
        .onChange(of: tool) { _, newValue in
            if newValue != .sticker { selectedStickerID = nil }
            if newValue != .text { selectedTextID = nil }
            drawingMode = .draw
        }
    }

    private var historyControls: some View {
        HStack(spacing: 6) {
            iconButton("실행 취소", icon: "arrow.uturn.backward", isEnabled: history.canUndo) {
                history.undo(&design.snapshot)
            }
            iconButton("다시 실행", icon: "arrow.uturn.forward", isEnabled: history.canRedo) {
                history.redo(&design.snapshot)
            }
            iconButton("맞춤", icon: "arrow.up.left.and.down.right.magnifyingglass") {
                // 보기 상태만 바꾼다 — history에 넣지 않는다.
                viewport = EditorViewportState()
            }
        }
        .padding(10)
    }

    // MARK: - Tools

    private var toolBar: some View {
        HStack(spacing: 10) {
            toolButton("사진", icon: "photo") { isPickingPhoto = true }
            toolButton("그리기", icon: "scribble", isActive: tool == .draw) { tool = .draw }
            toolButton("스티커", icon: "heart", isActive: tool == .sticker) {
                tool = .sticker
                if selectedStickerID == nil { isPickingSticker = true }
            }
            toolButton("텍스트", icon: "textformat", isActive: tool == .text) {
                tool = .text
                if selectedTextID == nil { beginAddingText() }
            }
            toolButton("레이어", icon: "square.3.layers.3d") { isShowingLayers = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var drawBar: some View {
        HStack(spacing: 10) {
            ForEach(DrawingInteractionMode.allCases) { mode in
                Button {
                    drawingMode = mode
                } label: {
                    Image(systemName: mode.icon)
                        .font(InkFont.body)
                        .foregroundStyle(drawingMode == mode ? PaperTheme.paper : PaperTheme.ink)
                        .frame(width: 44, height: 40)
                        .background {
                            UnevenRoundedRectangle.ink(12, 9, 13, 10)
                                .fill(drawingMode == mode ? PaperTheme.ink : PaperTheme.subtleSurface)
                        }
                }
                .buttonStyle(InkPressStyle())
                .accessibilityLabel(mode.title)
            }

            Button {
                isEditingDrawSettings = true
            } label: {
                HStack(spacing: 8) {
                    StrokeSample(brush: brush, color: brushColor, width: brushWidth)
                        .frame(width: 40, height: 20)
                    Text(brush.title).font(InkFont.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up").font(.system(.footnote, weight: .bold))
                }
                .foregroundStyle(PaperTheme.ink)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(InkPressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(PaperTheme.subtleSurface)
        .overlay(alignment: .top) { InkSeparator() }
    }

    /// 선택한 오브젝트 컨트롤. 스티커와 텍스트가 같은 줄을 공유한다.
    private func objectBar(
        opacity: Double,
        onOpacity: @escaping (Double) -> Void,
        showsColor: Bool,
        onColor: @escaping () -> Void,
        isLocked: Bool,
        onLock: @escaping () -> Void,
        onFlip: (() -> Void)? = nil,
        onFont: (() -> Void)? = nil,
        onEditText: (() -> Void)? = nil,
        onDuplicate: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("투명도").font(InkFont.caption).foregroundStyle(PaperTheme.secondaryInk)
                Slider(value: Binding(get: { opacity }, set: onOpacity), in: 0.2...1)
                    .tint(PaperTheme.ink)
            }

            HStack(spacing: 8) {
                if showsColor { iconButton("색", icon: "paintpalette", action: onColor) }
                if let onFont { iconButton("글꼴", icon: "textformat", action: onFont) }
                if let onEditText { iconButton("내용 수정", icon: "square.and.pencil", action: onEditText) }
                if let onFlip { iconButton("뒤집기", icon: "arrow.left.and.right", action: onFlip) }
                iconButton(isLocked ? "잠금 해제" : "잠금", icon: isLocked ? "lock" : "lock.open", action: onLock)
                iconButton("복제", icon: "plus.square.on.square", action: onDuplicate)
                iconButton("삭제", icon: "trash", action: onDelete)
                Spacer(minLength: 0)
                Button("완료", action: onDone)
                    .font(InkFont.button)
                    .foregroundStyle(PaperTheme.ink)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(PaperTheme.subtleSurface)
        .overlay(alignment: .top) { InkSeparator() }
    }

    private func toolButton(
        _ title: String,
        icon: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(InkFont.body)
                Text(title).font(InkFont.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? PaperTheme.paper : PaperTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background {
                let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
                shape
                    .fill(isActive ? PaperTheme.ink : PaperTheme.subtleSurface)
                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.regular))
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
                            isEnabled ? PaperTheme.ink : PaperTheme.disabled, lineWidth: InkLine.regular
                        ))
                }
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private var photoProgress: some View {
        VStack(spacing: 12) {
            ProgressView().tint(PaperTheme.ink)
            Text("사진을 스티커로 만드는 중...")
                .font(InkFont.secondary)
                .foregroundStyle(PaperTheme.ink)
        }
        .padding(24)
        .background { InkCorner.card.fill(PaperTheme.paper) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperTheme.ink.opacity(0.2))
    }

    // MARK: - 사진

    /// 배경 제거는 Mirror Photo Sticker와 **같은 함수**를 쓴다 (`PhotoStickerMaker`).
    /// 스티커 전용으로 복사하지 않았다.
    private func makePhotoLayer(from item: PhotosPickerItem) {
        photoTask?.cancel()
        isMakingPhotoSticker = true
        photoTask = Task {
            defer { isMakingPhotoSticker = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw PhotoStickerError.unreadable
                }
                try Task.checkCancellation()
                let image = try await PhotoStickerMaker.makeSticker(from: data)
                try Task.checkCancellation()
                addSticker(PhotoStickerAssetStore.shared.register(image))
            } catch is CancellationError {
                return
            } catch {
                // 스티커는 배경 제거가 기본이라 원본 그대로 넣지 않는다.
                photoFailure = "배경을 지우지 못했어요. 피사체가 뚜렷한 사진을 골라 주세요."
            }
        }
    }

    // MARK: - 편집

    private func addSticker(_ source: StickerSource) {
        let sticker = StickerPlacement.insert(source, in: design, visibleRect: visibleRect)
        history.apply(.addSticker(sticker), to: &design.snapshot)
        tool = .sticker
        selectedStickerID = sticker.id
    }

    private func beginAddingText() {
        draftText = ""
        isAddingText = true
        isEditingText = true
    }

    private func commitText() {
        guard let text = TextPolicy.normalized(draftText) else { return }
        if isAddingText {
            let object = TextPlacement.insert(text, in: design, visibleRect: visibleRect)
            history.apply(.addText(object), to: &design.snapshot)
            selectedTextID = object.id
        } else if let selected = selectedText {
            var updated = selected
            updated.text = text
            history.apply(.replaceText(updated), to: &design.snapshot)
        }
    }

    private var selectedSticker: StickerObject? {
        guard let selectedStickerID else { return nil }
        return design.stickers.first { $0.id == selectedStickerID }
    }

    private var selectedText: TextObject? {
        guard let selectedTextID else { return nil }
        return design.texts.first { $0.id == selectedTextID }
    }

    private func apply(_ sticker: StickerObject, _ change: (inout StickerObject) -> Void) {
        var updated = sticker
        change(&updated)
        history.apply(.replaceSticker(updated.constrained()), to: &design.snapshot)
    }

    private func apply(_ text: TextObject, _ change: (inout TextObject) -> Void) {
        var updated = text
        change(&updated)
        history.apply(.replaceText(updated.constrained()), to: &design.snapshot)
    }

    /// 복제는 Editor와 같은 규칙이다 — 새 id, 맨 위 zIndex, 살짝 옆으로.
    private func duplicate(_ sticker: StickerObject) {
        var copy = sticker
        copy.id = UUID()
        copy.zIndex = (design.stickers.map(\.zIndex).max() ?? 0) + 1
        copy.frame = NormalizedRect(
            x: sticker.frame.x + 0.02, y: sticker.frame.y + 0.02,
            width: sticker.frame.width, height: sticker.frame.height
        )
        copy = copy.constrained()
        history.apply(.addSticker(copy), to: &design.snapshot)
        selectedStickerID = copy.id
    }

    private func duplicate(_ text: TextObject) {
        var copy = text
        copy.id = UUID()
        copy.zIndex = (design.texts.map(\.zIndex).max() ?? 0) + 1
        copy.center = NormalizedPoint(x: text.center.x + 0.02, y: text.center.y + 0.02)
        copy = copy.constrained()
        history.apply(.addText(copy), to: &design.snapshot)
        selectedTextID = copy.id
    }

    private func select(_ layer: DecorationLayer) {
        switch layer {
        case .sticker(let object):
            tool = .sticker
            selectedTextID = nil
            selectedStickerID = object.id
        case .text(let object):
            tool = .text
            selectedStickerID = nil
            selectedTextID = object.id
        case .importedArtwork:
            break   // 스티커 캔버스에는 외부 디자인이 없다
        }
    }

    // MARK: - 저장

    private func beginSave() {
        // 편집이면 이름을 다시 묻지 않는다 — 같은 스티커를 고치는 것이다.
        if context.existingID != nil {
            saveProject()
        } else {
            isNaming = true
        }
    }

    private func saveProject() {
        library.save(design, name: draftName, context: context)
        onSaved()
        dismiss()
    }
}
