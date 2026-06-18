import 'package:dio/dio.dart';

import '../../core/constants/api_constants.dart';
import 'auth_service.dart';

/// charge_server `/api/user/*` 클라이언트 — 로그인 회원 데이터 동기화.
/// 모든 호출은 Bearer 토큰 필요. 비로그인이면 조용히 skip(false/null 반환).
/// JSON parse 는 BackgroundTransformer 로 isolate 분리(메인스레드 jank 방지).
class UserSyncService {
  UserSyncService._();
  static final UserSyncService instance = UserSyncService._();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ))..transformer = BackgroundTransformer();

  Future<Options?> _auth() async {
    final token = await AuthService.accessToken();
    if (token == null || token.isEmpty) return null; // 비로그인 → skip
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// 전체 스냅샷 pull. 비로그인/실패 시 null.
  Future<Map<String, dynamic>?> sync() async {
    final opt = await _auth();
    if (opt == null) return null;
    try {
      final res = await _dio.get('/user/sync', options: opt);
      final data = res.data;
      if (data is Map && data['ok'] == true) return Map<String, dynamic>.from(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> putPrefs({String? vehicleType, String? fuelType, bool? marketingConsent}) async {
    final opt = await _auth();
    if (opt == null) return;
    final body = <String, dynamic>{};
    if (vehicleType != null) body['vehicleType'] = vehicleType;
    if (fuelType != null) body['fuelType'] = fuelType;
    if (marketingConsent != null) body['marketingConsent'] = marketingConsent;
    if (body.isEmpty) return;
    try {
      await _dio.put('/user/prefs', data: body, options: opt);
    } catch (_) {}
  }

  /// AI 차량 프로필 전체 교체(replace-all).
  Future<void> putVehicles(List<Map<String, dynamic>> vehicles) async {
    final opt = await _auth();
    if (opt == null) return;
    try {
      await _dio.put('/user/vehicles', data: {'vehicles': vehicles}, options: opt);
    } catch (_) {}
  }

  Future<void> addFavorite(Map<String, dynamic> fav) async {
    final opt = await _auth();
    if (opt == null) return;
    try {
      await _dio.post('/user/favorites', data: fav, options: opt);
    } catch (_) {}
  }

  Future<void> removeFavorite(String type, String stationId) async {
    final opt = await _auth();
    if (opt == null) return;
    try {
      await _dio.delete('/user/favorites/$type/$stationId', options: opt);
    } catch (_) {}
  }

  Future<void> addAlarm(Map<String, dynamic> alarm) async {
    final opt = await _auth();
    if (opt == null) return;
    try {
      await _dio.post('/user/alarms', data: alarm, options: opt);
    } catch (_) {}
  }

  Future<void> removeAlarm(String type, String stationId) async {
    final opt = await _auth();
    if (opt == null) return;
    try {
      await _dio.delete('/user/alarms/$type/$stationId', options: opt);
    } catch (_) {}
  }

  /// 게스트→회원 이관: 로컬 스냅샷 일괄 전송.
  Future<bool> import(Map<String, dynamic> snapshot) async {
    final opt = await _auth();
    if (opt == null) return false;
    try {
      final res = await _dio.post('/user/import', data: snapshot, options: opt);
      return res.data is Map && res.data['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
