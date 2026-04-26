import 'package:dio/dio.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import '../../core/constants/api_constants.dart';

enum HouseAdMode { solo, fallback, mix }

/// 콘솔에서 등록한 직접(house) 광고 한 건.
/// imageUrl 은 상대 경로일 수 있어 사용 시 [DkswCore.resolveAssetUrl] 권장.
class HouseAd {
  final int id;
  final String imageUrl;
  final String? ctaUrl;
  final String ctaType;
  final HouseAdMode mode;
  final int weight;

  const HouseAd({
    required this.id,
    required this.imageUrl,
    this.ctaUrl,
    required this.ctaType,
    required this.mode,
    required this.weight,
  });

  factory HouseAd.fromJson(Map<String, dynamic> j) => HouseAd(
        id: (j['id'] as num).toInt(),
        imageUrl: j['imageUrl']?.toString() ?? '',
        ctaUrl: j['ctaUrl']?.toString(),
        ctaType: j['ctaType']?.toString() ?? 'none',
        mode: switch (j['mode']?.toString()) {
          'solo' => HouseAdMode.solo,
          'fallback' => HouseAdMode.fallback,
          _ => HouseAdMode.mix,
        },
        weight: (j['weight'] as num?)?.toInt() ?? 1,
      );
}

/// 콘솔에서 받은 house ad 캐시. 앱 시작 후 1회 fetch.
class HouseAdCache {
  HouseAdCache._();

  static HouseAd? _homeTop;
  static HouseAd? _homeList;
  static bool _fetched = false;

  static HouseAd? get homeTop => _homeTop;
  static HouseAd? get homeList => _homeList;
  static bool get fetched => _fetched;

  /// 콘솔 /api/house-ads 호출. 실패해도 조용히 무시 (광고 없음 상태).
  static Future<void> fetch({String? serverBaseUrl}) async {
    try {
      final base = serverBaseUrl ?? 'https://dksw4.com/console';
      final res = await Dio().get(
        '$base/api/house-ads',
        queryParameters: {'package': AppConstants.packageName},
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      final data = res.data;
      if (data is! Map || data['ok'] != true) return;
      final ads = data['ads'];
      if (ads is! Map) return;
      _homeTop = ads['home_top'] is Map
          ? HouseAd.fromJson(Map<String, dynamic>.from(ads['home_top']))
          : null;
      _homeList = ads['home_list'] is Map
          ? HouseAd.fromJson(Map<String, dynamic>.from(ads['home_list']))
          : null;
      _fetched = true;
    } catch (_) {
      // 광고 시스템 장애가 앱 사용에 영향 주면 안 됨.
      _fetched = true;
    }
  }

  /// house ad 를 서버에 노출 카운트 +1.
  static Future<void> reportImpression(int adId,
      {String? serverBaseUrl}) async {
    try {
      final base = serverBaseUrl ?? 'https://dksw4.com/console';
      await Dio()
          .post('$base/api/ads/$adId/impression')
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  /// house ad 를 서버에 클릭 카운트 +1.
  static Future<void> reportClick(int adId, {String? serverBaseUrl}) async {
    try {
      final base = serverBaseUrl ?? 'https://dksw4.com/console';
      await Dio()
          .post('$base/api/ads/$adId/click')
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}
