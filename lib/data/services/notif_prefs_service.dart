import 'package:dio/dio.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';

/// 알림 카테고리별 수신 설정 — 리포트 / 공지 / 이벤트.
/// 유가·EV 개별 알림, 방해금지와는 별개 축(그건 각자 기능이 따로 관리한다).
///
/// 서버(push_devices.notif_*)가 진실이고, 로컬 Hive 는 화면을 즉시 그리기 위한 캐시.
/// 서버 조회 전에는 기본값(전부 수신)으로 그려서 토글이 깜빡이지 않게 한다.
class NotifPrefsService {
  NotifPrefsService._();
  static final NotifPrefsService instance = NotifPrefsService._();

  static const keyReport = 'report';
  static const keyNotice = 'notice';
  static const keyEvent = 'event';

  static const _boxName = 'settings';
  static String _hiveKey(String key) => 'notif_pref_$key';

  final _dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ))
    ..transformer = BackgroundTransformer();

  bool cached(String key) {
    try {
      return Hive.box(_boxName).get(_hiveKey(key), defaultValue: true) as bool;
    } catch (_) {
      return true;
    }
  }

  void _cache(String key, bool value) {
    try {
      Hive.box(_boxName).put(_hiveKey(key), value);
    } catch (_) {}
  }

  /// 서버 값으로 로컬 캐시 갱신. 실패하면 캐시 유지(설정 화면은 계속 동작).
  Future<Map<String, bool>?> fetch() async {
    try {
      final res = await _dio.get('/alerts/notif-prefs/${DkswCore.deviceId}');
      final p = (res.data['prefs'] as Map?) ?? const {};
      final out = <String, bool>{};
      for (final k in [keyReport, keyNotice, keyEvent]) {
        final v = p[k] != false;
        out[k] = v;
        _cache(k, v);
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// 토글 저장. 서버 실패 시 false 를 돌려 호출부가 UI 를 되돌린다.
  Future<bool> set(String key, bool value) async {
    _cache(key, value); // 낙관적 반영 — 화면이 먼저 움직인다
    try {
      await _dio.post('/alerts/notif-prefs', data: {
        'deviceId': DkswCore.deviceId,
        'key': key,
        'value': value,
      });
      return true;
    } catch (_) {
      _cache(key, !value); // 롤백
      return false;
    }
  }
}
