import 'dart:io';

/// AdMob 광고 단위 ID 상수.
/// 본인 디바이스가 AdMob 콘솔에 테스트 기기로 등록되어 있는 전제로 항상 실광고 ID 사용.
///
/// 리스트 위치 4 간격으로 최대 14자리 (4·8·…·56) AdMob 노출.
/// 실제 활성 개수는 콘솔 원격설정 ads.list_max_count 로 제어(앞에서부터 N개).
/// 각 위치마다 별개 unit ID 라야 AdMob 측에서 임프레션을 분리 카운트.
/// 주유/충전 리스트 모두 동일한 admobSlots 사용 (house_ad_service.dart 참조).
class AdUnitIds {
  AdUnitIds._();

  // ─── 리스트 인-피드 광고 (Android) — list_position 별 8개 ───
  //   position 4  → list_banner1
  //   position 8  → list_banner2
  //   position 12 → list_banner3
  //   ...
  //   position 32 → list_banner8
  static const Map<int, String> _listBannerAndroid = {
    4:  'ca-app-pub-8640148276009977/5716378640', // charge_list_banner1
    8:  'ca-app-pub-8640148276009977/4494809624', // charge_list_banner2
    12: 'ca-app-pub-8640148276009977/1868646285', // charge_list_banner3
    16: 'ca-app-pub-8640148276009977/9555564614', // charge_list_banner4
    20: 'ca-app-pub-8640148276009977/6929401276', // charge_list_banner5
    24: 'ca-app-pub-8640148276009977/4484721249', // charge_list_banner6
    28: 'ca-app-pub-8640148276009977/8998151099', // charge_list_banner7
    32: 'ca-app-pub-8640148276009977/2975668229', // charge_list_banner8
    36: 'ca-app-pub-8640148276009977/1851754826', // charge_list_banner9
    40: 'ca-app-pub-8640148276009977/5354061736', // charge_list_banner10
    44: 'ca-app-pub-8640148276009977/3330533624', // charge_list_banner11
    48: 'ca-app-pub-8640148276009977/2017451951', // charge_list_banner12
    52: 'ca-app-pub-8640148276009977/8179535629', // charge_list_banner13
    56: 'ca-app-pub-8640148276009977/4452043600', // charge_list_banner14
  };

  // ─── 상단 배너 (Android) — 현재 미사용, 추후 화면 상단 배너 자리 추가 시 ───
  static const String _topBannerAndroid =
      'ca-app-pub-8640148276009977/6658354489'; // charge_top_banner

  // ─── 상세화면 상단(주유소/충전소 카드 바로 아래) 네이티브 광고 (Android) ───
  static const String _stationDetailNativeAndroid =
      'ca-app-pub-8640148276009977/5929557058'; // charge_detail_native

  // ─── iOS — TODO: iOS 단위 ID 발급 후 교체 (현재 Android 재사용) ───
  static const Map<int, String> _listBannerIos = _listBannerAndroid;
  static const String _topBannerIos = _topBannerAndroid;
  static const String _stationDetailNativeIos = _stationDetailNativeAndroid;

  /// 리스트 list_position 에 매핑되는 광고 단위 ID.
  /// admobSlots 외 position 호출 시 list_banner1 으로 fallback.
  static String forPosition(int position) {
    final map = Platform.isIOS ? _listBannerIos : _listBannerAndroid;
    return map[position] ?? map[4]!;
  }

  /// 상단 배너 광고 단위 ID — 현재 호출처 없음 (추후 상단 자리 추가 시).
  static String get topBanner =>
      Platform.isIOS ? _topBannerIos : _topBannerAndroid;

  /// 주유소·충전소 상세 상단 네이티브 광고 단위 ID (카드 바로 아래).
  static String get stationDetailNative =>
      Platform.isIOS ? _stationDetailNativeIos : _stationDetailNativeAndroid;
}
