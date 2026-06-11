import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_service.dart';

/// AdMob 네이티브 광고 **프리로드 풀**.
///
/// 앱 시작 시 인-피드 슬롯 광고를 미리 load 해서 **'준비된 NativeAd'** 를 풀에 보관.
/// 스크롤로 광고 카드가 등장할 때 풀에서 **즉시 꺼내 붙이므로**, 스크롤 도중
/// load→표시 전환(플랫폼뷰 삽입 hitch)이 없어 리스트가 부드럽게 움직인다.
///
/// (gas factory `stationCardList` 기준. EV 카드는 다른 factory 라 풀 미사용.)
class AdMobWarmup {
  AdMobWarmup._();

  static bool _done = false;
  static final Map<String, NativeAd> _pool = {}; // unitId → 준비된 광고

  /// 풀에서 준비된 광고를 꺼냄(소유권 이전). 없으면 null → 카드가 직접 load.
  static NativeAd? take(String unitId) => _pool.remove(unitId);

  static Future<void> run() async {
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
    if (_pool.containsKey(unitId)) return;
    NativeAd? ad;
    ad = NativeAd(
      adUnitId: unitId,
      factoryId: 'stationCardList',
      request: const AdRequest(),
      listener: NativeAdListener(
        // 준비된 광고를 풀에 보관 → 카드가 스크롤 중 즉시 사용(전환 hitch 없음).
        onAdLoaded: (_) => _pool[unitId] = ad!,
        onAdFailedToLoad: (a, _) => a.dispose(),
      ),
    )..load();
  }
}
