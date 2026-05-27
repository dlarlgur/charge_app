import 'package:flutter/material.dart';

import '../ai_constants.dart';
import 'ai_painters.dart';

/// 큰 원형 게이지 — CustomPaint 로 그라데이션 + rounded cap.
class GaugeRing extends StatelessWidget {
  final double percent;        // 0-100
  final double reachableKm;
  final Color color;
  final Color colorDeep;
  final bool isEv;
  const GaugeRing({
    super.key,
    required this.percent, required this.reachableKm,
    required this.color, required this.colorDeep, required this.isEv,
  });

  @override
  Widget build(BuildContext context) {
    const size = 108.0;
    return SizedBox(
      width: size, height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(size, size),
            painter: GaugeRingPainter(
              percent: percent.clamp(0, 100) / 100,
              color: color, colorDeep: colorDeep,
              bgColor: isEv ? kEvAccentLight : kFuelAccentLight,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: TextSpan(children: [
                  TextSpan(
                    text: percent.round().toString(),
                    style: TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w800,
                      color: colorDeep, height: 1, letterSpacing: -1.2,
                    ),
                  ),
                  TextSpan(
                    text: '%',
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: kMuted, height: 1,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 3),
              RichText(
                text: TextSpan(children: [
                  const TextSpan(
                    text: '≈ ',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted),
                  ),
                  TextSpan(
                    text: '${reachableKm.round()} km',
                    style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800, color: kInk2,
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
