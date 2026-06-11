package com.dksw.charge

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

/**
 * 1:1 문의 화면 상단 네이티브 광고 — 세로 카드.
 * (AD 뱃지 + 광고주 / 큰 헤드라인 / 풀폭 그라데이션 CTA)
 * factoryId = "inquiryCard"
 */
class InquiryNativeAdFactory(private val context: Context) :
    GoogleMobileAdsPlugin.NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val view = LayoutInflater.from(context)
            .inflate(R.layout.native_ad_inquiry, null) as NativeAdView

        val headline = view.findViewById<TextView>(R.id.ad_headline)
        val advertiser = view.findViewById<TextView>(R.id.ad_advertiser)
        val cta = view.findViewById<Button>(R.id.ad_call_to_action)

        headline.text = nativeAd.headline ?: ""
        view.headlineView = headline

        val adv = nativeAd.advertiser ?: nativeAd.store
        if (adv.isNullOrBlank()) {
            advertiser.visibility = View.GONE
        } else {
            advertiser.text = adv
            view.advertiserView = advertiser
        }

        val ctaText = nativeAd.callToAction
        if (ctaText.isNullOrBlank()) {
            cta.visibility = View.GONE
        } else {
            cta.text = "$ctaText  →"
            view.callToActionView = cta
        }

        view.setNativeAd(nativeAd)
        return view
    }
}
