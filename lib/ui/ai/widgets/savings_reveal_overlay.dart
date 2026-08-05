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
    this.onConfirm,
  });

  /// [확인] 탭 시 실행 — 팝업을 닫고 추천 스테이션 상세화면으로 이동한다(형 확정).
  /// null 이면 닫기만 한다.
  final VoidCallback? onConfirm;

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
        final maxH = MediaQuery.of(dctx).size.height * 0.68;
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
                  // '다시 고르기'가 좁은 폭에서 두 줄로 깨졌다(형 재현 S24)
                  // → '재선택' + 공유 버튼 2:1 폭 배분.
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
                      child: const Text('재선택',
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
                            // ── 시안 5a/5g: ✨ AI 추천 pill (가운데) ──
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 5),
                              decoration: BoxDecoration(
                                color: _accent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome_rounded,
                                      size: 12, color: badgeFg),
                                  const SizedBox(width: 4),
                                  Text('AI 추천',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: badgeFg)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              widget.caption,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: captionColor,
                              ),
                            ),
                            const SizedBox(height: 3),
                            // 헤드라인 — 숫자=유종 액센트, '원 절약'=잉크 (시안 5a)
                            Builder(builder: (_) {
                              final m = RegExp(r'^([\d,]+)\s*원?\s*(.*)$')
                                  .firstMatch(widget.headline.trim());
                              final numText = m?.group(1);
                              final tail = m == null
                                  ? null
                                  : '원 ${m.group(2)!.isEmpty ? '절약' : m.group(2)}';
                              if (numText == null) {
                                return Text(widget.headline,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w900,
                                        height: 1.15,
                                        color:
                                            isDark ? _accent : _accentDeep));
                              }
                              return FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(numText,
                                        style: TextStyle(
                                          fontSize: 42,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -1.5,
                                          height: 1.05,
                                          color:
                                              isDark ? _accent : _accentDeep,
                                        )),
                                    const SizedBox(width: 5),
                                    Text(tail!,
                                        style: TextStyle(
                                          fontSize: 21,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5,
                                          color: nameColor,
                                        )),
                                  ],
                                ),
                              );
                            }),
                            // ── 스테이션 칩 (틴트 배경) ──
                            if (widget.stationName != null &&
                                widget.stationName!.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.fromLTRB(12, 11, 12, 11),
                                decoration: BoxDecoration(
                                  color: _accent.withValues(
                                      alpha: isDark ? 0.12 : 0.09),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color:
                                            isDark ? _accent : _accentDeep,
                                        borderRadius:
                                            BorderRadius.circular(11),
                                      ),
                                      child: Icon(widget.stationIcon,
                                          size: 19,
                                          color: isDark
                                              ? _accentFg
                                              : Colors.white),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(widget.stationName!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: nameColor)),
                                          if ((widget.stationSub ?? '')
                                              .trim()
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(widget.stationSub!,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: factLabelColor)),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            // ── 수치 타일 3칸 (시안 5a: 리터당·추가 시간·예상 주유비) ──
                            Builder(builder: (_) {
                              final fmt = NumberFormat('#,###');
                              final tiles = <(String, String)>[];
                              if (widget.myUnitWon != null) {
                                tiles.add((fmt.format(widget.myUnitWon),
                                    widget.isEv ? 'kWh당' : '리터당'));
                              }
                              for (final f in widget.facts) {
                                if (tiles.length >= 3) break;
                                if (f.label == '추가 시간') {
                                  tiles.add((f.value, '추가 시간'));
                                } else if (f.label == '예상 주유비') {
                                  tiles.add((f.value.replaceAll('원', ''),
                                      '예상 주유비'));
                                } else if (f.label == '예상 충전요금') {
                                  tiles.add((f.value.replaceAll('원', ''),
                                      '예상 충전비'));
                                } else if (f.label == '충전량') {
                                  tiles.add((f.value, '충전량'));
                                }
                              }
                              if (tiles.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Row(
                                  children: [
                                    for (var i = 0; i < tiles.length; i++) ...[
                                      if (i > 0) const SizedBox(width: 8),
                                      Expanded(
                                        child: Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 11),
                                          decoration: BoxDecoration(
                                            color: panelBg,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: panelBorder),
                                          ),
                                          child: Column(
                                            children: [
                                              FittedBox(
                                                child: Text(tiles[i].$1,
                                                    style: TextStyle(
                                                        fontSize: 15.5,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        letterSpacing: -0.4,
                                                        color:
                                                            factValueColor)),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(tiles[i].$2,
                                                  style: TextStyle(
                                                      fontSize: 10.5,
                                                      color:
                                                          factLabelColor)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }),
                            // ── 주변 평균가 · 주유량/충전량 행 (시안 5a) ──
                            Builder(builder: (_) {
                              final fmt = NumberFormat('#,###');
                              final rows = <Widget>[];
                              if (widget.avgUnitWon != null) {
                                final diff = widget.myUnitWon != null
                                    ? widget.avgUnitWon! - widget.myUnitWon!
                                    : null;
                                rows.add(Row(children: [
                                  Text('주변 평균가',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: factLabelColor)),
                                  const Spacer(),
                                  Text(
                                      '${fmt.format(widget.avgUnitWon)}원/${widget.isEv ? 'kWh' : 'L'}',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: factValueColor)),
                                  if (diff != null && diff != 0) ...[
                                    const SizedBox(width: 5),
                                    Text(
                                        diff > 0
                                            ? '▼${fmt.format(diff)}'
                                            : '▲${fmt.format(-diff)}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: diff > 0
                                                ? (isDark
                                                    ? _accent
                                                    : _accentDeep)
                                                : const Color(0xFFEF4444))),
                                  ],
                                ]));
                              }
                              for (final f in widget.facts) {
                                if (f.label == '주유량' || f.label == '충전량') {
                                  rows.add(Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Row(children: [
                                      Text(f.label,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: factLabelColor)),
                                      const Spacer(),
                                      Text(f.value,
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: factValueColor)),
                                    ]),
                                  ));
                                  break;
                                }
                              }
                              if (rows.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(2, 12, 2, 0),
                                child: Column(children: rows),
                              );
                            }),
                            const SizedBox(height: 14),
                            // ── 공유(사각) + 확인 → 상세화면 (형 확정: 경유 길안내 아님) ──
                            Row(
                              children: [
                                SizedBox(
                                  width: 46,
                                  height: 46,
                                  child: OutlinedButton(
                                    onPressed: _share,
                                    style: OutlinedButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      foregroundColor:
                                          isDark ? _accent : _accentDeep,
                                      side: BorderSide(
                                          color:
                                              (isDark ? _accent : _accentDeep)
                                                  .withValues(alpha: 0.42)),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(13)),
                                    ),
                                    child: const Icon(Icons.ios_share_rounded,
                                        size: 18),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SizedBox(
                                    height: 46,
                                    child: FilledButton(
                                      onPressed: () {
                                        _dismiss();
                                        widget.onConfirm?.call();
                                      },
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
                                              fontSize: 15,
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
