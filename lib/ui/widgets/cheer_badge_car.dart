import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 응원 뱃지 등급색 — 쿠페(실버) → 스포츠카(블루) → 슈퍼카(레드) → 하이퍼카(골드).
Color cheerTierColor(int level, {required Color fallback}) => switch (level) {
      1 => const Color(0xFF94A3B8),
      2 => AppColors.gasBlue,
      3 => const Color(0xFFDC2626),
      4 => const Color(0xFFD8A711),
      _ => fallback,
    };

/// 스포츠카 뱃지 — 등급별 실루엣, 위 등급일수록 낮고 사나워진다.
/// 1 쿠페(패스트백) → 2 스포츠카(라운드) → 3 슈퍼카(웨지+스포일러)
/// → 4 하이퍼카(빅윙+언더글로우). 미획득(level 0)은 쿠페 윤곽선만.
/// 이모지·외부 이미지 없이 전부 벡터 — 응원 화면·마이페이지 공용.
class CheerBadgeCarPainter extends CustomPainter {
  final int level;
  final Color color;
  final bool isDark;

  const CheerBadgeCarPainter({
    required this.level,
    required this.color,
    required this.isDark,
  });

  // 차체 실루엣 (정규화 좌표, y=0 위) — 앞범퍼 아래에서 지붕을 넘어 뒷범퍼 아래까지.
  static const Map<int, List<Offset>> _bodies = {
    1: [
      Offset(.06, .80), Offset(.03, .66), Offset(.07, .60), Offset(.30, .56),
      Offset(.44, .34), Offset(.56, .31), Offset(.70, .32), Offset(.84, .44),
      Offset(.94, .52), Offset(.95, .57), Offset(.93, .80),
    ],
    2: [
      Offset(.05, .80), Offset(.02, .68), Offset(.07, .60), Offset(.28, .56),
      Offset(.42, .36), Offset(.55, .33), Offset(.68, .35), Offset(.82, .44),
      Offset(.93, .52), Offset(.92, .80),
    ],
    3: [
      Offset(.03, .80), Offset(.01, .70), Offset(.06, .64), Offset(.34, .58),
      Offset(.50, .40), Offset(.60, .38), Offset(.70, .39), Offset(.80, .48),
      Offset(.94, .50), Offset(.97, .54), Offset(.96, .80),
    ],
    4: [
      Offset(.02, .80), Offset(.01, .72), Offset(.05, .66), Offset(.30, .60),
      Offset(.42, .44), Offset(.54, .41), Offset(.64, .42), Offset(.76, .48),
      Offset(.96, .52), Offset(.95, .80),
    ],
  };

  // 유리(캐빈) 영역 LTRB (정규화)
  static const Map<int, Rect> _glass = {
    1: Rect.fromLTRB(.46, .35, .74, .52),
    2: Rect.fromLTRB(.44, .37, .68, .52),
    3: Rect.fromLTRB(.52, .42, .70, .54),
    4: Rect.fromLTRB(.44, .45, .62, .56),
  };

  // 앞/뒤 바퀴 x (정규화)
  static const Map<int, List<double>> _wheels = {
    1: [.27, .77], 2: [.26, .77], 3: [.26, .80], 4: [.25, .81],
  };

  Path _smooth(List<Offset> pts, Size s) {
    Offset at(int i) => Offset(pts[i].dx * s.width, pts[i].dy * s.height);
    final p = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final c = at(i);
      final n = at(i + 1);
      p.quadraticBezierTo(c.dx, c.dy, (c.dx + n.dx) / 2, (c.dy + n.dy) / 2);
    }
    final l = at(pts.length - 1);
    p
      ..lineTo(l.dx, l.dy)
      ..close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final lv = level.clamp(0, 4);
    final shape = lv == 0 ? 1 : lv; // 미획득은 쿠페 윤곽
    final w = size.width, h = size.height;
    final body = _smooth(_bodies[shape]!, size);
    final wheelXs = _wheels[shape]!;
    final wheelY = .82 * h;
    final wheelR = .13 * h + (shape == 4 ? .01 * h : 0);

    // 바닥 그림자
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(.5 * w, .95 * h), width: .86 * w, height: .10 * h),
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.35 : 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    if (lv == 0) {
      // 미획득 — 윤곽선만 (수집욕 자극용 실루엣)
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: 0.7);
      canvas.drawPath(body, stroke);
      for (final x in wheelXs) {
        canvas.drawCircle(Offset(x * w, wheelY), wheelR, stroke);
      }
      return;
    }

    // 하이퍼카 언더글로우 — 최고 등급의 허세
    if (lv == 4) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(.5 * w, .84 * h), width: .8 * w, height: .16 * h),
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // 차체 — 2등급부터 그라데이션(위가 밝음), 쿠페는 단색
    final bodyPaint = Paint();
    if (lv >= 2) {
      bodyPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(color, Colors.white, lv == 4 ? 0.45 : 0.28)!,
          color,
        ],
      ).createShader(Offset.zero & size);
    } else {
      bodyPaint.color = color;
    }
    canvas.drawPath(body, bodyPaint);
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color =
            Color.lerp(color, Colors.black, 0.25)!.withValues(alpha: 0.6),
    );

    // 스포일러(슈퍼카) / 빅윙(하이퍼카)
    if (lv == 3) {
      final sp = Paint()
        ..color = Color.lerp(color, Colors.black, 0.3)!
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(.86 * w, .40 * h), Offset(.99 * w, .36 * h), sp);
      canvas.drawLine(Offset(.92 * w, .40 * h), Offset(.92 * w, .48 * h), sp);
    } else if (lv == 4) {
      final wing = Paint()
        ..color = Color.lerp(color, Colors.black, 0.3)!
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(.78 * w, .34 * h), Offset(1.0 * w, .30 * h), wing);
      canvas.drawLine(Offset(.84 * w, .35 * h), Offset(.84 * w, .46 * h), wing);
      canvas.drawLine(Offset(.95 * w, .32 * h), Offset(.95 * w, .48 * h), wing);
    }

    // 유리
    final g = _glass[shape]!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(g.left * w, g.top * h, g.right * w, g.bottom * h),
        Radius.circular(.06 * w),
      ),
      Paint()..color = Colors.white.withValues(alpha: isDark ? 0.30 : 0.45),
    );

    // 보닛 광택 스트릭 — 2등급부터
    if (lv >= 2) {
      canvas.drawLine(
        Offset(.10 * w, .58 * h),
        Offset(.36 * w, .53 * h),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
    }

    // 헤드라이트
    canvas.drawCircle(
      Offset(.07 * w, .64 * h),
      .035 * w,
      Paint()..color = const Color(0xFFFFF3C4).withValues(alpha: 0.95),
    );

    // 바퀴 — 2등급부터 스포크 휠
    final tire = Paint()..color = const Color(0xFF1E293B);
    final hub = Paint()..color = const Color(0xFFCBD5E1);
    for (final x in wheelXs) {
      final c = Offset(x * w, wheelY);
      canvas.drawCircle(c, wheelR, tire);
      canvas.drawCircle(c, wheelR * .48, hub);
      if (lv >= 2) {
        final spoke = Paint()
          ..color = const Color(0xFF475569)
          ..strokeWidth = 1;
        for (var i = 0; i < 4; i++) {
          final a = i * math.pi / 4 + math.pi / 8;
          canvas.drawLine(
            c,
            c + Offset(math.cos(a), math.sin(a)) * wheelR * .44,
            spoke,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(CheerBadgeCarPainter old) =>
      old.level != level || old.color != color || old.isDark != isDark;
}

/// 마이페이지용 뱃지 칩 — 차 실루엣 + 등급명 필. 미획득이면 아무것도 안 그린다.
class CheerBadgeChip extends StatelessWidget {
  final int level;
  final String name;
  final bool isDark;

  const CheerBadgeChip({
    super.key,
    required this.level,
    required this.name,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (level <= 0) return const SizedBox.shrink();
    final color = cheerTierColor(level, fallback: Colors.grey);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.20 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: color.withValues(alpha: isDark ? 0.45 : 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(24, 13),
            painter: CheerBadgeCarPainter(
                level: level, color: color, isDark: isDark),
          ),
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}
