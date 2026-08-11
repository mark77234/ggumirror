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
| Sheet | `paperSheet()` 하나로 통일. 표시 표면 전체(좌·우·아래 safe area 포함)를 종이가 덮는다. |
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
