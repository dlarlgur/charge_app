import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/services/cheer_service.dart';
import 'cheer_flow.dart';
import 'cheer_tier_theme.dart';
import 'garage_screen.dart';

/// 전기차 기름차 응원하기 — 계기판형 (design_handoff_supporter_badges 확정 시안 3b).
/// 서버 게이지(반원 계기판) + 오늘의 연료(3칸) + 내 뱃지 카드(→ 개러지).
class CheerScreen extends StatefulWidget {
  const CheerScreen({super.key});

  @override
  State<CheerScreen> createState() => _CheerScreenState();
}

class _CheerScreenState extends State<CheerScreen>
    with SingleTickerProviderStateMixin {
  CheerStatus? _status;
  bool _loading = true;
  bool _failed = false;
  bool _showing = false;

  // 니들 스윕 — 진입·적립 시 이전 값에서 새 값으로 (150ms easeOut, 시안 모션 규칙)
  late final AnimationController _needleCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));
  double _fillFrom = 0;
  double _fillTo = 0;

  @override
  void initState() {
    super.initState();
    _load();
    CheerService.instance.preload(onChanged: _refresh);
  }

  @override
  void dispose() {
    _needleCtrl.dispose();
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
    if (st != null) _animateTo(st.serverPct / 100);
  }

  void _animateTo(double target) {
    _fillFrom = _fillTo;
    _fillTo = target.clamp(0.0, 1.0);
    _needleCtrl.forward(from: 0);
  }

  void _applyStatus(CheerStatus st) {
    if (!mounted) return;
    setState(() => _status = st);
    _animateTo(st.serverPct / 100);
  }

  Future<void> _watchAd() async {
    if (_showing) return;
    setState(() => _showing = true);
    final started =
        await runCheerAdFlow(context, onStatus: _applyStatus);
    if (!started) CheerService.instance.preload(onChanged: _refresh);
    if (mounted) setState(() => _showing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: CheerDs.bg(isDark),
      appBar: AppBar(
        backgroundColor: CheerDs.bg(isDark),
        // 시안 헤더는 iOS 스타일 화살표(arrow_back_ios_new)
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('전기차 기름차 응원하기',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? _retryView(isDark)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  children: [
                    _gaugeCard(isDark),
                    const SizedBox(height: 12),
                    _fuelCard(isDark),
                    const SizedBox(height: 12),
                    _badgeCard(isDark),
                    const SizedBox(height: 16),
                    Center(
                      child: Text('광고 수익은 전액 서버 운영비에 보태져요.',
                          style: TextStyle(
                              fontSize: 11, color: CheerDs.faint(isDark))),
                    ),
                  ],
                ),
    );
  }

  Widget _retryView(bool isDark) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('응원 정보를 불러오지 못했어요',
              style: TextStyle(color: CheerDs.muted(isDark))),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            child: const Text('다시 시도'),
          ),
        ]),
      );

  BoxDecoration _card(bool isDark) => BoxDecoration(
        color: CheerDs.card(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CheerDs.cardBorder(isDark), width: 0.5),
      );

  // ─── 1. 서버 게이지 카드 (반원 계기판) ───
  Widget _gaugeCard(bool isDark) {
    final st = _status!;
    return Container(
      decoration: _card(isDark),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
      child: Column(
        children: [
          SizedBox(
            width: 230,
            height: 128,
            child: AnimatedBuilder(
              animation: _needleCtrl,
              builder: (_, __) {
                final t = Curves.easeOut.transform(_needleCtrl.value);
                final fill = _fillFrom + (_fillTo - _fillFrom) * t;
                return CustomPaint(
                  painter: _DialGaugePainter(fill: fill, isDark: isDark),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: '${st.serverCount}',
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: CheerDs.ink(isDark))),
            TextSpan(
                text: ' / ${st.serverGoal}',
                style: TextStyle(fontSize: 14, color: CheerDs.muted(isDark))),
          ])),
          const SizedBox(height: 4),
          Text('이번 달 서버 응원 게이지',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: CheerDs.ink(isDark))),
          const SizedBox(height: 2),
          Text('모두의 응원으로 ${st.serverPct.round()}% 채워졌어요',
              style: TextStyle(fontSize: 13, color: CheerDs.muted(isDark))),
        ],
      ),
    );
  }

  // ─── 2. 오늘의 연료 카드 ───
  Widget _fuelCard(bool isDark) {
    final st = _status!;
    final svc = CheerService.instance;
    final remaining = (st.dailyLimit - st.today).clamp(0, st.dailyLimit);
    final done = st.doneToday;

    return Container(
      decoration: _card(isDark),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('오늘의 연료',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: CheerDs.ink(isDark))),
            const Spacer(),
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: '${st.today}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: CheerDs.gas)),
              TextSpan(
                  text: ' / ${st.dailyLimit}',
                  style: TextStyle(
                      fontSize: 12, color: CheerDs.secondary(isDark))),
            ])),
          ]),
          const SizedBox(height: 12),
          // 연료바 3칸 — 채운 칸 파랑 그라데이션, 빈 칸 iconBg
          Row(
            children: [
              for (var i = 0; i < st.dailyLimit; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: i < st.today
                          ? const LinearGradient(
                              colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)])
                          : null,
                      color: i < st.today ? null : CheerDs.iconBg(isDark),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    done ? CheerDs.iconBg(isDark) : CheerDs.gas,
                disabledBackgroundColor: CheerDs.iconBg(isDark),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: EdgeInsets.zero,
              ),
              onPressed: done || _showing || !svc.adReady ? null : _watchAd,
              child: done
                  ? Text('오늘 응원 만땅!',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: CheerDs.muted(isDark)))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_showing || (!svc.adReady && svc.adLoading)) ...[
                          const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white)),
                          const SizedBox(width: 8),
                        ],
                        Text(
                            _showing
                                ? '광고 재생 중…'
                                : svc.adReady
                                    ? '광고 보고 응원하기'
                                    : '광고 불러오는 중…',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        if (!_showing && svc.adReady) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('$remaining번 남음',
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 9),
          Center(
            child: Text(
                done ? '내일 또 응원할 수 있어요' : '3칸을 다 채우면 "오늘 응원 만땅!"',
                style:
                    TextStyle(fontSize: 12, color: CheerDs.muted(isDark))),
          ),
        ],
      ),
    );
  }

  // ─── 3. 내 뱃지 카드 → 개러지 ───
  Widget _badgeCard(bool isDark) {
    final st = _status!;
    final tier = CheerTierTheme.of(st.total);
    final next = CheerTierTheme.nextOf(st.total);

    double progress = 1;
    if (next != null) {
      final from = tier?.threshold ?? 0;
      progress = ((st.total - from) / (next.threshold - from)).clamp(0.0, 1.0);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GarageScreen(initialStatus: st))),
        child: Ink(
          decoration: _card(isDark),
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 96,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0x0FFFFFFF)
                          : CheerDs.iconBgL,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: tier != null
                        ? tier.car()
                        : CheerTierTheme.byLevel(1).silhouette(
                            CheerDs.silhouette(isDark)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tier?.name ?? '첫 차를 기다리는 중',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: CheerDs.ink(isDark))),
                        const SizedBox(height: 3),
                        Text(
                            st.streak >= 2
                                ? '누적 응원 ${st.total}회 · ${st.streak}일 연속'
                                : '누적 응원 ${st.total}회',
                            style: TextStyle(
                                fontSize: 12,
                                color: CheerDs.secondary(isDark))),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 22, color: CheerDs.faint(isDark)),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 6,
                  child: Stack(children: [
                    Container(color: CheerDs.iconBg(isDark)),
                    FractionallySizedBox(
                      widthFactor: progress == 0 ? 0.015 : progress,
                      child: Container(color: CheerDs.gas),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: next != null
                          ? '다음 등급 「${next.name}」까지 '
                          : '최고 등급 달성! ',
                      style: TextStyle(
                          fontSize: 12, color: CheerDs.secondary(isDark))),
                  if (next != null)
                    TextSpan(
                        text: '${next.threshold - st.total}회',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: CheerDs.gas)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 반원 계기판 — 시안 SVG(3b, viewBox 200×116)를 좌표 그대로 옮김.
/// 틱 5개(45° 간격) + 트랙/그라데이션 호(13, round cap) + 테이퍼 삼각 니들 + 허브.
class _DialGaugePainter extends CustomPainter {
  final double fill; // 0~1
  final bool isDark;
  const _DialGaugePainter({required this.fill, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    // 시안 좌표계 200×116 → 화면 크기로 균일 스케일
    final k = math.min(size.width / 200, size.height / 116);
    final ox = (size.width - 200 * k) / 2;
    final oy = (size.height - 116 * k) / 2;
    Offset pt(double x, double y) => Offset(ox + x * k, oy + y * k);
    final center = pt(100, 100);

    // 틱 5개 — (14,100)→(24,100) 을 0/45/90/135/180° 회전 (시안 그대로)
    final tick = Paint()
      ..color = CheerDs.cardBorderStrong(isDark)
      ..strokeWidth = 2 * k
      ..strokeCap = StrokeCap.butt;
    for (final deg in [0, 45, 90, 135, 180]) {
      final a = math.pi + deg * math.pi / 180; // 왼쪽(180°)부터 시계방향
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
          center + dir * (86 * k), center + dir * (76 * k), tick);
    }

    // 트랙 (r70, 13px round cap)
    final rect = Rect.fromCircle(center: center, radius: 70 * k);
    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13 * k
        ..strokeCap = StrokeCap.round
        ..color = CheerDs.iconBg(isDark),
    );

    // 채움 호 — #3B82F6→#10B981 (시안 arcG)
    final sweep = math.pi * fill.clamp(0.0, 1.0);
    if (sweep > 0.01) {
      canvas.drawArc(
        rect,
        math.pi,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13 * k
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: math.pi,
            endAngle: math.pi * 2,
            colors: const [CheerDs.gas, CheerDs.ev],
          ).createShader(rect),
      );
    }

    // E / F — (20,115) (173,115), 11px/700 text-muted
    final tpStyle = TextStyle(
        fontSize: 11 * k,
        fontWeight: FontWeight.w700,
        color: CheerDs.muted(isDark));
    void label(String t, double x, double y) {
      final tp = TextPainter(
          text: TextSpan(text: t, style: tpStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      // SVG text 는 baseline 기준 — baseline 근사(높이의 0.8)
      tp.paint(canvas, pt(x, y) - Offset(0, tp.height * 0.8));
    }

    label('E', 20, 115);
    label('F', 173, 115);

    // 니들 — 테이퍼 삼각형 M100 96 L42 100 L100 104 Z, rotate(fill×180°)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(math.pi * fill.clamp(0.0, 1.0));
    canvas.translate(-center.dx, -center.dy);
    final needle = Path()
      ..moveTo(pt(100, 96).dx, pt(100, 96).dy)
      ..lineTo(pt(42, 100).dx, pt(42, 100).dy)
      ..lineTo(pt(100, 104).dx, pt(100, 104).dy)
      ..close();
    canvas.drawPath(needle, Paint()..color = CheerDs.amber);
    canvas.restore();

    // 허브 — r7 카드색 + 앰버 스트로크 3
    canvas.drawCircle(
        center, 7 * k, Paint()..color = CheerDs.cardSolid(isDark));
    canvas.drawCircle(
      center,
      7 * k,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * k
        ..color = CheerDs.amber,
    );
  }

  @override
  bool shouldRepaint(_DialGaugePainter old) =>
      old.fill != fill || old.isDark != isDark;
}
