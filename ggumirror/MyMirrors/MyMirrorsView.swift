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
    @State private var isChoosingCreateStyle = false
    @State private var isImportingArtwork = false
    /// 상점 등록 준비 중인 거울. 실제 등록이 아니라 판매 정보 작성이다.
    @State private var publishTarget: MyMirror?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var mirrors: [MyMirror] {
        guard let origin = filter.origin else { return library.mirrors }
        return library.mirrors.filter { $0.origin == origin }
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
                Text("내가 만든 거울 \(library.createdCount) / \(library.createdCapacity)")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("내가 만든 거울 \(library.createdCount)개, 최대 \(library.createdCapacity)개")

                createButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            InkFilterBar(items: MyMirrorFilter.allCases, selection: $filter) { $0.rawValue }
                .padding(.bottom, 14)

            gallery
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
            isPresented: $isChoosingCreateStyle
        ) {
            [
                InkDialogAction("꾸미러에서 만들기", role: .primary) { onCreateMirror(.blank) },
                InkDialogAction("외부에서 만들기") { isImportingArtwork = true },
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
        .inkDialog(
            "거울 보관 공간이 가득 찼어요",
            message: "새 거울을 만들려면 보관 공간을 늘려주세요. 보관 공간 확장은 준비 중이에요.",
            isPresented: $showsSlotFull
        ) {
            [
                InkDialogAction("취소"),
                InkDialogAction("보관 공간 늘리기", role: .primary),
            ]
        }
    }

    /// 거울 하나에 대해 할 수 있는 것. **스티커와 같은 구성이다** — 하나만 다르면 헷갈린다.
    ///
    /// 복제와 공유하기는 뺐다. 사진에 저장은 남는다 —
    /// 공유를 없앤다고 앱 밖으로 꺼내는 길까지 막지 않는다.
    private func actions(for mirror: MyMirror) -> [InkDialogAction] {
        var actions = [
            InkDialogAction("적용", role: .primary) { library.apply(mirror) },
            InkDialogAction("꾸미기") { onEditMirror(mirror) },
        ]
        // 상점에서 받은 거울을 그대로 되파는 흐름은 만들지 않는다.
        // 다만 **버튼을 조용히 감추지 않는다** — 왜 안 되는지 알려준다(스티커와 같은 방식).
        if MirrorPublishPolicy.isEligible(mirror) {
            actions.append(InkDialogAction("상점에 등록") { publishTarget = mirror })
        } else {
            actions.append(InkDialogAction("상점에 등록") {
                notice = "직접 만든 거울만 상점에 등록할 수 있어요."
            })
        }
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

    /// 보관 공간이 없으면 들어가기 전에 막는다 — 다 꾸미고 나서 저장이 실패하지 않게.
    private func createMirror() {
        guard library.hasFreeCreatedSlot else {
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
                        Button {
                            actionTarget = mirror
                        } label: {
                            MyMirrorItem(mirror: mirror, isCurrent: mirror.id == library.currentID)
                        }
                        .buttonStyle(InkPressStyle())
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
