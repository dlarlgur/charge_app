import 'package:flutter/material.dart';

import '../../data/services/cheer_service.dart';
import 'cheer_tier_theme.dart';
import 'crown_celebration.dart';
import 'tier_detail_popup.dart';

/// 내 개러지 — 2×2 수집 그리드 (핸드오프 G1).
/// 보유 카드는 등급색 글로우+컬러 차, 잠금 카드는 실루엣+남은 횟수.
class GarageScreen extends StatefulWidget {
  final CheerStatus? initialStatus;
  const GarageScreen({super.key, this.initialStatus});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  CheerStatus? _status;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    if (_status == null) _load();
    CheerService.instance.preload(onChanged: () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _load() async {
    final st = await CheerService.instance.status();
    if (mounted) setState(() => _status = st);
  }

  void _applyStatus(CheerStatus st) {
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
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: CheerDs.ev.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$owned/${CheerTierTheme.tiers.length} 수집',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: CheerDs.success)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.98,
            children: [
              for (final t in CheerTierTheme.tiers)
                _tierCard(t, total >= t.threshold, total, isDark),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: 12),
            _nextCard(next, total, nextProgress, isDark),
          ],
          if (st != null && st.crowns.isNotEmpty) ...[
            const SizedBox(height: 12),
            _hallOfFame(st, isDark),
          ],
          const SizedBox(height: 12),
          Center(
            child: Text('잠긴 차를 누르면 상세를 볼 수 있어요',
                style: TextStyle(fontSize: 11, color: CheerDs.faint(isDark))),
          ),
        ],
      ),
    );
  }

  /// 명예의 전당 — 월간 왕관 확정 기록. 하이퍼카 이후에도 매달 모을 게 남는다.
  Widget _hallOfFame(CheerStatus st, bool isDark) {
    final c = st.crownCounts;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: CheerDs.card(isDark),
        border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('명예의 전당',
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: CheerDs.ink(isDark))),
          const Spacer(),
          Text(
            [
              if ((c['gold'] ?? 0) > 0) '금 ${c['gold']}',
              if ((c['silver'] ?? 0) > 0) '은 ${c['silver']}',
              if ((c['bronze'] ?? 0) > 0) '동 ${c['bronze']}',
            ].join(' · '),
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB45309)),
          ),
        ]),
        const SizedBox(height: 10),
        for (final crown in st.crowns)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(Icons.emoji_events_rounded,
                  size: 17, color: CrownTheme.of(crown.rank).main),
              const SizedBox(width: 8),
              Text('${crown.month.replaceFirst('-', '년 ')}월',
                  style: TextStyle(
                      fontSize: 13, color: CheerDs.secondary(isDark))),
              const Spacer(),
              Text(
                  crown.rank == 1
                      ? '응원왕'
                      : '${crown.rank}위',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: CrownTheme.of(crown.rank).main)),
              const SizedBox(width: 6),
              Text('${crown.count}회',
                  style: TextStyle(
                      fontSize: 12, color: CheerDs.faint(isDark))),
            ]),
          ),
      ]),
    );
  }

  Widget _tierCard(CheerTierTheme t, bool ownedTier, int total, bool isDark) {
    final st = _status;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showTierDetailPopup(
          context,
          tier: t,
          status: st,
          total: total,
          onStatus: _applyStatus,
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: CheerDs.card(isDark),
            border: Border.all(
              color: ownedTier
                  ? t.ring(isDark).first.withValues(alpha: 0.9)
                  : CheerDs.cardBorder(isDark),
              width: ownedTier ? 1.5 : 0.5,
            ),
            gradient: ownedTier
                ? RadialGradient(
                    center: Alignment.center,
                    radius: 1.0,
                    colors: [
                      t.glow(isDark),
                      CheerDs.card(isDark),
                    ],
                  )
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 폭 고정(118) 대신 가용폭 — 320dp 에선 셀이 115px 라 고정폭이 더 크다.
              SizedBox(
                height: 47,
                width: double.infinity,
                child: ownedTier
                    ? t.car()
                    : t.silhouette(CheerDs.silhouette(isDark)),
              ),
              const SizedBox(height: 10),
              Text(t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ownedTier
                          ? CheerDs.ink(isDark)
                          : CheerDs.muted(isDark))),
              const SizedBox(height: 3),
              ownedTier
                  ? Text('누적 $total회 · 보유',
                      style: TextStyle(
                          fontSize: 11, color: CheerDs.secondary(isDark)))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_rounded,
                            size: 12, color: CheerDs.secondary(isDark)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                              '${t.threshold}회 · ${t.threshold - total}회 남음',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: CheerDs.secondary(isDark))),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nextCard(
      CheerTierTheme next, int total, double progress, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: CheerDs.card(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CheerDs.cardBorder(isDark), width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: CheerDs.success)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Stack(children: [
                Container(color: CheerDs.iconBg(isDark)),
                FractionallySizedBox(
                  widthFactor: progress == 0 ? 0.015 : progress,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient:
                          LinearGradient(colors: [CheerDs.gas, CheerDs.ev]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
