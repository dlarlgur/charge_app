package com.dksw.charge

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONException

class EvWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_ev)

            val prefs = context.getSharedPreferences(
                "HomeWidgetPreferences", Context.MODE_PRIVATE
            )
            val listJson = prefs.getString("widget_ev_list", "[]") ?: "[]"
            val updatedAt = prefs.getString("widget_ev_updated", "") ?: ""

            data class RowIds(
                val row: Int, val icon: Int, val name: Int, val type: Int,
                val status: Int, val total: Int
            )
            val rows = listOf(
                RowIds(R.id.ev_row1, R.id.ev_icon1, R.id.ev_name1, R.id.ev_type1,
                    R.id.ev_status1, R.id.ev_total1),
                RowIds(R.id.ev_row2, R.id.ev_icon2, R.id.ev_name2, R.id.ev_type2,
                    R.id.ev_status2, R.id.ev_total2),
            )

            views.setOnClickPendingIntent(
                R.id.ev_widget_root,
                buildLaunchIntent(context, appWidgetId, "ev", null)
            )

            try {
                val list = JSONArray(listJson)
                val count = minOf(list.length(), 2)

                for (i in 0 until count) {
                    val item = list.getJSONObject(i)
                    val name = item.optString("name", "—")
                    val stationId = item.optString("id", "")
                    val available = item.optInt("available", 0)
                    val total = item.optInt("total", 0)
                    val broken = item.optInt("broken", 0)
                    val hasFast = item.optBoolean("hasFast", false)
                    val maxKw = item.optInt("maxKw", 0)

                    val row = rows[i]
                    views.setViewVisibility(row.row, View.VISIBLE)

                    views.setInt(row.icon, "setBackgroundResource",
                        when {
                            broken > 0 && broken >= total -> R.drawable.badge_ev_broken
                            total == 0 -> R.drawable.badge_ev_empty
                            available == 0 -> R.drawable.badge_ev_busy
                            else -> R.drawable.badge_ev_ok
                        }
                    )
                    views.setTextViewText(row.icon, "EV")
                    views.setTextColor(row.icon, Color.WHITE)

                    views.setTextViewText(row.name, name)

                    val typeStr = buildString {
                        append(if (hasFast) "급속" else "완속")
                        if (maxKw > 0) append(" ${maxKw}kW")
                    }
                    views.setTextViewText(row.type, typeStr)

                    when {
                        broken > 0 && broken >= total -> {
                            views.setTextViewText(row.status, "고장")
                            views.setTextViewText(row.total, "")
                            views.setTextColor(row.status, Color.parseColor("#E24B4A"))
                            views.setFloat(row.status, "setTextSize", 13f)
                        }
                        total == 0 -> {
                            views.setTextViewText(row.status, "—")
                            views.setTextViewText(row.total, "")
                            views.setTextColor(row.status, Color.parseColor("#CBD5E1"))
                            views.setFloat(row.status, "setTextSize", 13f)
                        }
                        available == 0 -> {
                            views.setTextViewText(row.status, "대기중")
                            views.setTextViewText(row.total, "")
                            views.setTextColor(row.status, Color.parseColor("#EF9F27"))
                            views.setFloat(row.status, "setTextSize", 13f)
                        }
                        else -> {
                            views.setTextViewText(row.status, available.toString())
                            views.setTextViewText(row.total, "/$total")
                            views.setTextColor(row.status, Color.parseColor("#1D9E75"))
                            views.setFloat(row.status, "setTextSize", 17f)
                        }
                    }

                    views.setOnClickPendingIntent(
                        row.row,
                        buildLaunchIntent(context, appWidgetId, "ev", stationId.takeIf { it.isNotEmpty() })
                    )
                }

                for (i in count until rows.size) {
                    views.setViewVisibility(rows[i].row, View.GONE)
                }

                if (count == 0) {
                    views.setViewVisibility(rows[0].row, View.VISIBLE)
                    views.setTextViewText(rows[0].icon, "+")
                    views.setInt(rows[0].icon, "setBackgroundResource", R.drawable.badge_ev_empty)
                    views.setTextColor(rows[0].icon, Color.WHITE)
                    views.setTextViewText(rows[0].name, "즐겨찾기 충전소를 추가하세요")
                    views.setTextViewText(rows[0].type, "앱을 열어 추가")
                    views.setTextViewText(rows[0].status, "")
                    views.setTextViewText(rows[0].total, "")
                }

            } catch (e: JSONException) {
                views.setViewVisibility(rows[0].row, View.VISIBLE)
                views.setTextViewText(rows[0].name, "데이터 로드 중...")
                views.setTextViewText(rows[0].status, "")
                views.setTextViewText(rows[0].total, "")
                views.setViewVisibility(rows[1].row, View.GONE)
            }

            views.setTextViewText(
                R.id.ev_time,
                if (updatedAt.isNotEmpty()) updatedAt else "실시간"
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun buildLaunchIntent(
            context: Context,
            appWidgetId: Int,
            type: String,
            stationId: String?
        ): PendingIntent {
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(Intent.ACTION_MAIN)
            intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            intent.putExtra("widget_type", type)
            if (stationId != null) {
                intent.putExtra("widget_station_id", stationId)
            }
            val requestCode = appWidgetId * 100 + (stationId?.hashCode()?.and(0x7F) ?: 0)
            return PendingIntent.getActivity(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}
