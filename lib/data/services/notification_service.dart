import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'station_alias_service.dart';

final notificationPlugin = FlutterLocalNotificationsPlugin();

/// 방해 금지 시간(DND) 구간인지 — 시스템 알림 표시를 막을지 판단.
/// 포그라운드/백그라운드 isolate 양쪽에서 호출되므로 AlertService 의존 없이
/// Hive 'settings' 박스를 직접 읽는다(백그라운드 핸들러에서 이미 openBox 됨).
/// 자정 넘김(예 23:00~07:00) 처리 포함. 박스 미오픈 등 예외 시 false(=알림 표시).
/// 주의: ev_watch(자리변동알림)는 이 게이트를 거치지 않고 항상 표시한다.
bool _isWithinDnd() {
  try {
    final box = Hive.box('settings');
    if (box.get('dnd_enabled', defaultValue: false) != true) return false;
    final start = (box.get('dnd_start_min', defaultValue: 1380) as int?) ?? 1380;
    final end = (box.get('dnd_end_min', defaultValue: 420) as int?) ?? 420;
    if (start == end) return false;
    final now = DateTime.now();
    final n = now.hour * 60 + now.minute;
    return start < end ? (n >= start && n < end) : (n >= start || n < end);
  } catch (_) {
    return false;
  }
}

/// 알림 "상세보기" 액션 탭 시 increment → HomeScreen에서 알림 페이지로 이동
final navigateToAlertsNotifier = ValueNotifier<int>(0);

/// EV 알람 탭 시 stationId 전달 → HomeScreen에서 충전소 상세로 이동
final navigateToEvStationNotifier = ValueNotifier<String>('');

/// 문의 답변 알림 탭 시 그 문의 id 전달 → HomeScreen이 1:1 문의 상세로 이동.
final navigateToInquiryNotifier = ValueNotifier<int>(0);

/// 이벤트/공지 알림 탭 시 그 id 전달 → HomeScreen이 해당 상세로 이동 (포그라운드 로컬알림 탭 경로).
final navigateToEventNotifier = ValueNotifier<int>(0);
final navigateToNoticeNotifier = ValueNotifier<int>(0);

/// 홈 위젯(주유소) 탭 시 stationId 전달 → HomeScreen에서 주유소 상세로 이동
final navigateToGasStationNotifier = ValueNotifier<String>('');

/// EV watch 만석 알림의 "다른 충전소" 액션 탭 시 increment.
/// HomeScreen 이 listen → AI 탭 전환 + AiMainScreen 에 replan 트리거 전달.
/// value 는 단조 증가하는 카운터 (값 자체는 의미 없음, 새 이벤트 알림 신호용).
final requestEvReplanNotifier = ValueNotifier<int>(0);

/// "다른 충전소" 재추천 시 제외할 stationId (만석 도달한 곳).
/// AiMainScreen 이 분석 시 이 값을 읽어 후보에서 빼거나 표시 분기.
final excludeStationOnReplanNotifier = ValueNotifier<String>('');

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

/// Android Auto 차량 표시 필수 액션 (Google 정책) — RemoteInput 답장 + 읽음.
/// semanticAction(SEMANTIC_ACTION_REPLY / MARK_AS_READ) 부착 안 하면 안드로이드 오토가
/// 메시징 액션으로 인식 못 해 차량 HMI 에 알림 자체가 안 뜬다. flutter_local_notifications
/// 19.x 부터 semanticAction 파라미터 지원.
/// 액션 자체 동작은 noop. main.dart 의 backgroundResponse 에서 reply/mark_read 둘 다 무시.
List<AndroidNotificationAction> _autoActions() => const <AndroidNotificationAction>[
      AndroidNotificationAction(
        'reply',
        '답장',
        inputs: <AndroidNotificationActionInput>[
          AndroidNotificationActionInput(label: '메시지'),
        ],
        showsUserInterface: false,
        cancelNotification: false,
        semanticAction: SemanticAction.reply,
      ),
      AndroidNotificationAction(
        'mark_read',
        '읽음',
        showsUserInterface: false,
        cancelNotification: true,
        semanticAction: SemanticAction.markAsRead,
      ),
    ];

/// 서버에서 보낸 data payload 파싱 후 스타일 알림 표시
/// soundMode: 0=소리, 1=진동, 2=무음
void showGasPriceNotification(Map<String, dynamic> data, {int soundMode = 0}) {
  // 방해 금지 시간: 시스템 알림만 건너뜀. 알림 내역 저장은 호출부에서 별도로 수행.
  if (_isWithinDnd()) return;
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
    final originalName = s['name'] as String;
    final id = (s['id'] ?? '').toString();
    // 사용자 등록 별칭 우선 (id 가 없는 구버전 페이로드는 원본 그대로)
    final name = id.isEmpty ? originalName : StationAliasService.resolveGas(id, originalName);
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

/// EV 워치 세션 알림 표시 (ev_watch 타입)
/// soundMode: 0=소리, 1=진동, 2=무음
/// 만석(newAvail=0) 도달 시 "다른 충전소" 액션 버튼 노출 → AI 재추천 트리거
void showEvWatchNotification(Map<String, dynamic> data, {int soundMode = 0}) {
  final stationId = data['stationId'] as String? ?? '';
  final originalStationName = data['stationName'] as String? ?? '';
  // 사용자가 등록한 별칭 우선 — 알림 title / MessagingStyle conversationTitle 모두 적용
  final stationName = stationId.isEmpty
      ? originalStationName
      : StationAliasService.resolveEv(stationId, originalStationName);
  final serverTitle = data['title'] as String? ?? '⚡ 충전 현황 변동';
  final title = (originalStationName.isNotEmpty && stationName != originalStationName)
      ? serverTitle.replaceAll(originalStationName, stationName)
      : serverTitle;
  final body = data['body'] as String? ?? '충전 자리 변동이 감지됐어요';
  final newAvailStr = data['newAvail'] as String? ?? '';

  final channel = soundMode == 1
      ? evAlarmChannelVibrate
      : soundMode == 2
          ? evAlarmChannelSilent
          : evAlarmChannel;

  // Android Auto 호환 필수 액션 (reply + markAsRead) + 만석시 "다른 충전소"
  final actions = <AndroidNotificationAction>[
    ..._autoActions(),
    if (newAvailStr == '0')
      const AndroidNotificationAction(
        'find_alt',
        '다른 충전소',
        showsUserInterface: true,
        cancelNotification: true,
      ),
  ];

  // Android Auto 호환: MessagingStyleInformation + category=message 사용 시
  // 차량 디스플레이에 메시지 카드로 노출되고 음성 readout 도 트리거됨.
  // bot:true + 고정 key — 발신 주체를 "사람" 이 아닌 앱 봇으로 명시해야 안드로이드 오토가
  // 폰 연락처에 매칭(예: 동명의 연락처 이름으로 표시)하지 않는다. (없으면 사람으로 취급됨)
  // icon: 미지정 시 안드로이드가 이름 첫 글자로 자동 아바타를 그려서 앱 로고로 통일.
  const personIcon = FlutterBitmapAssetAndroidIcon('assets/halfNhalf_launcher.png');
  final messagingPerson = stationName.isNotEmpty
      ? Person(name: stationName, bot: true, key: 'ev_charge_helper', icon: personIcon)
      : const Person(name: '충전 도우미', bot: true, key: 'ev_charge_helper', icon: personIcon);

  notificationPlugin.show(
    1003,
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
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        styleInformation: MessagingStyleInformation(
          messagingPerson,
          conversationTitle: stationName.isNotEmpty ? stationName : null,
          messages: [
            Message(body, DateTime.now(), messagingPerson),
          ],
        ),
        actions: actions.isEmpty ? null : actions,
      ),
    ),
    payload: 'ev_watch:$stationId',
  );
}

/// EV 충전소 자리 알림 표시
/// soundMode: 0=소리, 1=진동, 2=무음
void showEvAlarmNotification(Map<String, dynamic> data, {int soundMode = 0}) {
  // 방해 금지 시간: 시스템 알림만 건너뜀. 알림 내역 저장은 호출부에서 별도로 수행.
  // (ev_watch/showEvWatchNotification 은 게이트 없이 항상 표시 — 자리변동알림은 무조건 수신)
  if (_isWithinDnd()) return;
  final stationId = data['stationId'] as String? ?? '';
  final originalStationName = data['stationName'] as String? ?? '';
  final stationName = stationId.isEmpty
      ? originalStationName
      : StationAliasService.resolveEv(stationId, originalStationName);
  final serverTitle = data['title'] as String? ?? '⚡ 충전소 자리 변동';
  final title = (originalStationName.isNotEmpty && stationName != originalStationName)
      ? serverTitle.replaceAll(originalStationName, stationName)
      : serverTitle;
  final body = data['body'] as String? ?? '충전 가능 자리가 변경됐어요';

  final channel = soundMode == 1
      ? evAlarmChannelVibrate
      : soundMode == 2
          ? evAlarmChannelSilent
          : evAlarmChannel;

  // Android Auto 호환: ev_watch 와 동일 패턴 (MessagingStyle + category=message)
  // bot:true + 고정 key — 사람(연락처)으로 매칭되지 않게. (ev_watch 와 동일 사유)
  const personIcon = FlutterBitmapAssetAndroidIcon('assets/halfNhalf_launcher.png');
  final messagingPerson = stationName.isNotEmpty
      ? Person(name: stationName, bot: true, key: 'ev_charge_helper', icon: personIcon)
      : const Person(name: '충전 도우미', bot: true, key: 'ev_charge_helper', icon: personIcon);

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
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        styleInformation: MessagingStyleInformation(
          messagingPerson,
          conversationTitle: stationName.isNotEmpty ? stationName : null,
          messages: [
            Message(body, DateTime.now(), messagingPerson),
          ],
        ),
        actions: _autoActions(),
      ),
    ),
    payload: 'ev_alarm:$stationId:${Uri.encodeComponent(title)}:${Uri.encodeComponent(body)}',
  );
}

const inquiryReplyChannel = AndroidNotificationChannel(
  'inquiry_reply',
  '문의 답변 알림',
  description: '1:1 문의에 대한 답변이 도착하면 알려드립니다',
  importance: Importance.high,
);

/// 포그라운드(앱 실행 중) 1:1 문의 답변 FCM 수신 시 로컬 알림 표시.
/// 백그라운드/종료 상태에선 시스템이 자동 표시하므로 이 함수는 포그라운드 전용.
/// 폰 알림이면 충분 — Android Auto 대상 아님(BigText).
void showInquiryReplyNotification({String? title, String? body, int? inquiryId}) {
  final t = (title == null || title.isEmpty) ? '문의 답변이 도착했어요' : title;
  final b = body ?? '';
  notificationPlugin.show(
    1004,
    t,
    b,
    NotificationDetails(
      android: AndroidNotificationDetails(
        inquiryReplyChannel.id,
        inquiryReplyChannel.name,
        channelDescription: inquiryReplyChannel.description,
        importance: inquiryReplyChannel.importance,
        priority: Priority.high,
        visibility: NotificationVisibility.public,
        styleInformation: BigTextStyleInformation(b),
      ),
    ),
    payload: 'inquiry_reply:${inquiryId ?? ''}',
  );
}

/// 이벤트·공지 포그라운드 알림 채널.
const eventNoticeChannel = AndroidNotificationChannel(
  'event_notice',
  '이벤트·공지 알림',
  description: '새 이벤트와 공지를 알려드립니다',
  importance: Importance.high,
);

/// 포그라운드(앱 실행 중) 이벤트 FCM 수신 시 로컬 알림 표시.
/// 백그라운드/종료 상태에선 시스템이 자동 표시하므로 이 함수는 포그라운드 전용.
void showEventNotification({String? title, String? body, int? eventId}) {
  _showContentNotification(1005, '🎉 새 이벤트', title, body, 'event:${eventId ?? ''}');
}

/// 포그라운드 공지 FCM 수신 시 로컬 알림 표시.
void showNoticeNotification({String? title, String? body, int? noticeId}) {
  _showContentNotification(1006, '📢 새 공지', title, body, 'notice:${noticeId ?? ''}');
}

void _showContentNotification(
    int id, String fallbackTitle, String? title, String? body, String payload) {
  final t = (title == null || title.isEmpty) ? fallbackTitle : title;
  final b = body ?? '';
  notificationPlugin.show(
    id,
    t,
    b,
    NotificationDetails(
      android: AndroidNotificationDetails(
        eventNoticeChannel.id,
        eventNoticeChannel.name,
        channelDescription: eventNoticeChannel.description,
        importance: eventNoticeChannel.importance,
        priority: Priority.high,
        visibility: NotificationVisibility.public,
        styleInformation: BigTextStyleInformation(b),
      ),
    ),
    payload: payload,
  );
}
