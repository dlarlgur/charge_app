import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_service.dart';

/// AdMob 네이티브 광고 워밍업.
///
/// 앱 시작 시 슬롯 1·2 의 광고 단위 ID 로 한 번 NativeAd.load() 를 호출해
/// AdMob SDK 내부 캐시를 데움. 결과 NativeAd 자체는 사용하지 않고 dispose
/// (광고 재사용은 SDK 가 허용 안 함). 다음 NativeAdCard 위젯이 마운트할 때
/// 같은 단위 ID 로 load() 하면 SDK 가 캐시된 응답을 빠르게 돌려줌.
///
/// 효과:
///  - 첫 광고 표시까지 RTT 한 번 절약 (~200~500ms).
///  - 이미 데이터 자체는 SDK 캐시에 있어 두 번째 요청부터는 거의 즉답.
class AdMobWarmup {
  AdMobWarmup._();

  static bool _done = false;

  static Future<void> run() async {
    if (_done) return;
    _done = true;
    _warmSlot(AdUnitIds.slot1);
    _warmSlot(AdUnitIds.slot2);
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
