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
            val updatedAt = prefs.getString("widget_gas_updated", "") ?: ""

            data class RowIds(
                val row: Int, val brand: Int, val name: Int, val sub: Int,
                val price: Int, val unit: Int
            )
            val rows = listOf(
                RowIds(R.id.gas_row1, R.id.gas_brand1, R.id.gas_name1, R.id.gas_sub1,
                    R.id.gas_price1, R.id.gas_unit1),
                RowIds(R.id.gas_row2, R.id.gas_brand2, R.id.gas_name2, R.id.gas_sub2,
                    R.id.gas_price2, R.id.gas_unit2),
            )

            views.setOnClickPendingIntent(
                R.id.gas_widget_root,
                buildLaunchIntent(context, appWidgetId, "gas", null)
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

                    views.setTextViewText(row.brand, brandShort(brand))
                    views.setInt(row.brand, "setBackgroundResource", brandDrawable(brand))
                    views.setTextColor(row.brand, Color.WHITE)

                    views.setTextViewText(row.name, name)

                    val subParts = mutableListOf<String>()
                    if (fuelLabel.isNotEmpty()) subParts.add(fuelLabel)
                    if (isSelf) subParts.add("셀프")
                    views.setTextViewText(row.sub, subParts.joinToString(" · "))

                    if (price > 0) {
                        views.setTextViewText(row.price, formatPrice(price))
                        views.setTextViewText(row.unit, "원")
                        views.setTextColor(row.price, Color.parseColor("#111827"))
                        views.setTextColor(row.unit, Color.parseColor("#9CA3AF"))
                    } else {
                        views.setTextViewText(row.price, "—")
                        views.setTextViewText(row.unit, "")
                        views.setTextColor(row.price, Color.parseColor("#CBD5E1"))
                    }

                    views.setOnClickPendingIntent(
                        row.row,
                        buildLaunchIntent(context, appWidgetId, "gas", stationId.takeIf { it.isNotEmpty() })
                    )
                }

                for (i in count until rows.size) {
                    views.setViewVisibility(rows[i].row, View.GONE)
                }

                if (count == 0) {
                    views.setViewVisibility(rows[0].row, View.VISIBLE)
                    views.setTextViewText(rows[0].brand, "+")
                    views.setInt(rows[0].brand, "setBackgroundResource", R.drawable.badge_default)
                    views.setTextColor(rows[0].brand, Color.WHITE)
                    views.setTextViewText(rows[0].name, "즐겨찾기 주유소를 추가하세요")
                    views.setTextViewText(rows[0].sub, "앱을 열어 추가")
                    views.setTextViewText(rows[0].price, "")
                    views.setTextViewText(rows[0].unit, "")
                }

            } catch (e: JSONException) {
                views.setViewVisibility(rows[0].row, View.VISIBLE)
                views.setTextViewText(rows[0].name, "데이터 로드 중...")
                views.setTextViewText(rows[0].price, "")
                views.setTextViewText(rows[0].unit, "")
                views.setViewVisibility(rows[1].row, View.GONE)
            }

            views.setTextViewText(R.id.gas_time, updatedAt)

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
            "GSC" -> R.drawable.badge_gs
            "SKE" -> R.drawable.badge_sk
            "HDO" -> R.drawable.badge_hd
            "SOL" -> R.drawable.badge_so
            "NHO" -> R.drawable.badge_nh
            "RTO", "RTX" -> R.drawable.badge_rto
            else -> R.drawable.badge_default
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
