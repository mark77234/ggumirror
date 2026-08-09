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
Phase 1에서는 로컬 샘플 1개만.
- transparent overlay
- touch 차단
- 화면 프레임에 정렬
- Decoration On/Off
- 비균등 Stretch 금지

Editor는 아직 만들지 않음.

### 5. Controls
- 탭하면 표시
- inactivity 후 숨김
- slider 조작 시 timer reset
- Prototype 기준 약 4.2초

### 6. Zoom
AVCaptureDevice.videoZoomFactor 사용.
기기 지원 범위 내 clamp.

### 7. Brightness
Mirror 밝기는 카메라 exposure가 아니라 화면 밝기로 취급.
- Mirror 진입 전 brightness 기억
- Mirror에서 조절
- 적절한 시점에 원래 밝기 복원

### 8. Freeze
권장:
- VideoDataOutput에서 latest frame 확보
- Freeze 시 최신 프레임을 live preview 위에 overlay
- Unfreeze 시 제거
- camera session은 계속 유지해서 재시작 지연 방지

### 9. Capture
현재 거울 화면 캡처.
최종적으로 decoration 포함 결과를 저장할 수 있어야 함.

### 10. Back → Home
첫 시작은 Mirror.
Back → Home.

Phase 1의 Home은 routing 검증만 가능하면 됨:
- 거울 개수
- 설정 placeholder
- 거울 보기
- 거울 꾸미기 placeholder

## Phase 1 Definition of Done
실제 iPhone에서 전부 확인:
- cold launch → Mirror
- 권한 거부 시 crash 없음
- 권한 허용 → front camera
- mirrored preview
- edge-to-edge, 빈 테두리 없음
- decoration overlay 정렬
- tap controls
- auto-hide
- zoom
- brightness
- freeze/unfreeze 반복
- capture
- decoration toggle
- Back → Home
- Home → Mirror 재진입
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
4. `feat(mirror): add freeze brightness zoom and capture`
5. `test(mirror): validate phase one device flows`

## Later
Phase 2: Home + Design System
Phase 3: Editor Canvas
Phase 4: Drawing / Sticker / Photo tools
Phase 5: Persistence + My Mirrors
Phase 6: Apple Login + Store + 조각
