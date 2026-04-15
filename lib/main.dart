import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_navi/kakao_flutter_sdk_navi.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'app.dart';
import 'core/constants/secrets.dart';
import 'data/services/alert_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/widget_service.dart';

/// WorkManager 백그라운드 콜백 (top-level 함수 필수)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case 'widgetGasUpdate':
        return await WidgetService.backgroundUpdateGas();
      case 'widgetEvUpdate':
        return await WidgetService.backgroundUpdateEv();
    }
    return Future.value(true);
  });
}

/// 백그라운드 isolate에서 Hive에 알림 내역 저장
Future<void> _saveGasPriceToHive(Map<String, dynamic> data) async {
  try {
    await Hive.initFlutter();
    final box = await Hive.openBox('settings');
    final raw = data['stations'];
    if (raw == null) return;
    final stations =
        List<Map<String, dynamic>>.from(jsonDecode(raw as String));
    if (stations.isEmpty) return;
    final body = stations.map((s) {
      final name = s['name'] as String;
      final price = s['price'] as int;
      final priceStr = price
          .toString()
          .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
              (m) => '${m[1]},');
      final change = s['change'] as int? ?? 0;
      String changeStr = '';
      if (change > 0) changeStr = ' ▲$change원';
      else if (change < 0) changeStr = ' ▼${change.abs()}원';
      final fuelType = s['fuelType'] as String? ?? '';
      final fuelSuffix = fuelType.isNotEmpty ? ' ($fuelType)' : '';
      return '• $name  ${priceStr}원/L$changeStr$fuelSuffix';
    }).join('\n');
    final msgs = List<Map<String, dynamic>>.from(
      ((box.get('push_messages', defaultValue: <dynamic>[]) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))),
    );
    msgs.insert(0, {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': '⛽ 오늘의 주유 가격',
      'body': body,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (msgs.length > 50) msgs.removeLast();
    await box.put('push_messages', msgs);
    final unread = ((box.get('push_unread_count', defaultValue: 0) as int?) ?? 0) + 1;
    await box.put('push_unread_count', unread);
  } catch (_) {}
}

/// "읽음" 액션 버튼: 앱 열지 않고 미읽음 수만 0으로 초기화
@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse details) async {
  if (details.actionId == 'mark_read') {
    try {
      await Hive.initFlutter();
      final box = Hive.isBoxOpen('settings')
          ? Hive.box('settings')
          : await Hive.openBox('settings');
      await box.put('push_unread_count', 0);
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final androidPlugin = notificationPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(gasPriceChannel);
  await androidPlugin?.createNotificationChannel(gasPriceChannelVibrate);
  await androidPlugin?.createNotificationChannel(gasPriceChannelSilent);
  await androidPlugin?.createNotificationChannel(evAlarmChannel);
  await androidPlugin?.createNotificationChannel(evAlarmChannelVibrate);
  await androidPlugin?.createNotificationChannel(evAlarmChannelSilent);
  await notificationPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
  );
  await Hive.initFlutter();
  final box = await Hive.openBox('settings');
  if (message.data['type'] == 'gas_price_alert') {
    final soundMode = (box.get('alert_sound_mode', defaultValue: 0) as int?) ?? 0;
    showGasPriceNotification(message.data, soundMode: soundMode);
    await _saveGasPriceToHive(message.data);
  } else if (message.data['type'] == 'ev_alarm') {
    final soundMode = (box.get('ev_alarm_sound_mode', defaultValue: 0) as int?) ?? 0;
    showEvAlarmNotification(message.data, soundMode: soundMode);
    await _saveEvAlarmToHive(box, message.data);
  } else if (message.data['type'] == 'ev_watch') {
    final soundMode = (box.get('ev_alarm_sound_mode', defaultValue: 0) as int?) ?? 0;
    showEvWatchNotification(message.data, soundMode: soundMode);
  }
}

Future<void> _saveEvAlarmToHive(dynamic box, Map<String, dynamic> data) async {
  try {
    final title = data['title'] as String? ?? '⚡ 충전소 자리 변동';
    final body = data['body'] as String? ?? '';
    if (body.isEmpty) return;
    final msgs = List<Map<String, dynamic>>.from(
      ((box.get('push_messages', defaultValue: <dynamic>[]) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))),
    );
    msgs.insert(0, {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': title,
      'body': body,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (msgs.length > 50) msgs.removeLast();
    await box.put('push_messages', msgs);
    final unread = ((box.get('push_unread_count', defaultValue: 0) as int?) ?? 0) + 1;
    await box.put('push_unread_count', unread);
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  KakaoSdk.init(nativeAppKey: Secrets.kakaoNativeAppKey);

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 로컬 알림 초기화 (소리/진동/무음 채널 각각 등록)
  final androidPlugin = notificationPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(gasPriceChannel);
  await androidPlugin?.createNotificationChannel(gasPriceChannelVibrate);
  await androidPlugin?.createNotificationChannel(gasPriceChannelSilent);
  await androidPlugin?.createNotificationChannel(evAlarmChannel);
  await androidPlugin?.createNotificationChannel(evAlarmChannelVibrate);
  await androidPlugin?.createNotificationChannel(evAlarmChannelSilent);
  await notificationPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (details) {
      final payload = details.payload ?? '';
      if (details.actionId == 'mark_read') {
        AlertService().markAllRead();
      } else if (payload.startsWith('ev_alarm:')) {
        // payload 형식: ev_alarm:stationId:encodedTitle:encodedBody
        final rest = payload.substring('ev_alarm:'.length);
        final parts = rest.split(':');
        final stationId = parts.isNotEmpty ? parts[0] : '';
        if (stationId.isNotEmpty) {
          navigateToEvStationNotifier.value = stationId;
        }
        // main isolate에서 히스토리 저장 (백그라운드 isolate Hive 캐시 불일치 방지)
        if (parts.length >= 3) {
          try {
            final title = Uri.decodeComponent(parts[1]);
            final body = Uri.decodeComponent(parts.sublist(2).join(':'));
            AlertService().addEvAlarmMessage({'title': title, 'body': body});
          } catch (_) {}
        }
      } else if (payload.startsWith('ev_watch:')) {
        final stationId = payload.substring('ev_watch:'.length);
        if (stationId.isNotEmpty) navigateToEvStationNotifier.value = stationId;
      } else {
        // 알림 본문 탭 또는 "상세보기" 버튼 → 알림 페이지로 이동
        navigateToAlertsNotifier.value++;
      }
    },
    onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
  );

  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('favorites');

  // 홈 위젯 초기화 및 WorkManager 등록
  await WidgetService.init();
  try {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      'widgetGasUpdate',
      'widgetGasUpdate',
      frequency: const Duration(minutes: 30),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
    await Workmanager().registerPeriodicTask(
      'widgetEvUpdate',
      'widgetEvUpdate',
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } catch (e) {
    debugPrint('[WorkManager] 초기화 실패 (무시됨): $e');
  }
  // 앱 시작 시 즉시 1회 갱신
  WidgetService.updateAll();

  await FlutterNaverMap().init(
    clientId: Secrets.naverMapClientId,
    onAuthFailed: (e) => debugPrint('네이버 지도 인증 실패: $e'),
  );

  runApp(const ProviderScope(child: ChargeHelperApp()));
}
