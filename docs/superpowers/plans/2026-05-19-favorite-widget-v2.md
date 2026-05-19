# Favorite Widget V2 (Bold Design) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** widget.html 사용자 디자인을 5종 위젯(Medium 가스/EV, Large 통합, Small 가스/EV) 으로 RemoteViews 구현

**Architecture:** drawable + colors 디자인 토큰 → layout XML 5개 → AppWidgetProvider 5개 → AndroidManifest 신규 receiver 3개 → widget_service 정렬 보장. 모두 같은 `HomeWidgetPreferences` prefs 공유.

**Tech Stack:** Android AppWidget, Kotlin RemoteViews, vector drawable, Pretendard ExtraBold/SemiBold

**Spec:** `docs/superpowers/specs/2026-05-19-favorite-widget-v2-design.md`

---

## Task 1: 디자인 토큰 (colors.xml)

**Files:**
- Modify: `android/app/src/main/res/values/colors.xml`

- [ ] **Step 1: colors.xml 에 디자인 토큰 추가**

기존 파일 그대로 두고 아래 항목들을 `<resources>` 안에 append:

```xml
<color name="widget_ink">#0F172A</color>
<color name="widget_ink_2">#334155</color>
<color name="widget_muted">#64748B</color>
<color name="widget_mute_2">#94A3B8</color>
<color name="widget_line">#E2E8F0</color>
<color name="widget_line_soft">#F1F5F9</color>
<color name="widget_blue">#2563EB</color>
<color name="widget_blue_2">#3B82F6</color>
<color name="widget_blue_soft">#EFF6FF</color>
<color name="widget_blue_text">#1E40AF</color>
<color name="widget_green">#10B981</color>
<color name="widget_green_2">#059669</color>
<color name="widget_green_soft">#ECFDF5</color>
<color name="widget_green_text">#047857</color>
<color name="widget_amber">#F59E0B</color>
<color name="widget_amber_soft">#FEF3C7</color>
<color name="widget_amber_text">#92400E</color>
<color name="widget_red">#EF4444</color>
<color name="widget_red_soft">#FEE2E2</color>
<color name="widget_red_text">#B91C1C</color>
<color name="widget_card_bg">#FAFFFFFF</color>
<color name="widget_best_gas_tint">#0F2563EB</color>
<color name="widget_best_ev_tint">#0F10B981</color>
```

- [ ] **Step 2: Commit**

```bash
git add android/app/src/main/res/values/colors.xml
git commit -m "widget v2: design tokens (colors)"
```

---

## Task 2: drawable 자원 — 카드/배지/필/best 행

**Files:**
- Create: `android/app/src/main/res/drawable/bg_widget_card.xml`
- Create: `android/app/src/main/res/drawable/bg_widget_card_dense.xml`
- Create: `android/app/src/main/res/drawable/bg_badge_{gs,hd,skn,soil,ev_slow,ev_fast,default}.xml` (이미 존재하는 badge 파일이 있으면 교체)
- Create: `android/app/src/main/res/drawable/bg_pill_{neutral,status_avail,status_busy,status_full,speed_slow,speed_fast}.xml`
- Create: `android/app/src/main/res/drawable/bg_row_{best_gas,best_ev,normal}.xml`

- [ ] **Step 1: 카드 배경**

`bg_widget_card.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="@color/widget_card_bg"/>
    <corners android:radius="22dp"/>
</shape>
```

`bg_widget_card_dense.xml` 동일 형식, `android:radius="18dp"`.

- [ ] **Step 2: 브랜드 배지 (radius 10dp, solid)**

`bg_badge_gs.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#0EA5E9"/>
    <corners android:radius="10dp"/>
</shape>
```

같은 형식으로 `bg_badge_hd.xml` (#16A34A), `bg_badge_skn.xml` (#DC2626), `bg_badge_soil.xml` (#FFCC00), `bg_badge_default.xml` (`@color/widget_mute_2`).

- [ ] **Step 3: EV 배지 (gradient)**

`bg_badge_ev_slow.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient android:type="linear" android:angle="315"
        android:startColor="#34D399" android:endColor="#065F46"/>
    <corners android:radius="10dp"/>
</shape>
```

`bg_badge_ev_fast.xml` 동일 형식, startColor `#3B82F6` endColor `#1E40AF`.

- [ ] **Step 4: pill (radius 99dp, padding 으로 작게)**

`bg_pill_neutral.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="@color/widget_line_soft"/>
    <corners android:radius="99dp"/>
</shape>
```

같은 형식으로:
| 파일 | solid color |
| `bg_pill_status_avail.xml` | `@color/widget_green_soft` |
| `bg_pill_status_busy.xml` | `@color/widget_amber_soft` |
| `bg_pill_status_full.xml` | `@color/widget_red_soft` |
| `bg_pill_speed_slow.xml` | `@color/widget_blue_soft` |
| `bg_pill_speed_fast.xml` | `@color/widget_green_soft` |

- [ ] **Step 5: best 행 highlight (좌→우 gradient)**

`bg_row_best_gas.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient android:type="linear" android:angle="0"
        android:startColor="@color/widget_best_gas_tint"
        android:endColor="#00FFFFFF"/>
    <corners android:radius="10dp"/>
</shape>
```

`bg_row_best_ev.xml` 동일 형식, startColor `@color/widget_best_ev_tint`.

`bg_row_normal.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#00FFFFFF"/>
    <corners android:radius="10dp"/>
</shape>
```

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/res/drawable/bg_*.xml
git commit -m "widget v2: drawable shapes (card, badge, pill, best row)"
```

---

## Task 3: drawable 자원 — 아이콘 vector

**Files:**
- Create: `android/app/src/main/res/drawable/ic_widget_mark_gas.xml`
- Create: `android/app/src/main/res/drawable/ic_widget_mark_ev.xml`
- Create: `android/app/src/main/res/drawable/ic_widget_mark_combined.xml`
- Create: `android/app/src/main/res/drawable/ic_star_filled.xml`
- Create: `android/app/src/main/res/drawable/ic_live_dot.xml`

- [ ] **Step 1: 가스 mark (22dp 파란 라운드 + 주유기 path 흰색)**

`ic_widget_mark_gas.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <shape android:shape="rectangle">
            <gradient android:type="linear" android:angle="315"
                android:startColor="#3B82F6" android:endColor="#1E40AF"/>
            <corners android:radius="7dp"/>
        </shape>
    </item>
    <item android:gravity="center">
        <vector android:width="12dp" android:height="12dp"
            android:viewportWidth="24" android:viewportHeight="24">
            <path android:strokeColor="#FFFFFF" android:strokeWidth="2.2"
                android:strokeLineCap="round" android:fillColor="#00000000"
                android:pathData="M5,21V6a2,2 0 0,1 2,-2h7a2,2 0 0,1 2,2v15"/>
            <path android:strokeColor="#FFFFFF" android:strokeWidth="2.2"
                android:strokeLineCap="round" android:fillColor="#00000000"
                android:pathData="M3,21h15"/>
            <path android:strokeColor="#FFFFFF" android:strokeWidth="2.2"
                android:strokeLineCap="round" android:fillColor="#00000000"
                android:pathData="M16,11h2a2,2 0 0,1 2,2v3a1,1 0 0,0 2,0V9l-3,-3"/>
        </vector>
    </item>
</layer-list>
```

- [ ] **Step 2: EV mark (초록 라운드 + 번개)**

`ic_widget_mark_ev.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <shape android:shape="rectangle">
            <gradient android:type="linear" android:angle="315"
                android:startColor="#34D399" android:endColor="#065F46"/>
            <corners android:radius="7dp"/>
        </shape>
    </item>
    <item android:gravity="center">
        <vector android:width="12dp" android:height="12dp"
            android:viewportWidth="24" android:viewportHeight="24">
            <path android:fillColor="#FFFFFF"
                android:pathData="M13,2L3,14h7l-1,8 10,-12h-7l1,-8z"/>
        </vector>
    </item>
</layer-list>
```

- [ ] **Step 3: 통합 mark (split)**

`ic_widget_mark_combined.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <shape android:shape="rectangle">
            <gradient android:type="linear" android:angle="0"
                android:startColor="#3B82F6" android:centerColor="#3B82F6"
                android:endColor="#10B981"/>
            <corners android:radius="7dp"/>
        </shape>
    </item>
</layer-list>
```

- [ ] **Step 4: star + live dot**

`ic_star_filled.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="11dp" android:height="11dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#F59E0B"
        android:pathData="M12,2l3,7 7,0.5 -5.5,4.5L18,21l-6,-3.5L6,21l1.5,-7L2,9.5 9,9z"/>
</vector>
```

`ic_live_dot.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="5dp" android:height="5dp"
    android:viewportWidth="10" android:viewportHeight="10">
    <path android:fillColor="#10B981"
        android:pathData="M5,2.5 a2.5,2.5 0 1,0 0.001,0 z"/>
</vector>
```

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/res/drawable/ic_*.xml
git commit -m "widget v2: vector icons (mark, star, live dot)"
```

---

## Task 4: Medium 가스 layout 개편

**Files:**
- Modify: `android/app/src/main/res/layout/widget_gas.xml` (전체 교체)

- [ ] **Step 1: widget_gas.xml 전체 교체**

```xml
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/gas_widget_root"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:padding="6dp">

    <LinearLayout
        android:layout_width="match_parent" android:layout_height="match_parent"
        android:orientation="vertical"
        android:background="@drawable/bg_widget_card"
        android:elevation="8dp"
        android:padding="16dp">

        <!-- Header -->
        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
            android:orientation="horizontal" android:gravity="center_vertical"
            android:layout_marginBottom="12dp">
            <ImageView android:layout_width="22dp" android:layout_height="22dp"
                android:src="@drawable/ic_widget_mark_gas"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_marginStart="8dp"
                android:text="즐겨찾기 주유소" android:textSize="13sp"
                android:textColor="@color/widget_ink"
                android:fontFamily="@font/pretendard_extrabold"
                android:letterSpacing="-0.02"/>
            <Space android:layout_width="0dp" android:layout_height="0dp" android:layout_weight="1"/>
            <ImageView android:layout_width="5dp" android:layout_height="5dp"
                android:src="@drawable/ic_live_dot" android:layout_marginEnd="4dp"/>
            <TextView android:id="@+id/gas_time" android:layout_width="wrap_content"
                android:layout_height="wrap_content" android:textSize="11sp"
                android:textColor="@color/widget_mute_2"
                android:fontFamily="@font/pretendard_bold"
                android:fontFeatureSettings="tnum"
                android:text="--:--"/>
        </LinearLayout>

        <!-- Row 1 -->
        <LinearLayout android:id="@+id/gas_row1"
            android:layout_width="match_parent" android:layout_height="wrap_content"
            android:orientation="horizontal" android:gravity="center_vertical"
            android:padding="7dp" android:background="@drawable/bg_row_best_gas">
            <TextView android:id="@+id/gas_brand1" android:layout_width="34dp"
                android:layout_height="34dp" android:gravity="center"
                android:textSize="11sp" android:textColor="#FFFFFF"
                android:fontFamily="@font/pretendard_extrabold"
                android:letterSpacing="-0.04"
                android:background="@drawable/bg_badge_default"/>
            <LinearLayout android:layout_width="0dp" android:layout_height="wrap_content"
                android:layout_weight="1" android:orientation="vertical"
                android:layout_marginStart="10dp">
                <LinearLayout android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:orientation="horizontal" android:gravity="center_vertical">
                    <TextView android:id="@+id/gas_name1" android:layout_width="0dp"
                        android:layout_height="wrap_content" android:layout_weight="1"
                        android:textSize="13sp" android:textColor="@color/widget_ink"
                        android:fontFamily="@font/pretendard_extrabold"
                        android:letterSpacing="-0.02" android:singleLine="true"
                        android:ellipsize="end"/>
                    <ImageView android:id="@+id/gas_star1" android:layout_width="11dp"
                        android:layout_height="11dp" android:layout_marginStart="5dp"
                        android:src="@drawable/ic_star_filled"/>
                </LinearLayout>
                <LinearLayout android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:orientation="horizontal" android:gravity="center_vertical"
                    android:layout_marginTop="2dp">
                    <TextView android:id="@+id/gas_pill1"
                        android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:paddingStart="6dp" android:paddingEnd="6dp"
                        android:paddingTop="1dp" android:paddingBottom="1dp"
                        android:background="@drawable/bg_pill_neutral"
                        android:textSize="10sp" android:textColor="@color/widget_ink_2"
                        android:fontFamily="@font/pretendard_bold"
                        android:text="셀프"/>
                    <TextView android:id="@+id/gas_sub1" android:layout_width="wrap_content"
                        android:layout_height="wrap_content" android:layout_marginStart="5dp"
                        android:textSize="10.5sp" android:textColor="@color/widget_muted"
                        android:fontFamily="@font/pretendard_semibold"/>
                </LinearLayout>
            </LinearLayout>
            <LinearLayout android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:orientation="horizontal" android:gravity="bottom"
                android:layout_marginStart="10dp">
                <TextView android:id="@+id/gas_price1" android:layout_width="wrap_content"
                    android:layout_height="wrap_content" android:textSize="18sp"
                    android:textColor="@color/widget_ink"
                    android:fontFamily="@font/pretendard_extrabold"
                    android:letterSpacing="-0.04"
                    android:fontFeatureSettings="tnum"/>
                <TextView android:id="@+id/gas_unit1" android:layout_width="wrap_content"
                    android:layout_height="wrap_content" android:textSize="11sp"
                    android:textColor="@color/widget_muted"
                    android:fontFamily="@font/pretendard_bold"
                    android:paddingBottom="1dp" android:paddingStart="1dp"
                    android:text="원"/>
            </LinearLayout>
        </LinearLayout>

        <Space android:layout_width="match_parent" android:layout_height="4dp"/>

        <!-- Row 2 (동일 구조, id 만 _2 로) -->
        <!-- copy of row1 with all id suffixes changed: row2, brand2, name2, star2, pill2, sub2, price2, unit2 ; background = @drawable/bg_row_normal -->

    </LinearLayout>
</FrameLayout>
```

Row 2: 위의 Row 1 LinearLayout 을 그대로 복사. 다음 변경만:
- 최상위 LinearLayout id: `gas_row2`, background: `@drawable/bg_row_normal`
- 하위 view id 전부 `1` → `2` 치환

- [ ] **Step 2: Commit**

```bash
git add android/app/src/main/res/layout/widget_gas.xml
git commit -m "widget v2: Medium gas layout (Bold design)"
```

---

## Task 5: GasWidgetProvider.kt 갱신

**Files:**
- Modify: `android/app/src/main/kotlin/com/dksw/charge/GasWidgetProvider.kt` (전체 교체)

- [ ] **Step 1: GasWidgetProvider 로직 갱신**

```kotlin
package com.dksw.charge

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONException

class GasWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) updateWidget(context, mgr, id)
    }

    companion object {
        fun updateWidget(context: Context, mgr: AppWidgetManager, widgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_gas)

            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val listJson = prefs.getString("widget_gas_list", "[]") ?: "[]"
            val updatedAt = prefs.getString("widget_gas_updated", "--:--") ?: "--:--"
            views.setTextViewText(R.id.gas_time, updatedAt)

            views.setOnClickPendingIntent(R.id.gas_widget_root,
                buildLaunchIntent(context, widgetId, "gas", null))

            data class RowIds(
                val row: Int, val brand: Int, val name: Int, val star: Int,
                val pill: Int, val sub: Int, val price: Int, val unit: Int,
                val bestBg: Int
            )
            val rows = listOf(
                RowIds(R.id.gas_row1, R.id.gas_brand1, R.id.gas_name1, R.id.gas_star1,
                    R.id.gas_pill1, R.id.gas_sub1, R.id.gas_price1, R.id.gas_unit1,
                    R.drawable.bg_row_best_gas),
                RowIds(R.id.gas_row2, R.id.gas_brand2, R.id.gas_name2, R.id.gas_star2,
                    R.id.gas_pill2, R.id.gas_sub2, R.id.gas_price2, R.id.gas_unit2,
                    R.drawable.bg_row_normal),
            )

            try {
                val list = JSONArray(listJson)
                val count = minOf(list.length(), 2)

                for (i in 0 until count) {
                    val item = list.getJSONObject(i)
                    val brand = item.optString("brand", "")
                    val name = item.optString("name", "—")
                    val stationId = item.optString("id", "")
                    val price = item.optInt("price", 0)
                    val isSelf = item.optBoolean("isSelf", false)
                    val fuelLabel = item.optString("fuelLabel", "")
                    val row = rows[i]

                    views.setViewVisibility(row.row, View.VISIBLE)
                    views.setInt(row.row, "setBackgroundResource", row.bestBg)

                    views.setTextViewText(row.brand, brandShort(brand))
                    views.setInt(row.brand, "setBackgroundResource", brandDrawable(brand))

                    views.setTextViewText(row.name, name)
                    views.setViewVisibility(row.star, View.VISIBLE)
                    views.setTextViewText(row.pill, if (isSelf) "셀프" else "일반")
                    views.setTextViewText(row.sub, fuelLabel)

                    if (price > 0) {
                        views.setTextViewText(row.price, formatPrice(price))
                        views.setTextViewText(row.unit, "원")
                    } else {
                        views.setTextViewText(row.price, "—")
                        views.setTextViewText(row.unit, "")
                    }

                    views.setOnClickPendingIntent(row.row,
                        buildLaunchIntent(context, widgetId, "gas",
                            stationId.takeIf { it.isNotEmpty() }))
                }

                for (i in count until rows.size) views.setViewVisibility(rows[i].row, View.GONE)

                if (count == 0) renderGasEmpty(views, rows[0])

            } catch (e: JSONException) {
                renderGasEmpty(views, rows[0])
                views.setViewVisibility(rows[1].row, View.GONE)
            }

            mgr.updateAppWidget(widgetId, views)
        }

        private fun renderGasEmpty(views: RemoteViews, row0: Any) {
            // 빈 상태: Row1 에 "+" 배지 + 안내 텍스트
            val r = row0 as Any
            // 일반 cast 어려우니 inline 으로:
        }

        // (renderGasEmpty 실제 inline — 위 try 블록의 catch 와 count==0 에서 직접 호출 후 inline 처리.
        //  코드 충돌 방지 위해 함수로 안 빼고 inline 으로 풀어 작성하는 게 안전.)

        private fun buildLaunchIntent(context: Context, widgetId: Int, type: String,
            stationId: String?): PendingIntent {
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(Intent.ACTION_MAIN)
            intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            intent.putExtra("widget_type", type)
            if (stationId != null) intent.putExtra("widget_station_id", stationId)
            val rc = widgetId * 100 + (stationId?.hashCode()?.and(0x7F) ?: 0) + 10000
            return PendingIntent.getActivity(context, rc, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        private fun brandShort(brand: String): String = when (brand) {
            "GSC" -> "GS"; "SKE" -> "SK"; "HDO" -> "HD"; "SOL" -> "S"
            "RTO", "RTX" -> "알"; "NHO" -> "NH"
            else -> if (brand.length >= 2) brand.take(2) else brand.ifEmpty { "?" }
        }

        private fun brandDrawable(brand: String): Int = when (brand) {
            "GSC" -> R.drawable.bg_badge_gs
            "SKE" -> R.drawable.bg_badge_skn
            "HDO" -> R.drawable.bg_badge_hd
            "SOL" -> R.drawable.bg_badge_soil
            "NHO" -> R.drawable.bg_badge_default
            "RTO", "RTX" -> R.drawable.bg_badge_default
            else -> R.drawable.bg_badge_default
        }

        private fun formatPrice(price: Int): String =
            if (price >= 1000) "${price / 1000},${(price % 1000).toString().padStart(3, '0')}"
            else price.toString()
    }
}
```

**중요**: 위 `renderGasEmpty` 는 cast 어려워서 try 블록 내부의 `if (count == 0)` 과 catch 블록 각각에서 inline 으로 다음 4줄 작성:

```kotlin
views.setViewVisibility(rows[0].row, View.VISIBLE)
views.setInt(rows[0].row, "setBackgroundResource", R.drawable.bg_row_normal)
views.setTextViewText(rows[0].brand, "+")
views.setInt(rows[0].brand, "setBackgroundResource", R.drawable.bg_badge_default)
views.setTextViewText(rows[0].name, "즐겨찾기 주유소를 추가하세요")
views.setViewVisibility(rows[0].star, View.GONE)
views.setViewVisibility(rows[0].pill, View.GONE)
views.setTextViewText(rows[0].sub, "앱을 열어 추가")
views.setTextViewText(rows[0].price, "")
views.setTextViewText(rows[0].unit, "")
```

(renderGasEmpty 헬퍼 함수는 실제론 빼고 inline 으로 위 코드 두 군데 작성.)

- [ ] **Step 2: Commit**

```bash
git add android/app/src/main/kotlin/com/dksw/charge/GasWidgetProvider.kt
git commit -m "widget v2: GasWidgetProvider for new layout"
```

---

## Task 6: Medium EV layout + EvWidgetProvider

**Files:**
- Modify: `android/app/src/main/res/layout/widget_ev.xml`
- Modify: `android/app/src/main/kotlin/com/dksw/charge/EvWidgetProvider.kt`

- [ ] **Step 1: widget_ev.xml**

가스 layout (Task 4) 과 동일한 구조. 변경:
- mark: `@drawable/ic_widget_mark_ev`
- 헤더 텍스트: "즐겨찾기 충전소"
- 모든 id `gas_*` → `ev_*` 치환
- 우측 price/unit 영역 → 가용 a/b 영역으로 교체:

```xml
<LinearLayout android:layout_width="wrap_content" android:layout_height="wrap_content"
    android:orientation="vertical" android:gravity="end"
    android:layout_marginStart="10dp">
    <LinearLayout android:layout_width="wrap_content" android:layout_height="wrap_content"
        android:orientation="horizontal" android:gravity="bottom">
        <TextView android:id="@+id/ev_avail1" android:layout_width="wrap_content"
            android:layout_height="wrap_content" android:textSize="18sp"
            android:textColor="@color/widget_green"
            android:fontFamily="@font/pretendard_extrabold"
            android:letterSpacing="-0.04" android:fontFeatureSettings="tnum"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:textSize="14sp" android:textColor="@color/widget_mute_2"
            android:fontFamily="@font/pretendard_bold"
            android:paddingStart="2dp" android:paddingEnd="2dp"
            android:text="/"/>
        <TextView android:id="@+id/ev_total1" android:layout_width="wrap_content"
            android:layout_height="wrap_content" android:textSize="18sp"
            android:textColor="@color/widget_ink_2"
            android:fontFamily="@font/pretendard_extrabold"
            android:fontFeatureSettings="tnum"/>
    </LinearLayout>
    <TextView android:id="@+id/ev_status1" android:layout_width="wrap_content"
        android:layout_height="wrap_content" android:layout_marginTop="3dp"
        android:paddingStart="7dp" android:paddingEnd="7dp"
        android:paddingTop="2dp" android:paddingBottom="2dp"
        android:textSize="10sp" android:fontFamily="@font/pretendard_extrabold"
        android:background="@drawable/bg_pill_status_avail"/>
</LinearLayout>
```

pill (sub 라인): `bg_pill_speed_slow` 또는 `bg_pill_speed_fast` 로 동적 변경 — id `ev_pill1`. text 도 "완속" / "급속".

sub 영역: 추가로 `ev_sub1` 에 "${maxKw}kW" 표기.

- [ ] **Step 2: EvWidgetProvider.kt**

GasWidgetProvider 와 동일 패턴이고 다음만 다름:

```kotlin
val list = JSONArray(listJson) // widget_ev_list
val item = list.getJSONObject(i)
val available = item.optInt("available", 0)
val total = item.optInt("total", 0)
val broken = item.optInt("broken", 0)
val hasFast = item.optBoolean("hasFast", false)
val maxKw = item.optInt("maxKw", 0)
val statusCode = item.optInt("statusCode", 0)
val name = item.optString("name", "—")
val stationId = item.optString("id", "")

views.setTextViewText(row.brand, "EV")
views.setInt(row.brand, "setBackgroundResource",
    if (hasFast) R.drawable.bg_badge_ev_fast else R.drawable.bg_badge_ev_slow)

views.setTextViewText(row.name, name)
views.setViewVisibility(row.star, View.VISIBLE)

views.setTextViewText(row.pill, if (hasFast) "급속" else "완속")
views.setInt(row.pill, "setBackgroundResource",
    if (hasFast) R.drawable.bg_pill_speed_fast else R.drawable.bg_pill_speed_slow)
views.setTextViewText(row.sub, "${maxKw}kW")

views.setTextViewText(row.avail, available.toString())
views.setTextViewText(row.total, total.toString())

// avail 숫자 색 + status pill
val (statusBg, statusText, availColor) = when (statusCode) {
    2 -> Triple(R.drawable.bg_pill_status_full, "점검 중", R.color.widget_red)
    1 -> Triple(R.drawable.bg_pill_status_busy, "충전 중", R.color.widget_red)
    else -> Triple(R.drawable.bg_pill_status_avail, "여유 가용", R.color.widget_green)
}
views.setInt(row.status, "setBackgroundResource", statusBg)
views.setTextViewText(row.status, statusText)
views.setTextColor(row.avail, context.getColor(availColor))
```

EvWidgetProvider 의 RowIds 도 ev_row/brand/name/star/pill/sub/avail/total/status/bestBg 로 정의.

빈 상태:
```kotlin
views.setTextViewText(rows[0].brand, "+")
views.setInt(rows[0].brand, "setBackgroundResource", R.drawable.bg_badge_default)
views.setTextViewText(rows[0].name, "즐겨찾기 충전소를 추가하세요")
views.setViewVisibility(rows[0].star, View.GONE)
views.setViewVisibility(rows[0].pill, View.GONE)
views.setTextViewText(rows[0].sub, "앱을 열어 추가")
views.setTextViewText(rows[0].avail, "0")
views.setTextViewText(rows[0].total, "0")
views.setViewVisibility(rows[0].status, View.GONE)
```

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/res/layout/widget_ev.xml \
       android/app/src/main/kotlin/com/dksw/charge/EvWidgetProvider.kt
git commit -m "widget v2: Medium EV layout + provider"
```

---

## Task 7: Large 통합 위젯

**Files:**
- Create: `android/app/src/main/res/layout/widget_combined.xml`
- Create: `android/app/src/main/res/xml/combined_widget_info.xml`
- Create: `android/app/src/main/kotlin/com/dksw/charge/CombinedWidgetProvider.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/res/values/strings.xml` (label)

- [ ] **Step 1: widget_combined.xml**

Medium 가스 + 구분선 + Medium EV 의 row 영역만 묶음. 헤더 mark = `@drawable/ic_widget_mark_combined`, 헤더 텍스트 "기름반 전기반". 두 섹션 각각:
- section-title: swatch (View width 9dp height 9dp + drawable 4dp radius bg) + TextView "주유 · 휘발유 기준" 11sp 800w muted
- row1 + row2 (가스/EV 각각)
- 가스 섹션 끝나면 1dp View 구분선 (margin-top 10dp)

각 row 의 id 는 `cgas_row1/2`, `cev_row1/2` 등 prefix 분리. nested layout 구조는 위 widget_gas.xml/widget_ev.xml row 와 동일.

- [ ] **Step 2: combined_widget_info.xml**

```xml
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="250dp" android:minHeight="250dp"
    android:targetCellWidth="4" android:targetCellHeight="4"
    android:updatePeriodMillis="1800000"
    android:widgetCategory="home_screen"
    android:resizeMode="horizontal|vertical"
    android:initialLayout="@layout/widget_combined"
    android:previewLayout="@layout/widget_combined"/>
```

- [ ] **Step 3: CombinedWidgetProvider.kt**

GasWidgetProvider + EvWidgetProvider 의 로직 합성. 같은 prefs 에서 `widget_gas_list` + `widget_ev_list` 동시 읽고 각 row 채움. 헬퍼 추출 가능하면 분리.

- [ ] **Step 4: Manifest receiver 추가**

`AndroidManifest.xml` 의 `<application>` 안 기존 위젯 receiver 옆에 추가:

```xml
<receiver android:name=".CombinedWidgetProvider"
    android:label="@string/combined_widget_label"
    android:exported="true">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
    </intent-filter>
    <meta-data android:name="android.appwidget.provider"
        android:resource="@xml/combined_widget_info"/>
</receiver>
```

`strings.xml` 에 `<string name="combined_widget_label">기름반 전기반</string>` 추가.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/res/layout/widget_combined.xml \
       android/app/src/main/res/xml/combined_widget_info.xml \
       android/app/src/main/kotlin/com/dksw/charge/CombinedWidgetProvider.kt \
       android/app/src/main/AndroidManifest.xml \
       android/app/src/main/res/values/strings.xml
git commit -m "widget v2: Large combined widget"
```

---

## Task 8: Small 위젯 2개 + manifest

**Files:**
- Create: `android/app/src/main/res/layout/widget_gas_small.xml`
- Create: `android/app/src/main/res/layout/widget_ev_small.xml`
- Create: `android/app/src/main/res/xml/gas_small_widget_info.xml`
- Create: `android/app/src/main/res/xml/ev_small_widget_info.xml`
- Create: `android/app/src/main/kotlin/com/dksw/charge/GasSmallWidgetProvider.kt`
- Create: `android/app/src/main/kotlin/com/dksw/charge/EvSmallWidgetProvider.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/res/values/strings.xml`

- [ ] **Step 1: widget_gas_small.xml**

```xml
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/gas_small_root"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:padding="6dp">
    <LinearLayout android:orientation="vertical"
        android:layout_width="match_parent" android:layout_height="match_parent"
        android:background="@drawable/bg_widget_card_dense" android:padding="14dp">
        <!-- Header -->
        <LinearLayout android:orientation="horizontal" android:gravity="center_vertical"
            android:layout_width="match_parent" android:layout_height="wrap_content"
            android:layout_marginBottom="8dp">
            <ImageView android:layout_width="22dp" android:layout_height="22dp"
                android:src="@drawable/ic_widget_mark_gas"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_marginStart="8dp" android:text="주유 최저가"
                android:textSize="13sp" android:textColor="@color/widget_ink"
                android:fontFamily="@font/pretendard_extrabold"/>
        </LinearLayout>
        <!-- Body -->
        <TextView android:id="@+id/gas_small_name" android:layout_width="match_parent"
            android:layout_height="wrap_content" android:maxLines="2"
            android:ellipsize="end" android:textSize="13sp"
            android:textColor="@color/widget_ink"
            android:fontFamily="@font/pretendard_extrabold"/>
        <TextView android:id="@+id/gas_small_sub" android:layout_width="wrap_content"
            android:layout_height="wrap_content" android:layout_marginTop="3dp"
            android:textSize="10.5sp" android:textColor="@color/widget_muted"
            android:fontFamily="@font/pretendard_bold"/>
        <Space android:layout_width="0dp" android:layout_height="0dp" android:layout_weight="1"/>
        <LinearLayout android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:orientation="horizontal" android:gravity="bottom">
            <TextView android:id="@+id/gas_small_price" android:layout_width="wrap_content"
                android:layout_height="wrap_content" android:textSize="34sp"
                android:textColor="@color/widget_blue"
                android:fontFamily="@font/pretendard_extrabold"
                android:letterSpacing="-0.04" android:fontFeatureSettings="tnum"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_marginStart="4dp" android:layout_marginBottom="2dp"
                android:textSize="11sp" android:textColor="@color/widget_muted"
                android:fontFamily="@font/pretendard_bold" android:text="원/L"/>
        </LinearLayout>
        <TextView android:id="@+id/gas_small_foot" android:layout_width="wrap_content"
            android:layout_height="wrap_content" android:layout_marginTop="4dp"
            android:textSize="10.5sp" android:textColor="@color/widget_ink_2"
            android:fontFamily="@font/pretendard_bold"/>
    </LinearLayout>
</FrameLayout>
```

- [ ] **Step 2: widget_ev_small.xml**

Step 1 과 동일 구조. 변경:
- mark: `@drawable/ic_widget_mark_ev`, 헤더 "충전 가용"
- price 위치에 `ev_small_avail` (34sp green), 단위 "/{total} 자리"
- foot 자리에 status pill (TextView with bg `bg_pill_status_*`)

- [ ] **Step 3: gas_small_widget_info.xml**

```xml
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="110dp" android:minHeight="110dp"
    android:targetCellWidth="2" android:targetCellHeight="2"
    android:updatePeriodMillis="1800000"
    android:widgetCategory="home_screen"
    android:resizeMode="none"
    android:initialLayout="@layout/widget_gas_small"
    android:previewLayout="@layout/widget_gas_small"/>
```

`ev_small_widget_info.xml` 동일, layout 만 widget_ev_small.

- [ ] **Step 4: GasSmallWidgetProvider.kt**

`widget_gas_list` JSON 의 list[0] 만 읽음. 빈 상태면 name="추가하세요" + price="—".

```kotlin
package com.dksw.charge

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import org.json.JSONArray

class GasSmallWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) update(context, mgr, id)
    }
    private fun update(context: Context, mgr: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_gas_small)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val list = JSONArray(prefs.getString("widget_gas_list", "[]") ?: "[]")

        views.setOnClickPendingIntent(R.id.gas_small_root,
            GasWidgetProvider.run {
                // re-use buildLaunchIntent via companion
                val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?: android.content.Intent(android.content.Intent.ACTION_MAIN)
                intent.addFlags(android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP)
                intent.putExtra("widget_type", "gas")
                android.app.PendingIntent.getActivity(context, widgetId + 50000, intent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
            })

        if (list.length() == 0) {
            views.setTextViewText(R.id.gas_small_name, "즐겨찾기 주유소를 추가하세요")
            views.setTextViewText(R.id.gas_small_sub, "")
            views.setTextViewText(R.id.gas_small_price, "—")
            views.setTextViewText(R.id.gas_small_foot, "앱을 열어 추가")
        } else {
            val item = list.getJSONObject(0)
            views.setTextViewText(R.id.gas_small_name, item.optString("name", "—"))
            val isSelf = item.optBoolean("isSelf", false)
            val fuel = item.optString("fuelLabel", "")
            views.setTextViewText(R.id.gas_small_sub,
                if (isSelf) "$fuel · 셀프" else fuel)
            val price = item.optInt("price", 0)
            views.setTextViewText(R.id.gas_small_price,
                if (price > 0) formatPrice(price) else "—")
            views.setTextViewText(R.id.gas_small_foot, fuel)
        }
        mgr.updateAppWidget(widgetId, views)
    }
    private fun formatPrice(p: Int): String =
        if (p >= 1000) "${p / 1000},${(p % 1000).toString().padStart(3, '0')}" else p.toString()
}
```

- [ ] **Step 5: EvSmallWidgetProvider.kt**

```kotlin
package com.dksw.charge

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

class EvSmallWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) update(context, mgr, id)
    }
    private fun update(context: Context, mgr: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_ev_small)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val list = JSONArray(prefs.getString("widget_ev_list", "[]") ?: "[]")

        views.setOnClickPendingIntent(R.id.ev_small_root, run {
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: android.content.Intent(android.content.Intent.ACTION_MAIN)
            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP)
            intent.putExtra("widget_type", "ev")
            android.app.PendingIntent.getActivity(context, widgetId + 60000, intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
        })

        if (list.length() == 0) {
            views.setTextViewText(R.id.ev_small_name, "즐겨찾기 충전소를 추가하세요")
            views.setTextViewText(R.id.ev_small_sub, "")
            views.setTextViewText(R.id.ev_small_avail, "0")
            views.setTextViewText(R.id.ev_small_total_label, "/ 0 자리")
            views.setViewVisibility(R.id.ev_small_status, View.GONE)
        } else {
            val item = list.getJSONObject(0)
            views.setTextViewText(R.id.ev_small_name, item.optString("name", "—"))
            val maxKw = item.optInt("maxKw", 0)
            val hasFast = item.optBoolean("hasFast", false)
            views.setTextViewText(R.id.ev_small_sub,
                "${if (hasFast) "급속" else "완속"} ${maxKw}kW")
            val available = item.optInt("available", 0)
            val total = item.optInt("total", 0)
            val statusCode = item.optInt("statusCode", 0)
            views.setTextViewText(R.id.ev_small_avail, available.toString())
            views.setTextViewText(R.id.ev_small_total_label, "/ $total 자리")
            views.setViewVisibility(R.id.ev_small_status, View.VISIBLE)
            val (bg, txt, color) = when (statusCode) {
                2 -> Triple(R.drawable.bg_pill_status_full, "점검 중", R.color.widget_red)
                1 -> Triple(R.drawable.bg_pill_status_busy, "충전 중", R.color.widget_red)
                else -> Triple(R.drawable.bg_pill_status_avail, "여유 가용", R.color.widget_green)
            }
            views.setInt(R.id.ev_small_status, "setBackgroundResource", bg)
            views.setTextViewText(R.id.ev_small_status, txt)
            views.setTextColor(R.id.ev_small_avail, context.getColor(color))
        }
        mgr.updateAppWidget(widgetId, views)
    }
}
```

- [ ] **Step 6: Manifest 2개 receiver + strings**

```xml
<receiver android:name=".GasSmallWidgetProvider"
    android:label="@string/gas_small_widget_label" android:exported="true">
    <intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter>
    <meta-data android:name="android.appwidget.provider" android:resource="@xml/gas_small_widget_info"/>
</receiver>
<receiver android:name=".EvSmallWidgetProvider"
    android:label="@string/ev_small_widget_label" android:exported="true">
    <intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter>
    <meta-data android:name="android.appwidget.provider" android:resource="@xml/ev_small_widget_info"/>
</receiver>
```

strings.xml 에:
```xml
<string name="gas_small_widget_label">주유 최저가</string>
<string name="ev_small_widget_label">충전 가용</string>
```

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/res/layout/widget_gas_small.xml \
       android/app/src/main/res/layout/widget_ev_small.xml \
       android/app/src/main/res/xml/gas_small_widget_info.xml \
       android/app/src/main/res/xml/ev_small_widget_info.xml \
       android/app/src/main/kotlin/com/dksw/charge/GasSmallWidgetProvider.kt \
       android/app/src/main/kotlin/com/dksw/charge/EvSmallWidgetProvider.kt \
       android/app/src/main/AndroidManifest.xml \
       android/app/src/main/res/values/strings.xml
git commit -m "widget v2: Small gas/ev widgets"
```

---

## Task 9: widget_service.dart 정렬 보장

**Files:**
- Modify: `lib/data/services/widget_service.dart`

- [ ] **Step 1: 가스 정렬 (가격 오름차순)**

`updateGasWidget()` 의 items 빌드 직후 (jsonEncode 직전) 정렬 추가:

```dart
items.sort((a, b) {
  final pa = (a['price'] as int? ?? 0);
  final pb = (b['price'] as int? ?? 0);
  if (pa == 0 && pb == 0) return 0;
  if (pa == 0) return 1; // price=0(데이터 없음) 은 뒤로
  if (pb == 0) return -1;
  return pa.compareTo(pb); // 저렴한 순
});
```

- [ ] **Step 2: EV 정렬 (가용 내림차순)**

`updateEvWidget()` 의 items 빌드 직후:

```dart
items.sort((a, b) {
  final aa = (a['available'] as int? ?? 0);
  final ab = (b['available'] as int? ?? 0);
  return ab.compareTo(aa); // 가용 많은 순
});
```

- [ ] **Step 3: Commit**

```bash
git add lib/data/services/widget_service.dart
git commit -m "widget v2: sort gas by price asc, ev by available desc"
```

---

## Task 10: 폰트 리소스 등록 확인 + 빌드 + 검증

**Files:**
- Check: `android/app/src/main/res/font/pretendard_extrabold.otf` 등 존재 여부

- [ ] **Step 1: 폰트 리소스 확인**

`ls android/app/src/main/res/font/` 결과에 `pretendard_extrabold`, `pretendard_semibold`, `pretendard_bold` 가 있어야 함. 없으면 `pubspec.yaml` 의 `assets/fonts/Pretendard-ExtraBold.otf` 를 `android/app/src/main/res/font/` 로 복사 (소문자 + underscore 명명):

```bash
cd /Users/ghim/my_business/charge_app
mkdir -p android/app/src/main/res/font
cp assets/fonts/Pretendard-Regular.otf android/app/src/main/res/font/pretendard_regular.otf
cp assets/fonts/Pretendard-Medium.otf android/app/src/main/res/font/pretendard_medium.otf
cp assets/fonts/Pretendard-SemiBold.otf android/app/src/main/res/font/pretendard_semibold.otf
cp assets/fonts/Pretendard-Bold.otf android/app/src/main/res/font/pretendard_bold.otf
cp assets/fonts/Pretendard-ExtraBold.otf android/app/src/main/res/font/pretendard_extrabold.otf
```

- [ ] **Step 2: 빌드 + 설치**

```bash
cd /Users/ghim/my_business/charge_app
flutter build apk --debug
adb -s R3CT7050FPW install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected: `Success`

- [ ] **Step 3: 디바이스에서 위젯 추가 + 시각 검증**

폰 홈화면 길게 → 위젯 → "기름반 전기반" 앱에서 5종 위젯이 모두 보이는지 확인. 각각 추가 → 표시 정상 확인:
1. Medium 가스: 카드 + best 행 하이라이트 + 셀프 pill + 큰 가격 + ▼/▲ 없음(스펙대로)
2. Medium EV: best 행 + 완속/급속 pill + 가용 큰 숫자 + 상태 pill
3. Large 통합: 가스+EV 한 카드 + 섹션 구분
4. Small 가스: 큰 가격
5. Small EV: 큰 슬롯 + 상태 pill

- [ ] **Step 4: Commit (없으면 skip)**

빌드 산출물 외 변경 없으면 commit X.

---

## Self-review checklist (완료 후)

- [ ] Phase 1 모든 항목 spec 반영 (gas/ev medium + combined + 2 small)
- [ ] 빈 상태 fallback 5종 모두 동작
- [ ] EV statusCode 0/1/2 매핑 정상
- [ ] 정렬 (가스 price asc / EV available desc) 적용
- [ ] flutter analyze 통과
