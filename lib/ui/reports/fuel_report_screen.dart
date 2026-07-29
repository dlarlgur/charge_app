import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/api_service.dart';

/// 유가 · 충전 리포트 — 주간 브리핑 / 월간 종합 목록.
/// 푸시로 받은 짧은 알림의 원문(섹션별 상세 분석)을 여기서 다시 볼 수 있다.
class FuelReportScreen extends StatefulWidget {
  const FuelReportScreen({super.key});

  @override
  State<FuelReportScreen> createState() => _FuelReportScreenState();
}

class _FuelReportScreenState extends State<FuelReportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _cache = <String, List<Map<String, dynamic>>>{};
  final _loading = <String, bool>{};
  final _error = <String, String?>{};

  static const _kinds = ['weekly', 'monthly'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) _load(_kinds[_tab.index]);
    });
    _load('weekly');
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load(String kind, {bool force = false}) async {
    if (!force && (_cache.containsKey(kind) || _loading[kind] == true)) return;
    setState(() {
      _loading[kind] = true;
      _error[kind] = null;
    });
    try {
      final list = await ApiService().getFuelReports(kind: kind);
      if (!mounted) return;
      setState(() {
        _cache[kind] = list;
        _loading[kind] = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading[kind] = false;
        _error[kind] = '리포트를 불러오지 못했어요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('유가 · 충전 리포트'),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.gasBlue,
          unselectedLabelColor:
              isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          indicatorColor: AppColors.gasBlue,
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          tabs: const [Tab(text: '주간'), Tab(text: '월간 종합')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_list('weekly', isDark), _list('monthly', isDark)],
      ),
    );
  }

  Widget _list(String kind, bool isDark) {
    if (_loading[kind] == true && !_cache.containsKey(kind)) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gasBlue));
    }
    final err = _error[kind];
    final items = _cache[kind] ?? const [];
    if (err != null && items.isEmpty) {
      return _empty(isDark, err, retry: () => _load(kind, force: true));
    }
    if (items.isEmpty) {
      return _empty(
        isDark,
        kind == 'weekly'
            ? '아직 발행된 주간 리포트가 없어요'
            : '아직 발행된 월간 종합 리포트가 없어요',
        sub: '매주 유가·충전 흐름을 정리해 알려드릴 예정이에요',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(kind, force: true),
      color: AppColors.gasBlue,
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
      padding: const EdgeInsets.fromLTRB(24, 90, 24, 24),
      children: [
        Icon(Icons.insights_rounded, size: 42, color: muted),
        const SizedBox(height: 14),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
        if (sub != null) ...[
          const SizedBox(height: 6),
          Text(sub,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: muted)),
        ],
        if (retry != null) ...[
          const SizedBox(height: 18),
          Center(
            child: OutlinedButton(onPressed: retry, child: const Text('다시 시도')),
          ),
        ],
      ],
    );
  }

  Widget _card(Map<String, dynamic> r, bool isDark) {
    final monthly = r['kind'] == 'monthly';
    final date = (r['date'] ?? '').toString();
    final label = monthly ? _fmtMonth(date) : _fmtDate(date);
    final title = (r['title'] ?? '').toString();
    final summary = (r['summary'] ?? '').toString();
    return Material(
      color: isDark ? AppColors.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          final id = r['id'];
          if (id is! num) return;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FuelReportDetailScreen(id: id.toInt()),
          ));
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 13, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isDark ? AppColors.darkCardBorder : const Color(0xFFEDEFF3),
                width: 0.8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: monthly
                                ? AppColors.gasBlue.withValues(alpha: 0.12)
                                : (isDark ? const Color(0x14FFFFFF) : const Color(0xFFF1F3F6)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(monthly ? '월간' : '주간',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: monthly
                                      ? AppColors.gasBlue
                                      : (isDark
                                          ? AppColors.darkTextMuted
                                          : AppColors.lightTextMuted))),
                        ),
                        const SizedBox(width: 7),
                        Text(label,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted)),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary)),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 20,
                  color: isDark ? AppColors.darkTextMuted : const Color(0xFFC5CBD4)),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmtDate(String iso) {
  try {
    final d = DateTime.parse(iso).toLocal();
    return DateFormat('yyyy년 M월 d일').format(d);
  } catch (_) {
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }
}

String _fmtMonth(String iso) {
  try {
    final d = DateTime.parse(iso).toLocal();
    return DateFormat('yyyy년 M월').format(d);
  } catch (_) {
    return iso.length >= 7 ? iso.substring(0, 7) : iso;
  }
}

/* ───────────────────────── 상세 ───────────────────────── */

const _sections = <(String, String, IconData)>[
  ('domestic', '국내 유가', Icons.local_gas_station_rounded),
  ('intl', '국제 유가', Icons.public_rounded),
  ('ev', '충전 요금', Icons.bolt_rounded),
  ('policy', '정책 · 제도', Icons.gavel_rounded),
  ('outlook', '전망 · 팁', Icons.tips_and_updates_rounded),
];

class FuelReportDetailScreen extends StatefulWidget {
  final int id;
  const FuelReportDetailScreen({super.key, required this.id});

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
      final r = await ApiService().getFuelReport(widget.id);
      if (!mounted) return;
      setState(() {
        _r = r;
        _loading = false;
        _error = r == null ? '리포트를 찾을 수 없어요' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '리포트를 불러오지 못했어요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = _r;
    return Scaffold(
      appBar: AppBar(title: const Text('리포트')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gasBlue))
          : (r == null
              ? Center(
                  child: Text(_error ?? '오류',
                      style: const TextStyle(fontSize: 14, color: Color(0xFF888888))))
              : _body(r, isDark)),
    );
  }

  Widget _body(Map<String, dynamic> r, bool isDark) {
    final monthly = r['kind'] == 'monthly';
    final detail = (r['detail'] is Map)
        ? Map<String, dynamic>.from(r['detail'] as Map)
        : const <String, dynamic>{};
    final facts = (r['facts'] is Map)
        ? Map<String, dynamic>.from(r['facts'] as Map)
        : const <String, dynamic>{};
    final sources = (r['sources'] is List) ? (r['sources'] as List) : const [];
    final filled = _sections
        .where((s) => ((detail[s.$1] ?? '') as String).trim().isNotEmpty)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
      children: [
        Text(
          monthly
              ? '${_fmtMonth((r['date'] ?? '').toString())} 종합'
              : _fmtDate((r['date'] ?? '').toString()),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
        ),
        const SizedBox(height: 6),
        Text((r['title'] ?? '').toString(),
            style: TextStyle(
                fontSize: 21,
                height: 1.3,
                fontWeight: FontWeight.w800,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)),
        if (((r['summary'] ?? '') as String).trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text((r['summary'] ?? '').toString(),
              style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary)),
        ],
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 16),
          _factsCard(facts, isDark),
        ],
        for (final s in filled) ...[
          const SizedBox(height: 22),
          _section(s.$2, s.$3, (detail[s.$1] as String).trim(), isDark),
        ],
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('참고자료',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
          const SizedBox(height: 8),
          for (final s in sources)
            if (s is Map)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '· ${(s['title'] ?? '').toString()}'
                  '${(s['source'] ?? '').toString().isNotEmpty ? ' (${s['source']})' : ''}',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary),
                ),
              ),
        ],
        const SizedBox(height: 20),
        Text('국내 유가는 한국석유공사 오피넷, 충전 요금은 운영사 공시 자료를 기준으로 작성했어요.',
            style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
      ],
    );
  }

  Widget _factsCard(Map<String, dynamic> f, bool isDark) {
    final won = NumberFormat('#,###');
    final rows = <(String, String)>[];
    final g = f['gasoline'];
    final d = f['diesel'];
    if (g is Map && g['price'] != null) {
      final diff = (g['diff'] as num?)?.toDouble() ?? 0;
      rows.add((
        '휘발유',
        '${won.format((g['price'] as num).round())}원/L'
            '${diff == 0 ? '' : (diff > 0 ? '  ▲${diff.abs().toStringAsFixed(2)}' : '  ▼${diff.abs().toStringAsFixed(2)}')}'
      ));
    }
    if (d is Map && d['price'] != null) {
      rows.add(('경유', '${won.format((d['price'] as num).round())}원/L'));
    }
    final evAvg = f['ev_fast_member_avg'];
    if (evAvg is num) {
      final lo = f['ev_fast_member_min'];
      final hi = f['ev_fast_member_max'];
      rows.add((
        '급속 회원가',
        '평균 ${won.format(evAvg.round())}원/kWh'
            '${(lo is num && hi is num) ? '  (${won.format(lo.round())}~${won.format(hi.round())})' : ''}'
      ));
    }
    final sido = f['sido'];
    if (sido is Map && sido['cheapest'] is List && (sido['cheapest'] as List).isNotEmpty) {
      final c = (sido['cheapest'] as List).first;
      if (c is Map) {
        rows.add((
          '최저 지역',
          '${c['sido']}  ${won.format(((c['price'] as num?) ?? 0).round())}원/L'
        ));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x14FFFFFF) : const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
            color: isDark ? AppColors.darkCardBorder : const Color(0xFFE8ECF2),
            width: 0.8),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            Row(
              children: [
                Text(rows[i].$1,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: isDark
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted)),
                const Spacer(),
                Flexible(
                  child: Text(rows[i].$2,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String label, IconData icon, String text, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.gasBlue),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary)),
          ],
        ),
        const SizedBox(height: 8),
        Text(text,
            style: TextStyle(
                fontSize: 14,
                height: 1.75,
                color:
                    isDark ? AppColors.darkTextSecondary : const Color(0xFF3B4653))),
      ],
    );
  }
}
