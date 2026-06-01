import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_service.dart';

/// AdMob 네이티브 광고 워밍업.
///
/// 앱 시작 시 인-피드 광고 단위 ID 들로 NativeAd.load() 를 호출해 AdMob SDK
/// 내부 캐시를 데움. 결과 NativeAd 자체는 사용하지 않고 dispose. 다음 NativeAdCard
/// 위젯이 같은 단위 ID 로 load() 하면 SDK 가 캐시된 응답을 빠르게 돌려줌.
///
/// 효과:
///  - 첫 광고 표시까지 RTT 한 번 절약 (~200~500ms).
///  - 이미 데이터 자체는 SDK 캐시에 있어 두 번째 요청부터는 거의 즉답.
///
/// 8자리 모두 워밍업 하지만 burst 부담 줄이려고 시간차로:
///  - 4, 8  : 즉시 (첫 화면 노출용)
///  - 12, 16: +3초
///  - 20, 24: +6초
///  - 28, 32: +10초
class AdMobWarmup {
  AdMobWarmup._();

  static bool _done = false;

  static Future<void> run() async {
    if (_done) return;
    _done = true;
    // 첫 화면 즉시 노출 슬롯
    _warmSlot(AdUnitIds.forPosition(4));
    _warmSlot(AdUnitIds.forPosition(8));
    // 스크롤 직후 노출 슬롯 — 3초 후
    Future.delayed(const Duration(seconds: 3), () {
      _warmSlot(AdUnitIds.forPosition(12));
      _warmSlot(AdUnitIds.forPosition(16));
    });
    // 더 아래 슬롯 — 6초 후
    Future.delayed(const Duration(seconds: 6), () {
      _warmSlot(AdUnitIds.forPosition(20));
      _warmSlot(AdUnitIds.forPosition(24));
    });
    // 가장 먼 슬롯 — 10초 후
    Future.delayed(const Duration(seconds: 10), () {
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
        onAdLoaded: (_) {
          // 즉시 dispose — 인스턴스는 재사용 안 하지만 SDK 내부 응답 캐시에는 남음.
          warm?.dispose();
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
        },
      ),
    )..load();
  }
}
