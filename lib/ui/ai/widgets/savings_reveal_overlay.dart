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
  final String? stationSub; // 스테이션 아래 한 줄 (유종 · 브랜드 · 영업시간)
  final bool isEv; // 충전=초록 / 주유=파랑 (앱 전체 색 규칙)

  const SavingsRevealOverlay({
    super.key,
    required this.caption,
    required this.headline,
    this.stationName,
    this.stationIcon = Icons.local_gas_station_rounded,
    this.facts = const [],
    this.stationSub,
    this.isEv = false,
    this.verdict,
    this.originName,
    this.destName,
    this.myUnitWon,
    this.avgUnitWon,
  });

  /// 공유 카드(시안 7a/7b)로 그대로 전달되는 부가 데이터 — 없으면 해당 조각 숨김.
  final String? verdict;
  final String? originName;
  final String? destName;
  final int? myUnitWon;
  final int? avgUnitWon;

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
  // 흰 배경에서 텍스트로 쓸 진한 유종 색 (연한 액센트는 대비가 모자란다)
  Color get _accentDeep =>
      widget.isEv ? const Color(0xFF0F9D6E) : const Color(0xFF2563EB);
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
        // 비율은 글로 설명해봐야 안 와닿는다 — 실제 카드 축소판을 나란히 놓고 고르게.
        Widget option({
          required bool isStory,
          required String title,
          required String size,
          required double ratio,
        }) =>
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.pop(ctx, isStory),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 152,
                        child: AspectRatio(
                          aspectRatio: ratio,
                          child: _MiniCardPreview(accent: _accent),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2)),
                      const SizedBox(height: 2),
                      Text(size,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    ],
                  ),
                ),
              ),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 12),
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: dark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 18),
              const Text('카드 크기 고르기',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
              const SizedBox(height: 5),
              Text('올릴 곳에 맞는 비율로 만들어 드려요',
                  style: TextStyle(fontSize: 12.5, color: muted)),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  option(
                      isStory: false,
                      title: '피드',
                      size: '1080 × 1350 · 4:5',
                      ratio: 4 / 5),
                  const SizedBox(width: 10),
                  option(
                      isStory: true,
                      title: '스토리 · 릴스',
                      size: '1080 × 1920 · 9:16',
                      ratio: 9 / 16),
                ],
              ),
              const SizedBox(height: 10),
            ]),
          ),
        );
      },
    );
    if (story == null || !mounted) return;
    final style = await _pickStyle(story);
    if (style == null || !mounted) return;
    await SavingsShare.shareCard(
      context,
      caption: widget.caption,
      headline: widget.headline,
      isEv: widget.isEv,
      stationName: widget.stationName,
      stationSub: widget.stationSub,
      facts: widget.facts,
      story: story,
      style: style,
    );
  }

  /// 크기 다음 단계 — 같은 데이터를 세 화법 중 무엇으로 보낼지 고른다.
  Future<ShareCardStyle?> _pickStyle(bool story) =>
      showModalBottomSheet<ShareCardStyle>(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) {
          final dark = Theme.of(ctx).brightness == Brightness.dark;
          final muted = dark ? Colors.white60 : const Color(0xFF64748B);
          Widget tile(ShareCardStyle st, String title, String sub) => Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    // 썸네일은 구성만 보여준다 — 실물을 보고 결정하게 한 번 띄운다.
                    final ok = await _previewStyle(ctx, st, story);
                    if (ok && ctx.mounted) Navigator.pop(ctx, st);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: story ? 132 : 116,
                          child: AspectRatio(
                            aspectRatio: story ? 9 / 16 : 4 / 5,
                            child: _StyleThumb(style: st, accent: _accent),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3)),
                        const SizedBox(height: 1),
                        Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10.5, color: muted)),
                      ],
                    ),
                  ),
                ),
              );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 12),
                Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: dark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 18),
                const Text('어떤 스타일로 만들까요?',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
                const SizedBox(height: 5),
                Text(story ? '스토리 · 릴스 (9:16)' : '인스타 피드 (4:5)',
                    style: TextStyle(fontSize: 12.5, color: muted)),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  tile(ShareCardStyle.savings, '절약액', '숫자 하나로'),
                  const SizedBox(width: 8),
                  tile(ShareCardStyle.recommend, '추천 카드', '어디를 왜'),
                  const SizedBox(width: 8),
                  tile(ShareCardStyle.receipt, '영수증', '조목조목'),
                ]),
                const SizedBox(height: 8),
              ]),
            ),
          );
        },
      );

  /// 고른 스타일을 실제 카드로 그려 보여준다. 공유 이미지와 같은 위젯이라
  /// 여기서 보이는 그대로 저장된다(캡처만 1080px 로 확대).
  Future<bool> _previewStyle(
      BuildContext ctx, ShareCardStyle st, bool story) async {
    final ok = await showDialog<bool>(
      context: ctx,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (dctx) {
        final maxW = MediaQuery.of(dctx).size.width - 56;
        final maxH = MediaQuery.of(dctx).size.height * 0.62;
        final scale = math.min(maxW / SavingsShareCard.side,
            maxH / SavingsShareCard.heightFor(story));
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Spacer(),
              // 실제 카드 그대로 축소 — 미리보기와 결과가 다르면 안 본 것만 못하다.
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: SavingsShareCard.side * scale,
                  height: SavingsShareCard.heightFor(story) * scale,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: SavingsShareCard.side,
                      height: SavingsShareCard.heightFor(story),
                      child: SavingsShareCard(
                        caption: widget.caption,
                        headline: widget.headline,
                        isEv: widget.isEv,
                        stationName: widget.stationName,
                        stationSub: widget.stationSub,
                        facts: widget.facts,
                        story: story,
                        style: st,
                        verdict: widget.verdict,
                        originName: widget.originName,
                        destName: widget.destName,
                        myUnitWon: widget.myUnitWon,
                        avgUnitWon: widget.avgUnitWon,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.45)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13)),
                      ),
                      child: const Text('다시 고르기',
                          style: TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(dctx, true),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('이걸로 공유',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: _accentFg,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13)),
                      ),
                    ),
                  ),
                ),
              ]),
              const Spacer(),
            ],
          ),
        );
      },
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    if (_out.isCompleted) return const SizedBox.shrink();
    final pop = CurvedAnimation(parent: _in, curve: Curves.elasticOut);
    final fadeIn = CurvedAnimation(
        parent: _in, curve: const Interval(0, 0.35, curve: Curves.easeOut));
    final cardW = math.min(MediaQuery.of(context).size.width - 48, 340.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 카드는 흰 종이. 유종 색은 '칠하는' 게 아니라 뱃지·숫자·상단 라인 같은
    // 포인트로만 쓴다 — 면적을 줄일수록 색이 비싸 보인다.
    final cardColors = isDark
        ? [
            Color.alphaBlend(
                _accent.withValues(alpha: 0.10), const Color(0xFF141821)),
            const Color(0xFF0E1116),
          ]
        : [
            // 위쪽만 유종 색을 아주 옅게 머금게 — 흰 카드가 밋밋해지지 않는다
            Color.alphaBlend(_accent.withValues(alpha: 0.10), Colors.white),
            Colors.white,
          ];
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.06);
    final captionColor =
        isDark ? Colors.white70 : const Color(0xFF64748B); // slate-500
    // 숫자는 유종 색 딥→라이트로 아주 살짝만 흘린다(무지개 금지).
    final headlineColors =
        isDark ? [Colors.white, _accent] : [_accentDeep, _accent];
    final badgeFg = isDark ? _accent : _accentDeep;
    final panelBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF1F5F9); // slate-100
    final panelBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final nameColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final factLabelColor = isDark ? Colors.white54 : const Color(0xFF64748B);
    final factValueColor = isDark ? Colors.white : const Color(0xFF0F172A);
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
                                      size: i.isEven ? 16 : 11, color: _accent),
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
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.45)
                                  : _accentDeep.withValues(alpha: 0.16),
                              blurRadius: 34,
                              offset: const Offset(0, 14),
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
                                color: _accent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: _accent.withValues(alpha: 0.32)),
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
                                            color:
                                                isDark ? _accent : _accentDeep),
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
                                      foregroundColor:
                                          isDark ? _accent : _accentDeep,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      side: BorderSide(
                                          color:
                                              (isDark ? _accent : _accentDeep)
                                                  .withValues(alpha: 0.42)),
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
                                        backgroundColor:
                                            isDark ? _accent : _accentDeep,
                                        foregroundColor:
                                            isDark ? _accentFg : Colors.white,
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

/// 공유 카드 축소판 — 실제 결과물의 톤(어두운 캔버스 + 액센트 글로우 + 큰 숫자)을
/// 그대로 줄여 보여준다. 비율 차이가 한눈에 보이는 게 목적이라 글자는 넣지 않는다.
class _MiniCardPreview extends StatelessWidget {
  const _MiniCardPreview({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor, double h, Color c, {double r = 3}) =>
        FractionallySizedBox(
          widthFactor: widthFactor,
          alignment: Alignment.centerLeft,
          child: Container(
            height: h,
            decoration:
                BoxDecoration(color: c, borderRadius: BorderRadius.circular(r)),
          ),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF111827), Color(0xFF05070C)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    accent.withValues(alpha: 0.42),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  bar(0.34, 7, accent.withValues(alpha: 0.55), r: 4),
                  const SizedBox(height: 9),
                  bar(0.52, 5, Colors.white.withValues(alpha: 0.3)),
                  const SizedBox(height: 6),
                  bar(0.86, 13, accent),
                  const SizedBox(height: 6),
                  bar(0.62, 13, accent.withValues(alpha: 0.75)),
                  const SizedBox(height: 11),
                  bar(0.7, 4, Colors.white.withValues(alpha: 0.16)),
                  const SizedBox(height: 5),
                  bar(0.45, 4, Colors.white.withValues(alpha: 0.16)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 스타일 선택용 축소판 — 실제 카드의 뼈대(밝은 배경 + 유종 포인트)를 그대로 줄인다.
/// 글자는 넣지 않는다. 여기서 읽히는 건 '어떤 구성인가' 하나면 된다.
class _StyleThumb extends StatelessWidget {
  const _StyleThumb({required this.style, required this.accent});

  final ShareCardStyle style;
  final Color accent;

  Color get _tint =>
      Color.alphaBlend(accent.withValues(alpha: 0.14), Colors.white);

  Widget _bar(double w, double h, Color c, {double r = 2}) =>
      FractionallySizedBox(
        widthFactor: w,
        alignment: Alignment.centerLeft,
        child: Container(
          height: h,
          decoration:
              BoxDecoration(color: c, borderRadius: BorderRadius.circular(r)),
        ),
      );

  Widget _box({Widget? child, Color? color}) => Container(
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final ink = const Color(0xFF0F172A).withValues(alpha: 0.75);
    final faint = const Color(0xFF94A3B8).withValues(alpha: 0.6);
    final Widget body;
    final Color bg;
    switch (style) {
      case ShareCardStyle.savings:
        bg = const Color(0xFFF7F8FA);
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _bar(0.45, 3, faint),
            const SizedBox(height: 6),
            _bar(0.8, 11, ink),
            const SizedBox(height: 3),
            _bar(0.42, 11, accent),
            const SizedBox(height: 10),
            _box(child: SizedBox(height: 16, width: double.infinity)),
            const SizedBox(height: 5),
            _box(
                color: _tint,
                child: const SizedBox(height: 18, width: double.infinity)),
          ],
        );
      case ShareCardStyle.recommend:
        bg = _tint;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _bar(0.4, 3, faint),
            const SizedBox(height: 5),
            _bar(0.78, 9, accent),
            const SizedBox(height: 3),
            _bar(0.34, 9, accent),
            const SizedBox(height: 9),
            Row(children: [
              Expanded(child: _box(child: const SizedBox(height: 15))),
              const SizedBox(width: 3),
              Expanded(child: _box(child: const SizedBox(height: 15))),
              const SizedBox(width: 3),
              Expanded(child: _box(child: const SizedBox(height: 15))),
            ]),
            const SizedBox(height: 5),
            _box(
                color: accent,
                child: const SizedBox(height: 16, width: double.infinity)),
          ],
        );
      case ShareCardStyle.receipt:
        bg = const Color(0xFFEDEFF2);
        body = _box(
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _bar(0.5, 4, ink),
                const SizedBox(height: 7),
                for (var i = 0; i < 4; i++) ...[
                  Row(children: [
                    Expanded(flex: 4, child: _bar(1, 2.5, faint)),
                    const Spacer(flex: 2),
                    Expanded(flex: 3, child: _bar(1, 2.5, faint)),
                  ]),
                  const SizedBox(height: 4),
                ],
                const SizedBox(height: 3),
                _box(
                    color: _tint,
                    child: const SizedBox(height: 16, width: double.infinity)),
              ],
            ),
          ),
        );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(8),
        child: body,
      ),
    );
  }
}
