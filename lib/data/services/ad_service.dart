import 'dart:io';

/// AdMob 광고 단위 ID 상수.
/// 디버그 빌드(또는 ENABLE_TEST_ADS=1) 에서는 Google 테스트 단위로 자동 치환.
class AdUnitIds {
  AdUnitIds._();

  // ─── 운영 단위 (네이티브 광고 고급형) ──────────────────────────────────────
  // AdMob 콘솔에서 발급받은 실제 단위 ID. 안드로이드만 발급되어 있어 iOS 는
  // 동일 ID 로 두되 콘솔에서 iOS 단위 따로 발급 후 분기하는 게 정석.
  static const _topBannerAndroid = 'ca-app-pub-8640148276009977/6658354489';
  static const _listBannerAndroid = 'ca-app-pub-8640148276009977/5716378640';
  static const _topBannerIos = _topBannerAndroid; // TODO: iOS 단위 발급 후 교체
  static const _listBannerIos = _listBannerAndroid; // TODO: iOS 단위 발급 후 교체

  // ─── 테스트 단위 (Google 공식) ────────────────────────────────────────────
  // 디버그 빌드에서는 항상 이 값을 사용해 정책 위반(자가 클릭) 방지.
  static const _testNativeAndroid = 'ca-app-pub-3940256099942544/2247696110';
  static const _testNativeIos = 'ca-app-pub-3940256099942544/3986624511';

  static bool _useTestAds() {
    // const bool.fromEnvironment 대신 assert 분기로 디버그 판정.
    bool isDebug = false;
    assert(() { isDebug = true; return true; }());
    return isDebug;
  }

  /// 홈 상단 (탭 토글 바로 아래) 배너 위치.
  static String get topBanner {
    if (_useTestAds()) {
      return Platform.isIOS ? _testNativeIos : _testNativeAndroid;
    }
    return Platform.isIOS ? _topBannerIos : _topBannerAndroid;
  }

  /// 홈 리스트 3번째 위치 인-피드 카드.
  static String get listBanner {
    if (_useTestAds()) {
      return Platform.isIOS ? _testNativeIos : _testNativeAndroid;
    }
    return Platform.isIOS ? _listBannerIos : _listBannerAndroid;
  }
}
