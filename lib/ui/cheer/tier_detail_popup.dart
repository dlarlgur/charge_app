import 'package:flutter/material.dart';

import '../../data/services/cheer_service.dart';
import 'car_paint.dart';
import 'car_paint_screen.dart';
import 'cheer_flow.dart';
import 'cheer_tier_theme.dart';

/// 등급 상세 팝업 (핸드오프 3e/3f).
/// 스포트라이트 삼각형 + 차 + 조건 칩/획득일 + 진행바 + CTA.
/// CTA는 형 확정대로 팝업을 닫고 그 자리에서 바로 광고를 시작한다.
void showTierDetailPopup(
  BuildContext context, {
  required CheerTierTheme tier,
  required CheerStatus? status,
  required int total,
  required void Function(CheerStatus st) onStatus,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showDialog(
    context: context,
    barrierColor: isDark
        ? const Color(0xFF0C0E13).withValues(alpha: 0.85)
        : const Color(0xFF2D3748).withValues(alpha: 0.60),
    builder: (ctx) => _TierDetailDialog(
      tier: tier,
      status: status,
      total: total,
      isDark: isDark,
      onStatus: onStatus,
    ),
  );
}

class _TierDetailDialog extends StatelessWidget {
  final CheerTierTheme tier;
  final CheerStatus? status;
  final int total;
  final bool isDark;
  final void Function(CheerStatus st) onStatus;
  const _TierDetailDialog({
    required this.tier,
    required this.status,
    required this.total,
    required this.isDark,
    required this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    final owned = total >= tier.threshold;
    final remaining = (tier.threshold - total).clamp(0, tier.threshold);
    final progress = (total / tier.threshold).clamp(0.0, 1.0);
    final ink = CheerDs.ink(isDark);
    final muted = CheerDs.muted(isDark);
    final acquiredAt = status?.tierAcquiredAt['${tier.level}'];
    final canAd = !(status?.doneToday ?? false);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          // 딤 위 팝업 — 불투명 표면
          color: CheerDs.cardSolid(isDark),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 스포트라이트 삼각형 + 차
              SizedBox(
                height: 150,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SpotlightPainter(
                          color: (owned
                                  ? tier.ring(isDark).first
                                  : CheerDs.faint(isDark))
                              .withValues(alpha: isDark ? 0.10 : 0.09),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      child: Text(
                        tier.level == CheerTierTheme.tiers.length
                            ? '${tier.level}단계 · 최고 등급'
                            : '${tier.level}단계',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: muted,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SizedBox(
                        width: 216,
                        height: 86,
                        child: owned
                            ? CarImage(tier: tier)
                            : tier.silhouette(
                                CheerDs.silhouette(isDark, popup: true)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(tier.name,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: ink)),
              const SizedBox(height: 10),
              // 조건 칩 or 획득일
              if (owned)
                Text(
                    acquiredAt != null
                        ? '획득일 ${_fmtDate(acquiredAt)}'
                        : '보유 중',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: tier.label(isDark)))
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: tier
                        .label(isDark)
                        .withValues(alpha: isDark ? 0.16 : 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded,
                          size: 12, color: tier.label(isDark)),
                      const SizedBox(width: 4),
                      Text('누적 ${tier.threshold}회 달성 시 획득',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tier.label(isDark))),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(tier.popupDesc,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.55, color: muted)),
              const SizedBox(height: 14),
              if (owned && status != null) ...[
                _ownedStats(status!, isDark),
                const SizedBox(height: 10),
                // 보유 차는 바디 컬러를 바꿀 수 있다 (handoff 2 컬러 꾸미기)
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: CheerDs.iconBg(isDark),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              CarPaintScreen(tier: tier, total: total)));
                    },
                    icon: Icon(Icons.format_paint_rounded,
                        size: 17, color: CheerDs.secondary(isDark)),
                    label: Text('컬러 꾸미기',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: CheerDs.ink(isDark))),
                  ),
                ),
              ] else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 6,
                    width: double.infinity,
                    child: Stack(children: [
                      Container(color: CheerDs.iconBg(isDark)),
                      FractionallySizedBox(
                        widthFactor: progress == 0 ? 0.015 : progress,
                        child: Container(color: CheerDs.amber),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 7),
                Row(children: [
                  Text('지금 $total회',
                      style: TextStyle(fontSize: 12, color: muted)),
                  const Spacer(),
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '$remaining회',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: ink)),
                    TextSpan(
                        text: ' 남음',
                        style: TextStyle(fontSize: 12, color: muted)),
                  ])),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: CheerDs.gas,
                      disabledBackgroundColor: CheerDs.iconBg(isDark),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    // 형 확정: 팝업 닫고 그 자리에서 바로 광고 → 완주 시 감사/승급 연출
                    onPressed: canAd
                        ? () {
                            Navigator.of(context).pop();
                            runCheerAdFlow(context, onStatus: onStatus);
                          }
                        : null,
                    child: Text(canAd ? '광고 보고 응원하기' : '오늘 응원 만땅!',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: canAd
                                ? Colors.white
                                : CheerDs.muted(isDark))),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 보유 등급 — 누적/연속/다음까지 3분할 스탯 (핸드오프 1c 팝업)
  Widget _ownedStats(CheerStatus st, bool isDark) {
    final next = CheerTierTheme.nextOf(st.total);
    Widget cell(String v, String label) => Expanded(
          child: Column(children: [
            Text(v,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: CheerDs.ink(isDark))),
            const SizedBox(height: 2),
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: CheerDs.muted(isDark))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: CheerDs.iconBg(isDark),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        cell('${st.total}회', '누적 응원'),
        // 오늘·어제 모두 없으면 연속이 끊긴 상태 — '0일' 은 고장처럼 보이고,
        // 그렇다고 1일로 띄우면 하지 않은 기록을 만드는 셈이라 '–' 로 비운다.
        cell(st.streak > 0 ? '${st.streak}일' : '–', '연속 응원'),
        cell(next != null ? '${next.threshold - st.total}회' : '완주',
            next != null ? '다음 등급까지' : '최고 등급'),
      ]),
    );
  }

  String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.year}.${d.month}.${d.day}';
  }
}

/// 스포트라이트 — 위 중앙에서 아래로 퍼지는 삼각형 빔
class _SpotlightPainter extends CustomPainter {
  final Color color;
  const _SpotlightPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.5 - 26, 0)
      ..lineTo(size.width * 0.5 + 26, 0)
      ..lineTo(size.width * 0.94, size.height)
      ..lineTo(size.width * 0.06, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.color != color;
}
