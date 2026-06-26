import 'package:dio/dio.dart';
import '../../core/constants/api_constants.dart';

/// 지도 런타임 설정 — 서버 원격설정으로 빌드 없이 조정.
/// startup 에 한 번 fetch 해서 static 에 담아둠. 지도는 build 때 이 값을 읽음.
class MapRuntimeConfig {
  MapRuntimeConfig._();

  /// 클러스터: 이 줌 이하에서만 마커를 동그라미로 묶음(그 위는 개별). 기본 11.
  /// 콘솔 원격설정 key: map.cluster.zoom_max (number).
  static int clusterZoomMax = 11;

  static Future<void> fetch() async {
    try {
      final res = await Dio().get(
        '${ApiConstants.baseUrl}/app-config',
        options: Options(
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );
      final data = res.data;
      final v = data is Map ? data['clusterZoomMax'] : null;
      final n = (v is num) ? v.toInt() : int.tryParse('$v');
      if (n != null && n >= 0 && n <= 21) clusterZoomMax = n;
    } catch (_) {
      // 실패 시 기본값(11) 유지 — 지도 동작에 영향 없음.
    }
  }
}
