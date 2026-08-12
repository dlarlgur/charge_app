import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/services/cheer_service.dart';
import 'car_paint.dart';
import 'cheer_tier_theme.dart';

/// 뱃지 승급 오버레이 — handoff 2 시안 3a '개러지 드라이브인'.
/// 뒤 화면 블러 + 기존 차가 오른쪽으로 빠지고 새 차가 왼쪽에서 오버슈트로 들어오며
/// 화이트 스윕·✦·컨페티가 터진다. 1회 재생(약 3.9초).
Future<void> showCheerPromotionOverlay(
  BuildContext context, {
  required CheerTierTheme tier,
  required CheerStatus status,
  required VoidCallback onSeeGarage,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'cheer-promotion',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
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
  static const _total = 3900; // ms — 시안 5초 루프의 유효 구간(0~76%)

  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: _total));

  /// 이전 등급 차 — 첫 뱃지(쿠페)면 퇴장할 차가 없다.
  CheerTierTheme? get _prevTier => widget.tier.level > 1
      ? CheerTierTheme.byLevel(widget.tier.level - 1)
      : null;

  @override
  void initState() {
    super.initState();
    // reduce-motion 이면 연출 없이 완료 상태로 둔다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _ctrl.value = 1;
      } else {
        _ctrl.forward();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double get _ms => _ctrl.value * _total;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = widget.tier;
    final ink = CheerDs.ink(isDark);
    final sub = CheerDs.secondary(isDark);

    return Stack(
      children: [
        // 뒤 화면 블러 11px + 배경색 92%
        Positioned.fill(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 11, sigmaY: 11),
            child: Container(
              color: (isDark ? CheerDs.bgD : CheerDs.bgL)
                  .withValues(alpha: isDark ? 0.93 : 0.92),
            ),
          ),
        ),
        Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: Stack(
              children: [
                // 하단 버튼 영역(≈130px)을 뺀 나머지에서 세로 중앙 정렬 (형 지시).
                Positioned.fill(
                  bottom: 130,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 오버라인 필 — 앱 톤(블루)로 통일 (형 지시: 주황이 앱 톤과 안 맞음)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0x263B82F6)
                                : const Color(0xFFEAF2FE),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(t.promoOverline,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? const Color(0xFF93C5FD)
                                      : const Color(0xFF2563EB))),
                        ),
                        const SizedBox(height: 24),
                        _stage(isDark),
                        const SizedBox(height: 22),
                        Text('「${t.name}」 뱃지 획득!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color: ink)),
                        const SizedBox(height: 8),
                        Text(t.promoSubEffective,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13, height: 1.45, color: sub)),
                        if (widget.status.streak >= 1) ...[
                          const SizedBox(height: 14),
                          // 연속 응원 뱃지 — 앱 시그니처(⚡ 블루) 톤
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0x2660A5FA)
                                  : const Color(0xFFEAF2FE),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bolt_rounded,
                                    size: 15,
                                    color: isDark
                                        ? const Color(0xFF60A5FA)
                                        : const Color(0xFF3B82F6)),
                                const SizedBox(width: 5),
                                Text('${widget.status.streak}일째 연속 응원',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? const Color(0xFF93C5FD)
                                            : const Color(0xFF2563EB))),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // 하단 고정 버튼
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 26,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: DecoratedBox(
                          // 메인 응원하기 CTA 와 같은 블루 그라디언트 — 앱 톤 통일(형 지시).
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: CheerDs.ctaBlue,
                            ),
                          ),
                          child: TextButton(
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
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
                      SizedBox(
                        height: 42,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('닫기',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: CheerDs.muted(isDark))),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 차 스테이지 252×130 — 좁은 화면에서는 축소, 큰 화면에서는 키운다.
  /// 폰이 커질수록 하단이 허전해 보이던 문제(형 제보) — 연출 주인공인 차를
  /// 화면 높이에 비례해 최대 1.35배까지 키워 빈 공간을 채운다.
  Widget _stage(bool isDark) {
    return LayoutBuilder(builder: (_, c) {
      final byWidth = c.maxWidth / 252;
      final byHeight = MediaQuery.sizeOf(context).height / 660; // 기준 660dp
      final s = math.min(byWidth, byHeight).clamp(0.6, 1.35);
      return SizedBox(
        height: 130 * s,
        child: Transform.scale(
          scale: s,
          child: SizedBox(
            width: 252,
            height: 130,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Stack(
                clipBehavior: Clip.none,
                children: [
                  _glow(isDark),
                  _speedLine(
                      left: 6,
                      top: 44,
                      width: 230,
                      height: 3,
                      color: isDark
                          ? const Color(0xFFFDBA74)
                          : const Color(0xFFF97316),
                      maxAlpha: isDark ? 0.7 : 0.55),
                  _speedLine(
                      left: -8,
                      top: 66,
                      width: 190,
                      height: 2,
                      color: isDark ? Colors.white : const Color(0xFF94A3B8),
                      maxAlpha: isDark ? 0.4 : 0.7),
                  // 바닥 그림자
                  Positioned(
                    left: 36,
                    bottom: 0,
                    child: Container(
                      width: 180,
                      height: 14,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: RadialGradient(colors: [
                          isDark
                              ? const Color(0x8C000000)
                              : const Color(0x260F172A),
                          const Color(0x00000000),
                        ]),
                      ),
                    ),
                  ),
                  // 차 진입/퇴장은 스테이지 밖에서 보이면 안 된다 — 시안의
                  // overflow:hidden. 이게 빠지면 차가 화면을 가로질러 날아다닌다.
                  Positioned.fill(
                    child: ClipRect(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (_prevTier != null) _oldCar(_prevTier!),
                          _newCar(),
                        ],
                      ),
                    ),
                  ),
                  _sweep(isDark),
                  _twinkleAt(
                      left: 30, top: 2, size: 15, delayMs: 0, isDark: isDark),
                  _twinkleAt(
                      right: 22,
                      top: 12,
                      size: 11,
                      delayMs: 250,
                      isDark: isDark),
                  _twinkleAt(
                      right: 52,
                      top: -6,
                      size: 13,
                      delayMs: 500,
                      isDark: isDark),
                  _confetti(
                      left: 64,
                      bottom: 6,
                      size: 7,
                      square: true,
                      color: isDark
                          ? const Color(0xFF60A5FA)
                          : const Color(0xFF3B82F6),
                      delayMs: 0),
                  _confetti(
                      right: 68,
                      bottom: 4,
                      size: 6,
                      square: false,
                      color: isDark
                          ? const Color(0xFF34D399)
                          : const Color(0xFF10B981),
                      delayMs: 200),
                  _confetti(
                      left: 120,
                      bottom: 10,
                      size: 6,
                      square: false,
                      color: isDark
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFFF59E0B),
                      delayMs: 400),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  // 0,32% 0.25 → 48% 1 → 74% 0.6 (5초 기준 1600/2400/3700ms)
  Widget _glow(bool isDark) {
    double op;
    if (_ms <= 1600) {
      op = 0.25;
    } else if (_ms <= 2400) {
      op = 0.25 + 0.75 * ((_ms - 1600) / 800);
    } else if (_ms <= 3700) {
      op = 1 - 0.4 * ((_ms - 2400) / 1300);
    } else {
      op = 0.6;
    }
    final size = isDark ? 190.0 : 180.0;
    return Positioned(
      left: (252 - size) / 2,
      top: (130 - size) / 2,
      child: IgnorePointer(
        child: Opacity(
          opacity: op.clamp(0.0, 1.0),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFFF97316).withValues(alpha: isDark ? 0.35 : 0.26),
                const Color(0x00F97316),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // 0,16% 0 → 22% 1 → 42% 1 → 50% 0 (800/1100/2100/2500ms)
  Widget _speedLine({
    required double left,
    required double top,
    required double width,
    required double height,
    required Color color,
    required double maxAlpha,
  }) {
    double op;
    if (_ms <= 800) {
      op = 0;
    } else if (_ms <= 1100) {
      op = (_ms - 800) / 300;
    } else if (_ms <= 2100) {
      op = 1;
    } else if (_ms <= 2500) {
      op = 1 - (_ms - 2100) / 400;
    } else {
      op = 0;
    }
    if (op <= 0) return const SizedBox.shrink();
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Opacity(
          opacity: op.clamp(0.0, 1.0),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(colors: [
                color.withValues(alpha: 0),
                color.withValues(alpha: maxAlpha),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // buOut — 0~700ms 정지, 850ms 에 -14 반동, 1400ms 에 +270 퇴장
  Widget _oldCar(CheerTierTheme prev) {
    if (_ms >= 1450) return const SizedBox.shrink();
    double dx;
    if (_ms <= 700) {
      dx = 0;
    } else if (_ms <= 850) {
      dx = -14 * ((_ms - 700) / 150);
    } else {
      final k = Curves.easeIn.transform(((_ms - 850) / 550).clamp(0.0, 1.0));
      dx = -14 + 284 * k;
    }
    return Positioned(
      left: 6 + dx,
      top: 14,
      child: IgnorePointer(child: CarImage(tier: prev, width: 240, height: 96)),
    );
  }

  // buIn — 1500ms 까지 -280 대기, 2100ms 에 +12 오버슈트, 2350ms 에 제자리
  Widget _newCar() {
    double dx;
    if (_ms <= 1500) {
      dx = -280;
    } else if (_ms <= 2100) {
      final k = Curves.easeOut.transform((_ms - 1500) / 600);
      dx = -280 + 292 * k;
    } else if (_ms <= 2350) {
      final k = Curves.easeOut.transform((_ms - 2100) / 250);
      dx = 12 - 12 * k;
    } else {
      dx = 0;
    }
    return Positioned(
      left: 6 + dx,
      top: 14,
      child: IgnorePointer(
          child: CarImage(tier: widget.tier, width: 240, height: 96)),
    );
  }

  // buSweep — 2300ms 부터 3200ms 까지 차 위를 비스듬히 훑는다
  Widget _sweep(bool isDark) {
    if (_ms < 2300 || _ms > 3200) return const SizedBox.shrink();
    final k = (_ms - 2300) / 900;
    final op = k < 0.33 ? k / 0.33 : 1 - (k - 0.33) / 0.67;
    return Positioned(
      left: 6,
      top: 10,
      child: IgnorePointer(
        child: SizedBox(
          width: 240,
          height: 104,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: -108 + k * 384,
                  top: -10,
                  bottom: -10,
                  width: 77, // 32%
                  child: Opacity(
                    opacity: op.clamp(0.0, 1.0),
                    child: Transform(
                      transform: Matrix4.skewX(-0.31),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: isDark ? 0.7 : 0.85),
                            Colors.white.withValues(alpha: 0),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // buTwinkle — 2200ms 부터 1.6초, 2600ms 에 최대(scale 1.25 · 20° 회전)
  Widget _twinkleAt({
    double? left,
    double? right,
    required double top,
    required double size,
    required double delayMs,
    required bool isDark,
  }) {
    final m = _ms - delayMs;
    if (m < 2200 || m > 3800) return const SizedBox.shrink();
    double op, sc, rot;
    if (m <= 2600) {
      final k = (m - 2200) / 400;
      op = k;
      sc = 0.3 + 0.95 * k;
      rot = 20 * k;
    } else if (m <= 3200) {
      final k = (m - 2600) / 600;
      op = 1 - 0.5 * k;
      sc = 1.25 - 0.45 * k;
      rot = 20 + 15 * k;
    } else {
      final k = (m - 3200) / 600;
      op = 0.5 * (1 - k);
      sc = 0.8;
      rot = 35;
    }
    if (op <= 0) return const SizedBox.shrink();
    return Positioned(
      left: left,
      right: right,
      top: top,
      child: IgnorePointer(
        child: Opacity(
          opacity: op.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: rot * math.pi / 180,
            child: Transform.scale(
              scale: sc,
              child: Text('✦',
                  style: TextStyle(
                      fontSize: size,
                      height: 1,
                      color: isDark ? const Color(0xFFFDE68A) : CheerDs.amber)),
            ),
          ),
        ),
      ),
    );
  }

  // buPop — 2100ms 부터 솟아올라 3700ms 에 사라진다
  Widget _confetti({
    double? left,
    double? right,
    required double bottom,
    required double size,
    required bool square,
    required Color color,
    required double delayMs,
  }) {
    final m = _ms - delayMs;
    if (m < 2100 || m > 3700) return const SizedBox.shrink();
    double op, sc, dy;
    if (m <= 2500) {
      final k = Curves.easeOut.transform((m - 2100) / 400);
      op = k;
      sc = k;
      dy = 26 * k;
    } else {
      final k = ((m - 2500) / 1200).clamp(0.0, 1.0);
      op = k < 0.5 ? 1 : 1 - (k - 0.5) / 0.5;
      sc = 1 - 0.3 * k;
      dy = 26 + 22 * k;
    }
    if (op <= 0) return const SizedBox.shrink();
    return Positioned(
      left: left,
      right: right,
      bottom: bottom + dy,
      child: IgnorePointer(
        child: Opacity(
          opacity: op.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: sc,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: square ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: square ? BorderRadius.circular(2) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
