//
//  NotificationPreferenceSession.swift
//  ggumirror
//
//  알림 설정. **서버가 authority다.**
//
//  토글이 먹통처럼 느껴지지 않게 화면을 먼저 바꾸고, 서버가 거절하면 되돌린다.
//  전체 설정 화면을 spinner로 막지 않는다 — 알림 하나 바꾸는 일이 다른 조작을
//  멈출 이유가 없다.
//
//  **OS 권한과 다른 것이다.** 여기 값이 켜져 있어도 iOS에서 알림이 꺼져 있으면
//  실제로는 오지 않는다. 그 사실을 감추지 않고 화면이 함께 보여 준다.
//

import Foundation

@MainActor
@Observable
final class NotificationPreferenceSession {
    private(set) var preferences = NotificationPreferences.fallback
    private(set) var isLoaded = false
    /// 저장에 실패했을 때 보여 줄 말. 실패를 조용히 삼키지 않는다.
    var failure: String?

    /// 지금 담겨 있는 것이 **누구의** 설정인가. 계정이 바뀌면 비운다.
    private var ownerID: String?
    private let backend: any NotificationBackend

    init(backend: any NotificationBackend = BackendClient()) {
        self.backend = backend
    }

    func refresh(session: ServerSession?) async {
        guard let session else {
            preferences = .fallback
            ownerID = nil
            isLoaded = false
            return
        }
        if ownerID != session.userID {
            // A의 설정이 B에게 보이면 안 된다.
            preferences = .fallback
            isLoaded = false
            ownerID = session.userID
        }
        guard let loaded = try? await backend.notificationPreferences(
            accessToken: session.accessToken
        ) else { return }
        preferences = loaded
        isLoaded = true
    }

    func setSales(_ enabled: Bool, session: ServerSession?) async {
        await update(session: session, apply: { $0.salesEnabled = enabled }) {
            try await self.backend.updateNotificationPreferences(
                salesEnabled: enabled, digestFrequency: nil,
                recommendationEnabled: nil, accessToken: $0
            )
        }
    }

    func setDigest(_ frequency: DigestFrequency, session: ServerSession?) async {
        await update(session: session, apply: { $0.mirrorDigestFrequency = frequency }) {
            try await self.backend.updateNotificationPreferences(
                salesEnabled: nil, digestFrequency: frequency,
                recommendationEnabled: nil, accessToken: $0
            )
        }
    }

    func setRecommendation(_ enabled: Bool, session: ServerSession?) async {
        await update(session: session, apply: { $0.recommendationEnabled = enabled }) {
            try await self.backend.updateNotificationPreferences(
                salesEnabled: nil, digestFrequency: nil,
                recommendationEnabled: enabled, accessToken: $0
            )
        }
    }

    /// 화면을 먼저 바꾸고 서버에 보낸다. **실패하면 되돌린다.**
    private func update(
        session: ServerSession?,
        apply: (inout NotificationPreferences) -> Void,
        save: @escaping (String) async throws -> NotificationPreferences
    ) async {
        guard let session else {
            failure = "로그인이 필요해요."
            return
        }
        let previous = preferences
        var optimistic = preferences
        apply(&optimistic)
        preferences = optimistic

        do {
            preferences = try await save(session.accessToken)
            failure = nil
        } catch {
            // 서버가 받지 않았다. 켜진 것처럼 두면 오지 않는 알림을 기다리게 된다.
            preferences = previous
            failure = (error as? NotificationFailure)?.message
                ?? NotificationFailure.network.message
        }
    }
}
