# Widget Refresh Button + Resize Dynamic Rows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 5종 위젯에 새로고침 버튼 + Medium/Large resize 시 동적 행(2~4) 표시

**Architecture:** 새로고침 = RemoteViews onClick broadcast → Provider.onReceive → WorkManager one-off → WidgetService.updateAll. resize = onAppWidgetOptionsChanged 에서 위젯 높이로 행 수 산정 → visibility 토글.

**Tech Stack:** Android AppWidget, Kotlin RemoteViews, WorkManager, Flutter callbackDispatcher

**Spec:** `docs/superpowers/specs/2026-05-20-widget-refresh-resize-design.md`

---

## Task 1: 새로고침 아이콘 drawable

**Files:**
- Create: `android/app/src/main/res/drawable/ic_widget_refresh.xml`

- [ ] **Step 1: vector 아이콘 생성**

```xml
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="14dp" android:height="14dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:strokeColor="#94A3B8" android:strokeWidth="2.4"
        android:strokeLineCap="round" android:fillColor="#00000000"
        android:pathData="M21,12a9,9 0 1,1 -2.64,-6.36"/>
    <path android:fillColor="#94A3B8"
        android:pathData="M21,3l0,6l-6,0z"/>
</vector>
```

- [ ] **Step 2: Commit**

```bash
git add android/app/src/main/res/drawable/ic_widget_refresh.xml
git commit -m "widget refresh: refresh icon drawable"
```

---

## Task 2: callbackDispatcher 에 widgetRefresh 추가

**Files:**
- Modify: `lib/main.dart` (callbackDispatcher 함수)

- [ ] **Step 1: callbackDispatcher 의 task switch 에 widgetRefresh case 추가**

`lib/main.dart` 의 `callbackDispatcher` 안 `Workmanager().executeTask` 콜백에서 task 이름 분기에 추가. 기존 `widgetGasUpdate`/`widgetEvUpdate` case 옆:

```dart
if (task == 'widgetRefresh') {
  await WidgetService.backgroundUpdateGas();
  await WidgetService.backgroundUpdateEv();
  return true;
}
```

(기존 main.dart:54-57 의 `backgroundUpdateGas`/`backgroundUpdateEv` 패턴과 동일.)

- [ ] **Step 2: Commit**

```bash
git add lib/main.dart
git commit -m "widget refresh: callbackDispatcher widgetRefresh task"
```

---

## Task 3: widget_service take(4) — 최대 4건

**Files:**
- Modify: `lib/data/services/widget_service.dart`

- [ ] **Step 1: gas/ev 모두 take(2) → take(4)**

`updateGasWidget()` 의 `for (final fav in gasFavs.take(2))` → `gasFavs.take(4)`.
`updateEvWidget()` 의 `for (final fav in evFavs.take(2))` → `evFavs.take(4)`.

정렬 로직(가격 asc / available desc)은 그대로 — 4건도 정렬되어 저장됨.

- [ ] **Step 2: Commit**

```bash
git add lib/data/services/widget_service.dart
git commit -m "widget refresh: widget_service take up to 4 favorites"
```

---

## Task 4: Medium 가스 layout — row3/row4 + 새로고침 버튼

**Files:**
- Modify: `android/app/src/main/res/layout/widget_gas.xml`

- [ ] **Step 1: 헤더에 새로고침 아이콘 추가**

헤더 LinearLayout 의 `ic_live_dot` ImageView **앞**에 삽입:

```xml
<ImageView
    android:id="@+id/gas_refresh"
    android:layout_width="26dp"
    android:layout_height="26dp"
    android:padding="6dp"
    android:src="@drawable/ic_widget_refresh"
    android:layout_marginEnd="2dp"
    android:contentDescription="새로고침"/>
```

- [ ] **Step 2: row3, row4 추가**

기존 `gas_row2` LinearLayout 블록 전체를 복사해 **2벌** 더 만들어 row2 아래 배치. 변경:
- 첫 복사본: id 전부 `gas_*2` → `gas_*3`, `android:visibility="gone"` 추가, `android:layout_marginTop="4dp"` 유지
- 둘째 복사본: id 전부 `gas_*3` → `gas_*4`, `android:visibility="gone"` 추가
- row3/row4 의 더미 `android:text` 는 제거(빈 값) — picker 미리보기는 2행만 노출

각 row 의 하위 id: `gas_row{N}`, `gas_brand{N}`, `gas_name{N}`, `gas_pill{N}`, `gas_sub{N}`, `gas_price{N}`, `gas_unit{N}`.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/res/layout/widget_gas.xml
git commit -m "widget refresh: gas layout row3/row4 + refresh button"
```

---

## Task 5: Medium EV layout — row3/row4 + 새로고침 버튼

**Files:**
- Modify: `android/app/src/main/res/layout/widget_ev.xml`

- [ ] **Step 1: 헤더에 새로고침 아이콘 추가**

`ic_live_dot` 앞에 삽입:

```xml
<ImageView
    android:id="@+id/ev_refresh"
    android:layout_width="26dp"
    android:layout_height="26dp"
    android:padding="6dp"
    android:src="@drawable/ic_widget_refresh"
    android:layout_marginEnd="2dp"
    android:contentDescription="새로고침"/>
```

- [ ] **Step 2: row3, row4 추가**

`ev_row2` 블록을 2벌 복사. id `ev_*2`→`ev_*3`, `ev_*3`→`ev_*4`, 각 `visibility="gone"`.
row 하위 id: `ev_row{N}`, `ev_brand{N}`, `ev_name{N}`, `ev_pill{N}`, `ev_sub{N}`, `ev_avail{N}`, `ev_total{N}`, `ev_status{N}`.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/res/layout/widget_ev.xml
git commit -m "widget refresh: ev layout row3/row4 + refresh button"
```

---

## Task 6: GasWidgetProvider — refresh + resize

**Files:**
- Modify: `android/app/src/main/kotlin/com/dksw/charge/GasWidgetProvider.kt`

- [ ] **Step 1: 상수 + onReceive + onAppWidgetOptionsChanged 추가**

클래스 본문 (companion 밖) 에 추가:

```kotlin
override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    if (intent.action == ACTION_REFRESH) {
        val mgr = AppWidgetManager.getInstance(context)
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
        if (id != -1) {
            val views = RemoteViews(context.packageName, R.layout.widget_gas)
            views.setTextViewText(R.id.gas_time, "갱신 중…")
            mgr.partiallyUpdateAppWidget(id, views)
        }
        enqueueRefresh(context)
    }
}

override fun onAppWidgetOptionsChanged(
    context: Context, mgr: AppWidgetManager, id: Int, newOptions: android.os.Bundle
) {
    updateWidget(context, mgr, id)
}

companion object {
    const val ACTION_REFRESH = "com.dksw.charge.WIDGET_REFRESH"

    fun enqueueRefresh(context: Context) {
        val req = androidx.work.OneTimeWorkRequest.Builder(
            Class.forName("be.tramckrijte.workmanager.BackgroundWorker")
                as Class<out androidx.work.ListenableWorker>
        ).build()
        // workmanager flutter 플러그인은 자체 task 이름 기반 — 아래 방식 대신
        // Flutter Workmanager().registerOneOffTask 를 쓸 수 없으므로
        // 간단히 AppWidget 갱신만 트리거하고 데이터는 next periodic 에 맡기거나
        // HomeWidget 의 백그라운드 콜백을 쓴다. (Step 1-b 참고)
    }
}
```

**주의:** Flutter `workmanager` 플러그인은 Dart 에서 `registerOneOffTask` 로만 task 를 등록한다. 네이티브에서 직접 enqueue 가 번거로우므로 **`home_widget` 의 백그라운드 콜백 방식**으로 한다 — Step 2 로 대체.

- [ ] **Step 2: home_widget 백그라운드 콜백 방식으로 재작성**

`onReceive` 에서 직접 `HomeWidgetBackgroundIntent` 를 broadcast 하는 대신, refresh 버튼의 PendingIntent 자체를 `HomeWidgetBackgroundIntent.getBroadcast` 로 만든다 (Task 8 에서 Dart 콜백 등록). Provider 의 `onReceive` 는 "갱신 중…" 표시만 담당:

```kotlin
override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    if (intent.action == ACTION_REFRESH) {
        val mgr = AppWidgetManager.getInstance(context)
        for (id in mgr.getAppWidgetIds(android.content.ComponentName(context, GasWidgetProvider::class.java))) {
            val views = RemoteViews(context.packageName, R.layout.widget_gas)
            views.setTextViewText(R.id.gas_time, "갱신 중…")
            mgr.partiallyUpdateAppWidget(id, views)
        }
    }
}

override fun onAppWidgetOptionsChanged(
    context: Context, mgr: AppWidgetManager, id: Int, newOptions: android.os.Bundle
) {
    updateWidget(context, mgr, id)
}

companion object {
    const val ACTION_REFRESH = "com.dksw.charge.WIDGET_REFRESH"

    private fun rowCountFor(context: Context, mgr: AppWidgetManager, widgetId: Int): Int {
        val opts = mgr.getAppWidgetOptions(widgetId)
        val minH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        return when {
            minH in 1..129 -> 2
            minH < 200 -> 3
            else -> 4
        }
    }
    ...
}
```

- [ ] **Step 3: updateWidget 에 rowCount 반영**

기존 `updateWidget` companion 함수에서 `rows` 리스트를 4행으로 확장하고, `rowCountFor` 결과를 반영:

```kotlin
val rows = listOf(
    RowIds(R.id.gas_row1, R.id.gas_brand1, R.id.gas_name1, R.id.gas_pill1,
        R.id.gas_sub1, R.id.gas_price1, R.id.gas_unit1, R.drawable.bg_row_best_gas),
    RowIds(R.id.gas_row2, R.id.gas_brand2, R.id.gas_name2, R.id.gas_pill2,
        R.id.gas_sub2, R.id.gas_price2, R.id.gas_unit2, R.drawable.bg_row_normal),
    RowIds(R.id.gas_row3, R.id.gas_brand3, R.id.gas_name3, R.id.gas_pill3,
        R.id.gas_sub3, R.id.gas_price3, R.id.gas_unit3, R.drawable.bg_row_normal),
    RowIds(R.id.gas_row4, R.id.gas_brand4, R.id.gas_name4, R.id.gas_pill4,
        R.id.gas_sub4, R.id.gas_price4, R.id.gas_unit4, R.drawable.bg_row_normal),
)
val maxRows = rowCountFor(context, appWidgetManager, appWidgetId)
```

`for (i in 0 until count)` 에서 `count = minOf(list.length(), maxRows)`.
빈 행 처리: `for (i in count until rows.size) setViewVisibility(GONE)`.

refresh 버튼 PendingIntent:
```kotlin
views.setOnClickPendingIntent(R.id.gas_refresh,
    HomeWidgetBackgroundIntent.getBroadcast(
        context, android.net.Uri.parse("chargehelper://refresh_gas")))
```
(import `es.antonborri.home_widget.HomeWidgetBackgroundIntent`)

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/com/dksw/charge/GasWidgetProvider.kt
git commit -m "widget refresh: GasWidgetProvider refresh + resize 2-4 rows"
```

---

## Task 7: EvWidgetProvider — refresh + resize

**Files:**
- Modify: `android/app/src/main/kotlin/com/dksw/charge/EvWidgetProvider.kt`

- [ ] **Step 1: onReceive + onAppWidgetOptionsChanged + rowCountFor**

Task 6 Step 2 와 동일 패턴. `R.layout.widget_ev`, `R.id.ev_time`, `EvWidgetProvider::class.java` 로 치환. `ACTION_REFRESH` 상수는 GasWidgetProvider 것 공유 가능하나, 명확성을 위해 EvWidgetProvider 에도 동일 상수 선언.

- [ ] **Step 2: updateWidget rowCount + refresh PendingIntent**

`rows` 를 4행으로 확장 (ev_row1~4, 각 하위 id). `maxRows = rowCountFor(...)`, `count = minOf(list.length(), maxRows)`.

refresh PendingIntent:
```kotlin
views.setOnClickPendingIntent(R.id.ev_refresh,
    HomeWidgetBackgroundIntent.getBroadcast(
        context, android.net.Uri.parse("chargehelper://refresh_ev")))
```

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/dksw/charge/EvWidgetProvider.kt
git commit -m "widget refresh: EvWidgetProvider refresh + resize 2-4 rows"
```

---

## Task 8: Dart 측 home_widget 백그라운드 콜백 등록

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/data/services/widget_service.dart`

- [ ] **Step 1: WidgetService 에 백그라운드 콜백 핸들러 추가**

`widget_service.dart` 에 추가:

```dart
/// home_widget 위젯 버튼(새로고침) 클릭 시 백그라운드 isolate 에서 호출
@pragma('vm:entry-point')
static Future<void> backgroundCallback(Uri? uri) async {
  // uri: chargehelper://refresh_gas | refresh_ev
  await Hive.initFlutter();
  for (final box in [AppConstants.settingsBox, AppConstants.favoritesBox]) {
    if (!Hive.isBoxOpen(box)) await Hive.openBox(box);
  }
  final host = uri?.host ?? '';
  if (host == 'refresh_gas') {
    await updateGasWidget();
  } else if (host == 'refresh_ev') {
    await updateEvWidget();
  } else {
    await updateAll();
  }
}
```

- [ ] **Step 2: main.dart 에서 콜백 등록**

`WidgetService.init()` 안 또는 `_initBackgroundTasks()` 에서:

```dart
await HomeWidget.registerInteractivityCallback(WidgetService.backgroundCallback);
```

(`import 'package:home_widget/home_widget.dart';` 이미 widget_service 에 있음. main.dart 에서 호출 시 import 확인.)

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart lib/data/services/widget_service.dart
git commit -m "widget refresh: register home_widget interactivity callback"
```

---

## Task 9: Large + Small — refresh 버튼 + Large resize

**Files:**
- Modify: `android/app/src/main/res/layout/widget_combined.xml`
- Modify: `android/app/src/main/res/layout/widget_gas_small.xml`
- Modify: `android/app/src/main/res/layout/widget_ev_small.xml`
- Modify: `android/app/src/main/kotlin/com/dksw/charge/CombinedWidgetProvider.kt`
- Modify: `android/app/src/main/kotlin/com/dksw/charge/GasSmallWidgetProvider.kt`
- Modify: `android/app/src/main/kotlin/com/dksw/charge/EvSmallWidgetProvider.kt`

- [ ] **Step 1: Large layout — 헤더 refresh + 가스/EV 섹션 row3**

`widget_combined.xml` 헤더의 `ic_live_dot` 앞에 `@+id/combined_refresh` ImageView 추가 (Task 4 Step 1 과 동일 스펙).
가스 섹션: `cg_row2` 복사 → `cg_*3` (visibility gone). EV 섹션: `ce_row2` 복사 → `ce_*3` (visibility gone).

- [ ] **Step 2: Small layout — 헤더 refresh 버튼**

`widget_gas_small.xml`/`widget_ev_small.xml` 헤더 LinearLayout 끝에 `@+id/{gas|ev}_small_refresh` ImageView 추가 (26dp, padding 6dp, `ic_widget_refresh`).

- [ ] **Step 3: CombinedWidgetProvider — refresh + resize**

`onReceive` (ACTION_REFRESH → "갱신 중…" via combined_time), `onAppWidgetOptionsChanged` → updateWidget.
`renderGasSection`/`renderEvSection` 에 `maxRows: Int` 파라미터 추가. `rowCountFor`: minH < 320 → 2, else 3.
gasRows/evRows 를 3행으로 확장.
refresh PendingIntent: `HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("chargehelper://refresh_all"))`.

- [ ] **Step 4: Small Providers — refresh PendingIntent**

`GasSmallWidgetProvider`/`EvSmallWidgetProvider` 의 `update()` 에서 헤더 refresh 버튼에 PendingIntent 연결:
```kotlin
views.setOnClickPendingIntent(R.id.gas_small_refresh,
    HomeWidgetBackgroundIntent.getBroadcast(
        context, android.net.Uri.parse("chargehelper://refresh_gas")))
```
EV 는 `ev_small_refresh` + `refresh_ev`.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/res/layout/widget_combined.xml \
       android/app/src/main/res/layout/widget_gas_small.xml \
       android/app/src/main/res/layout/widget_ev_small.xml \
       android/app/src/main/kotlin/com/dksw/charge/CombinedWidgetProvider.kt \
       android/app/src/main/kotlin/com/dksw/charge/GasSmallWidgetProvider.kt \
       android/app/src/main/kotlin/com/dksw/charge/EvSmallWidgetProvider.kt
git commit -m "widget refresh: Large resize + refresh, Small refresh button"
```

---

## Task 10: 빌드 + 디바이스 검증

- [ ] **Step 1: 빌드 + 설치**

```bash
cd /Users/ghim/my_business/charge_app
flutter build apk --debug
adb -s R3CT7050FPW install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected: `Success`

- [ ] **Step 2: 검증**

- 위젯 5종 추가 → 헤더에 새로고침 아이콘 보임
- 새로고침 클릭 → 시간 "갱신 중…" → 잠시 후 새 시각 + 값 갱신
- Medium 위젯 길게 → resize → 높이 늘리면 3행, 4행 노출
- 즐겨찾기 4건 이상이면 4행, 미만이면 있는 만큼
- Large resize 시 섹션별 3행
- logcat: `adb logcat -d | grep -E "Widget"` 으로 콜백 실행 확인

- [ ] **Step 3: home_widget 백그라운드 콜백 동작 안 하면**

`home_widget` 0.6.0 의 `HomeWidgetBackgroundIntent` 가 작동하지 않으면 (callback 미등록 등), Fallback: refresh 버튼 PendingIntent 를 앱 실행 Intent (`getLaunchIntentForPackage` + extra `widget_refresh=true`)로 바꾸고, `main.dart` 부팅 시 그 extra 감지 → `WidgetService.updateAll()`. 이 경우 앱이 잠깐 열린다.

---

## Self-review

- [ ] 새로고침: 5종 위젯 모두 버튼 + PendingIntent
- [ ] resize: Medium 2~4행, Large 섹션별 2~3행
- [ ] widget_service take(4)
- [ ] callbackDispatcher / interactivity callback 등록
- [ ] flutter analyze 통과
