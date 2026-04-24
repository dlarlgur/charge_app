import 'package:geolocator/geolocator.dart';

class LocationService {
  static final LocationService _instance = LocationService._();
  factory LocationService() => _instance;
  LocationService._();

  Position? _lastPosition;
  Position? get lastPosition => _lastPosition;

  /// 실시간 위치 스트림 (앱 전체에서 공유)
  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 30, // 30m 이상 이동 시에만 업데이트
      ),
    ).map((pos) {
      _lastPosition = pos;
      return pos;
    });
  }

  Future<bool> checkPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse || permission == LocationPermission.always;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) return null;

      // 캐시된 위치 즉시 반환
      if (_lastPosition != null) return _lastPosition;

      // OS 캐시 위치 즉시 시도 (수십ms)
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _lastPosition = lastKnown;
        // 백그라운드에서 갱신
        Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 5),
        ).then((pos) {
          _lastPosition = pos;
        }).catchError((_) {});
        return _lastPosition;
      }

      // 첫 실행 — GPS 초기화에 시간이 걸릴 수 있으므로 15초 대기
      _lastPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );
      return _lastPosition;
    } catch (e) {
      print('[Location] Error: $e');
      return _lastPosition;
    }
  }

  /// 캐시 무시하고 GPS에서 현재 위치를 새로 가져옴 (위치 버튼 전용)
  Future<Position?> getFreshPosition() async {
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) return null;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      _lastPosition = pos;
      return pos;
    } catch (e) {
      return _lastPosition;
    }
  }
}
