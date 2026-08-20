import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/services/cheer_service.dart';
import 'car_paint.dart';
import 'car_paint_screen.dart';
import 'cheer_tier_theme.dart';
import 'gold_profile.dart';
import 'tier_detail_popup.dart';

/// 내 개러지 — handoff 2 (CheerGarage.html) 시안.
/// 2×2 수집 그리드(보유=등급 그라데이션 카드+글로우, 최신 등급=NEW 스윕/✦,
/// 잠금=대시 보더+그레이스케일 차+자물쇠) + 다음 입고 진행바 + 명예의 전당.
class GarageScreen extends StatefulWidget {
  final CheerStatus? initialStatus;
  const GarageScreen({super.key, this.initialStatus});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen>
    with TickerProviderStateMixin {
  CheerStatus? _status;

  /// 다음 입고 진행바 — 진입 시 1회 채워진다 (시안 ggBar)
  late final AnimationController _bar = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    CarPaintService.instance.init();
    _status = widget.initialStatus;
    if (_status == null) _load();
    CheerService.instance.preload(onChanged: () {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bar.forward();
    });
  }

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final st = await CheerService.instance.status();
    if (!mounted || st == null) return;
    CheerTierTheme.applyThresholds(st.tierThresholds);
    setState(() => _status = st);
    CarPaintService.instance.applyServer(st.carPaints,
        signedIn: await CheerService.instance.signedIn);
  }

  void _applyStatus(CheerStatus st) {
    CheerTierTheme.applyThresholds(st.tierThresholds);
    if (mounted) setState(() => _status = st);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final st = _status;
    final total = st?.total ?? CheerService.instance.cachedTotal;
    final owned =
        CheerTierTheme.tiers.where((t) => total >= t.threshold).length;
    final next = CheerTierTheme.nextOf(total);
    final cur = CheerTierTheme.of(total);

    double nextProgress = 1;
    if (next != null) {
      final from = cur?.threshold ?? 0;
      nextProgress =
          ((total - from) / (next.threshold - from)).clamp(0.0, 1.0);
    }

    return Scaffold(
      backgroundColor: CheerDs.bg(isDark),
      appBar: AppBar(
        backgroundColor: CheerDs.bg(isDark),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('내 개러지',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3)),
        actions: [
          // 꾸미기 진입점은 앱바 아이콘이 아니라 본문의 이름 붙은 줄로 내렸다 —
          // 라벨 없는 붓 아이콘은 아무도 누르지 않았고, 앱바에 글자를 더 넣으면
          // 큰 글자 배율에서 제목이 밀린다.
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? CheerDs.ev.withValues(alpha: 0.15)
                    : const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$owned/${CheerTierTheme.tiers.length} 수집',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? CheerDs.success
                          : const Color(0xFF047857))),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
        children: [
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              // 시안 카드 = 11+47+6+17+3+14+10 ≈ 108. 큰 글자 배율 여유로 124.
              mainAxisExtent: 124,
            ),
            children: [
              for (final t in CheerTierTheme.tiers)
                _tierCard(t, total >= t.threshold, t == cur, total, isDark),
            ],
          ),
          // 보유 차가 있으면 꾸미기 줄 — 그리드 바로 아래, 이름과 설명을 달고.
          if (cur != null) ...[
            const SizedBox(height: 10),
            _paintRow(cur, total, isDark),
          ],
          if (next != null) ...[
            const SizedBox(height: 10),
            _nextCard(next, cur, total, nextProgress, isDark),
          ],
          if (st != null && st.crowns.isNotEmpty) ...[
            const SizedBox(height: 10),
            _hallOfFame(st, isDark),
          ],
          const SizedBox(height: 14),
          Center(
            child: Text('잠긴 차를 누르면 상세를 볼 수 있어요',
                style: TextStyle(fontSize: 10, color: CheerDs.muted(isDark))),
          ),
        ],
      ),
    );
  }

  // ─── 수집 카드 ───
  Widget _tierCard(CheerTierTheme t, bool ownedTier, bool isCurrent, int total,
      bool isDark) {
    final st = _status;
    final content = ownedTier
        ? _ownedCard(t, isCurrent, total, isDark)
        : _lockedCard(t, total, isDark);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showTierDetailPopup(
          context,
          tier: t,
          status: st,
          total: total,
          onStatus: _applyStatus,
        ),
        child: content,
      ),
    );
  }

  Widget _ownedCard(
      CheerTierTheme t, bool isCurrent, int total, bool isDark) {
    final badge = t.garageBadge(isDark);

    return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              // 160deg ≈ 위에서 아래로 살짝 기운 방향
              begin: const Alignment(-0.35, -1),
              end: const Alignment(0.35, 1),
              colors: t.garageBg(isDark),
            ),
            border: Border.all(
                color: t.garageBorder(isDark),
                width: t.level == 1 ? 0.5 : 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // 등급색 radial 글로우 — 정적 (상시 pulse 는 승급 연출 전용, 형 지시)
              Positioned(
                top: 6,
                left: 0,
                right: 0,
                child: Center(
                  child: Opacity(
                    opacity: 0.75,
                    child: Container(
                      width: 100,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          t.garageGlow(isDark),
                          t.garageGlow(isDark).withValues(alpha: 0),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 11, 10, 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                        height: 47,
                        width: double.infinity,
                        child: CarImage(tier: t)),
                    const SizedBox(height: 6),
                    Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: CheerDs.ink(isDark))),
                    const SizedBox(height: 3),
                    Text(
                        isCurrent
                            ? '누적 $total회 · NEW'
                            : '누적 ${t.threshold}회 · 보유',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                t.level == 1 ? FontWeight.w400 : FontWeight.w700,
                            color: t.garageSub(isDark))),
                  ],
                ),
              ),
              // 우상단 뱃지 — 보유는 체크, 최신 등급은 별
              Positioned(
                right: 7,
                top: 7,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: badge.length == 1 ? badge.first : null,
                    gradient: badge.length > 1
                        ? LinearGradient(
                            begin: const Alignment(-0.4, -1),
                            end: const Alignment(0.4, 1),
                            colors: badge)
                        : null,
                  ),
                  child: Icon(
                      isCurrent ? Icons.star_rounded : Icons.check_rounded,
                      size: 12,
                      color: isDark && isCurrent
                          ? const Color(0xFF2A1608)
                          : Colors.white),
                ),
              ),
            ],
          ),
        );
  }

  Widget _lockedCard(CheerTierTheme t, int total, bool isDark) {
    return CustomPaint(
      foregroundPainter: _DashedBorder(
        color: isDark ? const Color(0x29FFFFFF) : const Color(0xFFCBD5E1),
        radius: 14,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isDark ? const Color(0x05FFFFFF) : Colors.white,
        ),
        padding: const EdgeInsets.fromLTRB(10, 11, 10, 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 47,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: isDark ? 0.4 : 0.55,
                    child: ColorFiltered(
                      colorFilter: _grayscale(isDark),
                      child: t.car(),
                    ),
                  ),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? const Color(0x24FFFFFF)
                          : const Color(0xBF0F172A),
                    ),
                    child: Icon(Icons.lock_rounded,
                        size: 14,
                        color: isDark ? CheerDs.inkD : Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: CheerDs.secondary(isDark))),
            const SizedBox(height: 3),
            Text('${t.threshold}회 · ${t.threshold - total}회 남음',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 10, color: CheerDs.muted(isDark))),
          ],
        ),
      ),
    );
  }

  /// grayscale(1) + brightness/contrast — 시안 필터값 그대로 합성한 매트릭스.
  ColorFilter _grayscale(bool isDark) {
    // 라이트 brightness1.9·contrast0.5 / 다크 brightness3·contrast0.35
    final s = isDark ? 3 * 0.35 : 1.9 * 0.5;
    final off = isDark ? 0.5 * (1 - 0.35) * 255 : 0.5 * (1 - 0.5) * 255;
    final r = 0.2126 * s, g = 0.7152 * s, b = 0.0722 * s;
    return ColorFilter.matrix(<double>[
      r, g, b, 0, off, //
      r, g, b, 0, off, //
      r, g, b, 0, off, //
      0, 0, 0, 1, 0,
    ]);
  }

  // ─── 내 차 꾸미기 진입 ───
  /// 앱바 붓 아이콘을 대신하는 본문 줄. 무엇을 하는 곳인지 부제로 못 박고,
  /// 안 써본 해금 컬러가 있으면 그 이름을 그대로 부제에 올린다.
  Widget _paintRow(CheerTierTheme cur, int total, bool isDark) {
    final reward = CarPaint.rewardFor(cur.level);
    final fresh = reward != null &&
        reward.unlockedFor(total) &&
        CarPaintService.instance.of(cur.level).isDefault;
    final sub = fresh
        ? '「${reward.name}」 컬러가 열려 있어요'
        : '보유한 차의 바디 컬러를 바꿔요';

    return Material(
      color: CheerDs.card(isDark),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          CarPaintService.instance.markCoachSeen();
          Navigator.of(context)
              .push(MaterialPageRoute(
                  builder: (_) => CarPaintScreen(tier: cur, total: total)))
              .then((_) {
            if (mounted) setState(() {});
          });
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: CheerDs.cardBorder(isDark), width: 0.5),
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: CheerDs.iconBg(isDark),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.format_paint_rounded,
                    size: 18, color: CheerDs.secondary(isDark)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('내 차 꾸미기',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: CheerDs.ink(isDark))),
                    const SizedBox(height: 2),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: fresh
                                ? (isDark ? CheerDs.success : CheerDs.ev)
                                : CheerDs.muted(isDark))),
                  ],
                ),
              ),
              if (fresh) ...[
                const SizedBox(width: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Color(0xFFEF4444)),
                ),
              ],
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: CheerDs.muted(isDark)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 다음 입고 ───
  Widget _nextCard(CheerTierTheme next, CheerTierTheme? cur, int total,
      double progress, bool isDark) {
    final from = cur?.threshold ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: CheerDs.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CheerDs.cardBorder(isDark), width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('다음 입고 「${next.name}」',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: CheerDs.secondary(isDark))),
            ),
            Text('${next.threshold - total}회 남음',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isDark ? CheerDs.success : CheerDs.ev)),
          ]),
          const SizedBox(height: 8),
          // 진행바 8px + 진행점 위에 다음 등급 차 미니 아이콘
          SizedBox(
            height: 8,
            child: AnimatedBuilder(
              animation: _bar,
              builder: (_, __) {
                final w = Curves.easeOut.transform(_bar.value) * progress;
                return LayoutBuilder(builder: (_, c) {
                  return Stack(clipBehavior: Clip.none, children: [
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0x14FFFFFF)
                            : const Color(0xFFEEF1F4),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: w.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [CheerDs.ev, CheerDs.gas]),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (c.maxWidth * w).clamp(0.0, c.maxWidth) - 14,
                      top: -11,
                      child: SizedBox(
                        width: 28,
                        height: 11,
                        child: Opacity(
                          opacity: 0.9,
                          child: isDark
                              ? ColorFiltered(
                                  colorFilter: const ColorFilter.matrix(
                                      <double>[
                                        2.4, 0, 0, 0, 0, //
                                        0, 2.4, 0, 0, 0, //
                                        0, 0, 2.4, 0, 0, //
                                        0, 0, 0, 1, 0,
                                      ]),
                                  child: next.car())
                              : next.car(),
                        ),
                      ),
                    ),
                  ]);
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$from회',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: CheerDs.slash(isDark))),
              Text('${next.threshold}회',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: CheerDs.slash(isDark))),
            ],
          ),
        ],
      ),
    );
  }

  /// 명예의 전당 — 월간 왕관 확정 기록. 하이퍼카 이후에도 매달 모을 게 남는다.
  Widget _hallOfFame(CheerStatus st, bool isDark) {
    final c = st.crownCounts;
    final headAccent =
        isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: const Alignment(-0.35, -1),
          end: const Alignment(0.35, 1),
          colors: isDark
              ? [const Color(0x2EFBBF24), const Color(0x08FBBF24)]
              : [const Color(0xFFFEF7E0), const Color(0xFFFBE9B9)],
        ),
        border: isDark
            ? Border.all(color: const Color(0x40FBBF24), width: 0.5)
            : null,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFFFBBF24)
                      .withValues(alpha: isDark ? 0.35 : 0.5),
                  const Color(0x00FBBF24),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.emoji_events_rounded,
                      size: 16,
                      color: isDark
                          ? const Color(0xFFFDE68A)
                          : const Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Text('명예의 전당',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: CheerDs.ink(isDark))),
                  const Spacer(),
                  Text(
                    [
                      if ((c['gold'] ?? 0) > 0) '금 ${c['gold']}',
                      if ((c['silver'] ?? 0) > 0) '은 ${c['silver']}',
                      if ((c['bronze'] ?? 0) > 0) '동 ${c['bronze']}',
                    ].join(' · '),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: headAccent),
                  ),
                ]),
                for (var i = 0; i < st.crowns.length; i++) ...[
                  if (i == 0)
                    const SizedBox(height: 9)
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Container(
                          height: 0.5,
                          color: isDark
                              ? const Color(0x1AFFFFFF)
                              : const Color(0x26B45309)),
                    ),
                  _crownRow(st.crowns[i], isDark),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _crownRow(CheerCrown crown, bool isDark) {
    // 왕관(금·은·동) 컨셉은 폐기 — handoff 3 의 순위 메달 톤으로 통일한다.
    final medal = CheerGold.medal(crown.rank);
    final label = cheerMonthLabelFull(crown.month);
    return Row(children: [
      Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: const Alignment(-0.4, -1),
            end: const Alignment(0.4, 1),
            colors: medal,
          ),
        ),
        alignment: Alignment.center,
        child: Text('${crown.rank}',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: CheerGold.medalInk(crown.rank))),
      ),
      const SizedBox(width: 8),
      Text(label,
          style: TextStyle(fontSize: 12, color: CheerDs.secondary(isDark))),
      const Spacer(),
      Text(crown.rank == 1 ? '응원왕' : '${crown.rank}위',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: CheerGold.rankLabel(crown.rank, isDark))),
      const SizedBox(width: 6),
      Text('${crown.count}회',
          style: TextStyle(fontSize: 12, color: CheerDs.muted(isDark))),
    ]);
  }
}

/// 잠금 카드용 1px 대시 보더 (시안 border:1px dashed).
class _DashedBorder extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorder({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
        Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    const dash = 4.0, gap = 3.0;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
            metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}
