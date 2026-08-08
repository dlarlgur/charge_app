import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/cheer_service.dart';
import '../widgets/cheer_badge_car.dart';

/// 전기차 기름차 응원하기 — 보상형 광고 1회 = 응원 1개.
/// 하트 게이지(이번 달 서버 응원) + 오늘 3칸 + 개인 뱃지.
/// 강제성 없는 응원 기능이라 모든 실패는 조용히, 화면은 따뜻하게.
class CheerScreen extends StatefulWidget {
  const CheerScreen({super.key});

  @override
  State<CheerScreen> createState() => _CheerScreenState();
}

class _CheerScreenState extends State<CheerScreen>
    with TickerProviderStateMixin {
  static const _rose = Color(0xFFF43F5E);
  static const _roseSoft = Color(0xFFFB7185);

  CheerStatus? _status;
  bool _loading = true;
  bool _failed = false;
  bool _showing = false; // 광고 표시 중 중복 탭 방지

  // 게이지 채움 애니메이션 (이전 값 → 새 값)
  late final AnimationController _fillCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));
  double _fillFrom = 0;
  double _fillTo = 0;

  // 물결 — 은은하게 계속 흐른다
  late final AnimationController _waveCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 3))
    ..repeat();

  @override
  void initState() {
    super.initState();
    _load();
    CheerService.instance.preload(onChanged: _refresh);
  }

  @override
  void dispose() {
    _fillCtrl.dispose();
    _waveCtrl.dispose();
    CheerService.instance.disposeAd();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final st = await CheerService.instance.status();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = st == null;
      _status = st;
    });
    if (st != null) _animateFillTo(st.serverPct / 100);
  }

  void _animateFillTo(double target) {
    _fillFrom = _fillTo;
    _fillTo = target.clamp(0.0, 1.0);
    _fillCtrl.forward(from: 0);
  }

  bool _earnedThisRound = false;
  CheerBadge? _newBadgeThisRound; // 이번 시청으로 승급했으면 그 뱃지

  Future<void> _watchAd() async {
    final svc = CheerService.instance;
    if (_showing || !svc.adReady) return;
    setState(() => _showing = true);
    final levelBefore = _status?.badge.level ?? 0;
    await svc.show(
      onEarned: () async {
        _earnedThisRound = true;
        final st = await svc.cheer();
        if (st != null && st.badge.level > levelBefore) {
          _newBadgeThisRound = st.badge;
        }
        if (!mounted || st == null) return;
        setState(() => _status = st);
        _animateFillTo(st.serverPct / 100);
      },
      onDismissed: () {
        if (!mounted) return;
        setState(() => _showing = false);
        final st = _status;
        if (st != null && !st.doneToday) {
          CheerService.instance.preload(onChanged: _refresh);
        }
        // 광고 닫힌 직후 축하 연출 — 광고 위에선 안 보이므로 여기서.
        // 중간 이탈(리워드 미획득)은 아무것도 안 띄운다 (부담 금지).
        if (_earnedThisRound) {
          _earnedThisRound = false;
          final nb = _newBadgeThisRound;
          _newBadgeThisRound = null;
          if (st != null) _celebrate(st, newBadge: nb);
        }
      },
    );
  }

  /// 광고 완주 축하 — 횟수(1/2/3회차)·연속 응원에 따라 멘트가 달라지고,
  /// 승급 순간엔 새 차 뱃지가 등장하는 '뱃지 획득' 버전으로 바뀐다.
  void _celebrate(CheerStatus st, {CheerBadge? newBadge}) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'cheer-celebration',
      barrierColor: Colors.black.withValues(alpha: 0.60),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) =>
          _CheerCelebration(status: st, newBadge: newBadge),
      transitionBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('전기차 기름차 응원하기',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? _retryView(isDark)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _serverGaugeCard(isDark),
                    const SizedBox(height: 14),
                    _cheerCard(isDark),
                    const SizedBox(height: 14),
                    _badgeCard(isDark),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '광고 수익은 전액 서버 운영비에 보태져요.\n'
                        '부담 갖지 마세요 — 앱이 마음에 든 날, 한 번씩이면 충분해요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _retryView(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('응원 정보를 불러오지 못했어요',
                style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted)),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );

  Widget _card(bool isDark, Widget child) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? AppColors.darkCardBorder : const Color(0xFFE8ECF0),
            width: 1,
          ),
        ),
        child: child,
      );

  // ─── 히어로: 이번 달 서버 응원 게이지 ───
  Widget _serverGaugeCard(bool isDark) {
    final st = _status!;
    final ink = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    return _card(
      isDark,
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          children: [
            SizedBox(
              width: 158,
              height: 148,
              child: AnimatedBuilder(
                animation: Listenable.merge([_fillCtrl, _waveCtrl]),
                builder: (_, __) {
                  final t = Curves.easeOutCubic.transform(_fillCtrl.value);
                  final fill = _fillFrom + (_fillTo - _fillFrom) * t;
                  return CustomPaint(
                    painter: _HeartGaugePainter(
                      fill: fill,
                      wavePhase: _waveCtrl.value * 2 * math.pi,
                      isDark: isDark,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            AnimatedBuilder(
              animation: _fillCtrl,
              builder: (_, __) {
                final t = Curves.easeOutCubic.transform(_fillCtrl.value);
                final pct = (_fillFrom + (_fillTo - _fillFrom) * t) * 100;
                return Text(
                  '${pct.round()}%',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: _rose,
                    height: 1.1,
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text('이번 달 서버 응원 게이지',
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 3),
            Text(
              st.serverPct >= 100
                  ? '서버 만땅! 모두의 응원 ${st.serverCount}개, 최고예요'
                  : '모두의 응원 ${st.serverCount} / ${st.serverGoal}',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 오늘의 응원 + 광고 버튼 ───
  Widget _cheerCard(bool isDark) {
    final st = _status!;
    final svc = CheerService.instance;
    final ink = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    return _card(
      isDark,
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('오늘의 응원',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: ink)),
                ),
                // 오늘 3칸 — 본 만큼 하트가 채워진다
                ...List.generate(st.dailyLimit.clamp(0, 5), (i) {
                  final filled = i < st.today;
                  return Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: AnimatedScale(
                      scale: filled ? 1 : 0.92,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutBack,
                      child: CustomPaint(
                        size: const Size(20, 19),
                        painter: _MiniHeartPainter(
                            filled: filled, isDark: isDark),
                      ),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 14),
            _cheerButton(st, svc, isDark),
            const SizedBox(height: 10),
            Text(
              st.doneToday
                  ? '내일 또 응원할 수 있어요'
                  : '광고 한 편을 끝까지 보면 응원 1개가 쌓여요',
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cheerButton(CheerStatus st, CheerService svc, bool isDark) {
    final remaining = (st.dailyLimit - st.today).clamp(0, st.dailyLimit);

    if (st.doneToday) {
      return Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _rose.withValues(alpha: isDark ? 0.16 : 0.09),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(17, 16),
              painter: _MiniHeartPainter(filled: true, isDark: isDark),
            ),
            const SizedBox(width: 8),
            const Text('오늘 응원 만땅! 고마워요',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: _rose)),
          ],
        ),
      );
    }

    final ready = svc.adReady && !_showing;
    final label = _showing
        ? '광고 재생 중…'
        : svc.adReady
            ? '광고 보고 응원하기'
            : svc.adLoading
                ? '광고 불러오는 중…'
                : '광고를 불러올 수 없어요 · 다시 시도';

    return GestureDetector(
      onTap: ready
          ? _watchAd
          : (!svc.adLoading && !_showing
              ? () => svc.preload(onChanged: _refresh)
              : null),
      child: AnimatedOpacity(
        opacity: ready ? 1 : 0.55,
        duration: const Duration(milliseconds: 250),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_roseSoft, _rose],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: _rose.withValues(alpha: isDark ? 0.35 : 0.28),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (svc.adLoading || _showing) ...[
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 9),
              ] else ...[
                CustomPaint(
                  size: const Size(17, 16),
                  painter: _MiniHeartPainter(
                      filled: true, isDark: isDark, white: true),
                ),
                const SizedBox(width: 8),
              ],
              Text(label,
                  style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.2)),
              if (ready) ...[
                const SizedBox(width: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text('$remaining번 남음',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── 내 뱃지 ───
  Widget _badgeCard(bool isDark) {
    final st = _status!;
    final badge = st.badge;
    final next = st.nextBadge;
    final ink = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final tierColor = cheerTierColor(badge.level, fallback: muted);

    // 다음 등급까지 진행률 (현 등급 문턱 → 다음 문턱 구간 기준)
    double progress = 1;
    if (next != null) {
      final from = badge.threshold;
      progress = ((st.total - from) / (next.threshold - from)).clamp(0.0, 1.0);
    }

    return _card(
      isDark,
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 68,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tierColor.withValues(alpha: isDark ? 0.20 : 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: CustomPaint(
                    size: const Size(54, 30),
                    painter: CheerBadgeCarPainter(
                        level: badge.level, color: tierColor, isDark: isDark),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        badge.level > 0 ? badge.name : '아직 뱃지가 없어요',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: badge.level > 0 ? tierColor : ink,
                            letterSpacing: -0.2),
                      ),
                      const SizedBox(height: 2),
                      Text('누적 응원 ${st.total}회',
                          style: TextStyle(fontSize: 12, color: muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 7,
                child: Stack(
                  children: [
                    Container(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFEEF1F5)),
                    FractionallySizedBox(
                      widthFactor: progress == 0 ? 0.015 : progress,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                              colors: [_roseSoft, _rose]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              next != null
                  ? '다음 뱃지 「${next.name}」까지 ${next.threshold - st.total}회'
                  : '최고 등급 달성! 늘 고마워요',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: next != null ? muted : _rose),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 커스텀 하트 게이지 — 물결로 차오르는 하트 (이모지 대신 직접 그린 심볼) ───
class _HeartGaugePainter extends CustomPainter {
  final double fill; // 0~1
  final double wavePhase;
  final bool isDark;

  const _HeartGaugePainter({
    required this.fill,
    required this.wavePhase,
    required this.isDark,
  });

  static const _rose = Color(0xFFF43F5E);
  static const _roseSoft = Color(0xFFFB7185);

  Path _heartPath(Size s) {
    final w = s.width, h = s.height;
    final p = Path()
      ..moveTo(0.5 * w, 0.30 * h)
      ..cubicTo(0.5 * w, 0.20 * h, 0.42 * w, 0.08 * h, 0.28 * w, 0.08 * h)
      ..cubicTo(0.10 * w, 0.08 * h, 0.03 * w, 0.24 * h, 0.03 * w, 0.36 * h)
      ..cubicTo(0.03 * w, 0.57 * h, 0.22 * w, 0.74 * h, 0.5 * w, 0.94 * h)
      ..cubicTo(0.78 * w, 0.74 * h, 0.97 * w, 0.57 * h, 0.97 * w, 0.36 * h)
      ..cubicTo(0.97 * w, 0.24 * h, 0.90 * w, 0.08 * h, 0.72 * w, 0.08 * h)
      ..cubicTo(0.58 * w, 0.08 * h, 0.5 * w, 0.20 * h, 0.5 * w, 0.30 * h)
      ..close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final heart = _heartPath(size);

    // 은은한 글로우 — 다크에서 특히 예쁘다
    canvas.drawPath(
      heart,
      Paint()
        ..color = _rose.withValues(alpha: isDark ? 0.28 : 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );

    canvas.save();
    canvas.clipPath(heart);

    // 빈 속 — 옅은 장미빛
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _rose.withValues(alpha: isDark ? 0.14 : 0.08),
    );

    // 물결 액체 — fill 만큼 아래서부터 차오른다 (하트 세로 범위 0.08~0.94)
    final level =
        (0.94 - (0.94 - 0.08) * fill.clamp(0.0, 1.0)) * size.height;
    const amp = 3.5;
    final liquid = Path()..moveTo(0, level);
    for (double x = 0; x <= size.width; x += 3) {
      liquid.lineTo(
          x,
          level +
              math.sin(wavePhase + x / size.width * 2 * math.pi) * amp);
    }
    liquid
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      liquid,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_roseSoft, _rose],
        ).createShader(Offset.zero & size),
    );

    // 액체 표면 하이라이트 선
    final surface = Path()..moveTo(0, level);
    for (double x = 0; x <= size.width; x += 3) {
      surface.lineTo(
          x,
          level +
              math.sin(wavePhase + x / size.width * 2 * math.pi) * amp);
    }
    canvas.drawPath(
      surface,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.45),
    );
    canvas.restore();

    // 하트 윤곽
    canvas.drawPath(
      heart,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = _rose.withValues(alpha: isDark ? 0.85 : 0.65),
    );

    // 좌상단 유리 반사 + 반짝이 두 개
    final gloss = Paint()..color = Colors.white.withValues(alpha: 0.35);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(size.width * 0.30, size.height * 0.22),
            width: size.width * 0.14,
            height: size.height * 0.09),
        gloss);
    _sparkle(canvas, Offset(size.width * 0.86, size.height * 0.10), 5.5);
    _sparkle(canvas, Offset(size.width * 0.95, size.height * 0.24), 3.2);
  }

  void _sparkle(Canvas canvas, Offset c, double r) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(
        p, Paint()..color = _roseSoft.withValues(alpha: isDark ? 0.9 : 0.7));
  }

  @override
  bool shouldRepaint(_HeartGaugePainter old) =>
      old.fill != fill || old.wavePhase != wavePhase || old.isDark != isDark;
}

// ─── 미니 하트 — 오늘 3칸·버튼·뱃지 공용 ───
class _MiniHeartPainter extends CustomPainter {
  final bool filled;
  final bool isDark;
  final bool white;

  const _MiniHeartPainter({
    required this.filled,
    required this.isDark,
    this.white = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Path()
      ..moveTo(0.5 * w, 0.32 * h)
      ..cubicTo(0.5 * w, 0.18 * h, 0.40 * w, 0.06 * h, 0.27 * w, 0.06 * h)
      ..cubicTo(0.09 * w, 0.06 * h, 0.02 * w, 0.24 * h, 0.02 * w, 0.36 * h)
      ..cubicTo(0.02 * w, 0.58 * h, 0.22 * w, 0.74 * h, 0.5 * w, 0.95 * h)
      ..cubicTo(0.78 * w, 0.74 * h, 0.98 * w, 0.58 * h, 0.98 * w, 0.36 * h)
      ..cubicTo(0.98 * w, 0.24 * h, 0.91 * w, 0.06 * h, 0.73 * w, 0.06 * h)
      ..cubicTo(0.60 * w, 0.06 * h, 0.5 * w, 0.18 * h, 0.5 * w, 0.32 * h)
      ..close();

    if (filled) {
      final paint = Paint();
      if (white) {
        paint.color = Colors.white;
      } else {
        paint.shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFB7185), Color(0xFFF43F5E)],
        ).createShader(Offset.zero & size);
      }
      canvas.drawPath(p, paint);
    } else {
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xFFF43F5E)
              .withValues(alpha: isDark ? 0.45 : 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(_MiniHeartPainter old) =>
      old.filled != filled || old.isDark != isDark || old.white != white;
}

// ─── 광고 완주 축하 연출 — 버스트 + 하트 팝 + 횟수별 멘트 ───
// "봐줘서 고맙다"를 확실하게, 그러나 2.6초 안에 알아서 사라진다 (방해 금지).
class _CheerCelebration extends StatefulWidget {
  final CheerStatus status;
  final CheerBadge? newBadge; // null 아니면 '뱃지 획득' 연출
  const _CheerCelebration({required this.status, this.newBadge});

  @override
  State<_CheerCelebration> createState() => _CheerCelebrationState();
}

class _CheerCelebrationState extends State<_CheerCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))
    ..forward();
  Timer? _closer;

  @override
  void initState() {
    super.initState();
    _closer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _closer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  String get _mainMsg {
    final nb = widget.newBadge;
    if (nb != null) return '「${nb.name}」 뱃지 획득!';
    return switch (widget.status.today) {
      1 => '응원 완료! 개발자 힘이 불끈!',
      2 => '두 번째 응원! 서버가 쌩쌩 돌아가요',
      _ => '오늘 응원 만땅! 최고의 서포터예요',
    };
  }

  String get _subMsg {
    if (widget.newBadge != null) {
      return '누적 응원 ${widget.status.total}회 — 마이페이지에 달렸어요';
    }
    return widget.status.streak >= 2
        ? '${widget.status.streak}일째 연속 응원 — 진짜 팬 인정입니다'
        : '이 응원은 고스란히 서버비가 되어 돌아와요';
  }

  @override
  Widget build(BuildContext context) {
    Animation<double> seg(double a, double b, [Curve c = Curves.easeOut]) =>
        CurvedAnimation(parent: _ctrl, curve: Interval(a, b, curve: c));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 230,
                height: 210,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _ctrl,
                        builder: (_, __) => CustomPaint(
                            painter: _BurstPainter(t: _ctrl.value)),
                      ),
                    ),
                    ScaleTransition(
                      scale: Tween(begin: 0.0, end: 1.0).animate(
                          seg(0.0, 0.55, Curves.elasticOut)),
                      child: widget.newBadge != null
                          ? CustomPaint(
                              size: const Size(120, 66),
                              painter: CheerBadgeCarPainter(
                                level: widget.newBadge!.level,
                                color: cheerTierColor(widget.newBadge!.level,
                                    fallback: Colors.white),
                                isDark: true,
                              ),
                            )
                          : const CustomPaint(
                              size: Size(88, 84),
                              painter:
                                  _MiniHeartPainter(filled: true, isDark: true),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              FadeTransition(
                opacity: seg(0.30, 0.62),
                child: SlideTransition(
                  position: Tween(
                          begin: const Offset(0, 0.35), end: Offset.zero)
                      .animate(seg(0.30, 0.62, Curves.easeOutCubic)),
                  child: Text(
                    _mainMsg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.4,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              FadeTransition(
                opacity: seg(0.45, 0.80),
                child: SlideTransition(
                  position: Tween(
                          begin: const Offset(0, 0.5), end: Offset.zero)
                      .animate(seg(0.45, 0.80, Curves.easeOutCubic)),
                  child: Text(
                    _subMsg,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85),
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 버스트 — 확산 링 + 방사형 스파크 + 떠오르는 미니 하트 + 백글로우
class _BurstPainter extends CustomPainter {
  final double t; // 0~1
  const _BurstPainter({required this.t});

  static const _rose = Color(0xFFF43F5E);
  static const _roseSoft = Color(0xFFFB7185);

  void _heartAt(Canvas canvas, Offset c, double s, Paint paint) {
    final p = Path()
      ..moveTo(c.dx, c.dy - s * 0.18)
      ..cubicTo(c.dx, c.dy - s * 0.42, c.dx - s * 0.30, c.dy - s * 0.5,
          c.dx - s * 0.46, c.dy - s * 0.28)
      ..cubicTo(c.dx - s * 0.58, c.dy - s * 0.10, c.dx - s * 0.30,
          c.dy + s * 0.22, c.dx, c.dy + s * 0.5)
      ..cubicTo(c.dx + s * 0.30, c.dy + s * 0.22, c.dx + s * 0.58,
          c.dy - s * 0.10, c.dx + s * 0.46, c.dy - s * 0.28)
      ..cubicTo(c.dx + s * 0.30, c.dy - s * 0.5, c.dx, c.dy - s * 0.42,
          c.dx, c.dy - s * 0.18)
      ..close();
    canvas.drawPath(p, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide * 0.5;

    // 백글로우 — 하트 뒤 은은한 장미빛
    canvas.drawCircle(
      c,
      maxR * 0.55,
      Paint()
        ..color = _rose.withValues(alpha: 0.30 * (1 - t * 0.5))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );

    if (t <= 0) return;
    final fade = (1 - t).clamp(0.0, 1.0);

    // 확산 링
    canvas.drawCircle(
      c,
      maxR * (0.35 + 0.62 * Curves.easeOut.transform(t)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * fade + 0.3
        ..color = _roseSoft.withValues(alpha: 0.55 * fade),
    );

    // 방사형 스파크 12개
    final sparkT = Curves.easeOut.transform(t);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6 + 0.26;
      final dir = Offset(math.cos(a), math.sin(a));
      final r0 = maxR * (0.30 + 0.55 * sparkT);
      final r1 = r0 + maxR * 0.14 * fade;
      canvas.drawLine(
        c + dir * r0,
        c + dir * r1,
        Paint()
          ..strokeWidth = i.isEven ? 2.4 : 1.5
          ..strokeCap = StrokeCap.round
          ..color = (i.isEven ? _roseSoft : Colors.white)
              .withValues(alpha: 0.85 * fade),
      );
    }

    // 떠오르는 미니 하트 8개 — 각자 방향으로 퍼지며 위로 살짝 떠오르고 사라진다
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + 0.55;
      final dist = maxR * (0.18 + 0.58 * sparkT) * (i.isEven ? 1.0 : 0.78);
      final pos = c +
          Offset(math.cos(a), math.sin(a)) * dist +
          Offset(0, -maxR * 0.18 * sparkT);
      final s = (i.isEven ? 15.0 : 10.0) * (1 - 0.25 * t);
      _heartAt(
        canvas,
        pos,
        s,
        Paint()
          ..color = (i % 3 == 0 ? Colors.white : _roseSoft)
              .withValues(alpha: 0.9 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}
