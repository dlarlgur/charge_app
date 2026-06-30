package com.dksw.charge

import android.content.Context
import android.widget.RemoteViews

/**
 * 위젯 배경 투명도 적용.
 *
 * Flutter 가 SharedPreferences("HomeWidgetPreferences") 의 'widget_bg_opacity'(0~100, String)
 * 에 저장하고, 각 provider 가 풀 렌더 시 배경 ImageView 에 알파를 적용한다.
 * (로딩 partiallyUpdateAppWidget 은 배경을 안 건드려 알파가 유지됨)
 */
object WidgetOpacity {
    fun apply(context: Context, views: RemoteViews, bgViewId: Int) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val pct = (prefs.getString("widget_bg_opacity", "100") ?: "100")
            .toIntOrNull()?.coerceIn(0, 100) ?: 100
        views.setInt(bgViewId, "setImageAlpha", pct * 255 / 100)
    }
}
