//
//  PublishMirrorView.swift
//  ggumirror
//
//  상점에 올리기 전 판매 정보를 채우는 한 화면.
//
//  두 가지를 할 수 있다:
//    - **등록 준비 저장** — 로그인 없이 지금도 된다(Core Product Policy)
//    - **상점에 올리기** — 로그인이 필요하고 서버가 등록비를 차감한다
//
//  등록비는 **서버가 정하고 서버가 뺀다.** 앱은 안내만 하고, 성공 응답에 담긴
//  잔액을 지갑에 넣는다. "두 번째니까 무료"를 앱이 계산하지 않는다.
//

import SwiftUI

struct PublishMirrorView: View {
    let mirror: MyMirror
    var library: MirrorLibrary

    @Environment(\.inkModalDismiss) private var dismiss
    @Environment(AuthSession.self) private var session
    @Environment(ShardWallet.self) private var wallet
    @Environment(MarketplaceStore.self) private var marketplace
    /// 판매자 이름. **상점에 올리려면 먼저 있어야 한다** — 상품에 이 이름이 보인다.
    @Environment(ProfileSession.self) private var profile: ProfileSession?
    /// 이름을 정하러 가는 중.
    @State private var isNamingSeller = false
    @State private var draft: MirrorPublishDraft
    @State private var savedNotice = false
    /// 등록 결과 안내. 성공/실패 모두 여기로 온다.
    @State private var publishNotice: String?
    @State private var didPublish = false

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
            .inkDismissesKeyboardOnTap()
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        // 키보드가 등록 버튼을 덮은 채 남지 않게 한다 — 스크롤로도, 빈 곳 탭으로도 닫힌다.
        .scrollDismissesKeyboard(.interactively)
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
        // 이름을 정하고 오면 그대로 이어서 올릴 수 있다 — 등록 정보는 그대로 남는다.
        .inkBottomSheet(isPresented: $isNamingSeller, size: .fraction(0.8)) {
            SellerNameSheet()
        }
        .inkDialog(
            "등록 준비를 저장했어요",
            message: "아직 상점에 올라가지 않았어요. 조각도 차감되지 않았어요.",
            isPresented: $savedNotice
        ) {
            [InkDialogAction("확인", role: .primary) { dismiss() }]
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("상점에 올리기")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)
            Text("판매 정보를 채우고 상점에 올려 보세요.")
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
            Text("상점에 올릴 때 차감되는 등록 비용이에요.")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("상점 공개 등록 비용 \(MirrorPublishPolicy.feeInShards) 조각")
    }

    /// 실제 등록. 꾸러미를 만들어 올리고 게시까지 한 번에 한다.
    ///
    /// **연타를 막는다** — 등록비가 두 번 빠지면 사용자가 조각을 잃는다.
    private var publishButton: some View {
        let isBusy = marketplace.isBusy(.snapshot)
        return Button(isBusy ? "올리는 중…" : "상점에 올리기 (\(MirrorPublishPolicy.feeInShards) 조각)") {
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

    /// 꾸러미를 만들고 서버에 올린다.
    ///
    /// 이미지가 하나라도 없으면 **보내기 전에** 멈춘다 — 반쪽 꾸러미를 서버에
    /// 올리면 산 사람 기기에서 그림이 비어 보인다.
    private func publish() async {
        // **판매는 판매자 신원이 필요하다.** 조각 구매와 달리 계정을 요구한다.
        guard session.account != nil else {
            _ = session.requireSignIn(for: .shardTransaction)
            return
        }
        // **이름 없이 올리지 않는다.** 상품에 판매자 이름이 보이는데 비어 있으면
        // 사는 사람은 누가 올린 것인지 알 수 없다. 서버에 보내기 전에 받는다.
        guard profile?.profile?.hasName == true else {
            isNamingSeller = true
            return
        }
        let package: SnapshotPackage
        do {
            package = try SnapshotPackager.package(mirror, store: library.assetStore)
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
            library.savePublishDraft(draft)
            // 저장 경로가 동기라 여기까지 오면 남았다.
            return draft.listingID == listingID
        }
        defer { marketplace.onListingCreated = nil }

        // **상품명은 한 번만 정한다.** 서버로 가는 값과 내 거울에 남길 값이
        // 같은 변수에서 나와야 둘이 갈라질 수 없다.
        let title = MirrorPublishPolicy.normalizedTitle(draft.title) ?? mirror.name

        let result = await marketplace.publish(
            package: package,
            title: title,
            description: MirrorPublishPolicy.normalizedDescription(draft.description),
            priceShards: draft.priceInShards,
            session: session.account,
            wallet: wallet
        )
        guard let result else {
            // **실패하면 이름을 바꾸지 않는다.** 올리지도 못한 이름이 내 거울에
            // 남으면 사용자는 상점에 없는 이름을 보게 된다.
            didPublish = false
            publishNotice = marketplace.failure?.message
            return
        }
        didPublish = true
        // **등록에 성공한 뒤에** 내 거울 이름도 그 이름으로 맞춘다.
        //
        // 사용자가 등록하면서 붙인 이름이 이 거울의 이름이다 — 상점에서는
        // `짱구 거울`인데 내 거울에서는 `AI 거울`로 남아 있으면 같은 물건이
        // 두 이름을 갖는다. 기존 이름 바꾸기 통로를 그대로 쓰고(id로 찾는다),
        // 그 안에서 디스크까지 저장된다.
        _ = library.rename(mirror.id, to: title)
        // id는 publish **전에** 이미 남겼다(`onListingCreated`). 여기서는 서버가
        // 돌려준 값과 같은지만 확인한다 — 다르면 우리가 잘못된 listing을 올린 것이다.
        assert(draft.listingID == result.listing.id, "저장한 listing과 다른 것을 올렸다")
        // **서버가 말해 준 값을 그대로 옮긴다.** 앱이 10을 빼지 않는다.
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
    ///
    /// 다시 올릴 때 **추가 등록비가 없다** — 서버가 `feeCharged=false`로 알려 준다.
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
                            listingID: listingID, session: session.account
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
                            listingID: listingID, session: session.account, wallet: wallet
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
        Button("등록 준비만 저장") {
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
