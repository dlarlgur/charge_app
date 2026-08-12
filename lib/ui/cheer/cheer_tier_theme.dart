import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 응원하기 디자인 시스템 — design_handoff_supporter_badges 확정 시안의 토큰.
/// 등급 라벨 컬러: 1 실버 · 2 레드 · 3 골드 · 4 블랙. 모든 색은 라이트/다크 검증값
/// 그대로이며(README 표), 임의로 바꾸지 않는다.
class CheerDs {
  CheerDs._();

  // 화면 공통 — _ds/colors_and_type.css 토큰 그대로 (라이트 / .dark)
  static const bgL = Color(0xFFF8FAFB);
  static const bgD = Color(0xFF0C0E13);
  static const cardL = Colors.white;
  static const cardD = Color(0x08FFFFFF); // rgba(255,255,255,0.03)
  static const cardBorderL = Color(0xFFE8ECF0);
  static const cardBorderD = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
  // 틱 등 강조 보더 — --card-border-strong
  static const cardBorderStrongL = Color(0xFFDDE3EC);
  static const cardBorderStrongD = Color(0x14FFFFFF);
  static const inkL = Color(0xFF0F172A);
  static const inkD = Color(0xFFF1F5F9);
  // --text-secondary
  static const secondaryL = Color(0xFF64748B);
  static const secondaryD = Color(0xFF94A3B8);
  // --text-muted
  static const mutedL = Color(0xFF94A3B8);
  static const mutedD = Color(0xFF475569);
  static const iconBgL = Color(0xFFF1F5F9);
  static const iconBgD = Color(0xFF1E293B);
  // 반투명 다크 카드 위에 불투명이 필요한 곳(게이지 허브) — bg+card 합성 근사
  static const cardSolidD = Color(0xFF14161B);
  // 계기판 허브·존 갭처럼 '카드색 그대로'가 필요한 자리 (handoff 2 시안 #15171D)
  static const gaugeSolidD = Color(0xFF15171D);

  // ─── handoff 2 · 계기판(컬러 존 세그먼트) ───
  /// E→F 존 5색. 각 33°(첫 존 34°·끝 존 35°), 갭 3° — 합 180°
  static const gaugeZones = [
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFFFBBF24),
    Color(0xFFA3E635),
    Color(0xFF10B981),
  ];
  static const gaugeTrackL = Color(0xFFEEF1F4);
  static const gaugeTrackD = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
  static const needleFrom = Color(0xFFEF4444);
  static const needleTo = Color(0xFFF87171);
  static const efLabelL = Color(0xFF94A3B8);
  static const efLabelD = Color(0xFF7C8798);
  /// 숫자 옆 '/ 300' 슬래시 톤
  static const slashL = Color(0xFFCBD5E1);
  static const slashD = Color(0xFF475569);
  /// CTA 블루 그라디언트 (135°)
  static const ctaBlue = [Color(0xFF60A5FA), Color(0xFF2563EB)];
  /// 리워드 연출 강조 (숫자 스왑·+100·카피)
  static const rewardAccentL = Color(0xFF2563EB);
  static const rewardAccentD = Color(0xFF93C5FD);

  static Color gaugeTrack(bool d) => d ? gaugeTrackD : gaugeTrackL;
  static Color efLabel(bool d) => d ? efLabelD : efLabelL;
  static Color slash(bool d) => d ? slashD : slashL;
  static Color rewardAccent(bool d) => d ? rewardAccentD : rewardAccentL;
  /// 존 사이 갭 = 카드 바탕색
  static Color gaugeGap(bool d) => d ? gaugeSolidD : Colors.white;

  static const gas = Color(0xFF3B82F6);
  static const ev = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const success = Color(0xFF34D399);

  // 미획득 실루엣 틴트
  static const silhouetteL = Color(0xFFCBD5E1);
  static const silhouetteListD = Color(0xFF8B9CB1);
  static const silhouettePopupD = Color(0xFF9FB0C3);

  static Color bg(bool d) => d ? bgD : bgL;
  static Color card(bool d) => d ? cardD : cardL;
  static Color cardSolid(bool d) => d ? cardSolidD : cardL;
  static Color cardBorder(bool d) => d ? cardBorderD : cardBorderL;
  static Color cardBorderStrong(bool d) =>
      d ? cardBorderStrongD : cardBorderStrongL;
  static Color ink(bool d) => d ? inkD : inkL;
  static Color secondary(bool d) => d ? secondaryD : secondaryL;
  static Color muted(bool d) => d ? mutedD : mutedL;
  // 구 명칭 호환 — muted 보다 옅은 톤이 필요하던 자리, 시안 기준 muted 로 통일
  static Color faint(bool d) => muted(d);
  static Color iconBg(bool d) => d ? iconBgD : iconBgL;
  static Color silhouette(bool d, {bool popup = false}) =>
      d ? (popup ? silhouettePopupD : silhouetteListD) : silhouetteL;
}

/// 등급별 토큰 — README 표를 그대로 옮김.
class CheerTierTheme {
  final int level;
  final String name;

  /// 코드 기본 임계값 — 실제 판정은 아래 threshold getter 가 서버 override 를 우선한다.
  final int _threshold;

  /// 승급 임계값 — 콘솔 원격설정(cheer.tier_thresholds)이 있으면 그 값.
  /// status 응답 tierThresholds → applyThresholds() 로 반영되고 Hive 에 남아
  /// 다음 실행(오프라인 포함)에도 유지된다.
  int get threshold {
    _ensureOverridesLoaded();
    return _overrides[level] ?? _threshold;
  }

  static Map<int, int> _overrides = {};
  static bool _overridesLoaded = false;
  static const _hiveThresholdsKey = 'cheer_tier_thresholds';

  static void _ensureOverridesLoaded() {
    if (_overridesLoaded) return;
    _overridesLoaded = true;
    try {
      final raw = Hive.box('settings').get(_hiveThresholdsKey);
      if (raw is List) _applyList(raw.whereType<int>().toList(), persist: false);
    } catch (_) {}
  }

  /// 서버 status 의 tierThresholds 반영. 형식이 깨져 있으면 무시(기존 값 유지).
  static void applyThresholds(List<int>? t) {
    if (t == null) return;
    _ensureOverridesLoaded();
    _applyList(t, persist: true);
  }

  static void _applyList(List<int> t, {required bool persist}) {
    // 등급 수 일치 + 양수 + 순증 — 아니면 판정이 꼬이므로 통째로 무시.
    if (t.length != tiers.length) return;
    for (var i = 0; i < t.length; i++) {
      if (t[i] <= 0 || (i > 0 && t[i] <= t[i - 1])) return;
    }
    _overrides = {for (var i = 0; i < t.length; i++) i + 1: t[i]};
    if (persist) {
      try {
        Hive.box('settings').put(_hiveThresholdsKey, t);
      } catch (_) {}
    }
  }
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

  // ─── handoff 2 ───
  /// 히어로 스테이지 글로우 기준색 — 차 바디색을 따라간다.
  final Color heroGlow;
  final List<Color> _garageBgL, _garageBgD;
  final Color _garageBorderL, _garageBorderD;
  /// 보유 카드 우상단 뱃지 원 — 1개면 단색, 2개면 그라데이션
  final List<Color> _garageBadgeL, _garageBadgeD;
  final Color _garageSubL, _garageSubD;
  final Color _garageGlowL, _garageGlowD;

  const CheerTierTheme._({
    required this.level,
    required this.name,
    required int threshold,
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
    required this.heroGlow,
    required List<Color> garageBgL,
    required List<Color> garageBgD,
    required Color garageBorderL,
    required Color garageBorderD,
    required List<Color> garageBadgeL,
    required List<Color> garageBadgeD,
    required Color garageSubL,
    required Color garageSubD,
    required Color garageGlowL,
    required Color garageGlowD,
  })  : _threshold = threshold,
        _labelL = labelL,
        _labelD = labelD,
        _cardBgL = cardBgL,
        _cardBgD = cardBgD,
        _cardBorderD = cardBorderD,
        _ring = ring,
        _glowL = glowL,
        _glowD = glowD,
        _cta = cta,
        _ctaD = ctaD ?? const Color(0x00000000),
        _garageBgL = garageBgL,
        _garageBgD = garageBgD,
        _garageBorderL = garageBorderL,
        _garageBorderD = garageBorderD,
        _garageBadgeL = garageBadgeL,
        _garageBadgeD = garageBadgeD,
        _garageSubL = garageSubL,
        _garageSubD = garageSubD,
        _garageGlowL = garageGlowL,
        _garageGlowD = garageGlowD;

  /// 개러지 보유 카드 — 160° 그라데이션 배경 / 보더 / 뱃지 / 글로우 / 서브 텍스트
  List<Color> garageBg(bool d) => d ? _garageBgD : _garageBgL;
  Color garageBorder(bool d) => d ? _garageBorderD : _garageBorderL;
  List<Color> garageBadge(bool d) => d ? _garageBadgeD : _garageBadgeL;
  Color garageSub(bool d) => d ? _garageSubD : _garageSubL;
  Color garageGlow(bool d) => d ? _garageGlowD : _garageGlowL;

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
      glowL: Color(0x4D94A3B8), // 4a 마크업 실측 rgba(148,163,184,0.30)
      glowD: Color(0x4D94A3B8),
      cta: [Color(0xFF475569)],
      ctaD: Color(0xFF64748B),
      heroGlow: Color(0xFF94A3B8),
      garageBgL: [Color(0xFFF4F6F9), Color(0xFFE6EAF0)],
      garageBgD: [Color(0x08FFFFFF), Color(0x08FFFFFF)],
      garageBorderL: Color(0xFFE8ECF0),
      garageBorderD: Color(0x14FFFFFF),
      garageBadgeL: [Color(0xFF94A3B8)],
      garageBadgeD: [Color(0xFF64748B)],
      garageSubL: Color(0xFF94A3B8),
      garageSubD: Color(0xFF64748B),
      garageGlowL: Color(0x7394A3B8), // rgba(148,163,184,0.45)
      garageGlowD: Color(0x47CBD5E1), // rgba(203,213,225,0.28)
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
      heroGlow: Color(0xFFEF4444),
      garageBgL: [Color(0xFFFEEEEC), Color(0xFFFBDAD5)],
      garageBgD: [Color(0x29EF4444), Color(0x08EF4444)],
      garageBorderL: Color(0xFFF87171),
      garageBorderD: Color(0x80EF4444),
      garageBadgeL: [Color(0xFFEF4444)],
      garageBadgeD: [Color(0xFFEF4444)],
      garageSubL: Color(0xFFB91C1C),
      garageSubD: Color(0xFFFCA5A5),
      garageGlowL: Color(0x66EF4444), // rgba(239,68,68,0.40)
      garageGlowD: Color(0x59EF4444), // rgba(239,68,68,0.35)
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
      heroGlow: Color(0xFFF97316),
      garageBgL: [Color(0xFFFEF3E2), Color(0xFFFBE3C2)],
      garageBgD: [Color(0x2EF97316), Color(0x08F97316)],
      garageBorderL: Color(0xFFF59E0B),
      garageBorderD: Color(0x8CF97316),
      garageBadgeL: [Color(0xFFFBBF24), Color(0xFFEA580C)],
      garageBadgeD: [Color(0xFFFDE68A), Color(0xFFEA580C)],
      garageSubL: Color(0xFFB45309),
      garageSubD: Color(0xFFFDBA74),
      garageGlowL: Color(0x73F97316), // rgba(249,115,22,0.45)
      garageGlowD: Color(0x66F97316), // rgba(249,115,22,0.40)
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
      // 시안에 하이퍼카 '보유' 카드는 없다(잠금 상태만) — 실버 톤으로 같은 규칙 적용
      heroGlow: Color(0xFF94A3B8),
      garageBgL: [Color(0xFFF3F4F6), Color(0xFFE3E6EB)],
      garageBgD: [Color(0x2994A3B8), Color(0x0894A3B8)],
      garageBorderL: Color(0xFF94A3B8),
      garageBorderD: Color(0x8094A3B8),
      garageBadgeL: [Color(0xFF64748B), Color(0xFF1F2937)],
      garageBadgeD: [Color(0xFFCBD5E1), Color(0xFF64748B)],
      garageSubL: Color(0xFF334155),
      garageSubD: Color(0xFFCBD5E1),
      garageGlowL: Color(0x59475569),
      garageGlowD: Color(0x4D94A3B8),
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
