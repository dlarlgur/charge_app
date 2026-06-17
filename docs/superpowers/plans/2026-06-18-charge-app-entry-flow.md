# 진입 플로우 개편 (Phase A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** splash → 로그인 게이트(게스트 포함) → 권한 → 온보딩 → (게스트) 이벤트 팝업 → 홈 진입 흐름으로 개편하고, 설정 이벤트 알림 토글의 비로그인 차단을 제거한다.

**Architecture:** 기존 화면 재사용 + Hive `settings` 박스에 2개 플래그(`guest_started`, `pending_event_optin`) 추가. splash 라우팅을 결정표로 교체, login_screen에 `gate` 모드 추가, permission/onboarding/home에 최소 분기 삽입. 서버 변경 없음.

**Tech Stack:** Flutter, Riverpod(StateNotifier), go_router, Hive, dksw_app_core(consent), permission_handler.

**테스트 전략(중요):** 이 repo는 위젯/유닛 테스트 스위트가 없고, 앱 빌드/설치는 사용자가 직접 `flutter run` 으로 수행한다(서명 불일치로 데이터 wipe 방지). 따라서 각 태스크의 자동 검증은 **`flutter analyze`** (정적 분석, 설치 없음)로 하고, 런타임 동작은 마지막 **수동 검증 체크리스트**로 사용자가 확인한다. TDD 표준에서 벗어나지만 이 프로젝트의 제약(테스트 부재 + 빌드 정책)을 우선한다.

**Spec:** [docs/superpowers/specs/2026-06-18-charge-app-entry-flow-design.md](../specs/2026-06-18-charge-app-entry-flow-design.md)

---

## File Structure

| 파일 | 변경 | 책임 |
|---|---|---|
| `lib/core/constants/api_constants.dart` | Modify | 신규 키 2개 상수 추가 |
| `lib/providers/providers.dart` | Modify | SettingsNotifier에 guestStarted 상태 + pending optin 접근자 |
| `lib/ui/auth/login_screen.dart` | Modify | `gate` 모드: 성공/게스트 시 `/permission` 전진, 게스트 버튼, 뒤로가기 차단 |
| `lib/router/app_router.dart` | Modify | `/login?gate=1` 쿼리 → `LoginScreen(gate: true)` |
| `lib/ui/splash/splash_screen.dart` | Modify | `_navigateNext()` 결정표 교체 |
| `lib/ui/permission/permission_screen.dart` | Modify | 다음 목적지 = `onboardingDone ? /home : /onboarding` |
| `lib/ui/onboarding/onboarding_screen.dart` | Modify | `_finish()`에서 게스트면 pending optin 플래그 set |
| `lib/ui/widgets/marketing_reprompt.dart` | Modify | `force` 파라미터로 게이팅 우회 |
| `lib/ui/home/home_screen.dart` | Modify | pending optin 1회 팝업 트리거 + 토글 비로그인 차단 제거 |

---

### Task 1: settings 플래그 인프라 (상수 + Notifier)

**Files:**
- Modify: `lib/core/constants/api_constants.dart:133`
- Modify: `lib/providers/providers.dart:65-156`

- [ ] **Step 1: 상수 2개 추가**

`lib/core/constants/api_constants.dart` 의 `keyHomeTabOrder` 라인(133) 바로 아래에 추가:

```dart
  static const keyHomeTabOrder = 'home_tab_order'; // 0=주유 먼저, 1=충전 먼저

  // ── 진입 플로우 (Phase A) ──
  static const keyGuestStarted = 'guest_started'; // 게스트 "그래도 시작" 선택 완료
  static const keyPendingEventOptin = 'pending_event_optin'; // 온보딩 끝낸 게스트 홈 이벤트 팝업 대기
```

- [ ] **Step 2: SettingsState 에 guestStarted 추가**

`lib/providers/providers.dart` 의 `SettingsState` 를 아래로 교체 (필드/생성자/copyWith 세 곳):

```dart
class SettingsState {
  final bool onboardingDone;
  final bool aiOnboardingDone;
  final VehicleType vehicleType;
  final FuelType fuelType;
  final List<String> chargerTypes;
  final int radius;
  final int defaultTab;
  final bool guestStarted;

  const SettingsState({
    this.onboardingDone = false,
    this.aiOnboardingDone = false,
    this.vehicleType = VehicleType.gas,
    this.fuelType = FuelType.gasoline,
    this.chargerTypes = const ['01', '04'],
    this.radius = 5000,
    this.defaultTab = 0,
    this.guestStarted = false,
  });

  SettingsState copyWith({
    bool? onboardingDone, bool? aiOnboardingDone, VehicleType? vehicleType, FuelType? fuelType,
    List<String>? chargerTypes, int? radius, int? defaultTab, bool? guestStarted,
  }) {
    return SettingsState(
      onboardingDone: onboardingDone ?? this.onboardingDone,
      aiOnboardingDone: aiOnboardingDone ?? this.aiOnboardingDone,
      vehicleType: vehicleType ?? this.vehicleType,
      fuelType: fuelType ?? this.fuelType,
      chargerTypes: chargerTypes ?? this.chargerTypes,
      radius: radius ?? this.radius,
      defaultTab: defaultTab ?? this.defaultTab,
      guestStarted: guestStarted ?? this.guestStarted,
    );
  }
}
```

- [ ] **Step 3: _load 에 guestStarted 로드 + 메서드 3개 추가**

`SettingsNotifier._load()` 의 `state = SettingsState(...)` 마지막 인자에 추가:

```dart
      defaultTab: _box.get(AppConstants.keyDefaultTab, defaultValue: 0),
      guestStarted: _box.get(AppConstants.keyGuestStarted, defaultValue: false),
    );
```

그리고 `completeOnboarding()` 메서드 아래에 추가:

```dart
  void markGuestStarted() {
    state = state.copyWith(guestStarted: true);
    _box.put(AppConstants.keyGuestStarted, true);
  }

  // 온보딩 끝낸 게스트 → 홈에서 이벤트 팝업 1회. UI 반응 불필요해 state 미포함.
  bool get pendingEventOptin =>
      _box.get(AppConstants.keyPendingEventOptin, defaultValue: false) as bool;

  void setPendingEventOptin(bool v) => _box.put(AppConstants.keyPendingEventOptin, v);
```

- [ ] **Step 4: 정적 분석**

Run: `cd /Users/ghim/my_business/charge_app && flutter analyze lib/providers/providers.dart lib/core/constants/api_constants.dart`
Expected: No issues found (또는 기존 무관 경고만).

- [ ] **Step 5: Commit**

```bash
git add lib/core/constants/api_constants.dart lib/providers/providers.dart
git commit -m "feat(entry): guest_started/pending_event_optin 플래그 인프라"
```

---

### Task 2: 로그인 게이트 모드

**Files:**
- Modify: `lib/ui/auth/login_screen.dart`

- [ ] **Step 1: import 추가**

`lib/ui/auth/login_screen.dart` 상단 import 블록에 추가:

```dart
import 'package:go_router/go_router.dart';
import '../../providers/providers.dart';
```

- [ ] **Step 2: gate 파라미터 추가**

`LoginScreen` 위젯을 교체:

```dart
/// 소셜 로그인 화면. 카카오 / 네이버 / 구글.
/// [gate]=true 면 첫 진입 게이트 모드: 성공/게스트 시 pop 대신 /permission 전진,
/// 하단 "게스트로 시작" 노출, 뒤로가기 차단.
class LoginScreen extends ConsumerStatefulWidget {
  final bool gate;
  const LoginScreen({super.key, this.gate = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}
```

- [ ] **Step 3: 로그인 성공 시 게이트면 전진**

`_onProvider` 의 성공 분기에서 `Navigator.of(context).pop(true);` (현재 39행) 를 교체:

```dart
        if (mounted) {
          if (widget.gate) {
            context.go('/permission');
          } else {
            Navigator.of(context).pop(true);
          }
        }
        return;
```

- [ ] **Step 4: 게스트 시작 메서드 추가**

`_showEmailInUse` 메서드 아래에 추가:

```dart
  Future<void> _startGuest() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('게스트로 시작'),
        content: const Text(
          '기기를 바꾸면 차량 정보·설정이 유지되지 않아요.\n'
          '회원가입하면 기기를 바꿔도 그대로 유지돼요.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('그래도 시작')),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    ref.read(settingsProvider.notifier).markGuestStarted();
    if (mounted) context.go('/permission');
  }
```

- [ ] **Step 5: 뒤로가기 차단 + 게스트 버튼 + 닫기버튼 숨김**

`build()` 의 최상위 `return Scaffold(...)` 를 `PopScope` 로 감싸고(게이트면 canPop:false), 닫기(X) 버튼을 게이트가 아닐 때만 표시, 약관 안내 문구 아래에 게스트 버튼을 게이트일 때만 추가한다.

(a) `return Scaffold(` 를 교체:

```dart
    return PopScope(
      canPop: !widget.gate,
      child: Scaffold(
```

그리고 `build()` 의 마지막 닫는 괄호 `);` (현재 185~186행, Scaffold 닫힘)를 `));` 로 바꿔 PopScope 까지 닫는다.

(b) 닫기(X) 버튼 `Align(...IconButton...)` (현재 86~95행)을 게이트가 아닐 때만 렌더:

```dart
                if (!widget.gate)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
                      child: IconButton(
                        icon: Icon(Icons.close_rounded, color: textSecondary),
                        onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
```

(c) 약관 안내 문구 `Padding(...'로그인 시 이용약관...')` (현재 163~174행) 바로 아래에 게스트 버튼 추가:

```dart
                if (widget.gate)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                    child: TextButton(
                      onPressed: _busy ? null : _startGuest,
                      child: Text(
                        '게스트로 시작하기',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ),
```

- [ ] **Step 6: 정적 분석**

Run: `cd /Users/ghim/my_business/charge_app && flutter analyze lib/ui/auth/login_screen.dart`
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/auth/login_screen.dart
git commit -m "feat(entry): 로그인 게이트 모드 + 게스트로 시작하기"
```

---

### Task 3: router — /login gate 쿼리 파라미터

**Files:**
- Modify: `lib/router/app_router.dart:48`

- [ ] **Step 1: /login 라우트가 gate 쿼리 해석**

`GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),` (48행) 을 교체:

```dart
      GoRoute(
        path: '/login',
        builder: (_, state) =>
            LoginScreen(gate: state.uri.queryParameters['gate'] == '1'),
      ),
```

- [ ] **Step 2: 정적 분석**

Run: `cd /Users/ghim/my_business/charge_app && flutter analyze lib/router/app_router.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/router/app_router.dart
git commit -m "feat(entry): /login?gate=1 → 게이트 모드 라우팅"
```

---

### Task 4: splash 라우팅 결정표

**Files:**
- Modify: `lib/ui/splash/splash_screen.dart:149-160`

- [ ] **Step 1: import 추가**

`lib/ui/splash/splash_screen.dart` import 블록에 추가:

```dart
import '../../data/services/auth_service.dart';
```

- [ ] **Step 2: _navigateNext 교체**

`_navigateNext()` (149~160행) 을 교체:

```dart
  void _navigateNext() {
    if (_routed || !mounted) return;
    _routed = true;
    // 진입 결정표 (위치 권한은 소프트 — 라우팅 조건 아님):
    //  - onboardingDone        → /home (재방문자)
    //  - 로그인됨 or 게스트선택 → /permission (온보딩 재개)
    //  - 그 외(완전 첫 실행)    → /login 게이트
    final settings = ref.read(settingsProvider);
    if (settings.onboardingDone) {
      context.go('/home');
      return;
    }
    final loggedIn = ref.read(authProvider) != null;
    if (loggedIn || settings.guestStarted) {
      context.go('/permission');
    } else {
      context.go('/login?gate=1');
    }
  }
```

> 참고: `authProvider._load()` 는 비동기로 토큰을 복원한다. splash 는 bootstrap(최대 4s)을 await 한 뒤 라우팅하므로 그 시점엔 복원이 끝나 있다. 만약 미복원 상태에서 로그인 회원이 "완전 첫 실행" 으로 오판될 극히 드문 레이스가 있어도, 다음 실행에 정상 복구된다(데이터 손실 없음).

- [ ] **Step 3: 정적 분석**

Run: `cd /Users/ghim/my_business/charge_app && flutter analyze lib/ui/splash/splash_screen.dart`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/splash/splash_screen.dart
git commit -m "feat(entry): splash 진입 결정표 (게이트/재개/홈)"
```

---

### Task 5: permission 다음 목적지

**Files:**
- Modify: `lib/ui/permission/permission_screen.dart`

- [ ] **Step 1: import + 헬퍼 추가**

`lib/ui/permission/permission_screen.dart` import 블록에 추가:

```dart
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/api_constants.dart';
```

`_PermissionScreenState` 안에 헬퍼 추가 (예: `_recheckAfterSettings` 위):

```dart
  // 위치 단계 후 목적지: 신규/재개는 온보딩, 재방문자(위치 재허용 등)는 홈.
  String get _nextRoute {
    final done = Hive.box(AppConstants.settingsBox)
        .get(AppConstants.keyOnboardingDone, defaultValue: false) as bool;
    return done ? '/home' : '/onboarding';
  }
```

> import 경로 주의: 이 파일이 이미 다른 Hive import 를 쓰면 중복 추가하지 말 것. 없으면 위 `hive_flutter` 로 `Hive` 심볼을 가져온다(프로젝트 표준 import 와 일치하는지 `providers.dart` 의 Hive import 라인을 참고).

- [ ] **Step 2: 하드코딩 /onboarding 4곳을 _nextRoute 로 교체**

- 44행 `context.go('/onboarding');` (`_recheckAfterSettings`) → `context.go(_nextRoute);`
- 57행 `context.go('/onboarding');` (granted/limited) → `context.go(_nextRoute);`
- 62행 `context.go('/onboarding');` (denied) → `context.go(_nextRoute);`
- 139행 `onPressed: ... () => context.go('/onboarding'),` ("나중에") → `onPressed: _isLoading ? null : () => context.go(_nextRoute),`

- [ ] **Step 3: 정적 분석**

Run: `cd /Users/ghim/my_business/charge_app && flutter analyze lib/ui/permission/permission_screen.dart`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/permission/permission_screen.dart
git commit -m "feat(entry): 권한 후 목적지 = onboardingDone ? home : onboarding"
```

---

### Task 6: 온보딩 끝 — 게스트면 pending optin 플래그

**Files:**
- Modify: `lib/ui/onboarding/onboarding_screen.dart:58-84`

- [ ] **Step 1: import 추가**

`lib/ui/onboarding/onboarding_screen.dart` import 블록에 추가:

```dart
import '../../data/services/auth_service.dart';
```

- [ ] **Step 2: _finish 에서 게스트 플래그 set**

`_finish()` 의 `notifier.completeOnboarding();` (68행) 바로 아래에 추가:

```dart
    notifier.completeOnboarding();
    // 게스트로 온보딩을 끝낸 경우에만 홈에서 이벤트·혜택 옵트인 팝업 1회 노출.
    // (회원은 가입 시트에서 이미 마케팅 동의를 받았으므로 제외)
    if (ref.read(authProvider) == null) {
      notifier.setPendingEventOptin(true);
    }
```

- [ ] **Step 3: 정적 분석**

Run: `cd /Users/ghim/my_business/charge_app && flutter analyze lib/ui/onboarding/onboarding_screen.dart`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/onboarding/onboarding_screen.dart
git commit -m "feat(entry): 온보딩 끝낸 게스트 → 이벤트 팝업 대기 플래그"
```

---

### Task 7: marketing_reprompt force 파라미터

**Files:**
- Modify: `lib/ui/widgets/marketing_reprompt.dart:10-12`

- [ ] **Step 1: force 파라미터로 게이팅 우회**

`maybeShowChargeMarketingReprompt` 시그니처와 첫 두 줄(10~12행)을 교체:

```dart
/// charge_app 전용 마케팅(광고성) 수신 동의 재요청 팝업.
/// [force]=false: 콘솔 재요청 ON + 미동의자 + 오늘 미노출일 때만 (게이팅 DkswCore).
/// [force]=true: 게이팅 무시하고 무조건 노출 (온보딩 끝낸 게스트 1회용).
Future<void> maybeShowChargeMarketingReprompt(BuildContext context, {bool force = false}) async {
  if (!force) {
    if (!DkswCore.shouldShowMarketingReprompt()) return;
    await DkswCore.markMarketingRepromptShown(); // 동의/닫기 무관 오늘 노출 기록
  }
```

> 기존 13행 이후(`final marketing = ...`)는 그대로 둔다. force 경로에선 `markMarketingRepromptShown` 을 호출하지 않으므로 콘솔 게이팅의 "오늘 노출" 카운트에 영향을 주지 않는다.

- [ ] **Step 2: 정적 분석**

Run: `cd /Users/ghim/my_business/charge_app && flutter analyze lib/ui/widgets/marketing_reprompt.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/ui/widgets/marketing_reprompt.dart
git commit -m "feat(entry): marketing_reprompt force 옵션 (게이팅 우회)"
```

---

### Task 8: home — pending optin 1회 팝업 + 토글 차단 제거

**Files:**
- Modify: `lib/ui/home/home_screen.dart:137-145` (postFrame 시퀀스)
- Modify: `lib/ui/home/home_screen.dart:1720-1735` (토글)

- [ ] **Step 1: postFrame 시퀀스에 pending optin 우선 처리**

`maybeShowChargeMarketingReprompt(context);` 호출(138행)을 포함한 블록을 교체. 변경 후 (137행 `// 마케팅 동의 재요청 ...` 주석부터):

```dart
        // 온보딩 끝낸 게스트 1회 이벤트 옵트인(게이팅 무시). 있으면 이걸로 처리하고 재요청은 스킵.
        final notifier = ref.read(settingsProvider.notifier);
        if (notifier.pendingEventOptin) {
          notifier.setPendingEventOptin(false);
          await maybeShowChargeMarketingReprompt(context, force: true);
        } else {
          // 마케팅 동의 재요청 (콘솔 ON + 미동의자 + 오늘 미노출 시 하루 1회)
          await maybeShowChargeMarketingReprompt(context);
        }
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent != true) return;
        await PopupNoticeDialog.showIfEligible(context);
```

> 위 교체는 기존 138행(`await maybeShowChargeMarketingReprompt(context);`)과 그 다음 `if (!mounted)...` / `if (ModalRoute...)` / `await PopupNoticeDialog.showIfEligible(context);` 까지를 대상으로 한다. `PopupAdDialog.showIfEligible` 이후는 그대로 둔다.

- [ ] **Step 2: 토글 비로그인 차단 제거**

(a) `_promptLogin()` 메서드(1720~1728행)를 통째로 삭제.

(b) `build()` 내부(1732~1735행)를 교체:

```dart
    final muted = widget.isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    ref.watch(authProvider); // 회원가입 등 외부 동의 변경 시 리빌드 트리거
    final on = _on; // 게스트도 device 기반 consent 로 ON 가능
    void handle(bool v) => _set(v);
```

> 이로써 게스트도 토글 시 `_set(v)` → `DkswCore.postConsents(marketing)` 가 동작(device 기반). 회원가입 시 동의 시트가 최종값을 덮어쓴다.

- [ ] **Step 3: 정적 분석**

Run: `cd /Users/ghim/my_business/charge_app && flutter analyze lib/ui/home/home_screen.dart`
Expected: No issues found. (`_promptLogin` 미사용 경고가 사라졌는지 확인)

- [ ] **Step 4: Commit**

```bash
git add lib/ui/home/home_screen.dart
git commit -m "feat(entry): 게스트 이벤트 팝업 1회 + 토글 비로그인 차단 제거"
```

---

### Task 9: 전체 정적 분석 + 수동 검증 체크리스트

**Files:** 없음 (검증 전용)

- [ ] **Step 1: 전체 정적 분석**

Run: `cd /Users/ghim/my_business/charge_app && flutter analyze`
Expected: No issues found (또는 이번 변경과 무관한 기존 경고만).

- [ ] **Step 2: 사용자 수동 실행 검증 (flutter run, 사용자가 직접)**

아래 시나리오를 디바이스에서 확인:

1. **신규 설치 첫 실행(게스트)**: splash → 로그인 게이트(뒤로가기 안 됨, X 없음) → "게스트로 시작하기" → 경고 다이얼로그 → "그래도 시작" → 권한 → 온보딩 → 홈에서 **이벤트 팝업 1회** 노출.
2. **그 게스트 앱 재실행**: splash → 게이트 없이 바로 홈. 이벤트 팝업 다시 안 뜸.
3. **신규 설치 첫 실행(로그인)**: 게이트 → 소셜 로그인 → (미완성이면 SignupComplete) → 권한 → 온보딩 → 홈(**이벤트 팝업 없음**).
4. **온보딩 중간 종료 후 재실행**: 게스트/회원 모두 게이트 없이 권한→온보딩 재개.
5. **설정 토글(게스트)**: 마이페이지 "이벤트·혜택 알림 받기" ON/OFF — "회원가입 후 이용" 스낵바 안 뜨고 정상 토글.
6. **홈 계정카드 → 로그인**: 게스트 버튼 없음, X로 닫힘(기존 동작 회귀 없음).
7. **위치 거부**: 권한 화면 "나중에" 또는 거부해도 진입됨. 위치 필요한 동작에서 기존 컨텍스트 다이얼로그 노출.

- [ ] **Step 3: 검증 통과 후 마무리**

모든 시나리오 통과 시 finishing-a-development-branch 로 머지/PR 결정.

---

## Self-Review (작성자 점검 결과)

- **Spec coverage:** 라우팅(Task 4), 게이트+게스트(Task 2/3), 권한 소프트+목적지(Task 5), 이벤트 팝업(Task 6/7/8), 토글 해제(Task 8), 플래그(Task 1) — spec 전 항목 태스크 매핑됨.
- **Placeholder scan:** 모든 코드 스텝에 실제 코드 포함. TBD/TODO 없음.
- **Type consistency:** `markGuestStarted()`, `pendingEventOptin`/`setPendingEventOptin()`, `LoginScreen(gate:)`, `maybeShowChargeMarketingReprompt(force:)` 정의(Task 1/2/7)와 호출부(Task 4/6/8) 시그니처 일치 확인.
