package com.dksw.charge

import android.content.Context
import android.view.LayoutInflater
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

/**
 * AdMob 네이티브 광고를 앱 카드(GasStationCard / EvStationCard) 디자인으로
 * 렌더링하는 factory. layout/native_ad_card.xml 사용.
 *
 * 등록: MainActivity.configureFlutterEngine 에서
 *   GoogleMobileAdsPlugin.registerNativeAdFactory(flutterEngine, "stationCard", ...)
 * 호출.
 *
 * Flutter 측: NativeAd(adUnitId: ..., factoryId: "stationCard") 로 사용.
 */
class StationCardNativeAdFactory(private val context: Context) :
    GoogleMobileAdsPlugin.NativeAdFactory {

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val view = LayoutInflater.from(context)
            .inflate(R.layout.native_ad_card, null) as NativeAdView

        val headline = view.findViewById<TextView>(R.id.ad_headline)
        val body = view.findViewById<TextView>(R.id.ad_body)
        val cta = view.findViewById<android.widget.Button>(R.id.ad_call_to_action)
        val icon = view.findViewById<ImageView>(R.id.ad_icon)

        // 텍스트 바인딩 — null 인 필드는 GONE 처리해 빈 줄 방지.
        headline.text = nativeAd.headline ?: ""
        view.headlineView = headline

        val bodyText = nativeAd.body
        if (bodyText.isNullOrBlank()) {
            // body 가 없으면 advertiser, store 같은 폴백 사용
            val fallback = nativeAd.advertiser ?: nativeAd.store ?: ""
            if (fallback.isBlank()) {
                body.visibility = android.view.View.GONE
            } else {
                body.text = fallback
                view.advertiserView = body
            }
        } else {
            body.text = bodyText
            view.bodyView = body
        }

        val ctaText = nativeAd.callToAction
        if (ctaText.isNullOrBlank()) {
            cta.visibility = android.view.View.GONE
        } else {
            cta.text = ctaText
            view.callToActionView = cta
        }

        val iconDrawable = nativeAd.icon?.drawable
        if (iconDrawable != null) {
            icon.setImageDrawable(iconDrawable)
            view.iconView = icon
        } else {
            // 아이콘 없으면 첫 번째 이미지를 fallback 으로 사용 (대부분 이미지 광고)
            val firstImage = nativeAd.images.firstOrNull()?.drawable
            if (firstImage != null) {
                icon.setImageDrawable(firstImage)
                view.iconView = icon
            } else {
                icon.visibility = android.view.View.INVISIBLE
            }
        }

        view.setNativeAd(nativeAd)
        return view
    }
}
