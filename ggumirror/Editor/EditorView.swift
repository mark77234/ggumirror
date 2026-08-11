//
//  EditorView.swift
//  ggumirror
//
//  거울 한 장 전체를 자유롭게 꾸미는 편집기.
//  상/하/좌/우를 고르는 단계는 없다 — 카메라 영역을 포함한 캔버스 전체가 편집 대상이다.
//

import PhotosUI
import SwiftUI

struct EditorView: View {
    @State var design: MirrorDesign
    /// 저장 정책(제자리 갱신 / 새 거울 / 슬롯 제한)을 위해 라이브러리를 직접 본다.
    var library: MirrorLibrary
    /// 어디서 들어왔는가. 저장이 갱신인지 새 거울인지를 이 값이 정한다.
    var context: MirrorEditorContext
    var onSaved: () -> Void

    /// 지금 화면에 보이는 Master 영역. 새 스티커를 여기 중앙에 넣는다.
    @State private var visibleRect = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
    @State private var isPreviewing = false
    @State private var isChoosingBackground = false

    @State private var tool: EditorTool = .draw
    /// 그리기 도구의 한 손가락 동작. 붓 / 색 / 굵기를 바꿔도 이 값은 유지된다.
    @State private var drawingMode: DrawingInteractionMode = .draw
    @State private var brush: EditorBrush = .pen
    @State private var brushWidth: Double = EditorBrush.pen.defaultWidth
    @State private var brushColor: Color = PaperTheme.ink
    @State private var history = EditorHistory()
    @State private var isPickingSticker = false
    @State private var selectedStickerID: UUID?
    @State private var isChoosingStickerColor = false
    @State private var selectedTextID: UUID?
    @State private var isEditingText = false
    @State private var isChoosingTextColor = false
    @State private var isChoosingTextFont = false
    @State private var draftText = ""
    /// 시트가 새 텍스트를 만드는 중인지, 기존 내용을 고치는 중인지.
    @State private var isAddingText = false
    @State private var isShowingLayers = false
    /// 외부 디자인 선택. 캔버스를 눌러서는 고를 수 없고 Layers 목록으로만 고른다.
    @State private var selectedArtworkID: UUID?
    @State private var isReplacingArtwork = false
    @State private var isNamingMirror = false
    @State private var draftName = ""
    @State private var showsSlotFull = false
    /// 진입 시 context를 그대로 들고 있다가, 새 거울을 만든 뒤에는 그 거울 편집으로 바뀐다.
    @State private var saveContext: MirrorEditorContext = .editCurrent
    /// 사진 → 스티커 변환. 한 번에 하나만 돌고, 화면을 벗어나면 취소된다.
    @State private var photoTask: Task<Void, Never>?
    @State private var isMakingPhotoSticker = false
    @State private var photoFallback: PhotoStickerFallback?
    /// 보기 상태(zoom + pan). Editor session UI state이고 저장되지 않는다.
    @State private var viewport = EditorViewportState()
    @State private var isEditingDrawSettings = false
    /// 내가 만드는 스티커. 이번 Phase에서는 Creator로 들어가는 문만 있다.
    @State private var stickerLibrary = StickerLibrary.live
    @State private var isChoosingStickerStart = false
    @State private var creatorRequest: StickerCreatorRequest?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            InkSeparator()
            canvas
            InkSeparator()
            primaryToolBar
        }
        .paperBackground()
        .onAppear { saveContext = context }
        .fullScreenCover(isPresented: $isPreviewing) {
            EditorPreviewView(design: design)
        }
        .inkBottomSheet(isPresented: $isNamingMirror) {
            MirrorNameSheet(
                name: $draftName,
                isNewMirror: true,
                onSave: { saveMirror() }
            )
        }
        .inkDialog(
            "거울 보관 공간이 가득 찼어요",
            message: "새 거울을 저장하려면 보관 공간을 늘려주세요. 보관 공간 확장은 준비 중이에요.",
            isPresented: $showsSlotFull
        ) {
            [
                InkDialogAction("취소"),
                InkDialogAction("보관 공간 늘리기", role: .primary),
            ]
        }
        .inkBottomSheet(isPresented: $isChoosingStickerColor) {
            if let sticker = selectedSticker {
                StickerColorSheet(
                    color: sticker.tintColor ?? PaperTheme.ink,
                    onPick: { color in
                        apply(sticker) { $0.tintColor = color }
                    }
                )
            }
        }
        .inkBottomSheet(isPresented: $isPickingSticker, size: .fraction(0.62)) {
            StickerPickerSheet(
                onPick: { source in
                    addSticker(source)
                    isPickingSticker = false
                },
                onPickPhoto: { item in
                    isPickingSticker = false
                    makePhotoSticker(from: item)
                },
                onCreateSticker: {
                    isPickingSticker = false
                    isChoosingStickerStart = true
                },
                stickers: stickerLibrary,
                onPickUserSticker: { source in
                    // 배치 시점의 불변 스냅샷이 넘어온다. 사진 스티커와 같은 경로로 놓인다.
                    addSticker(source)
                    isPickingSticker = false
                }
            )
        }
        .overlay {
            if isMakingPhotoSticker { photoProgress }
        }
        .inkDialog(
            "사진에서 피사체를 찾지 못했어요",
            message: "배경을 지우지 못했어요. 다른 사진을 고르거나 원본을 그대로 넣을 수 있어요.",
            isPresented: Binding(get: { photoFallback != nil }, set: { if !$0 { photoFallback = nil } })
        ) {
            // 버튼을 누르기 전에 값을 잡아 둔다 — 닫히면서 photoFallback이 비워진다.
            let fallback = photoFallback
            return [
                InkDialogAction("다시 고르기", role: .primary) { isPickingSticker = true },
                InkDialogAction("원본 그대로 넣기") {
                    guard let fallback else { return }
                    addOriginalPhoto(fallback)
                },
                InkDialogAction("취소"),
            ]
        }
        // Editor를 떠나면 진행 중인 변환을 정리한다.
        .onDisappear {
            photoTask?.cancel()
            photoTask = nil
        }
        .inkBottomSheet(isPresented: $isReplacingArtwork, size: .fraction(0.9)) {
            ExternalArtworkView(showsGuide: false, onUse: { replaceArtwork($0) })
        }
        .inkBottomSheet(isPresented: $isShowingLayers, size: .fraction(0.72)) {
            LayersSheet(
                design: design,
                onReorder: { history.apply(.reorderDecorations(frontToBack: $0), to: &design.snapshot) },
                onSelect: { select($0) }
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
        .inkBottomSheet(isPresented: $isEditingDrawSettings, size: .fraction(0.66)) {
            DrawSettingsSheet(brush: $brush, width: $brushWidth, color: $brushColor)
        }
        .inkBottomSheet(isPresented: $isChoosingBackground) {
            BackgroundColorSheet(color: $design.backgroundColor)
        }
        // 스티커 만들기: 빈 캔버스 / 사진으로 시작. 커스텀 다이얼로그를 쓴다.
        .inkDialog(
            "스티커 만들기",
            message: "빈 캔버스에서 그리거나, 사진에서 배경을 지워 시작할 수 있어요.",
            isPresented: $isChoosingStickerStart
        ) {
            [
                InkDialogAction("빈 캔버스에서 만들기", role: .primary) {
                    creatorRequest = StickerCreatorRequest(startsWithPhoto: false)
                },
                InkDialogAction("사진으로 시작하기") {
                    creatorRequest = StickerCreatorRequest(startsWithPhoto: true)
                },
                InkDialogAction("취소"),
            ]
        }
        .fullScreenCover(item: $creatorRequest) { request in
            StickerCreatorView(
                design: .blankSticker(id: UUID().uuidString, name: stickerLibrary.suggestedName),
                library: stickerLibrary,
                context: .createNew,
                startsWithPhoto: request.startsWithPhoto,
                onSaved: {
                    creatorRequest = nil
                    // 만들고 나면 picker의 "내 스티커"로 돌아온다 — 방금 만든 것이 맨 앞에 있다.
                    isPickingSticker = true
                }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("취소") { dismiss() }
                .frame(minWidth: 44, minHeight: 44)

            Spacer()

            Text("거울 꾸미기")
                .font(InkFont.body.weight(.semibold))
                .lineLimit(1)

            Spacer()

            Button("저장") { beginSave() }
                .font(InkFont.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .foregroundStyle(PaperTheme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
        .overlay(alignment: .bottomTrailing) { fitControl }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let artwork = selectedArtwork {
                artworkContextBar(artwork)
            } else if tool == .sticker, let sticker = selectedSticker {
                stickerContextBar(sticker)
            } else if tool == .text, let text = selectedText {
                textContextBar(text)
            } else if tool == .draw {
                drawContextBar
            }
        }
        .onChange(of: tool) { _, newValue in
            if newValue != .sticker { selectedStickerID = nil }
            if newValue != .text { selectedTextID = nil }
            selectedArtworkID = nil
            // 그리기를 나갔다 들어오면 항상 그리기부터. 손바닥에 갇혀 있지 않게 한다.
            drawingMode = .draw
        }
    }

    /// Undo / Redo는 그리기 설정과 분리된 작은 독립 컨트롤로 둔다.
    private var historyControls: some View {
        HStack(spacing: 6) {
            iconButton("실행 취소", icon: "arrow.uturn.backward", isEnabled: history.canUndo) {
                history.undo(&design.snapshot)
            }
            iconButton("다시 실행", icon: "arrow.uturn.forward", isEnabled: history.canRedo) {
                history.redo(&design.snapshot)
            }
        }
        .padding(10)
    }

    /// 위치를 잃었을 때 거울 한 장이 전부 보이는 상태로 되돌린다.
    @ViewBuilder
    private var fitControl: some View {
        if !viewport.isFitted {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { viewport = EditorViewportState() }
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

    /// 그리기일 때만 보이는 최소 설정 요약 + 그리기 / 손바닥 전환.
    /// 손이 가장 잘 닿는 캔버스 바로 아래에 둔다 — 별도 카드나 모달을 띄우지 않는다.
    private var drawContextBar: some View {
        HStack(spacing: 10) {
            drawingModeControl

            Button {
                isEditingDrawSettings = true
            } label: {
                HStack(spacing: 10) {
                    StrokeSample(brush: brush, color: brushColor, width: brushWidth)
                        .frame(width: 40, height: 20)
                    Circle()
                        .fill(brushColor)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(PaperTheme.ink, lineWidth: 1.4))
                    Text(brush.title)
                        .font(InkFont.secondary)
                        .lineLimit(1)
                    Text("\(Int((brushWidth * MirrorCanvas.size.width).rounded()))")
                        .font(InkFont.caption)
                        .monospacedDigit()
                        .foregroundStyle(PaperTheme.secondaryInk)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(.system(.footnote, weight: .bold))
                }
                .foregroundStyle(PaperTheme.ink)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(InkPressStyle())
            .accessibilityLabel("그리기 설정: \(brush.title), 색상, 굵기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PaperTheme.subtleSurface)
        .overlay(alignment: .top) { InkSeparator() }
    }

    /// 지금 한 손가락이 무엇을 하는지 한눈에 보이는 잉크 컨트롤.
    private var drawingModeControl: some View {
        HStack(spacing: 0) {
            ForEach(DrawingInteractionMode.allCases) { mode in
                drawingModeButton(mode)
            }
        }
        .padding(2)
        .background {
            let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
            // **fill을 반드시 준다.** 채우지 않은 Shape는 상속된 foreground(시스템 primary)로
            // 칠해져서, 라이트 모드에서 검은 배경 + 검은 아이콘이 되어 컨트롤이 사라졌다.
            // 꾸미러는 시스템 appearance를 따르지 않는다 — 고정된 종이/잉크 색만 쓴다.
            shape
                .fill(PaperTheme.subtleSurface)
                .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.regular))
        }
    }

    private func drawingModeButton(_ mode: DrawingInteractionMode) -> some View {
        let isActive = drawingMode == mode
        return Button {
            drawingMode = mode
            EditorHaptics.placementConfirmed()
        } label: {
            Image(systemName: mode.icon)
                .font(InkFont.body)
                // 선택 = 잉크 면 + 종이색 아이콘 / 비선택 = 종이 면 + 잉크 아이콘.
                // 두 조합 모두 대비가 크고, 시스템 다크 모드 설정과 무관하게 늘 같다.
                .foregroundStyle(isActive ? PaperTheme.paper : PaperTheme.ink)
                .frame(width: 44, height: 40)
                .background {
                    UnevenRoundedRectangle.ink(12, 9, 13, 10)
                        .fill(isActive ? PaperTheme.ink : PaperTheme.subtleSurface)
                }
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    /// 내 거울에서 새 결과물을 만들 때만 이름을 묻는다.
    private func beginSave() {
        guard library.needsName(for: saveContext) else {
            // 홈에서 들어왔으면 이름을 묻지 않는다. 새로 만들어야 하면 자동 이름이 붙는다.
            saveMirror()
            return
        }
        // 복제로 들어왔으면 원본 이름을 바탕으로 채워두고, 사용자가 고칠 수 있게 한다.
        draftName = saveContext == .duplicate ? "\(design.name) 복사본" : design.name
        isNamingMirror = true
    }

    private func saveMirror() {
        switch library.save(design, name: draftName, context: saveContext) {
        case .updated:
            isNamingMirror = false
            onSaved()
            dismiss()
        case .created(let id, let name):
            isNamingMirror = false
            // 방금 만든 거울을 기억한다. 같은 Editor에서 다시 저장하면 이 거울을 갱신한다.
            design.id = id
            design.name = name
            saveContext = .editCurrent
            onSaved()
            dismiss()
        case .needsMoreSlots:
            isNamingMirror = false
            if !library.hasFreeCreatedSlot { showsSlotFull = true }
        }
    }

    // MARK: - 사진 스티커

    /// 배경 제거에 실패했을 때 되돌아갈 자리. 원본 데이터는 여기에만 잠깐 머문다.
    private struct PhotoStickerFallback: Identifiable {
        let id = UUID()
        let data: Data
    }

    private var photoProgress: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(PaperTheme.ink)
            Text("사진을 스티커로 만드는 중...")
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background {
            let shape = UnevenRoundedRectangle.ink(18, 15, 19, 16)
            shape
                .fill(PaperTheme.subtleSurface)
                .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperTheme.ink.opacity(0.12))
        // 처리 중에는 캔버스를 건드리지 못하게 한다.
        .contentShape(.rect)
        .accessibilityElement()
        .accessibilityLabel("사진을 스티커로 만드는 중")
    }

    /// 고른 사진을 기기 안에서 배경 제거해 스티커로 넣는다. 네트워크를 쓰지 않는다.
    private func makePhotoSticker(from item: PhotosPickerItem) {
        // 연속으로 고르면 앞의 작업은 버린다.
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
                // 실패해도 앱은 그대로. 사용자가 다음 동작을 고른다.
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photoFallback = PhotoStickerFallback(data: data)
                }
            }
        }
    }

    /// 배경 제거 없이 축소한 원본만 넣는다.
    private func addOriginalPhoto(_ fallback: PhotoStickerFallback) {
        photoFallback = nil
        guard let image = try? PhotoStickerMaker.makeOriginal(from: fallback.data) else { return }
        addSticker(PhotoStickerAssetStore.shared.register(image))
    }

    /// 지금 보고 있는 화면 한가운데에 넣는다.
    private func addSticker(_ source: StickerSource) {
        let sticker = StickerPlacement.insert(source, in: design, visibleRect: visibleRect)
        history.apply(.addSticker(sticker), to: &design.snapshot)
        selectedStickerID = sticker.id
    }

    private var selectedSticker: StickerObject? {
        guard let selectedStickerID else { return nil }
        return design.stickers.first { $0.id == selectedStickerID }
    }

    /// 스티커를 선택했을 때만 보이는 전용 컨트롤. 그리기 설정과 동시에 뜨지 않는다.
    private func stickerContextBar(_ sticker: StickerObject) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("투명도")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                Slider(
                    value: Binding(
                        get: { sticker.opacity },
                        set: { update(sticker) { $0.opacity = $1 } ($0) }
                    ),
                    in: 0.1...1
                )
                .tint(PaperTheme.ink)
                .disabled(sticker.isLocked)
                .accessibilityLabel("스티커 투명도")
            }

            HStack(spacing: 8) {
                if sticker.source.supportsTint {
                    Button {
                        isChoosingStickerColor = true
                    } label: {
                        Circle()
                            .fill(sticker.tintColor ?? PaperTheme.ink)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(PaperTheme.ink, lineWidth: 1.4))
                            .frame(width: 44, height: 44)
                            .contentShape(.circle)
                    }
                    .buttonStyle(InkPressStyle())
                    .disabled(sticker.isLocked)
                    .accessibilityLabel("스티커 색상")
                }
                iconButton("복제", icon: "plus.square.on.square") { duplicate(sticker) }
                iconButton("뒤집기", icon: "arrow.left.and.right",
                           isEnabled: !sticker.isLocked) {
                    apply(sticker) { $0.isFlippedHorizontally.toggle() }
                }
                iconButton(sticker.isLocked ? "잠금 해제" : "잠금",
                           icon: sticker.isLocked ? "lock" : "lock.open") {
                    apply(sticker) { $0.isLocked.toggle() }
                }
                iconButton("삭제", icon: "trash") {
                    history.apply(.deleteSticker(sticker.id), to: &design.snapshot)
                    selectedStickerID = nil
                }

                Spacer(minLength: 0)

                // 배치를 마치고 다음 작업으로 넘어가는 가장 눈에 띄는 컨트롤.
                Button("완료") {
                    EditorHaptics.placementConfirmed()
                    selectedStickerID = nil
                }
                .font(InkFont.body.weight(.semibold))
                .foregroundStyle(PaperTheme.subtleSurface)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background {
                    let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
                    shape.fill(PaperTheme.ink)
                }
                .buttonStyle(InkPressStyle())
                .accessibilityLabel("스티커 배치 완료")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PaperTheme.subtleSurface)
        .overlay(alignment: .top) { InkSeparator() }
    }

    // MARK: - Layers

    /// Layers 목록에서 고른 장식을 Canvas 선택으로 옮긴다.
    /// 겹쳐 있어 손으로 집기 어려운 오브젝트를 정확히 고르는 수단이다.
    private func select(_ layer: DecorationLayer) {
        switch layer {
        case .importedArtwork(let object):
            // 도구는 바꾸지 않는다 — 외부 디자인은 캔버스에서 잡는 오브젝트가 아니다.
            selectedArtworkID = object.id
            selectedStickerID = nil
            selectedTextID = nil
        case .sticker(let object):
            tool = .sticker
            selectedStickerID = object.id
            selectedTextID = nil
            selectedArtworkID = nil
        case .text(let object):
            tool = .text
            selectedTextID = object.id
            selectedStickerID = nil
            selectedArtworkID = nil
        }
    }

    // MARK: - 외부 디자인

    private var selectedArtwork: ImportedArtworkObject? {
        guard let selectedArtworkID else { return nil }
        return design.importedArtworks.first { $0.id == selectedArtworkID }
    }

    /// 전체 캔버스 고정이라 이동 / 크기 / 회전 컨트롤이 없다.
    private func artworkContextBar(_ artwork: ImportedArtworkObject) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("투명도")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                Slider(
                    value: Binding(
                        get: { artwork.opacity },
                        set: { value in apply(artwork) { $0.opacity = value } }
                    ),
                    in: ImportedArtworkObject.opacityRange
                )
                .tint(PaperTheme.ink)
                .accessibilityLabel("외부 디자인 투명도")
            }

            HStack(spacing: 8) {
                Text("외부 디자인")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)

                iconButton("교체", icon: "arrow.triangle.2.circlepath") { isReplacingArtwork = true }
                iconButton("삭제", icon: "trash") {
                    history.apply(.deleteImportedArtwork(artwork.id), to: &design.snapshot)
                    selectedArtworkID = nil
                }

                Spacer(minLength: 0)

                Button("완료") {
                    EditorHaptics.placementConfirmed()
                    selectedArtworkID = nil
                }
                .font(InkFont.body.weight(.semibold))
                .foregroundStyle(PaperTheme.subtleSurface)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background {
                    UnevenRoundedRectangle.ink(15, 12, 16, 13).fill(PaperTheme.ink)
                }
                .buttonStyle(InkPressStyle())
                .accessibilityLabel("외부 디자인 편집 완료")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PaperTheme.subtleSurface)
        .overlay(alignment: .top) { InkSeparator() }
    }

    private func apply(_ artwork: ImportedArtworkObject, _ change: (inout ImportedArtworkObject) -> Void) {
        var updated = artwork
        change(&updated)
        history.apply(.replaceImportedArtwork(updated), to: &design.snapshot)
    }

    /// 그림만 갈아 끼운다 — 같은 레이어이므로 id와 순서(zIndex)는 그대로 둔다.
    private func replaceArtwork(_ new: ImportedArtworkObject) {
        guard let current = selectedArtwork else { return }
        apply(current) { $0.assetID = new.assetID }
    }

    // MARK: - Text

    private var selectedText: TextObject? {
        guard let selectedTextID else { return nil }
        return design.texts.first { $0.id == selectedTextID }
    }

    private func beginAddingText() {
        isAddingText = true
        draftText = ""
        isEditingText = true
    }

    /// 시트의 "추가" / "저장". 빈 문자열은 정책 단계에서 걸러진다.
    private func commitText() {
        defer { isEditingText = false }
        guard let value = TextPolicy.normalized(draftText) else { return }

        if isAddingText {
            let object = TextPlacement.insert(value, in: design, visibleRect: visibleRect)
            history.apply(.addText(object), to: &design.snapshot)
            selectedTextID = object.id
            selectedStickerID = nil
        } else if let text = selectedText {
            // 같은 id를 유지해야 Undo가 이전 내용으로 되돌아간다.
            apply(text) { $0.text = value }
        }
    }

    /// 텍스트를 선택했을 때만 보이는 전용 컨트롤. 스티커 바와 같은 구성이다.
    private func textContextBar(_ text: TextObject) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("투명도")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                Slider(
                    value: Binding(
                        get: { text.opacity },
                        set: { value in apply(text) { $0.opacity = value } }
                    ),
                    in: 0.1...1
                )
                .tint(PaperTheme.ink)
                .disabled(text.isLocked)
                .accessibilityLabel("텍스트 투명도")
            }

            HStack(spacing: 8) {
                // 컨트롤이 많아 좁은 화면에서는 가로로 넘긴다. 완료는 항상 보인다.
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                Button {
                    isChoosingTextColor = true
                } label: {
                    Circle()
                        .fill(text.color)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(PaperTheme.ink, lineWidth: 1.4))
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(InkPressStyle())
                .disabled(text.isLocked)
                .accessibilityLabel("텍스트 색상")

                iconButton("내용 수정", icon: "square.and.pencil", isEnabled: !text.isLocked) {
                    isAddingText = false
                    draftText = text.text
                    isEditingText = true
                }
                iconButton("글꼴", icon: "textformat", isEnabled: !text.isLocked) {
                    isChoosingTextFont = true
                }
                iconButton("정렬", icon: text.alignment.icon, isEnabled: !text.isLocked) {
                    // 왼쪽 → 가운데 → 오른쪽 순으로 한 단계씩 돈다.
                    let all = TextAlignmentOption.allCases
                    let next = all[(all.firstIndex(of: text.alignment).map { $0 + 1 } ?? 0) % all.count]
                    apply(text) { $0.alignment = next }
                }
                iconButton("복제", icon: "plus.square.on.square") { duplicate(text) }
                iconButton(text.isLocked ? "잠금 해제" : "잠금",
                           icon: text.isLocked ? "lock" : "lock.open") {
                    apply(text) { $0.isLocked.toggle() }
                }
                iconButton("삭제", icon: "trash") {
                    history.apply(.deleteText(text.id), to: &design.snapshot)
                    selectedTextID = nil
                }
                    }
                    .padding(.trailing, 4)
                }
                .scrollIndicators(.hidden)

                Button("완료") {
                    EditorHaptics.placementConfirmed()
                    selectedTextID = nil
                }
                .font(InkFont.body.weight(.semibold))
                .foregroundStyle(PaperTheme.subtleSurface)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background {
                    UnevenRoundedRectangle.ink(15, 12, 16, 13).fill(PaperTheme.ink)
                }
                .buttonStyle(InkPressStyle())
                .accessibilityLabel("텍스트 배치 완료")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PaperTheme.subtleSurface)
        .overlay(alignment: .top) { InkSeparator() }
    }

    private func apply(_ text: TextObject, _ change: (inout TextObject) -> Void) {
        var updated = text
        change(&updated)
        history.apply(.replaceText(updated), to: &design.snapshot)
    }

    private func duplicate(_ text: TextObject) {
        var copy = text
        copy.id = UUID()
        copy.zIndex = design.topDecorationZIndex + 1
        copy.center = NormalizedPoint(x: text.center.x + 0.03, y: text.center.y + 0.03)
        copy = copy.constrained()
        history.apply(.addText(copy), to: &design.snapshot)
        selectedTextID = copy.id
    }

    private func apply(_ sticker: StickerObject, _ change: (inout StickerObject) -> Void) {
        var updated = sticker
        change(&updated)
        history.apply(.replaceSticker(updated), to: &design.snapshot)
    }

    /// 슬라이더처럼 값이 연속으로 오는 경우에도 최종값만 반영한다.
    private func update(
        _ sticker: StickerObject,
        _ change: @escaping (inout StickerObject, Double) -> Void
    ) -> (Double) -> Void {
        { value in
            var updated = sticker
            change(&updated, value)
            history.apply(.replaceSticker(updated), to: &design.snapshot)
        }
    }

    private func duplicate(_ sticker: StickerObject) {
        var copy = sticker
        copy.id = UUID()
        copy.zIndex = (design.stickers.map(\.zIndex).max() ?? 0) + 1
        copy.frame = NormalizedRect(
            x: sticker.frame.x + 0.02,
            y: sticker.frame.y + 0.01,
            width: sticker.frame.width,
            height: sticker.frame.height
        )
        copy = copy.constrained()
        history.apply(.addSticker(copy), to: &design.snapshot)
        selectedStickerID = copy.id
    }

    // MARK: - Primary tools

    /// 자주 바꾸는 큰 기능만. Undo/Redo와 색·굵기는 여기 넣지 않는다.
    private var primaryToolBar: some View {
        HStack(spacing: 10) {
            ForEach(EditorTool.allCases) { item in
                primaryButton(item.title, icon: item.icon, isActive: tool == item) {
                    tool = item
                    if item == .sticker, selectedStickerID == nil { isPickingSticker = true }
                    if item == .text, selectedTextID == nil { beginAddingText() }
                }
            }
            primaryButton("배경", icon: "paintpalette") { isChoosingBackground = true }
            primaryButton("레이어", icon: "square.3.layers.3d") { isShowingLayers = true }
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
    EditorView(design: .blank,
               library: MirrorLibrary(),
               context: .createNew,
               onSaved: {})
}
