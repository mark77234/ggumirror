//
//  LayersSheet.swift
//  ggumirror
//
//  장식 순서 보기 / 바꾸기.
//  위가 앞, 아래가 뒤 — Canvas에서 보이는 순서 그대로다.
//
//  Drawing과 Background는 고정 레이어라 목록 아래에 잠금 표시로만 보여준다.
//

import SwiftUI

struct LayersSheet: View {
    let design: MirrorDesign
    /// 앞 → 뒤 순서로 바뀐 id 목록. 놓았을 때 1회만 호출된다.
    let onReorder: ([UUID]) -> Void
    /// 줄을 누르면 Canvas에서 그 오브젝트를 고른다.
    let onSelect: (DecorationLayer) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var layers: [DecorationLayer] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("레이어")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 4)

            Text("위가 앞, 아래가 뒤예요")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            if layers.isEmpty {
                Text("아직 스티커나 텍스트가 없어요.")
                    .font(InkFont.secondary)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                Spacer(minLength: 0)
            } else {
                List {
                    ForEach(layers) { layer in
                        Button {
                            onSelect(layer)
                            dismiss()
                        } label: {
                            LayerRow(layer: layer)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(PaperTheme.subtleSurface)
                    }
                    .onMove(perform: move)

                    Section {
                        fixedRow("그리기", icon: "scribble")
                        fixedRow("배경", icon: "paintpalette")
                    } header: {
                        Text("고정")
                            .font(InkFont.caption)
                            .foregroundStyle(PaperTheme.secondaryInk)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // 항상 옮길 수 있게 둔다 — 별도 편집 모드 전환 없이 바로 끌어서 순서를 바꾼다.
                .environment(\.editMode, .constant(.active))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { layers = design.decorationLayers }
    }

    /// 놓았을 때 한 번만 history에 남긴다. 드래그 중에는 목록만 움직인다.
    private func move(from source: IndexSet, to destination: Int) {
        layers.move(fromOffsets: source, toOffset: destination)
        onReorder(layers.map(\.id))
    }

    private func fixedRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.secondaryInk)
                .frame(width: 34, height: 34)
            Text(title)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.secondaryInk)
            Spacer(minLength: 0)
            Image(systemName: "lock")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(PaperTheme.secondaryInk)
        }
        .frame(minHeight: 44)
        .listRowBackground(PaperTheme.subtleSurface)
        .moveDisabled(true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), 순서를 바꿀 수 없어요")
    }
}

/// 목록 한 줄. 사진 스티커는 이미 만들어 둔 이미지를 그대로 보여준다 —
/// 썸네일 때문에 배경 제거를 다시 돌리지 않는다.
private struct LayerRow: View {
    let layer: DecorationLayer

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(layer.title)
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .lineLimit(1)
                Text(layer.subtitle)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
            }

            Spacer(minLength: 0)

            if layer.isLocked {
                Image(systemName: "lock")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(PaperTheme.secondaryInk)
            }
        }
        .frame(minHeight: 48)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(layer.subtitle), \(layer.title)\(layer.isLocked ? ", 잠김" : "")")
        .accessibilityHint("두 번 탭하면 이 장식을 선택해요")
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch layer {
        case .sticker(let object):
            switch object.source {
            case .builtIn(let builtIn):
                Image(systemName: builtIn.symbolName)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(object.resolvedTint ?? PaperTheme.ink)
            case .photo(let assetID, _):
                if let image = PhotoStickerAssetStore.shared.image(for: assetID) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(PaperTheme.secondaryInk)
                }
            }
        case .text(let object):
            Text("T")
                .font(Font(object.style.font(ofSize: 20)))
                .foregroundStyle(object.color)
        }
    }
}

#Preview {
    LayersSheet(design: .blank, onReorder: { _ in }, onSelect: { _ in })
        .paperBackground()
}
