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

- 본앱 Mirror: **front ↔ rear 전환 가능**. 시작은 언제나 front
- front는 mirrored, rear는 **mirrored 아님**
- 잠금화면 Quick Mirror: **front 고정** (전환 없음)
- portrait
- no user zoom
- videoZoomFactor = 1
- rear도 **일반 1x wide 하나만** 쓴다 (ultra-wide / tele 선택 없음)
- Camera framing 문제를 해결하기 위해 Mirror frame geometry를 변경하지 않는다

## 전/후면 전환 + 플래시 (C-2B)

`MirrorCamera`는 본앱과 잠금화면 extension이 **공유한다.** 그래서 능력을 role로 나눈다:

| role | 쓰는 곳 | 전환 | photo output | flash |
|---|---|---|---|---|
| `.viewfinder` (**기본값**) | 잠금화면 `GgumirrorCapture` | 없음 | 없음 | 없음 |
| `.mirror` | 본앱 `MirrorView` | 있음 | 있음 | 있음 |

**기본값이 `.viewfinder`라서 본앱 기능을 추가해도 extension 동작이 따라 바뀌지 않는다.**
extension은 계속 `MirrorCamera()`를 쓰고 `currentFrame()` → `QuickMirrorComposer` 경로다.

전환:

- `position`(UI용)은 **성공한 전환만** 반영한다. 화면은 rear인데 실제로는 front인 상태를 만들지 않는다
- 세션 변경은 전부 `sessionQueue`에서만 일어난다 — retry(`start()`)와 자연히 직렬화된다.
  별도 lock을 만들지 않았다
- 전환 실패 시 **원래 input을 되돌려 붙인다.** 되돌리기도 실패하면 세션을 비우고
  `isConfigured = false`로 두어 다음 `start()`가 처음부터 구성한다
- 반전 / 회전은 `applyConnections(for:)` **한 곳**에서만 건다.
  input을 갈아 끼우면 connection이 새로 생기므로 매번 다시 걸어야 한다
- **`session.outputs`가 아니라 `session.connections`를 돈다.**
  preview layer의 connection은 output이 아니라 세션이 직접 들고 있는 것이라
  `outputs`만 돌면 영원히 갱신되지 않는 자리가 생긴다 —
  rear → front에서 화면이 180° 뒤집혀 보이던 원인이 정확히 이것이었다
- `CameraPreviewView`는 **반전/회전을 스스로 정하지 않는다.** 붙은 직후
  `camera.applyCurrentConnectionPolicy()`만 부른다. 소유자가 둘이면 반드시 어긋난다
- `automaticallyAdjustsVideoMirroring`은 항상 끈다.
  켜 두면 input이 바뀔 때 system이 `isVideoMirrored`를 임의로 되돌린다
- 회전 각은 **상수 하나**다. 전면/후면에 다른 숫자를 쓰지 않는다 —
  같은 90도가 두 카메라 모두에서 정방향이라는 것이 실기기로 확인됐다
- `.unavailable` 재시도 / `.denied` 최종 정책은 그대로다 (C-1A latch 회귀 금지)
- 후면 선택을 **저장하지 않는다.** 앱을 다시 켜면 front다

플래시:

- 상태는 **OFF / ON 둘뿐**이다. AUTO 없음, torch 없음
- **preview 중에 켜두지 않는다.** 촬영하는 순간에만 동작한다
- `AVCapturePhotoOutput` + `AVCapturePhotoSettings.flashMode`를 쓴다.
  deprecated `AVCaptureDevice.flashMode`를 쓰지 않는다
- settings는 **촬영마다 새로 만든다.** 재사용하면 AVFoundation이 예외를 던진다
- `supportedFlashModes`에 없는 mode를 요청하지 않는다 (`MirrorCamera.flashMode(wantsFlash:supported:)`)
- 공식 flash가 없으면(전면 Retina Flash 미지원 기기) **화면 flash**로 대신한다.
  흰 화면 + 밝기 최대 → 220ms 안정화 → 촬영 → 즉시 복원.
  overlay만 깜빡이고 이전 프레임을 저장하는 가짜가 되면 안 된다
- 밝기는 성공 · 실패 · 취소 · 백그라운드 · 화면 이탈 **어느 경로에서도** 되돌린다
- 흰 화면은 **저장되는 사진에 들어가지 않는다** — 사진은 화면 스냅샷이 아니라
  카메라 사진 + 장식을 따로 합성한다
- flash를 못 써도 촬영은 계속된다. 사용자가 사진을 못 찍게 만들지 않는다
- 앱을 다시 켜면 OFF다. 저장하지 않는다

촬영 요청은 **시작 시점의 position / flash 의도를 고정**한다. 촬영 중 토글해도 그 사진은 바뀌지 않고,
촬영 중에는 전환 버튼이 비활성이며 중복 촬영도 막는다.

`ggumirrorTests/CameraSwitchFlashTests.swift`가 위 전부를 고정한다.


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

## 내 콘텐츠 내보내기 (D-1)

- 내보내기는 **`MirrorRenderer`를 재사용한다.** 화면 스크린샷을 찍지 않는다
- 거울은 **1080 × 2340**(`MirrorCanvas.size`), 스티커는 `StickerRenderer` 규칙을 따른다.
  export가 자기만의 해상도를 정하지 않는다
- **PNG만 쓴다.** JPEG로 바꾸면 스티커 투명도가 사라진다
- `OwnContentExportPolicy`가 유일한 관문이다 — 거울은 `origin == .made`만.
  `MirrorPublishPolicy`를 재사용하지 않는다(다른 질문이라 따로 둔다)
- 상점 스티커를 프로젝트로 들여오는 경로가 생기면 **그 정책 함수에 조건을 추가한다**
- 사진 저장은 **add-only** 권한만. `NSPhotoLibraryUsageDescription`(읽기)을 추가하지 않는다
- 임시 파일은 `temporaryDirectory`에만 쓰고 공유 후 지운다.
  Application Support의 사용자 원본과 섞지 않는다
- 내보내기 코드에 `print` · `Logger`를 넣지 않는다 — 경로와 콘텐츠가 새어 나간다

`ggumirrorTests/OwnContentExportTests.swift`가 위 전부를 고정한다.

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

## 투명 프레임 + 편집 guide (C-2A)

프레임을 **완전히 투명하게** 만들 수 있다. 그리고 편집 guide는 Editor 밖으로 나가지 않는다.

투명 프레임:

- `MirrorStyle.isFrameVisible`(기본 `true`)이 유일한 표현이다.
  **`frame`을 `Color.clear`로 바꾸지 않는다** — 색을 지우면 고르던 색을 잃고,
  렌더러마다 "clear인가" 비교하는 magic value가 생긴다
- 렌더러는 `frame`이 아니라 **`style.frameFill`**(투명이면 `nil`) 하나만 본다.
  투명 판단이 한 곳에만 있어야 Mirror · Capture · 미리보기가 어긋나지 않는다
- 투명이면 프레임 밴드를 **아예 그리지 않는다** — paper grain도 같이 빠진다.
  색만 빼고 결을 남기면 카메라 위에 점이 흩뿌려진 것처럼 보인다
- 저장 key는 `frameVisible`이고 **없으면 `true`로 읽는다.**
  C-2A 이전에 저장된 거울이 업데이트 후 무프레임이 되면 안 된다. migration script는 없다
- geometry는 그대로다 — 1080 × 2340 · insets · 장식 좌표 하나도 움직이지 않는다
- 상점 9번째 기본 거울로 추가하지 않았다. **프레임 편집 option**이다
- 잠금화면은 이미 있던 `QuickMirrorPresetID.none`으로 간다.
  `transparent` case를 새로 만들지 않는다 (preset은 여전히 9개)

편집 guide(카메라 영역 점선):

- `MirrorCanvasView.showsCameraGuide`가 유일한 통로이고 **기본이 `false`**다.
  `true`로 켜는 곳은 `Editor/MirrorEditorCanvas.swift` **한 곳뿐**이다
- 실제 Mirror와 Capture는 `MirrorDecorationView`를 쓴다 — 이 view에는
  guide를 켤 인자가 **없다.** 그래서 새어 나갈 구조 자체가 아니다
- 저장된 PNG · 잠금화면 Quick Mirror · 상점/홈 미리보기에도 나오지 않는다
- 점선 굵기 · 색 · 간격은 재설계하지 않았다

`ggumirrorTests/TransparentFrameTests.swift`가 위 전부를 고정한다
(렌더 픽셀 비교 + guide를 켜는 파일 목록 검사).

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

### 출석 (B-4) — 하루의 기준도 서버가 정한다

하루 한 번 출석하면 조각 **+1**. 잔액과 마찬가지로 **날짜도 client 권위가 아니다.**

- 하루의 기준은 **server의 Asia/Seoul 날짜**다. client는 `Date()` · `Calendar` ·
  `DateFormatter` · `TimeZone` · `UserDefaults`로 "오늘 받았는지"를 판단하지 않는다.
  기기 시계를 바꾸거나 앱을 지웠다 깔아도 결과가 같다
- 통로는 `GET /users/me/attendance`와 `POST /users/me/attendance` 둘뿐이고,
  **POST에 body를 싣지 않는다** — userId · date · amount · reason을 만드는 자리가 없다
- `ShardWallet.claimAttendance(session:)`는 응답의 `balance`를 **그대로 대입**한다.
  `balance += 1` 같은 낙관적 증가는 하지 않는다. 실패하면 아무 것도 바꾸지 않는다
- 서버 응답의 `claimed` 뜻:
  **`true` = 이 요청이 지급했다**, **`false` = 이미 지급돼 이 요청은 지급하지 않았다**
- **`claimed=false`는 실패가 아니다.** 정상 HTTP 응답이면 오류 화면을 띄우지 않고
  "오늘 출석 완료"로 간다. client에는 출석 실패를 표시할 상태 자체가 없다 —
  실패는 조용히 아무 일도 하지 않는 것이다
- 두 경우 모두 `balance`는 **서버가 준 값**을 쓴다. `reward=0`이라고 0으로 되돌리지 않는다.
  그래서 응답을 못 받고 다시 눌러도 잔액이 부풀지 않고 오히려 제자리를 찾는다
- `isClaiming`은 **표시용 guard**다. 보안 경계가 아니다 —
  서버 API를 직접 반복 호출해도 +1은 정확히 한 번이다(원장 idempotency)
- 로그아웃하면 출석 표시도 `.unknown`으로 지운다. 다음 사람에게 물려주지 않는다
- 로그인하지 않은 사용자가 CTA를 누르면 **설정의 기존 Apple 로그인**으로 간다.
  홈에 새 로그인 UI를 만들지 않는다. Mirror · 촬영 · 꾸미기 앞에는 여전히 로그인 벽이 없다
- 다시 읽는 시점은 **view 진입 · scene active 복귀 · 로그인 상태 변화**뿐이다.
  Timer로 서버를 주기적으로 두드리지 않는다. 앱을 켜 둔 채 KST 자정을 넘겨도
  다시 활성화될 때 서버가 새 날짜를 알려준다
- streak · 7일 보너스 · 달력 · 알림은 **없다**

`ggumirrorTests/DailyAttendanceTests.swift`가 위 규칙을 고정한다.

### AdMob Rewarded (B-5) — client는 지급하지 않는다

광고 1회 → 조각 **+1**, 하루 **5회**(Asia/Seoul). 전부 서버가 정한다.

`onUserEarnedReward`로 조각을 주지 않는다. 그 callback은 "광고 UX가 끝났다"는 뜻이고,
실제 지급은 **Google SSV callback을 검증한 server**만 한다.
광고 시청 후 client가 할 일은 **서버 값을 다시 읽는 것** 하나다.

- `Ads/RewardedAds.swift`에 **잔액을 만질 방법 자체가 없다.** `ShardWallet`을 받지만
  쓰는 것은 `refresh(session:)`뿐이다. `RewardedAdTests`가 소스 레벨로 고정한다
- 오늘 몇 번 봤는지는 **서버가 센다**(`shards.rewardedToday`). 앱이 세지 않는다 —
  광고를 봤다고 보상이 확정되는 것도 아니다
- 광고에 실어 보내는 것은 서버가 발급한 **short-lived opaque context**뿐이다.
  session token · Apple token · 내부 user id를 넣지 않는다 — callback URL은 로그에 남는다
- 광고가 끝나면 상태는 **`.verifying`("보상을 확인하고 있어요")**이지 "+1 받았다"가 아니다
- SSV는 client와 별개 경로라 도착 시점을 알 수 없다. **무한 polling 금지** —
  즉시 · 1초 · 2초 · 4초 네 번만 확인하고, 오면 즉시 멈춘다.
  못 받으면 그대로 두고 다음 새로고침(scene 복귀 등)이 가져간다. **가짜 +1 금지**
- 중간에 닫으면(`.dismissed`) 확인을 시작조차 하지 않는다
- 로그아웃하면 광고 횟수 표시도 지운다

#### Privacy manifest

`ggumirror/PrivacyInfo.xcprivacy`가 **본앱 target**에 있다(빌드하면 `.app` 루트에 들어간다).

**우리 앱 코드가 실제로 쓰는 Required Reason API만** 선언한다:

| category | reason | 어디서 |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | `@AppStorage` 4개 (프로필 이름 · 태그 · 알림 · 편집 힌트) |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` | `MirrorEditorCanvas`의 햅틱 rate limiter (`ProcessInfo.systemUptime`) |

- App Group을 쓰지 않으므로 UserDefaults reason은 **`CA92.1`이고 `1C8F.1`이 아니다**
- `NSPrivacyTracking = false`. ATT를 도입하지 않았고 IDFA도 읽지 않는다
- `NSPrivacyCollectedDataTypes`는 **비어 있다.** 근거 없이 수집 항목을 지어내지 않는다
- **Google SDK의 manifest는 각 framework가 따로 들고 온다**
  (`Frameworks/GoogleMobileAds.framework/PrivacyInfo.xcprivacy` ·
  `.../UserMessagingPlatform.framework/...`). 그 내용을 우리 manifest에 베껴 오지 않고,
  우리 manifest가 그것을 대신하지도 않는다
- **extension 둘에는 manifest를 만들지 않았다.** 코드에도 빌드된 바이너리에도
  Required Reason API가 없다(`nm -u`로 0개 확인). 필요 없는 파일을 넣지 않는다
- 이 파일과 **App Store Connect 개인정보 설문(Nutrition Label)은 다른 것**이다.
  이 파일은 "왜 이 API를 부르는가", 설문은 "어떤 데이터를 수집하는가"다.
  설문은 출시 checklist에서 따로 답한다 (광고 SDK 수집 항목 포함)

`ggumirrorTests/AppConfigTests.swift`가 **빌드된 bundle을 읽어** 고정한다 —
repo 파일이 아니라 결과물을 본다.

#### Google Mobile Ads / UMP SDK (B-5C)

SPM 하나만 붙인다: `swift-package-manager-google-mobile-ads` (13.7.0, Up to Next Major).
**product는 `GoogleMobileAds` 하나뿐**이고 UMP(`GoogleUserMessagingPlatform` 3.1.0)는
그 package의 dependency로 따라온다 — UMP를 따로 추가하지 않는다.

- **앱 target에만 link한다.** `GgumirrorCapture` · `GgumirrorControls`에는 붙이지 않는다.
  잠금화면 extension에 광고 framework를 끌고 들어가면 기동이 느려지고,
  `GADApplicationIdentifier`가 없어 죽을 수도 있다.
  빌드 산출물에서 `otool -L`로 확인했다 — extension 둘 다 광고 SDK가 없다
- **SDK에 닿는 파일은 `ggumirror/Ads/GoogleAds.swift` 하나다.** 나머지
  (`RewardedAds.swift` · `AdsConsent.swift` · Home · Settings · RootView)는
  protocol만 알고 SDK 타입을 모른다. 그래서 광고 흐름 전체를 SDK 없이 테스트한다.
  `RewardedAdTests.sdkIsIsolatedToOneFile`이 고정한다
- Swift API 이름은 **설치된 header에서 직접 확인했다**(`NS_SWIFT_NAME`) —
  `MobileAds.shared.start` · `RewardedAd.load(with:request:)` ·
  `ServerSideVerificationOptions.customRewardText` ·
  `ConsentInformation.shared.canRequestAds` · `ConsentForm.loadAndPresentIfRequired(from:)`

#### UMP 동의

- 앱 실행마다 `requestConsentInfoUpdate` → 필요하면 양식 표시 → `canRequestAds` 확인
- **`canRequestAds`가 true가 되기 전에는 광고를 load하지도 present하지도 않는다**
- `MobileAds.start()`는 **정확히 한 번**이다. "이미 동의가 있는 경우"와 "방금 받은 경우"가
  같은 경로로 들어오므로 `hasStartedMobileAds` 하나로 막는다. 상태 기계를 만들지 않았다
- 동의 확인은 **RootView `.task`의 맨 마지막**이다. 거울이 이미 화면에 뜬 뒤에 돈다 —
  실행하자마자 동의창이 뜨는 앱이 되지 않는다
- `privacyOptionsRequirementStatus == .required`일 때만 설정에
  "광고 개인정보 설정"이 보인다. 새 화면을 만들지 않고 Google 양식을 그대로 띄운다
- **ATT는 도입하지 않았다.** `NSUserTrackingUsageDescription`도 넣지 않았다.
  UMP 규제 동의를 먼저 안정화하고, IDFA는 별도 phase에서 판단한다.
  ATT가 없어도 광고 요청은 정상 동작한다(비개인화 광고로 나간다)

#### ad unit 설정

| | Debug | Release |
|---|---|---|
| `ADMOB_APP_ID` | 꾸미러 production | 꾸미러 production (**같다**) |
| `ADMOB_REWARDED_AD_UNIT_ID` | Google 공식 test unit | 꾸미러 production unit |

**App ID는 두 환경이 같다.** 광고를 안전하게 만드는 것은 App ID가 아니라 ad unit이고,
App ID를 sample 값으로 바꾸면 **UMP가 남의 app 설정으로 동의 메시지를 조회**해
우리 동의 흐름을 실기기에서 확인할 수 없다(UMP 메시지는 AdMob console에서 app 단위 설정).

`SKAdNetworkItems`는 Google 공식 quick-start의 현재 목록 50개를 그대로 넣었다.
블로그 복사본을 쓰지 않는다.

`ADMOB_REWARDED_AD_UNIT_ID`는 `Config/*.xcconfig` → `Info.plist` → `AppConfig`로 온다.
이름의 `_ID`는 **광고를 load할 때 쓰는 값**이라는 뜻이다 — backend의
`ADMOB_SSV_EXPECTED_AD_UNIT`(SSV callback의 `ad_unit`과 비교할 값)과 **다른 것**이고,
둘이 같은 문자열이라고 가정하지 않는다. 실제 callback을 한 번 받아봐야 확정된다.

| | 값 |
|---|---|
| Debug | Google 공식 **test** rewarded unit |
| Release | **비어 있다** — 꾸미러 전용 ad unit이 아직 없다 |

- **Release에 test ad unit을 넣지 않는다.** 실제 사용자에게 test 광고가 나가면 정책 위반이다
- 비어 있으면 `AppConfig.admobRewardedAdUnit`이 `nil`이고 **광고 CTA를 아예 보여주지 않는다.**
  광고는 부가 기능이라 없다고 앱을 멈추지 않는다(다른 설정과 다른 점)
- production에서 test unit이 들어와도 `parseAdUnit`이 무시한다 — 마지막 방어선
- `RewardedAdTests`가 Debug/Release 설정을 고정한다

#### Google Mobile Ads SDK는 아직 없다

꾸미러 전용 AdMob app / ad unit이 만들어지기 전이라 붙일 ID가 없고,
**추측한 ID를 넣지 않는다.** 대신 경계(`RewardedAdPresenting`)를 먼저 뒀다 —
SDK가 들어오면 그 protocol 구현 하나만 추가하면 되고 나머지 흐름과 테스트는 그대로다.
UMP consent flow도 SDK와 함께 들어온다.

#### 광고 정책

- **Rewarded만.** interstitial · app-open · banner를 넣지 않는다
- Mirror Camera 시작 화면에 강제 광고를 붙이지 않는다.
  광고는 사용자가 **CTA를 명시적으로 눌렀을 때만** 뜬다
- 광고 보상은 server economy라 로그인이 필요하다. 로그인 전 CTA는
  **설정의 기존 Apple 로그인**으로 보낸다. Mirror core에는 여전히 로그인 벽이 없다

## Build Number Parity (영구 규칙)

본앱과 embed되는 extension **셋의 버전이 항상 같아야 한다.**

| target | bundle id |
|---|---|
| 본앱 | `com.mark77234.ggumirror` |
| 잠금화면 촬영 | `com.mark77234.ggumirror.capture` |
| Control | `com.mark77234.ggumirror.controls` |

`CURRENT_PROJECT_VERSION`(CFBundleVersion)과 `MARKETING_VERSION`
(CFBundleShortVersionString)을 **Debug · Release 모두** 같은 값으로 맞춘다.
다르면 빌드 warning이 나고 **App Store 검증에서 막힌다.**

버전을 올릴 때 본앱만 올리면 이 규칙이 깨진다 — 실제로 1.0.3 bump에서 extension이
1.0.2 / build 3에 남아 warning이 생겼다. 현재는 셋 다 **1.0.3 / build 4**다.

test target(`ggumirrorTests` · `ggumirrorUITests`)은 앱에 embed되지 않으므로
이 규칙에서 제외한다.

`ggumirrorTests/AppConfigTests.swift::extensionsMatchTheApp`이 고정한다 —
pbxproj를 build configuration 블록 단위로 읽고 **bundle id를 열쇠로** 비교하므로
줄 번호나 target 순서가 바뀌어도 견딘다.

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
