package com.dksw.charge

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val ADFIT_NATIVE_TOP_VIEW_TYPE  = "com.dksw.charge/adfit_native_top"
        const val ADFIT_NATIVE_LIST_VIEW_TYPE = "com.dksw.charge/adfit_native_list"
        const val ADFIT_EXIT_CHANNEL          = "com.dksw.charge/adfit_exit"
        // TMAP 앱 연동(Tapi) — 경유지 포함 길안내
        const val TMAP_CHANNEL                = "com.dksw.charge/tmap"
    }

    // AdFit 앱 종료 팝업 광고 (전용 상품 — SDK 다이얼로그) MethodChannel 연동.
    private val adFitExitAd by lazy { AdFitExitAdHandler(this) }

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

        // Kakao AdFit 네이티브 상단/상세 카드 — 실패 이벤트 채널 포함(자리 접기)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            ADFIT_NATIVE_TOP_VIEW_TYPE,
            AdFitNativeTopPlatformViewFactory(this, flutterEngine.dartExecutor.binaryMessenger),
        )
        // Kakao AdFit 네이티브 목록 슬롯 (리스트 3번째) — 레거시
        flutterEngine.platformViewsController.registry.registerViewFactory(
            ADFIT_NATIVE_LIST_VIEW_TYPE,
            AdFitNativeListPlatformViewFactory(this),
        )

        // AdMob 네이티브 광고 — 두 layout 분리:
        //  - stationCardTop  : 강조형 (홈 상단)
        //  - stationCardList : 인라인 (리스트 3번째)
        io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "stationCardTop",
            StationCardTopNativeAdFactory(this),
        )
        io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "stationCardList",
            StationCardListNativeAdFactory(this),
        )
        io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "stationCardListEv",
            StationCardListEvNativeAdFactory(this),
        )
        // 1:1 문의 화면 상단 — 세로 카드 (큰 헤드라인 + 풀폭 CTA)
        io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "inquiryCard",
            InquiryNativeAdFactory(this),
        )

        // AdFit 앱 종료 팝업 — load(미리 로드) / show(표시, 결과 exit|dismiss|none)
        io.flutter.plugin.common.MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ADFIT_EXIT_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> adFitExitAd.load(call.argument<String>("clientId") ?: "", result)
                "show" -> adFitExitAd.show(result)
                else -> result.notImplemented()
            }
        }

        // TMAP 앱 연동 — 경유지를 포함한 길안내를 티맵 앱에 넘긴다.
        // URL 스킴(tmap://route)으로는 목적지 하나만 가능하고 경유지는 무시된다.
        // 공식 SDK 는 앱키 인증 후 HashMap(rGoName/rStName/rV1Name…)을 받아 처리한다.
        io.flutter.plugin.common.MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TMAP_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "invokeRoute" -> {
                    try {
                        val appKey = call.argument<String>("appKey") ?: ""
                        @Suppress("UNCHECKED_CAST")
                        val info = (call.argument<Map<String, Any?>>("routeInfo") ?: emptyMap())
                            .mapValues { it.value?.toString() ?: "" }
                        val tapi = com.skt.Tmap.TMapTapi(this)
                        tapi.setSKTMapAuthentication(appKey)
                        result.success(tapi.invokeRoute(HashMap(info)))
                    } catch (e: Throwable) {
                        result.success(false) // 실패 시 Dart 가 URL 스킴으로 폴백
                    }
                }
                "isInstalled" -> {
                    val ok = try {
                        packageManager.getPackageInfo("com.skt.tmap.ku", 0) != null
                    } catch (_: Throwable) {
                        false
                    }
                    result.success(ok)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        // AdMob factory 해제 — 누수 방지
        io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
            .unregisterNativeAdFactory(flutterEngine, "stationCardTop")
        io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
            .unregisterNativeAdFactory(flutterEngine, "stationCardList")
        io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
            .unregisterNativeAdFactory(flutterEngine, "stationCardListEv")
        io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
            .unregisterNativeAdFactory(flutterEngine, "inquiryCard")
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
