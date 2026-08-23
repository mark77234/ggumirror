//
//  StoreCatalog.swift
//  ggumirror
//
//  상점에 올라가는 템플릿 목록 한 곳.
//
//  두 종류가 있다:
//    1. 단색 기본 템플릿 — 프레임 색만 다르다. 공식 제공이라 항상 무료.
//    2. 아트워크 템플릿 — 1080 × 2340 손그림 PNG 한 장이 거울의 얼굴이 된다.
//       사용자가 "외부에서 만들기"로 가져오는 것과 **완전히 같은 형식**이라
//       렌더 / 저장 / 미리보기 파이프라인을 하나도 새로 만들지 않는다.
//
//  템플릿을 늘릴 때는 `artworkTemplates`에 한 줄 추가하면 된다.
//  PNG는 Resources/StoreTemplates/<카테고리>/<파일이름>.png 에 둔다.
//  폴더 갈래는 Free / RibbonHeart / Diary / Y2K / Moments 다섯 가지로 정해 두었다.
//  (빈 폴더는 번들에 그대로 복사돼 이름 충돌을 내므로, 첫 PNG를 넣을 때 함께 만든다.)
//

import CoreGraphics
import ImageIO
import SwiftUI

// MARK: - 분류

enum StoreTag: String, CaseIterable, Identifiable {
    case ribbon = "리본"
    case y2k = "Y2K"
    case cute = "큐트"
    case minimal = "미니멀"
    case vintage = "빈티지"
    case character = "캐릭터"
    case diary = "다이어리"

    var id: String { rawValue }
}

/// 상점 필터 한 줄에 들어가는 항목.
///
/// **콘텐츠 갈래**(무료 / 리본 & 하트 / 다이어리 / Y2K / 기념일 / 기본)와
/// **표시 꼬리표**(추천 / 인기 / 신규)를 하나의 열거형으로 다루되,
/// 템플릿 쪽에서는 갈래를 정확히 하나만 갖고 꼬리표는 따로 담는다.
/// 문자열 Set 하나에 섞어 넣지 않는다.
enum StoreCategory: String, CaseIterable, Identifiable {
    case all = "전체"
    case free = "무료"
    case ribbonHeart = "리본 & 하트"
    case diary = "다이어리"
    case y2k = "Y2K"
    case moments = "기념일"
    case basic = "기본"
    case featured = "추천"
    case popular = "인기"
    case new = "신규"

    var id: String { rawValue }

    /// 템플릿 하나가 정확히 하나씩 갖는 갈래.
    static let contentGroups: [StoreCategory] = [.free, .ribbonHeart, .diary, .y2k, .moments, .basic]

    /// 갈래와 별개로 붙는 꼬리표.
    static let highlightTags: [StoreCategory] = [.featured, .popular, .new]

    /// **actual Store economy 이전 임시 가격.** 갈래마다 한 값만 쓴다 —
    /// 조각 차감 / 실제 구매는 다음 Backend·Shard Ledger phase의 일이다.
    var temporaryPrice: Int {
        switch self {
        case .free, .basic: 0
        case .ribbonHeart, .diary: 18
        case .moments: 20
        case .y2k: 24
        // 갈래가 아닌 꼬리표에는 가격이 없다.
        case .all, .featured, .popular, .new: 0
        }
    }
}

// MARK: - 아트워크 리소스

/// 번들에 들어 있는 전체 캔버스 PNG 한 장.
///
/// `assetID`는 **고정값**이다. 상점을 열 때마다 새 id를 만들면 같은 그림이
/// 계속 새 파일로 쌓이므로, 템플릿마다 하나씩 미리 정해 둔다.
struct StoreArtworkResource: Hashable {
    let fileName: String
    /// Resources 아래 폴더. 번들이 폴더 구조를 평탄화해도 파일 이름으로 다시 찾는다.
    let subdirectory: String
    let assetID: UUID

    var url: URL? {
        Bundle.main.url(forResource: fileName, withExtension: "png", subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: fileName, withExtension: "png")
    }

    func loadImage() -> CGImage? {
        guard let url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

// MARK: - 템플릿

struct MirrorTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let creator: String
    /// 콘텐츠 갈래. 정확히 하나다.
    let category: StoreCategory
    /// 추천 / 인기 / 신규. 갈래와 섞이지 않는 별도 꼬리표다.
    let highlights: Set<StoreCategory>
    let tags: [StoreTag]
    let style: MirrorStyle
    /// 손그림 PNG 템플릿이면 여기 들어온다. 단색 기본 템플릿은 nil.
    var artwork: StoreArtworkResource?

    /// 이 상품의 획득 수를 **서버가 세고 있는가.**
    ///
    /// 내장 템플릿은 아직 아니다 — 다운로드가 순수 로컬 동작이라 서버에 기록되는
    /// 곳도 세는 곳도 없다(감사로 확인했다). 그래서 `0`을 보여 주면 "아무도 안
    /// 받았다"는 **거짓말**이 된다. 세지 않는 값은 숫자로 말하지 않는다.
    ///
    /// 서버가 세는 Marketplace 상품은 `MarketplaceListing`이 따로 표시한다.
    var hasServerStats: Bool = false

    /// 받아 간 횟수. **서버가 세는 값이고 앱이 올리지 않는다.**
    ///
    /// 의미는 "최초 소유권 획득 성공"이다 — 유료는 결제+소유권 생성, 무료는 소유권 생성.
    /// 재다운로드 · 중복 구매 · 판매자 본인 사용 · 미리보기는 **오르지 않는다**.
    /// 아직 서버가 없으므로 내장 목록은 전부 0이다. 숫자를 지어내지 않는다.
    var downloadCount: Int = 0
    /// 좋아요 수. 마찬가지로 서버 값이고, 지금은 0이다.
    var likeCount: Int = 0
    /// **상점에 처음 올라온 날.** 마지막 수정일이 아니다(서버의 `publishedAt`과 같은 뜻).
    ///
    /// 내장 목록은 상점에 업로드된 적이 없으므로 `nil`이다 —
    /// `Date.now`를 채워 넣으면 거짓말이 된다.
    var uploadedAt: Date?

    /// 조각 가격. 갈래 하나로 정해진다 — 값이 코드 여기저기 흩어지지 않는다.
    var price: Int { category.temporaryPrice }

    /// 공식 단색 기본 템플릿인지. 받아도 슬롯을 쓰지 않고 항상 무료다.
    var isBasic: Bool { id.hasPrefix(StoreCatalog.basicPrefix) }
    var isFree: Bool { price == 0 }

    func matches(_ filter: StoreCategory) -> Bool {
        switch filter {
        case .all: true
        default: category == filter || highlights.contains(filter)
        }
    }
}

// MARK: - 정렬

/// 상점 정렬. **거울 상점과 스티커 상점이 같은 규칙을 쓴다.**
enum StoreSort: String, CaseIterable, Identifiable {
    case latest
    case popular
    case likes

    var id: String { rawValue }

    /// 상점에 처음 들어왔을 때의 값.
    static let `default` = StoreSort.latest

    var label: String {
        switch self {
        case .latest: "최신 순"
        case .popular: "인기 순"
        case .likes: "좋아요 순"
        }
    }

    /// **"인기"의 authority는 다운로드 수 하나다.**
    ///
    /// 좋아요와 다운로드를 섞은 가중 점수를 만들지 않는다 — 이름만 "인기 순"이고
    /// 실제 기준은 `downloadCount`다. 섞으면 왜 이 순서인지 아무도 설명할 수 없다.
    ///
    /// tie-breaker는 **결정적**이다. 값이 같을 때 순서가 실행마다 흔들리면
    /// 목록이 이유 없이 재배열돼 보인다.
    func sorted(_ templates: [MirrorTemplate]) -> [MirrorTemplate] { ordered(templates) }

    /// 내장 목록과 **서버 상품**이 같은 규칙으로 정렬된다(`StoreSortable`).
    /// 두 목록이 다른 순서를 내면 사용자는 목록이 흔들리는 것으로 본다.
    func ordered<T: StoreSortable>(_ items: [T]) -> [T] {
        items.sorted { lhs, rhs in
            switch self {
            case .latest:
                // uploadedAt DESC, 같으면 id로 안정화
                if lhs.uploadedAtKey != rhs.uploadedAtKey {
                    return lhs.uploadedAtKey > rhs.uploadedAtKey
                }
            case .popular:
                // downloadCount DESC → uploadedAt DESC → id
                if lhs.downloadCount != rhs.downloadCount {
                    return lhs.downloadCount > rhs.downloadCount
                }
                if lhs.uploadedAtKey != rhs.uploadedAtKey {
                    return lhs.uploadedAtKey > rhs.uploadedAtKey
                }
            case .likes:
                // likeCount DESC → downloadCount DESC → uploadedAt DESC → id
                if lhs.likeCount != rhs.likeCount {
                    return lhs.likeCount > rhs.likeCount
                }
                if lhs.downloadCount != rhs.downloadCount {
                    return lhs.downloadCount > rhs.downloadCount
                }
                if lhs.uploadedAtKey != rhs.uploadedAtKey {
                    return lhs.uploadedAtKey > rhs.uploadedAtKey
                }
            }
            // 마지막 열쇠는 언제나 id다 — 값이 모두 같아도 순서가 흔들리지 않는다.
            return lhs.sortIdentity < rhs.sortIdentity
        }
    }
}

extension MirrorTemplate {
    /// 정렬에 쓰는 업로드 시각. **올라온 적 없는 내장 목록은 가장 뒤로 간다.**
    /// `Date.distantPast`는 저장하지 않고 비교할 때만 쓴다 — 문서에 거짓 날짜를 넣지 않는다.
    var uploadedAtKey: Date { uploadedAt ?? .distantPast }
}

extension MirrorTemplate {
    /// 카드/상세가 함께 쓰는 표시 문자열. **0도 감추지 않는다** —
    /// 감추면 상품마다 metadata 폭이 달라져 목록이 들쭉날쭉해진다.
    var uploadedAtLabel: String {
        guard let uploadedAt else { return "—" }
        return uploadedAt.formatted(.dateTime.year().month().day())
    }
}

// MARK: - 목록

enum StoreCatalog {
    static let basicPrefix = "basic-"

    /// 상점 전체 목록. 손그림 아트워크 24장이 먼저, 그다음 단색 기본 8종.
    /// placeholder(SF Symbol 낙서 샘플)는 남아 있지 않다.
    static var samples: [MirrorTemplate] { artworkTemplates + basics }

    /// 손그림 PNG 템플릿 **24장**. 상점에서 사용자에게 보이는 콘텐츠는 이게 전부다.
    /// 갈래: 무료 8 / 리본 & 하트 4 / 다이어리 4 / Y2K 4 / 기념일 4.
    ///
    /// `id`와 `assetID`는 둘 다 고정값이다 — 앱을 다시 켜도 같은 값이어야
    /// 이미 받은 거울이 그대로 열리고, 같은 그림이 새 파일로 쌓이지 않는다.
    static let artworkTemplates: [MirrorTemplate] = [
        MirrorTemplate(
            id: "art-pink-ribbon",
            name: "핑크 리본",
            creator: "꾸미러",
            category: .free,
            highlights: [.featured],
            tags: [.ribbon, .cute],
            style: MirrorStyle(frame: Color(red: 0.980, green: 0.890, blue: 0.918)),
            artwork: StoreArtworkResource(
                fileName: "pink-ribbon",
                subdirectory: "StoreTemplates/Free",
                assetID: UUID(uuidString: "A0000001-0000-4000-A000-000000000001")!
            )
        ),
        MirrorTemplate(
            id: "art-ink-heart",
            name: "잉크 하트",
            creator: "꾸미러",
            category: .free,
            highlights: [],
            tags: [.minimal, .cute],
            style: MirrorStyle(frame: Color(red: 0.988, green: 0.976, blue: 0.972)),
            artwork: StoreArtworkResource(
                fileName: "ink-heart",
                subdirectory: "StoreTemplates/Free",
                assetID: UUID(uuidString: "A0000004-0000-4000-A000-000000000004")!
            )
        ),
        MirrorTemplate(
            id: "art-cream-note",
            name: "크림 노트",
            creator: "꾸미러",
            category: .free,
            highlights: [],
            tags: [.diary, .vintage],
            style: MirrorStyle(frame: Color(red: 0.976, green: 0.957, blue: 0.918)),
            artwork: StoreArtworkResource(
                fileName: "cream-note",
                subdirectory: "StoreTemplates/Free",
                assetID: UUID(uuidString: "A0000005-0000-4000-A000-000000000005")!
            )
        ),
        MirrorTemplate(
            id: "art-lavender-star",
            name: "라벤더 스타",
            creator: "꾸미러",
            category: .free,
            highlights: [.new],
            tags: [.y2k, .cute],
            style: MirrorStyle(frame: Color(red: 0.941, green: 0.929, blue: 0.965)),
            artwork: StoreArtworkResource(
                fileName: "lavender-star",
                subdirectory: "StoreTemplates/Free",
                assetID: UUID(uuidString: "A0000006-0000-4000-A000-000000000006")!
            )
        ),
        MirrorTemplate(
            id: "art-sky-cloud",
            name: "스카이 클라우드",
            creator: "꾸미러",
            category: .free,
            highlights: [],
            tags: [.minimal, .cute],
            style: MirrorStyle(frame: Color(red: 0.925, green: 0.949, blue: 0.973)),
            artwork: StoreArtworkResource(
                fileName: "sky-cloud",
                subdirectory: "StoreTemplates/Free",
                assetID: UUID(uuidString: "A0000007-0000-4000-A000-000000000007")!
            )
        ),
        MirrorTemplate(
            id: "art-mint-flower",
            name: "민트 플라워",
            creator: "꾸미러",
            category: .free,
            highlights: [],
            tags: [.cute, .minimal],
            style: MirrorStyle(frame: Color(red: 0.918, green: 0.961, blue: 0.945)),
            artwork: StoreArtworkResource(
                fileName: "mint-flower",
                subdirectory: "StoreTemplates/Free",
                assetID: UUID(uuidString: "A0000008-0000-4000-A000-000000000008")!
            )
        ),
        MirrorTemplate(
            id: "art-gray-check",
            name: "그레이 체크",
            creator: "꾸미러",
            category: .free,
            highlights: [],
            tags: [.minimal],
            style: MirrorStyle(frame: Color(red: 0.949, green: 0.945, blue: 0.937)),
            artwork: StoreArtworkResource(
                fileName: "gray-check",
                subdirectory: "StoreTemplates/Free",
                assetID: UUID(uuidString: "A0000009-0000-4000-A000-000000000009")!
            )
        ),
        MirrorTemplate(
            id: "art-red-point",
            name: "레드 포인트",
            creator: "꾸미러",
            category: .free,
            highlights: [.new],
            tags: [.minimal, .vintage],
            style: MirrorStyle(frame: Color(red: 0.984, green: 0.949, blue: 0.941)),
            artwork: StoreArtworkResource(
                fileName: "red-point",
                subdirectory: "StoreTemplates/Free",
                assetID: UUID(uuidString: "A0000010-0000-4000-A000-000000000010")!
            )
        ),
        MirrorTemplate(
            id: "art-lovely-bow",
            name: "러블리 보우",
            creator: "꾸미러",
            category: .ribbonHeart,
            highlights: [.featured],
            tags: [.ribbon, .cute],
            style: MirrorStyle(frame: Color(red: 0.984, green: 0.910, blue: 0.929)),
            artwork: StoreArtworkResource(
                fileName: "lovely-bow",
                subdirectory: "StoreTemplates/RibbonHeart",
                assetID: UUID(uuidString: "A0000011-0000-4000-A000-000000000011")!
            )
        ),
        MirrorTemplate(
            id: "art-love-letter",
            name: "러브 레터",
            creator: "꾸미러",
            category: .ribbonHeart,
            highlights: [],
            tags: [.ribbon, .vintage],
            style: MirrorStyle(frame: Color(red: 0.980, green: 0.933, blue: 0.941)),
            artwork: StoreArtworkResource(
                fileName: "love-letter",
                subdirectory: "StoreTemplates/RibbonHeart",
                assetID: UUID(uuidString: "A0000012-0000-4000-A000-000000000012")!
            )
        ),
        MirrorTemplate(
            id: "art-cherry-love",
            name: "체리 러브",
            creator: "꾸미러",
            category: .ribbonHeart,
            highlights: [.popular],
            tags: [.cute, .vintage],
            style: MirrorStyle(frame: Color(red: 0.988, green: 0.925, blue: 0.918)),
            artwork: StoreArtworkResource(
                fileName: "cherry-love",
                subdirectory: "StoreTemplates/RibbonHeart",
                assetID: UUID(uuidString: "A0000013-0000-4000-A000-000000000013")!
            )
        ),
        MirrorTemplate(
            id: "art-angel-heart",
            name: "엔젤 하트",
            creator: "꾸미러",
            category: .ribbonHeart,
            highlights: [.new],
            tags: [.cute, .ribbon],
            style: MirrorStyle(frame: Color(red: 0.937, green: 0.953, blue: 0.976)),
            artwork: StoreArtworkResource(
                fileName: "angel-heart",
                subdirectory: "StoreTemplates/RibbonHeart",
                assetID: UUID(uuidString: "A0000014-0000-4000-A000-000000000014")!
            )
        ),
        MirrorTemplate(
            id: "art-my-diary",
            name: "마이 다이어리",
            creator: "꾸미러",
            category: .diary,
            highlights: [.featured],
            tags: [.diary, .vintage],
            style: MirrorStyle(frame: Color(red: 0.969, green: 0.945, blue: 0.890)),
            artwork: StoreArtworkResource(
                fileName: "my-diary",
                subdirectory: "StoreTemplates/Diary",
                assetID: UUID(uuidString: "A0000002-0000-4000-A000-000000000002")!
            )
        ),
        MirrorTemplate(
            id: "art-checklist",
            name: "체크리스트",
            creator: "꾸미러",
            category: .diary,
            highlights: [],
            tags: [.diary, .minimal],
            style: MirrorStyle(frame: Color(red: 0.961, green: 0.961, blue: 0.957)),
            artwork: StoreArtworkResource(
                fileName: "checklist",
                subdirectory: "StoreTemplates/Diary",
                assetID: UUID(uuidString: "A0000015-0000-4000-A000-000000000015")!
            )
        ),
        MirrorTemplate(
            id: "art-scrapbook",
            name: "스크랩북",
            creator: "꾸미러",
            category: .diary,
            highlights: [.popular],
            tags: [.diary, .vintage],
            style: MirrorStyle(frame: Color(red: 0.973, green: 0.953, blue: 0.918)),
            artwork: StoreArtworkResource(
                fileName: "scrapbook",
                subdirectory: "StoreTemplates/Diary",
                assetID: UUID(uuidString: "A0000016-0000-4000-A000-000000000016")!
            )
        ),
        MirrorTemplate(
            id: "art-cafe-note",
            name: "카페 노트",
            creator: "꾸미러",
            category: .diary,
            highlights: [],
            tags: [.diary, .vintage],
            style: MirrorStyle(frame: Color(red: 0.965, green: 0.945, blue: 0.925)),
            artwork: StoreArtworkResource(
                fileName: "cafe-note",
                subdirectory: "StoreTemplates/Diary",
                assetID: UUID(uuidString: "A0000017-0000-4000-A000-000000000017")!
            )
        ),
        MirrorTemplate(
            id: "art-y2k-star",
            name: "Y2K 스타",
            creator: "꾸미러",
            category: .y2k,
            highlights: [.popular, .new],
            tags: [.y2k, .character],
            style: MirrorStyle(frame: Color(red: 0.878, green: 0.878, blue: 0.973)),
            artwork: StoreArtworkResource(
                fileName: "y2k-star",
                subdirectory: "StoreTemplates/Y2K",
                assetID: UUID(uuidString: "A0000003-0000-4000-A000-000000000003")!
            )
        ),
        MirrorTemplate(
            id: "art-cyber-love",
            name: "사이버 러브",
            creator: "꾸미러",
            category: .y2k,
            highlights: [],
            tags: [.y2k, .ribbon],
            style: MirrorStyle(frame: Color(red: 0.898, green: 0.914, blue: 0.976)),
            artwork: StoreArtworkResource(
                fileName: "cyber-love",
                subdirectory: "StoreTemplates/Y2K",
                assetID: UUID(uuidString: "A0000018-0000-4000-A000-000000000018")!
            )
        ),
        MirrorTemplate(
            id: "art-flash-girl",
            name: "플래시 걸",
            creator: "꾸미러",
            category: .y2k,
            highlights: [.new],
            tags: [.y2k, .character],
            style: MirrorStyle(frame: Color(red: 0.984, green: 0.902, blue: 0.941)),
            artwork: StoreArtworkResource(
                fileName: "flash-girl",
                subdirectory: "StoreTemplates/Y2K",
                assetID: UUID(uuidString: "A0000019-0000-4000-A000-000000000019")!
            )
        ),
        MirrorTemplate(
            id: "art-retro-pop",
            name: "레트로 팝",
            creator: "꾸미러",
            category: .y2k,
            highlights: [],
            tags: [.y2k, .vintage],
            style: MirrorStyle(frame: Color(red: 0.988, green: 0.941, blue: 0.898)),
            artwork: StoreArtworkResource(
                fileName: "retro-pop",
                subdirectory: "StoreTemplates/Y2K",
                assetID: UUID(uuidString: "A0000020-0000-4000-A000-000000000020")!
            )
        ),
        MirrorTemplate(
            id: "art-birthday",
            name: "생일",
            creator: "꾸미러",
            category: .moments,
            highlights: [.featured],
            tags: [.cute, .character],
            style: MirrorStyle(frame: Color(red: 0.988, green: 0.961, blue: 0.902)),
            artwork: StoreArtworkResource(
                fileName: "birthday",
                subdirectory: "StoreTemplates/Moments",
                assetID: UUID(uuidString: "A0000021-0000-4000-A000-000000000021")!
            )
        ),
        MirrorTemplate(
            id: "art-summer-trip",
            name: "여름 여행",
            creator: "꾸미러",
            category: .moments,
            highlights: [],
            tags: [.cute, .minimal],
            style: MirrorStyle(frame: Color(red: 0.910, green: 0.957, blue: 0.969)),
            artwork: StoreArtworkResource(
                fileName: "summer-trip",
                subdirectory: "StoreTemplates/Moments",
                assetID: UUID(uuidString: "A0000022-0000-4000-A000-000000000022")!
            )
        ),
        MirrorTemplate(
            id: "art-spring-bloom",
            name: "봄 꽃",
            creator: "꾸미러",
            category: .moments,
            highlights: [.new],
            tags: [.cute],
            style: MirrorStyle(frame: Color(red: 0.988, green: 0.945, blue: 0.937)),
            artwork: StoreArtworkResource(
                fileName: "spring-bloom",
                subdirectory: "StoreTemplates/Moments",
                assetID: UUID(uuidString: "A0000023-0000-4000-A000-000000000023")!
            )
        ),
        MirrorTemplate(
            id: "art-winter-letter",
            name: "겨울 편지",
            creator: "꾸미러",
            category: .moments,
            highlights: [],
            tags: [.minimal, .vintage],
            style: MirrorStyle(frame: Color(red: 0.933, green: 0.953, blue: 0.973)),
            artwork: StoreArtworkResource(
                fileName: "winter-letter",
                subdirectory: "StoreTemplates/Moments",
                assetID: UUID(uuidString: "A0000024-0000-4000-A000-000000000024")!
            )
        ),
    ]

    /// 단색 기본 템플릿 8종. 공식 제공이라 항상 무료다.
    static let basics: [MirrorTemplate] = BasicMirror.allCases.map { basic in
        MirrorTemplate(
            id: basicPrefix + basic.id,
            name: basic.name,
            creator: "꾸미러",
            category: .basic,
            highlights: [],
            tags: [.minimal],
            style: basic.style
        )
    }
}

// MARK: - 아트워크 보관

/// 번들 PNG를 거울이 쓰는 형태(`ImportedArtworkObject`)로 바꿔 준다.
///
/// 사용자가 직접 가져올 때와 **같은 `normalize`를 거친다** — 카메라 영역이 비워지고
/// 1080 × 2340으로 맞춰지는 규칙이 상점 템플릿에도 똑같이 적용된다.
/// 결과는 템플릿 id 하나당 한 번만 만들어 캐시한다.
@MainActor
enum StoreArtworkLibrary {
    private static var cache: [String: ImportedArtworkObject] = [:]

    static func artworks(for template: MirrorTemplate) -> [ImportedArtworkObject] {
        guard let artwork = artwork(for: template) else { return [] }
        return [artwork]
    }

    static func artwork(for template: MirrorTemplate) -> ImportedArtworkObject? {
        if let cached = cache[template.id] { return cached }
        guard let resource = template.artwork,
              let image = resource.loadImage(),
              let framed = MirrorArtworkImporter.framedArtwork(image)
        else { return nil }

        ImportedArtworkAssetStore.shared.registerBundled(framed, id: resource.assetID)
        let object = ImportedArtworkObject(assetID: resource.assetID)
        cache[template.id] = object
        return object
    }
}
