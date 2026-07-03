import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';

/// 차량타입별 푸시 토픽 동기화 — 콘솔 '푸시 발송'의 주유/전기 타겟용.
///
/// 토픽: veh_gas_<pkg> / veh_ev_<pkg> (콘솔 pushService.topicFor 와 동일 규칙)
///  · 기름차(gas)  → veh_gas 구독, veh_ev 해지
///  · 전기차(ev)   → veh_ev 구독, veh_gas 해지
///  · 둘 다(both)  → 둘 다 구독 (주유·충전 푸시 모두 수신)
///
/// 호출 시점: 앱 부팅(main) + 차량타입 변경(온보딩/설정). 매 부팅 재동기화라
/// 어긋나도 다음 부팅에 정정됨. 실패는 무시(fire-and-forget).
class PushTopicService {
  static Future<void> syncVehicleTopics() async {
    try {
      final box = Hive.box(AppConstants.settingsBox);
      final vt = (box.get(AppConstants.keyVehicleType) as String?) ?? 'both';
      // DkswCore 토픽 규칙 재사용 — notices_<safePkg> 에서 safePkg 추출.
      final safePkg = DkswCore.noticesTopic().replaceFirst('notices_', '');
      final fm = FirebaseMessaging.instance;
      final wantGas = vt == 'gas' || vt == 'both';
      final wantEv = vt == 'ev' || vt == 'both';
      if (wantGas) {
        await fm.subscribeToTopic('veh_gas_$safePkg');
      } else {
        await fm.unsubscribeFromTopic('veh_gas_$safePkg');
      }
      if (wantEv) {
        await fm.subscribeToTopic('veh_ev_$safePkg');
      } else {
        await fm.unsubscribeFromTopic('veh_ev_$safePkg');
      }
    } catch (_) {
      // 토픽 동기화 실패는 치명적이지 않음 — 다음 부팅에 재시도.
    }
  }
}
