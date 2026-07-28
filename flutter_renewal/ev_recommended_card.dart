import 'package:flutter/material.dart';

import '../ai_constants.dart';

/// AI 추천 충전소 카드 (리뉴얼)
/// 상태 헤더(AI 추천 + 여유 + avail/total dots) / 로고 + 이름 /
/// SOC 예측 바(도착 시 → N분 후) / 정보 칩 / 길안내·알림·상세.
///
/// `ev_result_screen.dart` 의 `_StationCard(isRecommended:true)` 를
/// 이 위젯으로 교체하거나 참고하세요. accent 는 충전 green(#10B981).
class EvRecommendedCard extends StatelessWidget {
  final Widget logo; // 기존 운영사 로고 위젯
  final String stationName;
  final String subtitle; // 예: '한전 KEPCO · 영동고속도로'
  final int availCount;
  final int totalCount;
  final int arrivalSoc; // 도착 시 잔량 %
  final int afterChargeSoc; // 충전 후 잔량 %
  final int chargeMinutes; // 충전 소요(분)
  final String unitPriceLabel; // 예: '347원/kWh · 100kW'
  final String distanceLabel; // 예: '98km'
  final bool onRoute; // 경로 이탈 없음 여부
  final VoidCallback? onNavigate;
  final VoidCallback? onAlarm;
  final VoidCallback? onDetail;

  static const _green = Color(0xFF10B981);
  static const _greenDeep = Color(0xFF059669);
  static const _greenLight = Color(0xFFECFDF5);
  static const _amber = Color(0xFFF59E0B);

  const EvRecommendedCard({
    super.key,
    required this.logo,
    required this.stationName,
    required this.subtitle,
    required this.availCount,
    required this.totalCount,
    required this.arrivalSoc,
    required this.afterChargeSoc,
    required this.chargeMinutes,
    required this.unitPriceLabel,
    required this.distanceLabel,
    required this.onRoute,
    this.onNavigate,
    this.onAlarm,
    this.onDetail,
  });

  String get _statusText {
    if (availCount > 1) return '$availCount자리 여유 있어요';
    if (availCount == 1) return '자리 1개 남았어요. 서두르세요!';
    return '현재 만석이에요';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _green, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _green.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상태 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: const BoxDecoration(
              color: _greenLight,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16.5)),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text('AI 추천',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_statusText,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _greenDeep),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                _ChargerDots(avail: availCount, total: totalCount),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 로고 + 이름
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: SizedBox(width: 42, height: 42, child: logo),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(stationName,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: kInk,
                                  letterSpacing: -0.4),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 1),
                          Text(subtitle,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: kMute2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                // SOC 예측 바
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFB),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFEEF2F6)),
                  ),
                  child: Row(
                    children: [
                      _socEnd('도착 시', '$arrivalSoc', _amber),
                      const SizedBox(width: 8),
                      const Icon(Icons.trending_flat_rounded,
                          size: 18, color: Color(0xFFCBD5E1)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _socBar(arrivalSoc, afterChargeSoc),
                      ),
                      const SizedBox(width: 8),
                      _socEnd('$chargeMinutes분 후', '$afterChargeSoc', _green),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 정보 칩
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _chip(Icons.bolt_rounded, unitPriceLabel, kInk2,
                        kLineSoft),
                    _chip(Icons.near_me_rounded, distanceLabel, kMuted,
                        kLineSoft),
                    if (onRoute)
                      _chip(Icons.check_circle_rounded, '경로 이탈 없음',
                          _greenDeep, _greenLight),
                  ],
                ),
              ],
            ),
          ),
          // 액션
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: onNavigate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.route_rounded, size: 17),
                      label: const Text('길안내',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                _iconBtn(Icons.notifications_outlined, onAlarm),
                const SizedBox(width: 9),
                _iconBtn(Icons.info_outline_rounded, onDetail),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _socEnd(String label, String pct, Color color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: kMute2)),
        RichText(
          text: TextSpan(children: [
            TextSpan(
                text: pct,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: color)),
            const TextSpan(
                text: '%',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800, color: kMute2)),
          ]),
        ),
      ],
    );
  }

  Widget _socBar(int from, int to) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 9,
        child: Row(
          children: [
            Expanded(
              flex: from.clamp(1, 100),
              child: Container(color: _amber),
            ),
            Expanded(
              flex: (to - from).clamp(1, 100),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_amber, _green]),
                ),
              ),
            ),
            Expanded(
              flex: (100 - to).clamp(1, 100),
              child: Container(color: const Color(0xFFE2E8F0)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData ic, String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ic, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData ic, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: _greenLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(ic, size: 19, color: _green),
      ),
    );
  }
}

/// avail/total 점 표시 (avail = 초록 채움, 나머지 = 회색).
class _ChargerDots extends StatelessWidget {
  final int avail;
  final int total;
  const _ChargerDots({required this.avail, required this.total});

  @override
  Widget build(BuildContext context) {
    final shown = total.clamp(0, 6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < shown; i++)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: i < avail
                    ? const Color(0xFF10B981)
                    : const Color(0xFFE2E8F0),
                shape: BoxShape.circle,
              ),
            ),
          ),
        const SizedBox(width: 5),
        Text('$avail/$total',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: kInk)),
      ],
    );
  }
}
