import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/user_sync_service.dart';

/// 홈 리포트 바로가기 버튼 표시 여부 — 기본 ON, 설정에서 끌 수 있다.
class ReportFabPref {
  ReportFabPref._();

  static const _key = 'report_fab_on';

  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static bool get() =>
      Hive.box(AppConstants.settingsBox).get(_key, defaultValue: true) == true;

  static Future<void> set(bool on) async {
    await Hive.box(AppConstants.settingsBox).put(_key, on);
    version.value++;
    UserSyncService.instance.putPrefs(reportShortcut: on);
  }

  static void notifyChanged() => version.value++;
}

/// 홈 하단 좌측 플로팅 버튼 — 유가·충전 리포트로 바로 이동.
///
/// 설정 안에만 두면 아무도 못 찾는 기능이라 홈에 상시 진입점을 둔다.
/// 목록을 스크롤해도 가려지지 않게 Stack 오버레이로 띄우고, 바텀탭 위에 앉힌다.
class ReportFab extends StatefulWidget {
  const ReportFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<ReportFab> createState() => _ReportFabState();
}

class _ReportFabState extends State<ReportFab> {
  @override
  void initState() {
    super.initState();
    ReportFabPref.version.addListener(_onChanged);
  }

  @override
  void dispose() {
    ReportFabPref.version.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!ReportFabPref.get()) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 14, bottom: 10),
      child: Material(
        color: isDark ? AppColors.darkSurface2 : Colors.white,
        borderRadius: BorderRadius.circular(26),
        elevation: isDark ? 0 : 3,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 15, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isDark
                    ? AppColors.darkCardBorder
                    : AppColors.lightCardBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.gasBlue
                        .withValues(alpha: isDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.insights_rounded,
                      size: 15, color: AppColors.gasBlue),
                ),
                const SizedBox(width: 8),
                Text(
                  '유가 리포트',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
