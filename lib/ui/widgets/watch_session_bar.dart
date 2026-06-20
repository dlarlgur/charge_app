import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/helpers.dart';
import '../../data/services/watch_service.dart';
import '../detail/ev_detail_screen.dart';

class WatchSessionBar extends StatefulWidget {
  const WatchSessionBar({super.key});

  @override
  State<WatchSessionBar> createState() => _WatchSessionBarState();
}

class _WatchSessionBarState extends State<WatchSessionBar> {
  Timer? _timer;
  bool _extending = false;

  static const _kBlue = Color(0xFF1D6FE0);
  static const _kBlueLight = Color(0xFFEEF4FF);

  @override
  void initState() {
    super.initState();
    WatchService().sessionChanged.addListener(_onSessionChanged);
    _startTimer();
  }

  @override
  void dispose() {
    WatchService().sessionChanged.removeListener(_onSessionChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (WatchService().session == null) return;
    // 진입 즉시 최신 자리 수 조회
    WatchService().refreshAvail();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      WatchService().refreshAvail();
    });
  }

  String _formatRemaining(Duration d) {
    if (d.isNegative) return '만료됨';
    return fmtMin(d.inMinutes.clamp(0, 9999));
  }

  Future<void> _extend() async {
    if (_extending) return;
    setState(() => _extending = true);
    final ok = await WatchService().extend();
    if (mounted) {
      setState(() => _extending = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('연장에 실패했어요. 다시 시도해주세요.')),
        );
      }
    }
  }

  void _openDetail() {
    final statId = WatchService().session?.statId;
    if (statId == null) return;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => EvDetailScreen(stationId: statId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = WatchService().session;
    if (session == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 시인성 ↑ — 은은한 블루 틴트(흰 콘텐츠와 구분) + 또렷한 보더(아래 Container)
    final bg = isDark ? const Color(0xFF18222F) : const Color(0xFFF3F8FF);
    final iconBg = isDark ? _kBlue.withValues(alpha: 0.18) : _kBlueLight;
    final primary = isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
    final muted = isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);
    final offColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);

    final remaining = session.remaining;
    final timeStr = _formatRemaining(remaining);
    final avail = session.currentAvail;

    return SafeArea(
      top: false,
      child: Padding(
        // 하단 플로팅 — 바텀 네비 바로 위에 떠서 스크롤해도 항상 보임.
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          elevation: 12,
          shadowColor: _kBlue.withValues(alpha: 0.38),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: _kBlue.withValues(alpha: isDark ? 0.55 : 0.5),
                  width: 1.4),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                children: [
                  // ── 왼쪽: 아이콘 + 텍스트 ──
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.radar_rounded, size: 18, color: _kBlue),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6, height: 6,
                              decoration: const BoxDecoration(
                                color: _kBlue,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              '자리 변동 알림 중',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _kBlue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          session.stationName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          avail != null
                              ? '$timeStr 남음  ·  현재 ${avail}자리'
                              : '$timeStr 남음',
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // ── 오른쪽: 액션 버튼들 ──
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SmallBtn(
                            label: _extending ? '...' : '+30분',
                            color: _kBlue,
                            filled: false,
                            isDark: isDark,
                            onTap: _extending ? null : _extend,
                          ),
                          const SizedBox(width: 5),
                          _SmallBtn(
                            label: '상세',
                            color: _kBlue,
                            filled: false,
                            isDark: isDark,
                            onTap: _openDetail,
                          ),
                          const SizedBox(width: 5),
                          _SmallBtn(
                            label: '끄기',
                            color: offColor,
                            filled: false,
                            isDark: isDark,
                            onTap: () => WatchService().stop(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  final bool isDark;
  final VoidCallback? onTap;

  const _SmallBtn({
    required this.label,
    required this.color,
    required this.filled,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: isDark ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: filled ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}
