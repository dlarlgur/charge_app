package com.dksw.charge

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import org.json.JSONArray
import org.json.JSONException

class CombinedWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) updateWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == GasWidgetProvider.ACTION_REFRESH) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, CombinedWidgetProvider::class.java))
            for (id in ids) {
                val v = RemoteViews(context.packageName, R.layout.widget_combined)
                v.setViewVisibility(R.id.combined_progress, View.VISIBLE)
                v.setViewVisibility(R.id.combined_live_dot, View.GONE)
                v.setViewVisibility(R.id.combined_time, View.GONE)
                mgr.partiallyUpdateAppWidget(id, v)
            }
            try {
                HomeWidgetBackgroundIntent.getBroadcast(
                    context, Uri.parse("chargehelper://refresh_all")
                ).send()
            } catch (e: Exception) {
                // ignore
            }
        }
    }

    companion object {

        private data class GasRow(
            val row: Int, val brand: Int, val name: Int,
            val pill: Int, val sub: Int, val price: Int, val unit: Int,
            val delta: Int, val bestBg: Int
        )

        private data class EvRow(
            val row: Int, val brand: Int, val name: Int,
            val pill: Int, val sub: Int, val avail: Int, val total: Int,
            val status: Int, val bestBg: Int
        )

        private fun rowsPerSection(mgr: AppWidgetManager, widgetId: Int): Int {
            val minH = mgr.getAppWidgetOptions(widgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            return if (minH in 1..319) 2 else 3
        }

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_combined)

            val prefs = context.getSharedPreferences(
                "HomeWidgetPreferences", Context.MODE_PRIVATE
            )
            val gasJson = prefs.getString("widget_gas_list", "[]") ?: "[]"
            val evJson = prefs.getString("widget_ev_list", "[]") ?: "[]"
            val updatedAt = prefs.getString("widget_gas_updated", "--:--") ?: "--:--"
            views.setTextViewText(R.id.combined_time, updatedAt)
            views.setViewVisibility(R.id.combined_progress, View.GONE)
            views.setViewVisibility(R.id.combined_live_dot, View.VISIBLE)
            views.setViewVisibility(R.id.combined_time, View.VISIBLE)

            views.setOnClickPendingIntent(
                R.id.combined_widget_root,
                buildLaunchIntent(context, appWidgetId, "combined", null)
            )
            val refreshIntent = Intent(context, CombinedWidgetProvider::class.java).apply {
                action = GasWidgetProvider.ACTION_REFRESH
            }
            views.setOnClickPendingIntent(
                R.id.combined_refresh,
                PendingIntent.getBroadcast(
                    context, 93000, refreshIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )

            val gasRows = listOf(
                GasRow(
                    R.id.cg_row1, R.id.cg_brand1, R.id.cg_name1,
                    R.id.cg_pill1, R.id.cg_sub1, R.id.cg_price1, R.id.cg_unit1,
                    R.id.cg_delta1, R.drawable.bg_row_best_gas
                ),
                GasRow(
                    R.id.cg_row2, R.id.cg_brand2, R.id.cg_name2,
                    R.id.cg_pill2, R.id.cg_sub2, R.id.cg_price2, R.id.cg_unit2,
                    R.id.cg_delta2, R.drawable.bg_row_normal
                ),
                GasRow(
                    R.id.cg_row3, R.id.cg_brand3, R.id.cg_name3,
                    R.id.cg_pill3, R.id.cg_sub3, R.id.cg_price3, R.id.cg_unit3,
                    R.id.cg_delta3, R.drawable.bg_row_normal
                ),
            )
            val evRows = listOf(
                EvRow(
                    R.id.ce_row1, R.id.ce_brand1, R.id.ce_name1,
                    R.id.ce_pill1, R.id.ce_sub1, R.id.ce_avail1, R.id.ce_total1,
                    R.id.ce_status1, R.drawable.bg_row_best_ev
                ),
                EvRow(
                    R.id.ce_row2, R.id.ce_brand2, R.id.ce_name2,
                    R.id.ce_pill2, R.id.ce_sub2, R.id.ce_avail2, R.id.ce_total2,
                    R.id.ce_status2, R.drawable.bg_row_normal
                ),
                EvRow(
                    R.id.ce_row3, R.id.ce_brand3, R.id.ce_name3,
                    R.id.ce_pill3, R.id.ce_sub3, R.id.ce_avail3, R.id.ce_total3,
                    R.id.ce_status3, R.drawable.bg_row_normal
                ),
            )

            val maxRows = rowsPerSection(appWidgetManager, appWidgetId)
            renderGasSection(context, views, gasJson, gasRows, appWidgetId, maxRows)
            renderEvSection(context, views, evJson, evRows, appWidgetId, maxRows)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun renderGasSection(
            context: Context, views: RemoteViews, listJson: String,
            rows: List<GasRow>, widgetId: Int, maxRows: Int
        ) {
            try {
                val list = JSONArray(listJson)
                val count = minOf(list.length(), maxRows)
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
                    views.setImageViewResource(row.brand, brandLogo(brand))
                    views.setTextViewText(row.name, name)
                    views.setViewVisibility(row.pill, View.VISIBLE)
                    views.setTextViewText(row.pill, if (isSelf) "셀프" else "일반")
                    views.setTextViewText(row.sub, fuelLabel)
                    if (price > 0) {
                        views.setTextViewText(row.price, formatPrice(price))
                        views.setTextViewText(row.unit, "원")
                    } else {
                        views.setTextViewText(row.price, "—")
                        views.setTextViewText(row.unit, "")
                    }
                    val change = item.optInt("change", 0)
                    when {
                        change > 0 -> {
                            views.setViewVisibility(row.delta, View.VISIBLE)
                            views.setTextViewText(row.delta, "▲ $change")
                            views.setTextColor(row.delta, context.getColor(R.color.widget_red))
                        }
                        change < 0 -> {
                            views.setViewVisibility(row.delta, View.VISIBLE)
                            views.setTextViewText(row.delta, "▼ ${-change}")
                            views.setTextColor(row.delta, context.getColor(R.color.widget_green_2))
                        }
                        else -> views.setViewVisibility(row.delta, View.GONE)
                    }
                    views.setOnClickPendingIntent(
                        row.row,
                        buildLaunchIntent(
                            context, widgetId, "gas", stationId.takeIf { it.isNotEmpty() }
                        )
                    )
                }
                for (i in count until rows.size) views.setViewVisibility(rows[i].row, View.GONE)
                if (count == 0) renderGasEmpty(views, rows[0])
            } catch (e: JSONException) {
                renderGasEmpty(views, rows[0])
                for (i in 1 until rows.size) views.setViewVisibility(rows[i].row, View.GONE)
            }
        }

        private fun renderGasEmpty(views: RemoteViews, r0: GasRow) {
            views.setViewVisibility(r0.row, View.VISIBLE)
            views.setInt(r0.row, "setBackgroundResource", R.drawable.bg_row_normal)
            views.setImageViewResource(r0.brand, R.drawable.ic_widget_mark_gas)
            views.setTextViewText(r0.name, "즐겨찾기 주유소를 추가하세요")
            views.setViewVisibility(r0.pill, View.GONE)
            views.setTextViewText(r0.sub, "")
            views.setTextViewText(r0.price, "")
            views.setTextViewText(r0.unit, "")
            views.setViewVisibility(r0.delta, View.GONE)
        }

        private fun renderEvSection(
            context: Context, views: RemoteViews, listJson: String,
            rows: List<EvRow>, widgetId: Int, maxRows: Int
        ) {
            try {
                val list = JSONArray(listJson)
                val count = minOf(list.length(), maxRows)
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
                    views.setInt(row.status, "setBackgroundResource", statusBg)
                    views.setTextViewText(row.status, statusText)
                    views.setTextColor(row.status, context.getColor(statusTextColor))
                    views.setTextColor(row.avail, context.getColor(availColor))

                    views.setOnClickPendingIntent(
                        row.row,
                        buildLaunchIntent(
                            context, widgetId, "ev", stationId.takeIf { it.isNotEmpty() }
                        )
                    )
                }
                for (i in count until rows.size) views.setViewVisibility(rows[i].row, View.GONE)
                if (count == 0) renderEvEmpty(views, rows[0])
            } catch (e: JSONException) {
                renderEvEmpty(views, rows[0])
                for (i in 1 until rows.size) views.setViewVisibility(rows[i].row, View.GONE)
            }
        }

        private fun renderEvEmpty(views: RemoteViews, r0: EvRow) {
            views.setViewVisibility(r0.row, View.VISIBLE)
            views.setInt(r0.row, "setBackgroundResource", R.drawable.bg_row_normal)
            views.setTextViewText(r0.brand, "+")
            views.setInt(r0.brand, "setBackgroundResource", R.drawable.bg_badge_default)
            views.setTextViewText(r0.name, "즐겨찾기 충전소를 추가하세요")
            views.setViewVisibility(r0.pill, View.GONE)
            views.setTextViewText(r0.sub, "")
            views.setTextViewText(r0.avail, "0")
            views.setTextViewText(r0.total, "0")
            views.setViewVisibility(r0.status, View.GONE)
        }

        private fun buildLaunchIntent(
            context: Context, widgetId: Int, type: String, stationId: String?
        ): PendingIntent {
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(Intent.ACTION_MAIN)
            intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            intent.putExtra("widget_type", type)
            if (stationId != null) intent.putExtra("widget_station_id", stationId)
            val rc = widgetId * 100 + (stationId?.hashCode()?.and(0x7F) ?: 0) + 30000
            return PendingIntent.getActivity(
                context, rc, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        // 앱 주유 목록과 동일한 브랜드 심볼 아이콘 (assets/logo/oil 기반)
        private fun brandLogo(brand: String): Int = when (brand) {
            "GSC" -> R.drawable.oil_gs
            "SKE" -> R.drawable.oil_sk
            "HDO" -> R.drawable.oil_hd
            "SOL" -> R.drawable.oil_soil
            "NHO" -> R.drawable.oil_nh
            else -> R.drawable.brand_etc
        }

        private fun formatPrice(price: Int): String =
            if (price >= 1000) "${price / 1000},${(price % 1000).toString().padStart(3, '0')}"
            else price.toString()
    }
}
