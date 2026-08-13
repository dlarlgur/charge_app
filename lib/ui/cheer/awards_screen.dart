import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/services/cheer_service.dart';
import '../inbox/inbox_screen.dart';
import 'gold_profile.dart';

/// 월간 시상식 — handoff 3 (CheerAwards.html). 매월 결산 후 1등에게 1회 노출.
/// 상장 카드 + (치킨 배너) + 최종 순위 + 수상 결과 공유.
Future<void> showCheerAwards(
  BuildContext context, {
  required CheerAwards data,
  required String nickname,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'cheer-awards',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) =>
        AwardsScreen(data: data, nickname: nickname),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(begin: 0.98, end: 1.0)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
}

class AwardsScreen extends StatefulWidget {
  final CheerAwards data;
  final String nickname;

  const AwardsScreen({super.key, required this.data, required this.nickname});

  @override
  State<AwardsScreen> createState() => _AwardsScreenState();
}

class _AwardsScreenState extends State<AwardsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 5000));

  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 접근성 reduce motion 이면 포일 스윕·트윙클을 돌리지 않는다.
      if (!MediaQuery.of(context).disableAnimations) _anim.repeat();
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    await AwardsShare.share(context, data: widget.data, name: widget.nickname);
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final d = widget.data;
    final ink = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final capColor =
        isDark ? const Color(0xFF64748B) : const Color(0xFFA79573);

    return Material(
      color: isDark ? const Color(0xFF0B0D12) : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isDark
              ? null
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFFDF8),
                    Color(0xFFFCF8F0),
                    Color(0xFFF8FBFD),
                  ],
                  stops: [0, 0.4, 1],
                ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // 우상단 골드 글로우
              Positioned(
                right: -40,
                top: -30,
                child: IgnorePointer(
                  child: Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        const Color(0xFFE3B54C)
                            .withValues(alpha: isDark ? 0.18 : 0.20),
                        const Color(0x00E3B54C),
                      ]),
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  // 헤더 — 2026 · AUGUST + 닫기
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 10, 8),
                    child: Row(
                      children: [
                        Text(_headerLabel(d.month),
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                                color: capColor)),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              size: 19, color: capColor),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      children: [
                        CertificateCard(
                          anim: _anim,
                          isDark: isDark,
                          title: '${cheerMonthLabel(d.month)}의 응원왕',
                          name: widget.nickname,
                          count: d.first?.count ?? d.myCount,
                          footer: CertificateFooter.stamp,
                          stampLabel:
                              '전기차 기름차 · ${cheerMonthLabel(d.month)} 결산',
                        ),
                        if (d.chickenOn) ...[
                          const SizedBox(height: 9),
                          _chickenBanner(isDark, d),
                        ],
                        const SizedBox(height: 9),
                        _rankCard(isDark, d, ink),
                      ],
                    ),
                  ),
                  // CTA — 320dp 에서도 잘리지 않게 고정 높이 46 + 32
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFF6E4B8), Color(0xFFC9962B)],
                              ),
                            ),
                            child: TextButton(
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _sharing ? null : _share,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_sharing)
                                    const SizedBox(
                                        width: 17,
                                        height: 17,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF3A2A05)))
                                  else
                                    const Icon(Icons.ios_share_rounded,
                                        size: 18, color: Color(0xFF3A2A05)),
                                  const SizedBox(width: 7),
                                  const Text('수상 결과 공유',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF3A2A05))),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 32,
                          child: TextButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: Text(
                                '${cheerMonthLabel(_nextMonth(d.month))} 응원 시작하기',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF8A7C60))),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// '2026-08' → '2026 · AUGUST'
  static String _headerLabel(String month) {
    const names = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', //
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
    ];
    final parts = month.split('-');
    if (parts.length != 2) return month;
    final m = int.tryParse(parts[1]);
    if (m == null || m < 1 || m > 12) return month;
    return '${parts[0]} · ${names[m - 1]}';
  }

  static String _nextMonth(String month) {
    final parts = month.split('-');
    if (parts.length != 2) return month;
    final y = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    if (y == null || m == null) return month;
    return m == 12
        ? '${y + 1}-01'
        : '$y-${(m + 1).toString().padLeft(2, '0')}';
  }

  // ─── 치킨 이벤트 배너 (운영한 달에만) ───
  /// 결산 직후엔 아직 발송 전이다(수동 발송) — 그때는 예고만 한다.
  /// 도착한 뒤 다시 들어오면 눌러서 소식함 상세로 바로 간다.
  Widget _chickenBanner(bool isDark, CheerAwards d) {
    final banner = _chickenBox(isDark, d);
    if (!d.chickenSent) return banner;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).maybePop(); // 시상식을 닫고
          Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
              builder: (_) => InboxScreen(openId: d.chickenInboxId)));
        },
        child: banner,
      ),
    );
  }

  Widget _chickenBox(bool isDark, CheerAwards d) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0x2EF97316), Color(0x14F97316)]
              : const [Color(0xFFFFF4E8), Color(0xFFFFE8D2)],
        ),
        border: Border.all(
            color: isDark ? const Color(0x59FDBA74) : const Color(0xFFF4D6BA),
            width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: isDark ? const Color(0x33F97316) : const Color(0xFFFFE0C2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.redeem_rounded,
                size: 15,
                color:
                    isDark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1등에게 치킨 한 마리 쏩니다',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? const Color(0xFFF1F5F9)
                            : const Color(0xFF0F172A))),
                const SizedBox(height: 1),
                // 안내 문구는 잘리면 안 된다 — '며칠 안에 소식함으로' 가 잘리면
                // 언제 어디로 오는지가 사라져 배너가 의미를 잃는다. 320dp·배율 1.2
                // 에서는 한 줄에 안 들어가므로 두 줄까지 허용한다.
                Text(
                    d.chickenSent
                        ? '소식함에서 확인하세요'
                        : '치킨 기프티콘은 며칠 안에 소식함으로 보내드려요',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFA89B7E)
                            : const Color(0xFF8A6A4A))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(d.chickenSent ? '도착했어요' : '준비 중',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color:
                      isDark ? const Color(0xFFFDBA74) : const Color(0xFFB45309))),
        ],
      ),
    );
  }

  // ─── 최종 순위 ───
  Widget _rankCard(bool isDark, CheerAwards d, Color ink) {
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8);
    // 내가 3위 안에 이미 있으면 아래 '내 순위' 줄은 중복이라 뺀다.
    final meInTop = d.top.any((r) => r.me);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x0AFFFFFF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color:
                isDark ? const Color(0x14FFFFFF) : const Color(0xFFEDE6D8),
            width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 3),
            child: Row(
              children: [
                Text('${cheerMonthLabel(d.month)} 최종 순위',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: ink)),
                const Spacer(),
                Text('총 ${_comma(d.total)}회',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: muted)),
              ],
            ),
          ),
          for (final r in d.top) _rankRow(isDark, r, ink),
          if (!meInTop && d.myRank != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 3,
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? const Color(0xFF475569)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                ],
              ),
            ),
            _myRow(isDark, d, ink),
          ],
        ],
      ),
    );
  }

  Widget _rankRow(bool isDark, CheerAwardRank r, Color ink) {
    final isFirst = r.rank == 1;
    return Container(
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        gradient: isFirst
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [Color(0x2EE3B54C), Color(0x14E3B54C)]
                    : const [Color(0xFFFFF9EC), Color(0xFFFBEFD6)],
              )
            : null,
        border: isFirst
            ? Border.all(
                color: isDark
                    ? const Color(0x5AE3B54C)
                    : const Color(0xFFEBDCB8),
                width: 0.5)
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: const Alignment(-0.4, -1),
                end: const Alignment(0.4, 1),
                colors: CheerGold.medal(r.rank),
              ),
            ),
            alignment: Alignment.center,
            child: Text('${r.rank}',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: CheerGold.medalInk(r.rank))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(r.me ? '${r.name} (나)' : r.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isFirst ? FontWeight.w800 : FontWeight.w600,
                    color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E2A38))),
          ),
          Text('${r.count}',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                  color: isFirst
                      ? (isDark
                          ? const Color(0xFFFCEBB6)
                          : const Color(0xFF8A6A2E))
                      : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF43556B)))),
        ],
      ),
    );
  }

  Widget _myRow(bool isDark, CheerAwards d, Color ink) {
    final blue = isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: isDark ? const Color(0x1A3B82F6) : const Color(0xFFF3F8FF),
        border: Border.all(
            color:
                isDark ? const Color(0x593B82F6) : const Color(0xFFB9D6F7)),
      ),
      child: Row(
        children: [
          Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0x333B82F6) : const Color(0xFFDBEAFE),
            ),
            alignment: Alignment.center,
            child: Text('${d.myRank}',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                    color: blue)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: widget.nickname,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF1E2A38))),
                TextSpan(
                    text: ' (나)',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8))),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (d.delta != null && d.delta != 0) ...[
            Text(
                d.delta! > 0
                    ? '▲${d.delta}'
                    : '▼${d.delta!.abs()}',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: d.delta! > 0
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444))),
            const SizedBox(width: 6),
          ],
          Text('${d.myCount}',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                  color: blue)),
        ],
      ),
    );
  }

  static String _comma(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

enum CertificateFooter { stamp, share }

/// 상장 카드 — 시상식 화면과 공유 이미지가 같은 포맷을 쓴다.
/// 골드 포일 스윕 + 내부 프레임 + ✦ 4모서리 + 상단 스파클.
class CertificateCard extends StatelessWidget {
  /// 5초 루프 (0~1). 정지 상태로 그리려면 kAlwaysCompleteAnimation 등을 넘긴다.
  final Animation<double> anim;
  final bool isDark;
  final String title; // '8월의 응원왕'
  final String name;
  final int count;
  final CertificateFooter footer;
  final String? stampLabel; // footer=stamp 일 때
  final bool chicken; // footer=share 일 때 치킨 pill 노출
  final double radius;
  final EdgeInsets padding;

  const CertificateCard({
    super.key,
    required this.anim,
    required this.isDark,
    required this.title,
    required this.name,
    required this.count,
    required this.footer,
    this.stampLabel,
    this.chicken = false,
    this.radius = 18,
    this.padding = const EdgeInsets.fromLTRB(18, 20, 18, 18),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: const Alignment(-0.45, -1),
            end: const Alignment(0.45, 1),
            colors: isDark
                ? const [Color(0xFF1E242E), Color(0xFF28303B), Color(0xFF1B212A)]
                : const [
                    Color(0xFFFFFFFF),
                    Color(0xFFFFF8E7),
                    Color(0xFFFFFDF7),
                    Color(0xFFFAEDD2),
                  ],
            stops: isDark ? const [0, 0.46, 1] : const [0, 0.38, 0.66, 1],
          ),
        ),
        child: Stack(
          children: [
            // 골드 포일 스윕
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: anim,
                  builder: (_, __) => _foil(anim.value),
                ),
              ),
            ),
            // 내부 골드 프레임
            Positioned(
              left: 11,
              top: 11,
              right: 11,
              bottom: 11,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius - 6),
                    border: Border.all(
                        color: const Color(0xFFC9A354)
                            .withValues(alpha: isDark ? 0.45 : 0.5)),
                  ),
                ),
              ),
            ),
            // ✦ 4모서리 + 상단 스파클
            Positioned(
                left: 26,
                top: 16,
                child: GoldTwinkle(
                    anim: anim,
                    size: 9,
                    color: isDark
                        ? CheerGold.twinkleD
                        : CheerGold.twinkleL)),
            Positioned(
                right: 26,
                top: 16,
                child: GoldTwinkle(
                    anim: anim,
                    size: 9,
                    delaySec: 0.5,
                    color: isDark
                        ? CheerGold.twinkleD2
                        : CheerGold.twinkleL2)),
            Positioned(
                right: 26,
                bottom: 16,
                child: GoldTwinkle(
                    anim: anim,
                    size: 9,
                    delaySec: 1.1,
                    color: isDark
                        ? CheerGold.twinkleD
                        : CheerGold.twinkleL)),
            Positioned(
                left: 26,
                bottom: 16,
                child: GoldTwinkle(
                    anim: anim,
                    size: 9,
                    delaySec: 1.7,
                    color: isDark
                        ? CheerGold.twinkleD2
                        : CheerGold.twinkleL2)),
            Padding(
              padding: padding,
              child: footer == CertificateFooter.stamp
                  ? _stampBody()
                  : _shareBody(),
            ),
          ],
        ),
      ),
    );
  }

  /// 시상식 화면용 — 아래 도장 pill 로 끝난다.
  Widget _stampBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _cap(),
        const SizedBox(height: 10),
        _title(),
        const SizedBox(height: 5),
        _name(26),
        const SizedBox(height: 12),
        _divider(),
        const SizedBox(height: 12),
        _count(34),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFC9A354)
                .withValues(alpha: isDark ? 0.18 : 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: const Color(0xFFC9A354).withValues(alpha: 0.42),
                width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                  child: Image.asset(CheerGold.iconAsset,
                      width: 17, height: 17, fit: BoxFit.cover)),
              const SizedBox(width: 7),
              Text(stampLabel ?? '전기차 기름차',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? const Color(0xFFE8CE93)
                          : const Color(0xFF8A6A2E))),
            ],
          ),
        ),
      ],
    );
  }

  /// 공유 이미지용 — 리디자인: 본문을 위·아래 여백 사이에 두고 푸터는 바닥 고정.
  /// (기존 시안은 본문이 위 60%에 몰리고 아래가 비어 '위로 쏠려' 보였다)
  Widget _shareBody() {
    return Column(
      children: [
        const Spacer(flex: 10),
        _cap(),
        const SizedBox(height: 10),
        _divider(),
        const SizedBox(height: 14),
        _title(),
        const SizedBox(height: 6),
        _name(27),
        const SizedBox(height: 16),
        _count(38),
        if (chicken) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF97316)
                  .withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: isDark
                      ? const Color(0xFFFDBA74).withValues(alpha: 0.40)
                      : const Color(0xFFEA580C).withValues(alpha: 0.28),
                  width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.redeem_rounded,
                    size: 13,
                    color: isDark
                        ? const Color(0xFFFDBA74)
                        : const Color(0xFFC2410C)),
                const SizedBox(width: 6),
                Text('치킨 기프티콘 수상',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? const Color(0xFFFDBA74)
                            : const Color(0xFFC2410C))),
              ],
            ),
          ),
        ],
        const Spacer(flex: 12),
        // 점선 + 푸터
        CustomPaint(
          size: const Size(double.infinity, 1),
          painter: _DashedLine(
              color: const Color(0xFFC9A354).withValues(alpha: 0.35)),
        ),
        const SizedBox(height: 11),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipOval(
                child: Image.asset(CheerGold.iconAsset,
                    width: 18, height: 18, fit: BoxFit.cover)),
            const SizedBox(width: 7),
            Text('전기차 기름차',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? const Color(0xFFFCEBB6)
                        : const Color(0xFF8A6A2E))),
            const SizedBox(width: 5),
            Text('· 충전·주유 최저가',
                style: TextStyle(
                    fontSize: 10, color: CheerGold.subOnGold(isDark))),
          ],
        ),
      ],
    );
  }

  Widget _cap() => Text('CERTIFICATE',
      style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.1,
          color: CheerGold.cap(isDark)));

  Widget _title() => Text(title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: CheerGold.subOnGold(isDark)));

  Widget _name(double size) => ShaderMask(
        shaderCallback: (r) => LinearGradient(
          begin: const Alignment(-0.4, -1),
          end: const Alignment(0.4, 1),
          colors: CheerGold.nameGrad(isDark),
        ).createShader(r),
        child: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: Colors.white)),
      );

  Widget _divider() => Container(
        width: 58,
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            const Color(0xFFC9A354).withValues(alpha: 0),
            const Color(0xFFC9A354).withValues(alpha: isDark ? 0.85 : 0.8),
            const Color(0xFFC9A354).withValues(alpha: 0),
          ]),
        ),
      );

  Widget _count(double size) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('$count',
              style: TextStyle(
                  fontSize: size,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                  color: CheerGold.inkOnGold(isDark))),
          const SizedBox(width: 5),
          Text('회 응원',
              style: TextStyle(
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w700,
                  color: CheerGold.subOnGold(isDark))),
        ],
      );

  /// 5초 루프 중 52~82% 구간에 비스듬한 화이트 포일이 지나간다.
  Widget _foil(double t) {
    if (t < 0.52 || t > 0.82) return const SizedBox.shrink();
    final k = (t - 0.52) / 0.30;
    final op = k < 0.27 ? k / 0.27 : 1 - (k - 0.27) / 0.73;
    return LayoutBuilder(builder: (_, c) {
      final w = c.maxWidth;
      return ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: -0.64 * w + k * 1.86 * w,
              top: -10,
              bottom: -10,
              width: w * 0.36,
              child: Opacity(
                opacity: op.clamp(0.0, 1.0),
                child: Transform(
                  transform: Matrix4.skewX(-0.31),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.white.withValues(alpha: 0),
                        isDark
                            ? const Color(0xFFFDE68A).withValues(alpha: 0.34)
                            : Colors.white.withValues(alpha: 0.95),
                        Colors.white.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _DashedLine extends CustomPainter {
  final Color color;
  const _DashedLine({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0, gap = 3.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(
          Offset(x, 0), Offset(math.min(x + dash, size.width), 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => old.color != color;
}

/// 수상 결과 공유 — 상장 카드를 4:5 PNG(1080×1350)로 렌더해 시스템 공유로 보낸다.
class AwardsShare {
  AwardsShare._();

  /// 공유 카드 논리 크기 (4:5). 렌더는 1080×1350.
  static const cardW = 270.0;
  static const cardH = 337.5;

  static Future<void> share(BuildContext context,
      {required CheerAwards data, required String name}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    try {
      // 오프스크린 렌더는 이미지 로딩을 기다려주지 않는다 — 푸터 로고를 미리 캐시에
      // 올려야 캡처 결과에 빈 원이 남지 않는다(savings_share_card 와 같은 이유).
      await precacheImage(const AssetImage(CheerGold.iconAsset), context);
      if (!context.mounted) return;
      final card = SizedBox(
        width: cardW,
        height: cardH,
        child: CertificateCard(
          anim: kAlwaysDismissedAnimation, // 정지 프레임 — 포일/✦ 없이 깔끔하게
          isDark: isDark,
          title: '${cheerMonthLabelFull(data.month)}의 응원왕',
          name: name,
          count: data.first?.count ?? data.myCount,
          footer: CertificateFooter.share,
          chicken: data.chickenOn,
          radius: 20,
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
        ),
      );
      final bytes = await _render(card, context);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/award_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)],
          text: '${cheerMonthLabel(data.month)}의 응원왕 · 전기차 기름차');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('이미지를 만들지 못했어요. 잠시 후 다시 시도해 주세요.')));
    }
  }

  /// 위젯을 화면에 붙이지 않고 오프스크린으로 PNG 렌더 (savings_share_card 와 동일 방식).
  static Future<Uint8List?> _render(Widget child, BuildContext context) async {
    final repaint = RenderRepaintBoundary();
    final view = View.of(context);
    const pixelRatio = 1080 / cardW;

    final renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        physicalConstraints:
            BoxConstraints.tight(const Size(cardW, cardH) * pixelRatio),
        logicalConstraints: BoxConstraints.tight(const Size(cardW, cardH)),
        devicePixelRatio: pixelRatio,
      ),
      child: RenderPositionedBox(alignment: Alignment.center, child: repaint),
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
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }
}
