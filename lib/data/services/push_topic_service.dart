import 'dart:async';
import 'dart:convert';

import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';

/// 차량타입별 푸시 토픽 동기화 + 콘솔 디바이스 메타 보고.
///
/// 토픽: veh_gas_<pkg> / veh_ev_<pkg> (콘솔 pushService.topicFor 와 동일 규칙)
///  · 기름차(gas)  → veh_gas 구독, veh_ev 해지
///  · 전기차(ev)   → veh_ev 구독, veh_gas 해지
///  · 둘 다(both)  → 둘 다 구독 (주유·충전 푸시 모두 수신)
///
/// 호출 시점: 앱 부팅(main) + 차량타입 변경(온보딩/설정). 매 부팅 재동기화라
/// 어긋나도 다음 부팅에 정정됨. 실패는 무시(fire-and-forget).
class PushTopicService {
  // 콘솔 API — main.dart 의 DkswCore.init(serverUrl:)과 동일 값.
  static const _consoleBase = 'https://console.dksw4.com/console';

  static Future<void> syncVehicleTopics() async {
    try {
      final box = Hive.box(AppConstants.settingsBox);
      final vt = (box.get(AppConstants.keyVehicleType) as String?) ?? 'both';
      // DkswCore 토픽 규칙 재사용 — notices_<safePkg> 에서 safePkg 추출.
      final safePkg = DkswCore.noticesTopic().replaceFirst('notices_', '');
      // 콘솔 차량타입 보고를 FCM 구독보다 먼저 — 첫 설치 부팅은 FCM 토큰
      // 준비가 늦어 구독이 던지면 보고까지 스킵돼 사용자 목록 '차량'이
      // 미상(—)으로 남던 문제. 보고는 독립 fire-and-forget.
      unawaited(_reportVehicleType(vt));
      final fm = FirebaseMessaging.instance;
      final wantGas = vt == 'gas' || vt == 'both';
      final wantEv = vt == 'ev' || vt == 'both';
      // v2(data-only) 토픽 — 앱이 알림을 직접 그려 방해금지·알림함·탭 라우팅이 적용됨.
      // 레거시(veh_*)는 해지 (콘솔이 레거시+v2 이중 발송이라 이중 수신 방지).
      if (wantGas) {
        await fm.subscribeToTopic('v2_veh_gas_$safePkg');
      } else {
        await fm.unsubscribeFromTopic('v2_veh_gas_$safePkg');
      }
      await fm.unsubscribeFromTopic('veh_gas_$safePkg');
      if (wantEv) {
        await fm.subscribeToTopic('v2_veh_ev_$safePkg');
      } else {
        await fm.unsubscribeFromTopic('v2_veh_ev_$safePkg');
      }
      await fm.unsubscribeFromTopic('veh_ev_$safePkg');
    } catch (_) {
      // 토픽 동기화 실패는 치명적이지 않음 — 다음 부팅에 재시도.
    }
  }

  static Future<void> _reportVehicleType(String vt) async {
    try {
      final deviceId = DkswCore.deviceId;
      if (deviceId.isEmpty) return;
      await http
          .post(
            Uri.parse('$_consoleBase/api/device-meta'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'package': 'com.dksw.charge',
              'deviceId': deviceId,
              'vehicleType': vt,
            }),
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // 보고 실패 무시 — 다음 부팅에 재시도.
    }
  }
}
