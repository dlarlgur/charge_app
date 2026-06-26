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

  /// 닿기 어려운 마커 — 뮤트 슬레이트로 가라앉혀(디밍) 고급스럽게. 빨강·경고삼각형 X.
  static const Color _unreachableBg = Colors.white;
  static const Color _unreachableAccent = Color(0xFF9AA6B2); // 뮤트 슬레이트

  /// 추천 알약 색(배경, 글씨) — 메달 톤. 1위 골드 / 2위 슬레이트 / 3위 브론즈, 흰 글씨 통일.
  static (Color, Color) _medalPill(int rank) {
    switch (rank) {
      case 1:
        return (const Color(0xFFE3A008), Colors.white); // 골드
      case 2:
        return (const Color(0xFF647488), Colors.white); // 슬레이트
      default:
        return (const Color(0xFFAE6A34), Colors.white); // 브론즈
    }
  }

  /// 마커 테두리 등 외부에서 쓰도록 메달 배경색만 노출.
  static Color medalColor(int rank) => _medalPill(rank).$1;

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
    int? recommendRank,
  }) {
    final String? logoAsset = logoFor(brand: brand, stationName: stationName);
    final bool showLogo = logoAsset != null;
    const double logoSize = 20.0;
    const double logoGap = 4.0;
    // 닿기 어려운 마커 — 뮤트 슬레이트 + 전체 페이드(0.66)로 가라앉힘(고급스럽게). 강조 X.
    final Color effectiveBorder =
        unreachable ? _unreachableAccent : borderColor;
    final Color effectiveText = unreachable ? _unreachableAccent : textColor;
    final Color bgColor = unreachable ? _unreachableBg : Colors.white;
    final bool highlighted = emphasizeBorder; // 닿기 어려움은 강조 X — 가라앉힘
    final double fontSize = highlighted ? 12.0 : 11.0;
    final double textW = label.length * (highlighted ? 8.5 : 7.5);
    final double contentW =
        (showLogo ? logoSize + logoGap : (isEv ? 14.0 + logoGap : 0.0)) + textW;
    final double w = contentW + 14.0;
    final double h = highlighted ? 30.0 : 26.0;

    const double tailW = 12.0;
    const double tailH = 10.0;
    final double borderWidth = highlighted ? 2.0 : 1.0;

    // 추천 알약 — 가격 배지 위에 작게. 1위 골드 / 2위 실버 / 3위 브론즈 (흰 글씨 채움).
    final bool showRecommend = recommendRank != null;
    final (Color, Color) medal = showRecommend
        ? _medalPill(recommendRank!)
        : (Colors.transparent, Colors.white);
    final Color pillColor = medal.$1;
    final Color pillTextColor = medal.$2;
    // 추천 알약 — 텍스트를 딱 감싸는 컴팩트 메달(양옆 여백 최소). 가격배지 폭에 늘리지 않음.
    const double pillH = 16.0;
    const double pillGap = 3.0;
    final String pillText = showRecommend ? '추천 $recommendRank위' : '';
    final double pillW = showRecommend ? pillText.length * 9.0 + 14.0 : 0.0;
    // 알약이 배지보다 넓을 때만 알약 폭을 캔버스 기준으로 (텍스트 잘림 방지).
    final double canvasW = pillW > w ? pillW : w;
    final double extraTop = showRecommend ? pillH + pillGap : 0.0;

    return NOverlayImage.fromWidget(
      widget: Opacity(
        opacity: unreachable ? 0.66 : 1.0,
        child: SizedBox(
          width: canvasW,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showRecommend) ...[
                Container(
                  width: pillW,
                  height: pillH,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: pillColor,
                    borderRadius: BorderRadius.circular(pillH / 2),
                    boxShadow: [
                      BoxShadow(
                        color: pillColor.withValues(alpha: 0.45),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    pillText,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      color: pillTextColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(height: pillGap),
              ],
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
                      const Icon(Icons.bolt_rounded,
                          size: 14, color: Color(0xFF22C55E)),
                      const SizedBox(width: logoGap),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        // fromWidget 래스터는 앱 폰트 미상속 → Pretendard 명시해 통일.
                        fontFamily: 'Pretendard',
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
                painter:
                    _GasBadgeTailPainter(effectiveBorder, borderWidth, bgColor),
              ),
            ],
          ),
        ),
      ),
      size: Size(canvasW, h + tailH + extraTop),
      context: context,
    );
  }
}

class _GasBadgeTailPainter extends CustomPainter {
  _GasBadgeTailPainter(this.borderColor, this.borderWidth,
      [this.bgColor = Colors.white]);
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
      old.borderColor != borderColor ||
      old.borderWidth != borderWidth ||
      old.bgColor != bgColor;
}
