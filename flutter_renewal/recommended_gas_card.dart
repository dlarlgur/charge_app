import 'package:flutter/material.dart';

import '../ai_constants.dart';

/// AI 추천 주유소 카드 (리뉴얼)
/// 추천 배지 + 우회/경로상 + 지도 / 브랜드 로고 + 주유소명 /
/// 핵심 수치 3개(리터당 가격 · 직행 대비 · 절약액) / 경유 길안내.
///
/// `ai_result_screen.dart` 의 `_RecommendedCard` 를 이 위젯으로 교체하거나 참고하세요.
/// 추천 강조색은 amber(#F59E0B) 로 통일했습니다.
class RecommendedGasCard extends StatelessWidget {
  /// 기존 BrandLogo 위젯을 그대로 넘기세요. (38~42px 권장)
  final Widget logo;
  final String stationName;
  final String subtitle; // 예: 'SK에너지 · 1.2km · 셀프'
  final String pricePerLabel; // 예: '1,617'
  final String detourLabel; // 예: '+3분' / '우회 없음'
  final int savings; // 절약액(원). 0 이하면 미표시
  final bool isDetour;
  final VoidCallback? onViewMap;
  final VoidCallback? onNavigate;

  static const _amber = Color(0xFFF59E0B);
  static const _amberLight = Color(0xFFFFFDF8);
  static const _amberBorder = Color(0xFFFEEAC9);

  const RecommendedGasCard({
    super.key,
    required this.logo,
    required this.stationName,
    required this.subtitle,
    required this.pricePerLabel,
    required this.detourLabel,
    required this.savings,
    required this.isDetour,
    this.onViewMap,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _amber, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 배지 줄
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: _amber,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              size: 12, color: Colors.white),
                          SizedBox(width: 4),
                          Text('추천',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Text(isDetour ? '우회 최저가' : '경로상 최저가',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB45309))),
                    ),
                    const Spacer(),
                    if (onViewMap != null)
                      GestureDetector(
                        onTap: onViewMap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: kLineSoft,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.map_outlined,
                                  size: 13, color: kMuted),
                              SizedBox(width: 3),
                              Text('지도',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: kMuted)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
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
                                  fontSize: 17,
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
                // 핵심 수치 3개
                Container(
                  decoration: BoxDecoration(
                    color: _amberLight,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: _amberBorder),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        _stat(
                          icon: Icons.local_gas_station_rounded,
                          iconColor: _amber,
                          value: '$pricePerLabel',
                          unit: '원/L',
                          label: '리터당',
                        ),
                        const VerticalDivider(
                            width: 1, color: _amberBorder),
                        _stat(
                          icon: Icons.schedule_rounded,
                          iconColor: _amber,
                          value: detourLabel,
                          label: '직행 대비',
                        ),
                        const VerticalDivider(
                            width: 1, color: _amberBorder),
                        _stat(
                          icon: Icons.savings_rounded,
                          iconColor: const Color(0xFF22C55E),
                          value: savings > 0
                              ? '-${_comma(savings)}'
                              : '—',
                          unit: savings > 0 ? '원' : null,
                          valueColor: const Color(0xFF16A34A),
                          label: '절약액',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: onNavigate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _amber,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.route_rounded, size: 17),
                label: const Text('경유 길안내',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required IconData icon,
    required Color iconColor,
    required String value,
    String? unit,
    Color valueColor = kInk,
    required String label,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(height: 3),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(children: [
                TextSpan(
                    text: value,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: valueColor)),
                if (unit != null)
                  TextSpan(
                      text: unit,
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: kMute2)),
              ]),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 10, color: kMute2)),
          ],
        ),
      ),
    );
  }

  static String _comma(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}
