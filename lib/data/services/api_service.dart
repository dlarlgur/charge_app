import 'dart:math';

import 'package:dio/dio.dart';
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

    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => print('[API] $obj'),
    ));
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

  Future<Map<String, dynamic>> getGasStationDetail(String id) async {
    final res = await _dio.get('${ApiConstants.gasDetail}/$id');
    return Map<String, dynamic>.from(res.data['data'] ?? {});
  }

  Future<Map<String, dynamic>> getGasAvgPrice() async {
    final res = await _dio.get(ApiConstants.gasAvgPrice);
    return Map<String, dynamic>.from(res.data['data'] ?? {});
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

  Future<Map<String, dynamic>> postRefuelAnalyze(Map<String, dynamic> body) async {
    final res = await _dio.post(ApiConstants.refuelAnalyze, data: body);
    return Map<String, dynamic>.from(res.data ?? {});
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
