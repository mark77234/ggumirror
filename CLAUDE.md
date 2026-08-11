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

## Git / Verification

기능 완료 후 commit 전:

- build
- tests
- relevant regression tests

를 실행한다.

Client 변경은 Client repository에서만 commit한다.
