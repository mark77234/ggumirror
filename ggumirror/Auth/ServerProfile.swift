//
//  ServerProfile.swift
//  ggumirror
//
//  **사용자 이름은 이제 계정 정보다.** 이 기기의 값이 아니라 서버가 authority다.
//
//  예전에는 `UserDefaults`에만 있었고 모두에게 `거울지기`가 보였다 — 계정을 바꿔도
//  같은 이름이 남았고, 상점에 올린 상품의 판매자가 누구인지 보여 줄 방법도 없었다.
//
//  이름이 **없는 것이 정상**이다. 1.0.7 사용자에게는 이 값이 없고, Apple이 이름을
//  주지 않는 경우도 있다. 그때 기본 이름을 지어내지 않고 화면이 "이름을 정해주세요"를
//  보여 준다 — 그 문구 자체를 이름으로 저장하지 않는다.
//

import Foundation
import Observation

/// 서버가 준 프로필. **여기서 이름을 만들어내지 않는다.**
nonisolated struct ServerProfile: Decodable, Equatable, Sendable {
    let id: String
    /// 아직 정하지 않았으면 `nil`.
    let displayName: String?
    /// 지금 바꿀 수 있는가. **서버가 판단한다** — 기기 시계를 믿지 않는다.
    let canChangeDisplayName: Bool
    /// 다음에 바꿀 수 있는 시각. 바꾼 적이 없으면 `nil`.
    let nextDisplayNameChangeAt: Date?

    var hasName: Bool { displayName?.isEmpty == false }
}

/// 이름 규칙. **서버와 같은 것을 본다** — 화면에서 먼저 걸러 주되,
/// 최종 판단은 언제나 서버다(기기에서 통과했다고 저장되는 것이 아니다).
enum DisplayNamePolicy {
    static let maxLength = 20

    /// 앞뒤 공백을 다듬고 한 줄로. 비었거나 너무 길면 `nil`.
    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        // 보이지 않는 것만 막는다. 특수문자를 넓게 막으면 정당한 이름이 걸린다.
        guard !trimmed.contains(where: \.isNewline) else { return nil }
        return trimmed
    }

    /// 이름이 없을 때 화면에 보여 줄 말. **저장되는 값이 아니다.**
    static let placeholder = "이름을 정해주세요"

    static func nextChangeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

/// 로그인한 사용자의 프로필 상태. `ShardWallet`과 같은 규칙 —
/// **서버 값을 옮겨 적기만 한다.** 이름을 여기서 지어내거나 고치지 않는다.
@MainActor
@Observable
final class ProfileSession {
    private(set) var profile: ServerProfile?
    private(set) var isSaving = false

    private let backend: any ProfileBackend

    init(backend: any ProfileBackend = BackendClient()) {
        self.backend = backend
    }

    /// 화면에 보여 줄 이름. 없으면 `nil`이고, 그때 화면이 안내 문구를 쓴다.
    var displayName: String? { profile?.displayName }

    func refresh(session: ServerSession?) async {
        guard let token = session?.accessToken else {
            // **로그아웃은 지우는 것이다.** A의 이름이 B에게 보이면 안 된다.
            profile = nil
            return
        }
        profile = try? await backend.profile(accessToken: token)
    }

    func clear() { profile = nil }

    /// 이름을 바꾼다. 성공하면 서버가 준 프로필로 갈아 끼운다.
    /// 실패하면 **아무것도 바꾸지 않는다** — 저장되지 않은 이름을 보여 주지 않는다.
    func setDisplayName(_ raw: String, session: ServerSession?) async -> String? {
        guard let token = session?.accessToken else { return "로그인이 필요해요." }
        guard let name = DisplayNamePolicy.normalized(raw) else {
            return "이름은 1~\(DisplayNamePolicy.maxLength)자로 적어 주세요."
        }
        isSaving = true
        defer { isSaving = false }
        do {
            profile = try await backend.setDisplayName(name, accessToken: token)
            return nil
        } catch let error as DisplayNameFailure {
            // **generic 오류로 숨기지 않는다.** 겹친 이름은 다시 시도해도 같은 답이다.
            return error.message
        } catch let error as BackendError {
            return error.message
        } catch {
            return BackendError.unavailable.message
        }
    }
}
