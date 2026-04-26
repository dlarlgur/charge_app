import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 지도 탭과 동일: 흰 배경 + 브랜드 로고 + 가격(텍스트) 주유소 마커.
class GasStationMapBadge {
  GasStationMapBadge._();

  static const Map<String, String> brandLogos = {
    'GSC': 'assets/logo/oil/gs_icon.png',
    'SKE': 'assets/logo/oil/sk_icon.png',
    'HDO': 'assets/logo/oil/hd_icon.png',
    'SOL': 'assets/logo/oil/soil_icon.png',
    'NHO': 'assets/logo/oil/nh_icon.png',
    'RTO': 'assets/logo/oil/sail_logo.svg', // 알뜰주유소 (SAIL)
  };

  /// 고속도로 휴게소 EX(한국도로공사서비스) 로고.
  static const String _highwayLogo = 'assets/logo/oil/ex_log.png';

  /// 주유소 이름에 '휴게소' 포함 시 EX 로고 우선, 그 외는 brand 매핑.
  static String? logoFor({String? brand, String? stationName}) {
    if (stationName != null && stationName.contains('휴게소')) {
      return _highwayLogo;
    }
    if (brand != null && brand.isNotEmpty) return brandLogos[brand];
    return null;
  }

  static Future<void> precacheBrandImages(BuildContext context) async {
    for (final path in brandLogos.values) {
      if (path.toLowerCase().endsWith('.svg')) continue; // SVG 는 자체 캐시
      await precacheImage(AssetImage(path), context);
    }
    await precacheImage(const AssetImage(_highwayLogo), context);
  }

  static Future<NOverlayImage> overlayImage(
    BuildContext context, {
    required String label,
    String? brand,
    String? stationName,
    bool isEv = false,
    required Color borderColor,
    required Color textColor,
    bool emphasizeBorder = false,
  }) {
    final String? logoAsset = logoFor(brand: brand, stationName: stationName);
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
                    child: logoAsset.toLowerCase().endsWith('.svg')
                        ? SvgPicture.asset(
                            logoAsset,
                            width: logoSize,
                            height: logoSize,
                            fit: BoxFit.contain,
                          )
                        : Image.asset(
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
