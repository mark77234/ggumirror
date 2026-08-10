# PRODUCT.md

# Mirror Customizing App — Product Requirements

## Core
- 앱 실행 직후 첫 화면은 Mirror Camera.
- Mirror는 전면 카메라 + 좌우 반전 + edge-to-edge.
- 앱 전체 Portrait only. Landscape 대응 없음.
- Home에는 보유 거울 개수, 설정, 거울 보기, 거울 꾸미기만 표시.
- 거울 꾸미기 → 현재 사용 중인 거울 Editor로 즉시 진입.
- Main Tab: 홈 / 상점 / 내 거울.
- Mirror는 immersive full-screen. Tab Bar를 표시하지 않는다.

## Mirror (확정)
Mirror 화면의 액션은 **홈으로 / 촬영** 둘뿐이다.

- 기본 상태: Camera + Decoration만. 다른 UI 없음.
- 화면 탭 → 홈으로 + 촬영 표시.
- 마지막 interaction 후 4.2초 → 다시 숨김.
- 다시 탭하면 재표시.
- 홈으로 → Home.
- Decoration은 항상 표시. On/Off 없음.
- Freeze 없음. Zoom 없음. 화면 밝기 조절 없음.

## Capture (확정)
- 촬영 결과 = 지금 보고 있는 세로 Mirror 화면 그대로.
- 화면과 동일한 crop / 좌우 반전 / Decoration 위치 / 화면 비율.
- 결과는 항상 Portrait. orientation metadata가 아니라 실제 pixel 기준.
- 화면 screenshot이 아니라 원본 camera frame + Decoration을 합성한다.
- transient controls(홈으로, 촬영 버튼 등)는 결과 이미지에 포함하지 않는다.
- 저장은 Photos. 사진 추가 권한(add-only)만 사용한다.

## Editor
- 하나의 연속된 Mirror Canvas.
- 위 / 오른쪽 / 아래 / 왼쪽 4면 편집.
- 네 밴드 전체가 tap target.
- Corner continuity, minimap.
- Drawing, Brush, Undo/Redo.
- Photo → Background Removal → Sticker.
- Move / Resize / Rotate / Flip / Duplicate / Lock / Opacity.
- Text, Frame, Background Color, Layers, Preview, Save.
- 위치/크기는 0...1 normalized coordinate 우선.

## Editor Workspace (Side Detail)
- Left / Right 프레임을 고르면 그 밴드가 **화면 가로 중앙 근처**에 온다.
- 바깥쪽에 생기는 여백은 **Editor Workspace Gutter** — 편집용 공간이고 MirrorDesign이 아니다.
- Gutter는 Side Detail 화면에만 있다. Preview / 홈 미리보기 / 실제 Mirror / Capture에는 존재하지 않는다.
- Gutter 위에서는 그리기도 스티커 배치도 되지 않는다. 손가락을 놓을 자리일 뿐이다.
- 빈 공간 정책: 의도하지 않은 빈 공간은 여전히 금지. 밴드를 중앙에 놓기 위한 gutter만 geometry로 정확히 허용한다.
- Left / Right는 정확히 대칭이고, "맞춤"은 이 중앙 배치 상태로 되돌린다.

## Sticker
- 기본 제공 스티커는 카테고리(전체 / 하트 / 리본 / 반짝임 / 꽃 / 두들)로 나눠 고른다.
- 단색 template 스티커는 색을 바꿀 수 있다. 기본값은 잉크색.
- 사진 스티커처럼 원본 색을 유지해야 하는 스티커는 색 변경을 지원하지 않는다.
- 스티커를 옮기는 동안에는 아주 약한 촉각 피드백만 준다. 프레임마다 울리지 않고 시간·이동 거리로 제한한다.
- 배치가 끝나면 `완료`로 선택을 해제한다. 선택 해제 시 한 번 더 또렷한 피드백을 준다.
- 이미 놓은 스티커는 다시 탭해서 선택하고 계속 편집할 수 있다. 잠긴 스티커도 선택은 된다.
- 선택은 항상 하나다. 다른 스티커를 고르면 이전 선택은 풀린다.
- 재선택 시 스티커가 이미 충분히 보이면 화면을 움직이지 않는다. 화면 밖이면 배율을 유지한 채 최소한만 끌어온다.
- 회전하거나 작은 스티커도 눈에 보이는 자리를 누르면 잡힌다 (최소 tap target 44pt).
- 스티커 도구에서는 빈 곳을 한 손가락으로 끌면 화면이 움직인다. 그리기 / 지우개의 한 손가락 동작은 그대로다.
- 제스처 우선순위: 크기·회전 handle → 스티커 → 스크롤바 → 빈 캔버스 / Gutter(화면 이동).

## Mirror Frame 규격 (MVP 확정)
- 모든 거울의 프레임 두께는 동일하다.
- Master 1080 × 2340 기준 좌우 108px(0.10) / 상하 180px(약 0.0769).
- 중앙 Mirror Area 크기도 모든 거울에서 같다 (864 × 1980).
- 중앙 Mirror Area의 안쪽 네 모서리는 같은 값으로 살짝 둥글다 (Master 기준 30px). capsule처럼 과하지 않다.
- 이 모서리는 렌더 / FrameMask / 그리기 제한 / 스티커 제약 / 실제 Mirror / Capture가 모두 같은 geometry를 쓴다.
- 사용자가 프레임 두께를 바꾸는 기능은 없다.
- 상점 거울의 가치는 두꺼운 프레임이 아니라 같은 공간 안의 artwork 밀도로 만든다.

## Basic Mirrors
White / Black / Cream / Soft Pink / Lavender / Sky / Mint / Gray.
단색 프레임 + 은은한 종이 질감만 사용.
이 8종은 **내 거울에 미리 들어 있지 않다.** 상점의 "기본" 카테고리에서 무료(0 조각)로 받는다.

## Default Mirror
- 앱을 처음 설치하면 내 거울은 비어 있다.
- 그래도 바로 거울을 쓸 수 있도록 크림색 기본 거울 하나가 적용된 상태로 시작한다.
- 이 기본 거울은 내 거울 목록에 없고, 보관 슬롯도 쓰지 않으며, 구매한 템플릿도 아니다.
- 단순한 system fallback / 초기 적용값이다.

## Store
- 2열 Gallery.
- 상점 템플릿은 사람이 직접 그린 듯한 ink/doodle/sticker/journaling 감성.
- Preview / 이름 / Creator / 가격.
- 상세의 1순위 CTA는 “내 거울로 미리보기”.
- 공식 기본 단색 템플릿 8종은 **항상 무료**다.
- Creator 템플릿은 0...N 조각으로 판매자가 값을 정한다. 무료 배포도 가능하다.
- 무료 템플릿은 바로 받아 내 거울에 담긴다. 조각 결제와 서버 ledger는 향후 Store Phase.

## My Mirrors Empty State
- 초기 내 거울은 0개, "내가 만든 거울 0 / 3".
- 빈 화면 대신 안내를 보여준다: "아직 저장한 거울이 없어요 / 상점에서 거울을 받아보거나 직접 만들어보세요".
- 지금 실제로 되는 동작만 노출한다 — [상점 둘러보기].

## My Mirrors
2열 Gallery.
Actions: 적용 / 꾸미기 / 복제 / 삭제 / 상점에 올리기.

## Mirror 저장 / 보관
- 저장할 때 거울 이름을 정한다. 이름은 최대 24자.
- 내가 만든 거울을 다시 꾸며 저장하면 같은 거울을 덮어쓴다.
- 기본 제공 / 구매한 거울을 꾸며 저장하면 원본은 그대로 두고 **새 거울**로 저장된다.
- 보관 공간(슬롯)은 **내가 만든 거울만** 차지한다. 상점에서 받은 기본 / 구매한 거울은 차지하지 않는다.
- 무료 보관 공간은 3칸이다.
- 보관 공간이 가득 차면 새 거울 저장을 막고, 공간을 늘리라고 안내한다. 기존 거울 덮어쓰기는 계속 된다.
- 보관 공간 확장은 조각으로 구매한다. 1회 구매 시 5칸. **가격은 미정이고, 아직 조각을 차감하지 않는다.**
- 보관 공간과 조각은 서로 다른 개념이다. 공간을 늘려도 조각 잔액 계산은 별도다.

## Store Upload
새 거울 만들기와 꾸미기는 무료.
상점 공개 등록 비용은 20 조각.

## Currency
- 개념 이름: 거울조각
- UI 이름: 조각
- 아이콘: 5각형 깨진 거울 파편 + 반사선 2개 + 잉크 아웃라인
- 획득: 출석 +1, Rewarded Ad +1(하루 최대 5), IAP 10/50/100
- MVP 현금 출금 없음.

## Authentication
- 핵심 기능은 로그인 없이 사용.
- Apple 로그인만 지원.
- Store 이용 시점에만 로그인 요구.

## External Template
- MVP: 전체 프레임 PNG 1장.
- 1080 × 2340, 9:19.5, transparent PNG.
- 중앙 Mirror Area transparent.
- 앱 내부에서 TOP/RIGHT/BOTTOM/LEFT 영역 계산.
- 비균등 Stretch 금지, Uniform Scale + Crop/Extend.
