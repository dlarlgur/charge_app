import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 목록 인-피드 AdMob 네이티브 광고 **보관 캐시**.
///
/// chat_llm 의 "화면이 광고를 보관" 방식을 charge_app 에 이식한 전역 버전.
/// 광고를 카드가 소유하지 않고 여기서 (unitId+factory) 키로 1회 로드해 보관하므로:
///   - 스크롤로 카드가 벗어나도 인스턴스가 살아 있어 **재진입 시 재로드(네트워크·깜빡임) 없음**
///   - 그러면서 PlatformView 자체는 카드가 사라지면 unmount 되어 **상주(keepalive) 부담 없음**
///     → 되돌아오면 보관 인스턴스를 다시 mount(가벼운 재구성)만.
///
/// 즉 KeepAlive(상주 PlatformView) + 프리로드 풀 없이도 매끄럽고 가볍다.
class ListAdCache {
  ListAdCache._();

  static final Map<String, NativeAd> _ads = {};
  static final Map<String, ValueNotifier<bool>> _ready = {};

  /// 키의 준비 상태 알림. 카드가 ValueListenableBuilder 로 구독 → 로드 완료 시 자동 갱신.
  static ValueNotifier<bool> readyNotifier(String key) =>
      _ready.putIfAbsent(key, () => ValueNotifier<bool>(false));

  /// 키에 보관된 광고(없으면 null).
  static NativeAd? ad(String key) => _ads[key];

  /// 키에 광고가 없으면 로드(지연). 이미 로드/로딩 중이면 재사용(재로드 X).
  static void ensureLoaded(String key, String unitId, String factoryId) {
    if (_ads.containsKey(key)) return;
    final notifier = readyNotifier(key);
    final ad = NativeAd(
      adUnitId: unitId,
      factoryId: factoryId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) => notifier.value = true,
        onAdFailedToLoad: (a, _) {
          a.dispose();
          _ads.remove(key);
          notifier.value = false; // 실패 — 카드는 빈 자리(placeholder/shrink) 유지
        },
      ),
    )..load();
    _ads[key] = ad;
  }
}
