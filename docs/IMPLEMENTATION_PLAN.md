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
- Sticker 도구에서 빈 곳 한 손가락 drag = 화면 이동.
- 제스처 우선순위: handle → sticker → scroll handle → 빈 캔버스 / gutter.
- Pan은 언제나 같은 `EditorViewportState` 하나만 쓴다. Undo History에 들어가지 않는다.

Editor Gesture Policy (V-2)

- 한 손가락이 무엇을 하는지는 `EditorGesturePolicy.oneFingerAction(tool:drawingMode:grabbed:)`
  **한 함수**가 정한다. 도구마다 따로 판단하지 않는다.
  - draw + `.draw` → stroke / draw + `.pan` → viewport pan
  - erase → erase
  - sticker · text → 오브젝트를 잡았고 잠기지 않았으면 move, 아니면 viewport pan
- Hit target이 두 종류다. `EditorGesturePolicy.selectTapTarget`(44pt)은 제자리 tap 전용,
  `dragTapTarget`(0)은 끌기 전용 — 끌기에서 넓히면 오브젝트 옆 빈 곳을 밀 수 없다.
  `contains(_:in:minimumTapTarget:)` / `topSelectableDecoration(at:in:minimumTapTarget:)`가 이 값을 받는다.
- 두 손가락 pan / pinch는 `EditorCanvasGestureOverlay`의 전용 recognizer(최소 2 touch)라
  오브젝트 위에서 시작해도 언제나 viewport navigation이다. Zoom 범위 1…4 유지.
- 두 손가락이 들어오면 진행 중인 한 손가락 입력을 끊는다. 이때
  `DrawingCommitPolicy.keepsCancelledWork(travel:)`가 44pt 미만이면 그 획 / 지우기를 버린다 —
  pinch를 시작하려다 생기는 점·짧은 선을 막는다.
- `DrawingInteractionMode`(draw / pan)는 Editor session state다. 기본 `.draw`,
  도구를 바꾸면 `.draw`로 되돌아가고, 붓 / 색 / 굵기 변경으로는 리셋되지 않는다.
- 좌표 변환은 `EditorCanvasTransform` 하나뿐이다. 도구별 변환을 만들지 않는다.

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
- 디스크 저장은 Phase 3-5에서 붙였다 (`PhotoStickerAssets/<assetID>.png`).

## Phase 3-4A — Text Objects (확정)

Free Canvas 위에 텍스트를 얹는다. Sticker interaction 구조를 그대로 재사용했다.

- `TextObject`: id / text / center(normalized) / fontSize(normalized) / style / alignment /
  color / rotation / opacity / zIndex / isLocked. **화면 pt를 저장하지 않는다.**
- `MirrorDesign.texts`, `EditorSnapshot.texts`, `EditorEdit.addText / replaceText / deleteText`.
- 줄 나눔 / 크기는 `TextLayout`이 Master 픽셀에서 한 번만 계산한다 —
  렌더러 / hit test / selection overlay가 같은 결과를 공유한다.
- 크기 변경은 `fontSize` 하나만 바꾼다. 가로 / 세로를 따로 늘려 찌그러뜨리지 않는다.
- 글꼴은 system font design(default / bold / serif / rounded)만 쓴다. 폰트 파일을 추가하지 않는다.
  한글이 안정적으로 나오는 조합만 남겨 "손글씨" 대신 "명조"를 넣었다.
- 선택 오버레이는 `StickerSelectionOverlay` → `ObjectSelectionOverlay`로 일반화해 공용으로 쓴다.
- 스티커 / 텍스트는 하나의 zIndex 순서로 렌더되고, hit test도 같은 기준을 뒤집어 쓴다.
- 제스처 중에는 임시 상태만 바꾸고 끝날 때 1회만 history에 남긴다.
- 사진 스티커 binary는 여전히 AssetStore에만 있다 — 텍스트 추가로도 snapshot에 들어가지 않는다.

이 Phase에서 하지 않은 것

- 테두리 / 그림자 / glow / 그라디언트 / 텍스트 배경 박스 / 말풍선
- Shapes, Layers UI, Sticker Creator / Marketplace, Persistence, Store Publish

## Phase 3-4B — Shapes / Decorations (실험 후 제거)

도형 / 꾸미기 요소를 한 번 구현했으나 **제품 방향 결정으로 제거했다.**
현재 Editor 장식은 Drawing / Sticker · Photo Sticker / Text 세 가지뿐이다.
로드맵에 다시 기본 계획으로 넣지 않는다.

같은 Phase에서 확정한 **Home Save 정책은 그대로 유지된다.**

- 홈에서 저장할 때는 이름을 묻지 않는다. `MirrorLibrary.needsName(for:)`가 `.editCurrent`에서 false.
- 목록에 없는 기본 거울을 홈에서 처음 저장하면
  `MirrorStoragePolicy.automaticName(existing:)`이 "나의 거울" / "나의 거울 2" …를 지어준다.
- 내 거울에서 복제 / 새로 만들기는 그대로 이름을 받는다.

## Phase 3-4C — Layers (확정)

순서를 바꿀 수 있는 대상은 **스티커(사진 포함)와 텍스트**뿐이다.

- `DecorationLayer` — `.sticker` / `.text` 두 case. 향후 ImportedArtwork는 case 하나만 늘리면 된다.
  지금 미래를 위한 generic protocol 계층을 만들지 않았다.
- `MirrorDesign.decorationLayers`가 **앞에 보이는 것부터** 나열한다.
  정렬 기준(zIndex → 스티커 0 < 텍스트 1 → 배열 순서)은 Renderer / hit test와 완전히 같다.
- `EditorSnapshot.reorderDecorations(frontToBack:)`가 zIndex를 0부터 연속으로 다시 매긴다.
  오브젝트 id와 zIndex 외 속성은 건드리지 않는다.
- `EditorEdit.reorderDecorations(frontToBack:)` — 드래그 중이 아니라 놓았을 때 1회만 커밋한다.
- 사진 스티커는 assetID만 유지된다. 이미지 복사도, 배경 제거 재실행도 없다.
- Drawing은 하나의 고정 레이어(장식보다 아래), Background는 고정 최하단. 둘 다 재정렬 불가.
- 목록 줄을 누르면 Canvas 선택으로 이어진다. 잠긴 장식도 선택 가능.
- 이번 단계에는 숨기기 / 목록 삭제가 없다.

## Text Polish TODO (후속)

A. Resize 감도

- 실기기에서 텍스트 크기 변화 폭이 너무 크다.
- drag 대비 fontSize 변화량을 완화하고 더 세밀한 조절을 지원한다.
- 현재 `TextPolicy.fontSizeRange` 상·하한도 함께 재검토한다.

B. Decoration Font 확장

- 현재 4종(기본 / 굵게 / 명조 / 둥근)은 system font 기반 MVP다.
- 한글을 지원하는 손글씨 / 귀여운 글씨 / 굵은 포스터 / 얇은 감성 / 레트로 계열로 넓힌다.
- 실제 폰트 licensing과 bundle 전략을 함께 정한 뒤 Visual·Text Polish에서 진행한다.

## Phase 3-5 — Local Persistence (확정)

내 거울과 사진 스티커를 기기에 적어둔다. 서버 / 클라우드 동기화는 없다.

저장 위치

```
Application Support/ggumirror/
  mirror-library.json            거울 목록 + 현재 거울 (JSON 한 장)
  mirror-library-damaged.json    읽지 못한 파일을 치워두는 자리
  PhotoStickerAssets/<id>.png    배경 지운 사진 (투명도 유지, JPEG 금지)
```

Caches가 아니라 Application Support를 쓴다 — 사용자가 만든 콘텐츠라 시스템이 지우면 안 된다.

형식

- `PersistedLibrary { schemaVersion, currentMirrorID, mirrors, purchasedCreatedSlots }`, 현재 버전 **1**.
- 읽을 때 `schemaVersion`을 먼저 보고 `migrate(_:from:)` 한 곳에서 분기한다. 지금은 v1 하나뿐이다.
- `Color`만 직접 적을 수 없어 `RGBAColor`(sRGB 4값)로 바꾼다. UIImage / CGImage는 애초에 모델에 없다.
- Codable 정의는 `MirrorCodable.swift` 한 곳에 모았다 — 저장 때문에 Editor 모델을 갈아엎지 않는다.
- 모르는 enum 값(예전/나중 빌드)은 파일 전체를 버리지 않고 기본값으로 되돌린다.

진실은 하나

- `MirrorLibrary.live`가 앱 전체의 단 하나뿐인 목록이다. 화면은 각자 저장하지 않는다.
- 시작: 파일 읽기 → hydrate → 사진 preload → 안 쓰는 사진 정리 → UI.
- 변경: 저장 / 만들기 / 복제 / 삭제 / 적용 / 슬롯 추가 **1회 = 파일 쓰기 1회.**
- Editor의 드래그 / 확대 같은 중간 상태는 저장하지 않는다.
- 쓰기는 직렬 큐 하나를 지나며 atomic write다 — 쓰다 종료돼도 파일이 반쪽 나지 않는다.

사진

- 이미지 binary는 JSON에 넣지 않는다. 거울은 `assetID`만 참조하므로 복제해도 파일이 늘지 않는다.
- `PhotoStickerAssetStore` = 메모리 캐시 + 디스크. 시작할 때 참조된 사진을 미리 올려
  **렌더러가 그리는 도중 파일을 읽지 않는다.** 못 찾은 것은 한 번만 찾고 기억한다.
- 참조가 하나도 없는 사진은 거울 삭제 후 / 앱 시작 때 정리한다. Editor 작업 중에는 지우지 않는다.

실패 정책

- 파일 없음 = 최초 설치. 내 거울 0개 + 기본 거울.
- 못 읽는 파일은 **지우지 않고** `-damaged.json`으로 치운 뒤 빈 상태로 계속 쓸 수 있게 한다.
- `schemaVersion`이 앱보다 높으면 읽지도 덮어쓰지도 않는다(읽기 전용 세션). DEBUG에서 로그.
- 없는 거울을 가리키는 `currentMirrorID`는 기본 거울로 되돌린다. 어느 쪽도 crash하지 않는다.

크기 (측정값)

- 거울 50장 × (획 100 · 스티커 50 · 텍스트 20) → **3.7 MB / encode 0.20s / decode 0.15s**.
- 실제 MVP 상한(제작 3장 + 받은 거울)에서는 훨씬 작다. SQLite 같은 DB로 미리 옮기지 않는다.

이 Phase에서 하지 않은 것

- 클라우드 동기화 / 백엔드, Profile · 조각 잔액 이전(각각 AppStorage / 임시값 그대로).
- 상점 실제 등록 / 구매 / 정산 (Phase 4-1은 준비 단계까지)

## Phase 3-6 — External Mirror Artwork Import (확정)

작업 가이드 export → 외부 그림 앱 → transparent PNG → 전체 Canvas 고정 레이어.

작업 가이드

- `MirrorArtworkGuide.makeImage()` — 1080 × 2340 투명 PNG. 거울 외곽선 + 카메라 영역 dashed만.
- 규격은 `MirrorFrameInsets.standard` / `MirrorGeometry.innerCornerRadius`에서 온다.
  가이드가 108 / 180 / 220 / 30 같은 숫자를 따로 갖지 않는다.
- 배경을 채우지 않는다 — 그림 앱에서 참고 레이어로 밑에 깔 수 있어야 한다.
- `exportPNG()`는 임시 파일이다. persistence(Application Support)에 넣지 않는다. 공유는 `ShareLink`.

가져오기

- 사진(PhotosPicker) / 파일(fileImporter) 두 경로. 넓은 사진 라이브러리 권한을 요구하지 않는다.
- `MirrorArtworkImporter.normalize` — ImageIO thumbnail로 EXIF 회전 정규화 + 큰 원본 축소.
  정확히 1080 × 2340이면 크기 유지, 같은 비율이면 downsample, 다른 비율이면 `wrongAspectRatio`.
- **카메라 영역은 import 단계에서 지운다**(`framedArtwork`). 외부 디자인은 프레임용 overlay다.
  지우는 모양은 `mirrorAreaPath` 하나를 쓰고, bitmap context는 아래가 0이라 뒤집어서 채운다
  (위 180 / 아래 220으로 두께가 달라 뒤집지 않으면 40px 어긋난다).
  덕분에 "카메라를 가릴 수 있다"는 경고 자체가 필요 없어져 제거했다.
- 승인 전 Preview 단계를 반드시 거친다 — 실제 거울 geometry 위에 얹어 정렬과 투명도를 확인시킨다.

모델

- `ImportedArtworkObject { id, assetID, opacity, zIndex }`.
  center / frame / rotation / scale을 **저장하지 않는다.** 언제나 Master Canvas 전체다.
- 사진 스티커(`StickerSource.photo`)와 합치지 않았다 — 역할이 완전히 다르다.
- `EditorEdit`: add / replace / delete + 기존 reorder. History에는 assetID만 들어간다.
- 교체는 같은 레이어다 — id와 zIndex를 유지하고 assetID만 바꾼다.

Layers / 선택

- `DecorationLayer.importedArtwork` 추가. rank는 외부 디자인(0) < 스티커(1) < 텍스트(2).
- 새 외부 디자인은 장식 스택 맨 뒤에 들어간다. 그 위에 스티커 / 텍스트를 얹기 쉽게 하기 위해서다.
- **캔버스 hit test에서 제외한다.** 전체를 덮기 때문에 포함하면 어디를 눌러도 그것만 잡힌다.
  판정은 `MirrorDesign.topSelectableDecoration` 한 곳에만 있고, 선택은 Layers row로 한다.
- 컨트롤은 교체 / 투명도 / 삭제 / 완료뿐. 이동·크기·회전 handle이 없다.

Persistence

- `ImportedArtworkAssets/<assetID>.png` (PhotoStickerAssets와 분리, `MirrorAssetKind`).
- schemaVersion **1 → 2**. v1 파일은 `importedArtworks` 키가 없을 뿐이라 빈 배열로 읽힌다.
- 참조 계산 / GC는 종류별로 따로 돈다. 복제는 파일을 공유하고, 마지막 참조가 사라질 때만 지운다.

이 Phase에서 하지 않은 것

- 비율이 다를 때의 자동 crop/fit, PSD / SVG import, Imported Artwork transform,
  레이어 숨기기 / 그룹 / blend mode.

## 시트 배경 (수정)

`presentationBackground { PaperBackground() }`가 화면마다 흩어져 있었고,
배경 뷰가 safe area 안쪽에만 그려져 시트 아래 모서리에 종이가 닿지 않았다.

- `paperSheet()` 하나로 모았다. 그 안에서만 `ignoresSafeArea()`를 건다.
- 모든 시트(그리기 설정 / 텍스트 / 색 / 글꼴 / 레이어 / 외부 디자인 / 이름 / 등록 준비)가 같은 modifier를 쓴다.
- 시트마다 padding을 덧대는 임시방편은 쓰지 않는다.

## Phase V-1 — 손그림 비주얼 시스템 + 글꼴 (확정)

카메라 줌 없음 정책

- `videoZoomFactor`를 건드리는 코드는 애초에 없었다. 확대되어 보인 것은
  Camera Area(세로로 긺)와 카메라 소스(4:3)의 **비율 차이로 생기는 crop**이다.
- **한 번 잘못 고쳤다가 되돌렸다.** `.resizeAspect` + 남는 자리를 프레임 색으로 채우는 방식은
  화각은 살렸지만 영상이 작아지고 프레임이 두꺼워 보여 **거울 디자인 자체가 바뀌었다.**
  거울 geometry(108 / 108 / 180 / 220, Camera Area 864 × 1940)는 확정값이므로
  카메라 문제로 건드리지 않는다. → preview / capture 모두 aspect fill로 원복.
- 남은 정상 경로는 **소스를 더 넓게 받는 것** 하나뿐이다.
  `bestFormatIndex`가 30fps 이상 format 중 `videoFieldOfView`가 가장 큰 것을 고르고,
  같은 화각이면 버퍼가 과하지 않도록 화면을 채울 만한 것 중 작은 쪽을 고른다.
  (`sessionPreset`이 고르던 format보다 넓은 화각이 있으면 그만큼 넓어진다.)
- preset만 16:9 ↔ 4:3으로 바꾸는 것은 **효과가 없다** — fill이 세로에 맞춰 배율을 정하므로
  남는 절대 가로 폭이 같다.
- 비율 차이로 생기는 crop은 프레임을 바꾸지 않는 한 없앨 수 없다. 숨기지 않고 정책으로 적어 둔다.

앱 전체를 "종이에 손으로 만든 UI"로 통일하고, 번들 폰트를 실제로 연결했다.

브랜드 서체

- 앱 UI 글씨를 **개구(Gaegu) 하나로 고정**했다. `InkFont`가 유일한 semantic token이고,
  화면은 `.font(.system(...))`을 직접 쓰지 않는다. 자세한 표는 DESIGN.md.
- 폰트는 `CTFontManagerRegisterFontsForURL`로 런타임 등록한다.
  Info.plist(UIAppFonts)를 쓰지 않는 이유: 번들이 폴더를 평탄화해도 안전하고,
  등록하면서 PostScript 이름을 그 자리에서 확인할 수 있다.
  **파일 이름과 실제 이름이 다르다** — `NanumBrushScript-Regular.ttf` → `NanumBrush`.
- 이름 표는 전역 `let`으로 한 번만 만들어 어느 스레드에서나 안전하게 읽는다(렌더러가 MainActor 밖에서 돈다).
- 못 찾으면 시스템 한글 폰트로 떨어진다.

거울 글꼴 라이브러리

- `TextFontStyle`에 case만 **추가**했다. `basic / bold / serif / rounded`는 예전 저장 데이터가
  쓰고 있어 지우지 않는다. rawValue 저장 형식이 그대로라 **schemaVersion은 2 그대로**다.
- `selectable` 11개를 추천 / 손글씨 / 강조로 묶어 고르게 하고, 각 줄을 그 글꼴로 미리 보여준다.
- 예전 값을 쓰고 있으면 "지금 글꼴" 칸에 따로 보여준다.

텍스트 크기 조절

- 스티커(폭 0.39)와 글자(폭 0.178)는 값의 범위가 두 배 넘게 차이 나는데 같은 계수를 써서
  글자만 과민했다. `TextPolicy.resizeSensitivity = 0.45`로 범위 비율만큼 낮췄다.
- 잡는 순간 점프 없음(누적 translation 기준), 확대 상태에서도 체감 동일, min/max clamp 유지.

회전 handle

- handle이 회전한 오브젝트를 따라 돌도록 중심 기준으로 좌표를 회전시킨다.
  예전에는 축 정렬 bounding box 모서리에 붙어 있어 돌리면 따로 놀았다.
- 크기 조절 드래그도 오브젝트가 누운 방향으로 투영해 어느 각도에서든 "바깥으로 끌면 커진다".
- 스티커 / 사진 스티커 / 텍스트가 같은 오버레이를 쓰므로 셋 다 같이 고쳐졌다. 외부 디자인은 고정 레이어라 제외.

## Phase 4-2A — 상점 템플릿 연결 (확정)

손그림 PNG 3장을 실제 상점 데이터로 연결했다.

- `Store/StoreCatalog.swift` — 상점 타입(태그 / 카테고리 / 템플릿 / 목록)을 한 파일로 모았다.
  `MirrorSampleData.swift`에는 기본 색과 라이브러리만 남는다.
- `Resources/StoreTemplates/<카테고리>/<이름>.png` — 번들이 폴더를 평탄화해도
  `StoreArtworkResource.url`이 파일 이름으로 다시 찾는다.
- `MirrorTemplate.artwork` — 손그림 템플릿에만 붙는다. 단색 기본 템플릿은 nil.
- `assetID`는 템플릿마다 **고정 UUID**다. 상점을 열 때마다 새 파일이 쌓이지 않는다.
- `StoreArtworkLibrary` — 번들 PNG → `MirrorArtworkImporter.framedArtwork` → 메모리 등록 + 캐시.
  사용자 import와 같은 함수를 지나므로 카메라 영역이 비워지는 규칙이 상점에도 그대로 적용된다.
- 구경할 때는 메모리만 쓰고, **받을 때** `persistToDisk`로 파일을 내린다.
- `MirrorPreview(template:)` 하나를 목록과 상세가 같이 쓴다.

템플릿을 늘리는 방법: PNG를 Resources에 넣고 `StoreCatalog.artworkTemplates`에 한 줄 추가.

## Phase 4-1 — Store Publish Foundation (확정)

여기까지가 **등록 준비**다. 실제 등록 / 조각 차감 / listing / 판매는 없다.
로그인도 ledger도 없는 상태에서 "등록 완료"처럼 보이는 가짜 상태를 만들지 않는다.

- 진입: 내 거울 → 거울 → `상점에 올리기`. `MirrorPublishPolicy.isEligible`(= origin이 `.made`)일 때만 보인다.
- `MirrorPublishDraft { id, mirrorID, title, description, priceInShards, didAcknowledgePhotoPrivacy, updatedAt }`.
  디자인 스냅샷을 복사하지 않는다 — mirrorID만 참조하므로 거울을 고치면 미리보기도 같이 바뀐다.
- `MirrorPublishManifest`는 사진 / 외부 디자인 assetID만 모은다. 중복 제거 + 정렬, binary 없음.
- `MirrorPublishValidator` — 거울 존재 / 자격 / 제목 / 설명 / 가격 / asset 해석 / 사진 공개 확인.
  이미지가 하나라도 사라졌으면 준비 완료로 넘기지 않는다.
- 저장: `publish-drafts.json` (거울 목록과 파일 분리, 자체 schemaVersion 1).
  거울 목록 형식을 건드리지 않으므로 mirror-library schema는 그대로 2다.
- 거울을 지우면 그 준비 정보도 지운다. 앱을 켤 때 없는 거울의 준비 정보는 버린다.
- 저장해도 origin / 슬롯 / 조각 / 상점 목록은 바뀌지 않는다. 테스트로 고정했다.

아직 하지 않은 것

- 실제 등록(listing 생성), Apple 로그인, 서버 업로드, 조각 ledger와 20조각 차감,
  구매 / 판매자 정산, 상점 노출.

## Phase 4-2B — Apple Sign In Foundation (확정 · CLIENT ONLY)

계정의 **바탕만** 만들었다. 서버는 아직 없다 —
`ggumirror-be`는 이 Phase에서 한 줄도 건드리지 않았다.

경계

- **로그인 성공 ≠ 서버 계정 생성.** Apple 계정을 이 기기에 연결한 것뿐이다.
- 로그인 벽 0개. 앱은 여전히 Mirror부터 시작하고, 상점 구경 / 무료 받기 /
  등록 준비 저장까지 전부 로그아웃 상태로 된다. (PRODUCT.md "로그인 없이 되는 것")
- 실제 Publish / Purchase / ledger는 여기 붙이지 않았다. 가짜 성공 상태를 만들지 않는다.

구조 (`ggumirror/Auth/`)

- `AppleIdentity.swift` — `AppleIdentity`(userID / displayName / email) · `AuthState` ·
  `AppleSignInResult`(전달용, 저장 안 함) · `AppleSignInOutcome` · `AuthProtectedAction` · `AuthLog`
- `AuthIdentityStore.swift` — `AuthIdentityStoring` + Keychain 구현 + 메모리 구현
- `AppleSignInService.swift` — **AuthenticationServices와 닿는 유일한 파일**
- `AuthSession.swift` — 앱 하나뿐인 로그인 상태(`AuthSession.live`)
- `AccountSection.swift` — 설정의 계정 칸

`AuthSession`은 AuthenticationServices를 import하지 않는다. 순수한 값
(`AppleSignInOutcome` / `AppleCredentialState`)만 보므로 **실제 Apple UI 없이 단위 테스트가 된다.**
DI framework도 외부 OAuth / Keychain 라이브러리도 추가하지 않았다.

`ASAuthorizationController`를 직접 만들지 않았다 — `SignInWithAppleButton`이 내부에서
그것을 들고 있어서, 따로 만들면 같은 일을 하는 경로가 둘이 된다.
프로그래밍 방식 로그인이 필요해지면 그때 `AppleSignInService`에 함수 하나를 더한다.

이름 / 이메일 보존

- Apple은 **첫 로그인에서만** fullName / email을 준다. 다음부터는 nil이다.
- `AppleIdentity.merging(displayName:email:)`이 **값이 실제로 있을 때만** 갱신한다.
  공백 문자열도 "없음"으로 친다. nil로 덮어써서 이름이 사라지는 일이 없다.

복원 (앱 시작)

- 시작은 언제나 Mirror다. Keychain 읽기는 동기(즉시)지만 **Apple 확인은 화면이 뜬 뒤 비동기**로 한다.
- `authorized` → 유지 / `revoked` · `notFound` → Auth만 정리
- `transferred` → **아무것도 지우지 않는다.** 앱 이관 신호일 뿐이라 Backend Auth Phase에서 다룬다.
- 네트워크 · 시스템 오류(`unknown`) → **지우지 않는다.** 비행기 모드 한 번에 로그인이 풀리면 안 된다.
- `credentialRevokedNotification`도 같은 규칙 — Auth만 signedOut.

토큰

- `identityToken` / `authorizationCode`는 `AppleSignInResult`에 잠깐 있다가 사라진다.
  **저장하지 않고, 보내지 않고, 로그에 찍지 않는다.** 저장 형식(`AppleIdentity`)에는 칸 자체가 없다.
- 로그는 상태 전이만 남긴다 — 식별자 / 이메일 / 토큰은 DEBUG에서도 찍지 않는다.

Auth Gate (foundation)

- `AuthProtectedAction { publish, purchase, shardTransaction }` + `requireSignIn(for:)` /
  `takePendingAction()`. **지금 아무도 부르지 않는다.** 로그인 후 이어서 할 일을 담을 그릇만이다.

Capability

- `ggumirror/ggumirror.entitlements` 신규 — `com.apple.developer.applesignin = [Default]`.
- app target Debug / Release에 `CODE_SIGN_ENTITLEMENTS`만 추가했다.
  Camera / Photos usage description과 기존 build settings는 그대로다.

이 Phase에서 하지 않은 것

- Backend 전부(FastAPI / Firestore / HTTP client / 서버 토큰 검증 / Backend User / 세션 토큰)
- Shard Ledger, actual Store Publish, 유료 구매, 판매자 정산, 클라우드 동기화
- 계정 삭제 / Apple authorization revoke — 서버 사용자가 생긴 뒤에 만든다

다음: **Backend Foundation** → Apple server verification + Server User.

## Phase V-3 — Focused UI / Editor Polish (확정)

네 가지만 손봤다. **앱 전체 아이콘 교체 / 종이 texture 추가 / 전체 redesign은 이 Phase에 없다.**

### A. 제품 아이콘 둘 (`Shared/InkProductIcons.swift`)

- `MirrorIcon` / `ShardIcon`을 직접 그린 손그림으로 교체. `MirrorFrameShape` ·
  `MirrorReflectionShape` · `ShardShape` · `ShardReflectionShape` 모두 `Shape`다.
- 나머지 아이콘은 건드리지 않았다. 정의만 `InkComponents.swift`에서 옮겨 왔고
  타입 이름을 그대로 둬서 사용처(8곳)는 수정이 필요 없었다.
- 조각은 **네 번 다시 그렸다** — 깃발 / 커서 / 왕관 / 다이아몬드로 읽혀서.
  실패 원인과 결론은 DESIGN.md "제품 아이콘"에 적어 뒀다.

### B. Bottom Sheet · Dialog (`Shared/InkModal.swift`)

- 시스템 `.sheet` 13곳, `.confirmationDialog` 2곳, `.alert` 7곳 → `inkBottomSheet` / `inkDialog`.
- `presentationDetents` → `InkSheetSize`. `paperSheet()`는 삭제했다.
- 등장·퇴장은 `InkMotion` 한 곳(easeInOut 0.26초). spring 없음.
- `fullScreenCover` 2곳(Editor 진입 · 미리보기)은 그대로다 — 전체 화면이라 시스템 크롬이 없다.

**중간에 잡은 버그**: 비율 시트에서 `maxHeight`(비율) 뒤에 `maxHeight: .infinity`가 걸려
카드가 화면 전체를 차지하고 내용이 위로 붙었다(아래 빈 종이). 높이를 한 번만 주도록 고치고
`fractionSheetSitsAtTheBottom` 회귀 테스트를 붙였다.

### C. 내 거울 `꾸미기` = 기존 거울 수정

- 원인: `HomeView`가 `MirrorEditorContext.duplicate`를 넘겨서 저장할 때마다 새 거울이 생겼다.
  저장 로직은 이미 `.editCurrent`에서 제자리 갱신을 지원하고 있었다 — **routing만 틀렸다.**
- `.editCurrent`로 바꿔 같은 id / 이름 / origin / 슬롯을 유지한다.
- `save`가 currentID를 덮어쓰지 않게 했다. 쓰지 않는 거울을 고쳐도 적용은 그대로다.
- `복제`(`MirrorLibrary.duplicate`)와 `+ 거울 만들기`(`.createNew`)는 그대로 새 거울을 만든다.
- `.duplicate` context는 남아 있다 — Editor의 "○○ 복사본" 이름 프리필과 테스트가 쓴다.

### D. Draw / Hand 컨트롤 색

- 원인: 컨트롤 배경이 `shape.overlay(shape.stroke(...))`로 **채워지지 않은 Shape**였다.
  채우지 않은 Shape는 시스템 primary로 칠해져서 라이트 모드에서 검은 배경 + 검은 아이콘이 됐다.
  앱 전체에서 이 패턴은 이 한 곳뿐이었다.
- `.fill(PaperTheme.subtleSurface)` + 고정 semantic 색으로 고쳤다.
  선택 = 잉크 면 + 종이 아이콘 / 비선택 = 종이 면 + 잉크 아이콘.
- **colorScheme 분기를 만들지 않았다.** 앱 전체 다크 모드 지원도 이 Phase의 일이 아니다.

### 이 Phase에서 하지 않은 것

앱 전체 아이콘 교체 · 종이 texture · 전체 redesign · 다크 모드 대응 · Backend ·
Apple 서버 검증 · 실제 상점 등록 / 구매 · Store artwork · 폰트 · 카메라 · Mirror geometry.

## Phase V-4 — Doodle Sticker & Product Icon (확정)

기본 제공 스티커를 **손그림 두들 42종으로 전면 교체**하고, 제품 아이콘 네 개를 같은 펜으로 다시 그렸다.
앱 전체 아이콘 교체 / 종이 texture / redesign은 이 Phase에 없다.

### 구조

- `Editor/DoodleStickers.swift` — `DoodleStroke`(획) · `DoodleInk`(펜) · `DoodleAccent` · `DoodleCategory` · `DoodleStickerView`
- `Editor/DoodleStickerCatalog.swift` — 42종의 좌표. 그림의 전부가 이 파일 숫자다
- `Shared/DoodleProductIcons.swift` — 거울 · 조각 · 홈 · 상점 + 예전 이름(`MirrorIcon` / `ShardIcon`)

**PNG로 굽지 않았다.** picker 미리보기 · 실제 거울 · Capture가 `DoodleInk.draw` 한 함수를 지나므로
미리보기와 결과가 다를 수 없고, 어느 배율에서나 선이 뭉개지지 않는다.
renderer는 이미지 대신 Path를 그리는 분기 하나만 늘었다.

### Legacy 호환 (중요)

- `StickerSource`에 `.doodle` case를 더했다. `.builtIn`은 **legacy로 남긴다** —
  picker에 없고 새로 만들 수 없지만 예전 거울은 계속 그려진다
- 저장 형식 **2 → 3**. v1 · v2 파일은 그대로 읽히고, 예전 앱은 새 파일을 `tooNew`로 보호한다
- `kind`가 없던 시절의 파일도 `builtIn`으로 읽힌다

### 눈으로 확인하고 다시 그린 것

스냅샷을 뽑아보고 **10종을 다시 그렸다** — 꽃(씨앗) · 데이지(해와 구분 안 됨 → 포도알) ·
구름(조약돌) · 불꽃(아몬드) · 클립(타원) · 핀(막대사탕) · 케이크(떠 있는 점) ·
풍선(테두리 없는 원) · 날개하트 · 테이프(배터리).
원인과 규칙은 DESIGN.md "그릴 때 걸린 함정"에 남겼다.

### 함께 고친 버그 (이전 Phase 회귀)

커스텀 시트 안에서 `@Environment(\.dismiss)`를 쓰면 시트가 아니라 **뒤에 있는 Editor**가 닫혔다
("텍스트 추가 → 취소"가 홈으로 나가는 증상). 커스텀 모달만 닫는 `\.inkModalDismiss`를 만들고
시트 내용 7곳을 옮겼다. 구조 테스트로 재발을 막는다.

### 이 Phase에서 하지 않은 것

앱 전체 SF Symbol 교체 · 버튼/시트/다이얼로그 redesign · 폰트 · 종이 texture ·
Store 템플릿 24장 · 카메라 · Mirror geometry · Backend · 조각 economy.

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

## Phase V-5A — Sticker Creator Core (확정)

사용자가 스티커를 만들고, 투명 PNG로 굽고, 다시 편집할 수 있게 했다.
**Sticker Store / My Stickers / 판매 / 구매는 하지 않았다 — V-5B다.**

### 새 편집 엔진을 만들지 않았다

핵심 결정: 스티커 캔버스는 **거울 캔버스와 다른 것이 크기와 바탕뿐**이다.
그래서 `MirrorDesign`에 `canvas: CanvasKind`(mirror / sticker) 한 칸만 더하고,
비율에 의존하는 지점 세 곳만 캔버스를 받게 일반화했다(기본값은 `.mirror`라 기존 호출부는 그대로):

- `EditorCanvasTransform(viewport:state:canvas:)`
- `StickerObject.height(for:aspectRatio:canvas:)`
- `TextLayout.of(_:canvas:)`

그대로 재사용한 것: `EditorSnapshot` · `EditorHistory` · `EditorEdit` · `MirrorEditorCanvas` ·
`EditorGesturePolicy` · `MirrorRenderer` · 모든 도구 시트 · `PhotoStickerMaker`(Vision 배경 제거) ·
`PhotoStickerAssetStore` · 두들 42종 · 글꼴 11종 · 붓 5종.

### 새로 만든 것

| 파일 | 내용 |
|---|---|
| `Editor/StickerCanvas.swift` | `CanvasKind` · 1024² 규격 · 투명 체크무늬 |
| `Editor/StickerProject.swift` | 프로젝트 모델 · 저장 context · 이름 정책 |
| `Editor/StickerRenderer.swift` | 1024² RGBA 투명 PNG |
| `Editor/StickerProjectStore.swift` | 저장소(schemaVersion 1) + `StickerLibrary` |
| `Editor/StickerCreatorView.swift` | Creator 화면 |

### 저장

거울과 **파일을 나눴다**: `sticker-projects.json`(자체 schemaVersion 1) + `UserStickerAssets/<id>.png`.
거울 `mirror-library.json`은 schemaVersion **3 그대로**다 — 스티커가 생겼다고 올리지 않았다.
atomic write · 깨진 파일 격리 · 미래 버전 보호는 `MirrorStore`와 같은 규칙을 따른다.
PNG는 JSON에 base64로 넣지 않는다(테스트로 고정).

### 편집 = 같은 스티커

My Mirrors에서 겪은 "고쳤는데 새 항목이 생기는" 버그를 처음부터 만들지 않았다.
`StickerSaveContext.editExisting`은 같은 id · 이름 · 만든 날짜를 유지하고,
새 id는 `createNew` / `duplicate`만 만든다. 취소는 사본만 버린다.

### 눈으로 확인하고 잡은 것

체크포인트 4장을 렌더해 보니 **사진 레이어가 하나도 안 보였다.** 렌더러는
`PhotoStickerAssetStore.shared`에서 사진을 찾는데 테스트 하네스가 별도 인스턴스에 등록했기 때문이다.
앱 코드는 `.shared`를 쓰므로 제품 버그는 아니었지만, **"주변이 투명하다"만 보던 테스트가
사진이 안 그려진 것을 통과시켰다.** 사진이 실제로 그려지는지 확인하도록 테스트를 고쳤다.

### V-5B pending

내 스티커 목록 화면 · 거울 Editor에서 내 스티커 고르기 · 삭제 UX · Sticker Store ·
Publish Draft · 실제 등록 / 구매 / 정산.

## Phase V-5B (진행) — Sticker resize 수정 + 최대 크기 제한 제거

거울 꾸미기와 스티커 만들기 **양쪽에** 적용했다. 한쪽만 고치면 실패다.

### 찌그러짐 원인

`StickerObject.resized(width:)`가 높이를 `height(for:aspectRatio:)`로 다시 구할 때
**캔버스를 받지 않아 언제나 거울 비율(1080:2340)을 썼다.** 정사각 스티커 캔버스에서
크기를 조절하면 높이가 폭의 0.46배로 계산돼 스티커가 납작해졌다.
→ `resized(width:canvas:)`로 캔버스를 넘긴다.

제스처 자체는 이미 uniform이었다 — `alongWidth`가 스칼라 하나를 넘기고 높이는 파생값이다.
V-1의 rotation-aware projection은 그대로 유지된다.

함께 막은 것: `DoodleInk.draw`가 rect의 width / height를 각각 배율로 쓰고 있었다.
frame이 정사각이 아니면 두들이 늘어난다 → **짧은 변에 맞춰(aspect fit)** 그리게 했다.
지금 데이터는 항상 정사각 frame이라 보이는 크기는 달라지지 않는다.

### 최대 크기 제한 제거

`StickerObject.sizeRange = 0.06...0.45` → `minimumWidth = 0.02`(하한만).
전수 조사 결과 스티커 크기 상한은 이 한 곳뿐이었다(`maxScale` / `maxWidth` 등은 없었다).
`resized`에서 상한 clamp를 없애고, 저장 단계에도 clamp가 없음을 테스트로 고정했다.

- 캔버스보다 2 · 3 · 5배로 키울 수 있고 캔버스를 넘어가도 된다
- 넘어간 부분만 캔버스 경계에서 잘린다 — 렌더러가 오브젝트를 캔버스로 클립한다
  (예전에는 오브젝트가 클립되지 않아 Editor 크롬 위로 새어 나갈 수 있었다)
- viewport 확대(1…4)는 오브젝트 크기를 묶지 않는다
- NaN / 무한 / 0 / 음수는 `resized`와 `constrained`가 걸러낸다

### 마이그레이션

**없다.** schemaVersion을 올리지 않았다(거울 3, 스티커 1 그대로).
기존 저장 데이터는 이미 0.45 이하라 보이는 크기가 그대로다 — 새 크기 조절부터 상한이 없어진다.

기존 테스트 5곳이 `sizeRange`를 참조하고 있어 새 정책에 맞게 고쳤다(삭제 0).

## Phase V-5B — My Stickers + Sticker Store 연결 (확정)

Creator를 실제 사용자 흐름에 연결했다. **Marketplace Backend는 여전히 pending이다.**

### 새로 만든 것

| 파일 | 내용 |
|---|---|
| `Store/StickerStoreView.swift` | 상점의 스티커 칸 — 만들기 · 내 스티커 2열 · 스티커 상점(빈 상태) |
| `Store/PublishStickerView.swift` | 스티커 등록 준비 |
| `Editor/StickerPublishDraft.swift` | Draft 모델 · 정책 · 검사 |

`StoreView`에 `StoreSection`(거울/스티커) 전환을 더했다. Bottom Tab은 그대로 3개다.

### 배치 스냅샷 — 새 case도 schema bump도 없다

내 스티커를 거울에 놓을 때 **완성 PNG를 사진 asset으로 복사**한다.
`.photo`가 이미 "불변 bitmap 참조 + 비율"이므로 새 `StickerSource` case가 필요 없었고,
거울 저장 형식은 **3 그대로**다(억지 bump 없음). 그 결과:

- 원본을 고쳐도 이미 놓인 거울은 그대로 (테스트로 픽셀 비교까지 확인)
- 목록에서 지워도 거울은 깨지지 않음
- 새로 놓으면 최신 디자인
- GC가 분리됨 — 라이브러리 삭제는 `UserStickerAssets`만, 거울 스냅샷은 `PhotoStickerAssets`에서 거울 참조로만 관리

남은 한 가지: 레이어 목록에서 이 스냅샷의 이름이 "내 사진"으로 보인다(`.photo` 재사용의 대가).
이름만을 위해 schema를 올릴 이유가 없어 그대로 뒀다.

### 즉시 갱신

`StickerLibrary`(@Observable) 하나가 진실이다. 화면마다 배열을 따로 두지 않으므로
저장하면 상점의 내 스티커와 Editor picker가 같이 갱신된다. 앱 재실행이 필요 없다.

### 등록 준비

`sticker-publish-drafts.json`(schemaVersion 1). 거울 등록 준비와 파일도 모델도 분리.
**등록 비용은 `nil`(미정)** — 거울의 20 조각을 가져오지 않는다. 조각 변화 0, listing 0.
권리 확인은 필수, 사진이 있으면 공개 안내 확인도 필수.

### 확인하지 못한 것

시뮬레이터 UI를 직접 조작하는 도구를 쓸 수 없어(아래 참고) 화면은
`UIHostingController` 렌더로 확인했다 — 상점 거울/스티커 · 빈 상태 · 내 스티커 4개 2열 ·
picker 두 칸 · 배치 · 2.2배 확대까지 눈으로 봤다. 탭 이동 흐름 자체는 실기기 확인이 필요하다.

### pending

실제 Marketplace(서버 listing · 구매 · 판매자 정산) · 스티커 등록 비용 확정 ·
내 스티커를 거울에 "바로 적용"하는 지름길.

## Architecture Invariant — Infrastructure Isolation

꾸미러 production backend는 **꾸미러 전용 GCP project(`ggumirror-prod`)**에 있다.

DailyOPIc(`opicmobile-45cd5`)은 실제 사용자가 있는 LIVE production이고
꾸미러와 **어떤 product resource도 공유하지 않는다** —
GCP project · Firestore · Storage · Artifact Registry · service account · Firebase ·
RevenueCat · StoreKit product · AdMob app 전부.
공유하는 것은 계정과 billing account뿐이다.

Client가 아는 것은 **API 주소 하나**뿐이다(`BackendEnvironment`).
GCP project id · Firestore database · service account 같은 서버 사정을 client에 넣지 않는다.

이 invariant는 과거 bootstrap 기록보다 우선한다.

## Phase B-2B — Server User Identity + Session (확정)

Apple 로그인이 이제 **꾸미러 서버 계정**으로 이어진다.
Backend 작업은 `ggumirror-be` repo에 있다(별도 commit).

### Client 변경

| 파일 | 내용 |
|---|---|
| `Auth/AppleNonce.swift` | 시도마다 만드는 nonce. Apple에는 SHA-256만, 서버에는 원본 |
| `Auth/ServerSession.swift` | 서버 세션 + Keychain 저장소(identity와 다른 account) |
| `Backend/BackendClient.swift` | URLSession 기반 API client + 주소 · 오류 · JSON |
| `Auth/AuthSession.swift` | signedIn = Apple + **서버 세션**. async 로그인 / 로그아웃 |
| `Auth/AccountSection.swift` | 버튼이 nonce를 만들고, 완료는 서버까지 기다린다 |
| `RootView.swift` | 화면이 뜬 뒤 서버 세션 확인(비동기) |

### 결정한 것

**nonce**: client가 32 byte random을 만들어 `request.nonce`에는 **SHA-256**을 넣고,
서버에는 **원본**을 보낸다. 서버가 다시 해싱해 token claim과 비교한다 —
token만 훔쳐도 우리 서버에 쓸 수 없다. Apple 공식 방식이다.

nonce는 한 시도에만 존재하고 **꺼내는 순간 사라진다.** Keychain · 디스크 · 로그 어디에도
남지 않는다. 버튼을 연달아 눌러 시도가 겹치면 마지막 nonce만 남고, 뒤늦게 도착한 예전
credential은 서버 검증에서 떨어진다 — **잘못 통과하는 쪽이 아니라 실패하는 쪽으로 기운다.**

**로그인의 정의**: `signedIn`은 이제 "Apple identity + 유효한 서버 세션"이다.
Apple UI만 통과하면 signedIn이 아니다. Auth Gate(`requireSignIn` / `takePendingAction`)도
서버 세션까지 확인한다.

**저장**: accessToken · expiresAt · internal userID만 Keychain에 넣는다
(`service` 동일, `account = "server-session"`). identityToken · authorizationCode ·
nonce는 저장하지 않는다. UserDefaults를 쓰지 않는다.

**복원**: 앱은 여전히 Mirror부터 뜬다. 저장된 세션이 유효할 때만 로그인 상태로 시작하고,
서버 확인은 화면이 뜬 뒤 비동기로 한다. 만료된 세션은 로그인으로 인정하지 않되
Apple identity(이름 / 이메일)는 남긴다 — Apple이 다시 주지 않기 때문이다.

**장애**: 서버가 401이든 503이든 network failure든 **거울 · 스티커 · 등록 준비를
하나도 지우지 않고 앱 사용을 막지 않는다.** 실패하는 것은 서버 로그인뿐이다.

**주소**: `BackendEnvironment`. DEBUG는 `http://127.0.0.1:8080`,
release는 **아직 없다**(`nil`). 가짜 production URL을 만들지 않았다 —
그 상태에서 서버 로그인은 "준비 중"으로 실패한다. 배포 Phase에서 채운다.

### 아직 안 한 것

Shard Ledger · shard balance · Store API · Listing · asset upload · actual Publish ·
구매 · 소유권 · 판매자 정산 · Cloud Sync · refresh token · **실제 Cloud Run 배포**.

Auth Gate에 실제 publish / purchase를 연결하지 않았다 — foundation만 서버 인증에 맞췄다.

### 다음

**B-3 Shard Ledger.** 그 전에 Infra Phase(실제 Cloud Run 배포)가 필요하다.

## C-1 Prep — Lock Screen Quick Mirror (조사 확정, 구현 전)

### Locked Camera Capture Extension의 sandbox 제약 (Apple 공식)

이 제약이 C-1 설계를 결정한다.

- **network 접근 불가**
- **App Group shared container read/write 불가**
- **app shared preferences 접근 불가**

그래서 **C-1 때문에 Mirror / Sticker persistence 위치를 바꾸지 않는다.**
`Application Support/ggumirror` 기반 저장은 그대로 둔다.
App Group을 추가하지 않고, 데이터 마이그레이션도 하지 않는다 —
extension이 그 컨테이너를 읽을 수 없으므로 옮겨도 아무 이득이 없고
기존 사용자 데이터만 위험해진다.

extension은 backend도 부르지 못한다(network 불가). 로그인 · 세션 · 상점은
extension의 일이 아니다.

### 앱 ↔ widget ↔ extension 사이의 상태

`CameraCaptureIntent.AppContext`를 쓴다. **JSON 인코딩 4KB 이하**다.

담아도 되는 것: 전면 카메라 선호 · quick mirror preset 식별자 ·
작은 enum / 설정값 · extension UI 구성값.

담지 않는 것: **PNG · 사진 스티커 asset · MirrorDesign 전체 · 사용자 asset blob.**
4KB에 들어가지 않고, 들어가더라도 그렇게 쓸 통로가 아니다.

### 촬영 결과

extension은 `LockedCameraCaptureSession.sessionContentURL`에 쓴다.
본앱은 `LockedCameraCaptureManager`의 `sessionContentURLs` /
`sessionContentUpdates`로 수거한다. 다 쓴 결과는 `invalidateSessionContent(at:)`.

촬영 후 본앱으로 이어야 하면 `session.openApplication(for:)`으로
사용자를 잠금 해제시켜 넘긴다.

### C-1A (MVP)

잠금화면 control → **Quick Mirror**.

- 전면 카메라
- 좌우 반전 preview
- edge-to-edge
- 최소한의 촬영 UI
- 촬영
- 본앱 전환

**사용자의 custom mirror asset을 extension에 복제하지 않는다.**
`MirrorStore` · `StickerStore` · local asset · backend는 건드리지 않는다.

extension은 "앱 열기" 화면이 아니라 **실제 카메라 뷰파인더를 빠르게 띄워야 한다** —
Apple 요구사항이다. `AVCaptureEventInteraction` 등 LockedCameraCapture 요구사항은
구현 시 공식 sample / SDK 기준으로 반영한다.

### C-1B (후속)

잠금화면에서 **사용자의 실제 꾸미러 디자인을 그대로 렌더링**하는 것.
sandbox 제약 안에서 디자인을 어떻게 전달할지 별도로 설계해야 하므로 분리한다.
(4KB appContext로는 안 되고, App Group도 못 쓴다.)

### Target

Apple 공식 문서는 **File → New → Target → Application Extension → Capture Extension**
템플릿 사용을 안내한다. 구현 시작 시 설치된 Xcode에 이 템플릿이 있는지 먼저 확인하고,
**있으면 공식 템플릿을 쓴다.** generic ExtensionKit target에 extension identifier를
직접 넣는 방식은 공식 템플릿을 쓸 수 없을 때만 검토한다.

Control 자체는 WidgetKit `ControlWidget` + `CameraCaptureIntent`다.
잠금화면 control은 **사용자가 잠금화면 편집에서 직접 추가**한다 —
시스템 카메라 버튼을 코드로 교체하는 API는 없다.

전부 iOS 18.0+ API이고 현재 deployment target이 26.2라 `@available` 분기가 필요 없다.

### 실기기 필수

카메라와 잠금화면 control 둘 다 시뮬레이터로 검증할 수 없다.
사용자가 잠금화면 편집에서 control을 추가하고, **기기가 잠긴 상태에서** 눌러 봐야 한다.

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


## Phase V-2 — Editor Navigation UX + Store Content 24/24

PART A — Editor 이동/그리기 UX

- 위 **Editor Gesture Policy (V-2)** 참고. 새 gesture recognizer를 추가하지 않았다 —
  이미 있던 `EditorCanvasGestureOverlay`(1 touch / 2 touch / pinch) 위에서 라우팅만 정리했다.
- Drawing toolbar에 그리기 ↔ 손바닥 잉크 컨트롤 추가. 새 카드 / 모달 없음.
- Rotation(V-1) · Free Canvas drawing · Text 정책은 회귀 없음.

PART B — Store Content

- 실제 손그림 PNG **24 / 24**. procedural / placeholder 템플릿(`StoreCatalog.creators`)은 제거했다.
- 파일: `ggumirror/Resources/StoreTemplates/{Free, RibbonHeart, Diary, Y2K, Moments}/*.png`
  (Xcode의 synchronized group이 번들 루트로 평탄화하므로 `StoreArtworkResource.url`이 파일 이름으로 다시 찾는다.)
- 데이터 모델: `MirrorTemplate.category`(갈래 하나) + `highlights`(추천/인기/신규).
  문자열 Set 하나에 섞지 않는다.
- id / assetID 모두 고정값. 기존 3장(`art-pink-ribbon` / `art-my-diary` / `art-y2k-star`)의
  id와 assetID는 그대로 유지해 이미 받은 데이터와 호환된다.
- 가격은 `StoreCategory.temporaryPrice` 한 곳. **actual Store economy 이전 임시 가격**이다.
- 렌더 파이프라인은 4-2A 그대로: Bundle → `StoreArtworkResource` → `MirrorArtworkImporter.framedArtwork`
  → `registerBundled` → `MirrorPreview`. 새 렌더러를 만들지 않았다.
  구경할 때 memory only / 받을 때 persistToDisk 정책 유지.
