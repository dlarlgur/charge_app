import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../constants/api_constants.dart';
import '../../data/services/user_sync_service.dart';

/// 길찾기 범위 — 추천 주유소/충전소까지만 안내할지, 최종 목적지까지 한 번에 안내할지.
///
/// 내비 3사 모두 경유지를 지원한다(티맵 5개 / 카카오 3개 / 네이버 3개).
/// 목적지가 있는 흐름(AI 추천 등)에서만 의미가 있고, 그 외에는 이 값과 무관하게
/// 목적지 하나만 넘긴다.
class NavScopePref {
  NavScopePref._();

  static const _key = 'nav_scope';
  static const station = 'station'; // 주유소까지
  static const destination = 'destination'; // 목적지까지 (기본)

  /// 시트·설정 타일이 서로 다른 위젯 트리에 있어 변경 전파가 필요.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static String get() {
    final v = Hive.box(AppConstants.settingsBox).get(_key);
    return v == station ? station : destination;
  }

  static bool get toDestination => get() == destination;

  static Future<void> set(String v) async {
    final val = v == station ? station : destination;
    await Hive.box(AppConstants.settingsBox).put(_key, val);
    version.value++;
    // 로그인 사용자는 서버에도 — 기기 변경·재설치 시 복원 (게스트는 내부 no-op)
    UserSyncService.instance.putPrefs(navScope: val);
  }

  /// 서버 복원 등 외부 변경 후 구독처 갱신
  static void notifyChanged() => version.value++;

  static String label(String v) => v == station ? '주유소까지' : '목적지까지';
}
