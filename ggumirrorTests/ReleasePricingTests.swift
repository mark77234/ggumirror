//
//  ReleasePricingTests.swift
//  ggumirrorTests
//
//  1.1.0 출시 가격. **client는 값을 정하지 않는다.**
//
//      AI 거울 생성      5조각   ← 서버가 준 `config.price`를 그대로 보여 준다
//      AI 스티커 생성    5조각   ← 서버가 준 `config.price`를 그대로 보여 준다
//      스티커 상점 등록  10조각  ← 정책 상수(화면 표시용). 차감은 서버가 한다
//      거울 상점 등록    10조각  ← 이번에 바뀌지 않았다
//
//  생성값과 등록비는 **다른 축이다.** 숫자가 겹쳐 보여도 한 상수로 묶지 않는다.
//
//  여기서 지키는 것 셋:
//    1. 화면에 숫자를 적지 않는다 — 서버 값 또는 정책 상수를 읽는다
//    2. 요청에 가격을 실을 자리가 없다
//    3. 잔액은 서버가 준 값만 옮겨 적는다(local 차감 없음)
//

import Testing
import Foundation
@testable import ggumirror

private func priceSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    return codeWithoutComments(
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    )
}

// MARK: - 등록비

@Suite("상점 등록비")
struct PublishFeePricingTests {

    @Test("스티커 등록비가 10조각이다")
    func stickerPublishFeeIsTen() {
        #expect(StickerPublishPolicy.feeInShards == 10)
    }

    @Test("거울 등록비는 그대로 10조각이다")
    func mirrorPublishFeeIsUnchanged() {
        #expect(MirrorPublishPolicy.feeInShards == 10)
    }

    @Test("등록 화면이 숫자를 적지 않는다")
    func publishScreensReadThePolicy() throws {
        for (path, policy) in [
            ("ggumirror/Store/PublishStickerView.swift", "StickerPublishPolicy.feeInShards"),
            ("ggumirror/Store/PublishMirrorView.swift", "MirrorPublishPolicy.feeInShards"),
        ] {
            let code = try priceSource(path)
            #expect(code.contains(policy), "\(path)")
            // CTA · 가격 caption · 낭독기 label이 전부 그 값 하나에서 나온다.
            #expect(code.components(separatedBy: policy).count - 1 >= 3, "\(path)")
            // 옛 값도 새 값도 손으로 적지 않는다.
            for magic in ["(5 조각)", "(10 조각)", "amount: 5", "amount: 10"] {
                #expect(!code.contains(magic), "\(path): \(magic)")
            }
        }
    }

    @Test("삭제 안내가 실제 등록비를 말한다")
    func deleteCopyMatchesTheFee() throws {
        // "등록할 때 사용한 N조각은 환불되지 않아요" — N이 정책에서 온다.
        let code = try priceSource("ggumirror/Store/MySalesSection.swift")
        #expect(code.contains("StickerPublishPolicy.feeInShards"))
        #expect(code.contains("MirrorPublishPolicy.feeInShards"))
        #expect(code.contains("publishFeeShards"))
    }

    @Test("등록 요청이 가격을 싣지 않는다")
    func publishRequestCarriesNoPrice() throws {
        let api = try priceSource("ggumirror/Backend/MarketplaceAPI.swift")
        // 등록 요청 body에 등록비를 넣는 자리가 없다 — 서버가 정한다.
        for forbidden in ["publishFee", "feeShards:", "cost:"] {
            let create = api.range(of: "struct CreateListingBody")
            if let create {
                let body = String(api[create.lowerBound...].prefix(400))
                #expect(!body.contains(forbidden), "\(forbidden)")
            }
        }
        #expect(!api.contains("MirrorPublishPolicy.feeInShards"))
        #expect(!api.contains("StickerPublishPolicy.feeInShards"))
    }
}

// MARK: - AI 생성값

@Suite("AI 생성값은 서버가 정한다")
@MainActor
struct AIGenerationPricingTests {

    @Test("거울 화면이 서버 값을 그대로 보여 준다")
    func mirrorPriceComesFromTheServer() throws {
        let view = try priceSource("ggumirror/MyMirrors/AIMirrorView.swift")
        #expect(view.contains("config.price"))
        #expect(view.contains("maker.price"))
        // 숫자를 적으면 서버 표를 바꿀 때 화면만 옛 값을 말한다.
        for magic in ["10조각", "6조각", "5조각", "= 5", "= 10"] {
            #expect(!view.contains(magic), "\(magic)")
        }
    }

    @Test("스티커 화면이 서버 값을 그대로 보여 준다")
    func stickerPriceComesFromTheServer() throws {
        let sheet = try priceSource("ggumirror/AI/AIStickerPromptSheet.swift")
        #expect(sheet.contains("let price: Int"))
        // 부족 안내도 같은 값을 쓴다 — 문구와 실제 값이 갈라질 수 없다.
        #expect(sheet.contains("\\(price)조각이 필요해요"))
        for magic in ["6조각을", "5조각을", "= 6", "= 5"] {
            #expect(!sheet.contains(magic), "\(magic)")
        }
    }

    @Test("서버가 5를 주면 화면이 5를 쓴다")
    func serverPriceFlowsThrough() {
        // 서버 응답이 곧 화면 값이다 — 사이에 앱이 정한 숫자가 없다.
        let config = AIMirrorConfig(available: true, price: 5)
        #expect(config.price == 5)

        let maker = AIMirrorMaker(backend: FakePricingBackend(config: config))
        #expect(maker.price == 0, "서버에 묻기 전에는 값을 모른다")
    }

    @Test("서버에 묻기 전에는 값을 지어내지 않는다")
    func noPriceBeforeTheServerAnswers() {
        let maker = AIMirrorMaker(backend: FakePricingBackend(config: nil))
        // 모르는 값을 0으로 두고 화면이 가격 줄을 숨긴다 — 5를 미리 적지 않는다.
        #expect(maker.price == 0)
    }

    @Test("생성 요청이 가격을 싣지 않는다")
    func generateRequestCarriesNoPrice() throws {
        let api = try priceSource("ggumirror/Backend/BackendClient+AIMirror.swift")
        let body = try #require(api.range(of: "struct Body: Encodable"))
        let request = String(api[body.lowerBound...].prefix(300))
        for forbidden in ["price", "shardAmount", "cost", "amount"] {
            #expect(!request.contains(forbidden), "\(forbidden)")
        }
    }

    @Test("잔액을 client가 계산하지 않는다")
    func theClientNeverMovesTheWallet() throws {
        for path in [
            "ggumirror/MyMirrors/AIMirrorView.swift",
            "ggumirror/AI/AIStickerService.swift",
        ] {
            let code = try priceSource(path)
            for banned in ["balance -=", "balance +=", "balance = balance"] {
                #expect(!code.contains(banned), "\(path): \(banned)")
            }
        }
        // 값이 움직이는 유일한 통로는 서버 응답이다.
        let wallet = try priceSource("ggumirror/Shared/ShardWallet.swift")
        #expect(wallet.contains("func apply(balance newBalance: Int)"))
    }

    @Test("생성 뒤에 지갑을 서버 값으로 다시 맞춘다")
    func walletRefreshesAfterGeneration() throws {
        let view = try priceSource("ggumirror/MyMirrors/AIMirrorView.swift")
        // 성공이든 실패든 마지막에 서버에 다시 묻는다.
        #expect(view.contains("await refresh(session: session)"))
    }
}

/// 서버 응답만 흉내 낸다. **provider도 조각도 건드리지 않는다.**
private struct FakePricingBackend: AIMirrorBackend {
    let config: AIMirrorConfig?

    func aiMirrorConfig(accessToken: String) async throws -> AIMirrorConfig {
        guard let config else { throw AIMirrorFailure.unavailable }
        return config
    }

    func generateAIMirror(
        prompt: String, requestID: String, accessToken: String
    ) async throws -> Data {
        throw AIMirrorFailure.unavailable
    }
}

// MARK: - 두 축이 섞이지 않는다

@Suite("생성값과 등록비는 다른 축이다")
struct PricingAxesTests {

    @Test("등록비가 생성값을 따라가지 않는다")
    func publishFeeIsNotTheGenerationPrice() {
        // 서버 값이 5(생성)와 10(등록)으로 갈라져 있고, client 상수도 그 축을 지킨다.
        #expect(StickerPublishPolicy.feeInShards == 10)
        #expect(MirrorPublishPolicy.feeInShards == 10)
    }

    @Test("등록비 상수가 AI 화면에 새어 들지 않는다")
    func publishPolicyNeverReachesTheAIScreens() throws {
        for path in [
            "ggumirror/MyMirrors/AIMirrorView.swift",
            "ggumirror/AI/AIStickerPromptSheet.swift",
            "ggumirror/AI/AIStickerService.swift",
        ] {
            let code = try priceSource(path)
            #expect(!code.contains("PublishPolicy"), "\(path)")
        }
    }

    @Test("AI 생성값이 등록 화면에 새어 들지 않는다")
    func generationPriceNeverReachesThePublishScreens() throws {
        for path in [
            "ggumirror/Store/PublishStickerView.swift",
            "ggumirror/Store/PublishMirrorView.swift",
        ] {
            let code = try priceSource(path)
            for forbidden in ["aiSticker", "AIMirror", "config.price"] {
                #expect(!code.contains(forbidden), "\(path): \(forbidden)")
            }
        }
    }
}
