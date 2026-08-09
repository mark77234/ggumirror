# IMPLEMENTATION_PLAN.md

# Native iOS Implementation Plan

## Phase 0 — Foundation
- docs/ 고정
- PRODUCT.md
- DESIGN.md
- IMPLEMENTATION_PLAN.md
- MIRROR_CREATOR_TEMPLATE_GUIDE.md
- Claude Design 최종 export 저장
- Git baseline commit
- 폴더 구조 생성
- Camera permission 설정

## Phase 1 — Native Mirror Foundation

### Goal
실제 iPhone에서:
App Launch → Mirror Camera → Back → Home

### 1. Camera
AVFoundation:
- AVCaptureSession
- front AVCaptureDevice
- AVCaptureDeviceInput
- Preview
- 필요 시 AVCaptureVideoDataOutput

### 2. Mirroring
- 전면 카메라 좌우 반전
- 화면 회전 후에도 상태 유지

### 3. Edge-to-edge
- Camera preview는 safe area 무시
- resizeAspectFill
- 네 가장자리 빈 공간 금지
- UI 버튼만 safe area 고려

### 4. Decoration Overlay
항상 표시한다. On/Off 토글은 제품에서 제외.

- transparent overlay
- 터치를 가로채지 않음
- 화면 프레임에 정렬
- 비균등 Stretch 금지 (Uniform Scale + Crop)
- 프레임/배경은 물리적 화면 끝까지 채우고 중앙 Mirror Area만 투명

Editor는 아직 만들지 않음.

### 5. Controls
Mirror의 액션은 **홈으로 / 촬영** 둘뿐이다.

- 기본 상태에는 아무 컨트롤도 보이지 않음
- 탭하면 표시
- 마지막 interaction 후 약 4.2초에 숨김
- 다시 탭하면 재표시

### 6. Portrait only
- 앱 supported orientation은 iPhone Portrait 하나
- camera preview와 frame pipeline 모두 Portrait 고정
- Landscape 대응 없음

### 7. Capture
사용자가 보고 있는 완성된 거울 화면을 이미지로 만든다.

- 원본 camera frame + Decoration 합성 (화면 screenshot 아님)
- 화면과 동일한 crop / 좌우 반전 / Decoration 정렬 / 화면 비율
- 결과는 실제 pixel 기준 Portrait
- transient controls는 결과에 포함하지 않음
- Photos 저장은 add-only 권한만 사용, 거부 시 crash 없이 안내

### 8. Home Routing
첫 시작은 Mirror.

- Mirror 탭 → 홈으로 → Home
- Home → 거울 보기 → Mirror
- Mirror에는 Tab Bar를 표시하지 않음

Phase 1의 Home은 4개만 표시:
- 보유 거울 개수
- 설정 (placeholder)
- 거울 보기
- 거울 꾸미기 (UI만)

## 제품에서 제외한 것
실기기 검증 후 Mirror에서 제외하기로 확정.

- Freeze / 화면 고정
- Zoom
- 화면 밝기 조절
- Decoration On/Off

## Phase 1 Definition of Done
실제 iPhone에서 전부 확인:
- cold launch → Mirror
- 권한 거부 시 crash 없음
- 권한 허용 → front camera
- mirrored preview
- edge-to-edge, 빈 테두리 없음
- decoration overlay 정렬, 중앙만 투명
- tap → 홈으로 / 촬영 표시
- 4.2초 auto-hide, 재탭 시 재표시
- Portrait 고정 (기기를 눕혀도 회전하지 않음)
- capture 결과가 화면과 동일 (crop / 좌우 반전 / decoration / 비율)
- capture 결과가 Photos에서 Portrait
- 사진 권한 거부 시 crash 없이 안내
- 홈으로 → Home
- Home → 거울 보기 → Mirror 재진입
- Mirror에 Tab Bar가 보이지 않음
- background/foreground 후 session 정상
- main thread camera configuration warning 없음

## Phase 1에서 하지 않는 것
- Editor
- Drawing
- Photo background removal
- Layers
- Store backend
- Apple login
- 조각 economy
- Firebase
- Marketplace

## Suggested Commits
1. `chore(ios): establish handoff docs and project structure`
2. `feat(camera): add mirrored front camera preview`
3. `feat(mirror): add controls and decoration overlay`
4. `feat(mirror): add portrait capture and photo save`
5. `feat(home): add home routing`
6. `test(mirror): validate phase one device flows`

## Phase 3-3A — Side Detail Pan (다음 Phase 최우선)

현재 Left / Right Side Detail은 확대 배율이 고정이라
프레임 전체 높이를 편집할 수 없다. 다음 Phase에서 반드시 해결한다.

- Left / Right에서 상단 → 중간 → 하단까지 세로 pan / scroll
- Top / Bottom도 편집 영역이 화면보다 크면 같은 축으로 이동 허용
- 확대 배율은 유지
- Canvas 바깥 빈 공간이 보이지 않게 clamp
- Mini Map viewport가 실제 위치를 따라 이동
- Drawing / Sticker 모두 같은 viewport / pan 구조를 사용
- 기존 SideDetailTransform을 기반으로 구현 (임시 scroll 구조를 새로 만들지 않는다)

## Advanced Drawing Polish (후속)

MVP Editor가 끝난 뒤 진행한다. 지금은 현재 renderer로 표현 가능한
preset(가는 펜 / 기본 펜 / 연필 / 마커 / 형광펜)만 쓴다.

- 종이 질감 graphite pencil
- 크레용 / 오일 브러시 / 수채 느낌
- textured brush stamp engine
- 필압 기반 가변 굵기 (Apple Pencil 포함)
- 더 풍부한 팔레트, 최근/즐겨찾는 색

## Editor Coach Mark Tutorial (후속)

Editor 기능이 전부 완성된 뒤에 만든다.
지금은 Overview 프레임 선택 힌트 + Side Detail 제스처 힌트만 유지하고,
onboarding state machine은 만들지 않는다.

순서 예:

1. Overview — "상·하·좌·우 중 꾸미고 싶은 프레임을 선택해주세요"
2. Side Detail — "한 손가락으로 그릴 수 있어요"
3. Scroll Handle — "스크롤바를 움직여 프레임 전체를 꾸며보세요"
4. Pinch Zoom — "두 손가락으로 확대·축소할 수 있어요"
5. Drawing Settings — "펜과 색상, 굵기를 바꿀 수 있어요"
6. Sticker 구현 후 — 추가 / 이동 / 크기 안내
7. Preview / Save — 완성 확인과 저장 안내

방식:

- 실제 UI 위 Coach Mark, 설명 중인 control만 강조
- 전체 화면을 과도하게 가리지 않음
- Skip 가능
- 한 번 완료하면 반복 노출하지 않음
- 설정에서 다시 보기는 후속 검토

## Later
Phase 2: Home + Design System
Phase 3: Editor Canvas
Phase 4: Drawing / Sticker / Photo tools
Phase 5: Persistence + My Mirrors
Phase 6: Apple Login + Store + 조각
