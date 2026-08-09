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

## Editor
기존 Prototype interaction 유지.
Overview / 4-side detail / corner continuity / minimap.
밝은 paper chrome + ink controls.

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
