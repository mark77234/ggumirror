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

## Typography
한국어 가독성 우선.
Prototype의 Gaegu는 visual reference.
본문 전체를 손글씨 폰트로 강제하지 말고 실제 iOS에서는 시스템 한글 폰트를 기본으로 검토.

## Home
보유 거울 개수 / 설정 / 거울 보기 / 거울 꾸미기만 표시.

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

## My Mirrors Empty State
Clean pen sketch. 거울 아이콘 + 안내 문구 + [상점 둘러보기] 하나.
아직 없는 기능은 버튼으로 만들지 않는다.

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
