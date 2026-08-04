import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
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
    this.verdict,
    this.originName,
    this.destName,
    this.myUnitWon,
    this.avgUnitWon,
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

  /// AI 판단 한 줄 (시안 7a 하단: '✨ AI 판단 · 우회 없이 가는 길이 최적').
  final String? verdict;

  /// 경로 스트립 양끝 라벨 — 없으면 '출발'/'도착' (시안 7b: 충무로/대전역).
  final String? originName;
  final String? destName;

  /// 단가 비교 바(추천 vs 주변 평균, 시안 7a) — 둘 다 있을 때만 그린다.
  final int? myUnitWon;
  final int? avgUnitWon;

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

  /// 스토리(9:16)는 세로가 1.4배다. 같은 크기로 그리면 가운데만 차고 위아래가 휑하니
  /// 글자·여백을 함께 키워 화면을 채운다.
  double sc(double v) => story ? v * 1.18 : v;

  /// 절약 카드 전용 다크 팔레트 — 다른 공유 카드가 전부 흰색이라 이 한 장만 대비를 준다.
  bool get _dark => style == ShareCardStyle.savings;
  /// 딥네이비 위에서 읽히는 밝은 액센트 (흰 배경용 _accentInk 는 너무 어둡다)
  Color get _accentGlow => isEv ? const Color(0xFF34D399) : const Color(0xFF60A5FA);
  static const _dInk = Color(0xFFF8FAFC);   // 다크 위 본문
  static const _dMuted = Color(0xFF94A3B8); // 다크 위 보조
  static const _dCard = Color(0x14FFFFFF);  // 다크 위 카드면 (흰색 8%)
  static const _dLine = Color(0x1FFFFFFF);  // 다크 위 경계선

  Color get _fg => _dark ? _dInk : _ink;
  Color get _fgMuted => _dark ? _dMuted : _muted;
  Color get _accentFg => _dark ? _accentGlow : _accentInk;

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
      ShareCardStyle.savings => const Color(0xFF0A101C),
      ShareCardStyle.recommend => _tint,
      ShareCardStyle.receipt => const Color(0xFFEDEFF2),
    };
    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: 'Pretendard',
        color: _fg,
        height: 1.25,
        letterSpacing: -0.3,
      ),
      child: Container(
        width: side,
        height: heightFor(story),
        decoration: _dark
            ? BoxDecoration(
                // 우상단이 밝은 대각 그라데이션 + 액센트 글로우 — 평평한 단색보다 깊이가 산다.
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color.lerp(const Color(0xFF16243B), _accentGlow, 0.10)!,
                    const Color(0xFF0C1424),
                    const Color(0xFF080D17),
                  ],
                  stops: const [0, 0.55, 1],
                ),
              )
            : BoxDecoration(color: bg),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (style != ShareCardStyle.receipt) ...[
              _header(),
              SizedBox(height: story ? 26 : 16),
            ],
            Expanded(child: body),
            // 영수증은 로고·출처가 카드 안에 들어가므로 바깥 푸터를 그리지 않는다.
            if (style != ShareCardStyle.receipt) ...[
              SizedBox(height: story ? 18 : 12),
              _footer(),
            ],
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
              color: _dark ? _dCard : _tint,
              borderRadius: BorderRadius.circular(999),
              border: _dark ? Border.all(color: _dLine) : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome_rounded,
                  size: sc(11), color: _accentFg),
              const SizedBox(width: 4),
              Text(
                isEv ? 'AI 충전 추천' : 'AI 주유 추천',
                style: TextStyle(
                    fontSize: sc(11.5),
                    fontWeight: FontWeight.w800,
                    color: _accentFg),
              ),
            ]),
          ),
          const Spacer(),
          Text(_today(),
              style: TextStyle(
                  fontSize: sc(11),
                  fontWeight: FontWeight.w600,
                  color: _fgMuted)),
        ],
      );

  Widget _footer() => Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.asset(_logoAsset, width: sc(22), height: sc(22)),
          ),
          const SizedBox(width: 7),
          Text('전기차 기름차',
              style: TextStyle(
                  fontSize: sc(12.5),
                  fontWeight: FontWeight.w800,
                  color: _fg)),
          const Spacer(),
          Text(
            style == ShareCardStyle.receipt ? '출처: 오피넷' : '기름값·충전요금 아끼기',
            style: TextStyle(
                fontSize: sc(10.5),
                fontWeight: FontWeight.w600,
                color: _fgMuted),
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
    // 시안 7a: 라벨 → 큰 금액(숫자=액센트, '원 절약'=흰색) → 스테이션 행 →
    // 단가 타일 3칸 → 추천 vs 평균 비교 바 → AI 판단 한 줄.
    final m = RegExp(r'^(.*?)\s*(절약|아낌|절감)(!?)\$').firstMatch(headline.trim());
    final amount = m?.group(1) ?? headline;
    final tailText = m == null ? null : '\${m.group(2)}\${m.group(3)}';
    final isAmount = m != null;

    // 부제 — '주변 평균가 대비 · 30.8L 기준' (있는 재료로만 조립)
    String? liters;
    String extraTime = '+0분';
    for (final f in facts) {
      if (f.label == '주유량' || f.label == '충전량') liters = f.value;
      if (f.label == '추가 시간') extraTime = f.value;
    }
    final subParts = <String>[
      if (avgUnitWon != null) isEv ? '주변 평균 단가 대비' : '주변 평균가 대비',
      if (liters != null) '\$liters 기준',
    ];
    final hasUnits = myUnitWon != null && avgUnitWon != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (caption.trim().isNotEmpty) ...[
              Text(caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: sc(13),
                      fontWeight: FontWeight.w700,
                      color: _fgMuted)),
              SizedBox(height: sc(7)),
            ],
            // 시안: 숫자가 액센트(빛나는 쪽), '원 절약' 이 흰색.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(amount,
                      style: TextStyle(
                        fontSize: sc(isAmount ? 46 : 40),
                        fontWeight: FontWeight.w800,
                        color: isAmount ? _accentFg : _fg,
                        height: 1.02,
                        letterSpacing: -2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                  if (tailText != null) ...[
                    SizedBox(width: sc(7)),
                    Text(tailText,
                        style: TextStyle(
                          fontSize: sc(26),
                          fontWeight: FontWeight.w800,
                          color: _fg,
                          height: 1.02,
                          letterSpacing: -1,
                        )),
                  ],
                ],
              ),
            ),
            if (subParts.isNotEmpty) ...[
              SizedBox(height: sc(5)),
              Text(subParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: sc(11.5), color: _fgMuted)),
            ],
          ],
        ),
        if ((stationName ?? '').trim().isNotEmpty) _stationRowCard(),
        if (hasUnits) _unitTiles(extraTime) else if (facts.isNotEmpty) _factStrip(),
        if (hasUnits) _compareBars(),
        if ((verdict ?? '').trim().isNotEmpty) _verdictLine(),
      ],
    );
  }

  /// 시안 7a 스테이션 행 — 액센트 사각 아이콘 + 이름 + 보조줄.
  Widget _stationRowCard() => Container(
        padding: EdgeInsets.fromLTRB(sc(13), sc(12), sc(13), sc(12)),
        decoration: BoxDecoration(
          color: _dCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: sc(36),
              height: sc(36),
              decoration: BoxDecoration(
                color: isEv ? AppColors.evGreen : AppColors.gasBlue,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                isEv ? Icons.ev_station_rounded : Icons.local_gas_station_rounded,
                size: sc(19),
                color: Colors.white,
              ),
            ),
            SizedBox(width: sc(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(stationName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: sc(14),
                          fontWeight: FontWeight.w700,
                          color: _fg)),
                  if ((stationSub ?? '').trim().isNotEmpty) ...[
                    SizedBox(height: sc(2)),
                    Text(stationSub!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: sc(10.5), color: _fgMuted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  /// 시안 7a 타일 — [단가 / 주변 평균 / 추가 시간(액센트 틴트)].
  Widget _unitTiles(String extraTime) {
    final f = NumberFormat('#,###');
    Widget cell(String label, String big, String small,
        {bool tinted = false}) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.fromLTRB(sc(11), sc(10), sc(9), sc(10)),
          decoration: BoxDecoration(
            color: tinted ? _accentFg.withValues(alpha: 0.15) : _dCard,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: sc(9.5),
                      fontWeight: FontWeight.w600,
                      color: tinted
                          ? _accentFg.withValues(alpha: 0.85)
                          : _fgMuted)),
              SizedBox(height: sc(4)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(big,
                        style: TextStyle(
                          fontSize: sc(16),
                          fontWeight: FontWeight.w700,
                          color: tinted ? _accentFg : _fg,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                    if (small.isNotEmpty) ...[
                      SizedBox(width: sc(2)),
                      Text(small,
                          style: TextStyle(
                              fontSize: sc(9.5),
                              fontWeight: FontWeight.w500,
                              color: tinted
                                  ? _accentFg.withValues(alpha: 0.8)
                                  : _fgMuted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(children: [
      cell(isEv ? 'kWh당 단가' : '리터당 단가', f.format(myUnitWon), '원'),
      SizedBox(width: sc(8)),
      cell('주변 평균', f.format(avgUnitWon), '원'),
      SizedBox(width: sc(8)),
      cell('추가 시간', extraTime, '', tinted: true),
    ]);
  }

  /// 시안 7a 비교 바 — 추천(액센트) vs 주변 평균(흰 14%).
  Widget _compareBars() {
    final f = NumberFormat('#,###');
    final my = myUnitWon!;
    final avg = avgUnitWon!;
    final hi = my > avg ? my : avg;
    double frac(int v) => hi <= 0 ? 1 : (0.55 + 0.45 * (v / hi)).clamp(0.3, 1.0);
    Widget row(String label, int v, {required bool accentBar}) => Row(
          children: [
            SizedBox(
              width: sc(56),
              child: Text(label,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: sc(10),
                      fontWeight:
                          accentBar ? FontWeight.w700 : FontWeight.w500,
                      color: accentBar ? _accentFg : _fgMuted)),
            ),
            SizedBox(width: sc(6)),
            Expanded(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: frac(v),
                child: Container(
                  height: sc(7),
                  decoration: BoxDecoration(
                    color: accentBar
                        ? (isEv ? AppColors.evGreen : AppColors.gasBlue)
                        : Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
            SizedBox(width: sc(8)),
            Text(f.format(v),
                style: TextStyle(
                  fontSize: sc(10),
                  fontWeight: accentBar ? FontWeight.w700 : FontWeight.w600,
                  color: accentBar ? _fg : _fgMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ],
        );
    return Container(
      padding: EdgeInsets.fromLTRB(sc(13), sc(12), sc(13), sc(12)),
      decoration: BoxDecoration(
        color: _dCard,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(children: [
        row(isEv ? '추천 충전소' : '추천 주유소', my, accentBar: true),
        SizedBox(height: sc(7)),
        row('주변 평균', avg, accentBar: false),
      ]),
    );
  }

  /// 시안 7a AI 판단 줄 — '✨ AI 판단 · 우회 없이 가는 길이 최적'.
  Widget _verdictLine() => Row(
        children: [
          Icon(Icons.auto_awesome_rounded, size: sc(13), color: _accentFg),
          SizedBox(width: sc(6)),
          Text('AI 판단 · ',
              style: TextStyle(fontSize: sc(11), color: _fgMuted)),
          Expanded(
            child: Text(verdict!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: sc(11),
                    fontWeight: FontWeight.w700,
                    color: _fg)),
          ),
        ],
      );

  /// 출발 ─── ● 주유소 ─── 도착. 경로 위에 들렀다는 걸 한눈에 보여주는 조각.
  Widget _routeStrip() => Container(
        padding: EdgeInsets.fromLTRB(sc(16), sc(18), sc(16), sc(15)),
        decoration: BoxDecoration(
          color: _dark ? _dCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _dark ? _dLine : _line),
        ),
        child: Column(
          children: [
            Row(children: [
              _endDot(),
              Expanded(child: _dashLine()),
              _stationNode(),
              Expanded(child: _dashLine()),
              _endDot(),
            ]),
            SizedBox(height: sc(10)),
            Row(children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: sc(76)),
                child: Text((originName ?? '').trim().isNotEmpty ? originName! : '출발',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: sc(10.5),
                        fontWeight: FontWeight.w600,
                        color: _fgMuted)),
              ),
              Expanded(
                child: Text(
                  stationName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: sc(12.5),
                      fontWeight: FontWeight.w800,
                      color: _fg),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: sc(76)),
                child: Text((destName ?? '').trim().isNotEmpty ? destName! : '도착',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: sc(10.5),
                        fontWeight: FontWeight.w600,
                        color: _fgMuted)),
              ),
            ]),
          ],
        ),
      );

  Widget _endDot() => Container(
        width: sc(7),
        height: sc(7),
        decoration: BoxDecoration(
          color: _dark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
          shape: BoxShape.circle,
        ),
      );

  Widget _dashLine() => Padding(
        padding: EdgeInsets.symmetric(horizontal: sc(7)),
        child: SizedBox(
          height: 2,
          child: CustomPaint(
            painter: _DashPainter(
              color: _dark ? const Color(0xFF3A4A63) : const Color(0xFFCBD5E1),
            ),
          ),
        ),
      );

  /// 주유소 노드 — 액센트 원 + 바깥 글로우(다크에서만).
  Widget _stationNode() => Container(
        width: sc(26),
        height: sc(26),
        decoration: BoxDecoration(
          color: _accentFg,
          shape: BoxShape.circle,
          boxShadow: _dark
              ? [
                  BoxShadow(
                    color: _accentFg.withValues(alpha: 0.45),
                    blurRadius: sc(12),
                    spreadRadius: sc(1),
                  ),
                ]
              : null,
        ),
        child: Icon(
          isEv ? Icons.ev_station_rounded : Icons.local_gas_station_rounded,
          size: sc(14),
          color: _dark ? const Color(0xFF0A101C) : Colors.white,
        ),
      );

  Widget _factStrip() {
    final f = facts.take(3).toList();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: sc(12)),
      decoration: BoxDecoration(
        color: _dark ? _dCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _dark ? _dLine : _line),
      ),
      child: Row(
        children: [
          for (var i = 0; i < f.length; i++) ...[
            if (i > 0)
              Container(
                  width: 1, height: sc(26), color: _dark ? _dLine : _line),
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
                        style: TextStyle(
                            fontSize: sc(10),
                            fontWeight: FontWeight.w700,
                            color: _fgMuted)),
                    SizedBox(height: sc(4)),
                    _valueText(f[i].value, size: sc(15.5), color: _fg),
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

  /// '주변 평균 대비' 처럼 ▼ 로 시작하는 델타 값 — 시안에선 수치칸이 아니라
  /// 스테이션 바 오른쪽 배지로 붙는다.
  RevealFact? get _deltaFact {
    for (final f in facts) {
      if (f.value.trim().startsWith('▼') || f.label.contains('평균 대비')) return f;
    }
    return null;
  }

  Widget _recommendBody() {
    final d = _deltaFact;
    final f = facts.where((e) => e != d).take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
        ]),
        // 시안 7b: 헤드라인 → 경로 스트립(출발 ─ ● ─ 도착) → 수치 타일 순.
        if ((stationName ?? '').trim().isNotEmpty) _routeStrip(),
        if (f.isNotEmpty)
          // ⚠ Column 은 자식에게 세로 무한 제약을 준다 → stretch 만 쓰면 빌드가 터진다.
          //   (추천 카드 미리보기가 통째로 안 뜨던 원인) IntrinsicHeight 로 높이를 확정한다.
          IntrinsicHeight(
              child: Row(
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
          )),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((stationName ?? '').trim().isNotEmpty) ...[
            _stationBar(),
            const SizedBox(height: 9),
          ],
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
                            fontSize: sc(10),
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.78))),
                  ],
                ],
              ),
            ),
            if (_deltaFact != null) ...[
              const SizedBox(width: 8),
              Text(
                _deltaFact!.value.split('/').first, // '▼32원/L' → '▼32원'
                style: TextStyle(
                  fontSize: sc(15),
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      );

  // ── 스타일 3 : 영수증 ──────────────────────────────────────────────────────

  Widget _receiptBody() {
    // 시안 그대로: 제목/날짜 → 절취선 → 항목들 → 절취선 → 결제 예상액 → 절약 합계 → 로고.
    // 로고·출처는 카드 '안'에 들어간다(바깥 푸터는 이 스타일에서 숨긴다).
    final total = facts.where((f) => _isTotalLabel(f.label)).toList();
    // 피드(4:5)는 세로가 짧아 항목을 다 넣으면 넘친다. 스토리는 전부 들어간다.
    // 넘쳐서 잘리는 것보다 앞쪽 핵심 항목만 보이는 게 낫다.
    final all = facts.where((f) => !_isTotalLabel(f.label)).toList();
    final rows = story ? all : all.take(5).toList();
    return Container(
      padding: EdgeInsets.fromLTRB(sc(18), sc(18), sc(18), sc(14)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(isEv ? '충전 절약 영수증' : '주유 절약 영수증',
                style: TextStyle(
                    fontSize: sc(14),
                    fontWeight: FontWeight.w800,
                    color: _ink)),
            const Spacer(),
            Text(_today(),
                style: TextStyle(
                    fontSize: sc(10),
                    fontWeight: FontWeight.w600,
                    color: _muted)),
          ]),
          SizedBox(height: sc(13)),
          const _Dashed(),
          SizedBox(height: sc(11)),
          if ((stationName ?? '').trim().isNotEmpty)
            _receiptRow(isEv ? '충전소' : '주유소', stationName!),
          for (final f in rows) _receiptRow(f.label, f.value),
          // 남는 세로는 여기서 먹는다 — 스토리에서 항목이 위로 몰리지 않게.
          if (story) const Spacer() else SizedBox(height: sc(6)),
          SizedBox(height: sc(6)),
          const _Dashed(),
          SizedBox(height: sc(12)),
          if (total.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: sc(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(total.first.label,
                      style: TextStyle(
                          fontSize: sc(12.5),
                          fontWeight: FontWeight.w800,
                          color: _ink)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(total.first.value,
                            style: TextStyle(
                              fontSize: sc(21),
                              fontWeight: FontWeight.w800,
                              color: _ink,
                              letterSpacing: -0.8,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            )),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.fromLTRB(sc(14), sc(14), sc(14), sc(14)),
            decoration: BoxDecoration(
              color: _tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(_headlineIsAmount ? '절약 합계' : 'AI 판단',
                    style: TextStyle(
                        fontSize: sc(12.5),
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
                        maxLines: 1,
                        // 금액은 크게(주인공), 문구는 한 단 작게 — 25pt 문구는 칸을 넘겨 답답하다.
                        style: TextStyle(
                          fontSize: sc(_headlineIsAmount ? 25 : 16),
                          fontWeight: FontWeight.w800,
                          color: _accentInk,
                          letterSpacing: _headlineIsAmount ? -1 : -0.4,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: sc(14)),
          _footer(),
        ],
      ),
    );
  }

  /// '예상 주유비 / 예상 충전요금 / 결제 예상액' — 합계 줄로 따로 뺄 항목
  static bool _isTotalLabel(String label) =>
      label.contains('예상 주유비') ||
      label.contains('예상 충전요금') ||
      label.contains('결제');

  /// 헤드라인이 금액형('1,068원 절약!')인지 — 아니면 '가는 길이 최적!' 같은 문구다.
  bool get _headlineIsAmount =>
      RegExp(r'^(.*?)\s*(절약|아낌)!?$').hasMatch(headline.trim());

  /// 헤드라인에서 '절약!' 같은 꼬리말을 떼고 금액만 — 영수증에는 감탄사가 안 어울린다.
  String _savingsAmount() {
    final m = RegExp(r'^(.*?)\s*(절약|아낌)!?$').firstMatch(headline.trim());
    final amount =
        (m?.group(1) ?? headline).trim().replaceFirst(RegExp(r'^-'), '');
    // ▼ 는 '금액이 줄었다'는 기호다. '가는 길이 최적!' 같은 문구에 붙이면 말이 안 된다.
    return _headlineIsAmount ? '▼$amount' : amount;
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
  const _DashPainter({this.color = const Color(0xFFCBD5E1)});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
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
