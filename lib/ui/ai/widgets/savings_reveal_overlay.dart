import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// AI 추천 결과 진입 시 "이만큼 절약"을 게임 보상풍으로 1회 강조하는 오버레이.
/// - 등장: 스케일 팝(elasticOut) + 뒤 글로우 + 반짝(스파클) 애니메이션
/// - 종료: 1.9초 후 자동 페이드아웃 (탭하면 즉시 닫힘)
/// 결과 화면 Stack 최상단에 올려두면 스스로 사라진다.
class SavingsRevealOverlay extends StatefulWidget {
  final String caption; // 작은 줄 (예: '4분 더 걸리지만' / '주변 평균 대비')
  final String headline; // 큰 줄 (예: '28,000원 절감!')
  const SavingsRevealOverlay({
    super.key,
    required this.caption,
    required this.headline,
  });

  /// 절감액 헤드라인 포맷 헬퍼
  static String won(int v) => '${NumberFormat('#,###').format(v)}원';

  @override
  State<SavingsRevealOverlay> createState() => _SavingsRevealOverlayState();
}

class _SavingsRevealOverlayState extends State<SavingsRevealOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _in; // 등장 팝
  late final AnimationController _out; // 페이드아웃
  late final AnimationController _sparkle; // 반짝 루프
  Timer? _autoClose;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _in = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _out = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _sparkle = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HapticFeedback.mediumImpact();
      _in.forward();
      _autoClose = Timer(const Duration(milliseconds: 1900), _dismiss);
    });
  }

  void _dismiss() {
    if (_closing || !mounted) return;
    _closing = true;
    _autoClose?.cancel();
    _out.forward().whenComplete(() {
      if (mounted) setState(() {}); // _out.isCompleted → 자체 제거
    });
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    _in.dispose();
    _out.dispose();
    _sparkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_out.isCompleted) return const SizedBox.shrink();
    final pop = CurvedAnimation(parent: _in, curve: Curves.elasticOut);
    final fadeIn = CurvedAnimation(
        parent: _in, curve: const Interval(0, 0.35, curve: Curves.easeOut));
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismiss,
        child: FadeTransition(
          opacity: ReverseAnimation(_out),
          child: FadeTransition(
            opacity: fadeIn,
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              alignment: Alignment.center,
              child: ScaleTransition(
                scale: Tween(begin: 0.6, end: 1.0).animate(pop),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // 뒤 글로우 (연둣빛 방사형)
                    Container(
                      width: 320,
                      height: 320,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF34D399).withValues(alpha: 0.35),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    // 스파클 6개 — 원 둘레를 돌며 깜빡임
                    AnimatedBuilder(
                      animation: _sparkle,
                      builder: (_, __) {
                        final t = _sparkle.value;
                        return Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: List.generate(6, (i) {
                            final ang = (i / 6) * 2 * math.pi + t * 2 * math.pi;
                            final r = 120 + 8 * math.sin(t * 2 * math.pi + i);
                            final op =
                                0.35 + 0.65 * ((math.sin(t * 2 * math.pi * 2 + i * 1.3) + 1) / 2);
                            return Transform.translate(
                              offset: Offset(
                                  r * math.cos(ang), r * math.sin(ang) * 0.72),
                              child: Opacity(
                                opacity: op,
                                child: Icon(Icons.auto_awesome_rounded,
                                    size: i.isEven ? 16 : 11,
                                    color: const Color(0xFFFFD54F)),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                    // 본문
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25)),
                          ),
                          child: const Text('AI 추천',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 1)),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.caption,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // 헤드라인 — 골드→그린 그라데이션 대형 텍스트
                        ShaderMask(
                          shaderCallback: (rect) => const LinearGradient(
                            colors: [Color(0xFFFFE082), Color(0xFF6EE7B7)],
                          ).createShader(rect),
                          child: Text(
                            widget.headline,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
