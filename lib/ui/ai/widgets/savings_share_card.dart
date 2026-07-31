import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import 'savings_reveal_overlay.dart';

/// 절감 결과를 인스타그램 피드 규격(1:1)으로 그린 공유용 카드.
///
/// 화면에 보이는 오버레이와 레이아웃을 분리한 이유:
///  · 피드는 정사각형이라 세로 카드를 그대로 캡처하면 여백이 남거나 잘린다
///  · 공유 이미지는 폰트·여백을 고정해야 기기마다 결과가 같다
/// 주유는 파랑, 충전은 초록 — 앱 전체 색 규칙 그대로.
class SavingsShareCard extends StatelessWidget {
  const SavingsShareCard({
    super.key,
    required this.caption,
    required this.headline,
    required this.isEv,
    this.stationName,
    this.facts = const [],
  });

  final String caption;
  final String headline;
  final bool isEv;
  final String? stationName;
  final List<RevealFact> facts;

  /// 인스타 피드 권장 해상도. 실제 캡처는 pixelRatio 로 배율을 준다.
  static const double side = 360;

  Color get _accent => isEv ? AppColors.evGreen : AppColors.gasBlue;

  List<Color> get _bg => isEv
      ? [const Color(0xFF063E30), const Color(0xFF0B7A5B), const Color(0xFF0E9E74)]
      : [const Color(0xFF10243F), const Color(0xFF14487F), const Color(0xFF1D6FE0)];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: side,
      height: side,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _bg,
          ),
        ),
        child: Stack(
          children: [
            // 은은한 광원 — 단색 배경이 밋밋해 보이지 않게
            Positioned(
              top: -70,
              right: -50,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            Positioned(
              bottom: -90,
              left: -60,
              child: Container(
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withValues(alpha: 0.16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _badge(),
                  const Spacer(),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      headline,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.4,
                        height: 1.05,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if ((stationName ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _stationChip(),
                  ],
                  const Spacer(),
                  if (facts.isNotEmpty) _factRow(),
                  const SizedBox(height: 16),
                  _footer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 13, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              isEv ? 'AI 충전 추천' : 'AI 주유 추천',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );

  Widget _stationChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isEv ? Icons.ev_station_rounded : Icons.local_gas_station_rounded,
              size: 14,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 230),
              child: Text(
                stationName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _factRow() {
    final shown = facts.take(3).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: Colors.white.withValues(alpha: 0.16),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shown[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.66),
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      shown[i].value,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _footer() => Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(Icons.bolt_rounded, size: 14, color: _accent),
          ),
          const SizedBox(width: 8),
          const Text(
            '전기차 기름차',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Text(
            '기름값·충전요금 아끼기',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
        ],
      );
}

/// 화면 밖에서 [SavingsShareCard] 를 그려 PNG 로 만들고 공유 시트를 연다.
///
/// 오버레이를 그대로 캡처하지 않고 전용 카드를 따로 렌더한다 — 애니메이션 중간 프레임이
/// 찍히거나 기기 폰트 배율에 따라 결과가 달라지는 걸 막기 위해서.
class SavingsShare {
  SavingsShare._();

  static Future<void> shareCard(
    BuildContext context, {
    required String caption,
    required String headline,
    required bool isEv,
    String? stationName,
    List<RevealFact> facts = const [],
  }) async {
    try {
      final bytes = await _render(
        SavingsShareCard(
          caption: caption,
          headline: headline,
          isEv: isEv,
          stationName: stationName,
          facts: facts,
        ),
        context,
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
  static Future<Uint8List?> _render(Widget child, BuildContext context) async {
    final repaint = RenderRepaintBoundary();
    final view = View.of(context);
    // 1080px 목표 — 인스타 피드 권장 해상도
    const target = 1080.0; // 인스타 피드 권장 해상도
    final pixelRatio = target / SavingsShareCard.side;

    final renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        physicalConstraints: BoxConstraints.tight(
            const Size(SavingsShareCard.side, SavingsShareCard.side) *
                pixelRatio),
        logicalConstraints: BoxConstraints.tight(
            const Size(SavingsShareCard.side, SavingsShareCard.side)),
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
