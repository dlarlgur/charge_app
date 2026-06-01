import 'dart:io';

/// AdMob 광고 단위 ID 상수.
/// 본인 디바이스가 AdMob 콘솔에 테스트 기기로 등록되어 있는 전제로 항상 실광고 ID 사용.
///
/// 주유/충전 리스트 모두 동일한 인-피드 슬롯 패턴 (admobSlots = {4, 8}) 사용.
/// list_banner1~8 은 향후 admobSlots 확장 대비 9개 미리 발급해 둠.
/// top_banner 는 별도 위치 (현재 미사용, 추후 상단 배너 자리 추가 시).
class AdUnitIds {
  AdUnitIds._();

  // ─── 리스트 인-피드 광고 (Android) — list_position 별 9개 발급 ───
  static const Map<int, String> _listBannerAndroid = {
    1: 'ca-app-pub-8640148276009977/5716378640', // charge_list_banner1
    2: 'ca-app-pub-8640148276009977/4494809624', // charge_list_banner2
    3: 'ca-app-pub-8640148276009977/1868646285', // charge_list_banner3
    4: 'ca-app-pub-8640148276009977/9555564614', // charge_list_banner4
    5: 'ca-app-pub-8640148276009977/6929401276', // charge_list_banner5
    6: 'ca-app-pub-8640148276009977/4484721249', // charge_list_banner6
    7: 'ca-app-pub-8640148276009977/8998151099', // charge_list_banner7
    8: 'ca-app-pub-8640148276009977/2975668229', // charge_list_banner8
  };

  // ─── 상단 배너 (Android) ───
  static const String _topBannerAndroid =
      'ca-app-pub-8640148276009977/6658354489'; // charge_top_banner

  // ─── iOS — TODO: iOS 단위 ID 발급 후 교체 (현재 Android 재사용) ───
  static const Map<int, String> _listBannerIos = _listBannerAndroid;
  static const String _topBannerIos = _topBannerAndroid;

  /// 리스트 list_position 에 매핑되는 광고 단위 ID.
  /// position 이 1~8 범위 밖이면 list_banner1 으로 fallback.
  static String forPosition(int position) {
    final map = Platform.isIOS ? _listBannerIos : _listBannerAndroid;
    return map[position] ?? map[1]!;
  }

  /// 상단 배너 광고 단위 ID (별도 자리 — 현재 home/list 어디서도 호출 X,
  /// 추후 화면에 top banner 자리 추가 시 사용).
  static String get topBanner =>
      Platform.isIOS ? _topBannerIos : _topBannerAndroid;
}
