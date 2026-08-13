import 'dart:math' as math;

import 'package:flutter/material.dart';

/// handoff 3 골드 토큰 — 마이페이지 프로필 카드 · 계정 관리 · 상장/공유 카드가 공유한다.
class CheerGold {
  CheerGold._();

  // 카드 배경 / 보더
  //
  // 라이트는 **브랜드 메쉬**다 — 좌상단 블루 → 가운데 화이트 → 우하단 그린.
  // 골드 크림을 썼더니 앱 배경(#F8FAFB, 차가운 회백) 위에서 베이지 종이처럼
  // 죽었고, 무엇보다 이 앱의 색이 아니었다(로고가 블루→그린). 골드는 상장에만 남긴다.
  // 다크는 어두운 바탕에서 알파 골드가 실제로 발광하므로 그대로 둔다.
  static const cardL = [
    Color(0xFFEDF3FE), // 좌상단 블루 기운
    Color(0xFFFDFEFF), // 가운데 화이트
    Color(0xFFE9F7F0), // 우하단 그린 기운
  ];
  static const cardD = [Color(0x24E3B54C), Color(0x08E3B54C)];
  static const borderL = Color(0xFFDFE9F6);
  static const borderD = Color(0x47E3B54C);

  /// 카드를 배경에서 띄우는 그림자 — 라이트 전용(다크는 그림자가 안 보인다).
  /// 순검정이 아니라 브랜드 블루 계열이라 메쉬와 같은 톤으로 번진다.
  static List<BoxShadow> shadow(bool d) => d
      ? const []
      : const [
          BoxShadow(
              color: Color(0x143B82F6), blurRadius: 18, offset: Offset(0, 6)),
          BoxShadow(
              color: Color(0x0F64748B), blurRadius: 3, offset: Offset(0, 1)),
        ];

  /// 라이트 카드의 메쉬 글로우 — 좌상단 블루 · 우하단 그린.
  /// 단색 그라데이션만으로는 '메쉬'가 안 나와서 두 겹을 얹는다.
  static const meshBlue = Color(0xFF3B82F6);
  static const meshGreen = Color(0xFF10B981);

  /// 라이트 아바타 링 — 브랜드 블루→그린. 골드 링은 라이트 메쉬 위에서 튄다.
  static const ringL = [
    Color(0xFF60A5FA),
    Color(0xFF10B981),
    Color(0xFF34D399),
    Color(0xFF3B82F6),
    Color(0xFF60A5FA),
  ];

  /// 원형 골드 링(다크) — CSS conic-gradient(from 210deg, …) 를 그대로 옮긴 값
  static const ring = [
    Color(0xFFFDF3D0),
    Color(0xFFC9962B),
    Color(0xFFFDE68A),
    Color(0xFF8C6A10),
    Color(0xFFFDF3D0),
  ];

  /// 링 안쪽 원 — 카드 바탕과 같은 색이어야 링이 테두리처럼 보인다
  static const innerL = Color(0xFFFFFFFF);
  static const innerD = Color(0xFF141A14);

  static const twinkleL = Color(0xFFE3B54C);
  static const twinkleL2 = Color(0xFFF0C86A);
  static const twinkleD = Color(0xFFFDE68A);
  static const twinkleD2 = Color(0xFFFFFFFF);

  /// 골드 pill (배지)
  static const pillBgL = Color(0xFFF9EDD3);
  static const pillFgL = Color(0xFF8A6A2E);
  static const pillBgD = Color(0x2EE3B54C);
  static const pillFgD = Color(0xFFFCEBB6);

  /// 상장 본문 톤
  static const inkOnGoldL = Color(0xFF2A2416);
  static const inkOnGoldD = Color(0xFFF7F2E4);
  static const subOnGoldL = Color(0xFF8A7C5C);
  static const subOnGoldD = Color(0xFFA89B7E);
  static const capL = Color(0xFFB58C2E);
  static const capD = Color(0xFFE3B54C);
  static const divider = Color(0xFFC9A354);

  /// 이름 텍스트 그라데이션 (상장)
  static const nameGradL = [Color(0xFFC9962B), Color(0xFF7E5E12)];
  static const nameGradD = [Color(0xFFFDF3D0), Color(0xFFD5A021)];

  /// 등수별 메달 그라데이션 (1·2·3위)
  /// 등수별 메달 — 지시문의 3-stop radial 값.
  static List<Color> medal(int rank) => switch (rank) {
        1 => const [Color(0xFFFDE9A9), Color(0xFFE9B949), Color(0xFFC08A22)],
        2 => const [Color(0xFFF4F6F9), Color(0xFFC7CDD6), Color(0xFF99A1AC)],
        _ => const [Color(0xFFF0C9A5), Color(0xFFC97C4E), Color(0xFF9C5A32)],
      };

  /// 메달 위 숫자 색
  static Color medalInk(int rank) => switch (rank) {
        1 => const Color(0xFF3A2A05),
        2 => const Color(0xFF334155),
        _ => const Color(0xFF3A1A07),
      };

  /// 등수 라벨 색 (라이트 기준, 다크는 조금 밝게)
  static Color rankLabel(int rank, bool isDark) => switch (rank) {
        1 => isDark ? const Color(0xFFFCEBB6) : const Color(0xFF8A6A2E),
        2 => isDark ? const Color(0xFFCBD5E1) : const Color(0xFF54657A),
        _ => isDark ? const Color(0xFFE7B892) : const Color(0xFFA9612E),
      };

  static List<Color> card(bool d) => d ? cardD : cardL;
  static List<Color> avatarRing(bool d) => d ? ring : ringL;
  static Color border(bool d) => d ? borderD : borderL;
  static Color inner(bool d) => d ? innerD : innerL;
  static Color inkOnGold(bool d) => d ? inkOnGoldD : inkOnGoldL;
  static Color subOnGold(bool d) => d ? subOnGoldD : subOnGoldL;
  static Color cap(bool d) => d ? capD : capL;
  static List<Color> nameGrad(bool d) => d ? nameGradD : nameGradL;
  static Color pillBg(bool d) => d ? pillBgD : pillBgL;
  static Color pillFg(bool d) => d ? pillFgD : pillFgL;

  static const iconAsset = 'assets/new/app_icon_1024.png';
}

/// 골드 링 아바타 — 링(conic) + 안쪽 바탕 + 프로필.
/// 프로필 사진이 있으면 사진, 없으면 앱 아이콘(사각 테두리 금지 — 항상 원형).
class GoldAvatar extends StatelessWidget {
  final double size;
  final bool isDark;
  final String? photoUrl;

  /// 계정 관리처럼 사진을 바꿀 수 있는 자리엔 카메라 뱃지를 단다.
  final bool cameraBadge;
  final VoidCallback? onCameraTap;

  /// 지시문이 링·배지를 픽셀로 지정할 때 쓴다. 비우면 56px 기준 비율.
  final double? ringWidth;
  final double? badgeSize;

  const GoldAvatar({
    super.key,
    required this.size,
    required this.isDark,
    this.photoUrl,
    this.cameraBadge = false,
    this.onCameraTap,
    this.ringWidth,
    this.badgeSize,
  });

  @override
  Widget build(BuildContext context) {
    // 시안 비율 — 56px 기준 링 2.5 / 안쪽 여백 5
    final ringW = ringWidth ?? size * (2.5 / 56);
    final pad = ringW + size * (2.5 / 56);
    final inner = CheerGold.inner(isDark);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: CheerGold.avatarRing(isDark),
                // CSS conic 의 0° 는 12시, Flutter 는 3시 — 210° → 120°
                transform: const GradientRotation(120 * math.pi / 180),
              ),
            ),
            padding: EdgeInsets.all(ringW),
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, color: inner),
              padding: EdgeInsets.all(pad - ringW),
              child: ClipOval(
                child: (photoUrl?.isNotEmpty ?? false)
                    ? Image.network(photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _icon())
                    : _icon(),
              ),
            ),
          ),
          if (cameraBadge)
            Positioned(
              right: -2,
              bottom: -2,
              child: GestureDetector(
                onTap: onCameraTap,
                child: Container(
                  width: badgeSize ?? size * (23 / 64),
                  height: badgeSize ?? size * (23 / 64),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF3B82F6),
                    border: Border.all(color: inner, width: 2.5),
                  ),
                  child: Icon(Icons.photo_camera_rounded,
                      size: (badgeSize ?? size * (23 / 64)) * 0.52,
                      color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _icon() =>
      Image.asset(CheerGold.iconAsset, fit: BoxFit.cover);
}

/// 계정 관리 프로필 카드 — 라이트는 **브랜드 메쉬**(블루→그린), 다크는 골드.
///
/// ★ 정렬 주의: 닉네임 옆 연필 아이콘 때문에 이름이 왼쪽으로 밀린다.
///   [이름 + 6 + 아이콘15] 묶음을 Column 이 가운데 놓으면 **이름 자체는 10.5px
///   왼쪽**이 되고, 아래 이메일(정중앙)과 어긋나 보인다. 그래서 왼쪽에 아이콘과
///   같은 폭을 비워 이름이 실제 카드 중앙에 오게 한다.

/// 계정 관리 프로필 카드.
///
/// 라이트는 **브랜드 메쉬**(Blue #3B82F6 → Green #10B981) — 프로필카드_배경_지시문 1a안.
/// 크림/골드는 버렸다(앱 로고가 블루→그린인데 골드는 남의 옷이었다).
/// 다크는 어두운 바탕에서 알파 골드가 실제로 발광하므로 그대로 둔다.
///
/// ★ 정렬 주의: 닉네임 옆 연필 때문에 [이름 + gap + 아이콘] 묶음을 가운데 놓으면
///   이름 자체가 왼쪽으로 밀린다. 왼쪽에 같은 폭을 비워 이름이 실제 중앙에 오게 한다.
class BrandProfileCard extends StatefulWidget {
  final bool isDark;

  /// 아바타 위젯 — 사진 변경 시트 같은 동작을 감싸서 넘긴다.
  final Widget avatar;
  final String nickname;
  final String email;
  final String? ageGroup;
  final VoidCallback? onEditNickname;

  const BrandProfileCard({
    super.key,
    required this.isDark,
    required this.avatar,
    required this.nickname,
    required this.email,
    this.ageGroup,
    this.onEditNickname,
  });

  @override
  State<BrandProfileCard> createState() => _BrandProfileCardState();
}

class _BrandProfileCardState extends State<BrandProfileCard>
    with SingleTickerProviderStateMixin {
  /// ★ initState 에서 반드시 만든다. `late final ... = AnimationController(...)` 로
  ///   두면 지연 초기화라, build 가 이 필드를 안 쓰는 경우(라이트 — 트윙클이 다크 전용)
  ///   한 번도 생성되지 않는다. 그 상태로 화면을 나가면 dispose 가 필드를 **처음**
  ///   건드리면서 비활성 element 에서 ticker 를 만들다 크래시한다.
  late final AnimationController _tw;

  /// 연필 아이콘 폭 + 간격 — 왼쪽에 같은 만큼 비워 이름을 실제 중앙에 놓는다.
  static const _pencil = 20.0;
  static const _gap = 6.0;

  @override
  void initState() {
    super.initState();
    _tw = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4000));
    if (widget.isDark) _tw.repeat();
  }

  @override
  void didUpdateWidget(BrandProfileCard old) {
    super.didUpdateWidget(old);
    if (widget.isDark && !_tw.isAnimating) {
      _tw.repeat();
    } else if (!widget.isDark && _tw.isAnimating) {
      _tw.stop();
    }
  }

  @override
  void dispose() {
    _tw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final ink = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final sub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            // CSS 135deg = 좌상단 → 우하단
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? CheerGold.cardD
                : const [
                    Color(0xFFEDF4FF),
                    Color(0xFFE6F4F5),
                    Color(0xFFE3F6EC),
                  ],
            stops: isDark ? null : const [0, 0.55, 1],
          ),
          border: Border.all(
              color: isDark ? CheerGold.borderD : const Color(0xFFDCE7F5),
              width: 0.5),
          // elevation 0 — 지시문 원칙(그림자 쓰지 말 것)
        ),
        child: Stack(
          children: [
            if (!isDark) ..._lightDecor() else ..._darkDecor(),
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    widget.avatar,
                    const SizedBox(height: 14),
                    _nameRow(ink, isDark),
                    const SizedBox(height: 4),
                    Text(widget.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: sub)),
                    if (widget.ageGroup?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6)
                              .withValues(alpha: isDark ? 0.20 : 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(widget.ageGroup!,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? const Color(0xFF93C5FD)
                                    : const Color(0xFF2563EB))),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 라이트 데코 — 지시문의 아래→위 순서 그대로. 전부 터치를 막는다.
  List<Widget> _lightDecor() => [
        // 1) 좌상단 블루 글로우
        _glowCircle(
            top: -70, left: -50, size: 220, color: const Color(0xFF3B82F6), alpha: 0.32),
        // 2) 우하단 그린 글로우
        _glowCircle(
            bottom: -80, right: -40, size: 240, color: const Color(0xFF10B981), alpha: 0.30),
        // 3) 도트 그리드 — 가운데만 진하고 가장자리로 사라진다
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.45,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (r) => const RadialGradient(
                  center: Alignment(0, -0.2), // 50% / 40%
                  radius: 0.78,
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0, 0.2, 1],
                ).createShader(r),
                child: CustomPaint(painter: const _DotGrid()),
              ),
            ),
          ),
        ),
        // 4) 아바타 뒤 동심원 링 2개
        _ring(top: 14, size: 236, alpha: 0.75),
        _ring(top: 44, size: 176, alpha: 0.9),
        // 5) 대각선 하이라이트
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-1, -0.45), // ≈115°
                  end: const Alignment(1, 0.45),
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.55),
                    Colors.white.withValues(alpha: 0),
                  ],
                  stops: const [0.30, 0.48, 0.62],
                ),
              ),
            ),
          ),
        ),
        // 6) 상단 이너 하이라이트 1px
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
                height: 1, color: Colors.white.withValues(alpha: 0.9)),
          ),
        ),
      ];

  /// 다크는 기존 골드 트윙클 유지 — 어두운 바탕에서 알파 골드가 발광한다.
  List<Widget> _darkDecor() => [
        Positioned(
            left: 14,
            top: 14,
            child: GoldTwinkle(anim: _tw, size: 10, color: CheerGold.twinkleD)),
        Positioned(
            right: 16,
            top: 26,
            child: GoldTwinkle(
                anim: _tw, size: 8, delaySec: 0.6, color: CheerGold.twinkleD2)),
      ];

  Widget _glowCircle({
    double? top,
    double? left,
    double? right,
    double? bottom,
    required double size,
    required Color color,
    required double alpha,
  }) =>
      Positioned(
        top: top,
        left: left,
        right: right,
        bottom: bottom,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: 0),
              ], stops: const [0, 0.7]),
            ),
          ),
        ),
      );

  /// 가로 중앙 정렬 동심원 — left/right 0 + Center 로 카드 폭과 무관하게 가운데.
  Widget _ring({required double top, required double size, required double alpha}) =>
      Positioned(
        top: top,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: alpha), width: 1),
              ),
            ),
          ),
        ),
      );

  /// 왼쪽 여백(_pencil + _gap)이 오른쪽 아이콘과 균형을 맞춰 **이름이 실제 중앙**에 온다.
  Widget _nameRow(Color ink, bool isDark) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onEditNickname,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: _pencil + _gap),
                Flexible(
                  child: Text(widget.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: ink)),
                ),
                const SizedBox(width: _gap),
                Icon(Icons.edit_rounded,
                    size: _pencil,
                    color: isDark
                        ? const Color(0xFFD9B871)
                        : const Color(0xFF3B82F6)),
              ],
            ),
          ),
        ),
      );
}

/// 카드 배경 도트 그리드 — 1px 점, 14px 간격.
class _DotGrid extends CustomPainter {
  const _DotGrid();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.10);
    const gap = 14.0;
    for (var y = gap / 2; y < size.height; y += gap) {
      for (var x = gap / 2; x < size.width; x += gap) {
        canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGrid old) => false;
}

/// 수상 메달 줄 — 최대 3개를 가로로. 3개를 못 채워도 **가운데 정렬**이다.
///
/// 각 메달에 [Expanded] 를 주고 남는 칸을 뒤에만 [Spacer] 로 채우면 메달이 왼쪽으로
/// 쏠린다(1개일 때 1/6 지점). 양쪽에 같은 flex 를 두어 균형을 맞춘다 —
/// 메달 flex 2 · 좌우 여백 flex (3 - 개수) 면 3개일 때 1/3 배치와 정확히 같고,
/// 1·2개일 때만 가운데로 모인다.
class AwardMedals extends StatelessWidget {
  /// (등수, 라벨) — 라벨은 '8월 1위' 처럼 이미 만들어진 문자열
  final List<({int rank, String label})> items;
  final bool isDark;
  final double size;

  const AwardMedals(
      {super.key, required this.items, required this.isDark, this.size = 62});

  @override
  Widget build(BuildContext context) {
    final shown = items.take(3).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final pad = 3 - shown.length;
    return Row(
      children: [
        if (pad > 0) Spacer(flex: pad),
        for (final it in shown)
          Expanded(flex: 2, child: _medal(it.rank, it.label)),
        if (pad > 0) Spacer(flex: pad),
      ],
    );
  }

  Widget _medal(int rank, String label) => Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // 지시문 원칙: 그림자 쓰지 말 것 — radial 로만 입체감을 낸다.
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.4),
                radius: 0.95,
                colors: CheerGold.medal(rank),
              ),
            ),
            alignment: Alignment.center,
            child: Text('$rank',
                style: TextStyle(
                    fontSize: size * (20 / 62),
                    fontWeight: FontWeight.w800,
                    color: CheerGold.medalInk(rank))),
          ),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: CheerGold.rankLabel(rank, isDark))),
        ],
      );
}

/// ✦ 트윙클 — 4초 루프, 55~88% 구간에만 반짝인다(시안 cwTw).
/// 카드 모서리 장식용이라 [delaySec] 으로 서로 어긋나게 배치한다.
class GoldTwinkle extends StatelessWidget {
  final Animation<double> anim; // 0~1 (4초 루프)
  final double size;
  final Color color;
  final double delaySec;

  const GoldTwinkle({
    super.key,
    required this.anim,
    required this.size,
    required this.color,
    this.delaySec = 0,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final p = (anim.value - delaySec / 4) % 1.0;
        double op = 0, sc = 0.4, rot = 0;
        if (p >= 0.55 && p <= 0.88) {
          if (p <= 0.65) {
            final k = (p - 0.55) / 0.10;
            op = k;
            sc = 0.4 + 0.75 * k;
            rot = 16 * k;
          } else if (p <= 0.78) {
            final k = (p - 0.65) / 0.13;
            op = 1 - 0.55 * k;
            sc = 1.15 - 0.3 * k;
            rot = 16 + 12 * k;
          } else {
            final k = (p - 0.78) / 0.10;
            op = 0.45 * (1 - k);
            sc = 0.85;
            rot = 28;
          }
        }
        if (op <= 0) return const SizedBox.shrink();
        return IgnorePointer(
          child: Opacity(
            opacity: op.clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: rot * math.pi / 180,
              child: Transform.scale(
                scale: sc,
                child: Text('✦',
                    style: TextStyle(
                        fontSize: size, height: 1, color: color)),
              ),
            ),
          ),
        );
      },
    );
  }
}
