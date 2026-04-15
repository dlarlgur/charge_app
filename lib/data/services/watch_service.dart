import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/api_constants.dart';
import 'alert_service.dart';

/// 일회성 워치 세션 모델
class WatchSession {
  final String statId;
  final String stationName;
  final int etaMin;
  final DateTime expiresAt;
  final int? currentAvail;

  WatchSession({
    required this.statId,
    required this.stationName,
    required this.etaMin,
    required this.expiresAt,
    this.currentAvail,
  });

  bool get isActive => DateTime.now().isBefore(expiresAt);

  Duration get remaining => expiresAt.difference(DateTime.now());

  Map<String, dynamic> toMap() => {
        'statId': statId,
        'stationName': stationName,
        'etaMin': etaMin,
        'expiresAt': expiresAt.toIso8601String(),
        'currentAvail': currentAvail,
      };

  factory WatchSession.fromMap(Map<String, dynamic> m) => WatchSession(
        statId: m['statId'] as String,
        stationName: m['stationName'] as String,
        etaMin: (m['etaMin'] as num).toInt(),
        expiresAt: DateTime.parse(m['expiresAt'] as String),
        currentAvail: (m['currentAvail'] as num?)?.toInt(),
      );
}

class WatchService {
  static final WatchService _instance = WatchService._();
  factory WatchService() => _instance;
  WatchService._();

  static const _boxKey = 'settings';
  static const _hiveKey = 'ev_watch_session';

  final _dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  // 현재 세션 (메모리)
  WatchSession? _session;
  WatchSession? get session => (_session?.isActive == true) ? _session : null;

  // UI 갱신 알림용
  final sessionChanged = ValueNotifier<int>(0);
  void _notify() => sessionChanged.value++;

  /// 앱 시작 시 로컬 캐시 + 서버 복원
  Future<void> restore() async {
    // 1. Hive 로컬 우선
    try {
      final box = Hive.box(_boxKey);
      final raw = box.get(_hiveKey);
      if (raw is Map) {
        final s = WatchSession.fromMap(Map<String, dynamic>.from(raw));
        if (s.isActive) {
          _session = s;
          _notify();
          return;
        }
      }
    } catch (_) {}

    // 2. 서버에서 활성 세션 조회
    try {
      final res = await _dio.get('/stations/ev/watch/active',
          queryParameters: {'deviceId': AlertService().deviceId});
      final sessions = (res.data['sessions'] as List?) ?? [];
      if (sessions.isNotEmpty) {
        final s = WatchSession.fromMap(Map<String, dynamic>.from(sessions.first));
        if (s.isActive) {
          _session = s;
          _saveLocal();
          _notify();
        }
      }
    } catch (_) {}
  }

  /// 현재 충전소 자리 수를 서버에서 실시간으로 조회해 업데이트
  Future<void> refreshAvail() async {
    final s = _session;
    if (s == null || !s.isActive) return;
    try {
      final res = await _dio.get('/stations/ev/${s.statId}');
      final data = res.data['data'];
      if (data is Map) {
        final chargers = (data['chargers'] as List?) ?? [];
        final avail = chargers.where((c) => (c as Map)['stat'] == 2).length;
        if (avail != s.currentAvail) updateCurrentAvail(s.statId, avail);
      }
    } catch (_) {}
  }

  /// 워치 시작
  Future<bool> start({
    required String statId,
    required String stationName,
    required int etaMin,
    int? currentAvail,
  }) async {
    try {
      final res = await _dio.post('/stations/ev/watch/start', data: {
        'deviceId': AlertService().deviceId,
        'statId': statId,
        'stationName': stationName,
        'etaMin': etaMin,
        'currentAvail': currentAvail,
      });
      final expiresAt = DateTime.parse(res.data['expiresAt'] as String);
      _session = WatchSession(
        statId: statId,
        stationName: stationName,
        etaMin: etaMin,
        expiresAt: expiresAt,
        currentAvail: currentAvail,
      );
      _saveLocal();
      _notify();
      return true;
    } catch (e) {
      debugPrint('[WATCH] start 실패: $e');
      return false;
    }
  }

  /// 워치 종료
  Future<void> stop() async {
    final s = _session;
    _session = null;
    _clearLocal();
    _notify();
    if (s == null) return;
    try {
      await _dio.delete('/stations/ev/watch/stop', data: {
        'deviceId': AlertService().deviceId,
        'statId': s.statId,
      });
    } catch (_) {}
  }

  /// 워치 30분 연장
  Future<bool> extend() async {
    final s = _session;
    if (s == null) return false;
    try {
      final res = await _dio.post('/stations/ev/watch/extend', data: {
        'deviceId': AlertService().deviceId,
        'statId': s.statId,
      });
      final expiresAt = DateTime.parse(res.data['expiresAt'] as String);
      _session = WatchSession(
        statId: s.statId,
        stationName: s.stationName,
        etaMin: s.etaMin,
        expiresAt: expiresAt,
        currentAvail: s.currentAvail,
      );
      _saveLocal();
      _notify();
      return true;
    } catch (e) {
      debugPrint('[WATCH] extend 실패: $e');
      return false;
    }
  }

  /// FCM ev_watch 수신 시 현재 자리 수 업데이트
  void updateCurrentAvail(String statId, int newAvail) {
    if (_session?.statId != statId) return;
    _session = WatchSession(
      statId: _session!.statId,
      stationName: _session!.stationName,
      etaMin: _session!.etaMin,
      expiresAt: _session!.expiresAt,
      currentAvail: newAvail,
    );
    _saveLocal();
    _notify();
  }

  void _saveLocal() {
    try {
      Hive.box(_boxKey).put(_hiveKey, _session?.toMap());
    } catch (_) {}
  }

  void _clearLocal() {
    try {
      Hive.box(_boxKey).delete(_hiveKey);
    } catch (_) {}
  }
}
