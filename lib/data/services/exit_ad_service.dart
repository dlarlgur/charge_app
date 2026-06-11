import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 앱 종료 시 노출하는 전면(Interstitial) 광고.
///
/// 미리 로드해두고(종료 시점엔 네트워크 대기 없이 즉시 노출), 광고가 닫히면
/// [onDone] 으로 실제 종료를 진행한다. 광고 미준비/실패 시 종료를 막지 않고
/// 즉시 [onDone] 호출 — 사용자가 종료를 못 하는 일이 없도록.
class ExitAdService {
  ExitAdService._();
  static final ExitAdService instance = ExitAdService._();

  static const String _adUnitId = 'ca-app-pub-8640148276009977/3346750036';

  InterstitialAd? _ad;
  bool _loading = false;
  bool _showing = false;

  /// 전면광고 미리 로드 (앱 시작 시 1회 호출).
  void preload() {
    if (_ad != null || _loading) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
        },
        onAdFailedToLoad: (error) {
          if (kDebugMode) debugPrint('[ExitAd] load 실패: ${error.message}');
          _ad = null;
          _loading = false;
        },
      ),
    );
  }

  /// 종료 시점 호출 — 광고가 준비됐으면 보여주고 닫힌 뒤 [onDone],
  /// 없으면(또는 노출 중이면) 즉시 [onDone].
  void showThenExit(VoidCallback onDone) {
    final ad = _ad;
    if (ad == null || _showing) {
      onDone();
      return;
    }
    _showing = true;
    _ad = null; // 소비 — 한 광고는 1회만 노출 가능
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _showing = false;
        onDone();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _showing = false;
        onDone();
      },
    );
    ad.show();
  }
}
