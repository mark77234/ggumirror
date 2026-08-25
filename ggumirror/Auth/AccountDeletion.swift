//
//  AccountDeletion.swift
//  ggumirror
//
//  계정 삭제. **되돌릴 수 없다.**
//
//  서버가 계정을 지운 **뒤에만** 이 기기의 자료를 지운다. 순서를 바꾸면 서버 삭제가
//  실패했을 때 사용자는 계정도 살아 있고 거울도 잃은 상태가 된다.
//
//  지우는 것은 **그 계정의 서랍 하나뿐**이다 — guest 서랍과 다른 계정 서랍은
//  건드리지 않는다.
//

import Foundation

nonisolated protocol AccountDeletionBackend: Sendable {
    func deleteAccount(accessToken: String) async throws
}

extension BackendClient: AccountDeletionBackend {
    func deleteAccount(accessToken: String) async throws {
        _ = try await request("users/me/account", method: "DELETE", accessToken: accessToken)
    }
}

nonisolated enum AccountDeletionOutcome: Equatable {
    case deleted
    case notSignedIn
    case failed(String)
}

@MainActor
enum AccountDeletion {
    /// - Returns: 결과. **서버가 성공한 뒤에만** 로컬을 지운다.
    static func run(
        session: AuthSession,
        library: MirrorLibrary,
        stickers: StickerLibrary,
        profile: ProfileSession?,
        marketplace: MarketplaceStore?,
        backend: any AccountDeletionBackend = BackendClient()
    ) async -> AccountDeletionOutcome {
        guard let server = session.server else { return .notSignedIn }
        let owner = MirrorLibraryOwner.user(server.userID)

        do {
            try await backend.deleteAccount(accessToken: server.accessToken)
        } catch let error as BackendError {
            // 서버가 지우지 못했다. **로컬은 하나도 건드리지 않는다.**
            return .failed(error.message)
        } catch {
            return .failed(BackendError.unavailable.message)
        }

        // 여기부터는 계정이 실제로 사라진 뒤다.
        // 쓰기가 비동기라 서랍을 바꾸기 전에 기다린다(계정 전환과 같은 규칙).
        library.activate(owner: .guest)
        stickers.activate(owner: .guest)
        MirrorStore.removeAccountNamespace(for: owner)

        profile?.clear()
        // 세션이 없으면 이 함수들이 캐시를 비운다(로그아웃과 같은 경로다).
        await marketplace?.refreshMine(session: nil)
        await marketplace?.refreshMyListings(session: nil)
        await session.signOut()
        return .deleted
    }
}
