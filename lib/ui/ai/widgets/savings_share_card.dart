import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import 'savings_reveal_overlay.dart';

/// 공유 카드 스타일 — 같은 데이터를 세 가지 화법으로 보여준다.
enum ShareCardStyle {
  /// 절약액 하나를 크게 — "얼마 아꼈다"를 자랑하는 용도
  savings,

  /// 추천 결과 카드 — 어디를 왜 추천받았는지
  recommend,

  /// 영수증 — 숫자를 조목조목, 가장 신뢰감 있는 화법
  receipt,
}

/// 절감 결과를 인스타 규격(피드 4:5 / 스토리 9:16)으로 그린 공유용 카드.
///
/// 화면 오버레이와 레이아웃을 분리한 이유:
///  · 피드/스토리는 비율이 달라 화면 카드를 그대로 캡처하면 여백이 남거나 잘린다
///  · 공유 이미지는 폰트·여백을 고정해야 기기마다 결과가 같다
/// 주유는 파랑, 충전은 초록 — 앱 전체 색 규칙 그대로.
class SavingsShareCard extends StatelessWidget {
  const SavingsShareCard({
    super.key,
    required this.caption,
    required this.headline,
    required this.isEv,
    this.stationName,
    this.stationSub,
    this.facts = const [],
    this.story = false,
    this.style = ShareCardStyle.savings,
  });

  final String caption;
  final String headline;
  final bool isEv;
  final String? stationName;

  /// 스테이션 아래 한 줄 (예: '휘발유 · SK에너지 · 24시간')
  final String? stationSub;
  final List<RevealFact> facts;
  final bool story; // true=9:16 스토리 / false=4:5 피드
  final ShareCardStyle style;

  /// 공유 규격 — 피드 4:5(1080×1350), 스토리·릴스 9:16(1080×1920).
  static const double side = 360; // width
  static const double feedHeight = 450; // 4:5
  static const double storyHeight = 640; // 9:16

  static double heightFor(bool story) => story ? storyHeight : feedHeight;

  static const _logoAsset = 'assets/halfNhalf.png';

  // ── 팔레트 ──
  Color get _accentDeep => isEv ? AppColors.evGreenDark : AppColors.gasBlueDark;

  /// 흰 배경 위 큰 글자용 — 액센트보다 한 단 진하게 가야 눈이 안 아프다.
  Color get _accentInk =>
      isEv ? const Color(0xFF047857) : const Color(0xFF1D4ED8);
  Color get _tint => isEv ? const Color(0xFFE8F7F0) : const Color(0xFFEDF3FF);

  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _line = Color(0xFFE2E8F0);

  @override
  Widget build(BuildContext context) {
    final body = switch (style) {
      ShareCardStyle.savings => _savingsBody(),
      ShareCardStyle.recommend => _recommendBody(),
      ShareCardStyle.receipt => _receiptBody(),
    };
    final bg = switch (style) {
      ShareCardStyle.savings => const Color(0xFFF7F8FA),
      ShareCardStyle.recommend => _tint,
      ShareCardStyle.receipt => const Color(0xFFEDEFF2),
    };
    return DefaultTextStyle(
      style: const TextStyle(
        fontFamily: 'Pretendard',
        color: _ink,
        height: 1.25,
        letterSpacing: -0.3,
      ),
      child: Container(
        width: side,
        height: heightFor(story),
        color: bg,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (style != ShareCardStyle.receipt) ...[
              _header(),
              SizedBox(height: story ? 26 : 16),
            ],
            Expanded(child: body),
            SizedBox(height: story ? 18 : 12),
            _footer(),
          ],
        ),
      ),
    );
  }

  // ── 공통 조각 ─────────────────────────────────────────────────────────────

  Widget _header() => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
            decoration: BoxDecoration(
              color: _tint,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome_rounded, size: 11, color: _accentDeep),
              const SizedBox(width: 4),
              Text(
                isEv ? 'AI 충전 추천' : 'AI 주유 추천',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _accentDeep),
              ),
            ]),
          ),
          const Spacer(),
          Text(_today(),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: _muted)),
        ],
      );

  Widget _footer() => Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.asset(_logoAsset, width: 22, height: 22),
          ),
          const SizedBox(width: 7),
          const Text('전기차 기름차',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800, color: _ink)),
          const Spacer(),
          Text(
            style == ShareCardStyle.receipt ? '출처: 오피넷' : '기름값·충전요금 아끼기',
            style: const TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w600, color: _muted),
          ),
        ],
      );

  /// '1,824원/L' → 숫자는 크게, 단위는 작게. 숫자만 있으면 단위는 빈 문자열.
  static (String, String) _splitUnit(String v) {
    final m = RegExp(r'^([▼▲+\-]?[\d,.]+)(.*)$').firstMatch(v.trim());
    if (m == null) return (v, '');
    return (m.group(1)!, m.group(2)!.trim());
  }

  static String _today() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}.${two(n.month)}.${two(n.day)}';
  }

  /// 숫자 + 작은 단위. 폭이 모자라면 통째로 줄여 밀림·겹침을 막는다.
  Widget _valueText(String raw,
      {double size = 17, Color? color, double unitSize = 11}) {
    final (num_, unit) = _splitUnit(raw);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(num_,
              style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w800,
                color: color ?? _ink,
                letterSpacing: -0.6,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          if (unit.isNotEmpty) ...[
            const SizedBox(width: 1.5),
            Text(unit,
                style: TextStyle(
                    fontSize: unitSize,
                    fontWeight: FontWeight.w700,
                    color: (color ?? _ink).withValues(alpha: 0.55))),
          ],
        ],
      ),
    );
  }

  Widget _stationIcon({double size = 30, Color? bg, Color? fg}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg ?? _tint,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          isEv ? Icons.ev_station_rounded : Icons.local_gas_station_rounded,
          size: size * 0.52,
          color: fg ?? _accentDeep,
        ),
      );

  // ── 스타일 1 : 절약액 ──────────────────────────────────────────────────────

  Widget _savingsBody() {
    // '1,068원 절약!' → 숫자 줄과 '절약!' 줄을 나눠 액센트를 뒷줄에만 준다.
    final m = RegExp(r'^(.*?)\s*(절약|아낌)(!?)$').firstMatch(headline.trim());
    final amount = m?.group(1) ?? headline;
    final tail = m == null ? null : '${m.group(2)}${m.group(3)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (caption.trim().isNotEmpty) ...[
          Text(caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: _muted)),
          const SizedBox(height: 6),
        ],
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(amount,
              style: const TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                color: _ink,
                height: 1.05,
                letterSpacing: -2,
                fontFeatures: [FontFeature.tabularFigures()],
              )),
        ),
        if (tail != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(tail,
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  color: _accentInk,
                  height: 1.05,
                  letterSpacing: -2,
                )),
          ),
        SizedBox(height: story ? 30 : 20),
        if ((stationName ?? '').trim().isNotEmpty) _stationCard(),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 10),
          _factStrip(),
        ],
      ],
    );
  }

  Widget _stationCard() => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line),
        ),
        child: Row(
          children: [
            _stationIcon(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(stationName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: _ink)),
                  if ((stationSub ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(stationSub!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: _muted)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _tint,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('★ 최저가',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _accentDeep)),
            ),
          ],
        ),
      );

  /// 하단 수치 3칸. 4개 이상이면 앞 3개만 — 넘치면 글자가 서로 침범한다.
  Widget _factStrip() {
    final f = facts.take(3).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: BoxDecoration(
        color: _tint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < f.length; i++) ...[
            if (i > 0)
              Container(
                  width: 1,
                  height: 26,
                  color: Colors.white.withValues(alpha: 0.8)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(f[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _muted)),
                    const SizedBox(height: 3),
                    _valueText(f[i].value, size: 15.5),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 스타일 2 : 추천 카드 ───────────────────────────────────────────────────

  Widget _recommendBody() {
    final f = facts.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (caption.trim().isNotEmpty)
          Text(caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: _muted)),
        const SizedBox(height: 6),
        Text(
          isEv ? '최적 충전소\n추천!' : '최저가 주유소\n추천!',
          style: TextStyle(
            fontSize: 31,
            fontWeight: FontWeight.w800,
            color: _accentInk,
            height: 1.18,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _recommendSub(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: _muted),
        ),
        SizedBox(height: story ? 28 : 18),
        if (f.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < f.length; i++) ...[
                if (i > 0) const SizedBox(width: 7),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(9, 9, 8, 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(f[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: _muted)),
                        const SizedBox(height: 4),
                        _valueText(f[i].value,
                            size: 16,
                            color: i == 1 ? _accentInk : _ink,
                            unitSize: 10),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        if ((stationName ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 9),
          _stationBar(),
        ],
        const SizedBox(height: 9),
        Row(children: [
          Text('★',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _accentDeep)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              isEv ? '주변 충전소 중 단가 최저' : '주변 주유소 중 리터당 최저가',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: _accentDeep),
            ),
          ),
        ]),
      ],
    );
  }

  String _recommendSub() {
    if (caption.trim().isNotEmpty && headline.trim().isNotEmpty) {
      return headline;
    }
    return headline.trim().isEmpty ? caption : headline;
  }

  Widget _stationBar() => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: _accentDeep,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            _stationIcon(
              size: 28,
              bg: Colors.white.withValues(alpha: 0.2),
              fg: Colors.white,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(stationName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  if ((stationSub ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(stationSub!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.78))),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  // ── 스타일 3 : 영수증 ──────────────────────────────────────────────────────

  Widget _receiptBody() {
    // 마지막 항목은 보통 '예상 비용' 성격이라 합계 줄로 따로 뺀다.
    final rows = facts.toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(isEv ? '충전 절약 영수증' : '주유 절약 영수증',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
            const Spacer(),
            Text(_today(),
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, color: _muted)),
          ]),
          SizedBox(height: story ? 20 : 14),
          if ((stationName ?? '').trim().isNotEmpty)
            _receiptRow(isEv ? '충전소' : '주유소', stationName!),
          for (final f in rows) _receiptRow(f.label, f.value),
          SizedBox(height: story ? 14 : 8),
          const _Dashed(),
          SizedBox(height: story ? 14 : 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: _tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('절약 합계',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _accentDeep)),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _savingsAmount(),
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: _accentInk,
                          letterSpacing: -1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 헤드라인에서 '절약!' 같은 꼬리말을 떼고 금액만 — 영수증에는 감탄사가 안 어울린다.
  String _savingsAmount() {
    final m = RegExp(r'^(.*?)\s*(절약|아낌)!?$').firstMatch(headline.trim());
    final amount = (m?.group(1) ?? headline).trim();
    return amount.startsWith('-') ? amount : '-$amount';
  }

  Widget _receiptRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _muted)),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: value.startsWith('▼') ? _accentDeep : _ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

/// 영수증 절취선.
class _Dashed extends StatelessWidget {
  const _Dashed();

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 1, child: CustomPaint(painter: _DashPainter()));
}

class SavingsShare {
  SavingsShare._();

  static Future<void> shareCard(
    BuildContext context, {
    required String caption,
    required String headline,
    required bool isEv,
    String? stationName,
    String? stationSub,
    List<RevealFact> facts = const [],
    bool story = false,
    ShareCardStyle style = ShareCardStyle.savings,
  }) async {
    try {
      // 오프스크린 렌더는 이미지 로딩을 기다려주지 않는다 — 로고를 미리 캐시에 올려야
      // 캡처 결과에 로고가 빈칸으로 남지 않는다.
      await precacheImage(
          const AssetImage(SavingsShareCard._logoAsset), context);
      if (!context.mounted) return;
      final bytes = await _render(
        SavingsShareCard(
          caption: caption,
          headline: headline,
          isEv: isEv,
          stationName: stationName,
          stationSub: stationSub,
          facts: facts,
          story: story,
          style: style,
        ),
        context,
        story: story,
      );
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/savings_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '$headline · 전기차 기름차 AI 추천',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미지를 만들지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  /// 위젯을 오프스크린으로 레이아웃·페인트해 PNG 바이트로.
  static Future<Uint8List?> _render(Widget child, BuildContext context,
      {bool story = false}) async {
    final repaint = RenderRepaintBoundary();
    final view = View.of(context);
    // 가로 1080px 기준 — 피드 1080×1350, 스토리 1080×1920
    const double target = 1080;
    const pixelRatio = target / SavingsShareCard.side;

    final renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        physicalConstraints: BoxConstraints.tight(
            Size(SavingsShareCard.side, SavingsShareCard.heightFor(story)) *
                pixelRatio),
        logicalConstraints: BoxConstraints.tight(
            Size(SavingsShareCard.side, SavingsShareCard.heightFor(story))),
        devicePixelRatio: pixelRatio,
      ),
      child: RenderPositionedBox(
        alignment: Alignment.center,
        child: repaint,
      ),
    );

    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    final buildOwner = BuildOwner(focusManager: FocusManager());
    renderView.prepareInitialFrame();

    final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: repaint,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          // 기기 폰트 배율 무시 — 공유 이미지는 어디서 만들어도 같아야 한다
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

/// 영수증 절취선 — Flutter 기본 Divider 로는 점선이 안 나와 직접 그린다.
class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const dash = 4.0;
    const gap = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
          Offset(x, 0.5), Offset((x + dash).clamp(0, size.width), 0.5), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
