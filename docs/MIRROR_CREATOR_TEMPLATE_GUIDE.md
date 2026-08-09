# MIRROR Creator Template Guide v0.1

## 1. 목적

외부 툴(Figma, Procreate, Photoshop 등)에서 제작한 거울 프레임 디자인을
MIRROR 앱에 안정적으로 가져오기 위한 기본 제작 규격을 정의한다.

핵심 원칙은 다음과 같다.

- 상·하·좌·우 4장의 이미지를 각각 받지 않는다.
- 하나의 전체 프레임 마스터 이미지를 업로드한다.
- 앱 내부에서 상·하·좌·우 영역을 계산해 렌더링한다.
- 모서리 연결은 항상 하나의 원본 이미지 기준으로 유지한다.

## 2. 기본 업로드 포맷

### Master Frame

- 크기: 1080 × 2340 px
- 비율: 9 : 19.5
- 포맷: PNG
- 배경: 투명
- 색공간: sRGB 권장

중앙 거울 영역은 투명하게 유지하고,
장식은 외곽 프레임 영역을 중심으로 배치한다.

## 3. 프레임 영역

### Engine Requirement (반드시 지켜야 하는 것)

- Canvas: 1080 × 2340
- 중앙 Mirror Area는 투명
- 프레임 두께는 normalized 값(0...1)으로 표현된다
- 상·하·좌·우 네 방향 두께를 각각 다르게 가질 수 있다

앱의 Editor engine은 고정 두께를 가정하지 않는다.
거울마다 `MirrorFrameInsets(top / right / bottom / left)`를 따른다.
특정 px 값을 canonical thickness로 사용하지 않는다.

### Recommended Starting Point (권장 시작점)

1080 × 2340 master 기준:

| 면 | px | normalized |
|---|---|---|
| Left | 108 | 0.10 |
| Right | 108 | 0.10 |
| Top | 180 | 약 0.0769 |
| Bottom | 180 | 약 0.0769 |

중앙 Mirror Area: 864 × 1980

의도:

- 좌우는 얇게 — 얼굴 시야를 최대한 확보한다
- 상·하는 조금 더 넓게 — 그림 / 텍스트 / 스티커를 넣을 공간을 둔다

이 값은 현재 기본 거울이 쓰는 값이자 새 템플릿의 출발점이다.

### Decorative Template (예시)

Store처럼 장식이 많은 템플릿은 개별 frameInsets를 더 넓게 가질 수 있다.

예:

- Left / Right: 약 0.17
- Top / Bottom: 약 0.115

이건 decorative template 예시일 뿐 기본 규격이 아니다.
어느 값이든 앱은 normalized coordinate로 렌더링한다.

참고: 과거 가이드의 216 px (Canvas Width의 20%)는 초기 reference였고
현재 기본값이 아니다.

## 4. 제작 구조

권장 마스터 구조:

┌─────────────────────────────┐
│            TOP              │
│                             │
├─────┐                 ┌─────┤
│     │                 │     │
│LEFT │   MIRROR AREA   │RIGHT│
│     │  TRANSPARENT    │     │
│     │                 │     │
├─────┘                 └─────┤
│           BOTTOM            │
│                             │
└─────────────────────────────┘

전체 파일은 하나의 PNG다.

앱 내부에서 필요한 경우 TOP / BOTTOM / LEFT / RIGHT 영역을
sourceRect 기준으로 잘라서 사용한다.

원본 파일 자체를 4개의 별도 자산으로 분리하는 것은 기본 정책이 아니다.

## 5. 모서리 연속성

TOP / LEFT / RIGHT / BOTTOM은 시각적으로 하나의 프레임이어야 한다.

따라서 네 모서리 장식이 자연스럽게 연결되도록 하나의 캔버스에서 제작한다.

리본, 선, 패턴, 장식 등이 모서리를 넘어가는 디자인도 허용한다.

## 6. 기기별 대응 원칙

iPhone 기종마다 화면 비율이 다르기 때문에
1080 × 2340 이미지를 모든 화면에 X/Y 독립 Stretch하지 않는다.

금지:

- 가로만 늘이기
- 세로만 늘이기
- 원, 리본, 캐릭터 등이 찌그러지는 비균등 스케일

권장:

- Uniform Scale
- Crop
- Extend
- Safe Frame 기준 보정

외부 이미지 템플릿은 원본 비율을 유지하는 것을 우선한다.

## 7. 앱 내부 제작 템플릿과의 차이

### Native Template

앱 내부 Editor에서 만든 템플릿.

위치와 크기를 0~1 범위 normalized coordinate로 저장한다.

예:

x = 0.14
y = 0.82
width = 0.18

장점:

- 다양한 iPhone 화면 대응
- 수정 가능
- Remix 가능
- 객체 단위 편집 가능

### Image Template

외부 제작 도구에서 만든 완성형 프레임.

기본 입력:

- 1080 × 2340
- 투명 PNG 1장

앱에서 화면 비율에 맞게 매핑한다.

## 8. 업로드 UX

MVP의 Creator Upload는 단순하게 유지한다.

1. 전체 프레임 PNG 선택
2. 규격 검사
3. 전체 미리보기
4. 여러 iPhone 비율 미리보기
5. 필요 시 위치/Scale 보정
6. 저장 또는 Store 등록

## 9. 업로드 검증

업로드 시 최소 검증 항목:

- PNG 여부
- 1080 × 2340 권장 규격 여부
- 투명 영역 존재 여부
- 파일 용량
- 중앙 거울 영역 가림 정도
- 중요한 장식의 Safe Frame 이탈 여부

권장 규격과 다를 경우 자동 변환 또는 사용자 보정을 제공할 수 있다.

## 10. Compact / Legacy 대응

기본 Master는 9:19.5 하나만 필수로 한다.

향후 필요 시 추가 변형을 지원할 수 있다.

Optional Compact Master:

- 1080 × 1920
- 9 : 16

초기 MVP에서는 필수가 아니다.

## 11. MVP 결정사항

초기 버전에서는:

- 전체 프레임 PNG 1장 업로드만 지원
- 1080 × 2340 / 9:19.5를 기준 Master로 사용
- 중앙 거울 영역은 투명
- 프레임 두께는 고정값이 아니라 normalized frameInsets로 다룬다
- 앱 내부에서 상·하·좌·우 영역 계산
- 모서리 연속성 유지
- 비균등 Stretch 금지
- 기기별 Uniform Scale + Crop/Extend
- 앱 내부 제작물은 normalized coordinate 사용

향후 고급 크리에이터 기능으로:

- 4면 개별 업로드
- Compact/Legacy 전용 Master
- 반복 패턴형 Edge Asset
- 기기군별 커스텀 보정

등을 검토한다.

## 12. 핵심 원칙 요약

Creator에게는 한 장.

앱 내부에서는 네 면.

사용자에게는 하나의 거울.

이 구조를 MIRROR 템플릿 시스템의 기본 원칙으로 한다.
