# DESIGN.md

# Final Design Source of Truth

## Direction
Clean Pen Sketch.

- 한국어 UI
- 따뜻한 종이 질감 배경
- 검은 잉크 라인
- 사람이 그린 듯하지만 정돈된 UI
- cute but not childish
- 앱 크롬은 조용하게, 거울 디자인이 주인공

## Background
모든 일반 앱 화면에 subtle warm paper texture.
카메라 영상 자체에는 종이 질감을 덮지 않는다.

## Ink Style
- 약 1.4...2.1pt 수준의 line hierarchy
- 아주 미세한 손그림 떨림
- 약간 유기적인 모서리
- 실제 hit target geometry는 안정적으로 유지

## Typography — 브랜드 서체

앱 UI 글씨는 **개구(Gaegu) 하나로 고정**한다. 손그림 테두리만 두른 시스템 폰트 앱이 아니라,
글씨 자체가 UI의 일부여야 한다.

| 쓰임 | 파일 |
|---|---|
| 일반 UI | Gaegu-Regular |
| 제목 · 주요 CTA · 강조 | Gaegu-Bold |
| 아주 약한 보조 표현 | Gaegu-Light |

semantic token은 `InkFont` 하나뿐이다. 화면에서 `.font(.system(...))`이나
`.font(.custom(...))`을 직접 쓰지 않는다.

| token | 크기 | Dynamic Type 기준 | 쓰임 |
|---|---|---|---|
| `pageTitle` | 34 bold | largeTitle | 화면 최상단 제목 |
| `title` | 28 bold | title | 상세 화면 이름 |
| `cardTitle` | 22 bold | title3 | 카드 · 시트 제목 |
| `sectionTitle` | 19 bold | headline | 구역 머리말 |
| `body` | 19 | body | 본문 |
| `button` | 19 bold | body | 버튼 |
| `secondary` | 17 | subheadline | 보조 설명 |
| `caption` | 15 | caption | 작은 라벨 |
| `tab` | 14 | caption2 | 탭바 |
| `numeric` | 18 bold | body | 가격 · 개수 |
| `whisper` | 16 light | footnote | 아주 옅은 보조 |

- 전부 `relativeTo`를 갖고 있어 Dynamic Type을 그대로 따라간다.
- 폰트 파일을 못 찾으면 같은 semantic의 **시스템 한글 폰트로 떨어진다**. 글씨가 사라지지 않는다.
- 시스템이 통째로 그리는 UI(공유 시트 · 사진 선택 · 권한 알림 · 키보드)는 건드리지 않는다.
- UIKit이 그리는 네비게이션 제목만 `UINavigationBarAppearance`로 같은 서체를 맞춰 준다.

### 거울 장식 텍스트는 별개다

사용자가 거울에 넣는 글씨는 `TextFontStyle`이 담당하고 **11가지 중에서 고른다**
(기본 / 개구 3종 / 감자꽃 / 하이멜로디 / 주아 / 나눔붓 / 나눔펜 / 푸어스토리 / 싱글데이).
거울 글씨를 "나눔붓"으로 골라도 앱 버튼 글씨는 개구 그대로다.

폰트는 `CTFontManagerRegisterFontsForURL`로 **런타임 등록**하고 PostScript 이름은
파일에서 직접 읽는다 — 파일 이름과 실제 이름이 다르기 때문이다
(`NanumBrushScript-Regular.ttf` → `NanumBrush`).

## Paper

- 기본 배경 `#FCFBF6`. 따뜻한 off-white.
- 완전 평면이 아니라 아주 옅은 결이 있다. 씨앗이 고정돼 있어 **다시 그려도 같은 무늬**다 —
  스크롤할 때 반짝이지 않는다.
- 결이 먼저 눈에 보이면 실패다. 어두운 픽셀 비율 2% 미만을 유지한다.
- **카메라 영상 위에는 종이를 절대 덮지 않는다.** 실제 거울의 카메라 자리는 완전히 투명하다.

## Ink line

굵기는 `InkLine` 세 단계뿐이다. 화면마다 숫자를 적지 않는다.

| token | 값 | 쓰임 |
|---|---|---|
| `thin` | 1.3 | 구분선 · 작은 아이콘 |
| `regular` | 1.6 | 버튼 · 칩 · 입력 |
| `emphasis` | 1.9 | 카드 · 시트 |

**굵기를 랜덤하게 흔들지 않는다.** 손그림 느낌은 굵기가 아니라 모양으로 낸다.

## Corner

네 모서리 반지름을 일부러 조금씩 다르게 둔다. "손으로 상자를 그렸다" 정도의 어긋남이고,
**값이 고정**이라 다시 그려도 모양이 흔들리지 않는다. render마다 달라지는 jitter는 금지.

| preset | 반지름 (TL, TR, BR, BL) | 쓰임 |
|---|---|---|
| `InkCorner.card` | 20 · 24 · 25 · 19 | 카드 · 시트 |
| `InkCorner.control` | 16 · 13 · 17 · 12 | 버튼 · 입력 |
| `InkCorner.chip` | 15 · 12 · 16 · 13 | 칩 · 작은 라벨 |
| `InkCorner.badge` | 13 · 16 · 12 · 15 | 아이콘 배지 |

## Shadow

쓰지 않는다. 구분은 **종이 면 + 잉크 테두리 + 여백**으로만 한다.
카드가 떠 있는 Material 느낌이 나면 실패다.

## Component

| component | 규칙 |
|---|---|
| Button | 종이 면 + 잉크 테두리. Primary는 잉크로 채운다. 최소 44pt. |
| Card | `InkCard` — 종이 면 + `emphasis` 테두리 + `InkCorner.card`. 박스 안에 또 박스를 넣지 않는다. |
| Chip | `InkFilterBar` / `InkChip` / `InkToggleChip`. 선택은 잉크 채움으로만. |
| Input | 테두리만. 채워진 회색 배경을 쓰지 않는다. |
| Sheet | 시스템 시트를 쓰지 않는다. `inkBottomSheet` / `inkDialog` — 아래 **모달** 참고. |
| Tab | 종이 띠 + 잉크 테두리. 선택은 **작은 손그림 밑줄**(`InkUnderline`). 큰 알약 금지. |
| Separator | `InkSeparator` 1.2pt. |
| Empty state | 큰 SF Symbol 하나 대신 잉크 그림 + 문장. |

## Gallery card

2열. 거울 미리보기가 주인공이고, 아래 이름 · 가격 · 태그는 journal caption 크기로 조용히.
카드를 또 다른 테두리로 감싸지 않는다.

## Home
보유 거울 개수 / 설정 / 거울 보기 / 거울 꾸미기만 표시.

## Mirror Camera 화각

- 줌 없음. 기기 줌 1.0 고정 + 화각이 가장 넓은 format 선택.
- 배치는 `.resizeAspectFill` — **Camera Area를 꽉 채운다.**
  프레임 두께와 Camera Area 크기는 확정값이라 카메라 때문에 바꾸지 않는다.
- 촬영도 같은 규칙(aspect fill)이라 화면과 결과가 일치한다.

## Mirror
- camera is hero
- edge-to-edge
- 빈 가장자리 없음
- tap → controls
- auto hide
- Back만 navigation

## Store
- 2열 Gallery
- Store templates는 hand-drawn ink/doodle/sticker 감성
- 기본 거울보다 더 화려함
- 실제 손그림 24장이 한 세트로 보여야 한다. 24장이 공유하는 것:
  같은 바깥 테두리(여백 26px · 같은 모서리 · 같은 굵기), 같은 카메라 구멍 선,
  같은 떨림 함수와 2회 덧그리기, "좌우는 비우고 위·아래·모서리에 무게" 여백 정책.
  주제마다 바뀌는 것은 모티프와 **포인트 색 하나**뿐이다.
- 얼굴이 주인공이므로 장식이 덮는 면적은 장당 1.5% 안팎으로 유지한다.
- 종이 질감은 PNG에 굽지 않는다 — 앱의 종이 배경 위에 얹힌다.

## Basic Mirrors
단색 + subtle paper grain만.
초기 내 거울에 들어 있지 않고, 상점 "기본" 카테고리에서 무료로 받는다.

## Mirror Inner Corner
중앙 Camera Area의 안쪽 네 모서리는 같은 값으로 살짝 둥글다.
Master 1080 × 2340 기준 30px 하나만 정의하고 화면 크기로 환산한다.
실제 세로 거울처럼 부드럽게 — capsule 느낌은 금지.

## Editor (Free Canvas)
거울 한 장(1080 × 2340)이 통째로 보이는 하나의 캔버스.
밝은 paper chrome + ink controls.

- 상/하/좌/우 선택 UI 없음
- Camera Area는 아주 옅은 dashed rounded line 하나로만 표시 (secondaryInk, 낮은 opacity)
- Editor에서는 Camera Area도 배경색으로 채워 연속된 한 장처럼 보인다
- 안내선은 "여기가 카메라"라는 정보일 뿐, 금지 구역처럼 보이면 안 된다
- 첫 진입 1회만 짧은 안내 문구

### 그리기 ↔ 손바닥 컨트롤
- 그리기 도구를 골랐을 때만 캔버스 바로 아래(그리기 설정 바 왼쪽)에 나타난다.
- 잉크 세그먼트 둘 — `pencil` / `hand.raised`. 선택은 잉크 채움으로만 표시한다.
- 각 칸 최소 44pt. 손이 가장 잘 닿는 자리에 두고, 떠 있는 카드나 모달로 만들지 않는다.
- 지금 한 손가락이 무엇을 하는지가 한눈에 보여야 한다 — 상태를 숨기지 않는다.

## Sticker Creator

거울 Editor와 **같은 화면 언어**다. 새 visual system을 만들지 않았다 —
종이 · 잉크 · 개구, 같은 툴바 모양, 같은 커스텀 시트/다이얼로그.

| 자리 | 내용 |
|---|---|
| 위 | 취소 · "스티커 만들기" · 저장 |
| 가운데 | 캔버스 |
| 아래 | 사진 · 그리기 · 스티커 · 텍스트 · 레이어 |

### 캔버스 — 1024 × 1024

스티커는 **정사각 1024 × 1024**다(`StickerCanvas.size`). 거울의 1080 × 2340을 쓰지 않는다.
어느 앱에 붙여도 비율이 어긋나지 않고, 최종 PNG도 같은 크기다.

비율에 의존하는 계산만 캔버스 종류를 본다: viewport 변환 · 스티커 높이 · 텍스트 레이아웃.
나머지(엔진 · 제스처 · 실행 취소 · 렌더러)는 거울과 **같은 코드**다.

### 투명 표시

편집 화면에만 아주 옅은 체크무늬를 깐다(잉크 0.045, 한 칸 = 캔버스 폭의 1/16).
회색이 강하면 종이·잉크 UI와 싸운다.

**이 무늬는 최종 PNG에 절대 들어가지 않는다.** 편집 화면의 안내선 · 선택 표시 · 툴바도 마찬가지다.
저장은 `StickerRenderer`가 아무 바탕도 없는 컨텍스트에 장식만 다시 그린다.

### 제스처

거울과 완전히 같다 — 새로 배울 것이 없다.
확대 1…4 · pinch = 확대 · 손바닥 모드 = 한 손가락 화면 이동 · 맞춤 = 캔버스 전체 ·
그리기 모드 = 한 손가락 획 · 오브젝트 드래그 = 이동 · 360° 회전 handle.
확대 · 이동 · 맞춤은 실행 취소에 쌓이지 않는다.

### 출력 분리

| | 편집 화면 | 최종 PNG |
|---|---|---|
| 체크무늬 | 보인다 | **없다** |
| 종이 배경 | 없음(투명 캔버스) | 없다 |
| 안내선 · 선택 표시 · 툴바 | 보인다 | **없다** |
| 장식(사진 · 두들 · 텍스트 · 그리기) | 보인다 | 그대로 |

같은 함수(`MirrorRenderer.draw`, `canvas: .sticker`)를 지나므로 위치 · 크기 · 회전 · 투명도 ·
순서 · 글꼴 · tint가 편집 화면과 다를 수 없다.

## My Mirrors Empty State
Clean pen sketch. 거울 아이콘 + 안내 문구 + [상점 둘러보기] 하나.
아직 없는 기능은 버튼으로 만들지 않는다.

## Account (설정)

설정 맨 위 "계정" 칸. 두 가지 상태만 있다.

**로그아웃**

- "꾸미기는 로그인 없이 계속 쓸 수 있어요." + 계정이 나중에 왜 필요한지 한 줄
- Apple 공식 `SignInWithAppleButton` (`.signIn` / `.black` / 높이 48)

**로그인됨**

- 아바타 + 이름 + 이메일 + "Apple 계정으로 로그인됨"
- 이름을 못 받았으면 "Apple 계정"으로 표시한다. 이메일이 없으면 그 줄을 아예 그리지 않는다.
- [로그아웃]

### 공식 버튼은 예외다

Sign in with Apple 버튼만은 **Apple 공식 control을 그대로 쓴다.**
개구 서체나 잉크 테두리로 다시 그리지 않는다 — Apple 지침 위반이고, 사용자도 못 알아본다.

손그림 스타일은 버튼 **바깥**에만 적용한다: 감싸는 InkCard / 설명 문구 / 구분선 / 로그아웃 버튼.

로그인 실패 알림은 종이 alert 하나로 짧게. **취소는 알림을 띄우지 않는다.**

## 제품 아이콘 — 거울 · 조각

앱 아이콘 전체를 바꾸지 않는다. **제품을 가리키는 둘만** 직접 그린다
(`Shared/InkProductIcons.swift`). 나머지(홈 / 상점 / 도구 / undo …)는 지금 것을 쓴다.

**거울** — 세로로 긴 프레임(가로 = 높이 × 0.6) + 유리에 비친 빛 두 줄.
- 비친 빛이 "거울"을 만든다. 없으면 그냥 둥근 사각형이다.
- 반짝임 십자는 넣지 않는다 — 사각형 안의 십자는 **"추가(+)"로 읽힌다.**

**조각** — 뾰족한 끝을 가진 비대칭 파편 + 유리 결 한 줄. 13pt에서도 읽혀야 한다.
읽히면 안 되는 것과 그 원인:

| 잘못 읽힘 | 원인 |
|---|---|
| 동전 · 다이아몬드 · 보석 | 좌우 대칭 / 변 길이가 고르다 |
| 깃발 · 찢어진 종이 | 톱니가 규칙적으로 반복된다 |
| 커서 · 위치 핀 | 아래 가운데가 V로 파이고 위가 한 점으로 모인다 |
| 왕관 | 위쪽에 파인 자리가 둘 |

→ 파편은 **변 길이의 불균형**으로 만든다. 긴 위쪽 변 + 아래로 모이는 뾰족한 끝 +
한 번 꺾인 왼쪽 변. 어느 축으로도 대칭이 없다.

둘 다 좌표가 **고정값**이다. 난수로 떨지 않는다. 선 굵기는 크기에 비례하고 최소값이 있다.

## 모달 — Bottom Sheet · Dialog

시스템 `.sheet` / `.confirmationDialog` / `.alert`을 앱 안에서 걷어냈다
(`Shared/InkModal.swift`).

| 종류 | 자리 | 쓰는 곳 |
|---|---|---|
| `inkBottomSheet` | 아래에서 올라온다 | 고를 것이 많거나 스크롤이 있는 화면 |
| `inkDialog` | 화면 가운데 | 짧은 선택 · 확인 · 경고 |

- 종이 면 + 잉크 테두리. 시트는 위 모서리만, 다이얼로그는 네 모서리가 둥글다.
- 손잡이는 손으로 그은 선 하나. 시스템 알약이 아니다. 다이얼로그에는 없다.
- dim은 회색이 아니라 잉크가 옅게 번진 색(`ink 0.28`). **아래 화면 탭을 막는다.**
- 높이는 `InkSheetSize` — `.content`(내용만큼, 86% 상한) / `.fraction`(정해진 비율).
  **높이는 한 번만 준다.** `maxHeight`를 준 뒤 `.infinity`로 덮으면 카드가 화면 전체를
  차지하고 내용이 위로 붙는다(아래에 빈 종이가 남는 증상). 회귀 테스트로 막아 뒀다.
- 카드는 아래 safe area를 지키고, 종이 면만 그 아래까지 내려간다.
- Dialog 버튼 역할 셋 — primary(잉크 채움) / secondary(테두리) / destructive(굵은 테두리).
  셋 이상이면 세로로 쌓는다.

### 움직임 — easeInOut 하나

`InkMotion`이 유일한 출처다. **easeInOut 0.26초**, spring 없음.
시트는 아래에서 밀려 올라오고, 다이얼로그는 0.94 → 1로 커지며 나타난다. 퇴장은 그 반대.

### 시스템 UI는 흉내 내지 않는다
Sign in with Apple 공식 버튼 · PhotosPicker · fileImporter · ShareLink · 권한 알림.

## 고정 appearance (Light/Dark 분기 없음)

꾸미러는 시스템 Light/Dark를 따라가지 않는다. 언제나 종이 + 잉크 한 벌이다.

- 화면에서 `@Environment(\.colorScheme)`로 색을 갈라 쓰지 않는다.
- **`Shape`에 `.fill()`을 반드시 준다.** 채우지 않은 Shape는 상속된 foreground
  (시스템 primary — 라이트에서 검정, 다크에서 흰색)로 칠해진다.
  Draw / Hand 컨트롤이 라이트 모드에서 "검은 배경 + 검은 아이콘"으로 사라졌던 원인이다.

### Draw / Hand 컨트롤

| 상태 | 배경 | 아이콘 |
|---|---|---|
| 선택 | `ink` | `paper` |
| 비선택 | `subtleSurface` | `ink` |

두 조합 모두 대비가 크고, 시스템 설정과 무관하게 늘 같다. 컨트롤 바깥 테두리 면도 채운다.

## Doodle Asset Visual Grammar

꾸미러의 스티커와 제품 아이콘은 **같은 펜**으로 그린다. 서로 다른 세트처럼 보이면 실패다.
좌표는 `DoodleStroke`, 굵기·끝모양은 `DoodleInk` 한 곳에서만 정한다.

| 항목 | 규칙 |
|---|---|
| line | 검은 잉크 단일 굵기. 자로 그은 직선을 쓰지 않는다 |
| weight | 바깥선 = 상자의 7.5%, 내부 디테일 = 5.5%. 최소 1.1pt |
| irregularity | 마주보는 변을 평행하게 두지 않는다. 좌우 대칭을 일부러 조금 깬다 |
| corner | 이음은 둥글지만 **모서리는 살아 있다**. 각이 필요한 것은 `.poly`/`.shape`, 곡선은 `.line`/`.loop` |
| fill | 기본은 outline. 채움(`.fill`/`.blob`/`.disc`)은 아주 작은 강조에만 |
| color | 검은 잉크가 지배. 강조색은 muted 5색(`DoodleAccent`)에서만, 스티커 6개까지 |
| detail | 획 2~5개. 작아지면 실루엣으로 읽힌다 |
| small size | 16pt에서도 무엇인지 읽혀야 한다 |
| determinism | 좌표는 **고정값**. render마다 흔들지 않는다 — hit target도 흔들리면 안 된다 |

PNG로 굽지 않는다. 스티커는 캔버스에서 크게도 작게도 쓰이므로 어느 배율에서나 같은 선이어야 한다.
picker 미리보기 · 실제 거울 · Capture가 **모두 `DoodleInk.draw` 한 함수**를 지난다.

Reference(`docs/design-references/doodle-system/`)에서 가져온 것은 **재료**뿐이다 —
특정 아이콘 / 캐릭터 / game asset을 베끼지 않는다.

### Sticker categories

42종. 갈래는 정확히 하나씩이다.

| 갈래 | 수 | 스티커 |
|---|---|---|
| 러블리 | 10 | 하트 · 작은 하트 · 하트 둘 · 날개 하트 · 리본 · 매듭 리본 · 편지 · 꽃 · 데이지 · 체리 |
| 반짝 | 8 | 반짝 · 별 · 별무리 · 달 · 구름 · 해 · 번개 · 불꽃 |
| 다이어리 | 8 | 연필 · 펜 · 체크 · 화살표 · 테이프 · 핀 · 메모 · 클립 |
| 재미 | 8 | 웃는 얼굴 · 찡그린 얼굴 · 고양이 · 토끼 · 유령 · 왕관 · 풍선 · 케이크 |
| 심볼 | 8 | 플러스 · 엑스 · 느낌표 · 물음표 · 동그라미 · 물결 밑줄 · 휜 화살표 · 모서리 장식 |

강조색이 있는 6종(체리·꽃·해·구름·풍선·케이크)은 **색이 실루엣의 일부**라 tint를 지원하지 않는다.
나머지 36종은 잉크색이고 사용자가 색을 바꿀 수 있다.

### 그릴 때 걸린 함정 (기록)

- 곡선으로만 이으면 상자·지우개가 **콩**처럼 뭉갠다 → 각이 필요한 곳은 직선 획
- 꽃잎이 가운데에서 떨어져 있으면 **씨앗**으로 읽힌다
- 동그라미 다섯 개를 두르면 **포도알**이 된다 → 데이지는 꽃잎 + 줄기
- 구름을 한 덩어리로 그리면 **조약돌**이다 → 위는 봉우리, 아래는 평평
- 불꽃 끝이 둥글면 **아몬드**다 → 끝을 뾰족하게
- 좁은 두 겹을 곡선으로 이으면 **타원**으로 붙는다 → 클립은 각을 살린다
- 원 + 막대는 **막대사탕**이다 → 핀은 기울어진 머리판 + 바늘
- 채움만 있고 테두리가 없으면 그냥 **원**이다 → 풍선은 채움 + 잉크 테두리

## Product Icon rules

제품을 가리키는 **네 개**만 직접 그린다(`DoodleProductIcon`): 거울 · 조각 · 홈 · 상점.
나머지 아이콘은 지금 쓰는 것을 그대로 둔다. 스티커와 같은 펜을 통과한다.

| 아이콘 | 규칙 | 실패 |
|---|---|---|
| 거울 | 세로 프레임 + 비친 빛 두 줄 + 손잡이 | 스마트폰 · 둥근 사각형 |
| 조각 | 변 길이가 모두 다른 파편 + 결 한 줄. 대칭축 없음 | 동전 · 다이아몬드 · 깃발 · 커서 · 왕관 |
| 홈 | 지붕이 반듯하지 않고 문이 조금 삐뚤다 | 시스템 `house` |
| 상점 | 물결 차양 + 몸통 + 문 | 카트 |

16 / 20 / 24 / 28 / 32pt에서 전부 확인한다. 아이콘만 있는 버튼에는 `accessibilityLabel`을 준다.

## Legacy Sticker compatibility

예전 기본 제공 스티커(`BuiltInSticker`, SF Symbol 기반)는 **지우지 않는다.**

- picker에 나오지 않는다. 새로 만들 수도 없다
- 예전에 저장한 거울을 그리기 위해서만 남는다 — case를 지우면 그 거울에서 스티커가 사라진다
- `rawValue`는 저장 식별자라 절대 바꾸지 않는다
- 두들과는 `StickerSource`의 `kind`로 구분된다(`doodle` / `builtIn`)
- 스티커 종류가 늘었으므로 저장 형식은 **schemaVersion 3**이다. v1 · v2 파일은 그대로 읽힌다

## Accessibility
- 최소 44pt tap target
- Dynamic Type
- VoiceOver
- 충분한 contrast
- 작은 iPhone / 큰 iPhone 확인

## Prototype Reference
최종 Claude Design 파일:
docs/claude-design/Mirror App v2.dc.html

HTML을 WebView로 포함하지 않고 SwiftUI 구현의 visual/interaction reference로만 사용.
