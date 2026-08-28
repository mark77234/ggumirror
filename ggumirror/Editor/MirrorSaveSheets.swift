//
//  MirrorSaveSheets.swift
//  ggumirror
//
//  거울 이름 짓기와 스티커 색 고르기. Drawing 설정과 같은 디자인 언어를 쓴다.
//

import SwiftUI

/// 저장 시 거울 이름을 정한다.
/// 기본 제공 / 구매 거울을 꾸민 경우에는 원본을 두고 새 거울로 저장된다.
struct MirrorNameSheet: View {
    let isNewMirror: Bool
    /// 제목을 갈아 끼울 때. 비어 있으면 기존 문구를 쓴다.
    var title: String?
    /// 제목 아래 한 줄. 비어 있으면 기존 규칙을 따른다.
    var detail: String?
    /// 지금 이 이름을 쓸 수 있는가. **`nil`이면 쓸 수 있다는 뜻이다** —
    /// 문자열을 돌려주면 그 말이 그대로 화면에 뜨고 `저장`이 잠긴다.
    ///
    /// 판단은 **부르는 쪽이 한다** — 시트는 서랍이 무엇인지 모른다.
    var validate: ((String) -> String?)?
    let onSave: (String) -> Void

    /// **입력 중인 이름은 이 시트만 안다.** `TextInputSheet`와 같은 이유다 —
    /// 부모의 `@State`에 바로 쓰면 한 글자마다 거울 canvas가 다시 그려진다.
    @State private var name: String

    init(
        initialName: String = "",
        isNewMirror: Bool,
        title: String? = nil,
        detail: String? = nil,
        validate: ((String) -> String?)? = nil,
        onSave: @escaping (String) -> Void
    ) {
        self.isNewMirror = isNewMirror
        self.title = title
        self.detail = detail
        self.validate = validate
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    @Environment(\.inkModalDismiss) private var dismiss
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 지금 막고 있는 이유. 없으면 저장할 수 있다.
    private var problem: String? {
        guard !trimmed.isEmpty else { return nil }
        return validate?(name)
    }

    private var canSave: Bool { !trimmed.isEmpty && problem == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title ?? (isNewMirror ? "새 거울로 저장" : "거울 이름"))
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)

            if let detail {
                Text(detail)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isNewMirror {
                Text("원래 거울은 그대로 두고, 꾸민 결과를 내 거울로 저장해요.")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("나만의 거울", text: $name)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { if canSave { onSave(name) } }
                .onChange(of: name) { _, newValue in
                    // 지나치게 긴 이름은 입력 단계에서 막는다.
                    if newValue.count > MirrorStoragePolicy.maxNameLength {
                        name = String(newValue.prefix(MirrorStoragePolicy.maxNameLength))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(minHeight: 44)
                .background {
                    let shape = UnevenRoundedRectangle.ink(15, 18, 19, 14)
                    shape
                        .fill(PaperTheme.subtleSurface)
                        .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.8))
                }

            // **막힌 이유를 말한다.** 눌리지 않는 버튼만 보여 주지 않는다.
            if let problem {
                Text(problem)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                // **겉모습이 label 안에 있다.** 밖에 두면 글자만 눌린다 —
                // 실기기에서 `저장` 테두리를 눌러도 반응이 없던 이유다.
                Button {
                    dismiss()
                } label: {
                    Text("취소")
                        .font(InkFont.body)
                        .foregroundStyle(PaperTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background {
                            UnevenRoundedRectangle.ink(15, 12, 16, 13)
                                .stroke(PaperTheme.ink, lineWidth: 1.6)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())

                Button {
                    onSave(name)
                } label: {
                    Text("저장")
                        .font(InkFont.body.weight(.semibold))
                        .foregroundStyle(PaperTheme.subtleSurface)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background {
                            UnevenRoundedRectangle.ink(15, 12, 16, 13)
                                .fill(canSave ? PaperTheme.ink : PaperTheme.disabled)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(InkPressStyle())
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { isFocused = true }
    }
}

/// 스티커 색. Drawing 팔레트와 같은 색을 쓴다.
struct StickerColorSheet: View {
    let color: Color
    let onPick: (Color) -> Void

    @Environment(\.inkModalDismiss) private var dismiss
    @State private var custom: Color

    init(color: Color, onPick: @escaping (Color) -> Void) {
        self.color = color
        self.onPick = onPick
        _custom = State(initialValue: color)
    }

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
        VStack(alignment: .leading, spacing: 16) {
            Text("스티커 색")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Self.palette, id: \.self) { swatch in
                    Button {
                        onPick(swatch)
                        dismiss()
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
                    .accessibilityLabel("스티커 색 선택")
                }
            }

            // 연속으로 바뀌는 값은 시트를 닫을 때 한 번만 반영한다.
            ColorPicker("직접 고르기", selection: $custom, supportsOpacity: false)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .frame(minHeight: 44)

            Button("적용") {
                onPick(custom)
                dismiss()
            }
            .font(InkFont.body.weight(.semibold))
            .foregroundStyle(PaperTheme.subtleSurface)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background {
                UnevenRoundedRectangle.ink(15, 12, 16, 13).fill(PaperTheme.ink)
            }
            .buttonStyle(InkPressStyle())

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    MirrorNameSheet(initialName: "나만의 거울", isNewMirror: true) { _ in }
        .paperBackground()
}
