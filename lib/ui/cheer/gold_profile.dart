import 'dart:math' as math;

import 'package:flutter/material.dart';

/// handoff 3 골드 토큰 — 마이페이지 프로필 카드 · 계정 관리 · 상장/공유 카드가 공유한다.
class CheerGold {
  CheerGold._();

  // 카드 배경 (150~160° 그라데이션) / 보더
  //
  // 라이트는 앱 배경이 #F8FAFB(차가운 회백)이다. 여기에 거의 흰 크림을 얹으면
  // 명도 차가 없어 카드가 안 떠 보이고 골드도 베이지 종이처럼 죽는다. 그래서
  // ① 끝색을 샴페인까지 내리고 ② 보더를 실제 금색 라인으로 세우고
  // ③ 아주 옅은 골드 그림자로 배경에서 띄운다. 다크는 어두운 바탕에서 알파 골드가
  // 이미 발광하므로 그대로 둔다.
  static const cardL = [Color(0xFFFFFEFA), Color(0xFFF7E8C8)];
  static const cardD = [Color(0x24E3B54C), Color(0x08E3B54C)];
  static const borderL = Color(0xFFE4CFA2);
  static const borderD = Color(0x47E3B54C);

  /// 카드를 배경에서 띄우는 골드 톤 그림자 — 라이트 전용(다크는 그림자가 안 보인다).
  /// 순검정이 아니라 금빛이라 크림 카드와 같은 계열로 번진다.
  static List<BoxShadow> shadow(bool d) => d
      ? const []
      : const [
          BoxShadow(
              color: Color(0x1FA07828), blurRadius: 16, offset: Offset(0, 6)),
          BoxShadow(
              color: Color(0x0F8C6A10), blurRadius: 3, offset: Offset(0, 1)),
        ];

  /// 원형 골드 링 — CSS conic-gradient(from 210deg, …) 를 그대로 옮긴 값
  static const ring = [
    Color(0xFFFDF3D0),
    Color(0xFFC9962B),
    Color(0xFFFDE68A),
    Color(0xFF8C6A10),
    Color(0xFFFDF3D0),
  ];

  /// 링 안쪽 원 — 카드 바탕과 같은 색이어야 링이 테두리처럼 보인다
  static const innerL = Color(0xFFFFFEFA);
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
  static List<Color> medal(int rank) => switch (rank) {
        1 => const [Color(0xFFFDF3D0), Color(0xFFC9962B)],
        2 => const [Color(0xFFF5F8FB), Color(0xFF8E9BAC)],
        _ => const [Color(0xFFF7D5BC), Color(0xFFA9612E)],
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

  const GoldAvatar({
    super.key,
    required this.size,
    required this.isDark,
    this.photoUrl,
    this.cameraBadge = false,
    this.onCameraTap,
  });

  @override
  Widget build(BuildContext context) {
    // 시안 비율 — 56px 기준 링 2.5 / 안쪽 여백 5
    final ringW = size * (2.5 / 56);
    final pad = size * (5 / 56);
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
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: CheerGold.ring,
                // CSS conic 의 0° 는 12시, Flutter 는 3시 — 210° → 120°
                transform: GradientRotation(120 * math.pi / 180),
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
                  width: size * (23 / 64),
                  height: size * (23 / 64),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF3B82F6),
                    border: Border.all(color: inner, width: 2.5),
                  ),
                  child: Icon(Icons.photo_camera_rounded,
                      size: size * (12 / 64), color: Colors.white),
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

/// 수상 메달 줄 — 최대 3개를 가로로. 3개를 못 채워도 **가운데 정렬**이다.
///
/// 각 메달에 [Expanded] 를 주고 남는 칸을 뒤에만 [Spacer] 로 채우면 메달이 왼쪽으로
/// 쏠린다(1개일 때 화면 1/6 지점). 양쪽에 같은 flex 를 두어 균형을 맞춘다 —
/// 메달 flex 2 · 좌우 여백 flex (3 - 개수) 면 3개일 때 기존 1/3 배치와 정확히 같고,
/// 1·2개일 때만 가운데로 모인다.
class AwardMedals extends StatelessWidget {
  /// (등수, 라벨) — 라벨은 '8월 1위' 처럼 이미 만들어진 문자열
  final List<({int rank, String label})> items;
  final bool isDark;
  final double size;

  const AwardMedals(
      {super.key,
      required this.items,
      required this.isDark,
      this.size = 38});

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
              gradient: LinearGradient(
                begin: const Alignment(-0.4, -1),
                end: const Alignment(0.4, 1),
                colors: CheerGold.medal(rank),
              ),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFA07828).withValues(alpha: 0.22),
                    blurRadius: 8,
                    offset: const Offset(0, 3)),
              ],
            ),
            alignment: Alignment.center,
            child: Text('$rank',
                style: TextStyle(
                    fontSize: size * (13 / 38),
                    fontWeight: FontWeight.w800,
                    color: CheerGold.medalInk(rank))),
          ),
          const SizedBox(height: 5),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10,
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
