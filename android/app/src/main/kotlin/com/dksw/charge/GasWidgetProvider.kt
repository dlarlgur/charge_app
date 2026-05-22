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

class GasWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
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
        android.util.Log.i("WidgetRefresh", "GasWidgetProvider.onReceive action=${intent.action}")
        if (intent.action == ACTION_REFRESH) {
            // 즉시 스피너 표시 (백그라운드 isolate cold-start 와 무관하게 빠른 피드백)
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, GasWidgetProvider::class.java))
            android.util.Log.i("WidgetRefresh", "gas widget ids=${ids.size}")
            for (id in ids) {
                val v = RemoteViews(context.packageName, R.layout.widget_gas)
                v.setViewVisibility(R.id.gas_progress, View.VISIBLE)
                v.setViewVisibility(R.id.gas_live_dot, View.GONE)
                v.setViewVisibility(R.id.gas_time, View.GONE)
                mgr.partiallyUpdateAppWidget(id, v)
            }
            // 백그라운드 갱신 트리거
            try {
                HomeWidgetBackgroundIntent.getBroadcast(
                    context, Uri.parse("chargehelper://refresh_gas")
                ).send()
                android.util.Log.i("WidgetRefresh", "HomeWidgetBackgroundIntent sent")
            } catch (e: Exception) {
                android.util.Log.e("WidgetRefresh", "send failed: $e")
            }
        }
    }

    companion object {
        const val ACTION_REFRESH = "com.dksw.charge.WIDGET_REFRESH"

        private fun rowCountFor(mgr: AppWidgetManager, widgetId: Int): Int {
            val minH = mgr.getAppWidgetOptions(widgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            return when {
                minH in 1..129 -> 2
                minH < 200 -> 3
                else -> 4
            }
        }

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_gas)

            val prefs = context.getSharedPreferences(
                "HomeWidgetPreferences", Context.MODE_PRIVATE
            )
            val listJson = prefs.getString("widget_gas_list", "[]") ?: "[]"
            val updatedAt = prefs.getString("widget_gas_updated", "--:--") ?: "--:--"
            views.setTextViewText(R.id.gas_time, updatedAt)
            // 정상 상태 — 스피너 숨김, 시각 표시
            views.setViewVisibility(R.id.gas_progress, View.GONE)
            views.setViewVisibility(R.id.gas_live_dot, View.VISIBLE)
            views.setViewVisibility(R.id.gas_time, View.VISIBLE)

            views.setOnClickPendingIntent(
                R.id.gas_widget_root,
                buildLaunchIntent(context, appWidgetId, "gas", null)
            )
            val refreshIntent = Intent(context, GasWidgetProvider::class.java).apply {
                action = ACTION_REFRESH
            }
            views.setOnClickPendingIntent(
                R.id.gas_refresh,
                PendingIntent.getBroadcast(
                    context, 91000, refreshIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )

            data class RowIds(
                val row: Int, val brand: Int, val name: Int,
                val pill: Int, val sub: Int, val price: Int, val unit: Int,
                val delta: Int, val bestBg: Int
            )
            val rows = listOf(
                RowIds(
                    R.id.gas_row1, R.id.gas_brand1, R.id.gas_name1,
                    R.id.gas_pill1, R.id.gas_sub1, R.id.gas_price1, R.id.gas_unit1,
                    R.id.gas_delta1, R.drawable.bg_row_best_gas
                ),
                RowIds(
                    R.id.gas_row2, R.id.gas_brand2, R.id.gas_name2,
                    R.id.gas_pill2, R.id.gas_sub2, R.id.gas_price2, R.id.gas_unit2,
                    R.id.gas_delta2, R.drawable.bg_row_normal
                ),
                RowIds(
                    R.id.gas_row3, R.id.gas_brand3, R.id.gas_name3,
                    R.id.gas_pill3, R.id.gas_sub3, R.id.gas_price3, R.id.gas_unit3,
                    R.id.gas_delta3, R.drawable.bg_row_normal
                ),
                RowIds(
                    R.id.gas_row4, R.id.gas_brand4, R.id.gas_name4,
                    R.id.gas_pill4, R.id.gas_sub4, R.id.gas_price4, R.id.gas_unit4,
                    R.id.gas_delta4, R.drawable.bg_row_normal
                ),
            )
            val maxRows = rowCountFor(appWidgetManager, appWidgetId)

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
                            context, appWidgetId, "gas",
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
                    views.setImageViewResource(r0.brand, R.drawable.ic_widget_mark_gas)
                    views.setTextViewText(r0.name, "즐겨찾기 주유소를 추가하세요")
                    views.setViewVisibility(r0.pill, View.GONE)
                    views.setTextViewText(r0.sub, "앱을 열어 추가")
                    views.setTextViewText(r0.price, "")
                    views.setTextViewText(r0.unit, "")
                    views.setViewVisibility(r0.delta, View.GONE)
                }
            } catch (e: JSONException) {
                val r0 = rows[0]
                views.setViewVisibility(r0.row, View.VISIBLE)
                views.setInt(r0.row, "setBackgroundResource", R.drawable.bg_row_normal)
                views.setImageViewResource(r0.brand, R.drawable.ic_widget_mark_gas)
                views.setTextViewText(r0.name, "데이터 로드 중...")
                views.setViewVisibility(r0.pill, View.GONE)
                views.setTextViewText(r0.sub, "")
                views.setTextViewText(r0.price, "")
                views.setTextViewText(r0.unit, "")
                views.setViewVisibility(r0.delta, View.GONE)
                for (i in 1 until rows.size) {
                    views.setViewVisibility(rows[i].row, View.GONE)
                }
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
            val requestCode = appWidgetId * 100 + (stationId?.hashCode()?.and(0x7F) ?: 0) + 10000
            return PendingIntent.getActivity(
                context, requestCode, intent,
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

        private fun formatPrice(price: Int): String {
            return if (price >= 1000) {
                val thousands = price / 1000
                val remainder = price % 1000
                "${thousands},${remainder.toString().padStart(3, '0')}"
            } else {
                price.toString()
            }
        }
    }
}
