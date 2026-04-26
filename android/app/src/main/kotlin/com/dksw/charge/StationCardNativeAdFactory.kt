package com.dksw.charge

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

/**
 * 두 가지 네이티브 광고 layout 을 노출하는 공용 헬퍼.
 *  - factoryId="stationCardTop"  → R.layout.native_ad_top  (강조형 ~108dp)
 *  - factoryId="stationCardList" → R.layout.native_ad_list (인라인 ~64dp)
 *
 * 두 layout 모두 NativeAdView root + ad_icon / ad_headline / ad_body /
 * ad_call_to_action 동일한 view id 를 가지므로 binding 코드를 공유.
 */
private fun bind(view: NativeAdView, nativeAd: NativeAd) {
    val headline = view.findViewById<TextView>(R.id.ad_headline)
    val body = view.findViewById<TextView>(R.id.ad_body)
    val cta = view.findViewById<Button>(R.id.ad_call_to_action)
    val icon = view.findViewById<ImageView>(R.id.ad_icon)

    headline.text = nativeAd.headline ?: ""
    view.headlineView = headline

    val bodyText = nativeAd.body
    if (bodyText.isNullOrBlank()) {
        val fallback = nativeAd.advertiser ?: nativeAd.store ?: ""
        if (fallback.isBlank()) {
            body.visibility = View.GONE
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
        cta.visibility = View.GONE
    } else {
        cta.text = ctaText
        view.callToActionView = cta
    }

    val iconDrawable = nativeAd.icon?.drawable
    if (iconDrawable != null) {
        icon.setImageDrawable(iconDrawable)
        view.iconView = icon
    } else {
        val firstImage = nativeAd.images.firstOrNull()?.drawable
        if (firstImage != null) {
            icon.setImageDrawable(firstImage)
            view.iconView = icon
        } else {
            icon.visibility = View.INVISIBLE
        }
    }

    view.setNativeAd(nativeAd)
}

class StationCardTopNativeAdFactory(private val context: Context) :
    GoogleMobileAdsPlugin.NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val view = LayoutInflater.from(context)
            .inflate(R.layout.native_ad_top, null) as NativeAdView
        bind(view, nativeAd)
        return view
    }
}

class StationCardListNativeAdFactory(private val context: Context) :
    GoogleMobileAdsPlugin.NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val view = LayoutInflater.from(context)
            .inflate(R.layout.native_ad_list, null) as NativeAdView
        bind(view, nativeAd)
        return view
    }
}
