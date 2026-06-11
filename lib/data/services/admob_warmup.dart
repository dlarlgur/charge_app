import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_service.dart';

/// AdMob 네이티브 광고 **워밍업** (SDK 응답 캐시 데우기).
///
/// 앱 시작 시 인-피드 슬롯 단위 ID 로 NativeAd.load() 를 미리 호출해 AdMob SDK 내부
/// 응답 캐시를 데운 뒤 즉시 dispose 한다. 이후 [ListAdCache] 가 같은 단위 ID 로 lazy
/// 로드하면 SDK 가 캐시된 응답을 빠르게 돌려줘 첫 표시 지연이 줄어든다.
///
/// (이전: 로드한 광고를 풀에 보관해 재사용 → 상주 부담이 커서 chat_llm 과 동일하게
///  "캐시 워밍 + ListAdCache 지연 보관" 방식으로 단순화. 더 가볍고 빠름.)
class AdMobWarmup {
  AdMobWarmup._();

  static bool _done = false;

  static void run() {
    if (_done) return;
    _done = true;
    // 첫 화면 즉시 노출 슬롯
    _warmSlot(AdUnitIds.forPosition(4));
    _warmSlot(AdUnitIds.forPosition(8));
    // 스크롤 직후 슬롯 — burst 부담 줄이려 시간차
    Future.delayed(const Duration(seconds: 2), () {
      _warmSlot(AdUnitIds.forPosition(12));
      _warmSlot(AdUnitIds.forPosition(16));
    });
    Future.delayed(const Duration(seconds: 4), () {
      _warmSlot(AdUnitIds.forPosition(20));
      _warmSlot(AdUnitIds.forPosition(24));
    });
    Future.delayed(const Duration(seconds: 7), () {
      _warmSlot(AdUnitIds.forPosition(28));
      _warmSlot(AdUnitIds.forPosition(32));
    });
  }

  static void _warmSlot(String unitId) {
    NativeAd? warm;
    warm = NativeAd(
      adUnitId: unitId,
      factoryId: 'stationCardList',
      request: const AdRequest(),
      listener: NativeAdListener(
        // 즉시 dispose — 인스턴스는 재사용 안 하지만 SDK 내부 응답 캐시에는 남음.
        onAdLoaded: (_) => warm?.dispose(),
        onAdFailedToLoad: (a, _) => a.dispose(),
      ),
    )..load();
  }
}
