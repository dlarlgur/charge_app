import 'package:dio/dio.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/foundation.dart';

/// 폴백 하우스 광고 — 네트워크(AdMob/AdFit)가 광고를 못 채웠을 때 대신 노출.
/// 콘솔에서 home_top/station_detail 하우스 광고를 "네트워크 무시" 해제(bypass=0)로
/// 등록하면 폴백이 됨. 없으면 자리 접음.
///
/// placement 별 1건을 부팅 시 미리 받아 캐시. (네트워크 실패 시점에 즉시 그려야 하므로)
class FallbackAd {
  final int id;
  final String displayStyle; // 'card' | 'banner'
  final String imageUrl;
  final String? headline;
  final String? bodyText;
  final String? ctaLabel;
  final String? ctaUrl;
  final String ctaType;

  const FallbackAd({
    required this.id,
    required this.displayStyle,
    required this.imageUrl,
    this.headline,
    this.bodyText,
    this.ctaLabel,
    this.ctaUrl,
    required this.ctaType,
  });

  bool get isStructured => headline != null && headline!.trim().isNotEmpty;

  factory FallbackAd.fromJson(Map<String, dynamic> j) => FallbackAd(
        id: (j['id'] as num).toInt(),
        displayStyle:
            j['displayStyle']?.toString() == 'banner' ? 'banner' : 'card',
        imageUrl: j['imageUrl']?.toString() ?? '',
        headline: j['headline']?.toString(),
        bodyText: j['bodyText']?.toString(),
        ctaLabel: j['ctaLabel']?.toString(),
        ctaUrl: j['ctaUrl']?.toString(),
        ctaType: j['ctaType']?.toString() ?? 'none',
      );
}

class AdFallbackCache {
  AdFallbackCache._();

  static const _consoleBase = 'https://console.dksw4.com/console';
  static const _placements = ['home_top', 'station_detail'];

  static final Map<String, FallbackAd?> _cache = {};

  /// placement 폴백 광고 (없으면 null). fetch 전이면 null.
  static FallbackAd? at(String placement) => _cache[placement];

  /// 부팅 시 1회 — 모든 폴백 슬롯 병렬 fetch. 실패는 무시(폴백 없음 취급).
  static Future<void> fetchAll() async {
    final dio = Dio()..transformer = BackgroundTransformer();
    await Future.wait(_placements.map((pl) => _fetchOne(dio, pl)));
  }

  static Future<void> _fetchOne(Dio dio, String placement) async {
    try {
      final res = await dio.get(
        '$_consoleBase/api/ad-fallback',
        queryParameters: {
          'package': 'com.dksw.charge',
          'placement': placement,
          'device_id': DkswCore.deviceId,
        },
        options: Options(receiveTimeout: const Duration(seconds: 6)),
      );
      final ad = res.data is Map ? res.data['ad'] : null;
      _cache[placement] =
          ad is Map ? FallbackAd.fromJson(Map<String, dynamic>.from(ad)) : null;
    } catch (e) {
      if (kDebugMode) debugPrint('[ad-fallback] $placement fetch 실패: $e');
      _cache[placement] = null;
    }
  }
}
