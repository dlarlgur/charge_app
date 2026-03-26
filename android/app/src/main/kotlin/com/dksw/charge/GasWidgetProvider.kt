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

            // Tap widget → open app
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (intent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context, 0, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(android.R.id.content, pendingIntent)
            }

            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val listJson = prefs.getString("flutter.widget_gas_list", "[]") ?: "[]"
            val updatedAt = prefs.getString("flutter.widget_gas_updated", "") ?: ""

            data class RowIds(val row: Int, val brand: Int, val name: Int, val sub: Int, val price: Int)
            val rows = listOf(
                RowIds(R.id.gas_row1, R.id.gas_brand1, R.id.gas_name1, R.id.gas_sub1, R.id.gas_price1),
                RowIds(R.id.gas_row2, R.id.gas_brand2, R.id.gas_name2, R.id.gas_sub2, R.id.gas_price2),
                RowIds(R.id.gas_row3, R.id.gas_brand3, R.id.gas_name3, R.id.gas_sub3, R.id.gas_price3),
            )

            try {
                val list = JSONArray(listJson)
                val count = minOf(list.length(), 3)

                for (i in 0 until count) {
                    val item = list.getJSONObject(i)
                    val brand = item.optString("brand", "")
                    val name = item.optString("name", "—")
                    val price = item.optInt("price", 0)
                    val isSelf = item.optBoolean("isSelf", false)
                    val fuelLabel = item.optString("fuelLabel", "")

                    val row = rows[i]
                    views.setViewVisibility(row.row, View.VISIBLE)

                    // Brand badge
                    views.setTextViewText(row.brand, brandShort(brand))
                    views.setInt(row.brand, "setBackgroundColor", brandBgColor(brand))
                    views.setTextColor(row.brand, brandTextColor(brand))

                    // Name
                    views.setTextViewText(row.name, name)

                    // Sub info
                    val subParts = mutableListOf<String>()
                    if (fuelLabel.isNotEmpty()) subParts.add(fuelLabel)
                    if (isSelf) subParts.add("셀프")
                    views.setTextViewText(row.sub, subParts.joinToString(" · "))

                    // Price
                    if (price > 0) {
                        views.setTextViewText(row.price, formatPrice(price) + "원")
                        views.setTextColor(row.price, Color.parseColor("#1a1a1a"))
                    } else {
                        views.setTextViewText(row.price, "—")
                        views.setTextColor(row.price, Color.parseColor("#BBBBBB"))
                    }
                }

                // Hide unused rows
                for (i in count until 3) {
                    views.setViewVisibility(rows[i].row, View.GONE)
                }

                // Show empty state if no favorites
                if (count == 0) {
                    views.setTextViewText(R.id.gas_name1, "즐겨찾기 주유소를 추가하세요")
                    views.setTextViewText(R.id.gas_price1, "")
                    views.setViewVisibility(R.id.gas_row1, View.VISIBLE)
                }

            } catch (e: JSONException) {
                views.setTextViewText(R.id.gas_name1, "데이터 로드 중...")
                views.setViewVisibility(R.id.gas_row1, View.VISIBLE)
                views.setViewVisibility(R.id.gas_row2, View.GONE)
                views.setViewVisibility(R.id.gas_row3, View.GONE)
            }

            if (updatedAt.isNotEmpty()) {
                views.setTextViewText(R.id.gas_footer, "$updatedAt · Opinet")
            } else {
                views.setTextViewText(R.id.gas_footer, "앱을 열면 자동 업데이트")
            }
            views.setTextViewText(R.id.gas_time, updatedAt.takeLast(5).ifEmpty { "" })

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun brandShort(brand: String): String = when (brand) {
            "GSC" -> "GS"
            "SKE" -> "SK"
            "HDO" -> "HD"
            "SOL" -> "SO"
            "RTO", "RTX" -> "알"
            "NHO" -> "NH"
            else -> if (brand.length >= 2) brand.take(2) else brand.ifEmpty { "?" }
        }

        private fun brandBgColor(brand: String): Int = when (brand) {
            "GSC" -> Color.parseColor("#E1F5EE")
            "SKE" -> Color.parseColor("#FCEBEB")
            "HDO" -> Color.parseColor("#E6F1FB")
            "SOL" -> Color.parseColor("#FAEEDA")
            "RTO", "RTX", "NHO" -> Color.parseColor("#F5F5F5")
            else -> Color.parseColor("#F5F5F5")
        }

        private fun brandTextColor(brand: String): Int = when (brand) {
            "GSC" -> Color.parseColor("#085041")
            "SKE" -> Color.parseColor("#791F1F")
            "HDO" -> Color.parseColor("#0C447C")
            "SOL" -> Color.parseColor("#633806")
            else -> Color.parseColor("#666666")
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
