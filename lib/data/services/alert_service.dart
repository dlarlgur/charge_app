import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/api_constants.dart';

class AlertService {
  static final AlertService _instance = AlertService._();
  factory AlertService() => _instance;
  AlertService._();

  /// 구독 목록이 바뀔 때마다 increment → 리스너에서 UI 갱신 가능
  final subsChanged = ValueNotifier<int>(0);
  void _notifySubsChanged() => subsChanged.value++;

  static const _boxKey = 'settings';
  static const _deviceIdKey = 'alert_device_id';
  static const _subsKey = 'alert_subscriptions';           // Map<String, String> stationId → "fuelType1,fuelType2,..."
  static const _subsNamesKey = 'alert_subscription_names'; // Map<String, String> stationId → name
  static const _alertsEnabledKey = 'alerts_enabled';
  static const _messagesKey = 'push_messages';             // List of received messages
  static const _unreadCountKey = 'push_unread_count';      // 미읽음 수
  static const _alertHourKey = 'alert_hour';
  static const _alertMinuteKey = 'alert_minute';
  static const _soundModeKey = 'alert_sound_mode'; // 0=소리, 1=진동, 2=무음

  final _dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  String get deviceId {
    final box = Hive.box(_boxKey);
    var id = box.get(_deviceIdKey) as String?;
    if (id == null) {
      id = const Uuid().v4();
      box.put(_deviceIdKey, id);
    }
    return id;
  }

  bool get alertsEnabled =>
      Hive.box(_boxKey).get(_alertsEnabledKey, defaultValue: true) as bool;

  int get alertHour =>
      Hive.box(_boxKey).get(_alertHourKey, defaultValue: 8) as int;

  int get alertMinute =>
      Hive.box(_boxKey).get(_alertMinuteKey, defaultValue: 0) as int;

  /// 0=소리, 1=진동, 2=무음
  int get alertSoundMode =>
      (Hive.box(_boxKey).get(_soundModeKey, defaultValue: 0) as int?) ?? 0;

  void setAlertSoundMode(int mode) =>
      Hive.box(_boxKey).put(_soundModeKey, mode);

  /// 알림 시각 설정 (로컬 저장 + 서버 동기화)
  Future<void> setAlertTime(int hour, int minute) async {
    Hive.box(_boxKey).put(_alertHourKey, hour);
    Hive.box(_boxKey).put(_alertMinuteKey, minute);
    try {
      await _dio.put('/alerts/time', data: {
        'deviceId': deviceId,
        'hour': hour,
        'minute': minute,
      });
    } catch (_) {}
  }

  // ── 구독 목록 (주유소별 유종 문자열) ──

  /// 전체 구독 맵 (stationId → "fuelType1,fuelType2,...")
  Map<String, String> get _subsMap {
    final raw = Hive.box(_boxKey).get(_subsKey, defaultValue: <dynamic, dynamic>{});
    return Map<String, String>.from(raw as Map);
  }

  /// 구독된 stationId 목록
  List<String> get subscribedStationIds => _subsMap.keys.toList();

  /// 특정 주유소의 구독된 유종 목록
  List<String> subscribedFuelTypes(String stationId) {
    final fuelStr = _subsMap[stationId];
    if (fuelStr == null || fuelStr.isEmpty) return [];
    return fuelStr.split(',');
  }

  Map<String, String> get subscribedStationNames {
    final raw = Hive.box(_boxKey).get(_subsNamesKey, defaultValue: <dynamic, dynamic>{});
    return Map<String, String>.from(raw as Map);
  }

  String stationName(String id) => subscribedStationNames[id] ?? id;

  bool isSubscribed(String stationId) => _subsMap.containsKey(stationId);

  bool isSubscribedFuelType(String stationId, String fuelType) {
    final fuels = subscribedFuelTypes(stationId);
    return fuels.contains(fuelType);
  }

  static const _fuelLabels = {
    'B027': '휘발유', 'B034': '고급휘발유', 'D047': '경유', 'K015': 'LPG'
  };
  static String fuelLabel(String code) => _fuelLabels[code] ?? code;

  // ── 수신된 푸시 메시지 관리 ──

  List<Map<String, dynamic>> get receivedMessages {
    final raw = Hive.box(_boxKey).get(_messagesKey, defaultValue: <dynamic>[]);
    return List<Map<String, dynamic>>.from(
        (raw as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  int get messageCount => receivedMessages.length;

  int get unreadCount =>
      (Hive.box(_boxKey).get(_unreadCountKey, defaultValue: 0) as int?) ?? 0;

  void markAllRead() => Hive.box(_boxKey).put(_unreadCountKey, 0);

  void addMessage({required String title, required String body}) {
    final box = Hive.box(_boxKey);
    final msgs = receivedMessages;
    msgs.insert(0, {
      'id': const Uuid().v4(),
      'title': title,
      'body': body,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (msgs.length > 50) msgs.removeLast();
    box.put(_messagesKey, msgs);
    box.put(_unreadCountKey, unreadCount + 1);
  }

  /// gas_price_alert 데이터 메시지를 파싱해서 알림 내역에 저장
  void addGasPriceMessage(Map<String, dynamic> data) {
    try {
      final raw = data['stations'];
      if (raw == null) return;
      final stations =
          List<Map<String, dynamic>>.from(jsonDecode(raw as String));
      if (stations.isEmpty) return;
      
      // 전체 유종 중 최저가 찾기
      final allPrices = <int>[];
      for (final s in stations) {
        final prices = List<Map<String, dynamic>>.from(s['prices'] as List);
        for (final p in prices) {
          allPrices.add(p['price'] as int);
        }
      }
      final minPrice = allPrices.reduce((a, b) => a < b ? a : b);
      
      // 주유소별 모든 구독 유종 표시
      final lines = <String>[];
      for (final s in stations) {
        final name = s['name'] as String;
        final prices = List<Map<String, dynamic>>.from(s['prices'] as List);

        final hasMin = prices.any((p) => (p['price'] as int) == minPrice);
        final prefix = hasMin ? '★' : '•';
        lines.add('$prefix $name');

        for (final p in prices) {
          final fuelType = p['fuelType'] as String;
          final price = p['price'] as int;
          final change = p['change'] as int? ?? 0;

          final priceStr = price
              .toString()
              .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                  (m) => '${m[1]},');

          String changeStr = '';
          if (change > 0) changeStr = ' ▲$change원';
          else if (change < 0) changeStr = ' ▼${change.abs()}원';

          lines.add('  $fuelType ${priceStr}원/L$changeStr');
        }
      }
      
      addMessage(title: '⛽ 오늘의 주유 가격', body: lines.join('\n'));
    } catch (_) {}
  }

  void deleteMessage(String id) {
    final msgs = receivedMessages;
    msgs.removeWhere((m) => m['id'] == id);
    Hive.box(_boxKey).put(_messagesKey, msgs);
  }

  void clearMessages() {
    Hive.box(_boxKey).put(_messagesKey, <dynamic>[]);
  }

  /// 알림 전체 켜기/끄기
  Future<void> setAlertsEnabled(bool enabled) async {
    Hive.box(_boxKey).put(_alertsEnabledKey, enabled);
    final subs = _subsMap;
    final names = subscribedStationNames;
    
    if (!enabled) {
      // 서버에서 전부 구독 해제 (로컬 목록은 유지)
      for (final stId in subs.keys) {
        try {
          await _dio.delete('/alerts/unsubscribe', data: {
            'deviceId': deviceId,
            'stationId': stId,
          });
        } catch (_) {}
      }
    } else {
      // 서버에 전부 재구독
      for (final entry in subs.entries) {
        final stId = entry.key;
        final fuelTypes = entry.value;
        final name = names[stId] ?? stId;
        try {
          await _dio.post('/alerts/subscribe', data: {
            'deviceId': deviceId,
            'stationId': stId,
            'stationName': name,
            'fuelTypes': fuelTypes,
          });
        } catch (_) {}
      }
    }
    _notifySubsChanged();
  }

  /// 온보딩 완료 시점에 호출 — 권한 요청 후 FCM 토큰 등록
  Future<void> init() async {
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerDevice(token);

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _registerDevice(newToken);
      });
    } catch (e) {
      // FCM 실패해도 앱 동작에 영향 없음
    }
  }

  /// 홈 화면 진입 시 호출 — 권한 요청 없이 FCM 토큰만 갱신
  Future<void> refreshToken() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) await _registerDevice(token);
      }
    } catch (_) {}
  }

  Future<void> _registerDevice(String fcmToken) async {
    try {
      await _dio.post('/alerts/device', data: {
        'deviceId': deviceId,
        'fcmToken': fcmToken,
      });
    } catch (_) {}
  }

  /// 주유소 구독 (단일 유종 추가)
  Future<bool> subscribe({
    required String stationId,
    required String stationName,
    required String fuelType,
  }) async {
    // 기존 유종에 추가
    final box = Hive.box(_boxKey);
    final subs = _subsMap;
    final existingFuels = subscribedFuelTypes(stationId);
    
    if (!existingFuels.contains(fuelType)) {
      existingFuels.add(fuelType);
    }
    
    // 주유소 3개 제한 체크
    if (!subs.containsKey(stationId) && subs.length >= 3) {
      return false;
    }
    
    try {
      final res = await _dio.post('/alerts/subscribe', data: {
        'deviceId': deviceId,
        'stationId': stationId,
        'stationName': stationName,
        'fuelTypes': existingFuels.join(','),
      });
      if (res.statusCode == 200) {
        subs[stationId] = existingFuels.join(',');
        box.put(_subsKey, subs);
        
        final names = subscribedStationNames;
        names[stationId] = stationName;
        box.put(_subsNamesKey, names);
        _notifySubsChanged();
        return true;
      }
    } catch (e) {
      final data = (e as dynamic).response?.data;
      if (data?['code'] == 'LIMIT_EXCEEDED') return false;
    }
    return false;
  }

  /// 주유소 구독 (여러 유종 한 번에 설정)
  Future<bool> subscribeMultiple({
    required String stationId,
    required String stationName,
    required List<String> fuelTypes,
  }) async {
    final box = Hive.box(_boxKey);
    final subs = _subsMap;
    
    // 주유소 3개 제한 체크
    if (!subs.containsKey(stationId) && subs.length >= 3) {
      return false;
    }
    
    try {
      final res = await _dio.post('/alerts/subscribe', data: {
        'deviceId': deviceId,
        'stationId': stationId,
        'stationName': stationName,
        'fuelTypes': fuelTypes.join(','),
      });
      if (res.statusCode == 200) {
        subs[stationId] = fuelTypes.join(',');
        box.put(_subsKey, subs);
        
        final names = subscribedStationNames;
        names[stationId] = stationName;
        box.put(_subsNamesKey, names);
        _notifySubsChanged();
        return true;
      }
    } catch (e) {
      final data = (e as dynamic).response?.data;
      if (data?['code'] == 'LIMIT_EXCEEDED') return false;
    }
    return false;
  }

  /// 특정 유종 구독 해제
  Future<void> unsubscribeFuelType(String stationId, String fuelType) async {
    final box = Hive.box(_boxKey);
    final subs = _subsMap;
    final fuels = subscribedFuelTypes(stationId);
    fuels.remove(fuelType);
    
    if (fuels.isEmpty) {
      // 모든 유종 제거 → 주유소 자체 삭제
      subs.remove(stationId);
      final names = subscribedStationNames..remove(stationId);
      box.put(_subsNamesKey, names);
    } else {
      // 일부 유종만 제거
      subs[stationId] = fuels.join(',');
    }
    box.put(_subsKey, subs);
    
    try {
      await _dio.post('/alerts/subscribe', data: {
        'deviceId': deviceId,
        'stationId': stationId,
        'stationName': subscribedStationNames[stationId] ?? '',
        'fuelTypes': fuels.join(','),
      });
    } catch (_) {}
    
    _notifySubsChanged();
  }

  /// 주유소 전체 해제 (모든 유종)
  Future<void> unsubscribe(String stationId) async {
    final box = Hive.box(_boxKey);
    final subs = _subsMap;
    subs.remove(stationId);
    box.put(_subsKey, subs);
    
    final names = subscribedStationNames;
    names.remove(stationId);
    box.put(_subsNamesKey, names);
    
    try {
      await _dio.delete('/alerts/unsubscribe', data: {
        'deviceId': deviceId,
        'stationId': stationId,
      });
    } catch (_) {}
    
    _notifySubsChanged();
  }
}
