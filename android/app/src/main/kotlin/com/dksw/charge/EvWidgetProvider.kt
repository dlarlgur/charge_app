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
            val updatedAt = prefs.getString("widget_ev_updated", "--:--") ?: "--:--"
            views.setTextViewText(R.id.ev_time, updatedAt)

            views.setOnClickPendingIntent(
                R.id.ev_widget_root,
                buildLaunchIntent(context, appWidgetId, "ev", null)
            )

            data class RowIds(
                val row: Int, val brand: Int, val name: Int,
                val pill: Int, val sub: Int, val avail: Int, val total: Int,
                val status: Int, val bestBg: Int
            )
            val rows = listOf(
                RowIds(
                    R.id.ev_row1, R.id.ev_brand1, R.id.ev_name1,
                    R.id.ev_pill1, R.id.ev_sub1, R.id.ev_avail1, R.id.ev_total1,
                    R.id.ev_status1, R.drawable.bg_row_best_ev
                ),
                RowIds(
                    R.id.ev_row2, R.id.ev_brand2, R.id.ev_name2,
                    R.id.ev_pill2, R.id.ev_sub2, R.id.ev_avail2, R.id.ev_total2,
                    R.id.ev_status2, R.drawable.bg_row_normal
                ),
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
                    val statusCode = item.optInt("statusCode", 0)

                    val row = rows[i]

                    views.setViewVisibility(row.row, View.VISIBLE)
                    views.setInt(row.row, "setBackgroundResource", row.bestBg)

                    views.setTextViewText(row.brand, "EV")
                    views.setInt(
                        row.brand, "setBackgroundResource",
                        if (hasFast) R.drawable.bg_badge_ev_fast else R.drawable.bg_badge_ev_slow
                    )

                    views.setTextViewText(row.name, name)

                    views.setViewVisibility(row.pill, View.VISIBLE)
                    views.setTextViewText(row.pill, if (hasFast) "급속" else "완속")
                    views.setInt(
                        row.pill, "setBackgroundResource",
                        if (hasFast) R.drawable.bg_pill_speed_fast else R.drawable.bg_pill_speed_slow
                    )
                    views.setTextColor(
                        row.pill,
                        context.getColor(if (hasFast) R.color.widget_green_text else R.color.widget_blue_text)
                    )

                    views.setTextViewText(row.sub, if (maxKw > 0) "${maxKw}kW" else "")

                    views.setTextViewText(row.avail, available.toString())
                    views.setTextViewText(row.total, total.toString())

                    views.setViewVisibility(row.status, View.VISIBLE)
                    val isFull = (broken > 0 && broken >= total && total > 0) || statusCode == 2
                    val isBusy = !isFull && available == 0
                    val statusBg: Int
                    val statusText: String
                    val statusTextColor: Int
                    val availColor: Int
                    when {
                        isFull -> {
                            statusBg = R.drawable.bg_pill_status_full
                            statusText = "점검 중"
                            statusTextColor = R.color.widget_red_text
                            availColor = R.color.widget_red
                        }
                        isBusy -> {
                            statusBg = R.drawable.bg_pill_status_busy
                            statusText = "충전 중"
                            statusTextColor = R.color.widget_amber_text
                            availColor = R.color.widget_red
                        }
                        else -> {
                            statusBg = R.drawable.bg_pill_status_avail
                            statusText = "여유 가용"
                            statusTextColor = R.color.widget_green_text
                            availColor = R.color.widget_green
                        }
                    }
                    views.setInt(row.status, "setBackgroundResource", statusBg)
                    views.setTextViewText(row.status, statusText)
                    views.setTextColor(row.status, context.getColor(statusTextColor))
                    views.setTextColor(row.avail, context.getColor(availColor))

                    views.setOnClickPendingIntent(
                        row.row,
                        buildLaunchIntent(
                            context, appWidgetId, "ev",
                            stationId.takeIf { it.isNotEmpty() }
                        )
                    )
                }

                for (i in count until rows.size) {
                    views.setViewVisibility(rows[i].row, View.GONE)
                }

                if (count == 0) {
                    val r0 = rows[0]
                    views.setViewVisibility(r0.row, View.VISIBLE)
                    views.setInt(r0.row, "setBackgroundResource", R.drawable.bg_row_normal)
                    views.setTextViewText(r0.brand, "+")
                    views.setInt(r0.brand, "setBackgroundResource", R.drawable.bg_badge_default)
                    views.setTextViewText(r0.name, "즐겨찾기 충전소를 추가하세요")
                    views.setViewVisibility(r0.pill, View.GONE)
                    views.setTextViewText(r0.sub, "앱을 열어 추가")
                    views.setTextViewText(r0.avail, "0")
                    views.setTextViewText(r0.total, "0")
                    views.setViewVisibility(r0.status, View.GONE)
                    views.setViewVisibility(rows[1].row, View.GONE)
                }
            } catch (e: JSONException) {
                val r0 = rows[0]
                views.setViewVisibility(r0.row, View.VISIBLE)
                views.setInt(r0.row, "setBackgroundResource", R.drawable.bg_row_normal)
                views.setTextViewText(r0.brand, "+")
                views.setInt(r0.brand, "setBackgroundResource", R.drawable.bg_badge_default)
                views.setTextViewText(r0.name, "데이터 로드 중...")
                views.setViewVisibility(r0.pill, View.GONE)
                views.setTextViewText(r0.sub, "")
                views.setTextViewText(r0.avail, "0")
                views.setTextViewText(r0.total, "0")
                views.setViewVisibility(r0.status, View.GONE)
                views.setViewVisibility(rows[1].row, View.GONE)
            }

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
            val requestCode = appWidgetId * 100 + (stationId?.hashCode()?.and(0x7F) ?: 0) + 20000
            return PendingIntent.getActivity(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}
