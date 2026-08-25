<div align="center">

# 꾸미러 · Ggumirror

### 거울을 직접 꾸미고 공유하는 커스터마이징 앱

스티커 · 사진 · 그리기 · 텍스트 · 프레임을 활용해  
나만의 거울을 만들고, 다른 사용자의 디자인을 구매·판매할 수 있는 서비스입니다.

[Portfolio](https://mark77234.github.io/portfolio/)

</div>

---

## 프로젝트

- **형태**: 개인 프로젝트
- **역할**: 서비스 기획 · iOS · Backend · Infra 개발
- **상태**: 개발 및 운영 중

거울이라는 단순한 도구에

**꾸미기 → 저장 → 미리보기 → 마켓 등록 → 구매 → 적용**

흐름을 결합해 하나의 커스터마이징 서비스로 만들었습니다.

---

## 주요 기능

- 스티커 · 사진 · 그리기 · 텍스트 기반 거울 꾸미기
- Background 제거 사진 배치
- Frame · Background · Layer 편집
- 내가 만든 거울 저장 및 관리
- 다른 사용자의 거울 **미리보기 · 구매 · 적용**
- Apple 로그인 기반 Marketplace
- 자체 재화 **조각**을 활용한 구매·판매
- 판매 중인 거울 관리

---

## Tech Stack

`Swift` `SwiftUI`

`Cloud Run` `Firebase`

`Apple Sign In` `In-App Purchase`

`Google Cloud Storage` `Docker`

---

## Engineering

### 비로그인 기능과 Marketplace 인증 분리

거울 보기와 편집은 로그인 없이 바로 사용할 수 있도록 하고,  
구매 · 판매처럼 사용자 식별이 필요한 기능에만 **Apple 로그인**을 적용했습니다.

사용자가 앱을 처음 실행하자마자 핵심 기능을 사용할 수 있도록  
인증을 서비스 진입 조건으로 두지 않았습니다.

### 거울 디자인을 Marketplace Asset으로

사용자가 제작한 거울을 단순 이미지가 아니라  
다른 사용자가 다시 자신의 거울에 적용할 수 있는 Marketplace Item으로 구성했습니다.

판매자는 가격을 설정해 디자인을 등록하고,  
구매자는 실제 자신의 거울에 먼저 적용해 본 뒤 구매할 수 있습니다.

### 구매와 재화 검증을 서버에서

Marketplace에서는 앱 내부 재화인 **조각**을 사용합니다.

구매 · 판매와 관련된 상태를 Client만 신뢰하지 않고  
Backend에서 사용자와 거래 상태를 검증하도록 구성했습니다.

---

## Product

꾸미러는 기능만 구현하는 프로젝트가 아니라  
직접 서비스 구조와 경제 시스템까지 설계하며 개발하고 있습니다.

- 로그인 없이 사용할 수 있는 핵심 거울 기능
- Apple 로그인 기반 Marketplace
- 출석 · 광고 · 구매를 통한 조각 획득
- 거울 제작 비용과 판매 가격
- 구매 전 실제 거울 미리보기
- 판매자/구매자 상태 관리

---

<div align="center">

[GitHub](https://github.com/mark77234/ggumirror) ·
[Portfolio](https://mark77234.github.io/portfolio/) ·
[Resume](https://mark77234.github.io/resume/)

</div>
