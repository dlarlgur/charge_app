import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_dialog.dart';

/// 알림(푸시) 권한 보장. 허용되면 true.
/// - 영구거부 전이면 OS 허용 팝업을 띄운다(시스템 다이얼로그).
/// - 안드13+는 한 번 거부하면 OS 팝업이 다시 안 뜨므로(영구거부), 그땐 설정으로 유도.
Future<bool> ensureNotifPermission(BuildContext context) async {
  var status = await Permission.notification.status;
  if (status.isGranted) return true;
  if (!status.isPermanentlyDenied) {
    status = await Permission.notification.request();
    if (status.isGranted) return true;
  }
  if (context.mounted) {
    final go = await showAppDialog<bool>(
      context,
      icon: Icons.notifications_active_rounded,
      title: '알림을 켜주세요',
      message: '기기 설정에서 알림을 허용하면\n이벤트·혜택과 가격 알림을 받을 수 있어요.',
      primaryLabel: '설정 열기',
      primaryValue: true,
      secondaryLabel: '나중에',
      secondaryValue: false,
    );
    if (go == true) await openAppSettings();
  }
  return false;
}
