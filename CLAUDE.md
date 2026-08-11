# ggumirror iOS

## Source of Truth

작업 전에 필요한 범위에서 아래 문서를 확인한다.

- docs/PRODUCT.md
- docs/DESIGN.md
- docs/IMPLEMENTATION_PLAN.md
- docs/MIRROR_CREATOR_TEMPLATE_GUIDE.md

문서와 오래된 코드/주석이 충돌하면 최신 PRODUCT/DESIGN decision을 우선한다.

## Current Architecture

- native SwiftUI
- Mirror-first launch
- startup login 없음
- Free Canvas Editor
- 과거 4면 Side Editing 폐기
- local persistence schema v2
- Store hand-drawn artwork 24/24
- Publish Draft는 실제 Store listing이 아님

## Fixed Mirror Geometry

Master Canvas:

1080 × 2340

Insets:

| side | value |
|---|---|
| left | 108 |
| right | 108 |
| top | 180 |
| bottom | 220 |

Camera Area:

864 × 1940

이 geometry는

- Editor
- Preview
- Home
- Store
- My Mirrors
- Runtime Mirror
- Capture
- External guide

에서 공유한다.

임의 변경 금지.

## Camera Policy

- front camera
- mirrored
- portrait
- no user zoom
- videoZoomFactor = 1
- Camera framing 문제를 해결하기 위해 Mirror frame geometry를 변경하지 않는다

## Editor Policy

Free Canvas.

Drawing / Sticker / Photo Sticker / Text는 Camera Area를 포함한 전체 canvas에서 사용 가능.

External Artwork만 frame-only.

Drawing:

- Draw mode
- Hand/Pan mode

지원.

Sticker / Photo Sticker / Text:

| 입력 | 동작 |
|---|---|
| object drag | object 이동 |
| empty canvas drag | viewport pan |
| two-finger navigation | viewport pan |
| pinch | viewport zoom |

zoom range: 1...4

## Visual System

- Warm Paper
- Ink
- uneven stable borders
- Gaegu brand typography

앱 UI font는 InkFont semantic token을 사용한다.

Mirror Decoration Text는 별도 multi-font library를 사용한다.

## Store

production Store artwork는 실제 hand-drawn PNG 24개.

placeholder Store content를 다시 추가하지 않는다.

Store browse 자체는 로그인 없이 가능.

현재 유료 CTA는 실제 server purchase가 아니다.

## Publish

Publish Draft는 local preparation이다.

Draft 저장 성공을 실제 Store 공개 등록 성공처럼 표현하지 않는다.

Actual Publish는 Backend phase 이후 구현한다.

## Persistence Safety

Auth/login/logout 작업 때문에 다음 데이터를 삭제하지 않는다:

- MirrorLibrary
- current mirror
- Photo Sticker assets
- Imported Artwork assets
- Publish Drafts
- locally acquired mirrors

## Infrastructure Isolation (영구 규칙)

DailyOPIc(`opicmobile-45cd5`)은 **실제 사용자가 있는 LIVE production**이고
꾸미러 작업에서 **완전히 OUT OF SCOPE**다. 자세한 규칙은 workspace root CLAUDE.md 참고.

Client 쪽에서 지킬 것:

- 서버 주소는 `BackendEnvironment` **한 곳**에만 둔다.
  현재 production: https://ggumirror-api-cmyv4amroa-du.a.run.app (`ggumirror-prod` project)
- **client에 GCP project id · Firestore database · service account 정보를 넣지 않는다.**
  client가 아는 것은 API 주소 하나뿐이다.
- Apple 관련 resource는 꾸미러 전용을 쓴다 — Bundle ID `com.mark77234.ggumirror`,
  꾸미러 App Store Connect app, 꾸미러 StoreKit product.
  **DailyOPIc의 product identifier / RevenueCat mapping을 재사용하지 않는다.**
- AdMob도 꾸미러 전용 app / ad unit을 만든다.
- Firebase Client SDK는 **넣지 않는다.** 현재 구조는 iOS → Cloud Run → Firestore Admin이라
  필요가 없다. FCM · App Check처럼 실제 제품 요구가 생길 때만 검토하고,
  그때도 DailyOPIc Firebase project를 재사용하지 않는다.
- RevenueCat SDK는 IAP Phase까지 추가하지 않는다. 추가할 때도 꾸미러 전용 project를 만들고,
  **구매 성공을 그대로 조각 잔액으로 신뢰하지 않는다** — 잔액 권위는 server ledger다.

## Lock Screen Quick Mirror (C-1) — 지켜야 하는 제약

Locked Camera Capture Extension은 Apple sandbox 때문에
**network · App Group shared container · app shared preferences에 접근할 수 없다.**

따라서:

- **C-1 때문에 Mirror / Sticker persistence 위치를 바꾸지 않는다.**
  `Application Support/ggumirror` 그대로 유지하고, App Group을 추가하지 않는다
- extension은 backend를 부르지 않는다
- 앱 ↔ widget ↔ extension 상태는 `CameraCaptureIntent.AppContext`(**JSON 4KB 이하**)로만.
  PNG · 사진 스티커 · MirrorDesign 전체 같은 큰 데이터를 여기에 넣지 않는다
- 촬영 결과는 `LockedCameraCaptureSession.sessionContentURL`에 쓰고,
  본앱이 `LockedCameraCaptureManager`로 수거한다

자세한 계획은 docs/IMPLEMENTATION_PLAN.md의 C-1 Prep 참고.

## Git / Verification

기능 완료 후 commit 전:

- build
- tests
- relevant regression tests

를 실행한다.

Client 변경은 Client repository에서만 commit한다.
