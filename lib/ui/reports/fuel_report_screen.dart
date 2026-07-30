import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../providers/providers.dart';

/// 유가 · 충전 리포트 — 주간/월간 리포트 목록과 상세.
///
/// 리포트는 주제별로 따로 발행된다(유가 / 충전). 내 차종에 없는 주제는 탭 자체를
/// 만들지 않는다 — 주유만 쓰는 사용자에게 충전 요금을 보여줄 이유가 없다.
class FuelReportScreen extends ConsumerStatefulWidget {
  const FuelReportScreen({super.key});

  @override
  ConsumerState<FuelReportScreen> createState() => _FuelReportScreenState();
}

class _FuelReportScreenState extends ConsumerState<FuelReportScreen>
    with TickerProviderStateMixin {
  TabController? _tab;
  List<String> _topics = const ['fuel'];

  final _cache = <String, List<Map<String, dynamic>>>{};
  final _loading = <String, bool>{};
  final _error = <String, String?>{};

  @override
  void initState() {
    super.initState();
    // 차종 → 볼 수 있는 주제
    final v = ref.read(settingsProvider).vehicleType;
    _topics = switch (v) {
      VehicleType.gas => const ['fuel'],
      VehicleType.ev => const ['ev'],
      VehicleType.both => const ['fuel', 'ev'],
    };
    _tab = TabController(length: _topics.length, vsync: this);
    _tab!.addListener(() {
      if (_tab!.indexIsChanging) return;
      // 스와이프로 넘겨도 탭 강조색(유가=파랑/충전=초록)이 따라오게 리빌드
      if (mounted) setState(() {});
      _load(_topics[_tab!.index]);
    });
    _load(_topics.first);
  }

  @override
  void dispose() {
    _tab?.dispose();
    super.dispose();
  }

  Color _accent(String topic) =>
      topic == 'ev' ? AppColors.evGreen : AppColors.gasBlue;

  Future<void> _load(String topic, {bool force = false}) async {
    if (!force && (_cache.containsKey(topic) || _loading[topic] == true)) {
      return;
    }
    setState(() {
      _loading[topic] = true;
      _error[topic] = null;
    });
    try {
      final list = await ApiService().getFuelReports(topic: topic, limit: 30);
      if (!mounted) return;
      setState(() {
        _cache[topic] = list;
        _loading[topic] = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading[topic] = false;
        _error[topic] = '리포트를 불러오지 못했어요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final single = _topics.length == 1;
    final accent = _accent(_topics[single ? 0 : (_tab?.index ?? 0)]);
    return Scaffold(
      appBar: AppBar(
        title: Text(single
            ? (_topics.first == 'ev' ? '충전 리포트' : '유가 리포트')
            : '유가 · 충전 리포트'),
        bottom: single
            ? null
            : TabBar(
                controller: _tab,
                labelColor: accent,
                unselectedLabelColor:
                    isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                indicatorColor: accent,
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                tabs: const [Tab(text: '유가'), Tab(text: '충전')],
              ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [for (final t in _topics) _list(t, isDark)],
      ),
    );
  }

  Widget _list(String topic, bool isDark) {
    if (_loading[topic] == true && !_cache.containsKey(topic)) {
      return Center(
          child:
              CircularProgressIndicator(strokeWidth: 2, color: _accent(topic)));
    }
    final err = _error[topic];
    final items = _cache[topic] ?? const <Map<String, dynamic>>[];
    if (err != null && items.isEmpty) {
      return _empty(isDark, err, retry: () => _load(topic, force: true));
    }
    if (items.isEmpty) {
      return _empty(
        isDark,
        topic == 'ev' ? '아직 발행된 충전 리포트가 없어요' : '아직 발행된 유가 리포트가 없어요',
        sub: topic == 'ev'
            ? '매주 충전 요금과 정책 흐름을 정리해 알려드려요'
            : '매주 기름값 흐름과 정책 소식을 정리해 알려드려요',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(topic, force: true),
      color: _accent(topic),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _card(items[i], isDark),
      ),
    );
  }

  Widget _empty(bool isDark, String title, {String? sub, VoidCallback? retry}) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 80, 28, 28),
      children: [
        Icon(Icons.insights_rounded,
            size: 44, color: muted.withValues(alpha: 0.5)),
        const SizedBox(height: 14),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary)),
        if (sub != null) ...[
          const SizedBox(height: 6),
          Text(sub,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.5, color: muted)),
        ],
        if (retry != null) ...[
          const SizedBox(height: 16),
          Center(
            child: TextButton(onPressed: retry, child: const Text('다시 시도')),
          ),
        ],
      ],
    );
  }

  Widget _card(Map<String, dynamic> r, bool isDark) {
    final topic = (r['topic'] ?? 'fuel').toString();
    final monthly = r['kind'] == 'monthly';
    final accent = _accent(topic);
    final date = _fmtDate(r['date'], monthly: monthly);
    return Material(
      color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          final id = int.tryParse(r['id']?.toString() ?? '');
          if (id == null) return;
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FuelReportDetailScreen(reportId: id)));
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isDark
                    ? AppColors.darkCardBorder
                    : AppColors.lightCardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _pill(monthly ? '월간 종합' : '주간', accent, isDark),
                  const SizedBox(width: 6),
                  Text(date,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted)),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded,
                      size: 20,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted),
                ],
              ),
              const SizedBox(height: 9),
              Text((r['title'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary)),
              if ((r['summary'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(r['summary'].toString(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.55,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Widget _pill(String text, Color accent, bool isDark) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: accent)),
    );

String _fmtDate(dynamic raw, {bool monthly = false}) {
  final s = (raw ?? '').toString();
  if (s.length < 10) return s;
  final y = s.substring(0, 4), m = s.substring(5, 7), d = s.substring(8, 10);
  return monthly ? '$y년 ${int.parse(m)}월' : '$y.$m.$d';
}

/* ══════════════════════════ 상세 ══════════════════════════ */

class FuelReportDetailScreen extends StatefulWidget {
  const FuelReportDetailScreen({super.key, required this.reportId});

  final int reportId;

  @override
  State<FuelReportDetailScreen> createState() => _FuelReportDetailScreenState();
}

class _FuelReportDetailScreenState extends State<FuelReportDetailScreen> {
  Map<String, dynamic>? _r;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ApiService().getFuelReport(widget.reportId);
      if (!mounted) return;
      setState(() {
        _r = r;
        _loading = false;
        if (r == null) _error = _kGone;
      });
    } catch (e) {
      if (!mounted) return;
      // 404 = 아직 공개되지 않았거나 내려간 리포트. 통신 실패와 원인이 달라 문구를 나눈다.
      final code = e is DioException ? e.response?.statusCode : null;
      setState(() {
        _loading = false;
        _error = code == 404 ? _kGone : '리포트를 불러오지 못했어요';
      });
    }
  }

  static const _kGone = '지금은 볼 수 없는 리포트예요';

  // 섹션 순서·라벨 — 주제별로 쓰는 키만 등장한다
  static const _sections = <String, (String, IconData)>{
    'domestic': ('국내 기름값', Icons.local_gas_station_rounded),
    'intl': ('국제 유가', Icons.public_rounded),
    'ev': ('충전 요금', Icons.ev_station_rounded),
    'policy': ('정책 · 제도', Icons.gavel_rounded),
    'outlook': ('전망 · 팁', Icons.lightbulb_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = _r;
    final topic = (r?['topic'] ?? 'fuel').toString();
    final accent = topic == 'ev' ? AppColors.evGreen : AppColors.gasBlue;
    final monthly = r?['kind'] == 'monthly';

    return Scaffold(
      appBar: AppBar(
        title: Text(topic == 'ev' ? '충전 리포트' : '유가 리포트'),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: accent))
          : (r == null
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
                  child: Column(
                    children: [
                      Icon(Icons.insights_rounded,
                          size: 40,
                          color: (isDark
                                  ? AppColors.darkTextMuted
                                  : AppColors.lightTextMuted)
                              .withValues(alpha: 0.5)),
                      const SizedBox(height: 14),
                      Text(_error ?? _kGone,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary)),
                      const SizedBox(height: 8),
                      Text(
                          _error == _kGone
                              ? '리포트가 내려갔거나 아직 공개 전이에요.\n목록에서 다른 리포트를 확인해 주세요.'
                              : '잠시 후 다시 시도해 주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: isDark
                                  ? AppColors.darkTextMuted
                                  : AppColors.lightTextMuted)),
                      const SizedBox(height: 14),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          _load();
                        },
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
                  children: [
                    Row(
                      children: [
                        _pill(monthly ? '월간 종합' : '주간', accent, isDark),
                        const SizedBox(width: 6),
                        Text(_fmtDate(r['date'], monthly: monthly),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text((r['title'] ?? '').toString(),
                        style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            height: 1.3,
                            letterSpacing: -0.4,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary)),
                    if ((r['summary'] ?? '').toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(r['summary'].toString(),
                          style: TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary)),
                    ],
                    const SizedBox(height: 18),

                    // ── 수치 시각화 ──
                    if (topic == 'ev')
                      ..._evVisuals(r['facts'], isDark, accent)
                    else
                      ..._fuelVisuals(r['facts'], isDark),

                    // ── 섹션 본문 ──
                    for (final e in _sections.entries)
                      if (((r['detail'] as Map?)?[e.key] ?? '')
                          .toString()
                          .trim()
                          .isNotEmpty)
                        _sectionCard(
                          isDark: isDark,
                          accent: accent,
                          icon: e.value.$2,
                          title: e.value.$1,
                          body: (r['detail'] as Map)[e.key].toString(),
                        ),

                    _sources(r['sources'], isDark, accent),
                  ],
                )),
    );
  }

  /* ── 유가: 오늘 가격 + 7일 추이 + 시도별 ── */

  List<Widget> _fuelVisuals(dynamic factsRaw, bool isDark) {
    final f = factsRaw is Map ? factsRaw : const {};
    final g = f['gasoline'] is Map ? f['gasoline'] as Map : null;
    final d = f['diesel'] is Map ? f['diesel'] as Map : null;
    final week = f['week'] is Map ? f['week'] as Map : null;
    final sido = f['sido'] is Map ? f['sido'] as Map : null;
    final out = <Widget>[];

    if (g != null || d != null) {
      out.add(_panel(
        isDark: isDark,
        child: Row(
          children: [
            if (g != null)
              Expanded(
                  child: _priceCell(
                      '휘발유', g['price'], g['diff'], AppColors.gasBlue, isDark)),
            if (g != null && d != null)
              Container(
                  width: 1,
                  height: 46,
                  color: isDark
                      ? AppColors.darkCardBorder
                      : AppColors.lightCardBorder),
            if (d != null)
              Expanded(
                  child: _priceCell('경유', d['price'], d['diff'],
                      const Color(0xFF8B5CF6), isDark)),
          ],
        ),
      ));
    }

    final gPts = _series(week?['gasoline']);
    final dPts = _series(week?['diesel']);
    if (gPts.length >= 2 || dPts.length >= 2) {
      out.add(_panel(
        isDark: isDark,
        title: '최근 7일 전국 평균',
        legend: [
          ('휘발유', AppColors.gasBlue),
          if (dPts.length >= 2) ('경유', const Color(0xFF8B5CF6)),
        ],
        child: SizedBox(
          height: 168,
          child: _lineChart(
              gPts, AppColors.gasBlue, dPts, const Color(0xFF8B5CF6), isDark),
        ),
      ));
    }

    // 국제유가 (EIA Brent/WTI) — 국내 가격과 별도 축(USD/배럴)이라 패널을 분리한다
    final intl = f['intl'] is Map ? f['intl'] as Map : null;
    final brent = _series(intl?['brent'], key: 'usd');
    final wti = _series(intl?['wti'], key: 'usd');
    if (brent.length >= 2 || wti.length >= 2) {
      final last =
          brent.isNotEmpty ? brent.last : (wti.isNotEmpty ? wti.last : null);
      out.add(_panel(
        isDark: isDark,
        title: '국제유가 (달러/배럴)',
        legend: [
          if (brent.length >= 2) ('브렌트', const Color(0xFFF59E0B)),
          if (wti.length >= 2) ('WTI', const Color(0xFF06B6D4)),
        ],
        child: Column(
          children: [
            SizedBox(
              height: 168,
              child: _lineChart(brent, const Color(0xFFF59E0B), wti,
                  const Color(0xFF06B6D4), isDark,
                  usd: true),
            ),
            const SizedBox(height: 6),
            _caption(
                last == null
                    ? '미국 에너지정보청(EIA) 일별 현물가'
                    : '미국 에너지정보청(EIA) 일별 현물가 · 국내 가격에는 통상 2~3주 시차로 반영돼요',
                isDark),
          ],
        ),
      ));
    }

    final cheap = _sidoList(sido?['cheapest']);
    final pricey = _sidoList(sido?['priciest']);
    if (cheap.isNotEmpty || pricey.isNotEmpty) {
      final all = [...cheap, ...pricey];
      final maxV = all.map((e) => e.$2).reduce((a, b) => a > b ? a : b);
      final minV = all.map((e) => e.$2).reduce((a, b) => a < b ? a : b);
      out.add(_panel(
        isDark: isDark,
        title: '지역별 휘발유 평균',
        child: Column(
          children: [
            for (final row in cheap)
              _bar(row.$1, row.$2, minV, maxV, AppColors.evGreen, isDark,
                  unit: '원'),
            if (cheap.isNotEmpty && pricey.isNotEmpty)
              const SizedBox(height: 10),
            for (final row in pricey)
              _bar(row.$1, row.$2, minV, maxV, const Color(0xFFEF4444), isDark,
                  unit: '원'),
            const SizedBox(height: 4),
            _caption('초록 = 저렴한 지역 · 빨강 = 비싼 지역', isDark),
          ],
        ),
      ));
    }
    return out;
  }

  /* ── 충전: 평균/최저/최고 + 운영사별 급속 회원가 ── */

  List<Widget> _evVisuals(dynamic factsRaw, bool isDark, Color accent) {
    final f = factsRaw is Map ? factsRaw : const {};
    final ev = f['ev'] is Map ? f['ev'] as Map : const {};
    final avg = _num(ev['avg']);
    final min = _num(ev['min']);
    final max = _num(ev['max']);
    final prev = _num(f['prev_ev_avg']);
    final ops = <(String, double, int?)>[];
    for (final o
        in (ev['operators'] is List ? ev['operators'] as List : const [])) {
      if (o is! Map) continue;
      final v = _num(o['fast']);
      if (v == null) continue;
      ops.add(((o['name'] ?? '').toString(), v, _num(o['stations'])?.toInt()));
    }
    final out = <Widget>[];

    if (avg != null) {
      out.add(_panel(
        isDark: isDark,
        child: Row(
          children: [
            Expanded(
                child: _statCell('평균', avg, accent, isDark,
                    delta: prev == null ? null : avg - prev)),
            Container(
                width: 1,
                height: 46,
                color: isDark
                    ? AppColors.darkCardBorder
                    : AppColors.lightCardBorder),
            Expanded(child: _statCell('최저', min, AppColors.evGreen, isDark)),
            Container(
                width: 1,
                height: 46,
                color: isDark
                    ? AppColors.darkCardBorder
                    : AppColors.lightCardBorder),
            Expanded(
                child: _statCell('최고', max, const Color(0xFFEF4444), isDark)),
          ],
        ),
      ));
    }

    if (ops.isNotEmpty) {
      final maxV = ops.map((e) => e.$2).reduce((a, b) => a > b ? a : b);
      final minV = ops.map((e) => e.$2).reduce((a, b) => a < b ? a : b);
      out.add(_panel(
        isDark: isDark,
        title: '운영사별 급속 회원가',
        child: Column(
          children: [
            for (final o in ops)
              _bar(o.$1, o.$2, minV, maxV, accent, isDark,
                  unit: '원', sub: o.$3 == null ? null : '${_comma(o.$3!)}기'),
            const SizedBox(height: 4),
            _caption('kWh당 회원가 · 충전기 수 많은 주요 운영사', isDark),
          ],
        ),
      ));
    }
    return out;
  }

  /* ── 공통 조각 ── */

  Widget _panel({
    required bool isDark,
    required Widget child,
    String? title,
    List<(String, Color)>? legend,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary)),
                ),
                if (legend != null)
                  for (final l in legend) ...[
                    const SizedBox(width: 8),
                    Container(
                        width: 7,
                        height: 7,
                        decoration:
                            BoxDecoration(color: l.$2, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(l.$1,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.darkTextMuted
                                : AppColors.lightTextMuted)),
                  ],
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }

  Widget _priceCell(
      String label, dynamic price, dynamic diff, Color color, bool isDark) {
    final p = _num(price);
    final dv = _num(diff);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted)),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(p == null ? '-' : _comma(p.round()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                      color: color)),
            ),
            const SizedBox(width: 2),
            Text('원',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted)),
          ],
        ),
        if (dv != null) ...[
          const SizedBox(height: 3),
          _deltaChip(dv, isDark, suffix: '원 (어제 대비)'),
        ],
      ],
    );
  }

  Widget _statCell(String label, double? v, Color color, bool isDark,
      {double? delta}) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted)),
        const SizedBox(height: 5),
        FittedBox(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(v == null ? '-' : _comma(v.round()),
                  style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: color)),
              const SizedBox(width: 1),
              Text('원',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted)),
            ],
          ),
        ),
        if (delta != null && delta.abs() >= 1) ...[
          const SizedBox(height: 3),
          _deltaChip(delta, isDark, suffix: '원 (전주 대비)'),
        ],
      ],
    );
  }

  Widget _deltaChip(double v, bool isDark, {String suffix = ''}) {
    final up = v > 0;
    final flat = v.abs() < 0.005;
    final c = flat
        ? (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)
        : (up ? const Color(0xFFEF4444) : AppColors.evGreen);
    final txt = flat
        ? '변동 없음'
        : '${up ? '▲' : '▼'} ${v.abs() < 10 ? v.abs().toStringAsFixed(2) : _comma(v.abs().round())}$suffix';
    return Text(txt,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c));
  }

  /// 가로 바 — 값 차이가 작아도 보이게 최소/최대 사이를 0.35~1.0 폭으로 매핑.
  Widget _bar(String label, double value, double minV, double maxV, Color color,
      bool isDark,
      {String unit = '', String? sub}) {
    final span = (maxV - minV).abs();
    final ratio = span < 0.01 ? 1.0 : 0.35 + 0.65 * ((value - minV) / span);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: ratio.clamp(0.06, 1.0),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.85 : 1.0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: sub == null ? 56 : 84,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${_comma(value.round())}$unit',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary)),
                if (sub != null)
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 두 시리즈 라인차트 — 국내(원/L)와 국제유가(달러/배럴)를 같은 스타일로 그린다.
  Widget _lineChart(List<(String, double)> gas, Color colorA,
      List<(String, double)> diesel, Color colorB, bool isDark,
      {bool usd = false}) {
    final all = [...gas.map((e) => e.$2), ...diesel.map((e) => e.$2)];
    if (all.isEmpty) return const SizedBox.shrink();
    final maxY = all.reduce((a, b) => a > b ? a : b);
    final minY = all.reduce((a, b) => a < b ? a : b);
    final span = (maxY - minY).abs();
    final pad = span < 1 ? (usd ? 1.0 : 8.0) : span * 0.35;
    final base = gas.isNotEmpty ? gas : diesel;
    // 달러는 소수 1자리까지 (배럴당 91.8 처럼), 원은 정수
    String fmtY(double v) => usd ? v.toStringAsFixed(1) : _comma(v.round());
    final yStep = usd
        ? (span < 4 ? 1.0 : (span / 3).ceilToDouble())
        : (span < 4 ? 2.0 : (span / 2).ceilToDouble());
    final dotFill = isDark ? AppColors.darkSurface1 : AppColors.lightCard;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    LineChartBarData bar(List<(String, double)> pts, Color c, double w) =>
        LineChartBarData(
          spots: [
            for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), pts[i].$2)
          ],
          isCurved: true,
          curveSmoothness: 0.25,
          preventCurveOverShooting: true,
          color: c,
          barWidth: w,
          dotData: FlDotData(
            show: true,
            getDotPainter: (s, p, b, i) => FlDotCirclePainter(
              radius: 3.0,
              color: dotFill,
              strokeColor: c,
              strokeWidth: 1.8,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.withValues(alpha: 0.16), c.withValues(alpha: 0.0)],
            ),
          ),
        );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (base.length - 1).toDouble(),
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yStep,
          getDrawingHorizontalLine: (_) => FlLine(
            color:
                (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07),
            strokeWidth: 1,
            dashArray: const [2, 4],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: usd ? 38 : 46,
              interval: yStep,
              getTitlesWidget: (v, meta) {
                if (v <= minY - pad + 0.5 || v >= maxY + pad - 0.5) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(fmtY(v),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: muted)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= base.length) return const SizedBox.shrink();
                final last = i == base.length - 1;
                // 7개면 하루 걸러 하나씩 — 라벨 겹침 방지
                if (!last && i % 2 != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(last ? '최근' : _mmdd(base[i].$1),
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: muted)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          if (diesel.length >= 2) bar(diesel, colorB, 2.0),
          if (gas.length >= 2) bar(gas, colorA, 2.4),
        ],
      ),
    );
  }

  Widget _caption(String text, bool isDark) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted)),
      );

  Widget _sectionCard({
    required bool isDark,
    required Color accent,
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: accent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(body,
              style: TextStyle(
                  fontSize: 13.5,
                  height: 1.72,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary)),
        ],
      ),
    );
  }

  Widget _sources(dynamic raw, bool isDark, Color accent) {
    final list = raw is List ? raw : const [];
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (list.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('참고자료',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary)),
          const SizedBox(height: 8),
          for (final s in list)
            if (s is Map)
              InkWell(
                onTap: () {
                  final u = (s['link'] ?? '').toString();
                  if (u.startsWith('http')) {
                    launchUrl(Uri.parse(u),
                        mode: LaunchMode.externalApplication);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.link_rounded, size: 14, color: accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text((s['title'] ?? '').toString(),
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.45,
                                decoration: TextDecoration.underline,
                                decorationColor: accent.withValues(alpha: 0.4),
                                color: accent)),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 10),
        ],
        Text('국내 유가는 한국석유공사 오피넷 공식 데이터, 충전 요금은 앱에 등록된 운영사 요금 기준입니다.',
            style: TextStyle(fontSize: 10.5, height: 1.5, color: muted)),
      ],
    );
  }
}

/* ── 파싱 헬퍼 ── */

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String _comma(int v) => v
    .toString()
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

/// [{date:'20260730', price:1868.1}, ...] → [('20260730', 1868.1)]
/// 국제유가는 값 키가 'usd' 라 key 로 지정한다.
List<(String, double)> _series(dynamic raw, {String key = 'price'}) {
  if (raw is! List) return const [];
  final out = <(String, double)>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final p = _num(e[key]);
    if (p == null) continue;
    out.add(((e['date'] ?? '').toString(), p));
  }
  return out;
}

List<(String, double)> _sidoList(dynamic raw) {
  if (raw is! List) return const [];
  final out = <(String, double)>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final p = _num(e['price']);
    if (p == null) continue;
    out.add(((e['sido'] ?? '').toString(), p));
  }
  return out;
}

String _mmdd(String yyyymmdd) {
  final s = yyyymmdd.replaceAll('-', '');
  if (s.length < 8) return s;
  return '${int.parse(s.substring(4, 6))}/${int.parse(s.substring(6, 8))}';
}
