//
//  MirrorRenamePolicy.swift
//  ggumirror
//
//  **판매 중인 거울은 이름을 바꿀 수 없다.**
//
//  이름은 이 기기의 표시용 값이고 Marketplace listing title은 서버가 가진 별개의
//  authority다. 둘이 섞이면 "내 거울 이름을 바꿨더니 상점 상품 이름이 바뀌었다"가
//  되므로, 판매 중인 **원본**만 잠근다.
//
//  잠글 대상은 **stable source identity**로 고른다 — 서버가 준 `sourceContentId`가
//  이 거울의 id와 같은가. 제목이나 미리보기가 닮았다고 잠그지 않는다.
//  같은 상품에서 따로 받아 온 복사본은 내 것이므로 그대로 바꿀 수 있다.
//

import Foundation

/// 지금 이 거울의 이름을 바꿀 수 있는가.
enum MirrorRenameAvailability: Equatable {
    case allowed
    /// 지금 상점에서 팔리고 있는 원본이다.
    case lockedPublished
    /// 상점에 올린 적이 있는 것 같은데 **판매 상태를 확인하지 못했다.**
    ///
    /// 이때 그냥 허용하면 판매 중인 거울의 이름이 바뀔 수 있다. 그렇다고 모든
    /// 거울을 잠그면 오프라인에서 평범한 내 거울조차 못 바꾼다 — 그래서
    /// **올린 적 있다는 지역 흔적이 있을 때만** 이 상태가 된다.
    case unknownSellerStatus

    var isAllowed: Bool { self == .allowed }

    /// 막힌 이유. 허용이면 할 말이 없다.
    ///
    /// **판단은 거울과 스티커가 같다** — 다른 것은 문구의 명사 하나뿐이라
    /// 정책을 두 벌로 나누지 않았다.
    func message(for kind: RenameableAssetKind) -> String? {
        switch self {
        case .allowed: nil
        case .lockedPublished: "판매 중인 \(kind.subject) 이름을 바꿀 수 없어요."
        case .unknownSellerStatus: "판매 상태를 확인한 뒤 다시 시도해 주세요."
        }
    }

    /// 거울 기준 문구. 기존 호출부가 그대로 쓴다.
    var message: String? { message(for: .mirror) }
}

/// 이름을 바꿀 수 있는 것. **정책이 아니라 문구와 조회 종류만** 가른다.
nonisolated enum RenameableAssetKind: String, Equatable {
    case mirror
    case sticker

    var noun: String {
        switch self {
        case .mirror: "거울"
        case .sticker: "스티커"
        }
    }

    /// 조사까지 붙인 주어. **받침에 따라 은/는이 다르다** —
    /// 명사만 끼워 넣으면 "스티커은"처럼 어색한 말이 된다.
    var subject: String {
        switch self {
        case .mirror: "거울은"
        case .sticker: "스티커는"
        }
    }

    /// Marketplace 판매 목록을 볼 때 쓰는 값. 서버 계약 그대로다.
    var contentType: String { rawValue }
}

enum MirrorRenamePolicy {
    /// - Parameters:
    ///   - isSignedIn: 로그아웃 상태면 이 서랍에는 판매자 상품이 있을 수 없다.
    ///   - hasSellerLinkHint: 이 기기에 등록 준비/등록 기록이 남아 있는가(힌트일 뿐이다).
    ///   - sellerListingsAreKnown: 서버 판매 목록을 실제로 받아 왔는가.
    ///     받아 오지 못한 것과 "하나도 없다"를 같은 것으로 보면 안 된다.
    ///   - isPublishedOriginal: 판매 중 목록에 이 거울의 id가 있는가.
    static func availability(
        isSignedIn: Bool,
        hasSellerLinkHint: Bool,
        sellerListingsAreKnown: Bool,
        isPublishedOriginal: Bool
    ) -> MirrorRenameAvailability {
        // 확실히 팔리고 있다 — 다른 조건을 볼 것도 없다.
        if isPublishedOriginal { return .lockedPublished }
        // 서버 목록을 받아 왔고 거기 없다 → draft · 판매 중지 · 삭제 · 등록한 적 없음.
        // 어느 쪽도 공개 상점에 걸려 있지 않으므로 바꿔도 된다.
        if sellerListingsAreKnown { return .allowed }
        // 로그아웃 서랍에는 판매자 상품이 없다. 오프라인이어도 바꿀 수 있다.
        if !isSignedIn { return .allowed }
        // 올린 적 있다는 흔적이 있는데 지금 상태를 모른다 — 잠시 막는다.
        return hasSellerLinkHint ? .unknownSellerStatus : .allowed
    }
}

/// 이름 바꾸기 결과. **서버를 부르지 않는다** — 이 기기의 표시용 값 하나다.
enum MirrorRenameOutcome: Equatable {
    case renamed(String)
    /// 비었거나 공백뿐이다.
    case invalidName
    /// 그 거울이 없다.
    case notFound
    /// 이 서랍에 **사실상 같은 이름**이 이미 있다(`ContentNameKey`).
    case duplicateName

    /// 사용자에게 보여 줄 말. 성공이면 할 말이 없다.
    func message(for kind: RenameableAssetKind) -> String? {
        switch self {
        case .renamed: nil
        case .invalidName: "이름을 입력해 주세요."
        case .notFound: "\(kind.subject) 찾지 못했어요."
        case .duplicateName: "이미 있는 이름이에요. 다른 이름을 지어 주세요."
        }
    }
}

/// **같은 이름인지 판단하는 규칙 하나.**
///
/// 사람이 보기에 같은 이름은 같은 이름이어야 한다. `Pink` · ` pink ` · `PINK`가
/// 서랍에 나란히 있으면 어느 것이 어느 것인지 알 수 없다.
///
/// 이것은 **비교용 열쇠일 뿐이다** — 표시용 이름은 사용자가 적은 그대로 저장한다.
/// 한글은 자모 조합이 두 가지로 표현될 수 있어(`NFC`/`NFD`) 눈에 같아 보여도
/// 문자열이 다르다. 그래서 먼저 하나의 형태로 모은다.
///
/// **이름은 identity가 아니다.** 이 열쇠로 콘텐츠를 찾지 않는다 — id가 그 일을 한다.
nonisolated enum ContentNameKey {
    /// 비교에 쓰는 canonical form.
    static func canonical(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // 한글 자모 조합을 한 가지로 모은다(NFC).
            .precomposedStringWithCanonicalMapping
            // Latin 대소문자 차이를 없앤다. 한글에는 영향이 없다.
            .lowercased()
    }

    /// 사람이 보기에 같은 이름인가.
    static func matches(_ one: String, _ other: String) -> Bool {
        canonical(one) == canonical(other)
    }
}
