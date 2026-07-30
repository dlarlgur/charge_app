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
  /// 카피 A/B 변형 id — 노출·클릭 로깅 시 되돌려준다 (없으면 서버가 추정)
  final int? variantId;
  final String displayStyle; // 'card' | 'banner'
  final String imageUrl;
  final String? headline;
  final String? bodyText;
  final String? ctaLabel;
  final String? ctaUrl;
  final String ctaType;

  const FallbackAd({
    required this.id,
    this.variantId,
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
        variantId: (j['variantId'] as num?)?.toInt(),
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
  static const _placements = [
    'home_top', 'station_detail', 'login_bottom', 'login_social',
  ];

  static final Map<String, FallbackAd?> _cache = {};

  /// placement 폴백 광고 (없으면 null). fetch 전이면 null.
  static FallbackAd? at(String placement) => _cache[placement];

  /// fetch 보장 버전 — 캐시에 없으면 그 자리에서 1회 fetch (로그인 화면처럼
  /// 부팅 프리페치보다 먼저 뜰 수 있는 화면용).
  static Future<FallbackAd?> ensure(String placement) async {
    if (_cache.containsKey(placement)) return _cache[placement];
    final dio = Dio()..transformer = BackgroundTransformer();
    await _fetchOne(dio, placement);
    return _cache[placement];
  }

  /// 부팅 시 1회 — 모든 폴백 슬롯 병렬 fetch. 실패는 무시(폴백 없음 취급).
  static Future<void> fetchAll() async {
    final dio = Dio()..transformer = BackgroundTransformer();
    await Future.wait(_placements.map((pl) => _fetchOne(dio, pl)));
  }

  // ── 캐러셀(로그인 지면) — 활성 광고 '목록' 캐시 ──
  static final Map<String, List<FallbackAd>> _listCache = {};

  /// 로그인 지면 캐러셀용 목록 fetch (carousel=1 — 서버 노출카운트 스킵,
  /// 노출은 위젯이 장당 1회 보고). 실패/빈 목록 = [].
  static Future<List<FallbackAd>> ensureList(String placement) async {
    if (_listCache.containsKey(placement)) return _listCache[placement]!;
    try {
      final dio = Dio()..transformer = BackgroundTransformer();
      final res = await dio.get(
        '$_consoleBase/api/ad-fallback',
        queryParameters: {
          'package': 'com.dksw.charge',
          'placement': placement,
          'device_id': DkswCore.deviceId,
          'carousel': '1',
        },
        options: Options(receiveTimeout: const Duration(seconds: 6)),
      );
      final raw = res.data is Map ? res.data['ads'] : null;
      final list = raw is List
          ? raw
              .whereType<Map>()
              .map((m) => FallbackAd.fromJson(Map<String, dynamic>.from(m)))
              .where((a) => a.imageUrl.isNotEmpty || a.isStructured)
              .toList()
          : <FallbackAd>[];
      _listCache[placement] = list;
      return list;
    } catch (e) {
      if (kDebugMode) debugPrint('[ad-fallback] $placement 목록 실패: $e');
      _listCache[placement] = const [];
      return const [];
    }
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
