import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'savings_share_card.dart';

/// 보상 카드 상세 행 (라벨 — 값)
typedef RevealFact = ({String label, String value});

/// AI 추천 결과 진입 시 "이만큼 절약"을 게임 보상풍 카드로 보여주는 오버레이.
/// - 등장: 스케일 팝(elasticOut) + 글로우 + 스파클
/// - 종료: [확인] 버튼 또는 바깥 탭 (자동으로 사라지지 않음)
/// - 내용: 헤드라인(절약액) + 추천 스테이션명 + 핵심 수치(가격/예상비용/추가시간 등)
class SavingsRevealOverlay extends StatefulWidget {
  final String caption; // 작은 줄 (예: '4분 더 걸리지만' / '주변 평균 대비')
  final String headline; // 큰 줄 (예: '28,000원 절감!')
  final String? stationName; // 추천 주유소/충전소명
  final IconData stationIcon; // local_gas_station / ev_station
  final List<RevealFact> facts; // 상세 수치 행
  final bool isEv; // 충전=초록 / 주유=파랑 (앱 전체 색 규칙)

  const SavingsRevealOverlay({
    super.key,
    required this.caption,
    required this.headline,
    this.stationName,
    this.stationIcon = Icons.local_gas_station_rounded,
    this.facts = const [],
    this.isEv = false,
  });

  /// 절감액 헤드라인 포맷 헬퍼
  static String won(int v) => '${NumberFormat('#,###').format(v)}원';

  @override
  State<SavingsRevealOverlay> createState() => _SavingsRevealOverlayState();
}

class _SavingsRevealOverlayState extends State<SavingsRevealOverlay>
    with TickerProviderStateMixin {
  // 충전은 초록, 주유는 파랑 — 결과 화면·마커와 같은 규칙
  Color get _accent =>
      widget.isEv ? const Color(0xFF34D399) : const Color(0xFF5B9DF9);
  Color get _accentFg =>
      widget.isEv ? const Color(0xFF06281C) : const Color(0xFF0A2647);
  late final AnimationController _in; // 등장 팝
  late final AnimationController _out; // 페이드아웃
  late final AnimationController _sparkle; // 반짝 루프
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _in = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _out = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _sparkle = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HapticFeedback.mediumImpact();
      _in.forward();
    });
  }

  void _dismiss() {
    if (_closing || !mounted) return;
    _closing = true;
    _out.forward().whenComplete(() {
      if (mounted) setState(() {}); // _out.isCompleted → 자체 제거
    });
  }

  @override
  void dispose() {
    _in.dispose();
    _out.dispose();
    _sparkle.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    // 인스타는 피드 4:5, 스토리 9:16 이 서로 달라 어디에 올릴지 먼저 고른다.
    final story = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        final muted = dark ? Colors.white60 : const Color(0xFF64748B);
        Widget item(
                bool isStory, String title, String sub, double w, double h) =>
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              title: Text(title,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700)),
              subtitle: Text(sub, style: TextStyle(fontSize: 12, color: muted)),
              trailing:
                  Icon(Icons.chevron_right_rounded, size: 20, color: muted),
              onTap: () => Navigator.pop(ctx, isStory),
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 14),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: dark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            const Text('어디에 올릴까요?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            item(false, '피드', '인스타 피드 (4:5)', 22, 27.5),
            item(true, '스토리 · 릴스', '인스타 스토리 (9:16)', 18, 32),
            const SizedBox(height: 12),
          ]),
        );
      },
    );
    if (story == null || !mounted) return;
    await SavingsShare.shareCard(
      context,
      caption: widget.caption,
      headline: widget.headline,
      isEv: widget.isEv,
      stationName: widget.stationName,
      facts: widget.facts,
      story: story,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_out.isCompleted) return const SizedBox.shrink();
    final pop = CurvedAnimation(parent: _in, curve: Curves.elasticOut);
    final fadeIn = CurvedAnimation(
        parent: _in, curve: const Interval(0, 0.35, curve: Curves.easeOut));
    final cardW = math.min(MediaQuery.of(context).size.width - 48, 340.0);
    // 유종 색으로 꽉 채운 카드 — 라이트에서 흰 배경이면 밋밋해서 테마와 무관하게
    // 주유=딥블루 / 충전=딥그린 그라데이션 위에 흰 글씨로 간다(공유 이미지와 같은 톤).
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 색으로 전체를 칠하지 않는다 — 거의 검정 캔버스 + 액센트는 글로우와 숫자에만.
    final cardColors = widget.isEv
        ? const [Color(0xFF0A1A14), Color(0xFF06120E)]
        : const [Color(0xFF0B1220), Color(0xFF060A11)];
    final cardBorder = Colors.white.withValues(alpha: 0.18);
    final captionColor = Colors.white.withValues(alpha: 0.82);
    final accentSoft =
        widget.isEv ? const Color(0xFF5EEAD4) : const Color(0xFF7DD3FC);
    final headlineColors = [Colors.white, accentSoft, _accent];
    const badgeFg = Colors.white;
    final panelBg = Colors.black.withValues(alpha: 0.24);
    final panelBorder = Colors.white.withValues(alpha: 0.12);
    const nameColor = Colors.white;
    final factLabelColor = Colors.white.withValues(alpha: 0.62);
    const factValueColor = Colors.white;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismiss, // 바깥 탭으로도 닫힘 (버튼이 기본 동선)
        child: FadeTransition(
          opacity: ReverseAnimation(_out),
          child: FadeTransition(
            opacity: fadeIn,
            child: Container(
              color: Colors.black.withValues(alpha: 0.6),
              alignment: Alignment.center,
              child: ScaleTransition(
                scale: Tween(begin: 0.7, end: 1.0).animate(pop),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // 뒤 글로우 (연둣빛 방사형)
                    IgnorePointer(
                      child: Container(
                        width: 380,
                        height: 380,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              _accent.withValues(alpha: 0.28),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 스파클 — 카드 주위를 돌며 깜빡임
                    IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _sparkle,
                        builder: (_, __) {
                          final t = _sparkle.value;
                          return Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: List.generate(6, (i) {
                              final ang =
                                  (i / 6) * 2 * math.pi + t * 2 * math.pi;
                              final r = cardW / 2 +
                                  26 +
                                  8 * math.sin(t * 2 * math.pi + i);
                              final op = 0.35 +
                                  0.65 *
                                      ((math.sin(t * 2 * math.pi * 2 +
                                                  i * 1.3) +
                                              1) /
                                          2);
                              return Transform.translate(
                                offset: Offset(
                                    r * math.cos(ang), r * math.sin(ang) * 0.9),
                                child: Opacity(
                                  opacity: op,
                                  child: Icon(Icons.auto_awesome_rounded,
                                      size: i.isEven ? 16 : 11,
                                      color: const Color(0xFFFFD54F)),
                                ),
                              );
                            }),
                          );
                        },
                      ),
                    ),
                    // ── 보상 카드 ──
                    GestureDetector(
                      onTap: () {}, // 카드 내부 탭은 닫힘 방지
                      child: Container(
                        width: cardW,
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: cardColors,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cardBorder),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: isDark ? 0.4 : 0.18),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 'AI 추천' 뱃지
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF34D399)
                                    .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: const Color(0xFF34D399)
                                        .withValues(alpha: 0.4)),
                              ),
                              child: Text('AI 추천',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: badgeFg,
                                      letterSpacing: 1)),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              widget.caption,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: captionColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // 헤드라인 — 골드→그린 그라데이션
                            ShaderMask(
                              shaderCallback: (rect) => LinearGradient(
                                colors: headlineColors,
                              ).createShader(rect),
                              child: Text(
                                widget.headline,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            // ── 추천 스테이션 + 상세 수치 ──
                            if (widget.stationName != null &&
                                widget.stationName!.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                decoration: BoxDecoration(
                                  color: panelBg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: panelBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(widget.stationIcon,
                                            size: 16,
                                            color: const Color(0xFF6EE7B7)),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            widget.stationName!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: nameColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (widget.facts.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      for (final f in widget.facts)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 3),
                                          child: Row(
                                            children: [
                                              Text(f.label,
                                                  style: TextStyle(
                                                      fontSize: 12.5,
                                                      color: factLabelColor)),
                                              const Spacer(),
                                              Text(f.value,
                                                  style: TextStyle(
                                                      fontSize: 13.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: factValueColor)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                // 인스타 피드 규격(1:1) 이미지로 만들어 공유
                                SizedBox(
                                  height: 46,
                                  child: OutlinedButton.icon(
                                    onPressed: _share,
                                    icon: const Icon(Icons.ios_share_rounded,
                                        size: 17),
                                    label: const Text('공유',
                                        style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _accent,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      side: BorderSide(
                                          color:
                                              _accent.withValues(alpha: 0.55)),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(13)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SizedBox(
                                    height: 46,
                                    child: FilledButton(
                                      onPressed: _dismiss,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _accent,
                                        foregroundColor: _accentFg,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(13)),
                                      ),
                                      child: const Text('확인',
                                          style: TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w800)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
