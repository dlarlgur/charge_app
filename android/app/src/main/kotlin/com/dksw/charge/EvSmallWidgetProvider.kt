package com.dksw.charge

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

class EvSmallWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) update(context, appWidgetManager, id)
    }

    private fun update(context: Context, mgr: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_ev_small)

        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val listJson = prefs.getString("widget_ev_list", "[]") ?: "[]"

        views.setOnClickPendingIntent(R.id.ev_small_root, buildLaunch(context, widgetId))

        try {
            val list = JSONArray(listJson)
            if (list.length() == 0) {
                renderEmpty(views)
            } else {
                val item = list.getJSONObject(0)
                val name = item.optString("name", "—")
                val available = item.optInt("available", 0)
                val total = item.optInt("total", 0)
                val broken = item.optInt("broken", 0)
                val hasFast = item.optBoolean("hasFast", false)
                val maxKw = item.optInt("maxKw", 0)
                val statusCode = item.optInt("statusCode", 0)

                views.setTextViewText(R.id.ev_small_name, name)
                views.setTextViewText(
                    R.id.ev_small_sub,
                    "${if (hasFast) "급속" else "완속"}${if (maxKw > 0) " ${maxKw}kW" else ""}"
                )
                views.setTextViewText(R.id.ev_small_avail, available.toString())
                views.setTextViewText(R.id.ev_small_total_label, "/ $total 자리")
                views.setViewVisibility(R.id.ev_small_status, View.VISIBLE)

                val isFull = (broken > 0 && broken >= total && total > 0) || statusCode == 2
                val isBusy = !isFull && available == 0
                val statusBg: Int; val statusText: String
                val statusTextColor: Int; val availColor: Int
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
                views.setInt(R.id.ev_small_status, "setBackgroundResource", statusBg)
                views.setTextViewText(R.id.ev_small_status, statusText)
                views.setTextColor(R.id.ev_small_status, context.getColor(statusTextColor))
                views.setTextColor(R.id.ev_small_avail, context.getColor(availColor))
            }
        } catch (_: Exception) {
            renderEmpty(views)
        }

        mgr.updateAppWidget(widgetId, views)
    }

    private fun renderEmpty(views: RemoteViews) {
        views.setTextViewText(R.id.ev_small_name, "즐겨찾기\n충전소를 추가하세요")
        views.setTextViewText(R.id.ev_small_sub, "")
        views.setTextViewText(R.id.ev_small_avail, "0")
        views.setTextViewText(R.id.ev_small_total_label, "/ 0 자리")
        views.setViewVisibility(R.id.ev_small_status, View.GONE)
    }

    private fun buildLaunch(context: Context, widgetId: Int): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_MAIN)
        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        intent.putExtra("widget_type", "ev")
        return PendingIntent.getActivity(
            context, widgetId + 60000, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
