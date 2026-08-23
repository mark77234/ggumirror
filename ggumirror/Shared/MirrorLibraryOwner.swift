//
//  MirrorLibraryOwner.swift
//  ggumirror
//
//  **내 거울은 계정마다 따로 산다.**
//
//  예전에는 `Application Support/ggumirror/` 한 곳을 모든 Apple 계정이 공유했다.
//  A로 로그인해 만든 거울이 로그아웃 뒤에도 그대로 보였고, B로 로그인해도 A의 거울이
//  보였다. 한 기기를 나눠 쓰는 것이 아니라 **남의 콘텐츠가 보이는 것**이라 고쳤다.
//
//  로그아웃은 **삭제가 아니다.** 보고 있는 서랍을 바꿀 뿐이고 A의 파일은 그대로 남는다.
//  계정 삭제와 혼동하지 않는다.
//
//  경로에 raw Apple 식별자나 이메일을 쓰지 않는다 — backend가 준 내부 user UUID다.
//

import CryptoKit
import Foundation

/// 지금 보고 있는 서랍이 누구 것인가.
nonisolated enum MirrorLibraryOwner: Equatable, Sendable {
    /// 로그인하지 않았다. **비어 있는 것이 정상이다** — 남의 거울을 보여 주지 않는다.
    case guest
    /// backend 내부 user UUID. Apple subject가 아니다.
    case user(String)

    init(userID: String?) {
        if let userID, !userID.isEmpty { self = .user(userID) } else { self = .guest }
    }

    /// 저장 폴더 이름. 파일 이름으로 안전한 값만 쓴다 —
    /// 서버 UUID가 그대로 오지만 믿지 않고 한 번 더 거른다.
    var directoryName: String {
        switch self {
        case .guest: "guest"
        case .user(let id): Self.safeName(id)
        }
    }

    var isGuest: Bool { self == .guest }

    /// UUID 이외의 문자가 섞여 있으면 경로로 쓰지 않는다.
    /// 값을 잃지 않도록 hash로 바꾼다 — 같은 사용자는 언제나 같은 폴더다.
    static func safeName(_ id: String) -> String {
        // 서버 user id는 UUID다. 그 모양이면 그대로 쓰고, 아니면 **직접 만들지 않고**
        // system hash로 바꾼다 — 같은 사용자는 언제나 같은 폴더다.
        let looksLikeUUID = !id.isEmpty && id.count <= 64
            && id.allSatisfy { $0.isHexDigit || $0 == "-" }
        guard !looksLikeUUID else { return id }
        let digest = SHA256.hash(data: Data(id.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
