# charge_app 진입 플로우 개편 — 로그인 게이트 + 게스트 + 이벤트 팝업 (Phase A)

작성일: 2026-06-18
범위: 클라이언트(charge_app) 전용. 서버 변경 없음.

## 목적

앱 첫 진입 흐름을 **splash → 로그인/회원가입 게이트 → 권한 → 온보딩 → (게스트) 이벤트 팝업 → 홈** 으로 개편한다.
- 로그인/회원가입을 첫 진입 게이트로 올리되, 하단 "게스트로 시작하기"로 비회원도 즉시 사용 가능
- 게스트에게 기기 변경 시 데이터 비유지 경고
- 온보딩을 끝낸 게스트에게 이벤트·혜택 알림 옵트인 팝업 1회 노출
- 설정의 이벤트 알림 토글에서 "회원가입 후 이용" 차단 제거 (게스트도 ON 가능)

## 비범위 (명시)

- 회원 데이터 서버 영속화, 게스트→회원 데이터 이관: **Phase B/C** 에서 별도 설계
- 알림 구독 서버 동기화: 기존 device_id 방식 그대로 유지 (변경 없음)
- 위치 권한 하드블록: 채택 안 함 (아래 "위치 권한" 참조)

## 현재 상태 (기준선)

- 진입 라우팅: [splash_screen.dart](../../../lib/ui/splash/splash_screen.dart) `_navigateNext()` —
  `settings.onboardingDone ? '/home' : '/permission'`. 로그인 화면은 진입 게이트가 아니라 홈 계정카드에서 push 되는 선택 화면.
- 로그인 화면: [login_screen.dart](../../../lib/ui/auth/login_screen.dart) — 소셜 로그인 성공 시 `Navigator.pop(true)`. 게스트 버튼 없음.
- 권한: [permission_screen.dart](../../../lib/ui/permission/permission_screen.dart) — 위치 요청 후 `/onboarding`. 거부해도 진입 가능한 소프트 동작 + 위치 필요 동작에서 컨텍스트 다이얼로그(이미 구현).
- 온보딩: [onboarding_screen.dart](../../../lib/ui/onboarding/onboarding_screen.dart) `_finish()` — 설정 저장 + `completeOnboarding()`(onboardingDone=true) + `/home`.
- 이벤트 팝업: [marketing_reprompt.dart](../../../lib/ui/widgets/marketing_reprompt.dart) `maybeShowChargeMarketingReprompt()` — 홈 진입 시 `shouldShowMarketingReprompt()`(콘솔 ON + 미동의 + 오늘 미노출) 게이팅으로 노출.
- 설정 이벤트 알림 토글: [home_screen.dart](../../../lib/ui/home/home_screen.dart) `_promptLogin()` — 비로그인이면 "회원가입 후 이용" 스낵바로 차단.
- 인증 상태: `authProvider == null` → 게스트, `!= null` → 로그인.

## 설계

### 1. 진입 라우팅 (splash)

`_navigateNext()` 를 아래 결정표로 교체한다. 위치 권한은 라우팅 조건에서 제외(소프트).

| 상태 판별 | 결과 |
|---|---|
| `onboardingDone == true` | `/home` |
| `onboardingDone == false` 이고 (로그인됨 `authProvider != null` **또는** `guest_started == true`) | `/permission` → (이후 `/onboarding` 재개) |
| `onboardingDone == false` 이고 위 둘 다 아님 (완전 첫 실행) | `/login` (게이트 모드) |

- 게이트는 "로그인/게스트 선택 전" 한 번만 노출. 회원=토큰, 게스트=`guest_started` 플래그로 "선택 완료"를 판별하므로, 온보딩을 중간에 중단해도 다음 실행에서 게이트가 아니라 온보딩 재개로 진입.
- 라우팅 시점에 `authProvider` 의 토큰 복원이 완료돼 있어야 한다. splash 의 bootstrap 완료 후 인증 상태가 로드된 뒤 분기하도록 보장한다.

### 2. 로그인/회원가입 게이트

[login_screen.dart](../../../lib/ui/auth/login_screen.dart) 를 재사용하고 `gate` 모드를 추가한다 (별도 화면 신설 X).

게이트 모드 동작:
- 소셜 로그인 성공:
  - 미완성 계정(`!signupCompleted`) → 기존대로 `SignupCompleteScreen`(닉네임·약관·마케팅 동의) → 완료 시
  - **`pop` 대신 `/permission` 으로 전진** (`context.go('/permission')`)
- 하단 **"게스트로 시작하기"** 버튼 노출 (게이트 모드에서만):
  - 탭 → 경고 `AlertDialog`
    - 문구: "기기를 바꾸면 차량정보·설정이 유지되지 않아요." (회원가입 시 유지됨을 안내)
    - 버튼: `[그래도 시작]` / `[취소]`
  - "그래도 시작" → `guest_started = true` 저장 → `/permission` 전진
- **뒤로가기 차단** (`PopScope(canPop: false)`) — 게이트에서는 로그인 또는 게스트 중 하나 필수.

비(非)게이트 모드(홈 계정카드에서 `/login` 호출): 기존 동작 유지 — `pop(true)`, 게스트 버튼 없음, 뒤로가기 허용.

### 3. 권한 → 온보딩

- `/permission` 는 위치 요청만 하고 **거부해도 통과**(소프트). 하드블록·스킵차단 없음.
- `/permission` 의 "다음 목적지" 를 `onboardingDone ? '/home' : '/onboarding'` 로 결정한다.
  - 신규/재개 사용자: 위치 단계 후 `/onboarding`
  - 재방문자가 위치 재허용 등으로 권한 화면을 거친 경우: 온보딩 재실행 없이 `/home`
- 알림 권한(온보딩 마지막 스텝)은 기존대로 선택("나중에" 허용).

### 4. 온보딩 끝 이벤트 팝업 (게스트 1회)

- 온보딩 `_finish()`: `completeOnboarding()` 직후, **게스트(`authProvider == null`)인 경우에만** `pending_event_optin = true` 저장 후 `/home`.
- 홈 진입 postFrame 시퀀스([home_screen.dart](../../../lib/ui/home/home_screen.dart) 의 `maybeShowChargeMarketingReprompt`/`PopupNoticeDialog` 묶음)에서:
  - `pending_event_optin == true` 이면 → **콘솔/하루1회 게이팅을 무시하고 무조건** 이벤트 팝업 1회 표시 → 플래그 클리어
  - 팝업 본문/디자인은 기존 [marketing_reprompt.dart](../../../lib/ui/widgets/marketing_reprompt.dart) 재사용. 게이팅만 우회하는 변형 진입점 또는 파라미터(`force: true`)를 추가한다.
- 회원은 가입 시트에서 이미 마케팅 동의를 받았으므로 `pending_event_optin` 을 켜지 않음 → 스킵.
- 기존 홈 리프롬프트(`maybeShowChargeMarketingReprompt`, 콘솔 게이팅)는 "나중에" 누른 사용자 재유도용으로 **그대로 유지**.

### 5. 설정 이벤트 알림 토글 차단 해제

[home_screen.dart](../../../lib/ui/home/home_screen.dart) 의 이벤트·혜택 알림 토글:
- 비로그인 차단(`_promptLogin()` 스낵바 "이벤트·혜택 알림은 회원가입 후 이용할 수 있어요") **제거**.
- `handle(v)` 가 로그인 여부와 무관하게 `_set(v)` 호출 → `DkswCore.postConsents(marketing)` (device 기반이라 게스트도 동작).
- 회원가입 시 동의 시트가 최종 동의값을 덮어쓰므로 재동의 일관성 유지.

## 신규 저장 키 (settings box)

| 키 | 타입 | 의미 |
|---|---|---|
| `guest_started` | bool | 게스트 "그래도 시작" 선택 완료. 게이트 재노출 방지 + 온보딩 재개 판별 |
| `pending_event_optin` | bool | 온보딩 끝낸 게스트에게 홈에서 이벤트 팝업 1회 노출 대기. 표시 후 클리어 |

## 엣지 케이스

- **회원가입 후 온보딩 중단 → 재실행**: 토큰 존재 + onboardingDone=false → 게이트 스킵, `/permission`→`/onboarding` 재개.
- **게스트 선택 후 온보딩 중단 → 재실행**: `guest_started=true` + onboardingDone=false → 게이트 스킵, 온보딩 재개.
- **재방문자가 OS 설정에서 위치 끔**: 하드블록 안 함. 홈 진입은 허용되고, 위치 필요한 동작에서 기존 컨텍스트 다이얼로그가 유도.
- **게스트가 이벤트 팝업에서 "나중에"**: `pending_event_optin` 은 표시 시점에 클리어되므로 재노출 안 됨. 이후엔 홈 리프롬프트(콘솔 게이팅)만 재유도.
- **게이트에서 로그인 도중 SignupComplete 취소(로그아웃)**: 게이트 화면 유지(전진 X), 다시 로그인 또는 게스트 선택 가능.

## 위치 권한 (결정 사항)

소프트 게이트 채택. 위치 거부 시 앱 진입을 막지 않는다. 근거:
- 현재 앱이 이미 소프트 방식(진입 허용 + 위치 필요 동작 시 컨텍스트 다이얼로그/스낵바)으로 동작하며 검증돼 있음.
- 하드블록은 기존 UX 대비 퇴행이고 이탈 위험. 실시간 resume 가드도 동반 제거.

## 검증 관점

- 신규 설치 첫 실행: 게이트 노출 → 게스트 시작 경고 → 권한 → 온보딩 → 홈에서 이벤트 팝업 1회.
- 신규 설치 첫 실행 + 소셜 로그인: 게이트 → (SignupComplete) → 권한 → 온보딩 → 홈(이벤트 팝업 없음).
- 온보딩 중단 후 재실행: 회원/게스트 모두 게이트 없이 온보딩 재개.
- 재방문자: splash → 홈 직행.
- 설정 토글: 게스트 상태에서 이벤트 알림 ON/OFF 정상 동작(스낵바 차단 없음).
- 홈 계정카드 → 로그인: 기존 동작(게스트 버튼 없음, pop) 회귀 없음.
