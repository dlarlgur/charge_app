import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/constants/api_constants.dart';
import '../../../data/services/user_sync_service.dart';

/// 경로 프리뷰 엔진 사용자 선택 — 목적지 입력 시 그려주는 경로를 어느 내비 기준으로 할지.
/// 저장: settings box 'route_engine' (tmap | naver | kakao). 미설정 = 아직 안 물어봄.
class RouteEnginePref {
  static const _key = 'route_engine';

  /// 변경 신호 — 설정 타일/AI 탭 배지가 IndexedStack 로 상시 mount 라 필요.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  /// 저장된 값 (미설정이면 null)
  static String? raw() {
    final v = Hive.box(AppConstants.settingsBox).get(_key);
    return (v == 'tmap' || v == 'naver' || v == 'kakao') ? v as String : null;
  }

  /// 실제 사용할 값 (미설정이면 tmap)
  static String get() => raw() ?? 'tmap';

  static Future<void> set(String v) async {
    await Hive.box(AppConstants.settingsBox).put(_key, v);
    version.value++;
    // 로그인 사용자는 서버에도 저장 — 재설치/기기변경 시 복원 (게스트는 내부 no-op)
    UserSyncService.instance.putPrefs(routeEngine: v);
  }

  /// 서버 복원 등 외부 변경 후 구독처 갱신
  static void notifyChanged() => version.value++;

  static String label(String v) => switch (v) {
        'naver' => '네이버',
        'kakao' => '카카오',
        _ => '티맵',
      };
}

class _EngineOption {
  final String value, title, sub, asset;
  const _EngineOption(this.value, this.title, this.sub, this.asset);
}

const _options = [
  _EngineOption('tmap', '티맵', '추천경로 · 고속도로우선', 'assets/nav/tmap_logo.webp'),
  _EngineOption('naver', '네이버지도', '실시간 추천 · 큰길우선', 'assets/nav/naver_logo.png'),
  _EngineOption(
      'kakao', '카카오내비', '추천경로 · 큰길우선', 'assets/nav/kakaomap_logo.png'),
];

/// 엔진 선택 시트 — 선택 시 저장까지 하고 값을 반환, 닫으면 null.
Future<String?> showRouteEngineSheet(BuildContext context) {
  final current = RouteEnginePref.raw();
  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final muted = isDark ? Colors.white60 : const Color(0xFF64748B);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 14),
              const Text('경로 미리보기 기준',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('목적지 경로를 어떤 내비 기준으로 보여드릴까요?',
                  style: TextStyle(fontSize: 12.5, color: muted)),
              const SizedBox(height: 6),
              for (final o in _options)
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(o.asset,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEDEDED),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.route_rounded,
                                  color: Colors.grey, size: 20),
                            )),
                  ),
                  title: Text(o.title,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                  subtitle:
                      Text(o.sub, style: TextStyle(fontSize: 12, color: muted)),
                  trailing: current == o.value
                      ? const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF10B981), size: 20)
                      : null,
                  onTap: () async {
                    await RouteEnginePref.set(o.value);
                    if (ctx.mounted) Navigator.pop(ctx, o.value);
                  },
                ),
              const SizedBox(height: 2),
              Text('경로 칩 옆 "OO 기준"을 누르면 언제든 바꿀 수 있어요',
                  style: TextStyle(fontSize: 11.5, color: muted)),
            ],
          ),
        ),
      );
    },
  );
}
