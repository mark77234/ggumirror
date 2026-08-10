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
    /// 아직 아무 거울도 없을 때 상점으로 보낸다.
    var onBrowseStore: () -> Void = {}

    @State private var filter: MyMirrorFilter = .all
    @State private var actionTarget: MyMirror?
    @State private var notice: String?
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

            Text("내가 만든 거울 \(library.createdCount) / \(library.createdCapacity)")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .accessibilityLabel("내가 만든 거울 \(library.createdCount)개, 최대 \(library.createdCapacity)개")

            InkFilterBar(items: MyMirrorFilter.allCases, selection: $filter) { $0.rawValue }
                .padding(.bottom, 14)

            gallery
        }
        .confirmationDialog(
            actionTarget?.name ?? "",
            isPresented: Binding(get: { actionTarget != nil }, set: { if !$0 { actionTarget = nil } }),
            titleVisibility: .visible,
            presenting: actionTarget
        ) { mirror in
            Button("적용") { library.apply(mirror) }
            Button("꾸미기") { onEditMirror(mirror) }
            Button("복제") { library.duplicate(mirror) }
            Button("상점에 올리기") { notice = "상점 등록은 다음 업데이트에서 열려요." }
            if mirror.origin != .basic {
                Button("삭제", role: .destructive) { library.delete(mirror) }
            }
            Button("닫기", role: .cancel) {}
        }
        .alert("준비 중", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
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
    /// "새 거울 만들기"는 아직 없는 기능이라 버튼으로 내지 않는다.
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

            Button("상점 둘러보기") { onBrowseStore() }
                .font(InkFont.body.weight(.semibold))
                .foregroundStyle(PaperTheme.subtleSurface)
                .padding(.horizontal, 22)
                .frame(minHeight: 48)
                .background {
                    UnevenRoundedRectangle.ink(16, 13, 17, 12).fill(PaperTheme.ink)
                }
                .buttonStyle(InkPressStyle())
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
            MirrorPreview(style: mirror.style, strokes: mirror.strokes)
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
