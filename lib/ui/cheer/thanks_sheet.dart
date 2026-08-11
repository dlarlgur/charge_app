import 'package:flutter/material.dart';

import '../../data/services/cheer_service.dart';
import 'cheer_tier_theme.dart';

/// 광고 완주 감사 바텀시트 (핸드오프 3d).
/// 로고 그라데이션 원 + 감사 카피(회차별) + 오늘/연속 칩 + 응원 게이지 미니바
/// + "한 번 더 응원하기"(3회차엔 숨김).
Future<void> showCheerThanksSheet(
  BuildContext context, {
  required CheerStatus status,
  required void Function(CheerStatus st) onStatus,
  /// '한 번 더' — 시트가 닫힌 뒤 살아있는 화면 context 로 다음 회차를 돌린다.
  /// (시트 자신의 context 는 pop 순간 죽어서 다음 팝업·연출이 통째로 증발한다)
  VoidCallback? onAgain,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: isDark
        ? const Color(0xFF0C0E13).withValues(alpha: 0.72)
        : const Color(0xFF2D3748).withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (ctx) =>
        _ThanksSheet(
            status: status, isDark: isDark, onStatus: onStatus, onAgain: onAgain),
  );
}

class _ThanksSheet extends StatelessWidget {
  final CheerStatus status;
  final bool isDark;
  final void Function(CheerStatus st) onStatus;
  final VoidCallback? onAgain;
  const _ThanksSheet(
      {required this.status,
      required this.isDark,
      required this.onStatus,
      this.onAgain});

  String get _body {
    // 회차별 카피 — 시안 문구 유지. 2회차도 '서버가 쌩쌩' 대신 같은 톤으로(형 확정).
    switch (status.today) {
      case 1:
        return '응원 1개가 서버에 전해졌어요.\n개발자 힘이 불끈! 오늘도 쌩쌩하게 달릴게요.';
      case 2:
        return '오늘 두 번째 응원이에요.\n개발자 힘이 불끈! 오늘도 쌩쌩하게 달릴게요.';
      default:
        return '오늘 응원 만땅! 최고의 서포터예요.\n개발자 힘이 불끈! 내일도 쌩쌩하게 달릴게요.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = CheerDs.ink(isDark);
    final remaining = (status.dailyLimit - status.today).clamp(0, 3);

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        // 딤 위에 뜨는 시트라 불투명이어야 한다(반투명 카드색이면 딤이 비친다)
        color: CheerDs.cardSolid(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Stack(
        children: [
          // 그린 radial 글로우 — 상단 중앙
          Positioned(
            top: -60,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      CheerDs.ev.withValues(alpha: isDark ? 0.16 : 0.12),
                      CheerDs.ev.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 로고 그라데이션 원 64 + volunteer_activism
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2563EB), Color(0xFF10B981)],
                    ),
                  ),
                  child: const Icon(Icons.volunteer_activism_rounded,
                      color: Colors.white, size: 30),
                ),
                const SizedBox(height: 14),
                Text('응원해주셔서 감사합니다!',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
                const SizedBox(height: 8),
                Text(_body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: CheerDs.secondary(isDark))),
                const SizedBox(height: 14),
                // 칩 2개 — 오늘 N/3 (그린 틴트) · N일 연속 (앰버 틴트)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _chip(Icons.check_rounded,
                        '오늘 ${status.today} / ${status.dailyLimit}',
                        fg: isDark
                            ? CheerDs.success
                            : const Color(0xFF059669),
                        bg: isDark
                            ? const Color(0x2610B981)
                            : const Color(0xFFD1FAE5)),
                    if (status.streak >= 1) ...[
                      const SizedBox(width: 8),
                      _chip(Icons.local_fire_department_rounded,
                          '${status.streak}일 연속',
                          fg: isDark
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFFB45309),
                          bg: isDark
                              ? const Color(0x26F59E0B)
                              : const Color(0xFFFEF3C7)),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                // 응원 게이지 미니바
                Row(
                  children: [
                    Text('오늘의 응원 게이지',
                        style: TextStyle(
                            fontSize: 12, color: CheerDs.secondary(isDark))),
                    const Spacer(),
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: '${status.serverCount}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: ink)),
                      TextSpan(
                          text: ' / ${status.serverGoal}',
                          style: TextStyle(
                              fontSize: 12,
                              color: CheerDs.secondary(isDark))),
                    ])),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 6,
                    child: Stack(children: [
                      Container(color: CheerDs.iconBg(isDark)),
                      FractionallySizedBox(
                        widthFactor:
                            (status.serverPct / 100).clamp(0.015, 1.0),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                                colors: [CheerDs.gas, CheerDs.ev]),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 18),
                if (remaining > 0)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: CheerDs.ev,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onAgain?.call();
                      },
                      child: Text('한 번 더 응원하기 · $remaining번 남음',
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('닫기',
                      style: TextStyle(
                          fontSize: 13, color: CheerDs.muted(isDark))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text,
          {required Color fg, required Color bg}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ]),
      );
}
