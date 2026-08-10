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

## Phase 3-3E — Free Canvas Mirror Editor (확정, 최신)

Editor의 핵심 편집 방식을 바꿨다. **아래 정책이 기존 4면 Side Editing보다 최신이다.**

- Editor는 1080 × 2340 거울 한 장을 통째로 편집한다. 상/하/좌/우 선택 단계 없음.
- Camera Area는 **안내용 점선**이다. 장식 금지 구역이 아니다.
- 배경 Layer만 Camera Area를 비운다. 장식 Layer는 캔버스 전체를 쓴다.
- 실제 Mirror 레이어: 카메라 → 프레임 배경 → 그림 → 템플릿 장식 → 스티커.
- 표준 inset이 **108 / 108 / 180 / 220**으로 바뀌었다 (아래를 조금 더 두껍게).

제거한 것

- `EditorSide` / `SideBandShape` / `SideDetailTransform`
- Side 선택 UX, Side별 title, Side workspace gutter / centering
- `ScrollHandle`, `EditorMiniMap` — 전체 캔버스를 직접 보므로 필요 없다
- Drawing의 프레임 밴드 제한(`isInsideFrameBand`), Sticker의 밴드 constraint

재사용한 것 (다시 만들지 않았다)

- `SideDetailCanvas` → `MirrorEditorCanvas`로 일반화: Drawing / Eraser / Sticker /
  Photo Sticker / selection / transform / tap·drag / pinch / pan / undo·redo 전부 유지
- `SideDetailTransform` → `EditorCanvasTransform`: 같은 uniform scale + translation,
  같은 masterPoint / screenPoint / focusState 구조

Deprecated

- 아래 "Phase 3-3A / 3-3C.2"의 Side Detail Pan · Workspace Centering 항목은
  이 Phase에서 대체되었다. 기록으로만 남긴다.

## Phase 3-3A — Side Detail Pan (대체됨 · 기록용)

현재 Left / Right Side Detail은 확대 배율이 고정이라
프레임 전체 높이를 편집할 수 없다. 다음 Phase에서 반드시 해결한다.

- Left / Right에서 상단 → 중간 → 하단까지 세로 pan / scroll
- Top / Bottom도 편집 영역이 화면보다 크면 같은 축으로 이동 허용
- 확대 배율은 유지
- Canvas 바깥 빈 공간이 보이지 않게 clamp
- Mini Map viewport가 실제 위치를 따라 이동
- Drawing / Sticker 모두 같은 viewport / pan 구조를 사용
- 기존 SideDetailTransform을 기반으로 구현 (임시 scroll 구조를 새로 만들지 않는다)

## Phase 3-3C.1 — Sticker Creator UX + 저장/보관 정책 (확정)

Photo Sticker Phase 이전에 확정한 정책이다.

Sticker

- 기본 제공 스티커 20종 이상 + 카테고리 필터(전체 / 하트 / 리본 / 반짝임 / 꽃 / 두들)
- `BuiltInSticker.rawValue`는 저장 식별자다. asset을 교체해도 유지한다.
- template 스티커는 tint 지원, 기본값 잉크색. `.original`(사진 등)은 tint 무시.
- 색 변경은 Undo / Redo 대상이다.
- 이동 중 촉각 피드백은 시간(0.09s) + 이동 거리(Master 26px)로 제한한다. 프레임마다 울리지 않는다.
- `완료`로 선택 해제. 이때 한 번 더 또렷한 피드백.

저장 / 보관

- 저장 시 이름 입력. 최대 `MirrorStoragePolicy.maxNameLength`(24자).
- 내가 만든 거울 → 제자리 갱신. 기본 제공 / 구매 거울 → 원본 유지 + 새 거울 생성.
- 슬롯은 `origin == .made`만 소비한다.
- 무료 슬롯 `MirrorStoragePolicy.freeCreatedSlots` = 3. 코드에 숫자 3을 직접 쓰지 않는다.
- 슬롯이 가득 차면 새 거울 저장만 막고 덮어쓰기는 허용한다.
- 확장 1회 = `MirrorStoragePolicy.slotPackSize` = 5칸.

이 Phase에서 하지 않은 것 (후속)

- Photo Picker / Background Removal
- 조각 차감, StoreKit / IAP, Ledger, 가격 확정
- 슬롯·거울의 서버 persistence

## Phase 3-3C.2 — Side Workspace Centering + Sticker Refocus (일부 대체됨 · 기록용)

> Workspace Centering / Gutter 부분은 Phase 3-3E Free Canvas로 대체되었다.
> Sticker 재선택 / focus / 제스처 우선순위 / Mirror Inner Corner는 그대로 유효하다.

Editor Workspace

- Left / Right Side Detail에서 밴드를 화면 가로 중앙에 놓는다.
- 바깥 여백 = **Editor Workspace Gutter**. Editor 전용 UI 공간이고 MirrorDesign에 저장되지 않는다.
- Gutter 크기는 magic number가 아니라 "밴드 중심 = 화면 중심"이 되는 offset으로 계산된다.
- Pan clamp 정책 수정: 세로축은 여전히 빈 공간 금지. 가로축은 이 centering offset까지만 허용.
- Mini Map은 Master Canvas와 실제로 겹치는 부분만 보여준다 — gutter를 디자인 영역처럼 그리지 않는다.
- Gutter에서는 그리기 / 스티커 배치 불가 (`MirrorFrameInsets.isInsideFrameBand`).

Sticker

- 이미 놓은 스티커를 다시 탭하면 선택 + 필요할 때만 최소 focus.
- Focus 조건: 스티커가 화면에 다 보이면 이동 없음. 아니면 zoom 유지 + 최소 pan.
- 잠긴 스티커도 선택 가능(변형만 막힌다).
- hit test는 중심 기준 역회전 후 로컬 사각형 판정 + 최소 tap target 44pt.
- Sticker 도구에서 빈 곳 한 손가락 drag = 화면 이동. Drawing / Eraser는 기존 그대로.
- 제스처 우선순위: handle → sticker → scroll handle → 빈 캔버스 / gutter.
- Pan은 언제나 같은 `EditorViewportState` 하나만 쓴다. Undo History에 들어가지 않는다.

Mirror Inner Corner Radius

- `MirrorGeometry.innerCornerRadius` (Master 기준 30px) 하나만 정의한다.
- `MirrorFrameInsets.mirrorAreaPath(in:)`가 단일 geometry source다.
- Renderer / FrameMask / 그리기 제한 / 스티커 제약 / Preview / Runtime / Capture가 모두 이 하나를 쓴다.

초기 라이브러리

- 최초 실행 시 내 거울은 비어 있다.
- `MirrorLibrary.defaultMirror` = 목록에 없는 초기 적용 거울. 슬롯을 쓰지 않는다.
- 기본 단색 8종은 상점의 "기본" 카테고리 무료 템플릿으로 이동.
- 무료 템플릿 받기는 실제로 동작한다(`MirrorLibrary.acquire`). 조각 결제 / ledger는 미구현.

## Phase 3-3D — Photo Sticker (확정)

기존 Sticker Engine을 그대로 쓴다. 새 Transform Engine을 만들지 않았다.

- 진입: Sticker Picker 상단 "내 사진으로 만들기" → `PhotosPicker`(1장, `.images`).
- 배경 제거: Vision `GenerateForegroundInstanceMaskRequest` + `generateMaskedImage(croppedToInstancesExtent:)`.
  온디바이스 전용이고 네트워크를 쓰지 않는다.
- 다운샘플: `CGImageSourceCreateThumbnailAtIndex`, 긴 변 `PhotoStickerMaker.maximumPixelSize`(1600)로 제한.
- 잘라낸 뒤 긴 변의 `transparentPadding`(4%)만큼 투명 여백을 더한다.
- 실패: `PhotoStickerError.noSubject` → 다시 고르기 / 원본 그대로 넣기 / 취소. crash 없음.
- 중복 실행 / Editor 이탈은 `Task` 취소로 정리한다.

데이터 경계 (중요)

- 이미지 binary는 `PhotoStickerAssetStore`에만 있다. `MirrorDesign` / `StickerObject` / `EditorSnapshot` / Undo 스택에는 들어가지 않는다.
- `StickerSource`가 `.builtIn(BuiltInSticker)` / `.photo(assetID:aspectRatio:)` 둘로 나뉜다 — 사진은 **참조 + 비율**만 담는다.
- 복제는 같은 assetID를 참조하므로 이미지가 늘지 않는다.
- 렌더는 `MirrorRenderer` 한 곳에서 두 source를 모두 처리한다 → Editor / Preview / 홈 / 내 거울 / 상점 / 실제 Mirror / Capture가 같은 결과.

이 Phase에서 하지 않은 것

- Sticker Creator / Marketplace
- Text / Shapes / Layers
- 사진 asset의 디스크 persistence (앱 전체 persistence Phase에서 함께)

## Phase 3-3D.1 — Photo Preview Fix + Mirror Creation + Save Context (확정)

미리보기 버그

- 홈 / 내 거울 미리보기가 `MirrorPreview`에 `stickers:`를 넘기지 않아 **모든 스티커**가 빠져 있었다.
- `MirrorPreview.init(mirror:)`로 거울 한 장을 통째로 넘긴다. 인자를 하나씩 조립하지 않아 다시 빠뜨릴 수 없다.
- AssetStore / assetID / 저장 경로 / 렌더러에는 문제가 없었다.

Editor Save Context

- `MirrorEditorContext { editCurrent, duplicate, createNew }`를 진입 시점에 넘긴다.
- `MirrorLibrary.save(_:name:context:)`가 이 값으로 갈린다. origin만 보고 추측하지 않는다.
- `willCreateNewMirror(for:context:)`가 true일 때만 이름을 묻는다.
- 새 거울을 만든 뒤 Editor는 새 id를 기억하고 context를 `editCurrent`로 바꾼다 — 연속 저장이 거울을 여러 개 만들지 않는다.
- `MirrorSaveOutcome`이 id와 이름을 함께 돌려준다.

거울 만들기

- 내 거울 상단에 항상 `+ 거울 만들기`. Empty State에도 같은 동작.
- `MirrorDesign.blank` = standard 108 / 180 + 둥근 Mirror Area + 장식 없음. 상점 템플릿을 복사하지 않는다.
- 슬롯이 없으면 Editor에 들어가기 전에 막는다.

사진 asset

- 거울을 복제해도 `StickerSource.photo(assetID:)`를 그대로 참조한다. binary는 하나.
- 디스크 persistence는 여전히 후속 Persistence Phase.

## Sticker Creator (후속 Phase)

별도의 "스티커 만들기" 페이지. Mirror Editor 기술을 최대한 재사용한다.

- 공유: Drawing tools / Brush / Color / Undo·Redo / Sticker renderer / normalized object 개념
- 다름: Mirror의 1080 × 2340 좌표계를 강제하지 않는다. 투명 Sticker Canvas라는 별도 output format.
- 핵심 스타일은 **사용자의 손그림**이다.
- 최종 asset: transparent background + 사용자의 그림만. 흰 사각형 배경이 붙으면 안 된다.
- 그린 부분의 visible bounds로 crop하고 약간의 투명 padding만 남긴다.
- Flow(예상): 스티커 만들기 → 빈 캔버스 또는 사진 → Drawing / Text / Decoration → Crop → Preview → 이름 → 태그 → 저장

두 가지 creation source가 최종적으로 같은 transparent asset이 된다.

- A. 손그림: Transparent Canvas → Drawing → Crop → Sticker
- B. 사진: Photo → Background Removal → Transparent Foreground → Sticker (Photo Sticker Phase 이후)

## Sticker Marketplace (후속 Phase)

- Sticker Creator → 저장 → 내 스티커 → 상점에 올리기 → 가격 설정 → Sticker Store
- 구매자: 조각으로 구매 → Editor Sticker Library에 추가
- 판매자: 조각 획득. 현금 출금은 MVP 정책상 없음.
- Store에는 Mirror Template / Sticker 두 종류의 Creator Content가 생긴다. 정보구조는 Store Phase에서 설계.

등록 비용

- Mirror Template Publish = 20 조각.
- **Sticker Publish Cost < Mirror Publish Cost** (확정).
- 정확한 가격 미정. 후보 5~10 조각. UI에 숫자를 띄우거나 차감 로직을 만들지 않는다.

가격 / 정산

- 판매자가 개별 Sticker 가격을 0...N 조각으로 설정. 무료 Sticker 허용.
- 판매 시 구매자 잔액 감소 / 판매자 잔액 증가.
- Server-authoritative ledger는 Backend Phase.

TODO — Sticker Pack

- 장기적으로 "리본 세트" / "생일 세트" / "Y2K 세트" 같은 묶음 판매 확장 가능. 지금은 설계하지 않는다.

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
