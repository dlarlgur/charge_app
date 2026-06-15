# 방해 금지 시간 (DND / Quiet Hours) — 설계

날짜: 2026-06-15
대상 앱: charge_app (전기차 기름차)
서버(charge_server) 변경: 없음

## 1. 개요 / 목표

사용자가 지정한 시간대(기본 심야)에는 푸시 알림이 소리·진동·팝업으로 사용자를
방해하지 않게 한다. 단, 정보 손실은 없도록 앱 내 "알림 내역"에는 그대로 저장한다.

기능명(UI): **방해 금지 시간**
코드/키 네이밍: `dnd` / `quietHours`

## 2. 적용 범위

| 알림 종류 | type | 방해 금지 적용 |
|---|---|---|
| 주유 가격 알림 | `gas_price_alert` | ✅ 준수 |
| 충전소 즐겨찾기 자리알림 | `ev_alarm` | ✅ 준수 |
| 자리변동알림 (AI탭 길안내 watch) | `ev_watch` | 🚫 **항상 수신** (게이트 미적용) |

`ev_watch`는 사용자가 충전하러 가는 중 직접 등록하는 "무조건 받아야 하는" 알림이고
TTL(도착예상+30분)로 자동 만료되므로, **확인 다이얼로그/예외 플래그 없이 항상 통과**한다.

## 3. 방해 금지 중 동작 (Option A — 조용히 보관)

- **시스템 알림 표시 안 함** — `notificationPlugin.show()` 호출을 건너뜀 (소리·진동·트레이 팝업 전부 없음).
- **앱 내 "알림 내역"엔 저장** — 내역 저장은 show* 함수와 **별개로 호출부에서 실행**되므로,
  show* 가 일찍 return 해도 내역은 보존된다:
  - 백그라운드(`main.dart`): `_saveGasPriceToHive` / `_saveEvAlarmToHive`
  - 포그라운드(`home_screen.dart`): `AlertService().addGasPriceMessage` / `addEvAlarmMessage`
- 따라서 DND 게이트는 **오직 `notificationPlugin.show()` 만 감싸고**(show* 함수 내부에서 early return),
  내역 저장 로직은 건드리지 않는다.

## 4. 차단 방식 — 클라이언트측 억제 (서버 변경 0)

서버는 현행대로 모든 FCM data 메시지를 발송한다. 앱이 렌더 직전에 판단한다.

- 렌더 진입점은 2곳이지만 **둘 다 동일한 `show*` 함수를 호출**한다:
  - 포그라운드: `lib/ui/home/home_screen.dart` 의 `FirebaseMessaging.onMessage.listen`
  - 백그라운드: `lib/main.dart` 의 `_firebaseMessagingBackgroundHandler`
- 그러므로 `notification_service.dart` 의 `show*` 함수 **한 곳**에 게이트를 넣으면 양쪽 다 커버된다.
- 판정은 `DateTime.now()`(기기 로컬시간) 기준 → **타임존 문제 자동 해결**.

서버측을 택하지 않는 이유: 서버가 사용자별 DND 설정·타임존을 알아야 하고 동기화 API가
필요해져 복잡도가 큼. 클라이언트측은 단일 choke point + 로컬시간으로 단순하다.
트레이드오프: 기기가 data 메시지 처리를 위해 잠깐 깨어남(소리/팝업 없음 → 사용자 방해 0,
배터리 영향 미미).

## 5. 자정 넘는 시간대 처리

분 단위(0~1439)로 저장된 `start`, `end` 기준:

```
nowMin = now.hour*60 + now.minute
if (start == end) → 항상 false (빈 구간)
if (start < end)  → start <= nowMin < end          // 같은 날 (예 13:00~14:00)
if (start > end)  → nowMin >= start || nowMin < end // 자정 넘김 (예 23:00~07:00)
```

## 6. 데이터 모델 (기존 soundMode 패턴 미러)

Hive `'settings'` 박스 (백그라운드 isolate에서도 읽힘):

| 키 | 타입 | 기본값 | 의미 |
|---|---|---|---|
| `dnd_enabled` | bool | `false` | 방해 금지 켜짐 여부 |
| `dnd_start_min` | int | `1380` (23:00) | 시작 시각 (분) |
| `dnd_end_min` | int | `420` (07:00) | 종료 시각 (분) |

`AlertService` 에 게터/세터 추가 (포그라운드·UI용):
- `bool get dndEnabled`
- `int get dndStartMin` / `int get dndEndMin`
- `void setDnd({bool enabled, int startMin, int endMin})`
- `bool isWithinDnd([DateTime? now])` — 5절 로직

`notification_service.dart` 의 게이트는 `AlertService` 의존 없이 `Hive.box('settings')` 를
직접 읽는 `_isWithinDnd()` 로 구현(백그라운드 안전). 로직은 동일.

## 7. 렌더 게이트 구현

`lib/data/services/notification_service.dart`:

```dart
bool _isWithinDnd() {
  try {
    final box = Hive.box('settings');
    if (box.get('dnd_enabled', defaultValue: false) != true) return false;
    final start = box.get('dnd_start_min', defaultValue: 1380) as int;
    final end   = box.get('dnd_end_min',   defaultValue: 420)  as int;
    final now = DateTime.now();
    final n = now.hour * 60 + now.minute;
    if (start == end) return false;
    return start < end ? (n >= start && n < end) : (n >= start || n < end);
  } catch (_) {
    return false; // 박스 미오픈 등 → 안전하게 알림 표시
  }
}
```

- `showGasPriceNotification` 시작부: `if (_isWithinDnd()) return;` (내역 저장은 호출부 별도)
- `showEvAlarmNotification` 시작부: `if (_isWithinDnd()) return;`
- `showEvWatchNotification`: **게이트 없음** (항상 표시)

주의: `notification_service.dart` 가 `hive_flutter` 를 import 하는지 확인,
없으면 추가. 백그라운드 핸들러에서 `Hive.initFlutter()` + `openBox('settings')` 는 이미 됨.

## 8. UI (설정 화면 '알림' 섹션)

`lib/ui/settings/settings_screen.dart` 의 알림 섹션에 행 추가 — 기존 톤(둥근 카드,
ListTile, Switch, AppColors gasBlue, Pretendard) 그대로. **이모지 사용 안 함.**

- 제목 행: "방해 금지 시간" + 우측 `Switch` (기존 알림 토글 스타일과 동일).
- 켜짐일 때 아래로 펼침: **시작 / 종료** 시간 칩 2개. 탭 → Material `showTimePicker`
  (앱 테마 적용). 표기 예 "23:00 ~ 07:00".
- 보조 문구: "이 시간엔 알림이 소리 없이 보관돼요. 자리변동 알림은 제외돼요."
- 값 변경 시 `AlertService.setDnd(...)` 로 Hive 저장.

## 9. 변경 파일 요약

- `lib/data/services/notification_service.dart` — `_isWithinDnd()` + gas/ev_alarm show* 게이트
- `lib/data/services/alert_service.dart` — dnd 게터/세터 + `isWithinDnd`
- `lib/ui/settings/settings_screen.dart` — 방해 금지 시간 UI 행
- (서버 변경 없음)

## 10. 테스트 / 검증

- 단위: `_isWithinDnd` 경계값 — 같은날 구간, 자정 넘김 구간, start==end, 비활성.
- 수동: DND 켜고 시간대 안에서 gas/ev_alarm 푸시 → 알림 안 뜸 + 내역엔 남음 확인.
  ev_watch 푸시 → 정상 표시 확인. DND 끄면 전부 정상.
- 빌드/설치는 사용자가 `flutter run` 으로 직접.

## 11. 범위 밖 (YAGNI)

- 서버측 차단/사용자별 DND 동기화
- "모아서 나중에 발송"(요약 푸시) 스케줄러
- 복수 구간(여러 개의 방해 금지 시간대)
- 요일별 설정
