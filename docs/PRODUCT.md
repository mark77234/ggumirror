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

## Basic Mirrors
White / Black / Cream / Soft Pink / Lavender / Sky / Mint / Gray.
기본 거울은 단색 프레임 + 은은한 종이 질감만 사용.

## Store
- 2열 Gallery.
- 상점 템플릿은 사람이 직접 그린 듯한 ink/doodle/sticker/journaling 감성.
- Preview / 이름 / Creator / 가격.
- 상세의 1순위 CTA는 “내 거울로 미리보기”.

## My Mirrors
2열 Gallery.
Actions: 적용 / 꾸미기 / 복제 / 삭제 / 상점에 올리기.

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
