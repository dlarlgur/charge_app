package com.dksw.charge

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONArray

class GasSmallWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) update(context, appWidgetManager, id)
    }

    private fun update(context: Context, mgr: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_gas_small)

        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val listJson = prefs.getString("widget_gas_list", "[]") ?: "[]"

        views.setOnClickPendingIntent(R.id.gas_small_root, buildLaunch(context, widgetId))

        try {
            val list = JSONArray(listJson)
            if (list.length() == 0) {
                renderEmpty(views)
            } else {
                val item = list.getJSONObject(0)
                val name = item.optString("name", "—")
                val price = item.optInt("price", 0)
                val isSelf = item.optBoolean("isSelf", false)
                val fuelLabel = item.optString("fuelLabel", "")

                views.setTextViewText(R.id.gas_small_name, name)
                views.setTextViewText(
                    R.id.gas_small_sub,
                    if (isSelf) "$fuelLabel · 셀프" else fuelLabel
                )
                views.setTextViewText(
                    R.id.gas_small_price,
                    if (price > 0) formatPrice(price) else "—"
                )
                views.setTextViewText(
                    R.id.gas_small_foot,
                    if (fuelLabel.isNotEmpty()) fuelLabel else "최저가"
                )
            }
        } catch (_: Exception) {
            renderEmpty(views)
        }

        mgr.updateAppWidget(widgetId, views)
    }

    private fun renderEmpty(views: RemoteViews) {
        views.setTextViewText(R.id.gas_small_name, "즐겨찾기\n주유소를 추가하세요")
        views.setTextViewText(R.id.gas_small_sub, "")
        views.setTextViewText(R.id.gas_small_price, "—")
        views.setTextViewText(R.id.gas_small_foot, "앱을 열어 추가")
    }

    private fun buildLaunch(context: Context, widgetId: Int): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_MAIN)
        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        intent.putExtra("widget_type", "gas")
        return PendingIntent.getActivity(
            context, widgetId + 50000, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun formatPrice(p: Int): String =
        if (p >= 1000) "${p / 1000},${(p % 1000).toString().padStart(3, '0')}" else p.toString()
}
