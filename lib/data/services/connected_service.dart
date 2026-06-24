import 'package:dio/dio.dart';

import '../../core/constants/api_constants.dart';
import 'auth_service.dart';

/// 커넥티드(현기/제네시스) 차량 — charge_server 중개 API 호출.
class ConnectedCar {
  final String carId;
  final String name;
  final String carType; // GN/EV/HEV/PHEV/FCEV
  final bool isEv;
  ConnectedCar({required this.carId, required this.name, required this.carType, required this.isEv});
}

class ConnectedStatus {
  final int? dteKm;     // 주행가능거리
  final double? soc;    // EV 배터리 %
  final bool? charging; // EV 충전중
  ConnectedStatus({this.dteKm, this.soc, this.charging});
  bool get isEmpty => dteKm == null && soc == null;
}

class ConnectedService {
  ConnectedService._();

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20), // 차에 핑 → 느릴 수 있음
  ));

  static Future<Options> _auth() async {
    final token = await AuthService.accessToken();
    return Options(headers: token != null ? {'Authorization': 'Bearer $token'} : null);
  }

  /// 로그인(OAuth) URL 받기 — Custom Tab 으로 열면 됨.
  static Future<String?> getAuthorizeUrl(String brand) async {
    final res = await _dio.get('/connected/$brand/authorize', options: await _auth());
    final url = res.data is Map ? res.data['authorizeUrl'] : null;
    return url is String ? url : null;
  }

  /// 연동·동의 완료된 차량 리스트.
  static Future<List<ConnectedCar>> vehicles(String brand) async {
    final res = await _dio.get('/connected/vehicles',
        queryParameters: {'brand': brand}, options: await _auth());
    final list = (res.data is Map ? res.data['cars'] : null) as List? ?? [];
    return list
        .whereType<Map>()
        .map((c) => ConnectedCar(
              carId: '${c['carId'] ?? ''}',
              name: '${c['name'] ?? '차량'}',
              carType: '${c['carType'] ?? ''}',
              isEv: c['isEv'] == true,
            ))
        .where((c) => c.carId.isNotEmpty)
        .toList();
  }

  /// 차량 현재 상태 (DTE / EV 배터리·충전).
  static Future<ConnectedStatus> status({
    required String brand,
    required String carId,
    required bool isEv,
  }) async {
    final res = await _dio.get('/connected/status',
        queryParameters: {'brand': brand, 'carId': carId, 'type': isEv ? 'ev' : 'gas'},
        options: await _auth());
    final d = res.data is Map ? res.data as Map : const {};
    return ConnectedStatus(
      dteKm: (d['dteKm'] as num?)?.toInt(),
      soc: (d['soc'] as num?)?.toDouble(),
      charging: d['charging'] as bool?,
    );
  }

  /// 연동 해제 — 서버 토큰 삭제 + CCAPI 철회.
  static Future<void> unlink(String brand) async {
    await _dio.post('/connected/$brand/unlink', options: await _auth());
  }

  /// Dio 에러에서 서버가 준 친화 메시지 추출.
  static String errorMessage(Object e, String fallback) {
    if (e is DioException && e.response?.data is Map) {
      final m = (e.response!.data as Map)['message'];
      if (m is String && m.isNotEmpty) return m;
    }
    return fallback;
  }
}
