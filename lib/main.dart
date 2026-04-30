import 'dart:async';
import 'dart:convert';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_navi/kakao_flutter_sdk_navi.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';
import 'app.dart';
import 'core/constants/api_constants.dart';
import 'core/constants/secrets.dart';
import 'data/services/admob_warmup.dart';
import 'data/services/alert_service.dart';
import 'data/services/house_ad_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/widget_service.dart';

/// 홈 위젯 탭으로 전달된 station 딥링크 처리.
/// MainActivity.onCreate / onNewIntent 에서 SharedPreferences("flutter.widget_pending_*")
/// 키에 써둔 값을 읽어 적절한 notifier에 전달 후 클리어.
Future<void> _consumePendingWidgetIntent() async {
  try {
    final type = await HomeWidget.getWidgetData<String>('widget_pending_type');
    if (type == null || type.isEmpty) return;
    final stationId =
        await HomeWidget.getWidgetData<String>('widget_pending_station_id');
    await HomeWidget.saveWidgetData<String>('widget_pending_type', '');
    await HomeWidget.saveWidgetData<String>(
        'widget_pending_station_id', '');
    if (stationId == null || stationId.isEmpty) return;
    if (type == 'ev') {
      navigateToEvStationNotifier.value = stationId;
    } else if (type == 'gas') {
      navigateToGasStationNotifier.value = stationId;
    }
  } catch (_) {
    // 위젯 딥링크 실패는 무시 (앱 실행 자체엔 영향 없음)
  }
}

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
    await _saveEvAlarmToHive(box, message.data);
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

/// 로컬 알림 채널 + 핸들러 초기화. main() 을 빨리 끝내기 위해 분리.
/// 채널 생성은 OS 측에서 idempotent — 첫 알림이 발송되기 전에만 끝나면 됨.
Future<void> _initLocalNotifications() async {
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
      } else if (details.actionId == 'find_alt' && payload.startsWith('ev_watch:')) {
        // "다른 충전소" 액션 — 만석 도달 시 AI 재추천 트리거
        final stationId = payload.substring('ev_watch:'.length);
        excludeStationOnReplanNotifier.value = stationId;
        requestEvReplanNotifier.value++;
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
}

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // 네이티브 스플래시 0.3초 cap. 로고는 잠깐만 보이도록 최소화.
  // 캐시된 광고가 같은 시점에 그 아래로 push 돼있어 내려가는 순간 흰 갭 없이
  // 바로 광고가 보인다. 캐시 없으면 0.3초 후 다음 화면으로 진행.
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  Timer(const Duration(milliseconds: 300), FlutterNativeSplash.remove);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  // setPreferredOrientations 는 await 안 해도 무방 (이후 화면 빌드 전에 적용됨)
  unawaited(SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]));

  KakaoSdk.init(nativeAppKey: Secrets.kakaoNativeAppKey);

  // Firebase 는 onBackgroundMessage 등록 전에 필수
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 로컬 알림 초기화는 fire-and-forget — 채널 생성은 idempotent,
  // 첫 알림이 발송되기 전에만 끝나면 됨. main() 을 0.3초 정도 줄임.
  unawaited(_initLocalNotifications());

  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('favorites');

  // House ad: 디스크 캐시 즉시 로드 → 첫 프레임에 광고가 있으면 바로 보임.
  // 네트워크 fetch 는 백그라운드에서 갱신 (stale-while-revalidate).
  HouseAdCache.readFromDiskAndInstall();

  // 홈 위젯 탭 딥링크: MainActivity가 SharedPreferences에 써둔 값 소비.
  // 첫 프레임 라우팅에 영향 가능 → await 유지.
  await _consumePendingWidgetIntent();

  // bootstrap 호출에 _serverUrl 필요 → 첫 프레임 전 필수
  await DkswCore.init(
    packageName: AppConstants.packageName,
    serverUrl: 'https://console.dksw4.com/console',
  );
  DkswCore.trackSession();

  // 무거운 init들은 fire-and-forget. 첫 프레임/스플래시 시간만 늘리던 주범:
  //  - Workmanager: 백그라운드 작업 등록 (지도/주유 위젯) — 화면 빌드 전 끝날 필요 X
  //  - WidgetService: 홈 위젯 갱신 — 위젯이 백그라운드로 갱신되므로 약간 지연 OK
  //  - FlutterNaverMap.init: 지도 화면 들어가기 전에만 끝나면 됨
  unawaited(_initBackgroundTasks());

  runApp(const ProviderScope(child: ChargeHelperApp()));
}

/// 첫 프레임 이후에 진행해도 되는 무거운 init들. main() 응답 시간 단축용.
Future<void> _initBackgroundTasks() async {
  try {
    await WidgetService.init();
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
    WidgetService.updateAll();
  } catch (e) {
    debugPrint('[BG Tasks] 초기화 실패 (무시됨): $e');
  }
  try {
    await FlutterNaverMap().init(
      clientId: Secrets.naverMapClientId,
      onAuthFailed: (e) => debugPrint('네이버 지도 인증 실패: $e'),
    );
  } catch (e) {
    debugPrint('[NaverMap] init 실패 (무시됨): $e');
  }
  try {
    await MobileAds.instance.initialize();
    // AdMob 워밍업 — 슬롯 단위 ID 로 한 번 load() 해서 SDK 내부 캐시 데움.
    unawaited(AdMobWarmup.run());
  } catch (e) {
    debugPrint('[AdMob] init 실패 (무시됨): $e');
  }
  // house ad — 디스크 캐시는 main 에서 이미 install 됨. 여기선 백그라운드 갱신.
  unawaited(HouseAdCache.fetch());
}
