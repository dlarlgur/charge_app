import 'package:dio/dio.dart';
import '../../core/constants/api_constants.dart';

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
  }) async {
    final res = await _dio.get(
      ApiConstants.routeDriving,
      queryParameters: {
        'start_lat': startLat,
        'start_lng': startLng,
        'goal_lat': goalLat,
        'goal_lng': goalLng,
      },
    );
    return Map<String, dynamic>.from(res.data ?? {});
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
