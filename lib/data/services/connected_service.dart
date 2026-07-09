import 'package:dio/dio.dart';

import '../../core/constants/api_constants.dart';
import 'auth_service.dart';

/// 커넥티드(현기/제네시스) 차량 — charge_server 중개 API 호출.
class ConnectedCar {
  final String carId;
  final String name;
  final String carType; // GN/EV/HEV/PHEV/FCEV
  final bool isEv;

  // 서버가 판매명으로 에너지공단 제원 DB 매칭해 내려주는 프리필값 (실패 시 전부 null).
  // 탱크 용량은 AI 추정값 — 채울 때 '확인·수정' 안내 필수.
  final String? specFuelType;      // 앱 유종코드 (EV 는 null)
  final double? specEfficiency;    // km/L 또는 km/kWh
  final double? specTankCapacity;  // L (AI 추정)
  final double? specBatteryCapacity; // kWh

  ConnectedCar({
    required this.carId,
    required this.name,
    required this.carType,
    required this.isEv,
    this.specFuelType,
    this.specEfficiency,
    this.specTankCapacity,
    this.specBatteryCapacity,
  });
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

  /// 제3자제공 '동의' URL 받기 — 5005(미동의) 복구용. Custom Tab 으로 열면 됨.
  static Future<String?> getAgreeUrl(String brand) async {
    final res = await _dio.get('/connected/$brand/agree-url', options: await _auth());
    final url = res.data is Map ? res.data['agreeUrl'] : null;
    return url is String ? url : null;
  }

  /// 연동·동의 완료된 차량 리스트.
  static Future<List<ConnectedCar>> vehicles(String brand) async {
    final res = await _dio.get('/connected/vehicles',
        queryParameters: {'brand': brand}, options: await _auth());
    final list = (res.data is Map ? res.data['cars'] : null) as List? ?? [];
    return list.whereType<Map>().map((c) {
      final spec = c['spec'] is Map ? c['spec'] as Map : null;
      double? num_(dynamic v) => v is num && v > 0 ? v.toDouble() : null;
      return ConnectedCar(
        carId: '${c['carId'] ?? ''}',
        name: '${c['name'] ?? '차량'}',
        carType: '${c['carType'] ?? ''}',
        isEv: c['isEv'] == true,
        specFuelType: spec?['fuelType'] is String ? spec!['fuelType'] as String : null,
        specEfficiency: num_(spec?['efficiency']),
        specTankCapacity: num_(spec?['tankCapacity']),
        specBatteryCapacity: num_(spec?['batteryCapacity']),
      );
    }).where((c) => c.carId.isNotEmpty).toList();
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

  /// CCAPI errCode 추출 (예: '5005'=제3자 미동의). 없으면 null.
  static String? errorCode(Object e) {
    if (e is DioException && e.response?.data is Map) {
      final c = (e.response!.data as Map)['errCode'];
      if (c != null) return '$c';
    }
    return null;
  }
}
