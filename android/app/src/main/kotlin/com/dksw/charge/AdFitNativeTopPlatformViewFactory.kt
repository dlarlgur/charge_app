package com.dksw.charge

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.kakao.adfit.ads.AdError
import com.kakao.adfit.ads.na.AdFitAdInfoIconPosition
import com.kakao.adfit.ads.na.AdFitMediaView
import com.kakao.adfit.ads.na.AdFitNativeAdBinder
import com.kakao.adfit.ads.na.AdFitNativeAdLayout
import com.kakao.adfit.ads.na.AdFitNativeAdLoader
import com.kakao.adfit.ads.na.AdFitNativeAdRequest
import com.kakao.adfit.ads.na.AdFitNativeAdView
import com.kakao.adfit.ads.na.AdFitVideoAutoPlayPolicy
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

private const val TAG = "AdFitNativeTop"

class AdFitNativeTopPlatformViewFactory(
    private val activity: Activity,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val clientId = params?.get("clientId") as? String ?: ""
        return AdFitNativeTopPlatformView(activity, clientId)
    }
}

private class AdFitNativeTopPlatformView(
    private val activity: Activity,
    private val clientId: String,
) : PlatformView, AdFitNativeAdLoader.AdLoadListener {

    private val root: View =
        LayoutInflater.from(activity).inflate(R.layout.adfit_native_top_card, null, false)

    private val placeholder: View = root.findViewById(R.id.adfit_placeholder)
    private val containerView: AdFitNativeAdView = root.findViewById(R.id.containerView)

    private var nativeAdLoader: AdFitNativeAdLoader? = null
    private var nativeAdBinder: AdFitNativeAdBinder? = null
    private var nativeAdLayout: AdFitNativeAdLayout? = null
    private var disposed = false
    private var httpRetryDone = false
    private val mainHandler = Handler(Looper.getMainLooper())

    private val nativeRequest: AdFitNativeAdRequest = AdFitNativeAdRequest.Builder()
        .setAdInfoIconPosition(AdFitAdInfoIconPosition.LEFT_BOTTOM)
        .setVideoAutoPlayPolicy(AdFitVideoAutoPlayPolicy.WIFI_ONLY)
        .build()

    init {
        if (clientId.isNotEmpty()) {
            nativeAdLoader = AdFitNativeAdLoader.create(activity, clientId)
            nativeAdLoader?.loadAd(nativeRequest, this)
        } else {
            placeholder.visibility = View.VISIBLE
            containerView.visibility = View.INVISIBLE
        }
    }

    override fun getView(): View {
        root.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
        )
        return root
    }

    override fun onAdLoaded(binder: AdFitNativeAdBinder) {
        if (disposed) { binder.unbind(); return }
        if (activity is LifecycleOwner &&
            activity.lifecycle.currentState == Lifecycle.State.DESTROYED) {
            binder.unbind(); return
        }

        nativeAdBinder?.unbind()
        nativeAdBinder = binder

        if (nativeAdLayout == null) {
            nativeAdLayout = AdFitNativeAdLayout.Builder(containerView)
                .setContainerViewClickable(true)
                .setTitleView(root.findViewById<TextView>(R.id.titleTextView))
                .setBodyView(root.findViewById<TextView>(R.id.bodyTextView))
                .setProfileIconView(root.findViewById<ImageView>(R.id.profileIconView))
                .setProfileNameView(root.findViewById<TextView>(R.id.profileNameTextView))
                .setMediaView(root.findViewById<AdFitMediaView>(R.id.mediaView))
                .setCallToActionButton(root.findViewById<Button>(R.id.callToActionButton))
                .build()
        }

        binder.bind(nativeAdLayout!!)
        placeholder.visibility = View.GONE
        containerView.visibility = View.VISIBLE
        httpRetryDone = false
    }

    override fun onAdLoadError(errorCode: Int) {
        if (disposed) return
        Log.w(TAG, "onAdLoadError errorCode=$errorCode clientId=$clientId")
        if (!httpRetryDone && errorCode == AdError.HTTP_FAILED.errorCode && nativeAdLoader != null) {
            httpRetryDone = true
            mainHandler.postDelayed({
                if (!disposed) nativeAdLoader?.loadAd(nativeRequest, this)
            }, 900)
            return
        }
        if (nativeAdBinder == null) {
            placeholder.visibility = View.VISIBLE
            containerView.visibility = View.INVISIBLE
        }
    }

    override fun dispose() {
        disposed = true
        nativeAdBinder?.unbind()
        nativeAdBinder = null
        nativeAdLayout = null
        nativeAdLoader = null
    }
}
