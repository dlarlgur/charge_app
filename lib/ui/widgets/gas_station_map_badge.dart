import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

/// 지도 탭과 동일: 흰 배경 + 브랜드 로고 + 가격(텍스트) 주유소 마커.
class GasStationMapBadge {
  GasStationMapBadge._();

  static const Map<String, String> brandLogos = {
    'GSC': 'assets/logo/oil/gs_icon.png',
    'SKE': 'assets/logo/oil/sk_icon.png',
    'HDO': 'assets/logo/oil/hd_icon.png',
    'SOL': 'assets/logo/oil/soil_icon.png',
    'NHO': 'assets/logo/oil/nh_icon.png',
  };

  static Future<void> precacheBrandImages(BuildContext context) async {
    for (final path in brandLogos.values) {
      await precacheImage(AssetImage(path), context);
    }
  }

  static Future<NOverlayImage> overlayImage(
    BuildContext context, {
    required String label,
    String? brand,
    bool isEv = false,
    required Color borderColor,
    required Color textColor,
    bool emphasizeBorder = false,
  }) {
    final String? logoAsset = (brand != null && brand.isNotEmpty) ? brandLogos[brand] : null;
    final bool showLogo = logoAsset != null;
    const double logoSize = 20.0;
    const double logoGap = 4.0;
    final bool highlighted = emphasizeBorder;
    final double fontSize = highlighted ? 12.0 : 11.0;
    final double textW = label.length * (highlighted ? 8.5 : 7.5);
    final double contentW =
        (showLogo ? logoSize + logoGap : (isEv ? 14.0 + logoGap : 0.0)) + textW;
    final double w = contentW + 18.0;
    final double h = highlighted ? 30.0 : 26.0;

    const double tailW = 12.0;
    const double tailH = 10.0;
    final double borderWidth = emphasizeBorder ? 2.0 : 1.0;

    return NOverlayImage.fromWidget(
      widget: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(h / 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: borderColor,
                width: borderWidth,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showLogo) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Image.asset(
                      logoAsset,
                      width: logoSize,
                      height: logoSize,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: logoGap),
                ] else if (isEv) ...[
                  const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF22C55E)),
                  const SizedBox(width: logoGap),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          CustomPaint(
            size: const Size(tailW, tailH),
            painter: _GasBadgeTailPainter(borderColor, borderWidth),
          ),
        ],
      ),
      size: Size(w, h + tailH),
      context: context,
    );
  }
}

class _GasBadgeTailPainter extends CustomPainter {
  _GasBadgeTailPainter(this.borderColor, this.borderWidth);
  final Color borderColor;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

    // 흰 배경 삼각형 (뱃지와 동일한 흰 배경)
    final fillPath = Path()
      ..moveTo(cx, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = Colors.white);

    // 테두리: 좌·우 두 사선만 (상단 edge는 뱃지 하단 border와 겹치므로 생략)
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.miter;
    final borderPath = Path()
      ..moveTo(0, 0)
      ..lineTo(cx, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _GasBadgeTailPainter old) =>
      old.borderColor != borderColor || old.borderWidth != borderWidth;
}
