import 'package:flutter/material.dart';

import '../ai_constants.dart';
import 'ai_painters.dart';

/// 큰 원형 게이지 (리뉴얼)
/// - 상단: "잔량 NN%" / "배터리 NN%" (accent)
/// - 중앙: 주행 가능 km 를 큰 수치로
/// - 우하단: 편집 뱃지 (탭 처리는 상위 HeroCard 의 GestureDetector(onTapLevel) 담당)
class GaugeRing extends StatelessWidget {
  final double percent; // 0-100
  final double reachableKm;
  final Color color;
  final Color colorDeep;
  final bool isEv;

  const GaugeRing({
    super.key,
    required this.percent,
    required this.reachableKm,
    required this.color,
    required this.colorDeep,
    required this.isEv,
  });

  @override
  Widget build(BuildContext context) {
    const size = 116.0;
    final levelLabel = isEv ? '배터리' : '잔량';

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(size, size),
            painter: GaugeRingPainter(
              percent: percent.clamp(0, 100) / 100,
              color: color,
              colorDeep: colorDeep,
              bgColor: const Color(0xFFEEF2F6),
            ),
          ),
          // 중앙 텍스트 — 편집 뱃지와 겹치지 않게 살짝 위로(bottom padding)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$levelLabel ${percent.round()}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: colorDeep,
                    letterSpacing: -0.3,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                RichText(
                  text: TextSpan(children: [
                    TextSpan(
                      text: '${reachableKm.round()}',
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: kInk,
                        letterSpacing: -0.8,
                        height: 1.05,
                      ),
                    ),
                    const TextSpan(
                      text: ' km',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kMute2,
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
          // 편집 뱃지
          Positioned(
            right: 2,
            bottom: 6,
            child: Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.32),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.edit_outlined, size: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
