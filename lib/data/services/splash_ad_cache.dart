import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/painting.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 스플래시 광고 디스크 캐시 — stale-while-revalidate.
///
/// - 매 실행 시 캐시된 광고를 즉시 노출 → 흰 화면 갭 없이 0.5초 native splash
///   직후 광고가 보임.
/// - 동시에 서버 bootstrap 으로 새 광고를 가져와 캐시 갱신 → 다음 실행부터 반영.
/// - 캐시 max age 7일: 그보다 오래된 캐시는 폐기하고 광고 스킵.
///
/// 콘솔에서 광고를 새로 올리면 다음 실행 한 번은 옛 캐시(또는 무광고)가 보이고
/// 그 다음 실행부터 새 광고가 노출된다 (1 실행 지연).
class SplashAdCache {
  static const _box = 'settings';
  static const _kAdJson = 'splash_ad_cache_json';
  static const _kAdImage = 'splash_ad_cache_image';
  static const _kAdSavedAt = 'splash_ad_cache_saved_at';
  static const _maxAgeMs = 7 * 24 * 60 * 60 * 1000; // 7일

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

  /// 광고 이미지 바이트를 Flutter image cache 에 NetworkImage(resolvedUrl) 키로
  /// 미리 꽂아둔다. 이후 `Image.network(resolvedUrl)` 은 디스크 다운로드 없이
  /// 즉시 첫 프레임을 그린다.
  static Future<bool> installInImageCache(String url, Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final completer = OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: frame.image, scale: 1.0)),
      );
      // NetworkImage 는 == / hashCode 를 url 로 정의하므로 같은 url 의
      // Image.network() 가 같은 캐시 키로 매핑된다.
      PaintingBinding.instance.imageCache.putIfAbsent(
        NetworkImage(url),
        () => completer,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 서버 응답 광고를 캐시에 저장. 이미지가 큰 경우 다운로드 실패하면
  /// 메타도 저장하지 않는다 (다음 실행에 어중간한 상태가 되지 않도록).
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
