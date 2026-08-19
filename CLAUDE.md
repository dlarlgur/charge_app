# charge_app — 저장소 지도

전기차·기름차 도우미 앱 (Flutter / Riverpod / go_router / Hive). 서버는 `../charge_server`.
오케스트레이션 규칙은 `~/.claude/CLAUDE.md`. 이 문서는 **작업 위치를 즉시 찾기 위한 지도**다.
구조를 바꾸는 작업을 했으면 이 문서도 같이 고친다.

## 검증 / 빌드
- 검증: `flutter analyze` (테스트 스위트 없음)
- **빌드·설치는 하지 않는다.** 사용자가 `flutter run`으로 직접 돌린다.
  APK 빌드 + adb install 은 서명 불일치로 앱 데이터가 날아간 전례가 있다.
- 마커/배지 등 이미지 캐시 변경은 hot reload로 안 보인다. "안 바뀐다"는 보고가 오면 fresh 실행부터 확인.
- 스토어 릴리즈는 빌드번호만 올리지 말고 버전명도 올린다(서버 타겟팅이 버전명 기준).

## 구조
| 경로 | 역할 |
|---|---|
| `lib/main.dart` | 부트 시퀀스, FCM 백그라운드 핸들러, 알림 payload 라우팅. 파급 최대 |
| `lib/app.dart` | MaterialApp.router 루트 |
| `lib/router/app_router.dart` | 라우트 테이블 (`/home`, `/gas/:id`, `/ev/:id`, `/inbox`, `/events` 등) |
| `lib/providers/providers.dart` | Riverpod 전역 상태 허브. 거의 모든 화면이 의존 |
| `lib/core/constants/api_constants.dart` | `baseUrl = https://charge.dksw4.com/api`, Hive 키 상수 |
| `lib/data/services/` | 서버 호출 + 캐시 계층 |
| `lib/data/models/models.dart` | `GasStation`, `EvStation` 등 |
| `lib/ui/<기능>/` | 화면별 폴더 (home, map, detail, ai, cheer, inbox, reports, settings …) |
| `lib/ui/widgets/shared_widgets.dart` | 카드·탭바·스켈레톤 공용 컴포넌트 |
| `lib/core/util/internal_link.dart` | 콘솔이 주는 내부 화면 식별자 → 실제 화면 디스패처 |

## 부트 순서 (main.dart)
스플래시 preserve → Kakao SDK → Firebase + 백그라운드 메시지 핸들러 → 로컬 알림 채널 →
Hive 오픈(`settings`, `favorites`, `station_aliases`, `charger_memos`, `push_inbox`) →
하우스광고 디스크 캐시 → 홈위젯 인텐트 → `DkswCore.init(console.dksw4.com) + trackSession` →
FCM 토픽 구독 → 네이버지도 init → 백그라운드 작업(Workmanager·AdMob·광고 fetch) → `runApp`.
이후 `splash_screen.dart`가 DkswCore bootstrap으로 강제업데이트/점검 게이트 → 로그인/온보딩/권한/홈 분기.

## 서버 연동 지점
- `api_service.dart` — 대부분의 API 단일 진입점 (주유/충전/테슬라 조회, 검색, 경로, 리포트, 제보, 업로드, refuel v1, AI 추천 등)
- `auth_service.dart` — `/auth/*`, 토큰은 flutter_secure_storage
- `user_sync_service.dart` — `/user/*` (prefs, vehicles, favorites, aliases, memos, alarms, places)
- `inbox_service.dart` — `/inbox/*` · `watch_service.dart` — EV 빈자리 감시 · `connected_service.dart` — 커넥티드카
- `notif_prefs_service.dart` — 알림 수신 설정 · `cheer_service.dart` — 응원/시상
- `DkswCore` 계열은 charge_server가 아니라 **console.dksw4.com** 을 향한다. 혼동 주의.

## 함정 (여기서 자주 틀린다)
- **설정 화면의 실제 구현은 `lib/ui/home/home_screen.dart`의 `SettingsScreenEmbed`다.**
  `lib/ui/settings/settings_screen.dart` 를 고치면 바텀탭 설정에는 아무 변화가 없다.
- 새로 만드는 Dio 인스턴스에는 반드시 `..transformer = BackgroundTransformer()`.
  JSON 파싱이 메인 스레드를 막아 지도 줌·스크롤이 끊긴다.
- 푸시는 **data-only**. `notification` 블록을 넣으면 탭해도 화면 이동이 안 된다.
  서버 발송부 / `main.dart` 핸들러 / 화면 소비부 3점을 같이 본다.
- 외부 내비 앱 연동은 3사 최소공통분모만. 일부 앱만 되는 기능은 넣지 않는다.
- 작은 화면 오버플로우 금지, 기존 톤 유지. 투박한 AI풍 디자인 금지.

## 파급 큰 파일
`main.dart`, `providers/providers.dart`, `data/services/api_service.dart`,
`core/constants/api_constants.dart`, `ui/widgets/shared_widgets.dart`,
`data/services/auth_service.dart`, `router/app_router.dart`
