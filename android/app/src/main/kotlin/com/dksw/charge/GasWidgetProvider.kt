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
            val views = RemoteViews(context.packageName, R.layout.widget_gas)

            val prefs = context.getSharedPreferences(
                "HomeWidgetPreferences", Context.MODE_PRIVATE
            )
            val listJson = prefs.getString("widget_gas_list", "[]") ?: "[]"
            val updatedAt = prefs.getString("widget_gas_updated", "--:--") ?: "--:--"
            views.setTextViewText(R.id.gas_time, updatedAt)

            views.setOnClickPendingIntent(
                R.id.gas_widget_root,
                buildLaunchIntent(context, appWidgetId, "gas", null)
            )

            data class RowIds(
                val row: Int, val brand: Int, val name: Int,
                val pill: Int, val sub: Int, val price: Int, val unit: Int,
                val bestBg: Int
            )
            val rows = listOf(
                RowIds(
                    R.id.gas_row1, R.id.gas_brand1, R.id.gas_name1,
                    R.id.gas_pill1, R.id.gas_sub1, R.id.gas_price1, R.id.gas_unit1,
                    R.drawable.bg_row_best_gas
                ),
                RowIds(
                    R.id.gas_row2, R.id.gas_brand2, R.id.gas_name2,
                    R.id.gas_pill2, R.id.gas_sub2, R.id.gas_price2, R.id.gas_unit2,
                    R.drawable.bg_row_normal
                ),
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
                    views.setTextViewText(r0.brand, "+")
                    views.setInt(r0.brand, "setBackgroundResource", R.drawable.bg_badge_default)
                    views.setTextViewText(r0.name, "즐겨찾기 주유소를 추가하세요")
                    views.setViewVisibility(r0.pill, View.GONE)
                    views.setTextViewText(r0.sub, "앱을 열어 추가")
                    views.setTextViewText(r0.price, "")
                    views.setTextViewText(r0.unit, "")
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
                views.setTextViewText(r0.price, "")
                views.setTextViewText(r0.unit, "")
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
            val requestCode = appWidgetId * 100 + (stationId?.hashCode()?.and(0x7F) ?: 0) + 10000
            return PendingIntent.getActivity(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun brandShort(brand: String): String = when (brand) {
            "GSC" -> "GS"
            "SKE" -> "SK"
            "HDO" -> "HD"
            "SOL" -> "S"
            "RTO", "RTX" -> "알"
            "NHO" -> "NH"
            else -> if (brand.length >= 2) brand.take(2) else brand.ifEmpty { "?" }
        }

        private fun brandDrawable(brand: String): Int = when (brand) {
            "GSC" -> R.drawable.bg_badge_gs
            "SKE" -> R.drawable.bg_badge_skn
            "HDO" -> R.drawable.bg_badge_hd
            "SOL" -> R.drawable.bg_badge_soil
            else -> R.drawable.bg_badge_default
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
