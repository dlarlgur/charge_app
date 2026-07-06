import 'dart:io';

import 'package:dksw_app_core/dksw_app_core.dart';

/// 광고 네트워크 공급자 — 콘솔 원격설정 `ads_network` 로 전환.
/// AdMob 계정 정지 등 비상 시 앱 업데이트 없이 AdFit 으로 즉시 스위칭하는 용도.
enum AdNetwork { admob, adfit, off }

/// 원격설정 기반 광고 네트워크 판별.
///
/// 콘솔 원격설정 키:
///  · `ads_network`              : 'admob'(기본) | 'adfit' | 'off'
///  · `ads_network_test_only`    : true 면 아래 테스트 기기에만 전환 적용(나머지 admob)
///  · `ads_network_test_devices` : 테스트 deviceId 배열(JSON)
///
/// 우선순위는 하우스 광고가 항상 위 — house_ad_service 의 bypass 오버라이드가
/// 슬롯을 차지하면 네트워크 광고 자체가 그려지지 않으므로 여기와 무관.
class AdNetworkConfig {
  AdNetworkConfig._();

  static AdNetwork get current {
    final v = (DkswCore.config<String>('ads_network') ?? 'admob')
        .trim()
        .toLowerCase();
    AdNetwork network;
    if (v == 'adfit') {
      network = AdNetwork.adfit;
    } else if (v == 'off' || v == 'none') {
      network = AdNetwork.off;
    } else {
      network = AdNetwork.admob;
    }
    // 테스트 기기 한정 모드 — 지정 기기만 새 네트워크, 나머지는 AdMob 유지.
    // 실전 전환 전 내 기기로 먼저 검증하는 용도.
    if (network != AdNetwork.admob &&
        (DkswCore.config<bool>('ads_network_test_only') ?? false)) {
      final ids = DkswCore.config<List>('ads_network_test_devices') ?? const [];
      final mine = DkswCore.deviceId;
      if (!ids.map((e) => e.toString().trim()).contains(mine)) {
        return AdNetwork.admob;
      }
    }
    return network;
  }
}

/// 광고단위 ID 원격 오버라이드 — 앱 이전/단위 재발급 대비 (콘솔 광고 페이지에서 관리).
///
/// 원격설정 키 `admob_units` / `adfit_units`, value_type=json:
///   {"list": {"4": "<unit>", "8": "<unit>", ...}, "top": "<unit>",
///    "detail": "<unit>", "exit": "<unit>"}
/// 부분 오버라이드 — 명시된 항목만 교체, 나머지는 앱 내장 기본값.
String? _overrideUnit(String cfgKey, String field, [int? position]) {
  final raw = DkswCore.config<Map>(cfgKey);
  if (raw == null) return null;
  final dynamic v = position != null
      ? (raw[field] is Map ? (raw[field] as Map)[position.toString()] : null)
      : raw[field];
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// Kakao AdFit 광고단위 코드 (애드핏 콘솔 발급분 2026-06-26, 매체 '전기차 기름차').
/// AdMob 과 동일하게 리스트 위치별 별도 단위 — 임프레션 분리 카운트.
class AdFitUnitIds {
  AdFitUnitIds._();

  // 리스트 인-피드 (이미지 네이티브 2:1) — banner_list_1~14 → 위치 4~56.
  static const Map<int, String> _list = {
    4: 'DAN-9njcCEiVjovKRqIt', // banner_list_1
    8: 'DAN-s3e6wxKqbI72BCHv', // banner_list_2
    12: 'DAN-MEVcbAOneIcWpvmy', // banner_list_3
    16: 'DAN-0EWt8IUgxInCx3CG', // banner_list_4
    20: 'DAN-fZ3xi92MWyRMmncn', // banner_list_5
    24: 'DAN-laksjZHKWj93tK4o', // banner_list_6
    28: 'DAN-LmHl20mmh0tHan3I', // banner_list_7
    32: 'DAN-R73l7KjWdmKYTqd6', // banner_list_8
    36: 'DAN-tLN52a96uf1Uv8Cb', // banner_list_9
    40: 'DAN-nH2dJjIwY4zkiSbV', // banner_list_10
    44: 'DAN-EJrKbkUS7X41NNrr', // banner_list_11
    48: 'DAN-FHQ9S9IJMOzUpNbf', // banner_list_12
    52: 'DAN-g4ZSWSmCrxRbPtSw', // banner_list_13
    56: 'DAN-zOSHzOjab0QJCTZB', // banner_list_14
  };

  static String forPosition(int position) =>
      _overrideUnit('adfit_units', 'list', position) ??
      (_list[position] ?? _list[4]!);

  /// 홈 상단 배너 (이미지 네이티브 2:1).
  /// top_banner(구)는 노출 중단 상태 → top_banner2(2026-07-06 재발급)로 교체.
  static String get topBanner =>
      _overrideUnit('adfit_units', 'top') ?? 'DAN-9uB2oNjhMTD4jNYA'; // top_banner2

  /// 주유/충전 상세 화면 (이미지 네이티브 2:1, 2026-07-06 발급).
  static String get detail =>
      _overrideUnit('adfit_units', 'detail') ?? 'DAN-kCzG9V08OXvppqpt'; // charge_detail

  /// 앱 종료 팝업 (전용 상품 — AOS_중앙형_프로필 포함_2:1).
  static String get exit =>
      _overrideUnit('adfit_units', 'exit') ?? 'DAN-IEU82MBhLEWWwlOx'; // app_exit
}

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
    final override = _overrideUnit('admob_units', 'list', position);
    if (override != null) return override;
    final map = Platform.isIOS ? _listBannerIos : _listBannerAndroid;
    return map[position] ?? map[4]!;
  }

  /// 홈 상단 배너 광고 단위 ID (TopBannerAdmobCard — house ad 없을 때 폴백).
  static String get topBanner =>
      _overrideUnit('admob_units', 'top') ??
      (Platform.isIOS ? _topBannerIos : _topBannerAndroid);

  /// 주유소·충전소 상세 상단 네이티브 광고 단위 ID (카드 바로 아래).
  static String get stationDetailNative =>
      _overrideUnit('admob_units', 'detail') ??
      (Platform.isIOS ? _stationDetailNativeIos : _stationDetailNativeAndroid);

  /// 종료 다이얼로그 네이티브 광고 단위 ID.
  static String get exitNative =>
      _overrideUnit('admob_units', 'exit') ??
      'ca-app-pub-8640148276009977/4895744199'; // charge_exit_native
}
