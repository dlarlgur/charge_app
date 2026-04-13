import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final notificationPlugin = FlutterLocalNotificationsPlugin();

/// 알림 "상세보기" 액션 탭 시 increment → HomeScreen에서 알림 페이지로 이동
final navigateToAlertsNotifier = ValueNotifier<int>(0);

/// EV 알람 탭 시 stationId 전달 → HomeScreen에서 충전소 상세로 이동
final navigateToEvStationNotifier = ValueNotifier<String>('');

const gasPriceChannel = AndroidNotificationChannel(
  'gas_price_alert',
  '주유 가격 알림 (소리)',
  description: '즐겨찾기 주유소의 오늘 유가를 알려드립니다',
  importance: Importance.high,
);

const gasPriceChannelVibrate = AndroidNotificationChannel(
  'gas_price_alert_vibrate',
  '주유 가격 알림 (진동)',
  description: '즐겨찾기 주유소의 오늘 유가를 알려드립니다',
  importance: Importance.high,
  playSound: false,
);

const gasPriceChannelSilent = AndroidNotificationChannel(
  'gas_price_alert_silent',
  '주유 가격 알림 (무음)',
  description: '즐겨찾기 주유소의 오늘 유가를 알려드립니다',
  importance: Importance.low,
  playSound: false,
  enableVibration: false,
);

const evAlarmChannel = AndroidNotificationChannel(
  'ev_alarm',
  '충전소 현황 알림 (소리)',
  description: '충전 가능 자리가 생기면 알려드립니다',
  importance: Importance.high,
);

const evAlarmChannelVibrate = AndroidNotificationChannel(
  'ev_alarm_vibrate',
  '충전소 현황 알림 (진동)',
  description: '충전 가능 자리가 생기면 알려드립니다',
  importance: Importance.high,
  playSound: false,
);

const evAlarmChannelSilent = AndroidNotificationChannel(
  'ev_alarm_silent',
  '충전소 현황 알림 (무음)',
  description: '충전 가능 자리가 생기면 알려드립니다',
  importance: Importance.low,
  playSound: false,
  enableVibration: false,
);

/// 서버에서 보낸 data payload 파싱 후 스타일 알림 표시
/// soundMode: 0=소리, 1=진동, 2=무음
void showGasPriceNotification(Map<String, dynamic> data, {int soundMode = 0}) {
  final raw = data['stations'];
  if (raw == null) return;

  final stations = List<Map<String, dynamic>>.from(jsonDecode(raw as String));
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

  final buf = StringBuffer();
  for (final s in stations) {
    final name = s['name'] as String;
    final prices = List<Map<String, dynamic>>.from(s['prices'] as List);

    final hasMin = prices.any((p) => (p['price'] as int) == minPrice);
    final prefix = hasMin ? '★' : '•';
    buf.write('$prefix <b>$name</b><br>');

    for (final p in prices) {
      final fuelType = p['fuelType'] as String;
      final price = p['price'] as int;
      final change = p['change'] as int? ?? 0;

      final priceStr = price.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

      String changeStr = '';
      if (change > 0) changeStr = ' ▲$change원';
      else if (change < 0) changeStr = ' ▼${change.abs()}원';

      if (price == minPrice) {
        buf.write('  <b>$fuelType ${priceStr}원/L</b>$changeStr<br>');
      } else {
        buf.write('  $fuelType ${priceStr}원/L$changeStr<br>');
      }
    }
  }

  final channel = soundMode == 1
      ? gasPriceChannelVibrate
      : soundMode == 2
          ? gasPriceChannelSilent
          : gasPriceChannel;

  notificationPlugin.show(
    1001,
    '⛽ 오늘의 주유 가격',
    null,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: channel.importance,
        priority: soundMode == 2 ? Priority.low : Priority.high,
        playSound: soundMode == 0,
        enableVibration: soundMode != 2,
        styleInformation: BigTextStyleInformation(
          buf.toString(),
          htmlFormatBigText: true,
          contentTitle: '⛽ 오늘의 주유 가격',
          htmlFormatContentTitle: false,
          summaryText: '즐겨찾기 주유소 ${stations.length}곳',
          htmlFormatSummaryText: false,
        ),
        actions: const [
          AndroidNotificationAction('mark_read', '읽음',
              showsUserInterface: false, cancelNotification: true),
          AndroidNotificationAction('view_detail', '상세보기',
              showsUserInterface: true, cancelNotification: true),
        ],
      ),
    ),
    payload: 'gas_price_alert',
  );
}

/// EV 충전소 자리 알림 표시
/// soundMode: 0=소리, 1=진동, 2=무음
void showEvAlarmNotification(Map<String, dynamic> data, {int soundMode = 0}) {
  final title = data['title'] as String? ?? '⚡ 충전소 자리 변동';
  final body = data['body'] as String? ?? '충전 가능 자리가 변경됐어요';
  final stationId = data['stationId'] as String? ?? '';
  final stationName = data['stationName'] as String? ?? '';

  final channel = soundMode == 1
      ? evAlarmChannelVibrate
      : soundMode == 2
          ? evAlarmChannelSilent
          : evAlarmChannel;

  notificationPlugin.show(
    1002,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: channel.importance,
        priority: soundMode == 2 ? Priority.low : Priority.high,
        playSound: soundMode == 0,
        enableVibration: soundMode != 2,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: stationName.isNotEmpty ? stationName : null,
        ),
      ),
    ),
    payload: 'ev_alarm:$stationId',
  );
}
