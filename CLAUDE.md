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
- 본앱 Mirror는 **0.5x / 1x / 2x preset + pinch**를 지원한다 (아래 참고).
  잠금화면 Quick Mirror(`.viewfinder`)는 여전히 **1x 고정**이다
- 시작 배율은 언제나 **1x**이고 저장하지 않는다
- **전면에는 framing 선택(`넓게` / `채우기`)이 있고 기본값은 `채우기`다** (아래 참고).
  후면은 언제나 화면을 꽉 채운다
- Camera framing 문제를 해결하기 위해 Mirror frame geometry를 변경하지 않는다

## 전면 Framing — 넓게 보기 / 화면 채우기

**배율이 아니다.** 센서가 준 그림을 세로로 긴 화면에 **어떻게 놓을 것인가**의 문제다.
어느 쪽을 골라도 기기 zoom factor는 그대로다.

### 왜 필요한가 (root cause)

전면 센서는 4:3에 가깝고 화면은 9:19.5쯤이다. `.resizeAspectFill`로 꽉 채우면
**좌우가 크게 잘려서** 기본 카메라 앱보다 얼굴이 훨씬 크게 보였다.
잘라낸 화각은 software로 되돌릴 수 없다 — 그래서 **자르지 않는 선택지**를 준다.

| | |
|---|---|
| `넓게` (`.wide`) | 센서 화각을 하나도 자르지 않는다. 위아래가 남는다 |
| `채우기` (`.fill`, **기본값**) | 화면을 꽉 채운다. 좌우가 잘린다 |

**기본값은 실기기 QA에서 `넓게` → `채우기`로 바뀌었다.** 넓게는 위아래에 검은 자리가
남아서, 거울을 처음 연 사람에게는 화면이 비어 보였다. 화각을 지키는 선택지는 그대로
있고 기본값만 옮겼다 — 없앤 기능이 아니다.

### crop이 걸리는 자리는 딱 두 곳이고 짝을 이룬다

| | `넓게` | `채우기` |
|---|---|---|
| preview (`AVCaptureVideoPreviewLayer`) | `.resizeAspect` | `.resizeAspectFill` |
| 저장 (`MirrorCapture.compose`) | `scaledToFit()` | `scaledToFill()` |

**둘이 갈라지면 "화면에서 본 것과 사진이 다르다"가 된다.** `MirrorView`가 같은
`camera.framing` 하나를 두 곳에 넘기고, 촬영 시작 순간의 값을 고정한다(플래시 의도와 같은 규칙).

넓게 보기에서 위아래에 남는 검은 자리는 **사진에도 그대로 들어간다.** 거울 장식이
전체 화면 기준 확정 geometry(1080 × 2340)라, 사진만 카메라 띠에 맞춰 자르면 장식이 잘린다.

### 비율을 코드에 적지 않는다

`4:3`도 `0.75`도 어디에도 없다. `activeFormat`이 실제로 주는 크기를 읽어
`sourceAspectRatio`로 둔다. 화면에 놓는 일은 layer의 `videoGravity`와 SwiftUI의
`scaledToFit/Fill`이 하므로 **우리가 확대·축소 계산을 하지 않는다** —
가짜 화각이 생길 구조가 아니다.

`visibleSourceFraction(source:viewport:framing:)`이 "얼마나 남는가"를 돌려주는
순수 함수다. 기기 없이 "넓게가 채우기보다 덜 자른다"를 시험한다.

### 범위

- **전면에서만** 고를 수 있다(`canChooseFraming`). 후면 UX는 그대로다 —
  `framing`은 `position == .front ? frontFraming : .fill`
- **사용자가 고른 값은 앱을 다시 켜도 남는다**(`UserDefaults` · `ggumirror.camera.frontFraming`).
  `setFrontFraming`이 유일한 쓰기 자리다. 후면에 갔다 전면으로 돌아와도 살아 있다
- **기본값은 미리 적어 두지 않는다.** 시작할 때는 읽기만 한다 — 적어 두면 나중에
  기본값을 바꿔도 그 사용자는 "이미 고른 사람"으로 취급돼 따라오지 못한다.
  모르는 값이 저장돼 있으면 기본값으로 떨어진다
- 미리보기(`MirrorLivePreviewView`)는 여전히 **저장하지 않는다** — 자기 카메라
  인스턴스를 갖고 `setFrontFraming`을 부르지 않는다. 상점에서 고른 것이 홈 거울을 바꾸지 않는다
- 잠금화면 `.viewfinder`는 role guard에 막혀 언제나 예전 동작(`fill`)이다.
  `compose(framing:)` 기본값도 `.fill`이라 모르는 호출부는 그대로 동작한다

### UI

배율 칩 **왼쪽에 따로 묶어** 둔다 — 같은 캡슐에 섞으면 넓게 보기가 배율처럼 읽힌다.
사용자에게 `4:3` · `16:9`를 고르게 하지 않는다. 글자는 `넓게` · `채우기`,
낭독기는 `넓게 보기` · `화면 채우기`. tap target은 배율 칩과 같은 **44pt**이고
같은 auto-hide 타이머를 쓴다.

`ggumirrorTests/FrontFramingTests.swift`가 위 전부를 고정한다.

## Mirror Camera 배율 (Zoom)

**사용자가 보는 배율(logical)과 기기가 쓰는 배율(device factor)은 다르다.**

ultra-wide를 품은 virtual 카메라에서 `videoZoomFactor == 1`은 1x가 아니라 **0.5x**다.
이걸 모르고 `videoZoomFactor = 0.5`를 쓰면 어느 기기에서도 실패하고
(`minAvailableVideoZoomFactor`가 1이다), `= 1`을 쓰면 0.5x 화면을 1x라고 표시한다.

| | |
|---|---|
| 변환 | `device = logical × baseFactor` |
| `baseFactor` | 첫 렌즈가 ultra-wide면 **첫 전환 지점**(보통 2), 아니면 1 |
| 출처 | `constituentDevices` · `virtualDeviceSwitchOverVideoZoomFactors` |

`MirrorCamera.ZoomCapability`가 변환·clamp를 전부 들고 있고 **순수 값**이라
기기 없이 시험한다. `baseZoomFactor` · `zoomPresets` · `selectedPreset`도 순수 함수다.

### 렌즈 선택

- **전면은 언제나 물리 wide 하나**(`.builtInWideAngleCamera`)다. virtual 전면 카메라를
  가진 iPhone이 없으므로 **전면에는 0.5x가 없고 그것이 정상이다.**
  요구를 맞추려고 software로 화각을 넓히지 않는다 — 없는 렌즈는 만들 수 없다
- 후면은 `.builtInTripleCamera` → `.builtInDualWideCamera` → `.builtInWideAngleCamera`
  순으로 찾는다. **0.5x는 렌즈가 있어야 나온다.** 없는 기기에는 버튼이 없다.
  (예전 정책은 후면도 wide 하나였다 — 0.5x를 주려면 virtual 카메라여야 한다)
- tele 단독 · ultra-wide 없는 `.builtInDualCamera`는 고르지 않는다 —
  0.5x도 못 얻으면서 화각만 좁아진다
- **기기 이름으로 분기하지 않는다.** `DiscoverySession`과 device property가 authority다

### 배율 범위는 format 뒤에 읽는다

`activeFormat`이 쓸 수 있는 렌즈와 전환 지점을 정한다. 순서가 바뀌면 **없는 0.5x를
있다고 말하게 된다.** `configure(_:)`가 format → capability 순서를 지키고 그 값을 돌려준다.

### 버튼

후보는 `zoomPresetCandidates = [0.5, 1, 2]`이고 **기기가 낼 수 있는 것만** 남는다.
나중에 3x·5x를 더하려면 이 줄에만 더한다. 고를 것이 하나뿐이면 selector를 그리지 않는다.

- 자리는 **촬영 버튼 바로 위 가운데**. 전환/플래시/홈으로와 겹치지 않고 거울 가운데를 가리지 않는다
- 글자는 작아도 tap target은 **44pt**. 낭독기 label은 `0.5배` · `1배` · `2배`
- **기존 control set의 일부다** — 같이 나타나고 같이 숨는다.
  누르면 기존 `onInteraction`으로 auto-hide 타이머를 다시 돌린다. 새 timer를 만들지 않는다

### pinch

두 손가락이라 컨트롤을 여닫는 한 손가락 탭과 섞이지 않는다.
`MagnifyGesture`에는 시작 callback이 없으므로 **첫 `onChanged`가 기준점을 잡고**
`endPinch`가 지운다 — 다음 gesture는 끝난 자리에서 시작한다.

- pinch는 손가락을 따라가야 하므로 **ramp를 쓰지 않고** 곧바로 넣는다.
  preset은 `ramp(toVideoZoomFactor:withRate:)`로 짧게 미끄러진다(rate 8 ≈ 0.25초).
  cinematic ramp는 거울에 느리다
- 언제나 **실제 지원 범위로 clamp**한다
- pinch로 preset 사이(예: 1.37x)에 있으면 **아무 버튼도 켜지지 않고** 현재 값이
  작은 label로 보인다. 화면이 말하는 것과 실제 배율이 다르면 안 된다
- pinch 뒤 `1x`를 누르면 **정확히** 1x다

### 카메라 전환

전환하면 배율 범위를 **다시 읽고**(`adoptActiveCapability`) 버튼 목록을 다시 만들고
1x로 맞춘다. 후면(0.5/1/2)에서 전면(1/2)으로 가면 0.5x 버튼이 사라진다.

### 촬영

`videoZoomFactor`는 **device 단계**라 preview · frame output · photo output이
같은 화각을 본다. preview만 확대되고 사진은 1x인 상태가 구조적으로 생기지 않는다.

`ggumirrorTests/MirrorZoomTests.swift`가 위 전부를 고정한다 —
**기기 이름이 아니라 capability 값으로** 시험한다.

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

### 등록 비용 · 정렬 · metadata (UI-P3)

상점 등록 비용은 **정책 상수 하나**에서만 나온다 — 화면·검증·안내가 전부 그 값을 읽는다.

| | 상수 | 값 |
|---|---|---|
| 거울 | `MirrorPublishPolicy.feeInShards` | **10 조각** |
| 스티커 | `StickerPublishPolicy.feeInShards` | **10 조각** |

과거 20조각 정책은 제거했다. B-7 backend도 이 값을 최종 정책으로 쓴다 —
`mirror_publish_fee = 10` · `sticker_publish_fee = 10`.

**등록비는 AI 생성값(5조각)과 다른 축이다.** 숫자가 겹쳐 보여도 한 상수로 묶지 않는다.

### 한 서랍에 같은 이름을 두 개 두지 않는다

`MirrorLibrary.rename` · `StickerLibrary.rename`이 겹치는 이름을 `.duplicateName`으로
거절한다. 실기기에서 같은 이름이 여럿이면 내 거울에서 어느 것인지 고를 수 없었다.

- 비교는 **`ContentNameKey.canonical`** 하나다 — 앞뒤 공백 제거 · NFC 정규화 · 소문자.
  `Pink` · ` pink ` · `PINK`가 같은 이름이고, 자모가 풀린 한글도 같은 이름이다
- **계정 안의 규칙**이다. 다른 계정 서랍과 상점 전체 이름 겹침은 다른 질문이다
- 자기 자신은 세지 않는다(`excluding:`) — 대소문자만 바꾸는 것도 정상적인 이름 바꾸기다
- **기존에 겹쳐 있던 이름을 자동으로 바꾸지 않는다.** 새로 겹치는 것만 막는다

### AI 거울도 이름을 정하고 저장한다

예전에는 전부 `AI 거울`로 저장돼 내 거울에 같은 이름이 쌓였다. 이제 `내 거울에 저장`이
**이름 시트를 먼저 연다**(`MirrorNameSheet` — 이름 바꾸기·새 거울 저장과 같은 component).

**이름 단계는 생성을 다시 부르지 않는다.** 이미 낸 조각으로 이미 받은 그림이라
`maker.generate` · wallet · shard가 그 경로에 없다. 시트를 닫아도 결과는 남는다.

### 등록하면 내 콘텐츠 이름도 그 이름이 된다

사용자가 상점에 올리면서 붙인 상품명이 **그 거울/스티커의 이름**이다.
등록에 **성공한 뒤에만** 기존 이름 바꾸기 통로(`MirrorLibrary.rename` ·
`StickerLibrary.rename`)로 local 이름을 맞춘다 — id로 찾고, 그 안에서 디스크까지 저장된다.

- 실패하면 이름을 바꾸지 않는다. 올리지도 못한 이름이 내 거울에 남으면 안 된다
- 화면에서 listing title로 **덮어 그리지 않는다** — 실제 model과 persistence를 바꾼다
- 서버로 가는 값과 local에 남길 값은 **같은 변수**에서 나온다(갈라질 수 없다)
- 이름으로 콘텐츠를 찾지 않는다. `MyMirror.id` / `StickerProject.id`가 열쇠다

### 이름 없이 상점에 올릴 수 없다

상품 카드에는 판매자 이름이 보인다. 비어 있으면 사는 사람은 누가 올린 것인지 알 수 없다.
그래서 `상점에 올리기`가 **서버에 보내기 전에** 이름을 받는다(`SellerNameSheet`).

- Apple 계정 이름이 아니라 **꾸미러 안의 판매자 표시 이름**이고,
  authority는 서버다(`ProfileSession` → `PATCH /users/me/profile`)
- **겹치는 이름은 서버 transaction이 거절한다.** 화면이 "찾아보니 없더라"로 정하지 않는다.
  겹침(`이미 사용 중인 이름이에요.`)과 30일 규칙을 **다른 말로** 알린다
- 상품 이름도 상점 전체에서 겹치지 않는다 — 서버가 거절하면 `이미 사용 중인 상품 이름이에요.`
- 저장에 성공한 뒤에만 시트가 닫히고, 등록 정보는 그대로 남아 이어서 올릴 수 있다

**정렬은 `StoreSort` 하나를 거울/스티커 상점이 공유한다.** 기본값은 최신 순이고
선택은 저장하지 않는다(로컬 목록 정렬이라 네트워크를 다시 부르지 않는다).

| UI | authority | tie-breaker |
|---|---|---|
| 최신 순 | `uploadedAt` DESC | id |
| **인기 순** | **`downloadCount` DESC** | uploadedAt → id |
| 좋아요 순 | `likeCount` DESC | downloadCount → uploadedAt → id |

**"인기"는 다운로드 수 하나다.** 좋아요를 섞은 가중 점수를 만들지 않는다 —
섞으면 왜 이 순서인지 아무도 설명할 수 없다. 이름만 "인기 순"이다.

`downloadCount`의 의미는 **"최초 소유권 획득 성공"**이다:

| | |
|---|---|
| 유료 구매 + ownership 생성 성공 | +1 |
| 무료 ownership 생성 성공 | +1 |
| 같은 사용자의 재다운로드 · 중복 구매 · retry | **+0** |
| 판매자 본인 사용 | **+0** |
| 미리보기 | **+0** |

**count는 서버가 센다.** 앱이 올리지 않고, 랜덤/실행마다 증가/클릭 증가를 만들지 않는다.
서버가 없는 지금 내장 목록은 전부 `0`이고 `uploadedAt`은 `nil`이다 —
`Date.now`를 채우면 거짓말이 된다. 표시는 `—`이고 정렬에서는 맨 뒤로 간다.

좋아요도 같다 — 실제 multi-user like backend가 없으므로 **표시와 정렬 계약까지만** 있다.

### 내 거울로 미리보기 (Marketplace Mirror Preview)

**받기 전에 · 로그인 없이 · 아무것도 사지 않고** 실제 카메라 위에 얹어 본다.
내장 템플릿과 사용자 상품이 **같은 버튼 · 같은 문구 · 같은 화면**을 쓴다.

`내 거울로 미리보기`는 상세의 **1순위 CTA**이고 받기보다 위에 있다.

| 출처 | 얹는 것 |
|---|---|
| 내장 템플릿 | `MirrorDesign(template:)` → 실제 거울과 **같은 renderer** |
| 사용자 상품 | 이미 받아 둔 **공개 미리보기 PNG**에서 카메라 자리를 도려낸 것 |

#### 미리보기는 경제 동작이 아니다

소유권 생성 ❌ `downloadCount` 증가 ❌ buyer debit ❌ seller credit ❌
`내 거울` 저장 ❌. `MirrorLivePreview.swift`에는 그런 것을 부르는 코드가 **없고**
`PreviewIsNotAnEconomicActionTests`가 소스 레벨로 고정한다.

로그아웃 상태에서도 열린다 — `openPreview()`에 로그인 관문이 없다.
`받기`를 누를 때만 기존 안내 창이 뜨고, **로그인 성공 직후 자동 구매/획득은 없다.**

#### 사기 전에 원본을 주지 않는다

미리보기가 읽는 것은 **`store.previews[listing.id]` 하나**다 — 카드가 이미 보여 주는
그 공개 그림이다. manifest · 원본 asset · 판매자 전용 경로를 새로 부르지 않고,
public raw object 권한을 추가하지도 않는다. 새 endpoint도 없다 —
**backend 변경 없음.**

#### 카메라 자리를 도려낸다

`preview.png`는 카메라 자리까지 **불투명하게 구워져** 있어 그대로 얹으면
자기 얼굴이 안 보인다. `MirrorThumbnailNormalizer.cameraOpeningRemoved(png:)`가
`MirrorFrameInsets.standard.mirrorArea` 안에서 **바탕색 픽셀만** 알파 0으로 바꾼다.

- 바탕색은 **카메라 자리의 최빈 불투명 색**이다. 구운 시점마다 값이 다르므로
  (예전 어두운 유리색 · 지금 `PaperTheme.thumbnailGlass`) 하나로 적어 두지 않는다.
  장식이 카메라 자리를 전부 덮는 일은 없어 최빈색이 곧 바탕이다
- 밝게 되돌리기(`normalized`)와 **같은 pass를 공유한다.** 새 hex를 하드코딩하지 않는다
- 프레임 밴드와 카메라 자리 위 장식은 **한 픽셀도** 바뀌지 않는다
- 반투명 경계는 손대지 않으므로 장식이 카메라 자리에 닿는 곳에 아주 옅은 테가 남는다.
  얼굴을 가리는 것보다 낫다는 판단이다
- 도려낼 수 없으면 **열지 않는다**(안내만 띄운다). 얼굴이 가려진 화면은 미리보기가 아니다
- 기존 GCS object를 다시 쓰지 않으므로 **예전에 등록된 상품도 그대로 동작한다.**
  re-publish도 일괄 rewrite도 없다

#### 미리보기에서도 넓게 / 채우기를 고른다

실제 거울과 **같은 authority**를 쓴다 — `MirrorCamera.Framing`(`wide` · `fill`)과
그 `previewGravity` 매핑, 그리고 같은 칩 component(`MirrorFramingSelector`)다.
미리보기 전용 비율 계산은 **없다**(`resizeAspect` · `videoGravity` · `4:3`이
`MirrorLivePreview.swift`에 없다는 것을 테스트가 고정한다).

칩은 예전에 `MirrorControls` 안 private이었다. 미리보기에도 필요해져서 **꺼냈다** —
사본을 만들면 두 화면의 생김새와 44pt tap 규칙이 반드시 갈라진다.

- 기본값은 `Framing.initial`(= `채우기`)이다. 미리보기가 자기 기본값을 따로 적지 않는다
- **`setFrontFraming(_:)`을 부르지 않는다.** 그것은 실제 거울 화면의 사용자 설정이고,
  상점에서 `채우기`를 골랐다고 홈 거울까지 따라 바뀌면 안 된다.
  미리보기의 선택은 그 화면 하나 동안만 살고 `UserDefaults`에 저장하지 않는다
  (`MirrorLivePreviewView`는 자기 `MirrorCamera` 인스턴스를 갖는다 —
  `frontFraming`을 공유하는 구조가 애초에 아니다)
- 자르는 방법은 **카메라 layer 하나**에만 걸린다. 프레임 · 글씨 · 그림 · 스티커 ·
  사진 · Marketplace 납작 overlay의 자리와 크기는 움직이지 않는다 —
  장식을 그리는 자리에 `framing`이 들어가지 않는다
- 바꾸면 `AVCaptureVideoPreviewLayer.videoGravity` 하나만 바뀐다.
  세션을 다시 시작하지도, 다시 붙이지도 않는다. 같은 값이면 아무 일도 하지 않아
  연속으로 눌러도 깜빡이지 않는다
- **도려내기를 다시 돌리지 않는다.** `cameraOpeningRemoved`는 상세 화면이 미리보기를
  열기 전에 한 번 부르고, 미리보기 화면 안에는 부르는 자리가 없다.
  납작 overlay도 `UIImage`로 **한 번만** 풀어 둔다 — 칩을 누를 때마다 1.66MB PNG를
  다시 해독하지 않는다
- 카메라 조작은 늘지 않았다 — 전환 · 플래시 · 촬영 · 배율 · pinch가 여전히 없다

#### 미리보기 화면에는 촬영이 없다

`MirrorCamera()` 기본 role은 `.viewfinder`다 — photo output · 전환 · 배율 · 플래시가
**구조적으로 없다.** 사진이 나가거나 저장될 길이 아예 아니다.
`fullScreenCover`인 이유는 거울이 화면 전체 좌표(1080 × 2340)로 그려지기 때문이다 —
시트에 넣으면 장식과 카메라가 실제 거울과 다른 자리에 놓인다.

스티커에는 미리보기가 없다 — 카메라 자리가 없고, 얹어 보는 것이 아니라 붙여 쓰는 것이다.

`ggumirrorTests/MirrorPreviewFlowTests.swift`가 위 전부를 고정한다.

### 운영 화면은 공개 상점과 같은 것을 말한다

`판매 중`(`AdminStatusFilter.live`)이 **실제로 공개된 것만** 보여 준다.
예전에는 draft까지 `판매 중`에 들어와서, 공개 상점에 없는 상품이 운영 화면에만
보였다(실기기에서 `찬찡`으로 나타났다). **데이터가 깨진 것이 아니라 필터 문제였고,
문서를 손으로 지우지 않았다.** 판단은 `AdminListing.isPubliclyVisible` 한 곳에서 나온다.

`상점에서 내리기`가 눌러도 아무 일이 없던 원인은 `InkDialog`가 버튼을 누르면
**`onAction()`(창 닫기)을 handler보다 먼저** 부르기 때문이다. 닫히면서 binding setter가
`pendingTakedown = nil`을 써서 handler가 언제나 빈 값을 읽었다.
이제 **창을 만들 때 대상을 붙잡는다**(`let target = pendingTakedown`) — handler가
`@State`를 다시 읽지 않는다. 되살리기도 같은 모양이다.

판매자가 삭제한 것은 여전히 되살릴 수 없고, 조치 뒤에는 그 항목만 **id로 찾아** 바꾼다.

### 등록 화면은 사실을 말한다

`지금은 차감되지 않아요`를 지웠다 — 등록비는 **실제로 차감된다.**
`등록 준비 저장`은 정말로 차감하지 않으므로 그 안내는 남는다. 두 문장은 다른 사실이다.

### 사용자 action (UI-P3)

거울과 스티커의 action 구성은 **같다**. 다른 것은 등록 비용뿐이다.

    상점에 등록 · 사진에 저장 · (거울: 적용/꾸미기, 스티커: 사용하기/꾸미기) · 삭제

**복제와 공유하기는 없다.** 사진에 저장은 남는다 — 공유를 없앤다고 앱 밖으로 꺼내는
길까지 막지 않는다. `UIActivityViewController`를 띄우는 코드가 앱에 없다.

Editor 캔버스의 오브젝트 복제(스티커/텍스트 하나를 캔버스에서 복제)는 **다른 기능이라 남는다.**
`MirrorLibrary.duplicate` · `StickerProjectStore.duplicate`도 남는다 —
`.duplicate` 저장 context와 asset 공유 테스트가 쓰는 내부 helper다.

등록할 수 없는 거울이라도 **버튼을 조용히 감추지 않는다** — 왜 안 되는지 알려준다.

`ggumirrorTests/StoreActionsTests.swift`가 위 전부를 고정한다.

production Store artwork는 실제 hand-drawn PNG 24개.

placeholder Store content를 다시 추가하지 않는다.

Store browse 자체는 로그인 없이 가능.

현재 유료 CTA는 실제 server purchase가 아니다.

### 공개 상점 필터 · 정렬 (Marketplace UX Hardening)

**디자인 갈래를 전부 없앴다.** 리본 & 하트 · 다이어리 · Y2K · 기념일 · 추천 · 인기 ·
신규 chip과 꼬리표 줄이 사라졌다 — 사용자 상품에는 그런 값이 **애초에 없어서**
갈래를 고르면 오히려 아무것도 안 보였고, 상품이 늘수록 어느 칸에 넣을지도 헷갈렸다.

상단은 두 줄뿐이다:

```
[전체] [무료]
최신 순 · 인기 순 · 좋아요 순 · 가격 순
```

| 정렬 | 기준 |
|---|---|
| 최신 | `publishedAt` DESC |
| 인기 | `downloadCount` DESC → publishedAt → id |
| 좋아요 | `likeCount` DESC → downloadCount → publishedAt → id |
| **가격** | `priceShards` **ASC** → publishedAt → id |

필터와 정렬은 **독립**이다(`무료 + 인기 순`). 갈래에서 끌어내던 내장 템플릿 가격은
이제 각 템플릿이 직접 들고 있다 — 값은 그대로다(0 · 18 · 20 · 24).
그림 이름("Y2K 스타")과 에셋 폴더 경로는 분류가 아니라 그대로 둔다.
backend에는 category가 **원래 없다.**

### 공개 목록을 받아오는 자리 (회귀)

**받아오는 `.task`를 상품 구획 안에 두지 않는다.** 그 구획은 목록이 비면
`EmptyView()`를 그리고, 그 위의 `.task`는 **한 번도 실행되지 않는다** —
비어 있으니 요청하지 않고, 요청하지 않으니 영원히 비었다.
등록한 거울이 상점에 안 보이고 카드에 하트가 없던 원인이 이것 하나였다.

받아오는 책임은 **언제나 그려지는 화면**(`StoreView` · `StickerStoreView`)에 있다.
등록에 성공하면 `publicFeedVersion`이 올라가 다시 받는다 — 앱을 껐다 켜지 않아도 된다.
**자기 상품을 공개 목록에서 빼지 않는다.** 막는 것은 self-like뿐이다.

### 로그인 관문

상점 탐색 · 정렬 · 필터 · 상세 · 미리보기는 **로그아웃 상태로 가능하다.**
좋아요 · 구매 · 받기 · `내 판매`를 누를 때만 안내 창이 뜬다.

- **서버에 먼저 보내 401을 받고 나서 알리지 않는다** — 로그인하지 않은 것은 이미 아는
  사실이라 요청 없이 바로 말한다
- `AuthSession.requireSignIn(for:)`이 예전부터 `pendingAction`을 세웠는데 **그 값을 보는
  곳이 없어서** 눌러도 아무 일이 없었다. 새 auth 체계를 만들지 않고 그 값을 화면에 이었다
- 창은 탭 컨테이너 **한 곳**에 달려 어느 탭에서 눌러도 같다.
  `로그인`은 설정의 기존 Apple 로그인으로 보내고, **경제 동작을 자동 실행하지 않는다**

### 스티커 카드는 거울 칸을 쓰지 않는다

거울 비율(≈0.46)에 거의 정사각인 스티커를 `.fill`로 넣으니 좌우가 잘리고 작은 투명
PNG는 늘어나 뭉개졌다. `ListingPreviewStyle`이 종류별로 정한다 —
거울은 거울 비율 + `.fill`, 스티커는 **정사각 + `.fit` + 투명 바탕**.
모르는 종류는 거울처럼 다룬다. **원본 픽셀 크기에 기대지 않는다.**

### 상점 IA — 공개와 판매자 관리를 나눈다 (Marketplace UX hardening)

상단 primary mode가 셋이다:

```
거울 | 스티커 | 내 판매
```

`거울` · `스티커`는 **공개 published 상품만** 보여 준다. 판매자 관리 UI를 여기에
섞지 않는다 — 실기기에서 사용자가 draft와 실제 판매 중인 것을 바로 혼동했다.

`내 판매`는 `GET /users/me/marketplace/listings`가 authority이고
**판매 중**(`published`) / **등록 미완료**(`draft`)로 나눈다. 등록 도중 실패해 남은
draft도 여기서 이어서 올릴 수 있다.

### 삭제 — 되살릴 수 없지만 아무것도 지우지 않는다

판매자 action은 `상점에서 내리기`가 아니라 **`삭제`**다. 누르면 바로 실행하지 않고
확인을 받는다(등록비 환불 없음 · 이미 받은 사용자는 계속 사용 가능을 명시).

서버는 `deleted` **끝 상태**로 표시만 한다 — snapshot · GCS object · 소유권 · 원장 ·
카운터가 전부 남는다. **client가 조각을 건드리지 않는다**(환불이 없으므로 서버 상태만
다시 받는다). 등록비 숫자는 화면에 적지 않고 기존 정책 상수를 읽는다.

### 내 거울 → 판매 중 (server authority)

`MirrorOrigin.listed`를 설정하는 코드가 없어서 이 필터는 **늘 비어 있었다** —
실제로 팔고 있어도 안 보였다. 이제 서버 판매 목록(`published`)과
**`sourceContentId`**(= `MyMirror.id`)로 맞춘다. **제목으로 맞추지 않는다.**
카드에 `판매 중` 배지가 붙는다.

### 좋아요는 카드에서 누른다

공개 상품 카드 오른쪽 위에 하트가 있다(44pt tap target). 상세로 들어가야만 누를 수
있으면 어디서 누르는지 알 수 없다는 것이 실기기에서 확인됐다.

`likedByMe`는 **서버가 authority**다 — `GET /users/me/marketplace/likes`를 공개
목록과 합친다(B-7E.1에 이미 있던 것을 재사용). 자기 상품에서는 숫자만 보이고
누를 수 없다 — 서버가 거절할 CTA를 일부러 보여 주지 않는다.

### 내장 템플릿 다운로드 수 — 서버가 센다 (Hardening.1)

`민트 플라워`가 받아도 늘지 않던 이유는 **애초에 세지 않았기 때문**이다. 획득이 순수
로컬 동작(`MirrorLibrary.acquire`)이라 서버에 기록도 집계도 없었다. 이제 catalog
domain이 센다.

```
GET  /catalog/templates/stats?ids=…        (공개, 한 번에)
POST /catalog/templates/{id}/acquire       (인증)
POST /catalog/templates/reconcile          (인증, 멱등)
```

- **받기 전에는 숫자를 보여 주지 않는다.** `CatalogStats.downloadCount`가 `nil`이면
  카드가 자리를 비운다 — 받아오기 전 `0`은 "아무도 안 받았다"는 거짓말이다.
  실제 `0`을 받으면 `0`을 보여 준다
- **로컬 저장이 성공한 뒤에** 서버에 기록한다. 그 요청이 실패해도 로컬 획득을 되돌리지
  않는다 — 다음 맞춰 보기가 되찾는다
- 로그아웃 상태에서도 받을 수 있다(로그인 벽을 세우지 않는다). 나중에 로그인하면
  **맞춰 보기 한 번**으로 반영된다
- 이전 다운로드는 **`MyMirror.id == template.id`**로 찾는다(`acquire`가 그렇게 저장한다).
  **제목으로 찾지 않는다** — 사용자가 이름을 바꿨을 수 있고 같은 이름이 여럿일 수 있다
- 카드마다 요청하지 않는다. 상점 진입에 **한 번** 묻는다
- **좋아요 수는 내장 카드에서 뺐다.** 그것을 세는 서버 domain이 없어서 `0`을 보여 주면
  방금 고친 거짓말을 다시 하는 셈이다. 사용자 상품에는 하트가 있다

### 이전 판매 중지 (legacy unlisted)

새 UI는 unpublish를 만들지 않으므로 `unlisted`가 **앞으로 새로 생기지 않는다.**
하지만 예전 UI로 내려둔 것이 production에 남아 있고, `판매 중`/`등록 미완료`
어디에도 안 보이면 관리할 수 없다. `내 판매`에 세 번째 구획을 뒀다.

action은 **삭제뿐**이다 — "다시 판매"를 만들지 않는다. 사용자가 원한 것은 되돌릴 수
있는 숨김이 아니라 끝내는 것이다. 기존 soft-delete endpoint를 그대로 쓴다.
`deleted`는 어느 구획에도 보이지 않는다.

### 모달은 화면 좌표에 뜬다 (UI Overlay Hardening)

`inkBottomSheet` · `inkDialog`는 **`InkModalPresentation` 하나**를 지나 window에
표현된다(`fullScreenCover` + `presentationBackground(.clear)`).

예전에는 `.overlay`였다 — `.overlay`는 **붙은 view의 좌표계**에 그린다. 그래서
`StoreView`의 ScrollView 안에서 띄운 삭제 확인이 화면이 아니라 **스크롤 내용** 기준으로
자리를 잡아, 아래로 내린 상태에서는 화면 밖에 그려졌다. 등록 시트도 같은 이유로
아래쪽이 탭바에 가려 `상점에 올리기`를 누를 수 없었다.

- **화면마다 `.offset` · 여백 · GeometryReader 숫자로 고치지 않는다.** 자리 문제는
  표현 경로 한 곳에서 끝낸다
- 탭바를 감추던 우회(`InkModalPresentedKey` · `inkHiddenWhileModalPresented`)는
  **사라졌다.** cover는 탭바보다 위이고 safe area를 스스로 안다
- 카드 모양 · dim · 손잡이 · 높이 규칙(`SheetHeight`)은 **그대로**다. 새 UI framework를
  만들지 않았다
- 시트를 닫으면서 **같은 순간에** 다음 것을 열지 않는다. 닫히는 중에 띄우면 시스템이
  두 번째 표현을 조용히 버려서, 버튼을 눌렀는데 아무 일도 안 일어난 것처럼 보인다.
  `onDismiss:`에서 연다 (AI 시트 → 조각 상점 / 스티커 고르기 → 만들기 → Creator /
  새 거울 → 가져오기)
- **모달은 이제 `ImageRenderer`로 그려지지 않는다** — window 표현이라 view 계층에
  들어오지 않는다. 픽셀로 확인하던 시트 검사는 자리·높이 **규칙 검사**로 바꿨다

`ggumirrorTests/OverlayHardeningTests.swift`가 위를 고정한다.

### 키보드는 두 가지로 닫는다

스크롤은 native `.scrollDismissesKeyboard(.interactively)`, 빈 곳 탭은
`inkDismissesKeyboardOnTap()`. 탭 층은 **내용 뒤**에 깔린다 — 앞에 겹치거나
`simultaneousGesture`로 붙이면 입력 칸을 누르는 순간 방금 올라온 키보드를 도로 내린다.

### 이미 받은 내장 템플릿

`MyMirror.id == template.id`로 판단한다(`acquire`가 그렇게 저장한다).
**제목으로 찾지 않는다.** 이미 있으면 CTA가 `이미 내 거울에 있어요`로 잠긴다 —
`acquire`가 중복을 만들지 않으므로 눌러도 아무 일이 없는데 "담았어요"라고 말했다.

### 좋아요는 눌린 상태가 뒤집힌다

속이 찬 하트와 빈 하트의 차이는 caption 크기에서 너무 미묘했다. 눌리면 칩 전체가
먹지 + 종이 글자로 뒤집힌다(기존 Ink 강조 그대로). 44pt tap target은 그대로다.

### 상점 scroll 계층 (B-7H UI hotfix)

**상단 제어부를 고정하지 않는다.** 제목 · 조각 잔액 · 거울/스티커 · 갈래 · 꼬리표 ·
정렬이 전부 상품과 **같은 scroll content** 안에 있어서, 아래로 내리면 함께 위로 사라진다.
고정해 두면 실제 상품이 보이는 세로 공간이 너무 좁았다.

**세로 scroll은 `StoreView`에 하나뿐이다.** `StickerStoreView`는 자기 ScrollView를
갖지 않는다 — 중첩되면 상단 제어부가 따라 올라가지 않는다.
`scrollIndicators` · `contentMargins(.bottom, InkTabBar.reservedHeight + 24)`도
그 한 곳에서만 준다(UI-P2 그대로).

content 순서:

```
상점 제목 + 조각 잔액
거울 / 스티커
갈래(category)
꼬리표(tag)
정렬(최신 / 인기 / 좋아요)
내 상점 상품          ← 판매자가 자기 것을 먼저 찾는다
사용자 상품
내장 템플릿 24종
```

하단 앱 tab bar만 고정이다. **디자인은 바꾸지 않았다** — layout/scroll 구조만 옮겼다.

`ggumirrorTests`의 `StoreScrollHierarchyTests`가 위 계층을 고정한다.

### 등록 복구 · 판매자 미리보기 (B-7H hotfix)

**판매자 카드에 실제 미리보기가 보인다.** 제목과 숫자만 있으면 어느 상품인지
알 수 없었다. `draft` · `unlisted`도 보여야 하므로 **판매자 전용 endpoint**
(`GET /users/me/marketplace/listings/{id}/preview`)를 쓴다 — 공개 미리보기는
여전히 `published`만이고 그 정책은 그대로다. 두 캐시를 섞지 않는다(권한이 다르다).

**등록 실패가 중복 상품을 만들지 않는다.** production에서 실제로 일어난 일:
snapshot·listing은 만들어졌고 publish만 404였는데, 앱이 listing id를 들고 있지
않아서 재시도 때 snapshot과 listing을 **또** 만들었다. 같은 콘텐츠가 두 건,
GCS object는 두 배가 됐다.

그래서 순서를 고정했다:

```
1. snapshot 생성 성공
2. listing 생성 성공
3. listing id 지역 저장 성공      ← 여기까지 되어야
4. publish 요청                   ← 보낸다
```

3이 실패하면 publish를 보내지 않는다 — 보내고 응답을 잃으면 그 listing을 영원히
못 찾는다. 재시도는 **서버 상태를 authority로** 판단한다:

| 서버 상태 | 하는 일 |
|---|---|
| `draft` | 그 listing의 publish만 다시 보낸다 |
| `unlisted` | 같은 endpoint(다시 올리기). 추가 등록비 없음 |
| `published` | 아무 요청도 보내지 않는다 |
| 없음 | 지역 기억이 낡았다. 호출부가 새 등록을 시작할 수 있다 |

**새 snapshot·새 listing을 만들지 않는다.** 제목으로 맞추지 않는다(같은 제목이
여러 개일 수 있다). 등록비 판단은 서버가 `publishFeePaid`로 한다.

복구는 이미 불변 snapshot을 가리키는 draft를 **그대로** 올린다 — 실패 이후
사용자가 거울을 고쳤어도 올라가는 것은 그때 올린 내용이다. 조용히 바꿔치기하지
않는다. 지금 콘텐츠로 새 버전을 올리는 것은 별개 문제로 남겼다.

문구도 바꿨다: `draft` → **"등록 미완료"**(옛 "등록 준비"는 실패로 남은 것에도
붙어서 사용자가 자기가 안 올린 줄 알았다), `unlisted` → **"판매 중지"**.
server status/schema는 그대로다.

### 내 상점 상품 — 서버가 authority다 (B-7G.1)

`GET /users/me/marketplace/listings`가 `draft` · `published` · `unlisted`를 전부 준다.
**이것이 자기 상품 관리의 authority다.**

`MirrorPublishDraft.listingID` · `StickerPublishDraft.listingID`는 **힌트(cache)**로
낮췄다(제거하지 않았다 — 기존 저장 파일을 깨지 않는다). 다음은 로컬 id에 의존하지 않는다:

- 내 등록 상품 찾기
- 내리기 · 다시 올리기
- `published` / `unlisted` 상태 판단

앱을 지웠거나 기기를 바꾸면 로컬 id가 없다 — 그때도 관리가 되어야 한다.
그래서 `MyListingsSection`은 서버 목록만 읽고 로컬 draft를 아예 모른다.
등록 시트의 관리 버튼은 편의이고, 힌트 id를 **서버 목록으로 조회한 뒤에만** 나온다.

성공 후 갱신: publish → 내 목록 / unpublish · republish → 내 목록 + 공개 목록.

**상태 문자열을 열거형으로 decode하지 않는다.** 모르는 값이 오면 목록이 통째로
비는 것보다 그 상품만 "알 수 없음"으로 남는 편이 낫다.

**서버 listing에는 local content id가 없다.** `Listing` · `Snapshot` ·
`ListingResponse` 어디에도 `MyMirror.id` / `StickerProject.id`가 없어서, "이 거울이
이미 등록돼 있다"를 로컬 화면에서 서버 authority로 판단할 수는 없다. 제목 문자열로
맞추는 것은 하지 않는다 — 같은 제목이 여러 개일 수 있다. 관리는 "내 상점 상품"
구획에서 완결되므로 이번 phase에 식별자를 새로 만들지 않았다.

## 내 거울 보관 한도 (UI Overlay Hardening)

무료 **5개**, 조각으로 늘린다. **origin을 가리지 않는다** — 만든 것 · 내장 템플릿 ·
상점에서 받은 것을 전부 센다. 예전에는 `.made`만 세서 화면의 "3 / 3"이 실제 보관량과 달랐다.

| | |
|---|---|
| 표시 | `보관 중 N / M` (`storedCount` / `mirrorCapacity`) |
| 무료 기본 | `MirrorStoragePolicy.freeMirrorSlots = 5` — **서버에 닿기 전의 보수적 기본값** |
| 담을 수 있는 칸 | **서버가 authority다** (`GET /users/me/mirror-capacity`) |
| 확장 | `mirror_slots_5` — 서버가 알려주는 값(현재 10조각 → +5칸), 반복 구매 가능 |

### 칸은 서버에 있다

산 칸은 **서버 사용자 문서**에 있다 — 이 기기의 저장 파일이 아니다.
앱을 지우거나 기기를 바꿔도 산 칸은 그대로다.

- `MirrorLibrary.mirrorCapacity`를 바꾸는 자리는 **`applyServerCapacity(_:)` 하나**다.
  `ShardWallet.apply(balance:)`와 같은 규칙 — 여기서 더하거나 빼지 않는다
- 서버를 못 읽으면 **마지막으로 본 값을 그대로 둔다.** 예전 로컬 값을 authority로
  올리지 않는다(그러면 결제하지 않은 칸이 생긴다). 무료 기본값 아래로도 내려가지 않는다
- 저장 파일의 `purchasedCreatedSlots`는 **더 이상 읽지 않고 언제나 0으로 쓴다.**
  field는 남겨 둔다 — 예전 파일이 깨지지 않게. 로컬 `grantSlotPack`은 삭제했다

### 구매 — 의도 하나 = operationId 하나

client가 UUID를 만들어 보낸다. **응답을 잃으면 같은 id로 재시도한다** —
새 id를 만들면 서버가 다른 의도로 보고 조각이 두 번 빠진다.
`MirrorCapacityStore.pendingOperationID`가 그 값을 들고 있고, 성공이나 명시적 거절
(409)에서만 지운다. 요청 중에는 버튼이 잠겨 의도가 여러 개 생기지 않는다.

- **client가 가격도 칸도 계산하지 않는다.** 보내는 것은 `packId`와 `operationId`뿐이고,
  결과는 서버가 준 `balance` · `effectiveSlots`를 그대로 옮겨 적는다
- **가격을 앱에 적지 않는다.** `10`과 `5`는 서버 응답(`pack`)에서 온다 —
  서버가 값을 바꾸면 화면이 따라간다. 상품을 못 읽었으면 CTA 자체를 그리지 않는다
- 확인 창 · 부족 안내 · 결과 안내는 **`inkMirrorStorageFullDialog` 한 곳**에 있다.
  가득 찼을 때의 `공간 늘리기`가 그대로 그 확인 창을 연다 — 새 시트를 만들지 않는다.
  `내 거울`의 `+N칸` 버튼도 같은 창을 연다
- 이 modifier는 Editor · 상점 상세에도 붙으므로 환경값을 **optional로 읽는다.**
  필수로 읽으면 그 화면을 따로 그리는 테스트·미리보기가 그 자리에서 죽는다

- **거울이 늘어나는 길 셋을 모두 막는다** — 만들기(`save`) · 내장 받기(`acquire`) ·
  상점에서 받기(`adopt`). 한 곳만 막으면 나머지로 계속 늘어난다.
  상점 가져오기는 **내려받기 전에** 막는다(다 받고 못 담으면 데이터만 버린다)
- 이미 가진 것을 다시 받는 것은 자리를 새로 쓰지 않으므로 통과한다
- **한도를 넘긴 사용자의 거울을 지우지 않는다.** 더 담기는 것만 막는다 —
  예전 정책에서 더 만들어 둔 사용자가 실제로 있다
- 안내는 `inkMirrorStorageFullDialog` **한 곳**이다. **가격을 적지 않는다** —
  확장 가격이 없고, 임의 숫자로 조각을 차감하는 버튼을 만들지 않는다
- **경제 거래와 섞지 않는다.** 보관 공간은 조각 원장이 아니라 이 기기의 저장 규칙이다.
  서버가 authority가 되면 `baseMirrorCapacity` 한 줄만 서버 값으로 바꾼다
- `createdCount`는 남아 있지만 뜻이 다르다 — 한도가 아니라
  "이 동작이 새 거울을 만들었나"를 보는 값이다

## 계정별 내 콘텐츠 (Account-scoped Library)

**내 거울과 내 스티커는 계정마다 따로 산다.**

예전에는 `Application Support/ggumirror/` 한 곳을 모든 Apple 계정이 공유했다 —
A로 만든 거울이 로그아웃 뒤에도, B로 로그인해도 그대로 보였다. 한 기기를 나눠 쓰는
편의가 아니라 **남의 콘텐츠가 보이는 문제**라 고쳤다.

```
Application Support/ggumirror/
  accounts/{userId}/   ← 로그인한 계정의 서랍 (거울 · 스티커 · asset 전부)
  accounts/guest/      ← 로그아웃 상태. 비어 있는 것이 정상이다
  (루트)               ← 계정 구분 이전 파일. 한 번 넘겨줄 때까지 그대로 둔다
```

- 폴더 이름은 **backend 내부 user UUID**다. raw Apple subject · 이메일을 쓰지 않는다.
  UUID 모양이 아니면 `SHA256`으로 바꾼다(직접 만들지 않는다)
- **로그아웃은 삭제가 아니다.** 보는 서랍만 바뀌고 A의 파일은 남는다.
  다시 로그인하면 그대로 돌아온다. 계정 삭제와 혼동하지 않는다
- `MirrorLibrary.live` · `StickerLibrary.live`는 **guest에서 시작한다.**
  세션이 확정된 뒤 `activate(owner:)`가 그 계정 서랍으로 갈아 끼운다 —
  `onChange`만 믿으면 시작할 때 이미 복구된 세션에서 guest로 남는다
- **서랍을 바꾸기 전에 `flush()`로 쓰기를 기다린다.** 저장이 비동기라
  기다리지 않으면 마지막 변경이 사라진다(테스트가 실제로 잡았다)
- 보관 칸도 계정을 따라간다 — 전환하면 무료 기본값으로 되돌리고 서버에 다시 묻는다

### 예전 데이터 넘겨주기 (한 번만)

`claimLegacy`가 계정 구분 이전 파일을 **로그인한 사용자 서랍으로 옮긴다.** 규칙 셋:

1. 로그인한 사용자가 분명할 때만. **guest에게 주지 않는다**
2. 그 사용자 서랍에 이미 무언가 있으면 **건드리지 않는다**(덮어쓰지 않는다)
3. 옮기면 표시를 남겨 다시 하지 않는다

어느 쪽으로도 확신이 없으면 예전 파일을 **그 자리에 그대로 둔다** — 지우지도,
아무에게나 주지도 않는다. 스티커 파일도 같은 서랍으로 함께 간다.

⚠️ 한 번도 로그인한 적 없는 사용자의 콘텐츠는 **로그인할 때까지 보이지 않는다**(지워지지 않는다).
로그아웃 상태 = 빈 목록이라는 정책의 직접적인 결과다.

`ggumirrorTests/AccountLibraryTests.swift`가 위 전부를 고정한다.

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

## AI 스티커 (A-1A) — client는 provider를 모른다

프롬프트 한 줄 → 투명 PNG 스티커. **앱은 AI provider가 무엇인지도 모른다.**

- **provider API key를 앱에 넣지 않는다.** bundle에 들어가는 것은 누구나 꺼낼 수 있다.
  client가 아는 주소는 꾸미러 backend 하나이고, provider 호출은 전부 서버가 한다.
  `Config/*.xcconfig` · `Info.plist`에도 provider 관련 값을 넣지 않는다
- **가격을 앱에 적지 않는다.** 몇 조각인지는 `GET /ai/stickers/config`가 알려주고
  화면은 받은 값을 그대로 보여준다. 코드에 숫자를 적으면 서버가 값을 바꿀 때 거짓말이 된다
  (1.1.0에서 실제로 6 → 5가 됐다)
- **잔액을 client가 계산하지 않는다.** `balance -= 6`을 쓰지 않고,
  서버가 응답에 담아준 `balance`를 `ShardWallet.apply(balance:)`로 옮겨 적기만 한다.
  실패했을 때의 **환불도 서버가 한다** — client에 되돌리는 코드가 없다
- **CTA는 서버가 켠다.** `config.available`이 false면 Creator에 AI 버튼 자체가 없다.
  앱을 다시 내지 않고 서버 설정(`AI_IMAGE_API_KEY` · `AI_IMAGE_MODEL`)만 채우면 열린다
- **AI는 불투명 PNG를 준다**(production model `gpt-image-2`가 투명을 지원하지 않는다).
  투명은 기기가 만든다 — **기존 사진 배경제거(`PhotoStickerMaker`)를 그대로 쓴다.**
  새 segmentation engine을 만들지 않았고 서버에 배경제거 API도 붙이지 않았다
- **배경제거가 실패해도 AI를 다시 부르지 않는다.** 그림은 서버에 남아 있으므로
  "다시 시도"는 같은 generation을 다시 받아 컷아웃만 재시도한다 —
  provider 재호출도, 추가 조각 차감도 없다
- 결과는 **새 `StickerSource` case를 만들지 않고** `.photo`로 들어간다 —
  이미 "id로 참조하는 불변 bitmap + 비율"이라 저장 형식 · GC · 렌더 · 크기 조절 · 레이어가
  그대로 동작한다. 사진 cutout이 지나는 `PhotoStickerAssetStore.register`와 같은 자리다
- **프롬프트 원문을 저장하지 않는다.** 서버도 기기도 남기지 않는다 —
  다시 편집할 때 필요한 것은 그림이지 그때 뭐라고 적었는지가 아니다.
  로그에도 남기지 않는다(Release · Debug 모두)
- 출처는 `StickerProject.origin`(`made` / `aiGenerated`) + `generationIDs`다.
  **한 번 AI가 들어간 스티커는 되돌아가지 않는다** — 레이어를 지워도 출처는 기록으로 남는다
- **AI 스티커는 상점에 올릴 수 없다**(`canPublishToStore`). 내보내기(D-1)는 된다 —
  내가 쓰려고 만든 것과 남에게 파는 것은 다른 문제다. 화면에서 감추는 것으로 끝내지 않고
  `StickerLibrary.saveDraft`에서도 막는다
- 스티커 저장 파일은 **schemaVersion 2**다. 읽기는 뒤로 호환되지만(1은 `origin=made`),
  이 값을 모르는 예전 앱이 다시 저장하면 출처가 조용히 사라지므로 버전을 올렸다

### 생성은 서버가 소유한다 (A-1B)

응답 한 번이 전부가 아니다. **끊겨도 잃지 않는다.**

- **`requestId`(UUID)를 client가 만들어 기기에 적어 둔다.** 같은 값으로 다시 물으면
  서버는 새로 만들지 않고 그 작업의 지금 상태를 준다 — 조각이 두 번 나가지 않는다
- 적어 두는 것은 `requestId`와 `generationId`뿐이다.
  **프롬프트는 기기에도 남기지 않는다**(`PendingAIGeneration`에 자리가 없다).
  이어받을 때는 프롬프트를 **비워** 보낸다 — 서버도 우리도 원문을 들고 있지 않다
- 이미지는 응답이 아니라 `GET /ai/stickers/{id}/image`로 받는다.
  **signed URL을 쓰지 않는다** — URL 자체가 credential이 되면 로그 한 줄로 새어 나간다
- 앱을 껐다 켜도 `UserDefaults`에 남은 pending을 집어 들고 이어받는다.
  `generationId`를 알면 조회, 모르면 같은 `requestId`로 다시 POST
- 실패는 **조각이 돌아왔는지**로 나눠 말한다(`.refunded` vs `.interrupted`).
  `.isRecoverable`이 "다시 확인" 버튼을 보여줄지 정한다
- **client는 여전히 잔액을 계산하지 않는다.** 차감도 환불도 서버가 하고,
  `ShardWallet.apply(balance:)`로 서버 값을 옮겨 적기만 한다
- AI 요청 timeout은 200초다(기본 15초로는 정상 생성도 끊긴다).
  끊겨도 작업은 서버에 남으므로 "다시 확인"으로 되찾는다

`ggumirrorTests/AIStickerTests.swift`가 위 전부를 고정한다.

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

### 조각 IAP (B-6C) — client는 지급하지 않는다

조각 충전 **10 / 50 / 100**, 전부 consumable. Apple 결제 성공과 조각 지급은 **다른 단계**다.

- **StoreKit 2만 쓴다.** RevenueCat 같은 third-party 구매 SDK를 넣지 않는다
- **StoreKit에 닿는 파일은 `IAP/StoreKitShardStore.swift` 하나다.** 나머지
  (`ShardPurchase.swift` · `ShardPurchaseController.swift` · 화면)는 protocol만 알고
  StoreKit 타입을 모른다 — 그래서 구매/복구 흐름 전체를 SDK 없이 시험한다 (B-5와 같은 격리)
- **구매에 `.appAccountToken(<서버 user UUID>)`을 반드시 싣는다.** 서버가 이 값으로 결제의
  주인을 판단한다. **로그인 전에는 구매를 시작하지 않고**, 임의의 로컬 UUID를 만들지 않는다.
  이 값을 로그에 남기지 않는다
- **서버에 보내는 것은 `VerificationResult`의 `jwsRepresentation` 하나뿐이다.**
  수량 · 가격 · userId · 잔액 변화량을 보내는 자리가 없다.
  JWS를 `print` · analytics · 로컬 저장에 넣지 않는다(요청 본문에만 실린다)
- **잔액은 서버 응답을 대입만 한다.** `wallet.balance += amount`를 쓰지 않는다.
  `credited=false`(중복)도 실패가 아니고 그때도 `balance`는 정상 현재 잔액이다

#### `finish()` 계약 (가장 중요)

**서버가 지급을 확정한 뒤에만 `transaction.finish()`를 부른다.**

| 상황 | finish |
|---|---|
| `credited=true` | ✅ |
| `credited=false` (같은 거래 재전송) | ✅ — 서버가 확정한 상태다 |
| network 실패 · timeout · 5xx · 잘못된 응답 · 인증 실패 | ❌ |
| `.unverified` | ❌ (서버에 보내지도 않는다) |
| `appAccountToken`이 다른 사용자 | ❌ (원래 주인이 되찾아야 한다) |

먼저 finish하면 응답을 잃었을 때 StoreKit이 다시 주지 않아 **사용자가 돈만 내고 조각을 잃는다.**
그래서 실패는 거래를 미완료로 남기는 것으로 처리하고, UX도 "결제 실패"가 아니라
**"구매를 확인하고 있어요"**로 말한다.

#### 복구

- 앱 수명 동안 `Transaction.updates` listener를 **하나만** 만든다
- 로그인된 세션이 준비되면 `Transaction.unfinished`를 sweep한다 —
  앱 재시작 · 응답 유실 · 결제가 로그인보다 먼저 온 경우가 여기로 온다
- **`Transaction.currentEntitlements`를 consumable 복구에 쓰지 않는다** — 소모품은 거기 남지 않는다
- 세션이 없으면 거래를 **아무 사용자에게도 귀속하지 않는다.** 미완료로 남기고 로그인 뒤에 가져간다
- 몇 번 다시 보내도 지급은 한 번이다(서버 전역 멱등 B-6A). client도 불필요한 중복 요청은 줄인다

#### 조각 상점 화면 (B-6D)

진입점은 **둘**이고 **같은 시트**를 연다 — 상점 UI를 두 번 만들지 않는다.

| 진입 | 어디 |
|---|---|
| 홈 잔액 칩 탭 | `HomeView.header` — 생김새는 그대로 두고 탭만 받는다. 낭독기는 "보유 N 조각. 조각 구매" |
| AI 조각 부족 "조각 채우기" | `AIStickerPromptSheet` → `StickerCreatorView`가 AI 시트를 닫고 상점을 연다 |

- **기존 `inkBottomSheet`를 쓴다.** native `.sheet` · `presentationDetents` ·
  `fullScreenCover`를 새로 들이지 않는다
- UI-P1 규칙: `ScrollView` + `safeAreaInset(edge: .bottom)` + `InkSheetMetrics.actionClearance`
- 카드는 `ShardIcon` + "N 조각" + **`Product.displayPrice`**.
  가격 문자열을 코드에 적지 않는다(다른 나라에서 거짓말이 된다)
- 순서는 controller가 조각 수로 정렬한 것을 그대로 쓴다 — 10 / 50 / 100
- 상품 상태 셋: 불러오는 중 / 카드 / **실패 + 다시 시도**. StoreKit 오류 문자열을 그대로 보여주지 않는다
- 구매 중에는 **모든 카드를 잠근다**(연타 방지). 진행 중인 카드만 spinner
- **잔액은 `ShardWallet`이 들고 있는 서버 값**을 읽기만 한다. 화면에서 더하지 않는다
- 시트는 로그아웃 상태에서도 **볼 수 있다.** 구매를 누르면 기존
  `requireSignIn(for: .shardTransaction)` gate로 보내고 안내만 남긴다 —
  **새 auth flow도 새 로그인 UI도 만들지 않았다.**
  로그인 뒤 결제를 자동으로 이어가지 않는다(사용자가 상품을 다시 고른다).
  임의의 pending purchase 저장소를 만들지 않았다

`AIStickerPromptSheet`의 "N조각이 필요해요 (지금 2조각)" 문구는 **그대로 두고** CTA만 더했다.
값은 서버가 준 `price`라 정책이 바뀌면 문구가 따라간다.

#### Xcode StoreKit 테스트 ≠ Apple Sandbox (acceptance 구분)

`ggumirror/Ggumirror.storekit`은 **client pipeline / 로컬 복구 확인용**이다.
Debug scheme에만 연결한다(Edit Scheme → Run → Options → StoreKit Configuration).

**Xcode StoreKit Testing이 만든 JWS는 production backend가 거절한다** —
서명이 로컬에서 만들어져 Apple 신뢰 사슬이 없고, B-6B가 `Xcode` / `LocalTesting`
environment를 값 단계에서 버린다. 받아 주게 만드는 bypass · flag · 별도 endpoint를
**절대 추가하지 않는다**(`IAP_ALLOW_XCODE` · debug 검증 우회 · 무서명 허용 ·
로컬 전용 credit endpoint · client 직접 지급 전부 금지).

**⚠️ Xcode transaction으로 실제 조각 지급을 검증하지 않는다.**
`.storekit` 구매로 production 잔액이 늘어나면 그것은 성공이 아니라 **보안 실패**다.

| | Xcode StoreKit Testing | Apple Sandbox / TestFlight (B-6E) |
|---|---|---|
| 검증 대상 | client pipeline · 로컬 복구 | **실제 서버 fulfillment** |
| product 3개 load · displayPrice | ✅ | ✅ |
| 결제 흐름 진입 · appAccountToken 포함 | ✅ | ✅ |
| verified transaction 획득 | ✅ | ✅ |
| `updates` 전달 · `unfinished` 복구 · 중복 억제 · finish 타이밍 | ✅ | ✅ |
| **production backend가 JWS를 거절** | ✅ **기대 동작** | ❌ |
| ledger `iap_purchase` · wallet +10/+50/+100 | ❌ **0이어야 한다** | ✅ |
| `transaction.finish()` | ❌ 불리지 않는다 | ✅ |
| 거래 상태 | **unfinished로 남는 것이 정상** | finished |

로컬에서 서버가 거절하면 controller는 `finish()`하지 않고 거래를 미완료로 남긴다 —
그게 설계대로 동작한다는 증거다. 화면에는 "구매를 확인하고 있어요"가 남는다.

fake backend를 쓰는 client test에서 `verified → 성공 → finish`를 검증하는 것은
**client 상태 기계를 보기 위한 test seam**이고, production backend와 무관하다.

`ggumirrorTests/ShardPurchaseTests.swift`가 위 전부를 고정한다.

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
