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

    // ── TMAP Tapi ──
    // invokeRoute() 는 내부 첫 줄에서 apiKey 검증 여부를 보고 통과 못하면 곧장 false 를
    // 뱉는다. setSKTMapAuthentication() 은 서버 인증이라 비동기 — 바로 이어서 호출하면
    // 항상 실패한다. 그래서 인증 콜백을 기다렸다가 실행한다(성공하면 캐시).
    private var tmapTapi: com.skt.Tmap.TMapTapi? = null
    private var tmapAuthed = false

    private fun withTmapAuth(appKey: String, done: (Boolean, String?) -> Unit) {
        val main = android.os.Handler(android.os.Looper.getMainLooper())
        val tapi = tmapTapi ?: com.skt.Tmap.TMapTapi(this).also { tmapTapi = it }
        if (tmapAuthed) {
            done(true, null)
            return
        }
        var settled = false
        val timeout = Runnable {
            if (!settled) { settled = true; done(false, "auth timeout") }
        }
        tapi.setOnAuthenticationListener(
            object : com.skt.Tmap.TMapTapi.OnAuthenticationListenerCallback {
                override fun SKTMapApikeySucceed() {
                    if (settled) return
                    settled = true
                    tmapAuthed = true
                    main.removeCallbacks(timeout)
                    main.post { done(true, null) }
                }

                override fun SKTMapApikeyFailed(msg: String?) {
                    if (settled) return
                    settled = true
                    main.removeCallbacks(timeout)
                    main.post { done(false, msg ?: "auth failed") }
                }
            }
        )
        tapi.setSKTMapAuthentication(appKey)
        main.postDelayed(timeout, 5000)
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
                    val appKey = call.argument<String>("appKey") ?: ""
                    val info = (call.argument<Map<String, Any?>>("routeInfo") ?: emptyMap())
                        .mapValues { it.value?.toString() ?: "" }
                    // 왜 실패했는지(인증/미설치/거부) Dart 로그에 남긴다 — 폴백이 조용하면
                    // "경유지가 안 들어온다"는 증상만 남고 원인을 못 잡는다.
                    withTmapAuth(appKey) { ok, err ->
                        if (!ok) {
                            result.success(mapOf("ok" to false, "reason" to "auth:$err"))
                        } else {
                            try {
                                val tapi = tmapTapi!!
                                if (!tapi.isTmapApplicationInstalled) {
                                    result.success(mapOf("ok" to false, "reason" to "not_installed"))
                                } else {
                                    val done = tapi.invokeRoute(HashMap(info))
                                    result.success(
                                        mapOf("ok" to done, "reason" to if (done) null else "invoke_false")
                                    )
                                }
                            } catch (e: Throwable) {
                                result.success(mapOf("ok" to false, "reason" to "throw:${e.message}"))
                            }
                        }
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
