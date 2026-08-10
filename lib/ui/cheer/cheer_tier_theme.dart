import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 응원하기 디자인 시스템 — design_handoff_supporter_badges 확정 시안의 토큰.
/// 등급 라벨 컬러: 1 실버 · 2 레드 · 3 골드 · 4 블랙. 모든 색은 라이트/다크 검증값
/// 그대로이며(README 표), 임의로 바꾸지 않는다.
class CheerDs {
  CheerDs._();

  // 화면 공통
  static const bgL = Color(0xFFF8FAFB);
  static const bgD = Color(0xFF0C0E13);
  static const cardL = Colors.white;
  static const cardD = Color(0xFF151A23);
  static const cardBorderL = Color(0xFFE8ECF0);
  static const cardBorderD = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
  static const inkL = Color(0xFF0F172A);
  static const inkD = Color(0xFFF1F5F9);
  static const mutedL = Color(0xFF64748B);
  static const mutedD = Color(0xFF94A3B8);
  static const faintL = Color(0xFF94A3B8);
  static const faintD = Color(0xFF64748B);
  static const iconBgL = Color(0xFFF1F5F9);
  static const iconBgD = Color(0x14FFFFFF);

  static const gas = Color(0xFF3B82F6);
  static const ev = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);

  // 미획득 실루엣 틴트
  static const silhouetteL = Color(0xFFCBD5E1);
  static const silhouetteListD = Color(0xFF8B9CB1);
  static const silhouettePopupD = Color(0xFF9FB0C3);

  static Color bg(bool d) => d ? bgD : bgL;
  static Color card(bool d) => d ? cardD : cardL;
  static Color cardBorder(bool d) => d ? cardBorderD : cardBorderL;
  static Color ink(bool d) => d ? inkD : inkL;
  static Color muted(bool d) => d ? mutedD : mutedL;
  static Color faint(bool d) => d ? faintD : faintL;
  static Color iconBg(bool d) => d ? iconBgD : iconBgL;
  static Color silhouette(bool d, {bool popup = false}) =>
      d ? (popup ? silhouettePopupD : silhouetteListD) : silhouetteL;
}

/// 등급별 토큰 — README 표를 그대로 옮김.
class CheerTierTheme {
  final int level;
  final String name;
  final int threshold;
  final String carAsset;
  final String silAsset;

  /// 등급 상세 팝업 설명 (2줄)
  final String popupDesc;

  /// 승급 오버레이 오버라인 · 서브 카피
  final String promoOverline;
  final String promoSub;

  final Color _labelL, _labelD;
  final List<Color> _cardBgL, _cardBgD;
  final Color _cardBorderD;
  final List<Color> _ring;
  final Color _glowL, _glowD;
  final List<Color> _cta; // 1개면 단색, 2개면 그라데이션
  final Color _ctaD; // 1단계만 다크에서 CTA 색이 다름

  const CheerTierTheme._({
    required this.level,
    required this.name,
    required this.threshold,
    required this.carAsset,
    required this.silAsset,
    required this.popupDesc,
    required this.promoOverline,
    required this.promoSub,
    required Color labelL,
    required Color labelD,
    required List<Color> cardBgL,
    required List<Color> cardBgD,
    required Color cardBorderD,
    required List<Color> ring,
    required Color glowL,
    required Color glowD,
    required List<Color> cta,
    Color? ctaD,
  })  : _labelL = labelL,
        _labelD = labelD,
        _cardBgL = cardBgL,
        _cardBgD = cardBgD,
        _cardBorderD = cardBorderD,
        _ring = ring,
        _glowL = glowL,
        _glowD = glowD,
        _cta = cta,
        _ctaD = ctaD ?? const Color(0x00000000);

  Color label(bool d) => d ? _labelD : _labelL;

  /// 다크 4단계 라벨은 그라데이션(#E2E8F0→#8B96A5) — ShaderMask 로 그린다.
  bool get labelIsGradientDark => level == 4;
  static const blackLabelGradient = [Color(0xFFE2E8F0), Color(0xFF8B96A5)];

  List<Color> cardBg(bool d) => d ? _cardBgD : _cardBgL;
  Color cardBorder(bool d) => d ? _cardBorderD : CheerDs.cardBorderL;
  List<Color> ring(bool d) => _ring;
  Color glow(bool d) => d ? _glowD : _glowL;

  /// CTA 배경 — 4단계는 그라데이션 + 흰 텍스트, 나머지 단색.
  List<Color> ctaColors(bool d) {
    if (level == 1) return [d ? _ctaD : _cta.first];
    return _cta;
  }

  Widget car({double? width, double? height, BoxFit fit = BoxFit.contain}) =>
      SvgPicture.asset(carAsset, width: width, height: height, fit: fit);

  Widget silhouette(Color color,
          {double? width, double? height, BoxFit fit = BoxFit.contain}) =>
      SvgPicture.asset(silAsset,
          width: width,
          height: height,
          fit: fit,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn));

  static const tiers = [
    CheerTierTheme._(
      level: 1,
      name: '쿠페 서포터',
      threshold: 1,
      carAsset: 'assets/cheer/car_tier1_coupe.svg',
      silAsset: 'assets/cheer/sil_tier1_coupe.svg',
      popupDesc: '국산 쿠페 패스트백이에요.\n첫 응원 한 번이면 바로 도착해요.',
      promoOverline: '첫 뱃지 획득',
      promoSub: '첫 응원 완료 — 개러지에 첫 차가 들어왔어요',
      labelL: Color(0xFF475569),
      labelD: Color(0xFFB7C4D4),
      cardBgL: [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
      cardBgD: [Color(0xFF141821), Color(0xFF0D1017)],
      cardBorderD: Color(0x14FFFFFF),
      ring: [Color(0xFFDCE4EE), Color(0xFF8FA3B8)],
      glowL: Color(0x29475569), // slate 0.16
      glowD: Color(0x4D94A3B8), // slate 0.30
      cta: [Color(0xFF475569)],
      ctaD: Color(0xFF64748B),
    ),
    CheerTierTheme._(
      level: 2,
      name: '스포츠카 서포터',
      threshold: 10,
      carAsset: 'assets/cheer/car_tier2_sports_red.svg',
      silAsset: 'assets/cheer/sil_tier2_sports.svg',
      popupDesc: '라운드 바디의 정통 스포츠카예요.\n매일 3회씩이면 나흘이면 도착해요.',
      promoOverline: '뱃지 승급',
      promoSub: '누적 10회 달성 — 개러지에 새 차가 들어왔어요',
      labelL: Color(0xFFB91C1C),
      labelD: Color(0xFFF87171),
      cardBgL: [Color(0xFFFEF2F2), Color(0xFFFEE2E2)],
      cardBgD: [Color(0xFF1E1113), Color(0xFF120A0C)],
      cardBorderD: Color(0x47DC2626), // red 0.28
      ring: [Color(0xFFF87171), Color(0xFFB91C1C)],
      glowL: Color(0x29DC2626),
      glowD: Color(0x33DC2626),
      cta: [Color(0xFFDC2626)],
    ),
    CheerTierTheme._(
      level: 3,
      name: '슈퍼카 서포터',
      threshold: 40,
      carAsset: 'assets/cheer/car_tier3_super_yellow.svg',
      silAsset: 'assets/cheer/sil_tier3_super.svg',
      popupDesc: '앵글러 웨지의 이탈리안 슈퍼카예요.\n매일 3회씩 약 2주면 도착해요.',
      promoOverline: '뱃지 승급',
      promoSub: '누적 40회 달성 — 로우 웨지가 개러지에 들어왔어요',
      labelL: Color(0xFFA16207),
      labelD: Color(0xFFFACC15),
      cardBgL: [Color(0xFFFEFBEB), Color(0xFFFCEFC0)],
      cardBgD: [Color(0xFF1A1504), Color(0xFF0D0A02)],
      cardBorderD: Color(0x47CA8A04), // gold 0.28
      ring: [Color(0xFFFDE047), Color(0xFFCA8A04)],
      glowL: Color(0x33CA8A04),
      glowD: Color(0x38CA8A04),
      cta: [Color(0xFFCA8A04)],
    ),
    CheerTierTheme._(
      level: 4,
      name: '하이퍼카 서포터',
      threshold: 120,
      carAsset: 'assets/cheer/car_tier4_hyper_black.svg',
      silAsset: 'assets/cheer/sil_tier4_hyper.svg',
      popupDesc: '가장 낮고 사나운 블랙라벨이에요.\n매일 3회씩 약 40일이면 도착해요.',
      promoOverline: '최고 등급 달성',
      promoSub: '누적 120회 달성 — 가장 낮고 사나운 차가 왔어요',
      labelL: Color(0xFF1F2937),
      labelD: Color(0xFFC7D0DC), // ShaderMask 폴백색
      cardBgL: [Color(0xFFF3F4F6), Color(0xFFE3E6EB)],
      cardBgD: [Color(0xFF1A1E26), Color(0xFF0B0D12)],
      cardBorderD: Color(0x4794A3B8), // silver 0.28
      ring: [Color(0xFF8B96A5), Color(0xFF1F242C)],
      glowL: Color(0x33475569),
      glowD: Color(0x3394A3B8),
      cta: [Color(0xFF4A515C), Color(0xFF14171D)],
    ),
  ];

  static CheerTierTheme byLevel(int level) =>
      tiers[(level - 1).clamp(0, tiers.length - 1)];

  /// 누적 횟수 → 현재 등급 (0회면 null)
  static CheerTierTheme? of(int total) {
    CheerTierTheme? cur;
    for (final t in tiers) {
      if (total >= t.threshold) cur = t;
    }
    return cur;
  }

  /// 다음 등급 (최고면 null)
  static CheerTierTheme? nextOf(int total) {
    for (final t in tiers) {
      if (total < t.threshold) return t;
    }
    return null;
  }
}
