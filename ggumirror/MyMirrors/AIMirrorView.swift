//
//  AIMirrorView.swift
//  ggumirror
//
//  한 문장으로 거울 만들기.
//
//  대화형 화면을 만들지 않는다 — 문장 하나 쓰고, 기다리고, 저장하거나 다시 만든다.
//  그게 전부다.
//
//  **비싼 요청을 헛되이 보내지 않는다.** 보관 공간이 없으면 만들기 전에 막는다.
//

import SwiftUI

@MainActor
@Observable
final class AIMirrorMaker {
    enum State: Equatable {
        case idle
        case generating
        case ready
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var config: AIMirrorConfig?
    /// 방금 만들어진 거울. 저장하기 전까지 여기에만 있다.
    private(set) var artwork: ImportedArtworkObject?

    private let backend: any AIMirrorBackend

    init(backend: any AIMirrorBackend = BackendClient()) {
        self.backend = backend
    }

    var isGenerating: Bool { state == .generating }
    var remaining: Int { config?.remaining ?? 0 }

    func refresh(session: ServerSession?) async {
        guard let token = session?.accessToken else {
            config = nil
            return
        }
        config = try? await backend.aiMirrorConfig(accessToken: token)
    }

    /// 값. **서버가 준 값을 그대로 쓴다** — 앱에 숫자를 적으면 서버와 갈라진다.
    var price: Int { config?.price ?? 0 }

    /// 지금 만들 수 있을 만큼 조각이 있는가. **화면을 위한 판단일 뿐이다** —
    /// 진짜 판단은 서버가 하고, 모자라면 provider를 부르기 전에 거절한다.
    func canAfford(balance: Int?) -> Bool {
        guard let balance, price > 0 else { return true }
        return balance >= price
    }

    /// 만든다. **한 번에 하나만** — 연타로 두 번 요청하면 하루 몫이 두 번 빠진다.
    ///
    /// `requestID`는 이 시도를 가리키는 멱등 키다. 같은 시도를 다시 보내면
    /// 서버가 조각을 다시 빼지 않는다.
    func generate(prompt: String, session: ServerSession?) async {
        guard !isGenerating else { return }
        guard let token = session?.accessToken else {
            state = .failed(AIMirrorFailure.notSignedIn.message)
            return
        }
        guard let cleaned = AIMirrorPrompt.normalized(prompt) else {
            state = .failed("무엇을 만들지 한 줄로 적어 주세요.")
            return
        }

        state = .generating
        artwork = nil
        do {
            let png = try await backend.generateAIMirror(
                prompt: cleaned, requestID: UUID().uuidString, accessToken: token
            )
            // **AI가 만든 것을 믿지 않는다.** 규격은 여기서 찍고 Phase C가 마무리한다.
            let image = try GeneratedMirrorAdapter.prepare(png)
            artwork = ImportedArtworkObject(
                assetID: ImportedArtworkAssetStore.shared.register(image)
            )
            state = .ready
        } catch let failure as AIMirrorFailure {
            state = .failed(failure.message)
        } catch let failure as MirrorImportFailure {
            // 규격으로 만들지 못했다. **거울을 저장하지 않는다.**
            state = .failed(failure.message)
        } catch {
            state = .failed(AIMirrorFailure.unavailable.message)
        }
        await refresh(session: session)
    }

    func reset() {
        state = .idle
        artwork = nil
    }
}

/// 프롬프트 규칙. 서버도 같은 것을 본다 — 화면에서 먼저 걸러 줄 뿐이다.
nonisolated enum AIMirrorPrompt {
    static let maxLength = 300

    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    static let examples = [
        "핑크 리본과 작은 하트가 있는 손그림 거울",
        "Y2K 실버 하트 거울",
        "검은 잉크 낙서 스타일",
        "따뜻한 크림색 다이어리 느낌",
    ]
}

// MARK: - 화면

struct AIMirrorView: View {
    var library: MirrorLibrary
    var onSaved: () -> Void

    @State private var maker = AIMirrorMaker()
    @State private var prompt = ""
    @State private var showsStorageFull = false
    @State private var insufficientNotice: String?
    @State private var notice: String?
    @Environment(AuthSession.self) private var session
    /// 잔액. **서버가 authority다** — 여기서 임의로 줄이지 않는다.
    /// 미리보기·테스트에는 없을 수 있어 optional이다.
    @Environment(ShardWallet.self) private var wallet: ShardWallet?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("어떤 거울을 만들까요?")
                    .font(InkFont.cardTitle)
                    .foregroundStyle(PaperTheme.ink)

                TextField("예: \(AIMirrorPrompt.examples[0])", text: $prompt, axis: .vertical)
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .lineLimit(3...5)
                    .focused($isPromptFocused)
                    .onChange(of: prompt) { _, value in
                        if value.count > AIMirrorPrompt.maxLength {
                            prompt = String(value.prefix(AIMirrorPrompt.maxLength))
                        }
                    }
                    .disabled(maker.isGenerating)
                    .padding(14)
                    .background {
                        let shape = UnevenRoundedRectangle.ink(15, 18, 19, 14)
                        shape.fill(PaperTheme.subtleSurface)
                            .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.8))
                    }

                if let config = maker.config, config.available {
                    HStack(spacing: 8) {
                        // **값은 서버가 준 것을 그대로 보여 준다.** 조각 아이콘은
                        // 상점·지갑이 쓰는 것과 같은 컴포넌트다.
                        if config.price > 0 {
                            ShardAmount(amount: config.price, font: InkFont.caption, iconSize: 14)
                        }
                        Text("오늘 \(config.remaining)번 남았어요.")
                            .font(InkFont.caption)
                            .foregroundStyle(PaperTheme.secondaryInk)
                        Spacer(minLength: 0)
                    }
                }

                if let artwork = maker.artwork {
                    result(artwork)
                } else {
                    generateButton
                }

                if case .failed(let message) = maker.state {
                    Text(message)
                        .font(InkFont.caption)
                        .foregroundStyle(PaperTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .inkDismissesKeyboardOnTap()
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .paperBackground()
        .navigationTitle("AI로 거울 만들기")
        .navigationBarTitleDisplayMode(.inline)
        .task { await maker.refresh(session: session.server) }
        .inkMirrorStorageFullDialog("저장하려면", isPresented: $showsStorageFull, library: library)
        .inkDialog(
            "조각이 부족해요",
            message: insufficientNotice,
            isPresented: Binding(
                get: { insufficientNotice != nil },
                set: { if !$0 { insufficientNotice = nil } }
            )
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
        .inkDialog(
            "AI 거울", message: notice,
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            [InkDialogAction("확인", role: .primary)]
        }
    }

    private var generateButton: some View {
        Button {
            isPromptFocused = false
            Task { await make() }
        } label: {
            Text(maker.isGenerating ? "거울을 그리고 있어요…" : "만들기")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.subtleSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .frame(minHeight: InkTapTarget.minimum)
                .background {
                    UnevenRoundedRectangle.ink(20, 24, 25, 19).fill(PaperTheme.ink)
                }
                .contentShape(.rect)
        }
        .buttonStyle(InkPressStyle())
        // 연타로 두 번 만들면 하루 몫이 두 번 빠진다.
        .disabled(maker.isGenerating)
    }

    @ViewBuilder
    private func result(_ artwork: ImportedArtworkObject) -> some View {
        MirrorPreview(
            style: MirrorLibrary.defaultMirror.style, importedArtworks: [artwork], lineWidth: 2.1
        )
        .frame(maxHeight: 360)

        HStack(spacing: 10) {
            Button {
                // **새로 만드는 것이다** — 하루 몫을 한 번 더 쓴다.
                Task { await make() }
            } label: {
                Text("다시 만들기")
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
            .disabled(maker.isGenerating)

            Button {
                save(artwork)
            } label: {
                Text("내 거울에 저장")
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.subtleSurface)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background {
                        UnevenRoundedRectangle.ink(15, 12, 16, 13).fill(PaperTheme.ink)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(InkPressStyle())
        }
    }

    /// **비싼 요청을 헛되이 보내지 않는다** — 보관 공간부터 본다.
    private func make() async {
        guard library.hasFreeMirrorSlot else {
            showsStorageFull = true
            return
        }
        // **화면에서 먼저 막는 것은 친절일 뿐이다.** 진짜 판단은 서버가 하고,
        // 모자라면 provider를 부르기 전에 거절한다. 여기서 잔액을 고치지 않는다.
        guard maker.canAfford(balance: wallet?.balance) else {
            insufficientNotice = "조각이 부족해요.\nAI 거울을 만들려면 \(maker.price)조각이 필요해요."
            return
        }
        await maker.generate(prompt: prompt, session: session.server)
        // 성공이든 실패든 **서버가 아는 잔액을 다시 읽는다.** 앱이 계산하지 않는다.
        await wallet?.refresh(session: session.server)
    }

    private func save(_ artwork: ImportedArtworkObject) {
        // 만드는 동안 자리가 찼을 수 있다. 저장 직전에 다시 본다.
        guard library.hasFreeMirrorSlot else {
            showsStorageFull = true
            return
        }
        var design = MirrorDesign.blank
        design.name = "AI 거울"
        design.importedArtworks = [artwork]
        // **어떻게 만들었는지 남긴다.** 나중에 이름이나 파일로 추측하지 않기 위해서다.
        switch library.save(
            design, name: design.name, context: .createNew, creationSource: .aiGenerated
        ) {
        case .created, .updated:
            maker.reset()
            onSaved()
            dismiss()
        case .needsMoreSlots:
            showsStorageFull = true
        }
    }
}
