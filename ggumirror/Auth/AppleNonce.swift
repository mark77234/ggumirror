//
//  AppleNonce.swift
//  ggumirror
//
//  Apple 로그인 한 번에 쓰는 nonce.
//
//  Apple 공식 방식대로 **원본은 우리만 알고, Apple 요청에는 SHA-256만 넣는다.**
//  Apple이 돌려주는 identityToken의 `nonce` claim에는 그 해시가 들어 있고,
//  서버는 우리가 보낸 원본을 다시 해싱해서 claim과 비교한다.
//  그래서 token만 훔쳐도 우리 서버에 쓸 수 없다.
//
//  이 값은 **한 번의 로그인 시도에만** 존재한다. Keychain에도, 디스크에도, 로그에도 남기지 않는다.
//

import CryptoKit
import Foundation

/// nonisolated — 기본 인자와 background에서도 만들 수 있어야 한다.
nonisolated struct AppleNonce: Equatable {
    /// 서버에 보내는 원본. Apple에는 주지 않는다.
    let raw: String

    init() {
        // 32 byte를 base64url로. UUID보다 넉넉하고 URL/JSON에 안전하다.
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // 시스템 RNG가 실패하는 상황이다. 예측 가능한 값으로 떨어지지 않는다.
            bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        }
        raw = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 테스트에서만 쓰는 고정 생성자.
    init(raw: String) { self.raw = raw }

    /// `ASAuthorizationAppleIDRequest.nonce`에 넣는 값. 소문자 16진수.
    var hashedForApple: String {
        SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// 진행 중인 로그인 시도의 nonce를 들고 있는 곳.
///
/// **한 번 꺼내면 사라진다.** 그래서 한 nonce가 두 credential에 쓰이는 일이 없다.
/// 버튼을 연달아 눌러 시도가 겹치면 마지막 nonce만 남고, 뒤늦게 도착한 예전 credential은
/// 서버 검증에서 떨어진다 — 잘못 통과하는 쪽이 아니라 실패하는 쪽으로 기운다.
@MainActor
final class AppleNonceBox {
    private var current: AppleNonce?

    /// 새 시도를 시작한다. Apple 요청에 넣을 해시를 돌려준다.
    func begin(_ nonce: AppleNonce = AppleNonce()) -> String {
        current = nonce
        return nonce.hashedForApple
    }

    /// 꺼내면서 버린다.
    func take() -> AppleNonce? {
        defer { current = nil }
        return current
    }

    /// 취소 / 실패 후 폐기.
    func discard() { current = nil }

    var hasPending: Bool { current != nil }
}
