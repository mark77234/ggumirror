//
//  PublishStickerView.swift
//  ggumirror
//
//  스티커 **등록 준비**. 실제 등록도, 조각 차감도, 상점 노출도 없다.
//  "등록됐다" / "판매 중"처럼 보이는 문구를 쓰지 않는다 — 서버가 없기 때문이다.
//
//  등록 비용은 5 조각이다(거울 10보다 싸다). 값은 StickerPublishPolicy 하나에서만 온다.
//

import SwiftUI

struct PublishStickerView: View {
    let project: StickerProject
    var library: StickerLibrary

    @State private var draft: StickerPublishDraft
    @State private var savedNotice = false
    @Environment(\.inkModalDismiss) private var dismiss
    @Environment(AuthSession.self) private var session
    @Environment(ShardWallet.self) private var wallet
    @Environment(MarketplaceStore.self) private var marketplace
    @State private var publishNotice: String?
    @State private var didPublish = false

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
            VStack(spacing: 8) {
                listingControls
                publishButton
                saveButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .inkDialog(
            didPublish ? "상점에 올렸어요" : "올리지 못했어요",
            message: publishNotice,
            isPresented: Binding(
                get: { publishNotice != nil },
                set: { if !$0 { publishNotice = nil } }
            )
        ) {
            [InkDialogAction("확인", role: .primary) { if didPublish { dismiss() } }]
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

    /// 거울과 **같은 모양**이다. 값만 정책 상수에서 다르게 온다.
    private var feeNotice: some View {
        HStack(spacing: 8) {
            ShardAmount(amount: StickerPublishPolicy.feeInShards, font: InkFont.caption, iconSize: 16)
            Text("상점 공개 등록 비용이에요. 지금은 차감되지 않아요.")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("상점 공개 등록 비용 \(StickerPublishPolicy.feeInShards) 조각, 지금은 차감되지 않아요")
    }

    /// 실제 등록. 등록비는 **서버가** 차감한다.
    private var publishButton: some View {
        let isBusy = marketplace.isBusy(.snapshot)
        return Button(isBusy ? "올리는 중…" : "상점에 올리기 (\(StickerPublishPolicy.feeInShards) 조각)") {
            Task { await publish() }
        }
        .font(InkFont.body.weight(.semibold))
        .foregroundStyle(PaperTheme.subtleSurface)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 50)
        .background {
            UnevenRoundedRectangle.ink(16, 13, 17, 12)
                .fill(issues.isEmpty && !isBusy ? PaperTheme.ink : PaperTheme.disabled)
        }
        .buttonStyle(InkPressStyle())
        .disabled(!issues.isEmpty || isBusy)
    }

    private func publish() async {
        guard session.server != nil else {
            _ = session.requireSignIn(for: .shardTransaction)
            return
        }
        let package: SnapshotPackage
        do {
            package = try SnapshotPackager.package(
                project, stickerStore: library.assetStore
            )
        } catch let failure as SnapshotPackagingFailure {
            didPublish = false
            publishNotice = failure.message
            return
        } catch {
            didPublish = false
            publishNotice = "상점에 올릴 준비를 마치지 못했어요."
            return
        }

        // **publish를 보내기 전에** listing id를 남길 준비를 한다.
        // 저장이 실패하면 store가 publish를 보내지 않는다 — 못 찾는 listing을
        // 만들지 않는 것이 실패보다 낫다.
        marketplace.onListingCreated = { [self] listingID in
            draft.listingID = listingID
            library.saveDraft(draft)
            // 저장 경로가 동기라 여기까지 오면 남았다.
            return draft.listingID == listingID
        }
        defer { marketplace.onListingCreated = nil }

        let result = await marketplace.publish(
            package: package,
            title: StickerPublishPolicy.normalizedTitle(draft.title) ?? project.name,
            description: StickerPublishPolicy.normalizedDescription(draft.description),
            priceShards: draft.priceInShards,
            session: session.server,
            wallet: wallet
        )
        guard let result else {
            didPublish = false
            publishNotice = marketplace.failure?.message
            return
        }
        didPublish = true
        assert(draft.listingID == result.listing.id, "저장한 listing과 다른 것을 올렸다")
        publishNotice = result.feeCharged
            ? "등록비 \(result.feeShards) 조각이 차감됐어요. 남은 조각 \(result.balance)개."
            : "추가 등록비 없이 다시 올렸어요."
        await wallet.refresh(session: session.server)
    }

    /// 관리 대상 listing. **서버 목록이 authority다.**
    ///
    /// `draft.listingID`는 힌트(cache)일 뿐이다 — 앱을 지웠거나 기기를 바꾸면 없다.
    /// 그래서 그 id로 서버 목록을 조회해 실제 상태를 확인하고, id가 없으면
    /// 서버 목록에서 **같은 콘텐츠 종류의 내 상품**을 보여 줄 수 없으므로
    /// (listing에 local content id가 없다) 관리 UI를 내지 않는다.
    /// 전체 관리는 상점의 "내 상점 상품" 구획에서 한다.
    private var managed: MarketplaceOwnedListing? {
        guard let hint = draft.listingID else { return nil }
        return marketplace.myListing(id: hint)
    }

    /// 이미 올린 상품이면 내리기 / 다시 올리기를 보여 준다.
    @ViewBuilder
    private var listingControls: some View {
        if let listing = managed {
            let listingID = listing.id
            let isBusy = marketplace.isBusy(.unpublish(listingID))
                || marketplace.isBusy(.publish(listingID))
            HStack(spacing: 8) {
                Text(listing.statusLabel)
                    .foregroundStyle(PaperTheme.secondaryInk)
                // **서버 상태로** 무엇을 보여 줄지 정한다. 앱이 추측하지 않는다.
                if listing.isPublished {
                    Button("상점에서 내리기") {
                    Task {
                        guard await marketplace.unpublish(
                            listingID: listingID, session: session.server
                        ) != nil else {
                            didPublish = false
                            publishNotice = marketplace.failure?.message
                            return
                        }
                        didPublish = false
                        publishNotice = "상점에서 내렸어요. 이미 산 사람은 계속 받을 수 있어요."
                    }
                    }
                }
                if listing.isUnlisted || listing.isDraft {
                    Button(listing.isDraft ? "상점에 올리기" : "다시 올리기") {
                    Task {
                        guard let result = await marketplace.republish(
                            listingID: listingID, session: session.server, wallet: wallet
                        ) else {
                            didPublish = false
                            publishNotice = marketplace.failure?.message
                            return
                        }
                        didPublish = false
                        publishNotice = result.feeCharged
                            ? "등록비 \(result.feeShards) 조각이 차감됐어요."
                            : "추가 등록비 없이 다시 올렸어요."
                        await wallet.refresh(session: session.server)
                    }
                    }
                }
            }
            .font(InkFont.caption)
            .foregroundStyle(PaperTheme.ink)
            .buttonStyle(InkPressStyle())
            .frame(minHeight: 44)
            .disabled(isBusy)
        }
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
