import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'auth_service.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/api_constants.dart';

// 서버(Node 등)에서 동일 검증 예시:
//   const d = haversineM(req.start_lat, req.start_lng, path_points[0].lat, path_points[0].lng);
//   logger.info({ tag: 'route/driving', request_start: [req.start_lat, req.start_lng],
//     first_path_point: path_points[0], distance_m: d, identical: d < 1 });

double _haversineM(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final p1 = lat1 * pi / 180;
  final p2 = lat2 * pi / 180;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(p1) * cos(p2) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * r * asin(min(1.0, sqrt(a)));
}

void _debugLogRouteStartVsFirstPolylinePoint({
  required double requestStartLat,
  required double requestStartLng,
  required Map<String, dynamic> routeJson,
  required String label,
}) {
  if (!kDebugMode) return;

  final lines = <String>[
    '[ROUTE_ORIGIN_CHECK] $label',
    '  request_start_lat_lng: $requestStartLat, $requestStartLng',
  ];

  final rawPts = routeJson['path_points'];
  if (rawPts is List && rawPts.isNotEmpty && rawPts.first is Map) {
    final p = rawPts.first as Map;
    final la = p['lat'];
    final ln = p['lng'];
    if (la is num && ln is num) {
      final flat = la.toDouble();
      final flng = ln.toDouble();
      final d = _haversineM(requestStartLat, requestStartLng, flat, flng);
      lines.add('  path_points[0]_lat_lng: $flat, $flng');
      lines.add('  distance_request_to_path_points[0]_m: ${d.toStringAsFixed(2)}');
      lines.add('  practically_same_coord: ${d < 1.0}');
    }
  } else {
    lines.add('  path_points: (없음 또는 비어 있음)');
  }

  final rawSegs = routeJson['path_segments'];
  if (rawSegs is List && rawSegs.isNotEmpty && rawSegs.first is Map) {
    final coords = (rawSegs.first as Map)['coords'];
    if (coords is List && coords.isNotEmpty && coords.first is Map) {
      final c = coords.first as Map;
      final la = c['lat'];
      final ln = c['lng'];
      if (la is num && ln is num) {
        final flat = la.toDouble();
        final flng = ln.toDouble();
        final d = _haversineM(requestStartLat, requestStartLng, flat, flng);
        lines.add('  path_segments[0].coords[0]_lat_lng: $flat, $flng');
        lines.add('  distance_request_to_segment0_first_m: ${d.toStringAsFixed(2)}');
      }
    }
  }

  debugPrint(lines.join('\n'));
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 40),
      headers: {'Content-Type': 'application/json'},
    ));

    // 응답 JSON parse 를 별도 isolate 에서 — Dio 기본 SyncTransformer 는 main
    // thread 에서 parse 라 500KB+ 응답 (EV/주유소 수백 건) 에서 50-200ms 차지 →
    // 줌/스크롤 jank 원인. BackgroundTransformer 가 compute() 으로 던져서 UI
    // thread 보존. 작은 응답엔 isolate 전환 비용(~5-10ms) 있지만 큰 응답에서
    // 이득이 훨씬 큼.
    _dio.transformer = BackgroundTransformer();

    // 응답 메모리 캐시 — 같은 URL+쿼리 + 짧은 시간내 (30초) 재요청 시 서버 안 가고
    // 즉시 반환. 지도 토글, 탭 전환 등에서 체감 즉시 응답.
    // policy.refresh = 캐시 만료된 경우만 fetch / cacheKeyBuilder = URL+쿼리 기반.
    _dio.interceptors.add(DioCacheInterceptor(
      options: CacheOptions(
        store: MemCacheStore(maxSize: 10 * 1024 * 1024, maxEntrySize: 2 * 1024 * 1024),
        policy: CachePolicy.request,
        maxStale: const Duration(seconds: 30),
        priority: CachePriority.normal,
        keyBuilder: CacheOptions.defaultCacheKeyBuilder,
        allowPostMethod: false, // POST (분석/추천) 은 캐시 X — 매번 fresh
      ),
    ));

    // 디버그에서만 request/response body 로그 — 릴리즈에서 위치/FCM 토큰/AI 응답 등
    // 민감 데이터가 logcat 으로 새지 않도록 차단.
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => debugPrint('[API] $obj'),
      ));
    }
  }

  // ─── 주유소 ───
  Future<List<Map<String, dynamic>>> getGasStationsAround({
    required double lat,
    required double lng,
    int radius = 5000,
    String fuelType = 'B027',
    int sort = 1,
  }) async {
    final res = await _dio.get(ApiConstants.gasAround, queryParameters: {
      'lat': lat, 'lng': lng, 'radius': radius,
      'fuelType': fuelType, 'sort': sort,
    });
    return List<Map<String, dynamic>>.from(res.data['data'] ?? []);
  }

  Future<Map<String, dynamic>> getGasStationDetail(String id, {String? fuelType}) async {
    final res = await _dio.get(
      '${ApiConstants.gasDetail}/$id',
      queryParameters: fuelType != null ? {'fuelType': fuelType} : null,
    );
    return Map<String, dynamic>.from(res.data['data'] ?? {});
  }

  /// 가격 추이 — period: '1w' | '4w' | '3m' | '1y'. 1y 는 서버에서 주 단위 down-sample.
  /// 응답: { period, fuels: [...], points: [{date: 'YYYYMMDD', prices: {B027:1700, ...}}], count }
  Future<Map<String, dynamic>> getGasPriceHistory(
    String id, {
    String period = '4w',
    List<String> fuels = const ['B027', 'D047', 'B034'],
  }) async {
    final res = await _dio.get(
      '${ApiConstants.gasDetail}/$id/price-history',
      queryParameters: {'period': period, 'fuels': fuels.join(',')},
    );
    return Map<String, dynamic>.from(res.data['data'] ?? {});
  }

  /// 전국 평균 + (위치 기반) 시도 평균 둘 다 응답.
  /// 반환 키: 'data' (레거시 = 전국), 'national', 'local' (시도 매핑 성공 시).
  Future<Map<String, dynamic>> getGasAvgPrice({double? lat, double? lng}) async {
    final res = await _dio.get(ApiConstants.gasAvgPrice, queryParameters: {
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return Map<String, dynamic>.from(res.data ?? {});
  }

  // ─── 충전소 ───
  Future<List<Map<String, dynamic>>> getEvStationsAround({
    required double lat,
    required double lng,
    int radius = 3000,
  }) async {
    final res = await _dio.get(ApiConstants.evAround, queryParameters: {
      'lat': lat, 'lng': lng, 'radius': radius,
    });
    return List<Map<String, dynamic>>.from(res.data['data'] ?? []);
  }

  Future<Map<String, dynamic>> getEvStationDetail(String statId) async {
    final res = await _dio.get('${ApiConstants.evDetail}/$statId');
    return Map<String, dynamic>.from(res.data['data'] ?? {});
  }

  // ─── 테슬라 (OCM) ───
  Future<List<Map<String, dynamic>>> getTeslaStationsAround({
    required double lat,
    required double lng,
    int radius = 5000,
  }) async {
    try {
      final res = await _dio.get(ApiConstants.teslaAround, queryParameters: {
        'lat': lat, 'lng': lng, 'radius': radius,
      });
      return List<Map<String, dynamic>>.from(res.data['data'] ?? []);
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> getTeslaStationDetail(String uuid) async {
    final res = await _dio.get('${ApiConstants.teslaDetail}/$uuid');
    return Map<String, dynamic>.from(res.data['data'] ?? {});
  }

  // ─── 장소 검색 ───
  Future<List<Map<String, dynamic>>> searchPlaces(String query, {double? lat, double? lng}) async {
    final params = <String, dynamic>{'query': query};
    if (lat != null && lng != null) {
      params['lat'] = lat;
      params['lng'] = lng;
    }
    final res = await _dio.get(ApiConstants.searchPlaces, queryParameters: params);
    return List<Map<String, dynamic>>.from(res.data['results'] ?? []);
  }

  // ─── AI 추천 ───
  Future<Map<String, dynamic>> getDrivingRoute({
    required double startLat,
    required double startLng,
    required double goalLat,
    required double goalLng,
    double? waypointLat,
    double? waypointLng,
  }) async {
    final res = await _dio.get(
      ApiConstants.routeDriving,
      queryParameters: {
        'start_lat': startLat,
        'start_lng': startLng,
        'goal_lat': goalLat,
        'goal_lng': goalLng,
        if (waypointLat != null) 'waypoint_lat': waypointLat,
        if (waypointLng != null) 'waypoint_lng': waypointLng,
      },
    );
    final out = Map<String, dynamic>.from(res.data ?? {});
    _debugLogRouteStartVsFirstPolylinePoint(
      requestStartLat: startLat,
      requestStartLng: startLng,
      routeJson: out,
      label: waypointLat != null ? 'GET /route/driving (경유)' : 'GET /route/driving',
    );
    return out;
  }

  /// 경로 대안: 추천(0) + 고속도로우선(4) 두 경로를 충전소/주유소·휴게소 개수와 함께.
  /// mode: 'ev'(충전) | 'fuel'(주유)
  Future<Map<String, dynamic>> getRouteAlternatives({
    required double startLat,
    required double startLng,
    required double goalLat,
    required double goalLng,
    String mode = 'ev',
  }) async {
    final res = await _dio.get(
      ApiConstants.routeAlternatives,
      queryParameters: {
        'start_lat': startLat,
        'start_lng': startLng,
        'goal_lat': goalLat,
        'goal_lng': goalLng,
        'mode': mode,
      },
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  // ─── 1:1 문의 ───
  Future<bool> createInquiry({
    required String appId,
    required String deviceId,
    required String title,
    required String content,
  }) async {
    final res = await _dio.post(ApiConstants.inquiries, data: {
      'app_id': appId,
      'device_id': deviceId,
      'title': title,
      'content': content,
    });
    return res.data?['success'] == true;
  }

  // ─── 주유소·충전소 정보 제보 ───
  Future<bool> submitReport({
    required String stationType, // 'gas' | 'ev'
    required String stationId,
    required String stationName,
    required String category,
    Map<String, dynamic>? detail,
    String? memo,
  }) async {
    final res = await _dio.post(ApiConstants.reports, data: {
      'app_id': AppConstants.packageName,
      'device_id': DkswCore.deviceId,
      'station_type': stationType,
      'station_id': stationId,
      'station_name': stationName,
      'category': category,
      if (detail != null) 'detail': detail,
      if (memo != null && memo.trim().isNotEmpty) 'memo': memo.trim(),
    });
    return res.data?['success'] == true;
  }

  Future<List<Map<String, dynamic>>> getMyInquiries({
    required String appId,
    required String deviceId,
  }) async {
    final res = await _dio.get(ApiConstants.inquiries, queryParameters: {
      'app_id': appId,
      'device_id': deviceId,
    });
    final list = res.data?['inquiries'];
    if (list is List) {
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> postEvAiRecommend(Map<String, dynamic> body) async {
    final res = await _dio.post(
      ApiConstants.evAiRecommend,
      data: body,
      options: await _aiAuthOptions(),
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  // AI 호출 공통 헤더 — 서버 쿼터 식별자.
  //   로그인: Bearer 토큰 → 사용자별(user_id) 쿼터
  //   게스트: x-device-id → 기기별 쿼터 (없으면 서버가 IP 폴백이라 NAT 공유돼 부정확)
  Future<Options?> _aiAuthOptions() async {
    final headers = <String, dynamic>{};
    if (DkswCore.deviceId.isNotEmpty) headers['x-device-id'] = DkswCore.deviceId;
    final token = await AuthService.accessToken();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers.isEmpty ? null : Options(headers: headers);
  }

  Future<Map<String, dynamic>> postRefuelAnalyze(Map<String, dynamic> body) async {
    final res = await _dio.post(ApiConstants.refuelAnalyze, data: body, options: await _aiAuthOptions());
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> postRefuelRouteStations(Map<String, dynamic> body) async {
    final res = await _dio.post(ApiConstants.refuelRouteStations, data: body, options: await _aiAuthOptions());
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> postRefuelCompare(Map<String, dynamic> body) async {
    final res = await _dio.post(ApiConstants.refuelCompare, data: body, options: await _aiAuthOptions());
    return Map<String, dynamic>.from(res.data ?? {});
  }

  // ─── EV 이용현황 카드 ───
  Future<Map<String, dynamic>?> getEvAnalytics(String statId) async {
    try {
      final res = await _dio.get('${ApiConstants.evAnalytics}/$statId');
      if (res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[API] getEvAnalytics 실패: $e');
      return null;
    }
  }

  // ─── 주변 POI (Tmap 프록시) ───
  Future<List<Map<String, dynamic>>> getNearbyPois({
    required double lat,
    required double lng,
    List<String>? categories,
    double radiusKm = 1,
    int count = 30,
    String sort = 'distance',
  }) async {
    try {
      final res = await _dio.get(
        ApiConstants.poiNearby,
        queryParameters: {
          'lat': lat, 'lng': lng,
          if (categories != null && categories.isNotEmpty) 'categories': categories.join(','),
          'radius': radiusKm,
          'count': count,
          'sort': sort,
        },
      );
      if (res.data is Map && res.data['success'] == true) {
        return List<Map<String, dynamic>>.from(res.data['items'] ?? []);
      }
      return [];
    } catch (e) {
      if (kDebugMode) debugPrint('[API] getNearbyPois 실패: $e');
      return [];
    }
  }

  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final res = await _dio.get(
        ApiConstants.reverseGeocode,
        queryParameters: {'lat': lat, 'lng': lng},
      );
      if (res.data['success'] == true) return res.data['address'] as String?;
      return null;
    } catch (_) {
      return null;
    }
  }

}
