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
  // 실패 재시도 횟수(키별). 첫 슬롯은 목록에서 가장 먼저 빌드돼 AdMob SDK init 완료
  // 전에 로드가 나가 실패하는 레이스가 있음 → 짧은 지연 후 제한적으로 재시도.
  static final Map<String, int> _retries = {};
  static const int _maxRetries = 3;
  // 재시도까지 전부 실패(no-fill 등) — 카드가 자리 예약 대신 접히도록 알림.
  // (신규 광고단위는 fill 붙기까지 며칠 걸릴 수 있어 빈 칸 방치가 더 나쁨)
  static final Map<String, ValueNotifier<bool>> _failed = {};

  /// 최종 실패 여부 알림 — true 면 카드는 SizedBox.shrink() 로 접는다.
  static ValueNotifier<bool> failedNotifier(String key) =>
      _failed.putIfAbsent(key, () => ValueNotifier<bool>(false));

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
        onAdLoaded: (_) {
          _retries.remove(key);
          failedNotifier(key).value = false;
          notifier.value = true;
        },
        onAdFailedToLoad: (a, _) {
          a.dispose();
          _ads.remove(key);
          notifier.value = false;
          // SDK init 레이스/일시적 no-fill 대비 제한적 재시도(지수 백오프).
          final n = _retries[key] ?? 0;
          if (n < _maxRetries) {
            _retries[key] = n + 1;
            Future.delayed(Duration(milliseconds: 700 * (n + 1)),
                () => ensureLoaded(key, unitId, factoryId));
          } else {
            // 최종 실패 — 카드 접기 (빈 자리 예약 해제).
            failedNotifier(key).value = true;
          }
        },
      ),
    )..load();
    _ads[key] = ad;
  }
}
