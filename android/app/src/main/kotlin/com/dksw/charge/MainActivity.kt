package com.dksw.charge

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val ADFIT_NATIVE_TOP_VIEW_TYPE  = "com.dksw.charge/adfit_native_top"
        const val ADFIT_NATIVE_LIST_VIEW_TYPE = "com.dksw.charge/adfit_native_list"
    }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Kakao AdFit 네이티브 상단 카드 (홈 탭바 아래)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            ADFIT_NATIVE_TOP_VIEW_TYPE,
            AdFitNativeTopPlatformViewFactory(this),
        )
        // Kakao AdFit 네이티브 목록 슬롯 (리스트 3번째)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            ADFIT_NATIVE_LIST_VIEW_TYPE,
            AdFitNativeListPlatformViewFactory(this),
        )
    }
}
