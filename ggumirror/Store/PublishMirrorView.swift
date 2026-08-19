//
//  PublishMirrorView.swift
//  ggumirror
//
//  상점에 올리기 전 판매 정보를 채우는 한 화면.
//
//  여기서 끝나는 것은 **등록 준비**다. 실제 등록 / 조각 차감 / 상점 노출은 하지 않는다.
//  로그인과 서버가 없는 상태에서 "등록됐어요"라고 말하지 않는다.
//

import SwiftUI

struct PublishMirrorView: View {
    let mirror: MyMirror
    var library: MirrorLibrary

    @Environment(\.inkModalDismiss) private var dismiss
    @State private var draft: MirrorPublishDraft
    @State private var savedNotice = false

    init(mirror: MyMirror, library: MirrorLibrary) {
        self.mirror = mirror
        self.library = library
        _draft = State(
            initialValue: library.publishDraft(for: mirror.id)
                ?? MirrorPublishDraft(mirrorID: mirror.id, title: mirror.name)
        )
    }

    private var manifest: MirrorPublishManifest { MirrorPublishManifest(mirror) }
    private var issues: [MirrorPublishIssue] {
        MirrorPublishValidator.issues(for: draft, mirror: mirror)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                preview
                titleField
                descriptionField
                priceField
                if manifest.needsPhotoPrivacyNotice { photoPrivacy }
                if manifest.needsArtworkRightsNotice { artworkRights }
                feeNotice
                if let issue = issues.first {
                    Text(issue.message)
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
            message: "실제 상점 등록은 로그인과 함께 다음 업데이트에서 열려요. 지금은 조각이 차감되지 않아요.",
            isPresented: $savedNotice
        ) {
            [InkDialogAction("확인", role: .primary) { dismiss() }]
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("상점에 올리기")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)
            Text("판매 정보를 미리 채워두세요. 지금은 저장만 되고 아직 상점에 올라가지 않아요.")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 실제 거울 그대로 — 배경 / 그리기 / 스티커 / 사진 / 텍스트 / 외부 디자인 / 레이어 순서.
    private var preview: some View {
        HStack {
            Spacer(minLength: 0)
            MirrorPreview(mirror: mirror)
                .frame(maxHeight: 320)
            Spacer(minLength: 0)
        }
    }

    private var titleField: some View {
        field("제목", detail: "\(draft.title.count) / \(MirrorPublishPolicy.maxTitleLength)") {
            TextField("상점에 보일 이름", text: $draft.title)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .textInputAutocapitalization(.never)
                .frame(minHeight: 44)
        }
    }

    private var descriptionField: some View {
        field("설명", detail: "\(draft.description.count) / \(MirrorPublishPolicy.maxDescriptionLength)") {
            TextEditor(text: $draft.description)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .scrollContentBackground(.hidden)
                .frame(height: 96)
                .accessibilityLabel("거울 설명")
        }
    }

    private var priceField: some View {
        field("가격", detail: draft.priceInShards == 0 ? "무료" : "\(draft.priceInShards) 조각") {
            Stepper(value: $draft.priceInShards, in: MirrorPublishPolicy.priceRange) {
                ShardAmount(amount: draft.priceInShards, font: InkFont.body, iconSize: 18)
            }
            .tint(PaperTheme.ink)
            .frame(minHeight: 44)
        }
    }

    private var photoPrivacy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("이 거울에는 내 사진으로 만든 스티커가 포함되어 있어요.\n상점에 등록하면 이 이미지도 함께 공개될 수 있어요.")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $draft.didAcknowledgePhotoPrivacy) {
                Text("확인했어요")
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
            }
            .tint(PaperTheme.ink)
            .frame(minHeight: 44)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = UnevenRoundedRectangle.ink(16, 13, 17, 12)
            shape.fill(PaperTheme.subtleSurface)
                .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.6))
        }
    }

    private var artworkRights: some View {
        Text("직접 만들었거나 사용할 권리가 있는 이미지만 등록해 주세요.")
            .font(InkFont.caption)
            .foregroundStyle(PaperTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                UnevenRoundedRectangle.ink(16, 13, 17, 12)
                    .stroke(PaperTheme.secondaryInk, lineWidth: 1.4)
            }
    }

    private var feeNotice: some View {
        HStack(spacing: 8) {
            ShardAmount(amount: MirrorPublishPolicy.feeInShards, font: InkFont.caption, iconSize: 16)
            Text("상점 공개 등록 비용이에요. 지금은 차감되지 않아요.")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("상점 공개 등록 비용 \(MirrorPublishPolicy.feeInShards) 조각, 지금은 차감되지 않아요")
    }

    private var saveButton: some View {
        // 안내 문구는 스크롤 안에 남는다 — 고정 줄은 버튼 하나만 담는다.
        Button("등록 준비 저장") {
            library.savePublishDraft(draft)
            savedNotice = true
        }
        .font(InkFont.body.weight(.semibold))
        .foregroundStyle(PaperTheme.subtleSurface)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 50)
        .background {
            UnevenRoundedRectangle.ink(16, 13, 17, 12)
                .fill(issues.isEmpty ? PaperTheme.ink : PaperTheme.disabled)
        }
        .buttonStyle(InkPressStyle())
        .disabled(!issues.isEmpty)
    }

    private func field(
        _ title: String,
        detail: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(InkFont.secondary.weight(.semibold))
                    .foregroundStyle(PaperTheme.ink)
                Spacer(minLength: 8)
                Text(detail)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .monospacedDigit()
            }
            content()
                .padding(.horizontal, 12)
                .background {
                    UnevenRoundedRectangle.ink(14, 11, 15, 12)
                        .stroke(PaperTheme.ink, lineWidth: 1.5)
                }
        }
    }
}

#Preview {
    PublishMirrorView(
        mirror: MyMirror(id: "made-1", name: "나의 거울", origin: .made, style: BasicMirror.mint.style),
        library: MirrorLibrary()
    )
    .paperBackground()
}
