//
//  MirrorAcquireCTA.swift
//  ggumirror
//
//  거울을 받는 버튼이 **어떤 상태인가.** 내장 템플릿과 사용자 상품이 같은 모델을 쓴다.
//
//  사용자는 이 거울이 내장인지 남이 올린 것인지 몰라도 같은 흐름을 겪어야 한다.
//  예전에는 두 화면이 다른 문구를 썼다 — 한쪽은 `조각으로 받기`, 다른 쪽은
//  `조각으로 구매`·`내 것으로 받기`였다. 같은 일에 다른 말을 쓰면 다른 일처럼 보인다.
//
//  **거울을 얻는 동작의 기본 용어는 `받기`다.**
//

import Foundation

nonisolated enum MirrorAcquireCTA: Equatable, Sendable {
    /// 로그인 전. 눌리면 로그인 안내로 간다 — 서버에 먼저 요청하지 않는다.
    case needsSignIn(title: String)
    /// 아직 없다. 무료.
    case acquireFree
    /// 아직 없다. 유료.
    case purchase(price: Int)
    /// 서버에는 내 것이지만 이 기기에 없다. **다시 사지 않는다.**
    case addToLibrary
    /// 이미 이 기기에 있다.
    case alreadyInLibrary
    /// 내가 올린 상품. 자기 것을 살 수 없다.
    case ownListing

    /// - Parameters:
    ///   - price: 0이면 무료.
    ///   - isSignedIn: 로그인 여부. **모르는 상태로 서버를 먼저 부르지 않는다.**
    ///   - isMine: 내가 올린 상품인가(내장 템플릿은 언제나 `false`).
    ///   - ownsOnServer: 서버 소유권. 내장 템플릿은 값이 없으므로 `false`.
    ///   - existsLocally: 이 기기의 내 거울에 이미 있는가.
    static func state(
        price: Int,
        isSignedIn: Bool,
        isMine: Bool = false,
        ownsOnServer: Bool = false,
        existsLocally: Bool
    ) -> MirrorAcquireCTA {
        // 이미 손에 있으면 그 사실이 가장 먼저다 — 값을 다시 보여 주지 않는다.
        if existsLocally { return .alreadyInLibrary }
        if isMine { return .ownListing }
        if ownsOnServer { return .addToLibrary }
        guard isSignedIn else {
            return .needsSignIn(title: price == 0 ? "무료로 받기" : "\(price)조각으로 받기")
        }
        return price == 0 ? .acquireFree : .purchase(price: price)
    }

    var title: String {
        switch self {
        case .needsSignIn(let title): title
        case .acquireFree: "무료로 받기"
        case .purchase(let price): "\(price)조각으로 받기"
        case .addToLibrary: "내 거울에 추가"
        case .alreadyInLibrary: "이미 내 거울에 있어요"
        case .ownListing: "내가 올린 상품이에요"
        }
    }

    /// 누를 수 있는가. 이미 있거나 내 상품이면 **실패할 버튼을 보여 주지 않는다.**
    var isEnabled: Bool {
        switch self {
        case .alreadyInLibrary, .ownListing: false
        default: true
        }
    }

    /// 값을 치르는 동작인가. 확인이 필요한지 판단하는 쪽이 쓴다.
    var costsShards: Bool {
        if case .purchase = self { return true }
        return false
    }
}
