//
//  InkModal.swift
//  ggumirror
//
//  앱이 직접 띄우는 Bottom Sheet / Dialog.
//
//  시스템 `.sheet` / `.confirmationDialog` / `.alert`은 회색 dim · 시스템 grabber ·
//  시스템 버튼 스타일을 함께 들고 온다. 종이 배경만 갈아 끼워도 "iOS 시트에 종이를 깐 것"이라
//  꾸미러 화면이 아니게 된다. 그래서 뜨는 방식부터 종이 카드로 만든다.
//
//  **시스템이 소유한 UI는 절대 흉내 내지 않는다**:
//  Sign in with Apple · PhotosPicker · fileImporter · ShareLink · 권한 알림.
//
//  색은 언제나 PaperTheme 고정값이다. `@Environment(\.colorScheme)`를 보지 않는다 —
//  시스템 다크 모드를 켰다고 앱 색이 바뀌면 안 된다.
//

import SwiftUI

// MARK: - 움직임

/// 모든 모달이 공유하는 등장·퇴장 곡선. 값을 화면마다 다시 적지 않는다.
/// 튕기는 spring을 쓰지 않는다 — 종이가 튀어오르지는 않는다.
enum InkMotion {
    static let duration = 0.26
    static var modal: Animation { .easeInOut(duration: duration) }
    /// 끌던 손을 뗐을 때 제자리로 돌아가는 움직임.
    static var settle: Animation { .easeInOut(duration: 0.18) }
}

// MARK: - 닫기

/// 커스텀 모달을 닫는 손잡이.
///
/// **시스템 `@Environment(\.dismiss)`를 시트 내용에서 쓰면 안 된다.** 커스텀 오버레이는
/// 실제 presentation이 아니라서, dismiss가 시트가 아니라 **뒤에 있는 화면**
/// (Editor의 fullScreenCover · NavigationStack)까지 닫아 버린다.
/// 실제로 "텍스트 추가 → 취소"가 Editor를 통째로 닫고 홈으로 나가는 버그가 있었다.
private struct InkModalDismissKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// 지금 떠 있는 종이 시트 / 다이얼로그만 닫는다.
    var inkModalDismiss: () -> Void {
        get { self[InkModalDismissKey.self] }
        set { self[InkModalDismissKey.self] = newValue }
    }
}

// MARK: - 크기

/// Bottom Sheet 높이. 시스템 `presentationDetents`를 대신한다.
enum InkSheetSize {
    /// 내용 높이만큼. 화면의 86%를 넘지 않는다.
    case content
    /// 화면 높이의 비율. 안에 스크롤이 있는 시트에 쓴다.
    case fraction(CGFloat)

    /// 테스트에서도 확인하므로 감추지 않는다.
    func maxHeight(in screen: CGFloat) -> CGFloat {
        switch self {
        case .content: screen * 0.86
        case .fraction(let value): screen * min(value, 0.94)
        }
    }

    var fitsContent: Bool {
        if case .content = self { return true }
        return false
    }
}

/// 시트 내용이 지켜야 하는 여백.
///
/// 카드 **내용**은 아래 safe area를 지키고(홈 인디케이터 위에서 끝난다),
/// 종이 면만 `InkModalSurface`가 그 아래까지 이어 그린다. 그래서 여기 값은
/// "홈 인디케이터와의 거리"가 아니라 **마지막 액션과 종이 경계 사이의 숨 쉴 자리**다.
///
/// 값을 화면마다 다시 적지 않는다 — 시트마다 다른 숫자를 쓰면 같은 앱으로 보이지 않는다.
enum InkSheetMetrics {
    /// 스크롤 밖에 고정하는 액션 줄의 아래 여백.
    static let actionClearance: CGFloat = 20
}

// MARK: - 공용 표면

/// 모달을 덮는 dim. 회색이 아니라 잉크가 옅게 번진 느낌이다.
/// **아래 화면의 탭을 막는다** — 실수로 뒤를 누르는 일이 없다.
private struct InkDim: View {
    let onTap: (() -> Void)?

    var body: some View {
        PaperTheme.ink.opacity(0.28)
            .ignoresSafeArea()
            .contentShape(.rect)
            .onTapGesture { onTap?() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("닫기")
            .accessibilityHidden(onTap == nil)
            .transition(.opacity)
    }
}

/// 손으로 그은 손잡이. 시스템 grabber처럼 반듯한 알약이 아니다.
struct InkSheetHandle: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 1, y: size.height * 0.64))
            path.addQuadCurve(
                to: CGPoint(x: size.width - 1, y: size.height * 0.44),
                control: CGPoint(x: size.width * 0.5, y: size.height * 0.1)
            )
            context.stroke(
                path,
                with: .color(PaperTheme.ink.opacity(0.5)),
                style: StrokeStyle(lineWidth: 3.4, lineCap: .round)
            )
        }
        .frame(width: 44, height: 10)
        .accessibilityHidden(true)
    }
}

/// 종이 면. Bottom Sheet는 위 모서리만, Dialog는 네 모서리가 둥글다.
private struct InkModalSurface: View {
    var isSheet: Bool

    var body: some View {
        let shape = isSheet
            ? UnevenRoundedRectangle.ink(24, 21, 0, 0)
            : UnevenRoundedRectangle.ink(22, 26, 23, 25)
        shape
            .fill(PaperTheme.paper)
            .overlay(shape.stroke(PaperTheme.ink, lineWidth: InkLine.emphasis))
            // 종이가 아래 safe area까지 내려간다 — 홈 인디케이터 쪽에 빈 자리가 생기지 않는다.
            .ignoresSafeArea(edges: isSheet ? .bottom : [])
    }
}

// MARK: - Bottom Sheet

private struct InkBottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var size: InkSheetSize
    var dismissesOnBackgroundTap: Bool
    @ViewBuilder var sheetContent: () -> SheetContent

    /// 끌어내리는 중의 이동량. 손을 떼면 0으로 돌아가거나 닫힌다.
    @State private var drag: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack(alignment: .bottom) {
                        // dim만 화면 끝까지 덮는다.
                        InkDim(onTap: dismissesOnBackgroundTap ? { close() } : nil)

                        // 카드는 safe area를 지킨다 — 내용이 홈 인디케이터 아래로 들어가지 않는다.
                        // 종이 면만 `InkModalSurface`에서 아래 safe area까지 내려간다.
                        GeometryReader { geometry in
                            card(available: geometry.size.height)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .accessibilityAddTraits(.isModal)
                }
            }
            .animation(InkMotion.modal, value: isPresented)
            .onChange(of: isPresented) { _, _ in drag = 0 }
    }

    private func close() {
        guard isPresented else { return }   // 닫히는 중 두 번 눌려도 한 번만 처리한다
        isPresented = false
    }

    private func card(available: CGFloat) -> some View {
        VStack(spacing: 0) {
            InkSheetHandle()
                .padding(.top, 10)
                .padding(.bottom, 6)

            sheetContent()
                .frame(maxWidth: .infinity)
                // 내용은 이 손잡이로만 닫는다. 시스템 dismiss는 뒤 화면을 닫아 버린다.
                .environment(\.inkModalDismiss) { close() }
        }
        .frame(maxWidth: .infinity)
        .modifier(SheetHeight(size: size, available: available))
        .background { InkModalSurface(isSheet: true) }
        .offset(y: max(drag, 0))
        .gesture(
            DragGesture()
                .onChanged { drag = max($0.translation.height, 0) }
                .onEnded { value in
                    if value.translation.height > 110 || value.predictedEndTranslation.height > 260 {
                        close()
                    } else {
                        withAnimation(InkMotion.settle) { drag = 0 }
                    }
                }
        )
        .transition(.move(edge: .bottom))
    }
}

/// 시트 높이를 **한 번만** 정한다.
///
/// 예전에는 `maxHeight`(비율)를 준 뒤 다시 `maxHeight: .infinity`를 걸었는데,
/// 나중 것이 이겨서 카드가 화면 전체를 차지하고 내용이 위로 붙어 버렸다
/// (아래에 빈 종이가 잔뜩 남는 증상). 그래서 경우마다 딱 하나의 frame만 준다.
private struct SheetHeight: ViewModifier {
    let size: InkSheetSize
    let available: CGFloat

    func body(content: Content) -> some View {
        switch size {
        case .content:
            // 내용만큼. 너무 길어지면 상한에서 멈춘다.
            content.frame(maxHeight: size.maxHeight(in: available), alignment: .top)
        case .fraction:
            // 정해진 높이를 그대로 쓴다. 안의 스크롤이 이 높이를 채운다.
            content.frame(height: size.maxHeight(in: available), alignment: .top)
        }
    }
}

// MARK: - Dialog

/// Dialog 버튼 하나. 역할에 따라 모양이 갈린다.
struct InkDialogAction: Identifiable {
    enum Role {
        /// 잉크로 채운 주 버튼.
        case primary
        /// 테두리만 있는 보조 버튼.
        case secondary
        /// 되돌릴 수 없는 동작. 테두리를 굵게 하고 글씨를 굵게 쓴다.
        case destructive
    }

    let id = UUID()
    let title: String
    var role: Role = .secondary
    let handler: () -> Void

    init(_ title: String, role: Role = .secondary, handler: @escaping () -> Void = {}) {
        self.title = title
        self.role = role
        self.handler = handler
    }
}

private struct InkDialogModifier<DialogContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var dismissesOnBackgroundTap: Bool
    @ViewBuilder var dialogContent: () -> DialogContent

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        InkDim(onTap: dismissesOnBackgroundTap ? { close() } : nil)

                        dialogContent()
                            .environment(\.inkModalDismiss) { close() }
                            .frame(maxWidth: 340)
                            .background { InkModalSurface(isSheet: false) }
                            .padding(.horizontal, 24)
                            // 커지며 나타나고 작아지며 사라진다. 튕기지 않는다.
                            .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .accessibilityAddTraits(.isModal)
                }
            }
            .animation(InkMotion.modal, value: isPresented)
    }

    private func close() {
        guard isPresented else { return }
        isPresented = false
    }
}

/// 제목 + 설명 + 버튼으로 이뤄진 기본 Dialog 내용.
struct InkDialogBody: View {
    let title: String
    var message: String?
    let actions: [InkDialogAction]
    /// 버튼을 눌렀을 때 먼저 불린다. 닫기는 여기서 한 번만 한다.
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Text(message)
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 버튼이 셋 이상이면 가로로 좁아지므로 세로로 쌓는다.
            if actions.count > 2 {
                VStack(spacing: 8) { buttons }
            } else {
                HStack(spacing: 10) { buttons }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    private var buttons: some View {
        ForEach(actions) { action in
            Button {
                onAction()
                action.handler()
            } label: {
                Text(action.title)
                    .font(action.role == .secondary ? InkFont.body : InkFont.button)
                    .foregroundStyle(action.role == .primary ? PaperTheme.paper : PaperTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background {
                        let shape = InkCorner.control
                        shape
                            .fill(action.role == .primary ? PaperTheme.ink : PaperTheme.subtleSurface)
                            .overlay(shape.stroke(
                                PaperTheme.ink,
                                lineWidth: action.role == .destructive ? InkLine.emphasis : InkLine.regular
                            ))
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(InkPressStyle())
        }
    }
}

// MARK: - 쓰는 쪽

extension View {
    /// 아래에서 올라오는 종이 시트. 시스템 `.sheet`를 대신한다.
    func inkBottomSheet<Content: View>(
        isPresented: Binding<Bool>,
        size: InkSheetSize = .content,
        dismissesOnBackgroundTap: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(InkBottomSheetModifier(
            isPresented: isPresented,
            size: size,
            dismissesOnBackgroundTap: dismissesOnBackgroundTap,
            sheetContent: content
        ))
    }

    /// 값이 있을 때 올라오는 종이 시트. 시스템 `.sheet(item:)`을 대신한다.
    func inkBottomSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        size: InkSheetSize = .content,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(InkItemSheetModifier(item: item, size: size, sheetContent: content))
    }

    /// 화면 가운데 뜨는 종이 Dialog. 내용을 직접 채운다.
    func inkDialog<Content: View>(
        isPresented: Binding<Bool>,
        dismissesOnBackgroundTap: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(InkDialogModifier(
            isPresented: isPresented,
            dismissesOnBackgroundTap: dismissesOnBackgroundTap,
            dialogContent: content
        ))
    }

    /// 제목 + 설명 + 버튼 Dialog. 시스템 `.alert` / `.confirmationDialog`를 대신한다.
    func inkDialog(
        _ title: String,
        message: String? = nil,
        isPresented: Binding<Bool>,
        actions: @escaping () -> [InkDialogAction]
    ) -> some View {
        inkDialog(isPresented: isPresented) {
            InkDialogBody(
                title: title,
                message: message,
                actions: actions(),
                onAction: { isPresented.wrappedValue = false }
            )
        }
    }
}

/// 닫히는 애니메이션이 끝날 때까지 마지막 값을 붙잡아 둔다.
private struct InkItemSheetModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    var size: InkSheetSize
    @ViewBuilder var sheetContent: (Item) -> SheetContent

    @State private var lastItem: Item?

    func body(content: Content) -> some View {
        content
            .onChange(of: item?.id) { _, _ in
                if let item { lastItem = item }
            }
            .inkBottomSheet(
                isPresented: Binding(
                    get: { item != nil },
                    set: { if !$0 { item = nil } }
                ),
                size: size
            ) {
                if let shown = item ?? lastItem {
                    sheetContent(shown)
                }
            }
    }
}

#Preview("Bottom Sheet / Dialog") {
    struct Demo: View {
        @State private var showsSheet = false
        @State private var showsDialog = true

        var body: some View {
            VStack(spacing: 14) {
                Button("시트 열기") { showsSheet = true }
                Button("다이얼로그 열기") { showsDialog = true }
            }
            .font(InkFont.button)
            .tint(PaperTheme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paperBackground()
            .inkBottomSheet(isPresented: $showsSheet) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("그리기 설정")
                        .font(InkFont.cardTitle)
                    Text("붓과 색, 굵기를 고를 수 있어요.")
                        .font(InkFont.secondary)
                        .foregroundStyle(PaperTheme.secondaryInk)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .inkDialog(
                "거울을 삭제할까요?",
                message: "지운 거울은 되돌릴 수 없어요.",
                isPresented: $showsDialog
            ) {
                [
                    InkDialogAction("취소"),
                    InkDialogAction("삭제", role: .destructive),
                ]
            }
        }
    }
    return Demo()
}
