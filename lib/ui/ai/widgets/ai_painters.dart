import 'package:flutter/material.dart';

/// 게이지 원 페인터 — 잔량/도착 잔량 시각화.
/// 12시 방향에서 시계방향으로 percent 만큼 호 그림 + 배경 원.
class GaugeRingPainter extends CustomPainter {
  final double percent;
  final Color color;
  final Color colorDeep;
  final Color bgColor;
  GaugeRingPainter({required this.percent, required this.color, required this.colorDeep, required this.bgColor});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    // 배경 원
    canvas.drawCircle(
      center, radius,
      Paint()..color = bgColor..style = PaintingStyle.stroke..strokeWidth = stroke,
    );
    // 진행 호 (12시부터 시계방향)
    if (percent > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [color, colorDeep],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, -1.5708, percent * 2 * 3.14159, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant GaugeRingPainter old) =>
      old.percent != percent || old.color != color || old.bgColor != bgColor;
}

/// 아래 방향 삼각형 — 카드/툴팁 아래 화살표 등.
class DownTrianglePainter extends CustomPainter {
  final Color color;
  const DownTrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(DownTrianglePainter old) => old.color != color;
}

/// 경로 화살표 (^) — 흰색 stroke, 3px.
class RouteArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.1, h * 0.8)
      ..lineTo(w * 0.5, h * 0.15)
      ..lineTo(w * 0.9, h * 0.8);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(RouteArrowPainter oldDelegate) => false;
}
