package com.dksw.charge

import android.util.Log
import androidx.fragment.app.FragmentActivity
import com.kakao.adfit.ads.popup.AdFitPopupAd
import com.kakao.adfit.ads.popup.AdFitPopupAdDialogFragment
import com.kakao.adfit.ads.popup.AdFitPopupAdLoader
import com.kakao.adfit.ads.popup.AdFitPopupAdRequest
import io.flutter.plugin.common.MethodChannel

private const val TAG = "AdFitExitAd"

/**
 * Kakao AdFit 앱 종료 팝업 광고 (전용 상품 — AOS_중앙형_프로필 포함_2:1).
 * SDK 의 AdFitPopupAdDialogFragment 가 광고 + 취소/앱 종료 버튼까지 통으로 그림.
 *
 * Flutter MethodChannel(com.dksw.charge/adfit_exit):
 *  · load {clientId} → 팝업 광고 미리 로드. true=로드됨(이미 로드돼 있으면 즉시 true)
 *  · show            → 로드된 팝업 표시. 결과 문자열:
 *      "exit"    앱 종료 확정 (Flutter 가 SystemNavigator.pop)
 *      "dismiss" 취소·뒤로가기 등으로 닫힘
 *      "none"    로드된 광고 없음 → Flutter 가 기존 종료 다이얼로그 폴백
 */
class AdFitExitAdHandler(private val activity: FragmentActivity) {

    private var loader: AdFitPopupAdLoader? = null
    private var popupAd: AdFitPopupAd? = null
    private var loading = false

    fun load(clientId: String, result: MethodChannel.Result) {
        if (clientId.isEmpty()) { result.success(false); return }
        if (popupAd != null) { result.success(true); return }
        if (loading) { result.success(false); return }

        var replied = false
        fun reply(v: Boolean) {
            if (!replied) { replied = true; result.success(v) }
        }

        val l = loader ?: AdFitPopupAdLoader.create(activity, clientId).also { loader = it }
        val request = AdFitPopupAdRequest.Builder(AdFitPopupAd.Type.Exit).build()
        loading = true
        val started = l.loadAd(request, object : AdFitPopupAdLoader.OnAdLoadListener {
            override fun onAdLoaded(ad: AdFitPopupAd) {
                loading = false
                popupAd = ad
                reply(true)
            }

            override fun onAdLoadError(errorCode: Int) {
                loading = false
                Log.w(TAG, "loadAd error=$errorCode clientId=$clientId")
                reply(false)
            }
        })
        if (!started) {
            loading = false
            reply(false)
        }
    }

    fun show(result: MethodChannel.Result) {
        val ad = popupAd
        if (ad == null || activity.isFinishing || activity.supportFragmentManager.isStateSaved) {
            result.success("none")
            return
        }
        popupAd = null // 1회 소비 — 재노출은 Flutter 가 load 재호출

        var replied = false
        fun reply(v: String) {
            if (!replied) { replied = true; result.success(v) }
        }

        val fm = activity.supportFragmentManager
        // show() 마다 재등록 — 같은 key 는 최신 listener 로 교체됨.
        fm.setFragmentResultListener(
            AdFitPopupAdDialogFragment.REQUEST_KEY_POPUP_AD, activity
        ) { _, bundle ->
            when (bundle.getString(AdFitPopupAdDialogFragment.BUNDLE_KEY_EVENT_TYPE)) {
                AdFitPopupAdDialogFragment.EVENT_EXIT_CONFIRMED -> reply("exit")
                AdFitPopupAdDialogFragment.EVENT_POPUP_CANCELED,
                AdFitPopupAdDialogFragment.EVENT_BACK_PRESSED,
                AdFitPopupAdDialogFragment.EVENT_POPUP_DISMISSED -> reply("dismiss")
                // EVENT_AD_CLICKED / EVENT_TODAY_DISMISSED 는 이어지는
                // dismiss 이벤트에서 응답 — 여기선 대기.
            }
        }
        try {
            AdFitPopupAdDialogFragment(ad).show(fm, AdFitPopupAdDialogFragment.TAG)
        } catch (e: Exception) {
            Log.w(TAG, "show 실패", e)
            reply("none")
        }
    }
}
