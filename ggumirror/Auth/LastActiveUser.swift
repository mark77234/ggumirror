//
//  LastActiveUser.swift
//  ggumirror
//
//  **다음 실행에서 어느 서랍을 먼저 열지** 기억한다.
//
//  거울 목록은 이미 계정마다 따로 산다(`MirrorLibraryOwner`). 그런데 어느 계정인지는
//  서버 세션이 확정된 뒤에야 알 수 있었고, 그 확정은 network 왕복 하나를 기다렸다.
//  그동안 화면은 guest 서랍(= 비어 있음)을 보고 있었으므로, 앱을 켜고 바로 거울로
//  들어가면 **마지막에 쓰던 거울이 사라진 것처럼** 보였다. 잠시 뒤 세션이 돌아오면
//  거울이 다시 생겼다 — 사용자에게는 앱이 자기 것을 잃어버렸다 되찾는 것으로 보인다.
//
//  그래서 여기 **내부 user UUID 하나만** 적어 둔다. 그것으로 서랍을 곧바로 열 수 있고,
//  거울 화면은 network를 기다리지 않는다.
//
//  이 값은 **credential이 아니다.** 세션 token은 여전히 Keychain에만 있고, 이 값으로는
//  아무 서버 요청도 인증되지 않는다. 같은 UUID가 이미 디스크의 서랍 폴더 이름이라
//  새로 드러나는 것도 없다.
//
//  **소유권 · 결제 · 잔액의 근거가 아니다.** 어느 캐시를 먼저 보여 줄지만 정한다.
//

import Foundation

/// 마지막으로 서버 세션이 확인된 사용자.
///
/// 명시적 로그아웃과 세션 만료에서 지운다 — 지우고 나면 다음 실행은 guest로 시작한다.
struct LastActiveUser {
    /// 앱이 쓰는 하나. 테스트는 자기 suite로 만든다.
    static let shared = LastActiveUser(defaults: .standard)

    private static let key = "ggumirror.lastActiveUserID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// 다음 cold launch가 먼저 열어야 할 서랍.
    var owner: MirrorLibraryOwner {
        MirrorLibraryOwner(userID: defaults.string(forKey: Self.key))
    }

    /// 서버 세션이 확인됐다. `nil`이면 지운다.
    func remember(_ userID: String?) {
        guard let userID, !userID.isEmpty else { forget(); return }
        defaults.set(userID, forKey: Self.key)
    }

    /// **다음 실행에서 이 계정 서랍을 먼저 열지 않는다.**
    ///
    /// 파일은 지우지 않는다 — 다시 로그인하면 그대로 돌아온다.
    /// 계정 삭제는 별개이고, 그때는 서랍 자체가 사라진다(`removeAccountNamespace`).
    func forget() {
        defaults.removeObject(forKey: Self.key)
    }
}
