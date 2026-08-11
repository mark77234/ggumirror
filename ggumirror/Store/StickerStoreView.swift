//
//  StickerStoreView.swift
//  ggumirror
//
//  상점의 **스티커** 칸. 세 부분이다.
//
//  1. 스티커 만들기 (V-5A Creator로 들어간다)
//  2. 내 스티커 — `StickerLibrary`가 유일한 진실이다. 가짜 배열을 만들지 않는다
//  3. 스티커 상점 — 서버가 없으므로 **정직하게 빈 상태**다. 가짜 판매자 / 가짜 listing을 만들지 않는다
//
//  로그인 없이 전부 쓸 수 있다. 로그인 wall을 만들지 않는다.
//

import SwiftUI

struct StickerStoreView: View {
    var library: StickerLibrary
    /// 거울 라이브러리는 스티커를 거울에 바로 적용하는 데 쓰인다(이번 Phase에서는 안내만).
    var mirrors: MirrorLibrary?

    @State private var actionTarget: StickerProject?
    @State private var creatorRequest: StickerCreatorRequest?
    @State private var publishTarget: StickerProject?
    @State private var isChoosingStart = false
    @State private var notice: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                createButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)

                sectionTitle("내 스티커", count: library.projects.count)
                if library.projects.isEmpty {
                    emptyStickers
                } else {
                    grid
                }

                sectionTitle("스티커 상점", count: nil)
                    .padding(.top, 26)
                marketplace
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, InkTabBar.reservedHeight + 24, for: .scrollContent)
        // 만들기 시작 방식. 커스텀 다이얼로그를 쓴다.
        .inkDialog(
            "스티커 만들기",
            message: "빈 캔버스에서 그리거나, 사진에서 배경을 지워 시작할 수 있어요.",
            isPresented: $isChoosingStart
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
        // 스티커 하나를 골랐을 때의 동작 목록.
        .inkDialog(isPresented: Binding(
            get: { actionTarget != nil },
            set: { if !$0 { actionTarget = nil } }
        )) {
            if let project = actionTarget {
                InkDialogBody(
                    title: project.name,
                    message: nil,
                    actions: actions(for: project),
                    onAction: { actionTarget = nil }
                )
            }
        }
        .inkDialog(
            "안내",
            message: notice,
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
        .fullScreenCover(item: $creatorRequest) { request in
            StickerCreatorView(
                design: request.design ?? .blankSticker(
                    id: UUID().uuidString, name: library.suggestedName
                ),
                library: library,
                context: request.context,
                startsWithPhoto: request.startsWithPhoto,
                onSaved: { creatorRequest = nil }
            )
        }
        .inkBottomSheet(item: $publishTarget, size: .fraction(0.92)) { project in
            PublishStickerView(project: project, library: library)
        }
    }

    // MARK: - 구역

    private func sectionTitle(_ title: String, count: Int?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(InkFont.sectionTitle)
                .foregroundStyle(PaperTheme.ink)
            if let count {
                Text("\(count)")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var createButton: some View {
        Button { isChoosingStart = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("스티커 만들기")
                        .font(InkFont.cardTitle)
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
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .background {
                let shape = UnevenRoundedRectangle.ink(18, 15, 19, 16)
                shape
                    .fill(PaperTheme.subtleSurface)
                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.emphasis))
            }
            .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        .accessibilityLabel("스티커 만들기")
    }

    private var emptyStickers: some View {
        VStack(spacing: 10) {
            DoodleStickerView(sticker: .sparkle, size: 40, tint: PaperTheme.secondaryInk)
            Text("아직 만든 스티커가 없어요")
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
            Text("직접 만든 스티커는 거울을 꾸밀 때 바로 쓸 수 있어요")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
    }

    private var grid: some View {
        LazyVGrid(columns: GalleryLayout.columns(for: dynamicTypeSize), spacing: 18) {
            ForEach(library.projects.reversed()) { project in
                Button { actionTarget = project } label: {
                    StickerGalleryItem(project: project, library: library)
                }
                .buttonStyle(InkPressStyle())
            }
        }
        .padding(.horizontal, 20)
    }

    /// 서버가 없다. **정직하게 비어 있다고 말한다** — 가짜 목록을 만들지 않는다.
    private var marketplace: some View {
        VStack(spacing: 8) {
            Text("아직 등록된 스티커가 없어요")
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
            Text("다른 사람이 만든 스티커를 사고파는 기능은 준비 중이에요")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .background {
            let shape = UnevenRoundedRectangle.ink(18, 15, 19, 16)
            shape.stroke(PaperTheme.separator, style: StrokeStyle(lineWidth: 1.4, dash: [6, 5]))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 동작

    private func actions(for project: StickerProject) -> [InkDialogAction] {
        [
            InkDialogAction("사용하기", role: .primary) {
                notice = "거울 꾸미기 → 스티커 → 내 스티커에서 이 스티커를 놓을 수 있어요."
            },
            InkDialogAction("꾸미기") {
                // 같은 스티커를 고친다. 새 스티커가 생기지 않는다.
                creatorRequest = StickerCreatorRequest(
                    design: project.design,
                    context: .editExisting(project.id)
                )
            },
            InkDialogAction("복제") { library.duplicate(project) },
            InkDialogAction("상점에 올리기") { publishTarget = project },
            InkDialogAction("삭제", role: .destructive) { library.delete(project) },
            InkDialogAction("닫기"),
        ]
    }
}

// MARK: - 카드

/// 내 스티커 카드. 투명 PNG라 뒤에 아주 옅은 체크무늬를 깐다 —
/// **미리보기 배경일 뿐이고 최종 PNG는 그대로 투명하다.**
struct StickerGalleryItem: View {
    let project: StickerProject
    var library: StickerLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                TransparencyCheckerboard(cell: 12)
                if let image = library.finalImage(for: project) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(UnevenRoundedRectangle.ink(16, 13, 17, 14))
            .overlay(
                UnevenRoundedRectangle.ink(16, 13, 17, 14)
                    .stroke(PaperTheme.ink, lineWidth: InkLine.regular)
            )

            Text(project.name)
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("스티커, \(project.name)")
    }
}
