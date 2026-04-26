package com.dksw.charge

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val ADFIT_NATIVE_TOP_VIEW_TYPE  = "com.dksw.charge/adfit_native_top"
        const val ADFIT_NATIVE_LIST_VIEW_TYPE = "com.dksw.charge/adfit_native_list"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleWidgetIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleWidgetIntent(intent)
    }

    /**
     * 홈 위젯에서 전달된 extras 를 Flutter 가 읽을 수 있도록
     * SharedPreferences 에 저장한다. Flutter 측에서 시작 시 소비.
     */
    private fun handleWidgetIntent(intent: Intent?) {
        if (intent == null) return
        val type = intent.getStringExtra("widget_type") ?: return
        val stationId = intent.getStringExtra("widget_station_id")
        val prefs = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putString("widget_pending_type", type)
            if (stationId != null) {
                putString("widget_pending_station_id", stationId)
            } else {
                remove("widget_pending_station_id")
            }
            apply()
        }
        // Consume extras so repeat onNewIntent doesn't re-trigger
        intent.removeExtra("widget_type")
        intent.removeExtra("widget_station_id")
    }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Kakao AdFit 네이티브 상단 카드 (홈 탭바 아래) — 레거시
        flutterEngine.platformViewsController.registry.registerViewFactory(
            ADFIT_NATIVE_TOP_VIEW_TYPE,
            AdFitNativeTopPlatformViewFactory(this),
        )
        // Kakao AdFit 네이티브 목록 슬롯 (리스트 3번째) — 레거시
        flutterEngine.platformViewsController.registry.registerViewFactory(
            ADFIT_NATIVE_LIST_VIEW_TYPE,
            AdFitNativeListPlatformViewFactory(this),
        )

        // AdMob 네이티브 광고 — 앱 카드 디자인 (factoryId="stationCard").
        // Flutter 측에서 NativeAd(factoryId: "stationCard") 로 호출 시 매칭.
        io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "stationCard",
            StationCardNativeAdFactory(this),
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        // AdMob factory 해제 — 누수 방지
        io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
            .unregisterNativeAdFactory(flutterEngine, "stationCard")
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
