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

  /// 고속도로 휴게소 식별 패턴 — BrandLogo.isHighwayRestArea 와 동일.
  static final RegExp _highwayCityLabelRe = RegExp(
    r'\((?:서울|부산|인천|대구|광주|대전|울산|세종|일산|하남|양평|춘천|강릉|속초|삼척|영덕|포항|서부산|창원|통영|함양|광양|순천|장수|전주|완주|익산|목포|영암|무안|논산|당진|서천|천안|공주|청주|제천|남이|평택|양양|경산|마산|영천|상주|판교|충주|안동|경주|보령|군위|처인|산청|진영|포천|원주|동해|여주|횡성|평창|대관령)(?:방향)?\)',
  );
  static final RegExp _updownRe = RegExp(r'\((?:상|하)\)');

  static bool _isHighwayRestArea(String? name) {
    if (name == null) return false;
    if (name.contains('휴게소')) return true;
    if (_highwayCityLabelRe.hasMatch(name)) return true;
    return _updownRe.hasMatch(name);
  }

  /// 휴게소(이름 패턴 매칭) → EX 로고, 그 외 → brand 매핑.
  static String? logoFor({String? brand, String? stationName}) {
    if (_isHighwayRestArea(stationName)) {
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

  /// 잔량 부족 마커 — 옅은 빨강 배경 + 진한 빨강 border + ⚠ 아이콘.
  static const Color _unreachableBg = Color(0xFFFFECEC);
  static const Color _unreachableAccent = Color(0xFFD32F2F);

  static Future<NOverlayImage> overlayImage(
    BuildContext context, {
    required String label,
    String? brand,
    String? stationName,
    bool isEv = false,
    required Color borderColor,
    required Color textColor,
    bool emphasizeBorder = false,
    bool unreachable = false,
  }) {
    final String? logoAsset = logoFor(brand: brand, stationName: stationName);
    final bool showLogo = logoAsset != null;
    const double logoSize = 20.0;
    const double logoGap = 4.0;
    // 잔량 부족 마커 — 색만 빨강 톤으로 강제 오버라이드. emphasize 도 자동 true (border 굵게).
    final Color effectiveBorder = unreachable ? _unreachableAccent : borderColor;
    final Color effectiveText = unreachable ? _unreachableAccent : textColor;
    final Color bgColor = unreachable ? _unreachableBg : Colors.white;
    final bool highlighted = emphasizeBorder || unreachable;
    final double fontSize = highlighted ? 12.0 : 11.0;
    final double textW = label.length * (highlighted ? 8.5 : 7.5);
    const double warningSize = 14.0;
    const double warningGap = 3.0;
    final double contentW =
        (showLogo ? logoSize + logoGap : (isEv ? 14.0 + logoGap : 0.0))
        + (unreachable ? warningSize + warningGap : 0.0)
        + textW;
    final double w = contentW + 18.0;
    final double h = highlighted ? 30.0 : 26.0;

    const double tailW = 12.0;
    const double tailH = 10.0;
    final double borderWidth = highlighted ? 2.0 : 1.0;

    return NOverlayImage.fromWidget(
      widget: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(h / 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: effectiveBorder,
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
                if (unreachable) ...[
                  const Icon(Icons.warning_amber_rounded,
                      size: warningSize, color: _unreachableAccent),
                  const SizedBox(width: warningGap),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: effectiveText,
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
            painter: _GasBadgeTailPainter(effectiveBorder, borderWidth, bgColor),
          ),
        ],
      ),
      size: Size(w, h + tailH),
      context: context,
    );
  }

}

class _GasBadgeTailPainter extends CustomPainter {
  _GasBadgeTailPainter(this.borderColor, this.borderWidth, [this.bgColor = Colors.white]);
  final Color borderColor;
  final double borderWidth;
  final Color bgColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

    // 배경 삼각형 — 뱃지 캡슐과 동일 색 (잔량 부족 마커는 옅은 빨강).
    final fillPath = Path()
      ..moveTo(cx, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = bgColor);

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
      old.borderColor != borderColor || old.borderWidth != borderWidth || old.bgColor != bgColor;
}
