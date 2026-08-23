//
//  MirrorCapacityPurchaseTests.swift
//  ggumirrorTests
//
//  거울 보관 공간 확장. **client는 authority가 아니다.**
//
//  가장 위험한 두 가지:
//  1. client가 `balance -= 10` · `slots += 5`를 직접 계산하는 것
//  2. 응답을 잃었을 때 **새 operationId로** 다시 보내 조각이 두 번 빠지는 것
//

import Testing
import Foundation
@testable import ggumirror

private func capacitySource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    let text = try String(contentsOf: root.appending(path: path), encoding: .utf8)
    return text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            guard let comment = line.range(of: "//") else { return String(line) }
            return String(line[..<comment.lowerBound])
        }
        .joined(separator: "\n")
}

private let pack = MirrorSlotPack(id: "mirror_slots_5", costShards: 10, slotDelta: 5)

private func info(purchased: Int) -> MirrorCapacityInfo {
    MirrorCapacityInfo(
        baseSlots: 5, purchasedSlots: purchased, effectiveSlots: 5 + purchased, pack: pack
    )
}

private func purchase(
    _ operationID: String, purchased: Int, balance: Int, applied: Bool = true
) -> MirrorCapacityPurchase {
    MirrorCapacityPurchase(
        operationId: operationID, packId: pack.id, chargedShards: 10, slotDelta: 5,
        applied: applied, balance: balance,
        baseSlots: 5, purchasedSlots: purchased, effectiveSlots: 5 + purchased
    )
}

/// 서버를 흉내 낸다. **operationId별로 한 번만** 경제를 움직인다.
private final class FakeCapacityBackend: MirrorCapacityBackend, @unchecked Sendable {
    var balance = 20
    var purchasedSlots = 0
    var failure: Error?
    /// 응답을 잃는 상황: 서버는 처리하지만 client에게 오류를 던진다.
    var losesResponse = false
    var slowPurchase = false

    private(set) var capacityCalls = 0
    private(set) var purchaseCalls: [String] = []
    private var handled: [String: MirrorCapacityPurchase] = [:]

    func mirrorCapacity(accessToken: String) async throws -> MirrorCapacityInfo {
        capacityCalls += 1
        if let failure { throw failure }
        return info(purchased: purchasedSlots)
    }

    func purchaseMirrorSlots(
        packId: String, operationId: String, accessToken: String
    ) async throws -> MirrorCapacityPurchase {
        purchaseCalls.append(operationId)
        if slowPurchase { try? await Task.sleep(for: .milliseconds(120)) }

        if let already = handled[operationId] {
            // 같은 의도가 이미 처리됐다. **경제를 다시 움직이지 않는다.**
            return purchase(
                operationId, purchased: already.purchasedSlots,
                balance: balance, applied: false
            )
        }
        if let failure { throw failure }
        guard balance >= pack.costShards else { throw BackendError.unexpected(status: 409) }

        balance -= pack.costShards
        purchasedSlots += pack.slotDelta
        let result = purchase(operationId, purchased: purchasedSlots, balance: balance)
        handled[operationId] = result
        if losesResponse { throw BackendError.unexpected(status: 500) }
        return result
    }
}

@MainActor
private func harness(
    balance: Int = 20
) -> (MirrorCapacityStore, FakeCapacityBackend, MirrorLibrary, ShardWallet) {
    let backend = FakeCapacityBackend()
    backend.balance = balance
    return (
        MirrorCapacityStore(backend: backend), backend,
        MirrorLibrary(), ShardWallet()
    )
}

private let session = ServerSession(
    accessToken: "t-1", expiresAt: .distantFuture, userID: "u-1"
)

// MARK: - 읽기

@MainActor
@Suite("보관 칸은 서버가 정한다")
struct CapacityAuthorityTests {

    @Test("서버에 닿기 전에는 무료 기본값이다")
    func defaultsToFreeSlots() {
        let (store, _, library, _) = harness()
        #expect(store.effectiveSlots == MirrorStoragePolicy.freeMirrorSlots)
        #expect(library.mirrorCapacity == 5)
        // 가격을 지어내지 않는다.
        #expect(store.pack == nil)
    }

    @Test("로그인 전에는 서버를 부르지 않는다")
    func signedOutDoesNotCallTheServer() async {
        let (store, backend, library, _) = harness()
        let refreshed = await store.refresh(session: nil, library: library)
        #expect(refreshed == false)
        #expect(backend.capacityCalls == 0)
    }

    @Test("서버 값을 그대로 옮겨 적는다")
    func serverValueBecomesCapacity() async {
        let (store, backend, library, _) = harness()
        backend.purchasedSlots = 5

        await store.refresh(session: session, library: library)

        #expect(store.effectiveSlots == 10)
        #expect(library.mirrorCapacity == 10)
        #expect(store.pack?.costShards == 10)
        #expect(store.pack?.slotDelta == 5)
    }

    @Test("못 읽어도 마지막으로 본 값을 잃지 않는다")
    func failureKeepsTheLastKnownValue() async {
        let (store, backend, library, _) = harness()
        backend.purchasedSlots = 10
        await store.refresh(session: session, library: library)
        #expect(library.mirrorCapacity == 15)

        backend.failure = BackendError.unexpected(status: 503)
        let refreshed = await store.refresh(session: session, library: library)

        #expect(refreshed == false)
        // **줄어들지 않는다.** 산 칸을 잃어버리는 write를 하지 않는다.
        #expect(library.mirrorCapacity == 15)
        #expect(store.effectiveSlots == 15)
    }

    @Test("잘못된 응답으로 무료 기본값 아래로 내려가지 않는다")
    func capacityNeverDropsBelowFree() {
        let library = MirrorLibrary()
        library.applyServerCapacity(2)
        #expect(library.mirrorCapacity == 5)
        library.applyServerCapacity(0)
        #expect(library.mirrorCapacity == 5)
    }

    @Test("로그아웃하면 표시가 무료 기본값으로 돌아간다")
    func signOutResetsTheDisplay() async {
        let (store, backend, library, _) = harness()
        backend.purchasedSlots = 5
        await store.refresh(session: session, library: library)
        #expect(library.mirrorCapacity == 10)

        store.clear(library: library)

        #expect(library.mirrorCapacity == 5)
        #expect(store.pack == nil)
    }
}

// MARK: - 구매

@MainActor
@Suite("보관 공간 구매")
struct CapacityPurchaseTests {

    @Test("성공하면 서버가 준 값으로 갱신한다")
    func purchaseAppliesServerValues() async {
        let (store, backend, library, wallet) = harness(balance: 20)
        await store.refresh(session: session, library: library)

        let outcome = await store.purchase(session: session, wallet: wallet, library: library)

        guard case .purchased(let result) = outcome else {
            Issue.record("구매가 성공하지 않았다: \(outcome)")
            return
        }
        #expect(result.chargedShards == 10)
        #expect(result.slotDelta == 5)
        #expect(result.effectiveSlots == 10)
        #expect(library.mirrorCapacity == 10)
        #expect(wallet.balance == result.balance)
        #expect(backend.balance == 10)
    }

    @Test("두 번째 구매는 새 의도이고 정상 누적된다")
    func repeatPurchaseStacks() async {
        let (store, backend, library, wallet) = harness(balance: 30)
        await store.refresh(session: session, library: library)

        await store.purchase(session: session, wallet: wallet, library: library)
        await store.purchase(session: session, wallet: wallet, library: library)

        #expect(library.mirrorCapacity == 15)
        #expect(backend.balance == 10)
        // 서로 다른 의도로 갔다.
        #expect(Set(backend.purchaseCalls).count == 2)
    }

    @Test("조각이 부족하면 아무것도 바뀌지 않는다")
    func insufficientShardsChangesNothing() async {
        let (store, backend, library, wallet) = harness(balance: 9)
        await store.refresh(session: session, library: library)

        let outcome = await store.purchase(session: session, wallet: wallet, library: library)

        #expect(outcome == .insufficientShards)
        #expect(library.mirrorCapacity == 5)
        #expect(backend.balance == 9)
        #expect(backend.purchasedSlots == 0)
    }

    @Test("로그인이 없으면 요청을 보내지 않는다")
    func signedOutDoesNotPurchase() async {
        let (store, backend, library, wallet) = harness()
        await store.refresh(session: session, library: library)

        let outcome = await store.purchase(session: nil, wallet: wallet, library: library)

        #expect(outcome == .needsSignIn)
        #expect(backend.purchaseCalls.isEmpty)
    }

    @Test("상품을 못 읽었으면 사지 않는다")
    func noPackMeansNoPurchase() async {
        let (store, backend, library, wallet) = harness()
        // refresh를 하지 않았다 — 가격을 모른다.
        let outcome = await store.purchase(session: session, wallet: wallet, library: library)

        if case .failed = outcome {} else { Issue.record("가격 없이 구매를 시도했다") }
        #expect(backend.purchaseCalls.isEmpty)
    }
}

// MARK: - 연타 · 재시도

@MainActor
@Suite("의도 하나 = operationId 하나")
struct CapacityOperationIDTests {

    @Test("연타해도 요청은 하나다")
    func doubleTapSendsOneRequest() async {
        let (store, backend, library, wallet) = harness(balance: 30)
        await store.refresh(session: session, library: library)
        backend.slowPurchase = true

        async let first = store.purchase(session: session, wallet: wallet, library: library)
        // 첫 요청이 아직 돌고 있는 동안 두 번째를 누른다.
        try? await Task.sleep(for: .milliseconds(20))
        async let second = store.purchase(session: session, wallet: wallet, library: library)
        _ = await (first, second)

        #expect(backend.purchaseCalls.count == 1)
        #expect(backend.balance == 20, "두 번 빠졌다")
        #expect(library.mirrorCapacity == 10)
    }

    @Test("응답을 잃으면 **같은 id로** 다시 보낸다")
    func retryReusesTheOperationID() async {
        let (store, backend, library, wallet) = harness(balance: 20)
        await store.refresh(session: session, library: library)

        // 서버는 처리했지만 응답이 사라졌다.
        backend.losesResponse = true
        let lost = await store.purchase(session: session, wallet: wallet, library: library)
        if case .failed = lost {} else { Issue.record("실패로 보고하지 않았다") }
        #expect(store.pendingOperationID != nil)

        // 재시도. **새 id를 만들지 않는다.**
        backend.losesResponse = false
        let retry = await store.purchase(session: session, wallet: wallet, library: library)

        #expect(backend.purchaseCalls.count == 2)
        #expect(backend.purchaseCalls[0] == backend.purchaseCalls[1], "새 id로 다시 보냈다")
        // **조각은 한 번만 빠졌다.**
        #expect(backend.balance == 10)
        #expect(backend.purchasedSlots == 5)
        if case .alreadyApplied(let result) = retry {
            #expect(result.effectiveSlots == 10)
        } else {
            Issue.record("이미 처리된 결과로 보고하지 않았다: \(retry)")
        }
        #expect(library.mirrorCapacity == 10)
    }

    @Test("성공한 뒤에는 다음 구매가 새 의도다")
    func successClearsThePendingIntent() async {
        let (store, backend, library, wallet) = harness(balance: 30)
        await store.refresh(session: session, library: library)

        await store.purchase(session: session, wallet: wallet, library: library)
        #expect(store.pendingOperationID == nil)

        await store.purchase(session: session, wallet: wallet, library: library)
        #expect(backend.purchaseCalls[0] != backend.purchaseCalls[1])
    }

    @Test("거절된 의도는 남기지 않는다")
    func rejectionClearsThePendingIntent() async {
        let (store, backend, library, wallet) = harness(balance: 9)
        await store.refresh(session: session, library: library)

        _ = await store.purchase(session: session, wallet: wallet, library: library)

        #expect(store.pendingOperationID == nil)
    }

    @Test("operationId는 UUID다")
    func operationIDIsAUUID() async {
        let (store, backend, library, wallet) = harness(balance: 20)
        await store.refresh(session: session, library: library)
        await store.purchase(session: session, wallet: wallet, library: library)

        let sent = try? #require(backend.purchaseCalls.first)
        #expect(UUID(uuidString: sent ?? "") != nil)
    }
}

// MARK: - 소스 규칙

@Suite("client는 경제를 계산하지 않는다")
struct CapacityClientArithmeticTests {

    @Test("잔액도 칸도 client가 더하지 않는다")
    func noLocalArithmetic() throws {
        let store = try capacitySource("ggumirror/Store/MirrorCapacityStore.swift")
        for banned in [
            "balance -=", "balance +=", "balance -", "purchasedSlots +=",
            "effectiveSlots +=", "+ pack.slotDelta", "- pack.costShards",
        ] {
            #expect(!store.contains(banned), "client가 경제를 계산한다: \(banned)")
        }
        // 서버 값을 옮겨 적는 통로만 있다.
        #expect(store.contains("wallet?.apply(balance: result.balance)"))
        #expect(store.contains("library?.applyServerCapacity(result.effectiveSlots)"))
    }

    @Test("가격과 칸 수를 앱에 적지 않는다")
    func noHardcodedEconomyNumbers() throws {
        for path in [
            "ggumirror/Store/MirrorCapacityStore.swift",
            "ggumirror/Shared/MirrorStorageFullDialog.swift",
            "ggumirror/Backend/BackendClient+Capacity.swift",
        ] {
            let source = try capacitySource(path)
            for banned in ["10조각", "5칸", "costShards: 10", "slotDelta: 5"] {
                #expect(!source.contains(banned), "\(path)에 경제 숫자를 적어 두었다: \(banned)")
            }
        }
    }

    @Test("보내는 것은 packId와 operationId뿐이다")
    func requestCarriesNoEconomyValues() throws {
        let client = try capacitySource("ggumirror/Backend/BackendClient+Capacity.swift")
        #expect(client.contains("let packId: String"))
        #expect(client.contains("let operationId: String"))
        for banned in ["costShards", "slotDelta", "balance", "amount", "slots"] {
            #expect(!client.contains("let \(banned)"), "요청에 \(banned)를 싣는다")
        }
    }

    @Test("로컬 저장 파일이 칸의 authority가 아니다")
    func localFileIsNotTheAuthority() throws {
        let library = try capacitySource("ggumirror/Shared/MirrorSampleData.swift")
        // 예전 로컬 부여 경로가 사라졌다.
        #expect(!library.contains("func grantSlotPack"))
        #expect(!library.contains("purchasedCreatedSlots +="))
        #expect(!library.contains("slotPackSize"))
        // 저장할 때 칸을 적지 않는다.
        #expect(library.contains("purchasedCreatedSlots: 0"))
        #expect(library.contains("private(set) var mirrorCapacity: Int = MirrorStoragePolicy.freeMirrorSlots"))
    }

    @Test("보관 한도만 막고 다른 도메인을 건드리지 않는다")
    func capacityDoesNotTouchOtherDomains() throws {
        let store = try capacitySource("ggumirror/Store/MirrorCapacityStore.swift")
        for foreign in ["Marketplace", "StickerProject", "ownership", "downloadCount"] {
            #expect(!store.contains(foreign), "capacity가 \(foreign)를 안다")
        }
    }
}

// MARK: - 가득 찼을 때

@MainActor
@Suite("가득 찬 안내가 구매로 이어진다")
struct CapacityFullDialogTests {

    @Test("세 경로가 같은 문을 쓴다")
    func everyFullPathSharesOneDialog() throws {
        for path in [
            "ggumirror/MyMirrors/MyMirrorsView.swift",
            "ggumirror/Editor/EditorView.swift",
            "ggumirror/Store/TemplateDetailView.swift",
        ] {
            #expect(try capacitySource(path).contains("inkMirrorStorageFullDialog"), "\(path)")
        }
    }

    @Test("공간 늘리기가 실제 구매를 연다")
    func expandCTALeadsToThePurchase() throws {
        let dialog = try capacitySource("ggumirror/Shared/MirrorStorageFullDialog.swift")
        #expect(dialog.contains("\"공간 늘리기\""))
        #expect(dialog.contains("isConfirming.wrappedValue = true"))
        #expect(dialog.contains("capacity.purchase("))
        // 별도 시트를 새로 만들지 않는다 — 기존 root-level Ink dialog다.
        #expect(!dialog.contains("inkBottomSheet"))
        #expect(!dialog.contains("fullScreenCover"))
        #expect(!dialog.contains(".overlay"))
    }

    @Test("상품을 모르면 누를 수 있는 버튼을 두지 않는다")
    func noPackMeansNoCTA() throws {
        let dialog = try capacitySource("ggumirror/Shared/MirrorStorageFullDialog.swift")
        #expect(dialog.contains("if pack != nil"))
        #expect(dialog.contains("if let pack {"))
    }

    @Test("한도가 늘면 다시 담을 수 있다")
    func raisingCapacityUnlocksAcquisition() {
        let library = MirrorLibrary()
        while library.hasFreeMirrorSlot {
            _ = library.save(.blank, name: "거울", context: .createNew)
        }
        #expect(library.acquire(StoreCatalog.basics[0]) == nil)

        // 서버가 칸을 늘려 줬다.
        library.applyServerCapacity(10)

        #expect(library.hasFreeMirrorSlot)
        #expect(library.acquire(StoreCatalog.basics[0]) != nil)
    }

    @Test("한도를 넘긴 사용자의 거울을 지우지 않는다")
    func overCapacityMirrorsSurvive() {
        let library = MirrorLibrary()
        library.applyServerCapacity(10)
        while library.hasFreeMirrorSlot {
            _ = library.save(.blank, name: "거울", context: .createNew)
        }
        let stored = library.storedCount
        #expect(stored == 10)

        // 다음 세션에서 서버를 못 읽어 무료 기본값으로 돌아갔다.
        let reset = MirrorLibrary()
        _ = reset
        library.applyServerCapacity(5)   // 무시된다(무료 기본값 아래로 내려가지 않는 규칙과 별개)

        // 담아 둔 거울은 그대로다.
        #expect(library.storedCount == stored)
    }
}
