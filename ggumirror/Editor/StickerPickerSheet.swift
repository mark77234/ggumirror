//
//  StickerPickerSheet.swift
//  ggumirror
//
//  기본 제공 스티커 고르기. 손그림 두들 42종만 보여준다.
//  Legacy(`BuiltInSticker`)는 **여기 나오지 않는다** — 예전에 저장한 거울을 그리기 위해서만 남아 있다.
//

import PhotosUI
import SwiftUI

/// Picker의 두 칸.
enum StickerGroup: String, CaseIterable, Identifiable, Hashable {
    case builtIn = "기본 스티커"
    case mine = "내 스티커"

    var id: String { rawValue }
}

struct StickerPickerSheet: View {
    let onPick: (StickerSource) -> Void
    /// 사진 1장 선택. 배경 제거와 진행 표시는 부르는 화면이 맡는다.
    var onPickPhoto: (PhotosPickerItem) -> Void = { _ in }
    /// "내 사진으로 만들기" 줄을 보여줄지. Sticker Creator는 자체 사진 도구가 있어 숨긴다.
    var showsPhotoEntry = true
    /// "+ 스티커 만들기" 줄. Mirror Editor에서만 보여준다(Creator 안에서 또 열지 않는다).
    var onCreateSticker: (() -> Void)?

    /// 내가 만든 스티커. 저장하면 바로 이 목록에 나타난다.
    var stickers: StickerLibrary = .live
    /// 내 스티커를 골랐을 때. 거울에 놓을 **불변 스냅샷**을 만들어 넘긴다.
    var onPickUserSticker: ((StickerSource) -> Void)?

    @State private var group: StickerGroup = .builtIn
    @State private var category: DoodleCategory = .all
    @State private var photoItem: PhotosPickerItem?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            if showsPhotoEntry {
                photoEntry
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            if let onCreateSticker {
                createEntry(onCreateSticker)
                    .padding(.horizontal, 20)
                    .padding(.top, showsPhotoEntry ? 10 : 16)
            }

            if onPickUserSticker != nil {
                groupSwitch
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }

            if group == .builtIn {
                InkFilterBar(items: DoodleCategory.allCases, selection: $category) { $0.rawValue }
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            }

            if group == .mine {
                mineList
            } else {
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(DoodleSticker.all(in: category)) { source in
                        Button {
                            onPick(.doodle(source))
                        } label: {
                            VStack(spacing: 8) {
                                DoodleStickerView(sticker: source, size: 40)
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
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            }
        }
        // 시트가 닫힌 뒤에 처리하지 않도록 선택 즉시 위로 넘긴다.
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            photoItem = nil
            onPickPhoto(newValue)
        }
    }

    private var groupSwitch: some View {
        HStack(spacing: 8) {
            ForEach(StickerGroup.allCases) { item in
                let isActive = group == item
                Button { group = item } label: {
                    Text(item.rawValue)
                        .font(InkFont.button)
                        .foregroundStyle(isActive ? PaperTheme.paper : PaperTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .background {
                            let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
                            shape
                                .fill(isActive ? PaperTheme.ink : PaperTheme.subtleSurface)
                                .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.regular))
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// 내가 만든 스티커. `StickerLibrary`가 유일한 진실이다.
    @ViewBuilder
    private var mineList: some View {
        if stickers.projects.isEmpty {
            VStack(spacing: 10) {
                Text("아직 만든 스티커가 없어요")
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                if let onCreateSticker {
                    Button {
                        onCreateSticker()
                    } label: {
                        Text("스티커 만들기")
                            .font(InkFont.button)
                            .foregroundStyle(PaperTheme.ink)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    // 방금 만든 것이 맨 앞에 온다.
                    ForEach(stickers.projects.reversed()) { project in
                        Button {
                            // 지금 완성 PNG를 **복사해** 넘긴다 — 나중에 원본을 고쳐도
                            // 이미 놓인 거울은 그대로다.
                            if let source = stickers.placementSnapshot(for: project) {
                                onPickUserSticker?(source)
                            }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    TransparencyCheckerboard(cell: 10)
                                    if let image = stickers.finalImage(for: project) {
                                        Image(decorative: image, scale: 1)
                                            .resizable()
                                            .scaledToFit()
                                            .padding(6)
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(UnevenRoundedRectangle.ink(15, 12, 16, 13))
                                .overlay(
                                    UnevenRoundedRectangle.ink(15, 12, 16, 13)
                                        .stroke(PaperTheme.ink, lineWidth: 1.4)
                                )
                                Text(project.name)
                                    .font(InkFont.caption)
                                    .foregroundStyle(PaperTheme.secondaryInk)
                                    .lineLimit(1)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(InkPressStyle())
                        .accessibilityLabel(project.name)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// 스티커 만들기 진입점. 아직 "내 스티커" 목록은 없다 — Creator로 들어가는 문만 있다.
    private func createEntry(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("스티커 만들기")
                        .font(InkFont.body.weight(.semibold))
                    Text("직접 그리거나 사진으로 만들어요")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .bold))
            }
            .foregroundStyle(PaperTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background {
                let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
                shape
                    .fill(PaperTheme.subtleSurface)
                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.regular))
            }
            .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel("스티커 만들기")
    }

    /// 사진 스티커 진입점. 기본 제공 스티커보다 먼저 눈에 들어오게 위에 둔다.
    private var photoEntry: some View {
        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: 10) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 20, weight: .light))
                VStack(alignment: .leading, spacing: 2) {
                    Text("내 사진으로 만들기")
                        .font(InkFont.body.weight(.semibold))
                    Text("배경을 지워 스티커로 만들어요")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .bold))
            }
            .foregroundStyle(PaperTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .background {
                let shape = UnevenRoundedRectangle.ink(15, 12, 16, 13)
                shape
                    .fill(PaperTheme.subtleSurface)
                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.6))
            }
            .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel("내 사진으로 스티커 만들기")
    }
}

#Preview {
    StickerPickerSheet(onPick: { _ in })
        .paperBackground()
}
