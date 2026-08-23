//
//  MyMirrorsView.swift
//  ggumirror
//
//  내 거울. 2열 Gallery + 항목별 액션.
//  Editor / 상점 등록처럼 아직 없는 기능은 안내만 띄운다.
//

import SwiftUI

struct MyMirrorsView: View {
    @Bindable var library: MirrorLibrary
    var onEditMirror: (MyMirror) -> Void
    /// 새 거울을 시작한다. 빈 거울이거나, 외부에서 가져온 디자인이 깔린 거울이다.
    var onCreateMirror: (MirrorDesign) -> Void = { _ in }
    /// 아직 아무 거울도 없을 때 상점으로 보낸다.
    var onBrowseStore: () -> Void = {}

    @State private var filter: MyMirrorFilter = .all
    @State private var actionTarget: MyMirror?
    @State private var notice: String?
    @State private var showsSlotFull = false
    /// 만들기 다이얼로그가 닫히면 가져오기 시트를 연다.
    @State private var wantsArtworkImport = false
    @State private var isChoosingCreateStyle = false
    @State private var isImportingArtwork = false
    /// 상점 등록 준비 중인 거울. 실제 등록이 아니라 판매 정보 작성이다.
    @State private var publishTarget: MyMirror?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 판매 상태의 authority. RootView가 소유한 하나를 쓴다.
    @Environment(MarketplaceStore.self) private var marketplace
    @Environment(AuthSession.self) private var session
    /// 담을 수 있는 칸의 authority. 산 칸은 서버에 있다.
    /// **optional이다** — 이 화면을 따로 그리는 곳(미리보기 · 테스트)에 환경값이 없다.
    @Environment(MirrorCapacityStore.self) private var capacity: MirrorCapacityStore?

    /// 확장 확인 창.
    @State private var isConfirmingExpand = false

    private var mirrors: [MyMirror] {
        // **판매 중은 서버가 정한다.** `MirrorOrigin.listed`를 설정하는 코드가 없어서
        // 이 필터는 늘 비어 있었다 — 실제로 팔고 있어도 안 보였다.
        //
        // 이제 서버 판매 목록(`published`)과 `sourceContentId`로 맞춘다.
        // **제목으로 맞추지 않는다** — 같은 제목이 여럿일 수 있다.
        if filter == .listed {
            let ids = Set(marketplace.selling(contentType: "mirror").map(\.sourceContentId))
            return library.mirrors.filter { ids.contains($0.id) }
        }
        guard let origin = filter.origin else { return library.mirrors }
        return library.mirrors.filter { $0.origin == origin }
    }

    /// 이 거울이 지금 상점에서 팔리고 있는가. 카드의 배지가 쓴다.
    private func isSelling(_ mirror: MyMirror) -> Bool {
        marketplace.sellingListing(forContentID: mirror.id, contentType: "mirror") != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("내 거울")
                .font(InkFont.pageTitle)
                .foregroundStyle(PaperTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 14)

            HStack(spacing: 12) {
                // **보관 중인 전부**를 센다. 만든 것만 세면 화면 숫자와 실제로 담을 수
                // 있는 양이 달라서, 왜 더 못 담는지 설명할 수 없다.
                //
                // 칸 수는 서버가 정한다 — 조각으로 산 칸은 이 기기가 아니라 서버에 있다.
                Text("보관 중 \(library.storedCount) / \(library.mirrorCapacity)")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(
                        "거울 \(library.storedCount)개 보관 중, 최대 \(library.mirrorCapacity)개"
                    )

                expandButton

                createButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            InkFilterBar(items: MyMirrorFilter.allCases, selection: $filter) { $0.rawValue }
                .padding(.bottom, 14)

            gallery
        }
        // 판매 상태는 서버가 authority다. 화면에 들어올 때와 로그인이 바뀔 때 받는다.
        .task(id: session.server?.userID) {
            await marketplace.refreshMyListings(session: session.server)
        }
        .inkDialog(isPresented: Binding(
            get: { actionTarget != nil },
            set: { if !$0 { actionTarget = nil } }
        )) {
            if let mirror = actionTarget {
                InkDialogBody(
                    title: mirror.name,
                    message: nil,
                    actions: actions(for: mirror),
                    onAction: { actionTarget = nil }
                )
            }
        }
        .inkDialog(
            "준비 중",
            message: notice,
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
        .inkDialog(
            "새 거울 만들기",
            message: "빈 거울에서 시작하거나, 그림 앱에서 만든 디자인을 가져올 수 있어요.",
            isPresented: $isChoosingCreateStyle,
            // 다이얼로그가 **완전히 닫힌 뒤** 가져오기 시트를 연다.
            onDismiss: {
                if wantsArtworkImport {
                    wantsArtworkImport = false
                    isImportingArtwork = true
                }
            }
        ) {
            [
                InkDialogAction("꾸미러에서 만들기", role: .primary) { onCreateMirror(.blank) },
                InkDialogAction("외부에서 만들기") { wantsArtworkImport = true },
                InkDialogAction("취소"),
            ]
        }
        .inkBottomSheet(item: $publishTarget, size: .fraction(0.92)) { mirror in
            PublishMirrorView(mirror: mirror, library: library)
        }
        .inkBottomSheet(isPresented: $isImportingArtwork, size: .fraction(0.92)) {
            ExternalArtworkView { artwork in
                var design = MirrorDesign.blank
                design.importedArtworks = [artwork]
                onCreateMirror(design)
            }
        }
        .inkMirrorStorageFullDialog(
            "만들려면",
            isPresented: $showsSlotFull,
            library: library,
            // `+칸 늘리기` 버튼도 **같은 확인 창**을 연다. 창을 두 번 만들지 않는다.
            isConfirmingExpansion: $isConfirmingExpand
        )
        // 화면에 들어올 때 한 번 읽는다. 다시 그릴 때마다 부르지 않는다.
        .task(id: session.server?.userID) {
            await capacity?.refresh(session: session.server, library: library)
        }
    }

    /// 카드 아래에 **바로 보이는** 상점 등록 CTA.
    ///
    /// 예전에는 동작 목록을 열어야만 보였고, 그래서 아무도 찾지 못했다.
    /// 등록은 **여기 한 곳**에서만 시작한다 — 같은 동작을 두 곳에 두지 않는다.
    ///
    /// 등록할 수 없는 거울이라도 **조용히 감추지 않는다.** 눌리면 이유를 알려준다.
    private func publishButton(for mirror: MyMirror) -> some View {
        let isEligible = MirrorPublishPolicy.isEligible(mirror)
        return Button {
            if isEligible {
                publishTarget = mirror
            } else {
                notice = "직접 만든 거울만 상점에 등록할 수 있어요."
            }
        } label: {
            Label("상점에 등록", systemImage: "tray.and.arrow.up")
                .font(InkFont.caption.weight(.semibold))
                .foregroundStyle(isEligible ? PaperTheme.ink : PaperTheme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 32)
                .background {
                    let shape = UnevenRoundedRectangle.ink(12, 10, 13, 11)
                    shape.stroke(
                        isEligible ? PaperTheme.ink : PaperTheme.separator,
                        lineWidth: InkLine.regular
                    )
                }
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel("\(mirror.name) 상점에 등록")
    }

    /// 거울 하나에 대해 할 수 있는 것. **스티커와 같은 구성이다** — 하나만 다르면 헷갈린다.
    ///
    /// 복제와 공유하기는 뺐다. 사진에 저장은 남는다 —
    /// 공유를 없앤다고 앱 밖으로 꺼내는 길까지 막지 않는다.
    /// 상점 등록은 카드 아래 CTA에 있다.
    private func actions(for mirror: MyMirror) -> [InkDialogAction] {
        var actions = [
            InkDialogAction("적용", role: .primary) { library.apply(mirror) },
            InkDialogAction("꾸미기") { onEditMirror(mirror) },
        ]
        // 상점 등록은 **카드 아래 CTA 한 곳**에서만 한다 — 같은 동작을 두 곳에 두지 않는다.
        // 내가 만든 거울만 앱 밖으로 나간다 — 상점 artwork를 원본 파일로 꺼내가지 않는다.
        if OwnContentExportPolicy.canExport(mirror) {
            actions.append(InkDialogAction("사진에 저장") { save(mirror) })
        }
        if mirror.origin != .basic {
            actions.append(InkDialogAction("삭제", role: .destructive) { library.delete(mirror) })
        }
        actions.append(InkDialogAction("닫기"))
        return actions
    }

    // MARK: - 내보내기

    /// 사진 앱에 PNG로 저장한다. **화면을 찍지 않는다** — 1080 × 2340으로 다시 그린다.
    private func save(_ mirror: MyMirror) {
        Task {
            do {
                let png = try OwnContentExport.mirrorPNG(mirror)
                if let failure = await OwnContentExport.saveToPhotos(png: png) {
                    notice = failure.message
                } else {
                    notice = "사진 앱에 저장했어요."
                }
            } catch {
                notice = (error as? OwnContentExportFailure)?.message
                    ?? OwnContentExportFailure.renderingFailed.message
            }
        }
    }


    /// 거울이 있든 없든 항상 여기서 새 거울을 시작할 수 있다.
    private var createButton: some View {
        Button {
            createMirror()
        } label: {
            Label("거울 만들기", systemImage: "plus")
                .font(InkFont.caption.weight(.semibold))
                .foregroundStyle(PaperTheme.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background {
                    Capsule().stroke(PaperTheme.ink, lineWidth: 1.6)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel("새 거울 만들기")
    }

    /// 조각으로 칸을 늘린다. **가격과 칸 수는 서버가 알려준 값**이다.
    ///
    /// 상품을 못 읽었으면(로그아웃 · 서버 미도달) 보여 주지 않는다 —
    /// 누를 수 없는 버튼이나 지어낸 숫자를 두지 않는다.
    @ViewBuilder
    private var expandButton: some View {
        if let pack = capacity?.pack {
            Button {
                isConfirmingExpand = true
            } label: {
                HStack(spacing: 4) {
                    Text("+\(pack.slotDelta)칸")
                    ShardAmount(amount: pack.costShards, font: InkFont.caption, iconSize: 13)
                }
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.ink)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background {
                    UnevenRoundedRectangle.ink(13, 11, 14, 12)
                        .stroke(PaperTheme.ink, lineWidth: 1.5)
                }
                .contentShape(.rect)
            }
            .buttonStyle(InkPressStyle())
            // 요청 중에는 잠근다 — 연타로 구매 의도가 여러 개 생기면 안 된다.
            .disabled(capacity?.isPurchasing == true)
            .opacity(capacity?.isPurchasing == true ? 0.4 : 1)
            .accessibilityLabel(
                "보관 공간 \(pack.slotDelta)칸 늘리기, \(pack.costShards) 조각"
            )
        }
    }

    /// 보관 공간이 없으면 들어가기 전에 막는다 — 다 꾸미고 나서 저장이 실패하지 않게.
    private func createMirror() {
        guard library.hasFreeMirrorSlot else {
            showsSlotFull = true
            return
        }
        isChoosingCreateStyle = true
    }

    private var gallery: some View {
        ScrollView {
            if library.mirrors.isEmpty {
                emptyState
            } else if mirrors.isEmpty {
                Text("아직 이 조건에 맞는 거울이 없어요.")
                    .font(InkFont.secondary)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: GalleryLayout.columns(for: dynamicTypeSize), spacing: 18) {
                    ForEach(mirrors) { mirror in
                        VStack(spacing: 6) {
                            Button {
                                actionTarget = mirror
                            } label: {
                                MyMirrorItem(
                                    mirror: mirror,
                                    isCurrent: mirror.id == library.currentID,
                                    isSelling: isSelling(mirror)
                                )
                            }
                            .buttonStyle(InkPressStyle())

                            publishButton(for: mirror)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, InkTabBar.reservedHeight + 24, for: .scrollContent)
    }

    /// 처음 설치하면 내 거울은 비어 있다. 빈 화면 대신 다음에 할 일을 보여준다.
    private var emptyState: some View {
        VStack(spacing: 14) {
            MirrorIcon(size: 62)

            VStack(spacing: 6) {
                Text("아직 저장한 거울이 없어요")
                    .font(InkFont.cardTitle)
                    .foregroundStyle(PaperTheme.ink)
                Text("상점에서 거울을 받아보거나 직접 만들어보세요")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button("거울 만들기") { createMirror() }
                    .font(InkFont.body.weight(.semibold))
                    .foregroundStyle(PaperTheme.subtleSurface)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background {
                        UnevenRoundedRectangle.ink(16, 13, 17, 12).fill(PaperTheme.ink)
                    }
                    .buttonStyle(InkPressStyle())

                Button("상점 둘러보기") { onBrowseStore() }
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background {
                        UnevenRoundedRectangle.ink(16, 13, 17, 12)
                            .stroke(PaperTheme.ink, lineWidth: 1.6)
                    }
                    .buttonStyle(InkPressStyle())
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 56)
    }
}

/// 미리보기 + 이름 + 사용 중 표시만. 카드 위에 버튼을 늘어놓지 않는다.
private struct MyMirrorItem: View {
    let mirror: MyMirror
    let isCurrent: Bool
    /// 지금 상점에서 팔리고 있는가. **서버 판매 목록이 authority다.**
    var isSelling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            MirrorPreview(mirror: mirror)
                .padding(.bottom, 6)

            HStack(spacing: 6) {
                Text(mirror.name)
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isSelling {
                    // 사용 중 배지와 같은 모양. 새 디자인을 만들지 않는다.
                    Text("판매 중")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            UnevenRoundedRectangle.ink(10, 8, 11, 9)
                                .stroke(PaperTheme.ink, lineWidth: 1.4)
                        }
                }

                if isCurrent {
                    Text("사용 중")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.subtleSurface)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            UnevenRoundedRectangle.ink(10, 8, 11, 9)
                                .fill(PaperTheme.ink)
                        }
                        .fixedSize()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isCurrent ? "\(mirror.name), 사용 중" : mirror.name)
        .accessibilityHint("두 번 탭하면 적용, 꾸미기 같은 동작을 고를 수 있어요")
    }
}

#Preview {
    MyMirrorsView(library: MirrorLibrary(), onEditMirror: { _ in })
        .paperBackground()
}
