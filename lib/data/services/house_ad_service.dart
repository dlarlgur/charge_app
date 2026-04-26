import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/painting.dart';
import 'package:hive_flutter/hive_flutter.dart';
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'listPosition': listPosition,
        'bypassAdmob': bypassAdmob,
        'imageUrl': imageUrl,
        'ctaUrl': ctaUrl,
        'ctaType': ctaType,
        'weight': weight,
      };
}

/// 콘솔에서 받은 house ad 캐시. 앱 시작 후 1회 fetch + 이미지 디스크 캐시.
///
/// stale-while-revalidate 패턴:
///  - 시작 시 Hive 디스크 캐시에서 메타+이미지 로드 → 즉시 사용 가능 (광고 깜빡임 0)
///  - 동시에 서버 fetch + 이미지 다운로드해 디스크 갱신
///  - 다음 실행/메타 새로고침 시 새 광고 적용
///
/// 노출 규칙:
///  - 슬롯 4·8 = 기본 AdMob. 같은 위치에 bypass=true house ad 가 있으면 대체.
///  - 슬롯 12+ = 등록된 house ad 항상 노출 (AdMob 자리 아님).
class HouseAdCache {
  HouseAdCache._();

  static const _box = 'settings';
  static const _kAdsJson = 'house_ads_meta';
  static const _kImagePrefix = 'house_ads_img_'; // + ad.id
  static const _maxAgeMs = 7 * 24 * 60 * 60 * 1000;

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

  /// 디스크에 저장된 이전 광고 + 이미지 즉시 로드.
  /// 첫 프레임에 광고가 보이게 — 네트워크 fetch 기다리지 않음.
  static void readFromDiskAndInstall() {
    try {
      final box = Hive.box(_box);
      final savedAt = box.get('${_kAdsJson}_savedAt') as int?;
      if (savedAt == null) return;
      if (DateTime.now().millisecondsSinceEpoch - savedAt > _maxAgeMs) return;

      final raw = box.get(_kAdsJson);
      if (raw is! List) return;
      _ads = raw
          .whereType<Map>()
          .map((m) => HouseAd.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      _fetched = true;

      // 이미지 바이트를 Flutter image cache 에 NetworkImage(url) 키로 미리 꽂음.
      for (final ad in _ads) {
        final bytes = box.get('$_kImagePrefix${ad.id}');
        if (bytes is Uint8List && bytes.isNotEmpty) {
          _installInImageCache(DkswCore.resolveAssetUrl(ad.imageUrl), bytes);
        }
      }
    } catch (_) {}
  }

  /// 디스크에서 읽은 광고를 Flutter image cache 에 등록 → Image.network(url) 즉시 그림.
  static Future<void> _installInImageCache(String url, Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final completer = OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: frame.image, scale: 1.0)),
      );
      PaintingBinding.instance.imageCache.putIfAbsent(
        NetworkImage(url),
        () => completer,
      );
    } catch (_) {}
  }

  /// 콘솔 /api/house-ads 호출 + 이미지 다운로드 + 디스크 저장.
  /// 실패해도 조용히 무시 (광고 없음 상태).
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
      final fresh = adsRaw
          .whereType<Map>()
          .map((m) => HouseAd.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      _ads = fresh;
      _fetched = true;

      // 이미지 다운로드 + Hive 저장 + image cache 등록
      final box = Hive.box(_box);
      final dio = Dio();
      final keepIds = <int>{};
      for (final ad in fresh) {
        keepIds.add(ad.id);
        final url = DkswCore.resolveAssetUrl(ad.imageUrl);
        try {
          final r = await dio.get<List<int>>(
            url,
            options: Options(
              responseType: ResponseType.bytes,
              receiveTimeout: const Duration(seconds: 10),
            ),
          );
          final body = r.data;
          if (r.statusCode == 200 && body != null && body.isNotEmpty) {
            final bytes = Uint8List.fromList(body);
            await box.put('$_kImagePrefix${ad.id}', bytes);
            await _installInImageCache(url, bytes);
          }
        } catch (_) {}
      }
      // 더 이상 등록 안 된 광고 이미지는 정리
      for (final key in box.keys.where((k) => k is String && k.startsWith(_kImagePrefix)).toList()) {
        final id = int.tryParse((key as String).substring(_kImagePrefix.length));
        if (id != null && !keepIds.contains(id)) {
          await box.delete(key);
        }
      }
      await box.put(_kAdsJson, fresh.map((a) => a.toJson()).toList());
      await box.put('${_kAdsJson}_savedAt', DateTime.now().millisecondsSinceEpoch);
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
