//
//  ShardStoreSheet.swift
//  ggumirror
//
//  조각 충전 화면. **결제 로직이 여기 없다** — `ShardPurchaseController`가 이미 갖고 있고
//  이 화면은 그것을 부르고 상태를 그릴 뿐이다. StoreKit 타입도 모른다.
//
//  가격은 **`Product.displayPrice`를 그대로** 보여준다. 통화 · 지역 · 세금은 Apple이 정한다 —
//  `₩1,100`을 코드에 적으면 다른 나라에서 거짓말이 된다.
//

import SwiftUI

struct ShardStoreSheet: View {
    let controller: ShardPurchaseController
    let wallet: ShardWallet
    let session: ServerSession?
    /// 로그인이 필요할 때. 기존 Apple 로그인으로 보낸다 — 새 auth flow를 만들지 않는다.
    let onNeedsSignIn: () -> Void

    @Environment(\.inkModalDismiss) private var dismiss
    /// 로그인이 필요할 때만 뜨는 안내. controller의 notice와 섞지 않는다.
    @State private var signedOutNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .inkSheetActions { footer }
        // **상품 조회는 상점을 열 때 시작한다** — 앱 시작에 묶지 않는다.
        .task { await controller.loadProductsIfNeeded(reason: "store_open") }
    }

    // MARK: - 머리말

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("조각 충전")
                .font(InkFont.cardTitle)
                .foregroundStyle(PaperTheme.ink)

            HStack(spacing: 6) {
                Text("지금")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                // 잔액의 authority는 서버다. 화면은 `ShardWallet`이 들고 있는 값을 그릴 뿐이다.
                ShardAmount(amount: wallet.balance, iconSize: 16, treatsZeroAsFree: false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("지금 보유 \(wallet.balance) 조각")
        }
    }

    // MARK: - 상품

    @ViewBuilder
    private var content: some View {
        if controller.products.isEmpty {
            if controller.phase == .loadingProducts {
                HStack(spacing: 8) {
                    ProgressView().tint(PaperTheme.ink)
                    message("상품을 불러오고 있어요")
                }
            } else {
                // StoreKit이 준 오류 문자열을 그대로 보여주지 않는다.
                VStack(alignment: .leading, spacing: 10) {
                    message("상품 정보를 불러오지 못했어요")
                    Button {
                        Task { await controller.reloadProducts() }
                    } label: {
                        Text("다시 시도")
                            .font(InkFont.body.weight(.semibold))
                            .foregroundStyle(PaperTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background {
                                UnevenRoundedRectangle.ink(16, 13, 17, 12)
                                    .stroke(PaperTheme.ink, lineWidth: 1.6)
                            }
                            .contentShape(.rect)
                    }
                        .buttonStyle(InkPressStyle())
                }
            }
        } else {
            VStack(spacing: 10) {
                // 순서는 controller가 조각 수로 정렬해 준다 — 10 / 50 / 100.
                ForEach(controller.products) { product in
                    card(product)
                }
                // 일부만 받은 상태. **받은 것은 그대로 살 수 있고**, 나머지는 기다리거나
                // 다시 시도한다. 내부 product id나 "Apple 오류"를 사용자에게 보여주지 않는다.
                if controller.hasMissingProducts {
                    partialNotice
                }
            }
        }
    }

    /// 일부 상품만 들어온 상태의 안내. 조회 중이면 진행 표시, 아니면 다시 시도.
    @ViewBuilder
    private var partialNotice: some View {
        HStack(spacing: 8) {
            if controller.phase == .loadingProducts {
                ProgressView().tint(PaperTheme.ink)
                Text("다른 상품을 불러오고 있어요")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
            } else {
                Text("일부 상품 정보를 불러오지 못했어요")
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                Spacer(minLength: 4)
                Button("다시 시도") { Task { await controller.reloadProducts() } }
                    .font(InkFont.caption.weight(.semibold))
                    .foregroundStyle(PaperTheme.ink)
                    .buttonStyle(InkPressStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private func card(_ product: ShardProductInfo) -> some View {
        let isThisOne = controller.phase == .purchasing(productID: product.id)
        return Button {
            buy(product)
        } label: {
            HStack(spacing: 12) {
                ShardIcon(size: 26)

                Text(product.shardAmount.map { "\($0) 조각" } ?? product.displayName)
                    .font(InkFont.body.weight(.semibold))
                    .foregroundStyle(PaperTheme.ink)

                Spacer(minLength: 8)

                if isThisOne {
                    ProgressView().tint(PaperTheme.ink)
                } else {
                    // **StoreKit이 만든 문자열 그대로.**
                    Text(product.displayPrice)
                        .font(InkFont.body)
                        .monospacedDigit()
                        .foregroundStyle(PaperTheme.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .frame(maxWidth: .infinity)
            .background {
                let shape = UnevenRoundedRectangle.ink(17, 14, 18, 13)
                shape.fill(PaperTheme.subtleSurface)
                    .overlay(shape.stroke(PaperTheme.ink, lineWidth: 1.6))
            }
        }
        .buttonStyle(InkPressStyle())
        // 구매 중에는 모든 카드를 잠근다 — 연타로 두 번 사지 않는다.
        .disabled(controller.isBusy)
        .opacity(controller.isBusy && !isThisOne ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(for: product))
        .accessibilityAddTraits(.isButton)
    }

    private func label(for product: ShardProductInfo) -> String {
        let amount = product.shardAmount.map { "조각 \($0)개" } ?? product.displayName
        return "\(amount), 가격 \(product.displayPrice)"
    }

    // MARK: - 꼬리말

    private var footer: some View {
        VStack(spacing: 10) {
            if let notice = signedOutNotice ?? controller.notice {
                Text(notice)
                    .font(InkFont.caption)
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }

            Button {
                dismiss()
            } label: {
                Text("닫기")
                    .font(InkFont.body)
                    .foregroundStyle(PaperTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background {
                        UnevenRoundedRectangle.ink(16, 13, 17, 12)
                            .stroke(PaperTheme.ink, lineWidth: 1.6)
                    }
                    .contentShape(.rect)
            }
                .buttonStyle(InkPressStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - 동작

    private func buy(_ product: ShardProductInfo) {
        // 조각은 서버 경제라 로그인이 필요하다. **새 auth flow를 만들지 않고**
        // 기존 gate에 "이걸 하려던 참이었다"만 기록한다.
        //
        // 로그인 뒤 결제를 **자동으로 이어가지 않는다.** 비동기 로그인 뒤에 결제창을
        // 몰래 다시 띄우는 것보다, 사용자가 상품을 다시 고르는 편이 안전하다.
        // pending purchase를 따로 저장하지도 않는다.
        guard session != nil else {
            onNeedsSignIn()
            signedOutNotice = "조각을 충전하려면 로그인이 필요해요. 설정에서 Apple로 로그인해 주세요."
            return
        }
        signedOutNotice = nil
        Task { await controller.purchase(product.id, session: session, wallet: wallet) }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(InkFont.body)
            .foregroundStyle(PaperTheme.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
