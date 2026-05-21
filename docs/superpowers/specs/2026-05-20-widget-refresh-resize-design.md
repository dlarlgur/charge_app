# 위젯 새로고침 버튼 + resize 동적 행

## 목표
1. 5종 위젯에 **새로고침 버튼** — 누르면 주유/충전 정보 즉시 재요청
2. Medium 가스/EV 위젯 **resize 시 2~4행 동적**, Large 는 섹션별 2~3행

## 출처
사용자 요청 (widget v2 후속). brainstorming 합의 완료.

## 범위
| 위젯 | 새로고침 | resize 동적 행 |
|------|---------|---------------|
| Medium 가스 | ✅ | ✅ 2~4행 |
| Medium EV | ✅ | ✅ 2~4행 |
| Large 통합 | ✅ | ✅ 가스/EV 각 2~3행 |
| Small 가스 | ✅ | ✗ (1개 고정) |
| Small EV | ✅ | ✗ (1개 고정) |

## 1. 새로고침 버튼

### 동작 흐름
```
[새로고침 아이콘 클릭]
  → RemoteViews setOnClickPendingIntent → broadcast "com.dksw.charge.WIDGET_REFRESH"
  → 각 Provider.onReceive() 가 액션 감지
  → WorkManager OneTimeWorkRequest("widgetRefresh") enqueue
  → callbackDispatcher 의 'widgetRefresh' case
  → WidgetService.updateAll()  (Hive init + API 재요청 + prefs 갱신 + updateWidget)
```

### UI
- 헤더 우측, 시간 텍스트 **왼쪽**에 22dp refresh 아이콘 (`ic_widget_refresh` vector)
- 클릭 즉시 피드백: 시간 텍스트를 `"갱신 중…"` 으로 교체 (Provider 가 broadcast 받은 직후 setTextViewText). 완료 시 WidgetService 가 새 시각 기록.

### 신규 파일/변경
- `drawable/ic_widget_refresh.xml` — vector 새로고침 아이콘 (mute-2 색)
- 각 5개 layout 헤더에 `@+id/{prefix}_refresh` ImageView 추가
- 각 Provider: `onReceive` override — `WIDGET_REFRESH` 액션 시 WorkManager enqueue + 시간 텍스트 "갱신 중…" 표시
- `main.dart` `callbackDispatcher`: `widgetRefresh` case → `WidgetService.updateAll()`
- AndroidManifest: 각 receiver 의 intent-filter 에 `com.dksw.charge.WIDGET_REFRESH` 액션 추가

### PendingIntent
- refresh 버튼 → `PendingIntent.getBroadcast` (자기 Provider 클래스 대상 Intent, action=`WIDGET_REFRESH`, extra `appWidgetId`)
- `FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE`

## 2. resize 동적 행 (Medium)

### layout 변경
- `widget_gas.xml` / `widget_ev.xml`: 현재 row1~2 → **row1~4** 추가 (각 `layout_weight="1"`, row2~4 는 `layout_marginTop="4dp"`)
- 기본 `visibility`: row1~2 VISIBLE, row3~4 GONE

### 행 수 결정
`AppWidgetProvider.onAppWidgetOptionsChanged(context, mgr, widgetId, newOptions)`:
```
val minH = newOptions.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
val rowCount = when {
    minH < 130 -> 2
    minH < 200 -> 3
    else -> 4
}
```
→ `updateWidget(context, mgr, widgetId, rowCount)` 호출. rowCount 만큼 VISIBLE.

`onUpdate` 는 저장된 옵션에서 minH 읽어 동일 계산 (`mgr.getAppWidgetOptions(widgetId)`).

### 데이터
- `widget_service.dart`: `gasFavs.take(2)` → `take(4)`, `evFavs.take(2)` → `take(4)`
- prefs `widget_gas_list` / `widget_ev_list` 가 최대 4건 포함
- Provider 는 list 와 rowCount 중 `minOf` 만큼 행 채움

## 3. Large 통합 resize

- `widget_combined.xml`: 가스 섹션 row1~2 → row1~3, EV 섹션 동일
- `onAppWidgetOptionsChanged`: minH < 320 → 섹션당 2행, 그 이상 → 3행
- CombinedWidgetProvider 의 renderGasSection/renderEvSection 에 rowCount 인자 추가

## 4. Small

- layout 헤더에 refresh 아이콘만 추가
- GasSmallWidgetProvider/EvSmallWidgetProvider 에 `onReceive` + WorkManager enqueue

## 검증
- 위젯 추가 후 새로고침 버튼 클릭 → "갱신 중…" → 잠시 후 새 시각 + 값 갱신 확인
- Medium 위젯 길게 눌러 resize → 높이 늘리면 3행, 4행 노출 확인
- 즐겨찾기 4건 이상일 때 4행까지 표시, 미만이면 있는 만큼만
- Large resize 시 섹션별 3행 확인
- logcat `[Widget]` 로 updateAll 호출 확인

## 제외
- 회전 애니메이션 (RemoteViews 미지원)
- RemoteViewsService 무제한 스크롤 리스트 (2~4행이라 불필요)
- 거리/전일변동 (이전 PR 에서 이미 제외)
