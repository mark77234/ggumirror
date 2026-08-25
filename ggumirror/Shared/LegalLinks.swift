//
//  LegalLinks.swift
//  ggumirror
//
//  개인정보처리방침 · 이용약관 주소. **한 곳에서만 정한다.**
//
//  화면마다 URL 문자열을 적으면 주소가 바뀔 때 한 곳을 빠뜨린다.
//
//  아직 실제 주소가 없다. **가짜 URL을 넣지 않는다** — `example.com`이나
//  지어낸 Notion 주소를 넣으면 사용자가 깨진 페이지를 보게 되고, 무엇보다
//  "이미 연결돼 있다"고 착각해 출시 전에 채우는 것을 잊는다.
//  없으면 `nil`이고, 화면은 준비 중이라고 말한다.
//

import Foundation

nonisolated enum LegalLinks {
    /// 개인정보처리방침. operator가 Notion에 올린 뒤 이 값 하나만 채운다.
    static let privacyPolicy: URL? = nil

    /// 이용약관. 위와 같다.
    static let termsOfService: URL? = nil

    /// 아직 채우지 않은 링크에 보여 줄 말.
    static let notReadyMessage = "링크를 준비하고 있어요. 조금만 기다려 주세요."

    /// 1.1.0을 내보내기 전에 둘 다 채워야 한다.
    /// release checklist test가 이 값을 본다 — 개발 중에는 빌드를 막지 않는다.
    static var isReadyForRelease: Bool {
        privacyPolicy != nil && termsOfService != nil
    }
}
