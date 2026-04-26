import 'dart:io';

/// AdMob 광고 단위 ID 상수.
///
/// 본인 디바이스가 AdMob 콘솔에 **테스트 기기**로 등록되어 있는 전제로
/// 항상 실광고 단위 ID 사용. (테스트 기기는 실광고 호출되어도 임프레션·
/// 클릭이 정책 위반으로 카운트되지 않음.)
///
/// 다른 사람이 디버그 빌드 돌릴 일이 생기면 main.dart 에서
/// `MobileAds.instance.updateRequestConfiguration(...)` 로 testDeviceIds 추가.
class AdUnitIds {
  AdUnitIds._();

  // ─── 운영 단위 (네이티브 광고 고급형) ──────────────────────────────────────
  static const _topBannerAndroid = 'ca-app-pub-8640148276009977/6658354489';
  static const _listBannerAndroid = 'ca-app-pub-8640148276009977/5716378640';
  static const _topBannerIos = _topBannerAndroid; // TODO: iOS 단위 발급 후 교체
  static const _listBannerIos = _listBannerAndroid; // TODO: iOS 단위 발급 후 교체

  /// 홈 상단 (탭 토글 바로 아래) 배너 위치.
  static String get topBanner =>
      Platform.isIOS ? _topBannerIos : _topBannerAndroid;

  /// 홈 리스트 3번째 위치 인-피드 카드.
  static String get listBanner =>
      Platform.isIOS ? _listBannerIos : _listBannerAndroid;
}
