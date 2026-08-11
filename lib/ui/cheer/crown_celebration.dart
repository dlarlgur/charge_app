import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/services/cheer_service.dart';
import 'cheer_tier_theme.dart';

/// 월간 응원 왕관 — 앱 진입 시 지난달 1·2·3등에게 한 번만 보여주는 축하 연출.
/// 왕관이 하늘에서 떨어져 프로필에 툭 얹히고(elasticOut + 반짝), 위트 멘트와
/// 인스타 공유 버튼이 뜬다. 확인하면 서버에 seen 처리되어 다시 안 뜬다.

class CrownTheme {
  final String name; // 금관/은관/동관
  final Color main;
  final Color deep;
  final Color glow;
  const CrownTheme(this.name, this.main, this.deep, this.glow);

  static const gold =
      CrownTheme('금관', Color(0xFFFACC15), Color(0xFFB45309), Color(0xFFFDE68A));
  static const silver =
      CrownTheme('은관', Color(0xFFE2E8F0), Color(0xFF64748B), Color(0xFFF1F5F9));
  static const bronze =
      CrownTheme('동관', Color(0xFFD97706), Color(0xFF92400E), Color(0xFFFBBF24));

  static CrownTheme of(int rank) =>
      rank == 1 ? gold : (rank == 2 ? silver : bronze);
}

/// 등수별 축하 멘트 — 담백하게 위트, AI스러운 호들갑 금지.
({String headline, String sub}) crownCopy(CheerCrown c) {
  final m = int.tryParse(c.month.split('-').last) ?? 0;
  switch (c.rank) {
    case 1:
      return (
        headline: '$m월의 응원왕, 등극!',
        sub: '지난달 가장 뜨겁게 응원해주셨어요.\n금관을 씌워드립니다',
      );
    case 2:
      return (
        headline: '아깝다, 딱 한 끗!',
        sub: '$m월 응원 2위 — 은관을 씌워드립니다.\n다음 달 왕좌를 노려보세요',
      );
    default:
      return (
        headline: '시상대 입성!',
        sub: '$m월 응원 3위 — 동관을 씌워드립니다.\n박수 받으실 자격, 충분합니다',
      );
  }
}

Future<void> showCrownCelebration(
  BuildContext context, {
  required CheerCrown crown,
  String? profileImageUrl,
}) {
  // 뜨는 즉시 seen 처리 — 연출 중 앱을 꺼도 다음에 또 안 뜬다.
  CheerService.instance.markCrownSeen();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'crown-celebration',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) =>
        _CrownOverlay(crown: crown, profileImageUrl: profileImageUrl),
    transitionBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _CrownOverlay extends StatefulWidget {
  final CheerCrown crown;
  final String? profileImageUrl;
  const _CrownOverlay({required this.crown, this.profileImageUrl});

  @override
  State<_CrownOverlay> createState() => _CrownOverlayState();
}

class _CrownOverlayState extends State<_CrownOverlay>
    with TickerProviderStateMixin {
  // 왕관 낙하(elasticOut) → 반짝 버스트 → 텍스트/버튼 페이드인
  late final AnimationController _drop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _sparkle = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _rest = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      await _drop.forward();
      if (!mounted) return;
      _sparkle.forward();
      _rest.forward();
    });
  }

  @override
  void dispose() {
    _drop.dispose();
    _sparkle.dispose();
    _rest.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = CrownTheme.of(widget.crown.rank);
    final copy = crownCopy(widget.crown);
    final tier = CheerTierTheme.of(CheerService.instance.cachedTotal);

    return Material(
      // 승급 오버레이와 같은 규칙 — 테마를 따른다 (다크 고정은 공유 이미지쪽만)
      color: isDark ? const Color(0xF20C0E13) : const Color(0xF5F8FAFB),
      child: SafeArea(
        child: Stack(children: [
          // 왕관색 라디얼 글로우
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.35),
                    radius: 0.9,
                    colors: [t.main.withValues(alpha: isDark ? 0.16 : 0.22), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          Column(children: [
            const Spacer(flex: 3),
            // ─── 아바타 + 떨어지는 왕관 ───
            SizedBox(
              width: 200,
              height: 210,
              child: Stack(alignment: Alignment.bottomCenter, children: [
                // 아바타 (프로필 사진 or 사람 아이콘) — 등급 링
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: 128,
                    height: 128,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: tier?.ring(true) ?? [t.main, t.deep],
                      ),
                      boxShadow: [
                        BoxShadow(
                            color: t.main.withValues(alpha: 0.35),
                            blurRadius: 40,
                            spreadRadius: 4),
                      ],
                    ),
                    child: ClipOval(
                      child: Container(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFE2E8F0),
                        child: widget.profileImageUrl != null
                            ? Image.network(widget.profileImageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                    Icons.person_rounded,
                                    size: 64,
                                    color: isDark
                                        ? Colors.white70
                                        : const Color(0xFF94A3B8)))
                            : Icon(Icons.person_rounded,
                                size: 64,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF94A3B8)),
                      ),
                    ),
                  ),
                ),
                // 왕관 — 위에서 낙하해 아바타 위에 살짝 기울어 얹힘
                AnimatedBuilder(
                  animation: _drop,
                  builder: (_, __) {
                    final v = Curves.elasticOut.transform(_drop.value);
                    final y = -150 + v * 150; // -150 → 0
                    final angle = (1 - v) * 0.6 - 0.10; // 도착 시 -0.10rad 삐딱
                    return Positioned(
                      bottom: 108,
                      child: Transform.translate(
                        offset: Offset(6, y),
                        child: Transform.rotate(
                          angle: angle,
                          child: CustomPaint(
                            size: const Size(84, 60),
                            painter: _CrownPainter(t),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // 반짝 버스트
                AnimatedBuilder(
                  animation: _sparkle,
                  builder: (_, __) => _sparkle.value == 0
                      ? const SizedBox.shrink()
                      : Positioned(
                          bottom: 70,
                          child: CustomPaint(
                            size: const Size(220, 160),
                            painter: _SparklePainter(_sparkle.value,
                                isDark ? t.glow : t.deep),
                          ),
                        ),
                ),
              ]),
            ),
            const SizedBox(height: 28),
            // ─── 멘트 ───
            FadeTransition(
              opacity: _rest,
              child: Column(children: [
                Text(copy.headline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: isDark ? t.main : t.deep)),
                const SizedBox(height: 10),
                Text(copy.sub,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF475569))),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: t.main.withValues(alpha: isDark ? 0.35 : 0.6)),
                  ),
                  child: Text(
                      '${widget.crown.month.replaceFirst('-', '년 ')}월 · 응원 ${widget.crown.count}회',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? t.glow : t.deep)),
                ),
              ]),
            ),
            const Spacer(flex: 2),
            // ─── 버튼 ───
            FadeTransition(
              opacity: _rest,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                child: Column(children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: t.main,
                        foregroundColor: const Color(0xFF1C1917),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => CrownShare.shareCard(context,
                          crown: widget.crown),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.ios_share_rounded, size: 19),
                            SizedBox(width: 8),
                            Text('공유하기',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800)),
                          ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('닫기',
                        style: TextStyle(
                            fontSize: 14.5,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B))),
                  ),
                ]),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// 왕관 — 밴드 + 3봉우리 + 보석. 등수별 색만 바뀐다.
class _CrownPainter extends CustomPainter {
  final CrownTheme t;
  const _CrownPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = Path()
      ..moveTo(w * 0.08, h * 0.92)
      ..lineTo(w * 0.04, h * 0.30)
      ..lineTo(w * 0.28, h * 0.55)
      ..lineTo(w * 0.50, h * 0.10)
      ..lineTo(w * 0.72, h * 0.55)
      ..lineTo(w * 0.96, h * 0.30)
      ..lineTo(w * 0.92, h * 0.92)
      ..close();
    canvas.drawPath(
        body,
        Paint()
          ..shader = ui.Gradient.linear(const Offset(0, 0), Offset(0, h),
              [t.main, t.deep]));
    // 밴드
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.06, h * 0.80, w * 0.88, h * 0.16),
            const Radius.circular(3)),
        Paint()..color = t.deep);
    // 봉우리 구슬
    final ball = Paint()..color = t.glow;
    canvas.drawCircle(Offset(w * 0.04, h * 0.26), 3.2, ball);
    canvas.drawCircle(Offset(w * 0.50, h * 0.07), 3.6, ball);
    canvas.drawCircle(Offset(w * 0.96, h * 0.26), 3.2, ball);
    // 보석
    canvas.drawCircle(Offset(w * 0.5, h * 0.68),
        4.4, Paint()..color = const Color(0xFFDC2626));
    canvas.drawCircle(Offset(w * 0.30, h * 0.72), 2.6, ball);
    canvas.drawCircle(Offset(w * 0.70, h * 0.72), 2.6, ball);
  }

  @override
  bool shouldRepaint(_CrownPainter old) => old.t != t;
}

/// 왕관 착지 순간의 반짝 버스트 — 방사형 스파크 + 작은 별.
class _SparklePainter extends CustomPainter {
  final double v; // 0~1
  final Color color;
  const _SparklePainter(this.v, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.45);
    final fade = (1 - v).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9 * fade)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 10; i++) {
      final a = i * math.pi / 5 + 0.3;
      final r0 = 34 + v * 52;
      final r1 = r0 + 10 * (1 - v);
      canvas.drawLine(c + Offset(math.cos(a) * r0, math.sin(a) * r0 * 0.8),
          c + Offset(math.cos(a) * r1, math.sin(a) * r1 * 0.8), paint);
    }
    final star = Paint()..color = color.withValues(alpha: fade);
    for (final (dx, dy, r) in [(-70.0, -20.0, 2.6), (76.0, -6.0, 2.2), (-48.0, 38.0, 1.8), (58.0, 44.0, 2.4)]) {
      canvas.drawCircle(c + Offset(dx * (0.6 + v * 0.4), dy), r, star);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.v != v;
}

// ───────────────────────── 인스타 공유 카드 ─────────────────────────

/// 1080×1350 피드 카드 — AI 절약 카드(savings_share_card)와 같은
/// 오프스크린 렌더 방식. 왕관 + 멘트 + 앱 이름.
class CrownShareCard extends StatelessWidget {
  static const double side = 360; // 논리 픽셀 (1080/3)
  static const double height = 450; // 4:5 피드

  final CheerCrown crown;
  const CrownShareCard({super.key, required this.crown});

  @override
  Widget build(BuildContext context) {
    final t = CrownTheme.of(crown.rank);
    final m = int.tryParse(crown.month.split('-').last) ?? 0;
    final title = crown.rank == 1
        ? '$m월의 응원왕'
        : '$m월의 응원 ${crown.rank}위';
    return Container(
      width: side,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF171B24), Color(0xFF0C0E13)],
        ),
      ),
      child: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.3),
                radius: 0.85,
                colors: [t.main.withValues(alpha: 0.18), Colors.transparent],
              ),
            ),
          ),
        ),
        Column(children: [
          const SizedBox(height: 40),
          Center(
              child: CustomPaint(
                  size: const Size(134, 96), painter: _CrownPainter(t))),
          const SizedBox(height: 26),
          Text(title,
              style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: t.main)),
          const SizedBox(height: 8),
          Text('한 달 동안 ${crown.count}번 응원했습니다',
              style: const TextStyle(
                  fontSize: 15, color: Color(0xFFCBD5E1))),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: t.main.withValues(alpha: 0.45)),
            ),
            child: Text('${t.name} 서포터',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.glow)),
          ),
          const Spacer(),
          // 하단 앱 시그니처
          Padding(
            padding: const EdgeInsets.only(bottom: 26),
            child: Column(children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF10B981)]),
                ),
                child: const Icon(Icons.bolt_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(height: 10),
              const Text('전기차 기름차',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 3),
              const Text('충전소·주유소 실시간 최저가',
                  style:
                      TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ]),
          ),
        ]),
      ]),
    );
  }
}

class CrownShare {
  CrownShare._();

  static Future<void> shareCard(BuildContext context,
      {required CheerCrown crown}) async {
    try {
      final bytes = await _render(CrownShareCard(crown: crown), context);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/crown_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      final m = int.tryParse(crown.month.split('-').last) ?? 0;
      await Share.shareXFiles([XFile(file.path)],
          text: '$m월의 응원 ${crown.rank}위 · 전기차 기름차');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('이미지를 만들지 못했어요. 잠시 후 다시 시도해 주세요.')));
    }
  }

  /// savings_share_card 의 오프스크린 렌더와 동일 — 위젯을 붙이지 않고 PNG 로.
  static Future<Uint8List?> _render(Widget child, BuildContext context) async {
    final repaint = RenderRepaintBoundary();
    final view = View.of(context);
    const pixelRatio = 1080 / CrownShareCard.side;

    final renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        physicalConstraints: BoxConstraints.tight(
            const Size(CrownShareCard.side, CrownShareCard.height) *
                pixelRatio),
        logicalConstraints: BoxConstraints.tight(
            const Size(CrownShareCard.side, CrownShareCard.height)),
        devicePixelRatio: pixelRatio,
      ),
      child: RenderPositionedBox(
          alignment: Alignment.center, child: repaint),
    );

    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    final buildOwner = BuildOwner(focusManager: FocusManager());
    renderView.prepareInitialFrame();

    final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: repaint,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.noScaling),
          child: child,
        ),
      ),
    ).attachToRenderTree(buildOwner);

    buildOwner
      ..buildScope(rootElement)
      ..finalizeTree();
    pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();

    final image = await repaint.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }
}
