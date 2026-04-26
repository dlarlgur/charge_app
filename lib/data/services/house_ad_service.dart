import 'package:dio/dio.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import '../../core/constants/api_constants.dart';

/// 콘솔에서 등록한 직접(house) 광고.
/// imageUrl 은 상대 경로일 수 있어 사용 시 [DkswCore.resolveAssetUrl] 권장.
class HouseAd {
  final int id;
  final int listPosition;
  final bool bypassAdmob;
  final String imageUrl;
  final String? ctaUrl;
  final String ctaType;
  final int weight;

  const HouseAd({
    required this.id,
    required this.listPosition,
    required this.bypassAdmob,
    required this.imageUrl,
    this.ctaUrl,
    required this.ctaType,
    required this.weight,
  });

  factory HouseAd.fromJson(Map<String, dynamic> j) => HouseAd(
        id: (j['id'] as num).toInt(),
        listPosition: (j['listPosition'] as num?)?.toInt() ?? 0,
        bypassAdmob: j['bypassAdmob'] == true,
        imageUrl: j['imageUrl']?.toString() ?? '',
        ctaUrl: j['ctaUrl']?.toString(),
        ctaType: j['ctaType']?.toString() ?? 'none',
        weight: (j['weight'] as num?)?.toInt() ?? 1,
      );
}

/// 콘솔에서 받은 house ad 캐시. 앱 시작 후 1회 fetch.
///
/// 노출 규칙:
///  - 슬롯 4·8 = 기본 AdMob. 같은 위치에 bypass=true house ad 가 있으면 대체.
///  - 슬롯 12+ = 등록된 house ad 항상 노출 (AdMob 자리 아님).
class HouseAdCache {
  HouseAdCache._();

  static List<HouseAd> _ads = const [];
  static bool _fetched = false;

  static List<HouseAd> get ads => _ads;
  static bool get fetched => _fetched;

  /// 위치별 house ad lookup. 같은 위치에 여러 개면 서버에서 1건만 픽해서 내려줌.
  static HouseAd? at(int position) {
    for (final a in _ads) {
      if (a.listPosition == position) return a;
    }
    return null;
  }

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
      final adsRaw = data['ads'];
      if (adsRaw is! List) return;
      _ads = adsRaw
          .whereType<Map>()
          .map((m) => HouseAd.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      _fetched = true;
    } catch (_) {
      _fetched = true;
    }
  }

  static Future<void> reportImpression(int adId,
      {String? serverBaseUrl}) async {
    try {
      final base = serverBaseUrl ?? 'https://dksw4.com/console';
      await Dio()
          .post('$base/api/ads/$adId/impression')
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  static Future<void> reportClick(int adId, {String? serverBaseUrl}) async {
    try {
      final base = serverBaseUrl ?? 'https://dksw4.com/console';
      await Dio()
          .post('$base/api/ads/$adId/click')
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}

/// 리스트 슬롯 결정 — 앱이 호출.
///
/// AdMob 기본 슬롯: 4, 8.
/// 같은 위치 house ad 가 있고 bypass_admob=true 면 house 가 대체.
/// 슬롯 12+ 는 house ad 만.
class AdSlotResolver {
  AdSlotResolver._();

  static const Set<int> admobSlots = {4, 8};

  /// 슬롯이 광고 위치인지 (AdMob 또는 house ad).
  /// 광고 자체가 없으면 false 라서 일반 station 으로 채워짐.
  static bool isAdSlot(int position) {
    if (admobSlots.contains(position)) {
      // AdMob 자리: house ad 가 bypass=false 면 AdMob 노출. 어쨌든 슬롯.
      return true;
    }
    // 비-AdMob 자리: house ad 등록되어 있을 때만 슬롯.
    return HouseAdCache.at(position) != null;
  }

  /// 슬롯의 광고 종류 반환. null = 광고 없음(station 자리).
  /// 'admob' / 'house'
  static SlotKind kindAt(int position) {
    final house = HouseAdCache.at(position);
    if (admobSlots.contains(position)) {
      // AdMob 슬롯 — house+bypass 면 대체, 아니면 AdMob.
      if (house != null && house.bypassAdmob) return SlotKind.house;
      return SlotKind.admob;
    }
    // 비-AdMob 슬롯 — house ad 있으면 노출, 없으면 station.
    if (house != null) return SlotKind.house;
    return SlotKind.none;
  }

  /// 화면에 등장할 가장 먼 광고 슬롯 (스크롤 끝까지 그릴 필요 X 한정용).
  static int get maxAdSlot {
    int m = 8; // AdMob 기본 두 자리
    for (final a in HouseAdCache.ads) {
      if (a.listPosition > m) m = a.listPosition;
    }
    return m;
  }
}

enum SlotKind { admob, house, none }
