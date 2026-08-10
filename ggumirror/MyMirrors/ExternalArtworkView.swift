//
//  ExternalArtworkView.swift
//  ggumirror
//
//  "외부에서 만들기" — 작업 가이드를 내보내고, 완성한 PNG를 다시 받아온다.
//
//  어려운 기능처럼 보이지 않게 한다. 그림 앱 이름을 조건으로 걸지 않는다 —
//  투명 PNG로 내보낼 수 있는 앱이면 무엇이든 된다.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ExternalArtworkView: View {
    /// 가이드 저장 안내까지 보여줄지. Editor에서 "교체"할 때는 파일 고르기만 필요하다.
    var showsGuide = true
    /// 사용자가 "이 디자인 사용"을 눌렀을 때. asset은 이미 보관된 상태다.
    var onUse: (ImportedArtworkObject) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var guideURL: URL?
    @State private var photoItem: PhotosPickerItem?
    @State private var isImportingFile = false
    @State private var isWorking = false
    /// 승인 전 상태. 여기서 "다시 선택"하면 그냥 버린다.
    @State private var candidate: ImportedArtworkObject?
    @State private var problem: ImportProblem?

    private struct ImportProblem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        Group {
            if let candidate {
                preview(candidate)
            } else {
                steps
            }
        }
        .overlay { if isWorking { progress } }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            load(item)
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.png, .image]
        ) { result in
            guard case .success(let url) = result else { return }
            load(url)
        }
        .alert(
            problem?.title ?? "",
            isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } }),
            presenting: problem
        ) { _ in
            Button("다시 선택") { problem = nil }
            Button("취소", role: .cancel) { problem = nil }
        } message: { problem in
            Text(problem.message)
        }
    }

    // MARK: - 안내

    private var steps: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(showsGuide ? "외부에서 거울 만들기" : "디자인 교체하기")
                        .font(InkFont.cardTitle)
                        .foregroundStyle(PaperTheme.ink)
                    Text("작업 가이드를 저장하고 원하는 그림 앱에서 꾸며보세요.")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                }

                if showsGuide {
                    step(1, "작업 가이드 저장", "1080 × 2340 크기의 투명 PNG예요.")
                    guideShare
                    step(2, "외부 그림 앱에서 작업", "프로크리에이트, 아이비스페인트, 포토샵 등 어떤 앱이든 좋아요.")
                    step(3, "투명 PNG로 내보내기", "프레임 부분만 그리고 배경은 비운 채로 내보내 주세요.")
                    step(4, "완성 파일 가져오기", "아래에서 완성한 PNG를 골라주세요.")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("점선 바깥 프레임만 사용해요")
                        .font(InkFont.secondary)
                        .foregroundStyle(PaperTheme.ink)
                    Text("점선 안쪽은 실제 거울에서 카메라가 보이는 자리예요. 그 안쪽을 그려도 가져올 때 자동으로 지워지니, 프레임 부분을 꾸며주세요.")
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    let shape = UnevenRoundedRectangle.ink(16, 13, 17, 12)
                    shape.fill(PaperTheme.subtleSurface)
                        .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.5))
                }

                importControls
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(InkFont.caption.weight(.semibold))
                .foregroundStyle(PaperTheme.subtleSurface)
                .frame(width: 24, height: 24)
                .background(Circle().fill(PaperTheme.ink))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                Text(detail)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// 가이드는 임시 파일이다. 사용자 콘텐츠 저장소에 넣지 않는다.
    @ViewBuilder
    private var guideShare: some View {
        if let guideURL {
            ShareLink(item: guideURL) {
                Label("작업 가이드 저장하기", systemImage: "square.and.arrow.up")
                    .font(InkFont.body.weight(.semibold))
                    .foregroundStyle(PaperTheme.subtleSurface)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background {
                        UnevenRoundedRectangle.ink(16, 13, 17, 12).fill(PaperTheme.ink)
                    }
            }
            .buttonStyle(InkPressStyle())
        } else {
            Button("작업 가이드 저장하기") { guideURL = try? MirrorArtworkGuide.exportPNG() }
                .font(InkFont.body.weight(.semibold))
                .foregroundStyle(PaperTheme.subtleSurface)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background {
                    UnevenRoundedRectangle.ink(16, 13, 17, 12).fill(PaperTheme.ink)
                }
                .buttonStyle(InkPressStyle())
                .task { guideURL = try? MirrorArtworkGuide.exportPNG() }
        }
    }

    private var importControls: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Label("사진에서 가져오기", systemImage: "photo")
                    .font(InkFont.body.weight(.semibold))
                    .foregroundStyle(PaperTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background {
                        UnevenRoundedRectangle.ink(16, 13, 17, 12)
                            .stroke(PaperTheme.ink, lineWidth: 1.6)
                    }
            }
            .buttonStyle(InkPressStyle())

            Button {
                isImportingFile = true
            } label: {
                Label("파일에서 가져오기", systemImage: "folder")
                    .font(InkFont.body.weight(.semibold))
                    .foregroundStyle(PaperTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background {
                        UnevenRoundedRectangle.ink(16, 13, 17, 12)
                            .stroke(PaperTheme.ink, lineWidth: 1.6)
                    }
            }
            .buttonStyle(InkPressStyle())
        }
    }

    // MARK: - 확인

    /// 실제 거울 geometry 위에 얹어 보여준다. 여기서 정렬과 투명도를 눈으로 확인한다.
    private func preview(_ artwork: ImportedArtworkObject) -> some View {
        VStack(spacing: 14) {
            Text("이대로 쓸까요?")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)
                .padding(.top, 20)

            Text("점선 없이 실제 거울처럼 보여드려요. 가운데 어두운 부분은 실제로는 카메라가 보여요.")
                .font(InkFont.caption)
                .foregroundStyle(PaperTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            MirrorCanvasView(design: previewDesign(artwork))
                .padding(.horizontal, 40)

            HStack(spacing: 10) {
                Button("다시 선택") { candidate = nil }
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background {
                        UnevenRoundedRectangle.ink(16, 13, 17, 12)
                            .stroke(PaperTheme.ink, lineWidth: 1.6)
                    }
                    .buttonStyle(InkPressStyle())

                Button("이 디자인 사용") {
                    onUse(artwork)
                    dismiss()
                }
                .font(InkFont.body.weight(.semibold))
                .foregroundStyle(PaperTheme.subtleSurface)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background {
                    UnevenRoundedRectangle.ink(16, 13, 17, 12).fill(PaperTheme.ink)
                }
                .buttonStyle(InkPressStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func previewDesign(_ artwork: ImportedArtworkObject) -> MirrorDesign {
        var design = MirrorDesign.blank
        design.importedArtworks = [artwork]
        return design
    }

    private var progress: some View {
        VStack(spacing: 12) {
            ProgressView().tint(PaperTheme.ink)
            Text("디자인을 확인하는 중...")
                .font(InkFont.body)
                .foregroundStyle(PaperTheme.ink)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background {
            let shape = UnevenRoundedRectangle.ink(18, 15, 19, 16)
            shape.fill(PaperTheme.subtleSurface)
                .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperTheme.ink.opacity(0.12))
        .contentShape(.rect)
        .accessibilityLabel("디자인을 확인하는 중")
    }

    // MARK: - 읽기

    private func load(_ item: PhotosPickerItem) {
        isWorking = true
        Task {
            defer {
                isWorking = false
                photoItem = nil
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                problem = Self.unreadable
                return
            }
            accept(data)
        }
    }

    private func load(_ url: URL) {
        isWorking = true
        defer { isWorking = false }
        // 파일 앱에서 온 경로는 잠깐 열어야 읽을 수 있다.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            problem = Self.unreadable
            return
        }
        accept(data)
    }

    /// 비율이 다르면 늘려서 왜곡시키지 않고 되묻는다.
    /// 카메라 영역은 `normalize`가 이미 지워서 온다 — 여기서 따로 검사하지 않는다.
    private func accept(_ data: Data) {
        do {
            let image = try MirrorArtworkImporter.normalize(data)
            candidate = ImportedArtworkObject(
                assetID: ImportedArtworkAssetStore.shared.register(image)
            )
        } catch ArtworkImportError.wrongAspectRatio(let width, let height) {
            problem = ImportProblem(
                title: "작업 가이드와 비율이 달라요",
                message: "가져온 이미지는 \(width) × \(height)예요. 1080 × 2340과 같은 비율(9 : 19.5)로 다시 내보내 주세요."
            )
        } catch {
            problem = Self.unreadable
        }
    }

    private static let unreadable = ImportProblem(
        title: "이미지를 읽지 못했어요",
        message: "투명 PNG로 내보낸 파일인지 확인하고 다시 골라주세요."
    )
}

#Preview {
    ExternalArtworkView(onUse: { _ in })
        .paperBackground()
}
