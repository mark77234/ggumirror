//
//  LegalLinks.swift
//  ggumirror
//
//  개인정보처리방침 · 이용약관 주소. **한 곳에서만 정한다.**
//
//  화면마다 URL 문자열을 적으면 주소가 바뀔 때 한 곳을 빠뜨린다.
//
//  주소는 운영자가 공개한 실제 문서다. **지어낸 주소를 넣지 않는다** —
//  깨진 페이지를 보여 주는 것보다, "이미 연결돼 있다"고 착각해 출시 전에
//  채우는 것을 잊는 쪽이 더 나쁘다.
//
//  아직 없을 때는 `nil`로 두고 화면이 준비 중이라고 말한다. 그 경로는
//  주소가 생긴 지금도 그대로 남는다 — 나중에 주소를 내리거나 바꾸는 동안
//  앱이 빈 페이지를 여는 대신 사람 말로 답한다.
//

import Foundation

nonisolated enum LegalLinks {
    /// 개인정보처리방침. 운영자가 공개한 문서다.
    static let privacyPolicy = URL(
        string: "https://battle-princess-097.notion.site/3be5d51fd95181e7a39de5ab9d430c23"
    )

    /// 이용약관. 위와 같다.
    static let termsOfService = URL(
        string: "https://battle-princess-097.notion.site/3c85d51fd95181c49126fa23e57ef7ce"
    )

    /// 아직 채우지 않은 링크에 보여 줄 말.
    static let notReadyMessage = "링크를 준비하고 있어요. 조금만 기다려 주세요."

    /// 1.1.0을 내보내기 전에 둘 다 채워야 한다. 이제 둘 다 있다.
    /// release checklist test가 이 값을 본다 — 개발 중에는 빌드를 막지 않는다.
    static var isReadyForRelease: Bool {
        privacyPolicy != nil && termsOfService != nil
    }
}
