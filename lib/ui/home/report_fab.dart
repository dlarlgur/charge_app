import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';
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

/// 퀵메뉴 항목 — 이모지 + 라벨 + 색. 항목 추가는 홈(home_screen)의 리스트에 한 줄.
class QuickMenuItem {
  const QuickMenuItem({
    required this.emoji,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// 홈 우측 하단 퀵메뉴 FAB (형 확정: 라벨 붙은 pill → 이모지 스피드다이얼).
///
/// 접힘: 📊 원형 버튼 하나. 탭하면 항목들이 위로 차례로 펼쳐진다(stagger).
/// 항목마다 [라벨 칩 + 이모지 원] — 원들이 메인 버튼과 세로로 정렬돼 손이 안 흔들린다.
/// 지금은 유가·충전 리포트뿐이지만, 나중에 다른 바로가기를 items 에 추가만 하면 된다.
class HomeQuickFab extends StatefulWidget {
  const HomeQuickFab({super.key, required this.items});

  final List<QuickMenuItem> items;

  @override
  State<HomeQuickFab> createState() => _HomeQuickFabState();
}

class _HomeQuickFabState extends State<HomeQuickFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260));
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
    _toggle(); // 항목을 골랐으면 접는다 — 다음에 열 때 다시 깔끔하게.
    item.onTap();
  }

  @override
  Widget build(BuildContext context) {
    if (!ReportFabPref.get()) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 항목이 하나면 스피드다이얼이 과하다 — 바로 실행.
    final single = widget.items.length == 1;

    return Padding(
      padding: const EdgeInsets.only(right: 14, bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── 펼침 항목 (아래→위 stagger, 뒤 항목이 먼저 나타나 위로 쌓이는 느낌) ──
          if (!single)
            for (var i = widget.items.length - 1; i >= 0; i--)
              _itemRow(widget.items[i], i, isDark),
          // ── 메인 버튼 ──
          _mainButton(isDark, single),
        ],
      ),
    );
  }

  Widget _itemRow(QuickMenuItem item, int index, bool isDark) {
    // stagger — 메인 버튼에서 가까운 항목부터 등장.
    final n = widget.items.length;
    final start = (n - 1 - index) * 0.12;
    final anim = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start.clamp(0.0, 0.6), (start + 0.5).clamp(0.0, 1.0),
          curve: Curves.easeOutBack),
    );
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final v = anim.value.clamp(0.0, 1.0);
        if (_ctrl.value == 0) return const SizedBox.shrink();
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 14),
            child: Transform.scale(
                scale: 0.85 + 0.15 * v,
                alignment: Alignment.centerRight,
                child: child),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GestureDetector(
          onTap: () => _select(item),
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 라벨 칩
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF232B36) : Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: isDark ? Colors.white : const Color(0xFF1F2937),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              // 이모지 원 — 메인 버튼과 세로 정렬
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: item.color.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3)),
                  ],
                ),
                child: Text(item.emoji, style: const TextStyle(fontSize: 19)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mainButton(bool isDark, bool single) {
    return GestureDetector(
      onTap: single ? widget.items.first.onTap : _toggle,
      child: Container(
        width: 50,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF232B36) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : const Color(0xFFE5EAF0)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.16),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        // 열림 ↔ 닫힘 크로스페이드: 📊 ↔ ✕
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (child, a) =>
              ScaleTransition(scale: a, child: child),
          child: _open
              ? Icon(Icons.close_rounded,
                  key: const ValueKey('x'),
                  size: 22,
                  color: isDark ? Colors.white : const Color(0xFF475569))
              : const Text('📊',
                  key: ValueKey('emoji'), style: TextStyle(fontSize: 21)),
        ),
      ),
    );
  }
}
