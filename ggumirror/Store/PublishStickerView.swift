//
//  PublishStickerView.swift
//  ggumirror
//
//  스티커 **등록 준비**. 실제 등록도, 조각 차감도, 상점 노출도 없다.
//  "등록됐다" / "판매 중"처럼 보이는 문구를 쓰지 않는다 — 서버가 없기 때문이다.
//
//  등록 비용은 아직 정하지 않았다. 거울의 20 조각을 그대로 가져오지 않는다.
//

import SwiftUI

struct PublishStickerView: View {
    let project: StickerProject
    var library: StickerLibrary

    @State private var draft: StickerPublishDraft
    @State private var savedNotice = false
    @Environment(\.inkModalDismiss) private var dismiss

    init(project: StickerProject, library: StickerLibrary) {
        self.project = project
        self.library = library
        _draft = State(initialValue: library.draft(for: project.id)
            ?? StickerPublishDraft(stickerProjectID: project.id, title: project.name))
    }

    private var issues: [StickerPublishIssue] {
        StickerPublishValidator.issues(for: draft, project: project)
    }

    private var hasPhoto: Bool { !project.photoAssetIDs.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                preview
                field("제목", text: $draft.title, limit: StickerPublishPolicy.maxTitleLength)
                descriptionField
                priceField
                if hasPhoto { photoNotice }
                rightsNotice
                feeNotice
                if let first = issues.first {
                    Text(first.message)
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        // 등록 버튼은 **스크롤 밖에 고정**한다 — 내용이 길어도 손이 닿아야 한다.
        .inkSheetActions {
            saveButton.padding(.horizontal, 20).padding(.top, 12)
        }
        .inkDialog(
            "등록 준비를 저장했어요",
            message: "실제 상점 등록은 준비 중이에요. 지금은 조각이 차감되지 않고, 아직 아무도 이 스티커를 볼 수 없어요.",
            isPresented: $savedNotice
        ) {
            [InkDialogAction("확인", role: .primary) { dismiss() }]
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("스티커 등록 준비")
                .font(InkFont.title)
                .foregroundStyle(PaperTheme.ink)
            Text("판매 정보를 미리 채워 둬요. 실제 등록은 다음 업데이트에서 열려요.")
                .font(InkFont.secondary)
                .foregroundStyle(PaperTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var preview: some View {
        HStack(spacing: 14) {
            ZStack {
                TransparencyCheckerboard(cell: 10)
                if let image = library.finalImage(for: project) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(UnevenRoundedRectangle.ink(15, 12, 16, 13))
            .overlay(
                UnevenRoundedRectangle.ink(15, 12, 16, 13)
                    .stroke(PaperTheme.ink, lineWidth: InkLine.regular)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(InkFont.cardTitle)
                    .foregroundStyle(PaperTheme.ink)
                    .lineLimit(1)
                Text("1024 × 1024 · 배경 투명")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
            }
            Spacer(minLength: 0)
        }
    }

    private func field(_ label: String, text: Binding<String>, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(label, detail: "\(text.wrappedValue.count) / \(limit)")
            TextField(label, text: text)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .frame(minHeight: 44)
                .background { inputSurface }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(
                "설명 (선택)",
                detail: "\(draft.description.count) / \(StickerPublishPolicy.maxDescriptionLength)"
            )
            TextField("어떤 스티커인지 알려주세요", text: $draft.description, axis: .vertical)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .lineLimit(3...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background { inputSurface }
        }
    }

    private var priceField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("가격", detail: "0 = 무료")
            HStack(spacing: 10) {
                ShardIcon(size: 18)
                TextField("0", value: $draft.priceInShards, format: .number)
                    .font(InkFont.numeric)
                    .keyboardType(.numberPad)
                    .foregroundStyle(PaperTheme.ink)
                Text("조각")
                    .font(InkFont.secondary)
                    .foregroundStyle(PaperTheme.secondaryInk)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(minHeight: 44)
            .background { inputSurface }
        }
    }

    private var photoNotice: some View {
        acknowledgement(
            isOn: $draft.didAcknowledgePhotoPrivacy,
            text: "사진이 포함된 스티커를 공개하면 이미지가 다른 사용자에게 보일 수 있어요."
        )
    }

    private var rightsNotice: some View {
        acknowledgement(
            isOn: $draft.didAcknowledgeRights,
            text: "직접 만들었거나 사용할 권리가 있는 이미지와 콘텐츠만 등록해 주세요."
        )
    }

    private func acknowledgement(isOn: Binding<Bool>, text: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square" : "square")
                    .font(InkFont.body)
                Text(text)
                    .font(InkFont.caption)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(PaperTheme.ink)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
    }

    /// 등록 비용은 **아직 정하지 않았다.** 숫자를 지어내지 않는다.
    private var feeNotice: some View {
        Text("등록 비용은 아직 정해지지 않았어요. 지금은 조각이 차감되지 않아요.")
            .font(InkFont.caption)
            .foregroundStyle(PaperTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var saveButton: some View {
        // 안내 문구는 스크롤 안에 남는다 — 고정 줄은 버튼 하나만 담는다.
        Group {
            Button {
                library.saveDraft(draft)
                savedNotice = true
            } label: {
                Text("등록 준비 저장")
                    .font(InkFont.button)
                    .foregroundStyle(issues.isEmpty ? PaperTheme.paper : PaperTheme.disabled)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background {
                        let shape = InkCorner.control
                        shape
                            .fill(issues.isEmpty ? PaperTheme.ink : PaperTheme.subtleSurface)
                            .overlay(shape.stroke(
                                issues.isEmpty ? PaperTheme.ink : PaperTheme.disabled,
                                lineWidth: InkLine.regular
                            ))
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(InkPressStyle())
            .disabled(!issues.isEmpty)
        }
    }

    private func fieldLabel(_ text: String, detail: String) -> some View {
        HStack {
            Text(text)
                .font(InkFont.caption.weight(.semibold))
                .foregroundStyle(PaperTheme.secondaryInk)
            Spacer(minLength: 8)
            Text(detail)
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
        }
    }

    private var inputSurface: some View {
        let shape = UnevenRoundedRectangle.ink(15, 18, 19, 14)
        return shape
            .fill(PaperTheme.subtleSurface)
            .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.regular))
    }
}
