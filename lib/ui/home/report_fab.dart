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

/// 퀵메뉴 항목 — 작은 컬러 아이콘 + 라벨 (+ 우측 배지). 이모지 금지(형 확정).
/// 형 시안(2026-08-04) 스타일: 타일·화살표 없이 담백한 행. 항목 추가는 홈에 한 줄.
class QuickMenuItem {
  const QuickMenuItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// 우측 회색 칩에 표시할 개수 (예: 가격 알림 3). null 이면 표시 안 함.
  final int? badge;
}

/// 홈 우측 하단 퀵메뉴 (형 확정 v3: 카드 한 장에 행 분할 팝업 메뉴).
///
/// 메뉴 카드는 홈 Stack 안이 아니라 **Overlay(최상단 레이어)** 에 띄운다 —
/// Stack 안에 그리면 자리변동 바 등 뒤 형제 위젯에 가려져 "눌러도 안 뜨는" 문제가
/// 났다(형 제보). Overlay + LayerLink 앵커라 무엇 위에서든 항상 보이고,
/// 바깥 탭으로 닫기도 자연스럽게 된다. 항목이 1개면 메뉴 없이 바로 실행.
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
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    ReportFabPref.version.addListener(_onChanged);
  }

  @override
  void dispose() {
    ReportFabPref.version.removeListener(_onChanged);
    _removeEntry();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  void _openMenu() {
    if (_entry != null) return;
    _entry = OverlayEntry(
      builder: (_) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Stack(
          children: [
            // 바깥 탭 → 닫기 (배경은 안 어둡게 — 홈 지도가 계속 보이게)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeMenu,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.bottomRight,
              offset: const Offset(0, -10),
              child: _menuCard(isDark),
            ),
          ],
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    setState(() => _open = true);
    _ctrl.forward(from: 0);
  }

  Future<void> _closeMenu() async {
    if (_entry == null) return;
    await _ctrl.reverse();
    _removeEntry();
    if (mounted) setState(() => _open = false);
  }

  void _select(QuickMenuItem item) {
    // 화면 전환 위에 메뉴가 남지 않게 애니메이션 없이 즉시 제거.
    _removeEntry();
    _ctrl.value = 0;
    setState(() => _open = false);
    item.onTap();
  }

  @override
  Widget build(BuildContext context) {
    if (!ReportFabPref.get()) {
      // build 중 Overlay 조작은 금지 — 프레임 뒤로 미룬다 (설정에서 끈 직후 케이스).
      if (_entry != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _removeEntry());
      }
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final single = widget.items.length == 1;

    // docked 슬롯은 버튼 중심을 바 위젯 상단선에 맞춰 반(25px)이 아래로 걸치는데,
    // 투명 오버행이 22px 라 알약 바를 3px 침범했다 → 6px 올려 '딱 안 닿게' (형 확정).
    return Transform.translate(
      offset: const Offset(0, -6),
      child: CompositedTransformTarget(
        link: _link,
        child: _mainButton(isDark, single),
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
      // ★ IntrinsicWidth 필수 — Overlay 의 Stack 자식은 화면 전체 폭의 느슨한 제약을
      //   받는데, 행 안의 Spacer + Column stretch 가 그 폭을 다 먹어 카드가 가로를
      //   꽉 채웠다(형 제보). 내용물(라벨) 기준 폭 + minWidth 208 로 고정.
      child: IntrinsicWidth(
        child: Container(
          constraints: const BoxConstraints(minWidth: 208),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(height: 1, thickness: 1, color: line),
                    ),
                  _menuRow(widget.items[i], isDark),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuRow(QuickMenuItem item, bool isDark) {
    final primary =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF26313D);
    return InkWell(
      onTap: () => _select(item),
      child: Padding(
        // 형 시안: 타일·화살표 없이 [컬러 아이콘 + 라벨 (+ 배지)] 담백한 행
        padding: const EdgeInsets.fromLTRB(18, 13, 16, 13),
        child: Row(
          children: [
            Icon(item.icon, size: 21, color: item.color),
            const SizedBox(width: 13),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: primary,
              ),
            ),
            const SizedBox(width: 20),
            const Spacer(),
            if (item.badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFFF1F3F6),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${item.badge}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mainButton(bool isDark, bool single) {
    // 항목 1개: 그 유종 그라데이션 + 아이콘, 바로 실행.
    // 여러 개: '메뉴' 임이 읽히게 grid 아이콘 (형: 메뉴 표시였으면 좋겠다).
    final base = widget.items.first.color;
    final colors = single
        ? [base, Color.lerp(base, Colors.black, 0.22)!]
        : const [Color(0xFF3B82F6), Color(0xFF2563EB)];
    final icon = single ? widget.items.first.icon : Icons.grid_view_rounded;
    return GestureDetector(
      onTap:
          single ? widget.items.first.onTap : (_open ? _closeMenu : _openMenu),
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
          // 색 글로우(파란 그림자 α0.45·blur12) + 반투명 테두리가 지도 위에서
          // 안개처럼 번져 보였다(형 제보 '뿌옇다') → 검정 그림자 + 테두리 제거로 또렷하게.
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.22),
                blurRadius: 9,
                offset: const Offset(0, 3)),
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
