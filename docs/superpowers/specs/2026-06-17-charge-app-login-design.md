# charge_app 소셜 로그인 / 계정 시스템 설계 (Phase 1)

작성일: 2026-06-17

## 목표

charge_app에 **선택형 소셜 로그인**을 도입한다. 목적은 (3) 데이터 동기화 기반 +
(4) 미래 인프라(수익화/쿼터)용 계정 식별. **AI 기능은 지금 막지 않는다** —
사용자 확보가 우선. 로그인은 강제가 아니라 "기기 바꿔도 정보 유지" 혜택으로 유도한다.

### 단계
- **Phase 1 (이 스펙)**: 로그인/계정 인프라 + 마이페이지 + 회원탈퇴 + 콘솔 소셜 표기.
  AI 사용량을 계정 귀속으로 집계(쿼터 대비)하되 한도는 켜지 않음.
- **Phase 2 (추후)**: 차량 프로필 등 동기화(로그인의 실 혜택).
- **Phase 3 (추후)**: 콘솔 원격설정 한도 기반 AI 쿼터 게이트.

## 식별 모델 (확정)

- **로그인/식별 키 = `(provider, provider_uid)`**. 이메일을 PK로 쓰지 않음.
- 프로바이더: **카카오 / 네이버 / 구글** (Android 전용, iOS·Apple 로그인 없음).
- 수집 필드 = 공통 보장 최소: `provider_uid, nickname, profile_image(nullable), email(nullable)`.
  - 카카오 이메일: 선택 동의로 받음(비즈니스 전환 불필요). 이름/성별 등 전환 필요 항목은 안 받음(최소수집).
- **교차 프로바이더 자동 dedup 안 함**: 같은 사람이 프로바이더별로 다른 이메일을 쓰면
  동일인 식별 불가(소셜 공통 person-id 없음) → 그게 정상. 같은 프로바이더 재로그인은
  `provider_uid`로 항상 복구. 교차는 별개 계정으로 수용. (추후 마이페이지 수동 "계정 연결" 가능)

## 데이터 모델

```
users
  id (PK), email (nullable), nickname, profile_image_url (nullable),
  status (active/withdrawn), created_at, last_login_at, withdrawn_at (nullable)

user_social_accounts
  id (PK), user_id (FK), provider (kakao/naver/google), provider_uid,
  email (nullable), linked_at,
  UNIQUE(provider, provider_uid)

app_devices (기존 + 추가)
  + user_id (nullable)   ← 로그인 시 기기↔계정 연결, 콘솔 디바이스탭 소셜 표기용
```

## 인증 흐름

```
앱: 소셜 SDK 로그인 → access_token 획득
앱 → 서버 POST /api/auth/{kakao|naver|google}  { token, deviceId }
서버: 프로바이더 userinfo API로 토큰 검증(서버측, 클라 프로필 신뢰 X)
      → provider_uid/email/nickname 획득
      → users / user_social_accounts upsert
      → app_devices.user_id 연결
      → 우리 JWT 발급
앱: JWT를 secure storage 저장, 이후 인증요청 Authorization 헤더에 사용
```
- 백엔드: charge_server(charge.dksw4.com) 유력. maccha_app `/auth/kakao` 패턴 재활용.
- 콘솔 디바이스탭이 소셜 가입을 표기하려면 users/social 테이블을 콘솔이 조회 가능해야 함
  (DB 위치는 구현 시 확정 — 같은 MySQL 인스턴스면 조인, 아니면 콘솔이 charge_server 조회).

## 회원탈퇴 (필수)

- 마이페이지 → 회원탈퇴 진입 → 확인 → 서버 `DELETE /api/auth/me` (또는 POST /withdraw).
- 처리: `users.status=withdrawn` + 개인정보 파기(개인정보보호법) — nickname/email/profile/social_uid
  삭제 또는 비식별화. `app_devices.user_id` 해제.
- 동의 증빙(app_user_consents)은 법정 보존 필요 범위만 device 기준으로 남길지 검토(개인정보 분리).
- 탈퇴 후 같은 소셜로 재로그인 = 신규 가입으로 취급.

## 화면 (charge_app)

- **마이페이지** (현 설정 화면 개편, 바텀탭 "설정"→"마이페이지"):
  - 비로그인: 상단 카드 "로그인이 필요합니다 >" + "폰을 바꿔도 정보가 저장돼요" + 아바타 placeholder.
    탭 → 로그인 화면.
  - 로그인: 닉네임/프로필 표시 + 로그아웃 + 회원탈퇴 진입.
  - 하단: 기존 설정 항목(공지/이벤트/FAQ/정책/알림설정 등) 유지.
- **로그인 화면**: 카카오/네이버/구글 3버튼(브랜드 컬러), 약관 안내. (최고 퀄 UI)
- UI는 charge_app AppTokens 디자인 시스템에 맞춰 폴리시.

## 콘솔 디바이스탭

- `app_devices.user_id` → `user_social_accounts` 조인 → 행마다 "가입(카카오/네이버/구글)" 뱃지.

## 외부 의존성 (사용자 준비 필요)

- 카카오: 네이티브 앱 키 + 키 해시(Android) 등록
- 네이버: Client ID/Secret + 앱 등록
- 구글: OAuth 클라이언트 + SHA-1 등록

## Phase 1 범위 밖 (명시)

- 차량 프로필/설정/즐겨찾기 동기화 (Phase 2)
- AI 쿼터 한도 실제 적용 (Phase 3) — 단 사용량 계정 귀속 집계는 Phase 1에서 준비

## 빌드 순서

1. 마이페이지 + 로그인 화면 **UI** (키 없이 제작, 폰 확인 가능) ← 먼저
2. (키 수령 후) 소셜 SDK 연동 + 서버 인증 API + JWT + 기기연결
3. 회원탈퇴
4. 콘솔 디바이스탭 소셜 표기
5. AI 사용량 계정 귀속 집계
