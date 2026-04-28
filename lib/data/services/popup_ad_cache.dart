import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/painting.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 홈 팝업 광고 디스크 캐시 — stale-while-revalidate.
///
/// 같은 패턴을 [SplashAdCache] / [HouseAdCache] 가 쓰고 있고, 이 클래스는
/// placement = 'popup' 광고용 사본이다.
///
/// 동작:
///  - 홈 진입 시 캐시된 광고를 즉시 노출 → 네트워크 fetch 대기 없음 (광고 0ms)
///  - 동시에 서버 /api/popup 로 새 광고 fetch → 디스크 갱신 → 다음 진입 반영
///  - 캐시 max age 7일.
///  - 콘솔에서 광고 비활성화/삭제 시 다음 fetch 가 null 을 받아 [clear] 호출.
///    한 번의 노출 지연(이미 캐시된 옛 광고 한 번 더 보임) 은 의도된 트레이드오프.
class PopupAdCache {
  static const _box = 'settings';
  static const _kAdJson = 'popup_ad_cache_json';
  static const _kAdImage = 'popup_ad_cache_image';
  static const _kAdSavedAt = 'popup_ad_cache_saved_at';
  static const _maxAgeMs = 7 * 24 * 60 * 60 * 1000;

  /// 디스크에 저장된 광고가 유효하면 (SplashAd, bytes) 를 반환.
  /// max age 초과·이미지 누락 등은 모두 null.
  static (SplashAd, Uint8List)? read() {
    try {
      final box = Hive.box(_box);
      final savedAt = box.get(_kAdSavedAt) as int?;
      if (savedAt == null) return null;
      if (DateTime.now().millisecondsSinceEpoch - savedAt > _maxAgeMs) return null;

      final json = box.get(_kAdJson);
      final bytes = box.get(_kAdImage);
      if (json is! Map || bytes is! Uint8List || bytes.isEmpty) return null;

      final ad = SplashAd.fromJson(Map<String, dynamic>.from(json));
      if (ad.imageUrl.isEmpty) return null;
      return (ad, bytes);
    } catch (_) {
      return null;
    }
  }

  /// 광고 이미지 바이트를 Flutter image cache 에 NetworkImage(url) 키로 미리 꽂음.
  /// 이후 `Image.network(url)` 은 디스크 다운로드 없이 즉시 첫 프레임을 그린다.
  static Future<bool> installInImageCache(String url, Uint8List bytes) async {
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
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 서버 응답 광고를 캐시에 저장. 이미지 다운로드 실패 시 메타도 저장하지 않음
  /// (다음 실행에 어중간한 상태가 되지 않도록).
  static Future<void> save(SplashAd ad) async {
    try {
      final url = DkswCore.resolveAssetUrl(ad.imageUrl);
      final res = await Dio().get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final body = res.data;
      if (res.statusCode != 200 || body == null || body.isEmpty) return;
      final bytes = Uint8List.fromList(body);

      final box = Hive.box(_box);
      await box.put(_kAdJson, ad.toJson());
      await box.put(_kAdImage, bytes);
      await box.put(_kAdSavedAt, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // 캐시 갱신 실패해도 앱 동작에는 영향 없음.
    }
  }

  /// 서버에 광고가 없거나 비활성화된 경우 호출 — 캐시 비움.
  static Future<void> clear() async {
    try {
      final box = Hive.box(_box);
      await box.delete(_kAdJson);
      await box.delete(_kAdImage);
      await box.delete(_kAdSavedAt);
    } catch (_) {}
  }

  /// 캐시된 광고와 새 광고가 동일한지 — id 기준.
  static bool isSameAsCached(SplashAd fresh) {
    try {
      final cached = Hive.box(_box).get(_kAdJson);
      if (cached is! Map) return false;
      final cachedId = (cached['id'] as num?)?.toInt();
      return cachedId == fresh.id;
    } catch (_) {
      return false;
    }
  }
}
