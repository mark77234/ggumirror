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

C-1A 구현 확정 사실:

- capture extension point는 **`com.apple.securecapture`**다 (공식 template 값).
  추론했던 `com.apple.LockedCameraCapture`는 틀렸다 — 다시 쓰지 않는다
- **전용 entitlement가 없다.** 공식 template도 만들지 않고, 서명에는 base만 들어간다
- target 2개: `GgumirrorCapture`(`…ggumirror.capture`) · `GgumirrorControls`(`…ggumirror.controls`)
- extension에는 카메라 파일 2개 + activity + capture store만 공유한다.
  `Backend/` · `Auth/` · `Store/` · `Editor/`는 절대 넣지 않는다
- extension `CURRENT_PROJECT_VERSION`은 본앱과 같아야 한다 (다르면 App Store 검증에서 막힌다)
- **하드웨어 촬영 버튼 처리는 필수다.** `.onCameraCaptureEvent`(AVKit)를 viewfinder에 붙인다.
  없으면 extension이 실행 직후 종료될 수 있다. **`.ended` phase에서만** 찍어
  한 번 누르면 한 장이 되게 한다. 화면 버튼과 같은 `capture()`를 쓴다

C-1B 확정 사실:

- Quick Mirror 프레임은 **내장 preset만**이다. `QuickMirrorPresetID`는 상점 기본 거울 8종과
  1:1이고 색·비율이 같다(테스트가 비교한다)
- 매핑 기준은 **프레임 색 하나**다. 장식이 있어도 표현 가능한 색은 그대로 지키고,
  표현할 수 없는 색일 때만 기본값으로 간다. 장식(사진·스티커·그림·텍스트)은 그리지 않는다
- extension에 넘기는 것은 `CameraCaptureIntent.AppContext`의 **작은 설정 하나**뿐이다
  (schemaVersion + presetID). PNG · 사진 · 스티커 · 그림 · 인증 정보를 넣지 않는다
- context가 없거나 못 읽으면 **기본 preset**으로 떨어진다.
  프레임 실패가 카메라를 못 띄우는 이유가 되면 안 된다
- 촬영 결과는 **카메라 + 같은 프레임**만 합친다. 화면 스냅샷을 쓰지 않는다(버튼이 찍힌다)
- `MirrorCamera`: 구성 실패를 영구히 굳히지 않는다. `.unavailable`은 재시도 가능,
  `.denied`만 최종이다. 이 latch가 잠금화면 간헐 검은 화면의 원인이었다

자세한 내용은 docs/IMPLEMENTATION_PLAN.md의 C-1B / C-1A / C-1 Prep 참고.

## 거울조각 (B-3) — client는 권위가 아니다

조각 잔액의 진실은 **server ledger 하나**다. client는 서버 값을 보여주기만 한다.

- `ShardWallet`(`Shared/ShardWallet.swift`)에 잔액을 바꾸는 함수가 **없다.**
  `balance += 1` · `balance -= 20` · `setBalance` 같은 것을 만들지 않는다.
  `balance`는 `private(set)`이고, 값이 바뀌는 유일한 경로는 `refresh(session:)`의 서버 응답이다
- `ShardBackend` protocol에는 **읽기 하나**(`shards(accessToken:)`)뿐이다.
  `BackendClient`도 `GET users/me/shards`만 부른다.
  `POST /shards/credit` 같은 요청을 client에서 만들지 않는다
- 서버가 새 잔액을 주면 **그것이 최종**이다(server wins). 로컬 값을 우선하지 않는다
- 서버에 닿지 못하면 마지막으로 본 값을 유지한다. 임의로 0으로 만들지 않는다 —
  "조각이 사라졌다"처럼 보인다
- 로그아웃은 **화면 표시만** 지운다. 서버 지갑은 그대로 있고 다시 로그인하면 돌아온다
- 로그인 전 잔액은 0이고 서버를 부르지 않는다. **조각 때문에 로그인 벽을 세우지 않는다** —
  거울 · 촬영 · 꾸미기 · 내 거울 · 상점 구경은 그대로 로그인 없이 쓴다
- 하드코딩 잔액(`ShardWallet.temporaryBalance = 32`)은 **삭제됐다.** 다시 만들지 않는다
- 로컬에 남아 있던 임시 잔액을 서버로 옮기지 않는다. 마이그레이션 자체가 없다

`ggumirrorTests/ShardWalletTests.swift`가 위 규칙을 소스 레벨로 고정한다.

### AdMob Rewarded (B-5) — client는 지급하지 않는다

`onUserEarnedReward`로 조각을 주지 않는다. 그 callback은 UI 갱신용이고,
실제 지급은 **Google SSV callback을 검증한 server**만 한다.
광고 시청 후 client가 할 일은 `shards.refresh(session:)` 하나다.

## Build Configuration (현재 정책)

서버 주소는 **코드에 없다.** `Config/*.xcconfig` → `Config/Info.plist` → `AppConfig`로 온다.
Swift에서 쓰는 곳은 `AppConfig.backendBaseURL` 한 곳뿐이고,
`BackendClient`는 Bundle을 직접 읽지 않는다.

| | APP_ENV | BACKEND_BASE_URL |
|---|---|---|
| Debug | `development` | 꾸미러 production API |
| Release | `production` | 꾸미러 production API |

**현재는 Debug도 production API를 쓴다.** 실기기 Debug 빌드로 실제 Apple 로그인을
디버깅하기 위한 정책이다 — Xcode console에서 `[Auth]` / `[Backend]` 로그를 보면서
실제 서버 응답을 확인할 수 있다. `127.0.0.1`은 실기기에서 iPhone 자신을 가리켜 쓸 수 없다.

로컬 backend가 필요해지면 `Config/Local.xcconfig`(gitignored)로 **Debug만** override한다.
`Config/Local.xcconfig.example`가 예시다. Release는 이 파일을 읽지 않는다.

`Config/Base.xcconfig` · `Debug.xcconfig` · `Release.xcconfig` · `Info.plist`는 **추적한다** —
fresh clone에서 그대로 빌드돼야 한다. Cloud Run public URL은 secret이 아니다.

client build config에 넣어도 되는 것: `APP_ENV` · `BACKEND_BASE_URL` ·
(향후) public SDK key. **넣지 않는 것**: GCP project id · Firestore 정보 ·
service account · private key · client secret · token · nonce.
앱 bundle에 들어가는 값은 secret이 될 수 없다.

`[Backend]` 로그는 `[Auth]`와 같은 규칙이다 — DEBUG 빌드에만, **분류와 status만.**
요청/응답 본문 · token · nonce · 식별자 · 이메일은 찍지 않는다.

## Git / Verification

기능 완료 후 commit 전:

- build
- tests
- relevant regression tests

를 실행한다.

Client 변경은 Client repository에서만 commit한다.
