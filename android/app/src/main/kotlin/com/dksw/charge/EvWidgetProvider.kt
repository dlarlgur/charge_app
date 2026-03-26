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

            // Tap widget → open app
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (intent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context, 1, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(android.R.id.content, pendingIntent)
            }

            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val listJson = prefs.getString("flutter.widget_ev_list", "[]") ?: "[]"
            val updatedAt = prefs.getString("flutter.widget_ev_updated", "") ?: ""

            data class RowIds(val row: Int, val icon: Int, val name: Int, val type: Int, val status: Int)
            val rows = listOf(
                RowIds(R.id.ev_row1, R.id.ev_icon1, R.id.ev_name1, R.id.ev_type1, R.id.ev_status1),
                RowIds(R.id.ev_row2, R.id.ev_icon2, R.id.ev_name2, R.id.ev_type2, R.id.ev_status2),
                RowIds(R.id.ev_row3, R.id.ev_icon3, R.id.ev_name3, R.id.ev_type3, R.id.ev_status3),
            )

            try {
                val list = JSONArray(listJson)
                val count = minOf(list.length(), 3)

                for (i in 0 until count) {
                    val item = list.getJSONObject(i)
                    val name = item.optString("name", "—")
                    val available = item.optInt("available", 0)
                    val total = item.optInt("total", 0)
                    val broken = item.optInt("broken", 0)
                    val hasFast = item.optBoolean("hasFast", false)
                    val maxKw = item.optInt("maxKw", 0)
                    val statusCode = item.optInt("statusCode", 0)
                    // statusCode: 0=ok(avail>0), 1=busy(full), 2=broken(all broken)

                    val row = rows[i]
                    views.setViewVisibility(row.row, View.VISIBLE)

                    // Icon background by status
                    val (iconBg, statusText, statusColor) = when {
                        broken > 0 && broken >= total -> Triple(
                            Color.parseColor("#FCEBEB"), "고장", Color.parseColor("#E24B4A")
                        )
                        available == 0 -> Triple(
                            Color.parseColor("#FAEEDA"), "대기중", Color.parseColor("#EF9F27")
                        )
                        else -> Triple(
                            Color.parseColor("#E1F5EE"),
                            "${available}/${total}",
                            Color.parseColor("#1D9E75")
                        )
                    }

                    views.setInt(row.icon, "setBackgroundColor", iconBg)

                    // Name
                    views.setTextViewText(row.name, name)

                    // Type info
                    val typeStr = buildString {
                        if (hasFast) append("급속")
                        else append("완속")
                        if (maxKw > 0) append(" ${maxKw}kW")
                    }
                    views.setTextViewText(row.type, typeStr)

                    // Status
                    views.setTextViewText(row.status, statusText)
                    views.setTextColor(row.status, statusColor)
                }

                // Hide unused rows
                for (i in count until 3) {
                    views.setViewVisibility(rows[i].row, View.GONE)
                }

                if (count == 0) {
                    views.setTextViewText(R.id.ev_name1, "즐겨찾기 충전소를 추가하세요")
                    views.setTextViewText(R.id.ev_status1, "")
                    views.setViewVisibility(R.id.ev_row1, View.VISIBLE)
                }

            } catch (e: JSONException) {
                views.setTextViewText(R.id.ev_name1, "데이터 로드 중...")
                views.setViewVisibility(R.id.ev_row1, View.VISIBLE)
                views.setViewVisibility(R.id.ev_row2, View.GONE)
                views.setViewVisibility(R.id.ev_row3, View.GONE)
            }

            if (updatedAt.isNotEmpty()) {
                views.setTextViewText(R.id.ev_footer, "환경부 API · $updatedAt")
            } else {
                views.setTextViewText(R.id.ev_footer, "환경부 API · 실시간")
            }
            views.setTextViewText(R.id.ev_time, "실시간")

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
