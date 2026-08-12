import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/services/cheer_service.dart';
import 'car_paint.dart';
import 'cheer_screen.dart';
import 'cheer_tier_theme.dart';

/// 설정 · 응원하기 진입 카드 — handoff 3 (CheerEntryRow.html).
/// 일반 리스트 행이 아니라 강조 카드로, 알림 설정보다 위에 놓인다.
/// 카드도 우측 버튼도 응원 메인으로 간다 — 광고는 응원 화면에서 시작한다.
class CheerEntryCard extends StatefulWidget {
  const CheerEntryCard({super.key});

  @override
  State<CheerEntryCard> createState() => _CheerEntryCardState();
}

class _CheerEntryCardState extends State<CheerEntryCard>
    with SingleTickerProviderStateMixin {
  /// 우상단 블루 라디얼 글로우 — 4s ease-in-out, opacity 0.5→1
  late final AnimationController _glow = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4000))
    ..repeat();

  @override
  void initState() {
    super.initState();
    CarPaintService.instance.init();
    CheerService.instance.preload();
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  void _openCheer() {
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => const CheerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<CheerStatus?>(
      valueListenable: CheerService.instance.statusNotifier,
      builder: (_, st, __) {
        final total = st?.total ?? CheerService.instance.cachedTotal;
        final tier = CheerTierTheme.of(total);
        final today = st?.today ?? 0;
        final limit = st?.dailyLimit ?? 3;
        final done = today >= limit;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _openCheer,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [Color(0x2E3B82F6), Color(0x0F10B981)]
                      : const [Color(0xFFEEF6FF), Color(0xFFE7FAF3)],
                ),
                border: Border.all(
                  color: isDark
                      ? const Color(0x5A60A5FA)
                      : const Color(0xFFCFE4F7),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Positioned(
                      right: -26,
                      top: -26,
                      child: AnimatedBuilder(
                        animation: _glow,
                        builder: (_, child) => Opacity(
                          opacity: 0.5 +
                              0.5 *
                                  (0.5 -
                                      0.5 *
                                          math.cos(_glow.value * 2 * math.pi)),
                          child: child,
                        ),
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [
                              const Color(0xFF3B82F6)
                                  .withValues(alpha: isDark ? 0.30 : 0.22),
                              const Color(0x003B82F6),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 66,
                                height: 26,
                                child: tier == null
                                    ? CheerTierTheme.byLevel(1).silhouette(
                                        isDark
                                            ? const Color(0xFF64748B)
                                            : const Color(0xFFBFD4EA))
                                    : CarImage(tier: tier),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('전기차 기름차 응원하기',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.2,
                                            color: isDark
                                                ? const Color(0xFFF1F5F9)
                                                : const Color(0xFF0F172A))),
                                    const SizedBox(height: 2),
                                    Text(
                                        tier == null
                                            ? '첫 응원을 기다리고 있어요'
                                            : '${tier.name} · 누적 $total회',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? const Color(0xFF93C5FD)
                                                : const Color(0xFF2563EB))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 11),
                          Row(
                            children: [
                              // 한도는 원격설정으로 바뀐다 — 도트가 그만큼 늘어나면
                              // 320dp 에서 줄이 터진다. 6회 이상이면 도트를 접고
                              // 'n/한도' 숫자만 남긴다(숫자가 이미 같은 정보).
                              if (limit <= 5) ...[
                                for (var i = 0; i < limit; i++) ...[
                                  if (i > 0) const SizedBox(width: 5),
                                  _dot(i < today, isDark),
                                ],
                                const SizedBox(width: 9),
                              ],
                              // Expanded 여야 남는 폭을 텍스트가 먹고 버튼이 오른쪽
                              // 끝으로 밀린다 — Flexible 이면 버튼이 텍스트에 붙는다.
                              Expanded(
                                child: Text('오늘 응원 $today/$limit',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? const Color(0xFF94A3B8)
                                            : const Color(0xFF5B7A9C))),
                              ),
                              const SizedBox(width: 8),
                              _cta(done, isDark),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dot(bool filled, bool isDark) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled
              ? (isDark ? const Color(0xFF60A5FA) : const Color(0xFF3B82F6))
              : null,
          border: filled
              ? null
              : Border.all(
                  color: isDark
                      ? const Color(0x9993C5FD)
                      : const Color(0xFF93C5FD),
                  width: 1.5),
        ),
      );

  /// 오늘 다 채웠으면 버튼 대신 '만땅' 표시 — 눌러도 못 하는 버튼은 안 둔다.
  /// 버튼도 카드와 같이 응원 메인으로 간다 — 여기서 바로 광고를 띄우면 설정 화면에서
  /// 맥락 없이 전면 광고가 뜬다(형 지시: 응원 페이지에서 시작).
  Widget _cta(bool done, bool isDark) {
    if (done) {
      return Text('오늘 만땅!',
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? const Color(0xFF93C5FD)
                  : const Color(0xFF2563EB)));
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: _openCheer,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Text('응원하기',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
