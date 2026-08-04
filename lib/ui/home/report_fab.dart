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

/// 퀵메뉴 항목 — 아이콘 + 라벨 + 그라데이션(밝은색→짙은색). 이모지 금지(형 확정).
/// 항목 추가는 홈(home_screen)의 리스트에 한 줄.
class QuickMenuItem {
  const QuickMenuItem({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final List<Color> gradient; // [base, deep]
  final VoidCallback onTap;
}

/// 홈 우측 하단 퀵메뉴 (형 확정 v3).
///
/// 떠 있는 칩 여러 개는 서로 따로 놀아 보여서 폐기 — 메뉴 버튼을 누르면 버튼 위로
/// **카드 한 장**이 펼쳐지고, 그 안이 구분선으로 행 분할되는 팝업 메뉴 형태.
/// 행 = [그라데이션 아이콘 타일 + 라벨 + ›]. 항목이 1개면 메뉴 없이 바로 실행.
class HomeQuickFab extends StatefulWidget {
  const HomeQuickFab({super.key, required this.items});

  final List<QuickMenuItem> items;

  @override
  State<HomeQuickFab> createState() => _HomeQuickFabState();
}

class _HomeQuickFabState extends State<HomeQuickFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 200));
  late final CurvedAnimation _anim = CurvedAnimation(
      parent: _ctrl, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn);
  bool _open = false;

  @override
  void initState() {
    super.initState();
    ReportFabPref.version.addListener(_onChanged);
  }

  @override
  void dispose() {
    ReportFabPref.version.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _ctrl.forward() : _ctrl.reverse();
  }

  void _select(QuickMenuItem item) {
    _toggle(); // 골랐으면 접는다
    item.onTap();
  }

  @override
  Widget build(BuildContext context) {
    if (!ReportFabPref.get()) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final single = widget.items.length == 1;

    return Padding(
      padding: const EdgeInsets.only(right: 14, bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!single) _menuCard(isDark),
          _mainButton(isDark, single),
        ],
      ),
    );
  }

  // ── 메뉴 카드 — 버튼 위에서 한 장으로 펼쳐지고 안에서 행이 나뉜다 ──
  Widget _menuCard(bool isDark) {
    final cardBg = isDark ? const Color(0xFF212A35) : Colors.white;
    final line = isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF0F3F6);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final v = _anim.value;
        if (_ctrl.isDismissed) return const SizedBox.shrink();
        // 버튼(우하단)에서 자라나는 느낌 — scale + 살짝 위로.
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 10),
            child: Transform.scale(
              scale: 0.92 + 0.08 * v,
              alignment: Alignment.bottomRight,
              child: child,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(minWidth: 196),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: isDark
              ? Border.all(color: Colors.white.withValues(alpha: 0.08))
              : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.14),
                blurRadius: 22,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.items.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Divider(height: 1, thickness: 1, color: line),
                  ),
                _menuRow(widget.items[i], isDark),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuRow(QuickMenuItem item, bool isDark) {
    final primary =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1F2937);
    final muted = isDark ? AppColors.darkTextMuted : const Color(0xFFB6C0CC);
    return InkWell(
      onTap: () => _select(item),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: Row(
          children: [
            // 그라데이션 아이콘 타일 — 리스트 안이라 원 대신 라운드 사각(요즘 메뉴 문법)
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: item.gradient,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 11),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: primary,
              ),
            ),
            const SizedBox(width: 14),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, size: 18, color: muted),
          ],
        ),
      ),
    );
  }

  Widget _mainButton(bool isDark, bool single) {
    // 항목 1개: 그 유종 그라데이션 + 아이콘, 바로 실행.
    // 여러 개: '메뉴' 임이 읽히게 grid 아이콘 (형: 메뉴 표시였으면 좋겠다).
    final colors = single
        ? widget.items.first.gradient
        : const [Color(0xFF3B82F6), Color(0xFF2563EB)];
    final icon = single ? widget.items.first.icon : Icons.grid_view_rounded;
    return GestureDetector(
      onTap: single ? widget.items.first.onTap : _toggle,
      child: Container(
        width: 50,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
                color: colors.last.withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, a) =>
              ScaleTransition(scale: a, child: child),
          child: Icon(
            _open ? Icons.close_rounded : icon,
            key: ValueKey(_open),
            size: _open ? 22 : 20,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
