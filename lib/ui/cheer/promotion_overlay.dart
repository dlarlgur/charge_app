import 'package:flutter/material.dart';

import '../../data/services/cheer_service.dart';
import 'cheer_tier_theme.dart';

/// 뱃지 승급 오버레이 (핸드오프 4b/4c — 등급별).
/// 풀스크린 딤 + 등급색 radial 글로우 + 컨페티 4개 + 차 슬라이드-인(150ms easeOut).
void showCheerPromotionOverlay(
  BuildContext context, {
  required CheerTierTheme tier,
  required CheerStatus status,
  required VoidCallback onSeeGarage,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'cheer-promotion',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (_, __, ___) =>
        _PromotionOverlay(tier: tier, status: status, onSeeGarage: onSeeGarage),
    transitionBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _PromotionOverlay extends StatefulWidget {
  final CheerTierTheme tier;
  final CheerStatus status;
  final VoidCallback onSeeGarage;
  const _PromotionOverlay(
      {required this.tier, required this.status, required this.onSeeGarage});

  @override
  State<_PromotionOverlay> createState() => _PromotionOverlayState();
}

class _PromotionOverlayState extends State<_PromotionOverlay>
    with SingleTickerProviderStateMixin {
  // 차 슬라이드-인 + 글로우 페이드 — 과한 바운스 금지 (핸드오프 연출 노트)
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 150))
    ..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = widget.tier;
    final ink = CheerDs.ink(isDark);
    final muted = CheerDs.muted(isDark);
    final cta = t.ctaColors(isDark);

    // 컨페티 팔레트 — 등급색 + 앰버/블루 보조 (시안의 사각 컨페티 4개)
    final confetti = [
      t.ring(isDark).first,
      CheerDs.amber,
      CheerDs.gas,
      t.label(isDark),
    ];

    return Material(
      color: (isDark ? const Color(0xFF0C0E13) : const Color(0xFFF8FAFB))
          .withValues(alpha: isDark ? 0.92 : 0.94),
      child: SafeArea(
        child: Stack(
          children: [
            // 중앙 radial 글로우 (등급색)
            Center(
              child: FadeTransition(
                opacity: CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
                child: Container(
                  width: 340,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      t.glow(isDark),
                      t.glow(isDark).withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
            ),
            // 컨페티 사각형 4개 (5~7px, 회전)
            ..._confettiDots(confetti),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.promoOverline,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SlideTransition(
                      position: Tween(
                              begin: const Offset(0, 0.12), end: Offset.zero)
                          .animate(CurvedAnimation(
                              parent: _ctrl, curve: Curves.easeOut)),
                      child: t.car(width: 240, height: 96),
                    ),
                    const SizedBox(height: 18),
                    Text('「${t.name}」 뱃지 획득!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: ink)),
                    const SizedBox(height: 8),
                    Text(t.promoSub,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: muted)),
                    if (widget.status.streak >= 1) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: CheerDs.amber
                              .withValues(alpha: isDark ? 0.20 : 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.local_fire_department_rounded,
                                size: 15, color: Color(0xFFB45309)),
                            const SizedBox(width: 5),
                            Text('${widget.status.streak}일째 연속 응원',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? const Color(0xFFFACC15)
                                        : const Color(0xFFB45309))),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 248,
                      height: 50,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: cta.length > 1
                              ? LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: cta)
                              : null,
                          color: cta.length == 1 ? cta.first : null,
                        ),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onSeeGarage();
                          },
                          child: const Text('내 뱃지 보러가기',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('닫기',
                          style: TextStyle(fontSize: 13, color: muted)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _confettiDots(List<Color> colors) {
    const specs = [
      (0.18, 0.26, 6.0, 0.6),
      (0.80, 0.22, 7.0, -0.4),
      (0.12, 0.62, 5.0, 0.9),
      (0.86, 0.58, 6.0, -0.7),
    ];
    return [
      for (var i = 0; i < specs.length; i++)
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment:
                  Alignment(specs[i].$1 * 2 - 1, specs[i].$2 * 2 - 1),
              child: Transform.rotate(
                angle: specs[i].$4,
                child: Container(
                  width: specs[i].$3,
                  height: specs[i].$3,
                  color: colors[i % colors.length],
                ),
              ),
            ),
          ),
        ),
    ];
  }
}
