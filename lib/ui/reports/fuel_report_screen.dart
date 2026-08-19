import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/place_service.dart';
import '../../core/utils/navigation_util.dart';
import '../../providers/providers.dart';
import '../cheer/cheer_thanks_cta.dart';
import '../detail/gas_detail_screen.dart';
import '../favorites/place_picker_screen.dart';

/// 유가 · 충전 리포트 — 주간/월간 리포트 목록과 상세.
///
/// 리포트는 주제별로 따로 발행된다(유가 / 충전). 내 차종에 없는 주제는 탭 자체를
/// 만들지 않는다 — 주유만 쓰는 사용자에게 충전 요금을 보여줄 이유가 없다.
class FuelReportScreen extends ConsumerStatefulWidget {
  const FuelReportScreen({super.key, this.initialTopic});

  /// 진입 시 열어둘 탭 — 홈에서 '충전 리포트' 로 들어오면 충전 탭이 바로 보이게.
  /// 내 차종에 없는 주제면 무시된다.
  final String? initialTopic;

  @override
  ConsumerState<FuelReportScreen> createState() => _FuelReportScreenState();
}

class _FuelReportScreenState extends ConsumerState<FuelReportScreen>
    with TickerProviderStateMixin {
  TabController? _tab;
  List<String> _topics = const ['fuel'];

  final _cache = <String, List<Map<String, dynamic>>>{};
  Map<String, dynamic>? _today; // 일간 유가(수치만) 최신 1건 — 목록 최상단 카드
  Map<String, dynamic>? _todayEv; // 일간 충전(기사 정리) 최신 1건 — 수동 발행이라 없을 수 있다
  final _loading = <String, bool>{};
  final _error = <String, String?>{};

  // 우리 동네 유가 — 사용자가 '받기'를 눌러 생성하는 온디맨드 리포트 (형 확정).
  // 자동 로드하지 않는다: 집 미등록 → 등록 유도 카드 / 등록 + 미생성 → '받기' 카드 /
  // 생성됨 → 요약 카드(탭 → 상세 화면). 같은 날 결과는 Hive 에 캐시해 재진입 시 그대로.
  static const _kLocalBriefCache = 'local_fuel_brief_cache';
  Map<String, dynamic>? _local;
  bool _localLoading = false;
  String? _localError;

  // 레이아웃 2종(형 확정): hero(오늘 평균 히어로) | dash(유종 선택 + 7일 그래프).
  // 앱바 토글로 전환, Hive 저장. 유가 탭 전용 — 충전은 기존 목록 유지.
  static const _kLayoutPref = 'report_layout_style';
  String _layout = 'hero';
  // 일간 리포트 상세(facts) — 유종별 오늘값·7일 시계열. 히어로 타일·대시 그래프 재료.
  Map<String, dynamic>? _dailyFacts;
  String _dashFuel = 'B027';
  // 충전 히어로 재료 — 최신 주간 리포트 상세의 facts.ev (급속 평균·최저·최고·운영사).
  Map<String, dynamic>? _evFacts;
  String? _evFactsDate;
  String _evRate = 'fast'; // 충전 대시보드 기준 — 급속(fast) | 완속(slow)
  num? _prevEvAvg; // 전주 급속 회원가 평균 — 대시보드 등락 표기용

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
    final want = widget.initialTopic;
    final initial =
        (want != null && _topics.contains(want)) ? _topics.indexOf(want) : 0;
    _tab = TabController(
        length: _topics.length, initialIndex: initial, vsync: this);
    _tab!.addListener(() {
      if (_tab!.indexIsChanging) return;
      // 스와이프로 넘겨도 탭 강조색(유가=파랑/충전=초록)이 따라오게 리빌드
      if (mounted) setState(() {});
      _load(_topics[_tab!.index]);
    });
    _restoreLocalCache();
    final saved = Hive.box(AppConstants.settingsBox).get(_kLayoutPref);
    if (saved == 'dash' || saved == 'hero') _layout = saved as String;
    final f = ref.read(settingsProvider).fuelType.code;
    if (const ['B027', 'D047', 'B034', 'K015'].contains(f)) _dashFuel = f;
    _load(_topics[initial]);
  }

  @override
  void dispose() {
    _tab?.dispose();
    super.dispose();
  }

  Color _accent(String topic) =>
      topic == 'ev' ? AppColors.evGreen : AppColors.gasBlue;

  String _todayYmd() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  /// 오늘 생성해 둔 리포트가 있으면 복원 (날짜 지나면 무시 → 다시 '받기' 카드).
  void _restoreLocalCache() {
    try {
      final raw = Hive.box(AppConstants.settingsBox).get(_kLocalBriefCache);
      if (raw is! String || raw.isEmpty) return;
      final m = jsonDecode(raw);
      if (m is Map && m['date'] == _todayYmd() && m['data'] is Map) {
        final d = Map<String, dynamic>.from(m['data'] as Map);
        // 구형 캐시(전 유종 fuels 없던 응답)면 버린다 — 그대로 쓰면 선택 유종만
        // 나와서 "왜 고급휘발유만 나와" 상태가 하루 종일 유지된다(형 제보).
        if (d['fuels'] is List) _local = d;
      }
    } catch (_) {}
  }

  /// '우리 동네 유가 받기' — 집 좌표로 생성. 서버가 시군구 단위로 캐시하므로
  /// 같은 동네 사용자끼리 결과를 공유하고, 하루 제한은 앱 캐시(당일 1회 생성)로 충분.
  Future<void> _generateLocal() async {
    if (_localLoading) return;
    final home = PlaceService.get('home');
    final lat = (home?['lat'] as num?)?.toDouble();
    final lng = (home?['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return; // 미등록 — 버튼 자체가 등록 유도 카드
    setState(() {
      _localLoading = true;
      _localError = null;
    });
    try {
      final fuel = ref.read(settingsProvider).fuelType.code;
      final r =
          await ApiService().getLocalFuelBrief(lat: lat, lng: lng, fuel: fuel);
      if (!mounted) return;
      if (r == null) {
        setState(() {
          _localLoading = false;
          _localError = '동네 시세를 만들지 못했어요. 잠시 후 다시 시도해 주세요';
        });
        return;
      }
      await Hive.box(AppConstants.settingsBox)
          .put(_kLocalBriefCache, jsonEncode({'date': _todayYmd(), 'data': r}));
      if (!mounted) return;
      setState(() {
        _local = r;
        _localLoading = false;
      });
      // 생성 직후 바로 상세로 — '받기'를 눌렀다 = 내용을 보고 싶다.
      _openLocalDetail(r);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _localLoading = false;
        _localError = '동네 시세를 만들지 못했어요. 잠시 후 다시 시도해 주세요';
      });
    }
  }

  /// 집 등록 화면 열기 — 즐겨찾기 탭의 집 등록과 같은 플로우.
  Future<void> _registerHome() async {
    final picked = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const PlacePickerScreen(title: '집 등록')),
    );
    if (picked != null) {
      await PlaceService.set('home', picked);
      if (mounted) setState(() {});
    }
  }

  void _openLocalDetail(Map<String, dynamic> d) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LocalFuelBriefDetailScreen(data: d)));
  }

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
      // 일간은 목록에서 제외돼 오므로(도배 방지) 주제별로 따로 1건씩 받는다.
      //  · 유가: 매일 07시 자동 발행 — 거의 항상 있다
      //  · 충전: 콘솔에서 수동 발행 — 없을 수 있고, 그 경우 카드를 그리지 않는다
      Map<String, dynamic>? daily;
      final d = await ApiService()
          .getFuelReports(topic: topic, kind: 'daily', limit: 1);
      if (d.isNotEmpty) daily = d.first;
      if (!mounted) return;
      setState(() {
        _cache[topic] = list;
        if (topic == 'fuel') {
          if (daily != null) _today = daily;
        } else {
          _todayEv = daily; // null 이면 카드 없음 — 이전 값이 남지 않게 그대로 대입
        }
        _loading[topic] = false;
      });
      if (topic == 'fuel' && daily != null) _loadDailyFacts(daily);
      if (topic == 'ev' && list.isNotEmpty) _loadEvFacts(list.first);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading[topic] = false;
        _error[topic] = '리포트를 불러오지 못했어요';
      });
    }
  }

  /// 일간 리포트 상세의 facts(유종별 price/diff + week 시계열)를 받아온다.
  /// 실패해도 조용히 — 히어로/대시는 기존 오늘 카드로 폴백.
  Future<void> _loadDailyFacts(Map<String, dynamic> daily) async {
    if (_dailyFacts != null) return;
    final id = int.tryParse(daily['id']?.toString() ?? '');
    if (id == null) return;
    try {
      final r = await ApiService().getFuelReport(id);
      final facts = r?['facts'];
      if (!mounted || facts is! Map) return;
      setState(() => _dailyFacts = Map<String, dynamic>.from(facts));
    } catch (_) {}
  }

  /// 충전 히어로 재료 — 최신 주간 상세의 facts.ev. 실패 시 기존 큰 카드로 폴백.
  Future<void> _loadEvFacts(Map<String, dynamic> latest) async {
    if (_evFacts != null) return;
    final id = int.tryParse(latest['id']?.toString() ?? '');
    if (id == null) return;
    try {
      final r = await ApiService().getFuelReport(id);
      final facts = r?['facts'] is Map ? r!['facts'] as Map : null;
      final ev = facts?['ev'];
      if (!mounted || ev is! Map) return;
      setState(() {
        _evFacts = Map<String, dynamic>.from(ev);
        _evFactsDate = (latest['date'] ?? '').toString();
        _prevEvAvg = facts?['prev_ev_avg'] is num ? facts!['prev_ev_avg'] as num : null;
      });
    } catch (_) {}
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

    final rows = <Widget>[];
    if (topic == 'fuel') {
      // ── 유가: 기본/대시보드 2 레이아웃 — 토글은 목록 상단에 항상 보이게
      //   (앱바 구석 아이콘은 아무도 못 찾는다 — 형 지적) ──
      rows.add(_layoutSwitcher(isDark));
      if (_layout == 'dash') {
        rows.add(_fuelChips(isDark));
        final dash = _dashCard(isDark);
        if (dash != null) {
          rows.add(dash);
        } else if (_today != null) {
          rows.add(_todayCard(_today!, isDark)); // facts 아직이면 기존 오늘 카드
        }
      } else {
        final hero = _dailyFacts != null ? _heroToday(isDark) : null;
        if (hero != null) {
          rows.add(hero);
        } else if (_today != null) {
          rows.add(_todayCard(_today!, isDark));
        }
      }
      rows.add(_localCard(isDark));
      final t3 = _top3Card(isDark);
      if (t3 != null) rows.add(t3);
      if (items.isEmpty) {
        final muted =
            isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
          child: Text('주간 · 월간 분석 리포트는 매주 월요일에 올라와요',
              style: TextStyle(fontSize: 12.5, color: muted)),
        ));
      } else {
        // 히어로: 최신 큰 카드 + 지난 그룹 / 대시: 전부 슬림 그룹 (시안 4c)
        _appendGroups(rows, items, isDark, topic, firstBig: _layout != 'dash');
        rows.add(_archiveRow(isDark, topic));
      }
    } else {
      // ── 충전: 유가 히어로와 같은 문법의 초록 히어로 (형 요청 '충전도 이쁘게') ──
      // 일간 충전이 하나라도 있으면 주간이 없어도 화면은 비지 않는다.
      if (items.isEmpty && _todayEv == null) {
        return _empty(
          isDark,
          '아직 발행된 충전 리포트가 없어요',
          sub: '매주 충전 요금과 정책 흐름을 정리해 알려드려요',
        );
      }
      // 기본/대시보드 토글 — 유가와 같은 자리, 같은 동작(선택은 두 탭이 공유).
      rows.add(_layoutSwitcher(isDark, accent: AppColors.evGreen));
      // 일간(오늘) 카드를 최상단에 — 유가 탭과 같은 자리, 같은 문법.
      if (_todayEv != null) rows.add(_todayCard(_todayEv!, isDark, isEv: true));
      if (_layout == 'dash') {
        rows.add(_evChips(isDark));
        final dash = _evDashCard(isDark);
        // 대시 데이터가 아직이면 기본 히어로로 떨어뜨린다(빈 화면 방지).
        if (dash != null) {
          rows.add(dash);
        } else if (_evFacts != null && items.isNotEmpty) {
          rows.add(_evHero(isDark, items.first));
        }
        if (items.isNotEmpty) {
          _appendGroups(rows, items, isDark, topic, firstBig: false);
        }
      } else {
        final evHero = (_evFacts != null && items.isNotEmpty)
            ? _evHero(isDark, items.first)
            : null;
        if (evHero != null) {
          rows.add(evHero);
          _appendGroups(rows, items, isDark, topic, firstBig: false);
        } else if (items.isNotEmpty) {
          _appendGroups(rows, items, isDark, topic, firstBig: true);
        }
      }
      if (items.isNotEmpty) rows.add(_archiveRow(isDark, topic));
    }

    return RefreshIndicator(
      onRefresh: () => _load(topic, force: true),
      color: _accent(topic),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => rows[i],
      ),
    );
  }

  /// 최신 큰 카드(firstBig) + 월별 그룹 슬림 행 — 카드 반복 스캔 피로 해소(형 제보).
  void _appendGroups(List<Widget> rows, List<Map<String, dynamic>> items,
      bool isDark, String topic,
      {required bool firstBig}) {
    var rest = items;
    if (firstBig) {
      rows.add(_card(items.first, isDark));
      rest = items.skip(1).toList();
    }
    if (rest.isEmpty) return;
    String? cur;
    var group = <Map<String, dynamic>>[];
    void flush() {
      if (group.isNotEmpty) {
        rows.add(_monthGroup(cur ?? '', group, isDark, topic,
            headSuffix: firstBig ? '지난 리포트' : '리포트'));
      }
      group = [];
    }

    for (final r in rest) {
      final d = (r['date'] ?? '').toString();
      final m = d.length >= 7 ? d.substring(0, 7) : '';
      if (m != cur) {
        flush();
        cur = m;
      }
      group.add(Map<String, dynamic>.from(r));
    }
    flush();
  }

  /// 지난 리포트 전체보기 — 년도·월별 아카이브 (형 확정: 쌓이면 여기서).
  Widget _archiveRow(bool isDark, String topic) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    return Material(
      color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FuelReportArchiveScreen(topic: topic))),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isDark
                    ? AppColors.darkCardBorder
                    : AppColors.lightCardBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.history_rounded, size: 17, color: muted),
              const SizedBox(width: 9),
              Text('지난 리포트 전체보기',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary)),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, size: 19, color: muted),
            ],
          ),
        ),
      ),
    );
  }

  /// 지난 리포트 월 그룹 — 카드 하나 안에 [월 헤더 + 슬림 행들] (퀵메뉴 카드와 같은 문법).
  Widget _monthGroup(
      String month, List<Map<String, dynamic>> list, bool isDark, String topic,
      {String headSuffix = '지난 리포트'}) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final line = isDark ? AppColors.darkCardBorder : const Color(0xFFF0F3F6);
    String label = month;
    if (month.length >= 7) {
      final y = month.substring(0, 4);
      final m = int.tryParse(month.substring(5, 7)) ?? 0;
      label = y == DateTime.now().year.toString() ? '$m월' : '$y년 $m월';
    }
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: Text('$label $headSuffix',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: muted)),
          ),
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(height: 1, thickness: 1, color: line),
              ),
            _slimRow(list[i], isDark, topic),
          ],
        ],
      ),
    );
  }

  Widget _slimRow(Map<String, dynamic> r, bool isDark, String topic) {
    final accent = _accent((r['topic'] ?? topic).toString());
    final monthly = r['kind'] == 'monthly';
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final primary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    // 주차 배지 — "1주차". 월간은 "월간".
    String badge = monthly ? '월간' : '주간';
    final d = (r['date'] ?? '').toString();
    if (!monthly && d.length >= 10) {
      final dt = DateTime.tryParse(d.substring(0, 10));
      if (dt != null) badge = '${((dt.day - 1) ~/ 7) + 1}주차';
    }
    return InkWell(
      onTap: () {
        final id = int.tryParse(r['id']?.toString() ?? '');
        if (id == null) return;
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FuelReportDetailScreen(reportId: id)));
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            SizedBox(width: 44, child: _pill(badge, accent, isDark)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                (r['title'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: primary),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 18, color: muted),
          ],
        ),
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

  /// 오늘의 일간 리포트. 목록 최상단에서 한눈에 보이게 강조.
  /// 유가는 수치 요약, 충전은 최근 기사 정리 — 카드 문법은 같고 색만 주제를 따른다.
  Widget _todayCard(Map<String, dynamic> r, bool isDark, {bool isEv = false}) {
    final accent = isEv ? AppColors.evGreen : AppColors.gasBlue;
    final id = int.tryParse(r['id']?.toString() ?? '');
    return Material(
      color: isEv
          ? (isDark ? AppColors.darkEvActiveCard : AppColors.lightEvActiveCard)
          : (isDark ? AppColors.darkGasActiveCard : AppColors.lightGasActiveCard),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: id == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FuelReportDetailScreen(reportId: id))),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isEv
                    ? (isDark
                        ? AppColors.darkEvActiveBorder
                        : AppColors.lightEvActiveBorder)
                    : (isDark
                        ? AppColors.darkGasActiveBorder
                        : AppColors.lightGasActiveBorder)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _pill('오늘', accent, isDark),
                  const SizedBox(width: 6),
                  Text(_fmtDate(r['date']),
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
              const SizedBox(height: 8),
              Text((r['title'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                      letterSpacing: -0.3,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary)),
              if ((r['summary'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 5),
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

  /// 우리 동네 유가 — 3단 상태 카드 (형 확정: 온디맨드 생성).
  ///  ① 집 미등록: 등록 유도 (탭 → 집 등록 화면)
  ///  ② 집 등록 + 오늘 미생성: '오늘 시세 받기' 버튼 — 사용자가 직접 생성
  ///  ③ 생성됨: 요약 카드, 탭 → 상세 화면 (다른 리포트와 같은 패턴)
  Widget _localCard(bool isDark) {
    const accent = AppColors.gasBlue;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final primary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    Widget shell({required Widget child, VoidCallback? onTap}) => Material(
          color: isDark
              ? AppColors.darkGasActiveCard
              : AppColors.lightGasActiveCard,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 13, 14, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isDark
                        ? AppColors.darkGasActiveBorder
                        : AppColors.lightGasActiveBorder),
              ),
              child: child,
            ),
          ),
        );

    final home = PlaceService.get('home');

    // ① 집 미등록 — 등록으로 안내
    if (home == null) {
      return shell(
        onTap: _registerHome,
        child: Row(
          children: [
            const Icon(Icons.home_rounded, size: 30, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('집을 등록하면 우리 동네 유가를 알려드려요',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: primary)),
                  const SizedBox(height: 3),
                  Text('동네 평균가 · 전국 비교 · 집 근처 최저가 TOP3',
                      style: TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Text('집 등록',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: accent)),
            Icon(Icons.chevron_right_rounded, size: 20, color: muted),
          ],
        ),
      );
    }

    // ② 오늘 아직 안 만듦 — 받기 버튼
    if (_local == null) {
      final homeName = (home['name'] ?? '집').toString();
      return shell(
        onTap: _localLoading ? null : _generateLocal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _pill('우리 동네', const Color(0xFF14B8A6), isDark),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('$homeName 기준',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: muted)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('오늘의 우리 동네 유가 받기',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: primary)),
                      const SizedBox(height: 3),
                      Text('동네 평균가 · 전국 비교 · 집 근처 최저가 TOP3',
                          style: TextStyle(
                              fontSize: 12, height: 1.4, color: secondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _localLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: accent))
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Text('받기',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
              ],
            ),
            if (_localError != null) ...[
              const SizedBox(height: 7),
              Text(_localError!,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? AppColors.darkOrangeBright
                          : const Color(0xFFE07000))),
            ],
          ],
        ),
      );
    }

    // ③ 생성됨 — 요약 + 상세로
    final d = _local!;
    final region = (d['region'] as Map?) ?? const {};
    final price = (d['region_price'] as Map?) ?? const {};
    final cmp = (d['compare'] as Map?) ?? const {};
    final nearby = (d['nearby'] as Map?) ?? const {};
    final label = (region['label'] ?? '우리 동네').toString();
    final fuelLabel = (d['fuel_label'] ?? '휘발유').toString();
    final avg = (price['avg_won_per_liter'] as num?)?.round();
    final vsNation = (cmp['vs_nation_won'] as num?)?.toDouble();
    final stations = (nearby['stations'] as List?) ?? const [];
    final best =
        stations.isNotEmpty ? Map<String, dynamic>.from(stations.first) : null;

    return shell(
      onTap: () => _openLocalDetail(d),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _pill('우리 동네', const Color(0xFF14B8A6), isDark),
              const SizedBox(width: 6),
              Flexible(
                child: Text('$label · 집 기준',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: muted)),
              ),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, size: 20, color: muted),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                avg != null ? '$fuelLabel ${_comma(avg)}원' : '$fuelLabel 시세',
                style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: primary),
              ),
              const SizedBox(width: 8),
              if (vsNation != null)
                _localDeltaChip(vsNation, isDark, suffix: '원 (전국 대비)'),
            ],
          ),
          if (best != null) ...[
            const SizedBox(height: 6),
            Text(
              '집 근처 최저가 ${best['name']} ${_comma((best['price_won_per_liter'] as num).round())}원',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, height: 1.5, color: secondary),
            ),
          ],
          // 나머지 유종 요약 한 줄 (형 확정: 선택 유종만 → 전 유종). 상세엔 표로.
          if (_otherFuelsLine(d) != null) ...[
            const SizedBox(height: 5),
            Text(
              _otherFuelsLine(d)!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ],
        ],
      ),
    );
  }

  /// "고급 2,096 · 경유 1,742 · LPG 998" — 대표 유종을 뺀 나머지. 없으면 null.
  String? _otherFuelsLine(Map<String, dynamic> d) {
    final fuels = (d['fuels'] as List?) ?? const [];
    final primaryCode = (d['fuel_type'] ?? '').toString();
    final parts = <String>[];
    for (final raw in fuels) {
      if (raw is! Map) continue;
      if (raw['code'] == primaryCode) continue;
      final avg = (raw['avg_won_per_liter'] as num?)?.round();
      if (avg == null) continue;
      final label = (raw['label'] ?? '').toString().replaceAll('고급휘발유', '고급');
      parts.add('$label ${_comma(avg)}');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// 전국 대비 델타 — 상세화면 `_deltaChip` 과 같은 표기(▲빨강/▼초록).
  /// 그쪽은 다른 State 의 메서드라 재사용할 수 없어 목록용으로 따로 둔다.
  Widget _localDeltaChip(double v, bool isDark, {String suffix = ''}) {
    final flat = v.abs() < 0.5;
    final up = v > 0;
    final c = flat
        ? (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)
        : (up ? const Color(0xFFEF4444) : AppColors.evGreen);
    final txt = flat
        ? '전국 평균과 비슷'
        : '${up ? '▲' : '▼'} ${_comma(v.abs().round())}$suffix';
    return Flexible(
      child: Text(txt,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
    );
  }

  static const _fuelCodes = ['B027', 'D047', 'B034', 'K015'];
  static const _fuelChipLabel = {
    'B027': '휘발유',
    'D047': '경유',
    'B034': '고급',
    'K015': 'LPG',
  };
  static const _factsKey = {
    'B027': 'gasoline',
    'D047': 'diesel',
    'B034': 'premium',
    'K015': 'lpg',
  };

  void _openDailyDetail() {
    final id = int.tryParse(_today?['id']?.toString() ?? '');
    if (id == null) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FuelReportDetailScreen(reportId: id)));
  }

  /// 충전 히어로 — 이번 주 급속 회원가 평균 큰 숫자 + 최저/최고/운영사 타일 (형 요청).
  Widget _evHero(bool isDark, Map<String, dynamic> latest) {
    const accent = AppColors.evGreen;
    final f = _evFacts!;
    final avg = (f['avg'] as num?)?.round();
    if (avg == null) return _card(latest, isDark);
    final minV = (f['min'] as num?)?.round();
    final maxV = (f['max'] as num?)?.round();
    final ops = (f['operators'] as List?)?.length;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final primary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    Widget tile(String label, String? value) {
      if (value == null) return const SizedBox.shrink();
      return Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 7),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Column(
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: muted)),
              const SizedBox(height: 3),
              Text(value,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: primary)),
            ],
          ),
        ),
      );
    }

    return Material(
      color: isDark ? AppColors.darkEvActiveCard : AppColors.lightEvActiveCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          final id = int.tryParse(latest['id']?.toString() ?? '');
          if (id == null) return;
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FuelReportDetailScreen(reportId: id)));
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isDark
                    ? AppColors.darkEvActiveBorder
                    : AppColors.lightEvActiveBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 주간 리포트는 '지난 7일' 분석 — '이번 주' 라고 쓰면 아직 안 온
                  // 이번 주를 분석한 걸로 읽힌다(형 지적).
                  _pill('지난주', accent, isDark),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                        _weeklyPeriod(_evFactsDate ?? latest['date']) ??
                            _fmtDate(latest['date']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: muted)),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded, size: 20, color: muted),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('급속 평균',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: muted)),
                  const SizedBox(width: 8),
                  Text(_comma(avg),
                      style: TextStyle(
                          fontSize: 33,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          height: 1,
                          color: primary)),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('원/kWh · 회원가',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: muted)),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  tile('최저', minV != null ? '${_comma(minV)}원' : null),
                  tile('최고', maxV != null ? '${_comma(maxV)}원' : null),
                  tile('운영사', ops != null ? '$ops곳' : null),
                ],
              ),
              const SizedBox(height: 8),
              // 제목 한 줄 — 히어로가 최신 주간 카드를 대체하므로 무슨 리포트인지 보이게
              Text((latest['title'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  /// 충전 대시보드 — 급속/완속 칩. 유가 유종 칩과 같은 문법.
  Widget _evChips(bool isDark) {
    const accent = AppColors.evGreen;
    Widget chip(String key, String label) {
      final on = _evRate == key;
      return Padding(
        padding: const EdgeInsets.only(right: 7),
        child: GestureDetector(
          onTap: () {
            if (_evRate == key) return;
            setState(() => _evRate = key);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: on
                  ? accent.withValues(alpha: isDark ? 0.18 : 0.12)
                  : (isDark ? AppColors.darkSurface1 : AppColors.lightCard),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: on
                      ? accent.withValues(alpha: 0.5)
                      : (isDark
                          ? AppColors.darkCardBorder
                          : AppColors.lightCardBorder)),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                    color: on
                        ? accent
                        : (isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary))),
          ),
        ),
      );
    }

    // 좁은 화면·큰 시스템 글씨에서도 넘치지 않게 가로 스크롤 (유가 칩과 동일)
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [chip('fast', '급속'), chip('slow', '완속')]),
    );
  }

  /// 충전 대시보드 카드 — 선택한 기준의 평균/최저/최고 + 운영사 요금 순위.
  /// facts.ev 의 avg/min/max 는 '급속 회원가' 기준이라, 완속은 운영사 값에서 직접 계산한다.
  Widget? _evDashCard(bool isDark) {
    final f = _evFacts;
    if (f == null) return null;
    final ops = (f['operators'] as List?) ?? const [];
    final isFast = _evRate == 'fast';
    final key = isFast ? 'fast' : 'slow';
    final vals = ops
        .map((o) => (o is Map ? o[key] : null))
        .whereType<num>()
        .map((v) => v.toDouble())
        .toList();
    if (vals.isEmpty) return null;

    final avg = isFast && f['avg'] is num
        ? (f['avg'] as num).toDouble()
        : vals.reduce((a, b) => a + b) / vals.length;
    final minV = isFast && f['min'] is num
        ? (f['min'] as num).toDouble()
        : vals.reduce((a, b) => a < b ? a : b);
    final maxV = isFast && f['max'] is num
        ? (f['max'] as num).toDouble()
        : vals.reduce((a, b) => a > b ? a : b);
    // 전주 대비는 서버가 급속 회원가만 준다 — 완속에는 붙이지 않는다(없는 비교를 만들지 않기).
    final prev = isFast && _prevEvAvg is num ? (_prevEvAvg as num).toDouble() : null;
    final diff = prev == null ? null : avg - prev;

    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final ink =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    // 요금 오름차순 — 싼 곳이 위로. 완속 기준일 땐 완속으로 다시 정렬한다.
    final sorted = ops.whereType<Map>().where((o) => o[key] is num).toList()
      ..sort((a, b) => (a[key] as num).compareTo(b[key] as num));

    Widget tile(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: muted)),
              const SizedBox(height: 2),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: ink)),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkEvActiveCard : AppColors.lightEvActiveCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark
                ? AppColors.darkEvActiveBorder
                : AppColors.lightEvActiveBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${isFast ? '급속' : '완속'} 평균',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: muted)),
              const SizedBox(width: 8),
              Text(_comma(avg.round()),
                  style: const TextStyle(
                      fontSize: 33,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      height: 1,
                      color: AppColors.evGreen)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('원/kWh · 회원가',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: muted)),
              ),
            ],
          ),
          if (diff != null && diff.abs() >= 0.5) ...[
            const SizedBox(height: 4),
            Text(
                '지난주보다 ${_comma(diff.abs().round())}원 ${diff > 0 ? '올랐어요' : '내렸어요'}',
                style: TextStyle(fontSize: 11.5, color: muted)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            tile('최저', '${_comma(minV.round())}원'),
            tile('최고', '${_comma(maxV.round())}원'),
            tile('운영사', '${sorted.length}곳'),
          ]),
          const SizedBox(height: 4),
          Divider(
              height: 18,
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.07)),
          Text('운영사별 ${isFast ? '급속' : '완속'} 요금',
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: muted)),
          const SizedBox(height: 8),
          for (final o in sorted)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text((o['name'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: ink)),
                  ),
                  if (o['stations'] is num) ...[
                    Text('${_comma((o['stations'] as num).round())}곳',
                        style: TextStyle(fontSize: 11, color: muted)),
                    const SizedBox(width: 10),
                  ],
                  Text('${_comma((o[key] as num).round())}원',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.evGreen)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 4a 히어로 — 오늘 전국 평균이 주인공. 큰 휘발유값 + 등락 + 유종 타일 3개 (형 시안).
  Widget _heroToday(bool isDark) {
    const accent = AppColors.gasBlue;
    final f = _dailyFacts!;
    final g = f['gasoline'] is Map ? f['gasoline'] as Map : null;
    if (g == null || (g['price'] as num?) == null) {
      return _todayCard(_today ?? {}, isDark);
    }
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final primary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    Widget tile(String label, dynamic v) {
      final price = (v is Map ? v['price'] as num? : null)?.round();
      if (price == null) return const SizedBox.shrink();
      return Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 7),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Column(
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: muted)),
              const SizedBox(height: 3),
              Text('${_comma(price)}원',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: primary)),
            ],
          ),
        ),
      );
    }

    return Material(
      color:
          isDark ? AppColors.darkGasActiveCard : AppColors.lightGasActiveCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openDailyDetail,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isDark
                    ? AppColors.darkGasActiveBorder
                    : AppColors.lightGasActiveBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _pill('오늘', accent, isDark),
                  const SizedBox(width: 6),
                  Text('${_fmtDate(_today?['date'])} · 전국 평균',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: muted)),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded, size: 20, color: muted),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('휘발유',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: muted)),
                  const SizedBox(width: 8),
                  Text(_comma((g['price'] as num).round()),
                      style: TextStyle(
                          fontSize: 33,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          height: 1,
                          color: primary)),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('원/L',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: muted)),
                  ),
                  const Spacer(),
                  _localDeltaChip(((g['diff'] as num?) ?? 0).toDouble(), isDark,
                      suffix: '원'),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  tile('경유', f['diesel']),
                  tile('고급휘발유', f['premium']),
                  tile('LPG', f['lpg']),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 보기 방식 세그먼트 — 기본(요약 카드) | 대시보드(유종·그래프). Hive 저장.
  /// 기본/대시보드 토글 — 유가·충전 공용. 색만 주제를 따른다.
  Widget _layoutSwitcher(bool isDark, {Color accent = AppColors.gasBlue}) {
    Widget seg(String key, IconData icon, String label) {
      final on = _layout == key;
      return GestureDetector(
        onTap: () {
          if (_layout == key) return;
          setState(() => _layout = key);
          Hive.box(AppConstants.settingsBox).put(_kLayoutPref, key);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: on
                ? (isDark ? AppColors.darkSurface2 : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: on && !isDark
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 5,
                        offset: const Offset(0, 1)),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: on
                      ? accent
                      : (isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted)),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                      color: on
                          ? (isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary)
                          : (isDark
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted))),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFEDF1F5),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              seg('hero', Icons.view_agenda_rounded, '기본'),
              seg('dash', Icons.insert_chart_rounded, '대시보드'),
            ],
          ),
        ),
      ],
    );
  }

  /// 4c 대시보드 — 유종 칩. 목록 최상단.
  Widget _fuelChips(bool isDark) {
    const accent = AppColors.gasBlue;
    // 좁은 화면·큰 시스템 글씨에서 4칩이 넘칠 수 있어 가로 스크롤 허용
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in _fuelCodes)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _dashFuel = c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    color: _dashFuel == c
                        ? accent
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.white),
                    borderRadius: BorderRadius.circular(99),
                    border: _dashFuel == c
                        ? null
                        : Border.all(
                            color: isDark
                                ? AppColors.darkCardBorder
                                : AppColors.lightCardBorder),
                  ),
                  child: Text(
                    _fuelChipLabel[c]!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: _dashFuel == c
                          ? Colors.white
                          : (isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 4c 대시보드 — 선택 유종 큰 숫자 + 등락 + 7일 추이 미니 바. facts 없으면 null.
  Widget? _dashCard(bool isDark) {
    final f = _dailyFacts;
    if (f == null) return null;
    final key = _factsKey[_dashFuel] ?? 'gasoline';
    final v = f[key];
    final price = (v is Map ? v['price'] as num? : null);
    if (price == null) return null;
    final diff = ((v as Map)['diff'] as num?)?.toDouble() ?? 0;
    const accent = AppColors.gasBlue;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final primary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    // 7일 시계열 — facts.week[key] = [{date, price}...] (과거→최신)
    final weekRaw = f['week'] is Map ? (f['week'] as Map)[key] : null;
    final series = <({String d, double p})>[];
    if (weekRaw is List) {
      for (final e in weekRaw) {
        if (e is! Map) continue;
        final pp = (e['price'] as num?)?.toDouble();
        if (pp == null) continue;
        series.add((d: (e['date'] ?? '').toString(), p: pp));
      }
    }
    final pts = series.length > 7 ? series.sublist(series.length - 7) : series;
    double minP = double.infinity, maxP = -double.infinity;
    for (final e in pts) {
      if (e.p < minP) minP = e.p;
      if (e.p > maxP) maxP = e.p;
    }
    final span = (maxP - minP).abs() < 0.01 ? 1.0 : (maxP - minP);
    String dayLabel(String d) {
      final t = d.replaceAll('-', '');
      if (t.length < 8) return d;
      return '${int.parse(t.substring(4, 6))}.${int.parse(t.substring(6, 8))}';
    }

    return Material(
      color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openDailyDetail,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 14, 14),
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
                  Text('전국 평균 · ${_fmtDate(_today?['date'])}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: muted)),
                  const Spacer(),
                  _localDeltaChip(diff, isDark, suffix: '원'),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_comma(price.round()),
                      style: TextStyle(
                          fontSize: 33,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          height: 1,
                          color: primary)),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('원/L',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: muted)),
                  ),
                ],
              ),
              if (pts.length >= 2) ...[
                const SizedBox(height: 13),
                SizedBox(
                  // 84 = 최대 막대 54 + 간격 4 + 라벨 ~14 + 큰 글씨 여유 (74 는 1px 오버플로우)
                  height: 84,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < pts.length; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  height: 24 + ((pts[i].p - minP) / span) * 30,
                                  decoration: BoxDecoration(
                                    color: i == pts.length - 1
                                        ? accent
                                        : accent.withValues(
                                            alpha: isDark ? 0.32 : 0.18),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  i == pts.length - 1
                                      ? '오늘'
                                      : dayLabel(pts[i].d),
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: i == pts.length - 1
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: i == pts.length - 1 ? accent : muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 내 주변 최저가 TOP3 — 동네 유가를 '받은' 뒤에만 (형 확정: 두 레이아웃 공통).
  Widget? _top3Card(bool isDark) {
    final d = _local;
    if (d == null) return null;
    final nearby = (d['nearby'] as Map?) ?? const {};
    final stations = (nearby['stations'] as List?) ?? const [];
    if (stations.isEmpty) return null;
    const accent = AppColors.gasBlue;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final primary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final line = isDark ? AppColors.darkCardBorder : const Color(0xFFF0F3F6);
    final radiusKm = ((nearby['radius_m'] as num?) ?? 5000) / 1000;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _openLocalDetail(d),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
              child: Row(
                children: [
                  _pill('내 주변', accent, isDark),
                  const SizedBox(width: 6),
                  Text('최저가 TOP3 · ${radiusKm.toStringAsFixed(0)}km',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: muted)),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded, size: 19, color: muted),
                ],
              ),
            ),
          ),
          for (var i = 0; i < stations.length && i < 3; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(height: 1, thickness: 1, color: line),
              ),
            Builder(builder: (ctx) {
              final st = Map<String, dynamic>.from(stations[i] as Map);
              final dist = (st['distance_m'] as num?)?.toDouble();
              final top = i == 0;
              final stId = (st['id'] ?? '').toString();
              return InkWell(
                onTap: stId.isEmpty
                    ? null
                    : () => Navigator.of(ctx).push(MaterialPageRoute(
                        builder: (_) => GasDetailScreen(stationId: stId))),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
                  child: Row(
                    children: [
                      Container(
                        width: 21,
                        height: 21,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: top ? accent : muted.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: top ? Colors.white : muted)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text((st['name'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                color: primary)),
                      ),
                      const SizedBox(width: 8),
                      if (dist != null)
                        Text('${(dist / 1000).toStringAsFixed(1)}km',
                            style: TextStyle(fontSize: 11.5, color: muted)),
                      const SizedBox(width: 9),
                      Text(
                          '${_comma((st['price_won_per_liter'] as num).round())}원',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: top
                                  ? accent
                                  : (isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.lightTextSecondary))),
                    ],
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 4),
        ],
      ),
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
                  _pill(monthly ? '월간 종합' : '주간',
                      _kindColor(monthly ? 'monthly' : 'weekly', accent), isDark),
                  const SizedBox(width: 6),
                  Text(!monthly ? (_weeklyPeriod(r['date']) ?? date) : date,
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

/// 리포트 종류 배지 색 — 주간·월간이 본문 파랑(액션 색)과 섞여 안 보이던 문제.
/// 주간=바이올렛, 월간=앰버. 종류가 색으로 먼저 읽히게 한다.
Color _kindColor(String kind, Color fallback) => switch (kind) {
      'weekly' => const Color(0xFF8B5CF6),
      'monthly' => const Color(0xFFF59E0B),
      _ => fallback,
    };

/// 주간 리포트 기간 라벨 — "8월 1주차 · 7.28 ~ 8.3".
/// brief_date(생성일)가 끝날이고, 데이터 창은 그날 포함 최근 7일이다.
String? _weeklyPeriod(dynamic raw) {
  final t = (raw ?? '').toString();
  if (t.length < 10) return null;
  final end = DateTime.tryParse(t.substring(0, 10));
  if (end == null) return null;
  final start = end.subtract(const Duration(days: 6));
  final week = ((end.day - 1) ~/ 7) + 1;
  String md(DateTime x) => '${x.month}.${x.day}';
  return '${end.month}월 $week주차 · ${md(start)} ~ ${md(end)}';
}

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
    final kind = (r?['kind'] ?? 'weekly').toString();
    final monthly = kind == 'monthly';
    final kindLabel = switch (kind) {
      'monthly' => '월간 종합',
      'daily' => '오늘',
      _ => '주간',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(topic == 'ev' ? '충전 리포트' : '유가 리포트'),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: accent))
          : (r == null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                  ),
                ))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
                  children: [
                    Row(
                      children: [
                        _pill(kindLabel, _kindColor(kind, accent), isDark),
                        const SizedBox(width: 6),
                        Text(
                            kind == 'weekly'
                                ? (_weeklyPeriod(r['date']) ??
                                    _fmtDate(r['date']))
                                : _fmtDate(r['date'], monthly: monthly),
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
                      ..._fuelVisuals(r['facts'], isDark,
                          kind: (r['kind'] ?? 'weekly').toString()),

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

                    // 다 읽은 직후 — 응원하기는 설정 탭 안에 있어 존재를 모르는
                    // 사용자가 많다. 리포트는 푸시로 도달하는 화면이라 노출이 공짜다.
                    const SizedBox(height: 4),
                    const CheerThanksCta(),
                  ],
                )),
    );
  }

  /* ── 유가: 오늘 가격 + 7일 추이 + 시도별 ── */

  List<Widget> _fuelVisuals(dynamic factsRaw, bool isDark,
      {String kind = 'weekly'}) {
    final f = factsRaw is Map ? factsRaw : const {};
    final g = f['gasoline'] is Map ? f['gasoline'] as Map : null;
    final d = f['diesel'] is Map ? f['diesel'] as Map : null;
    final week = f['week'] is Map ? f['week'] as Map : null;
    final sido = f['sido'] is Map ? f['sido'] as Map : null;
    final out = <Widget>[];

    // 유종 4종 — 한 줄에 4개면 작은 화면에서 넘치므로 2×2 로 (휘발유·경유 / 고급·LPG)
    final prem = f['premium'] is Map ? f['premium'] as Map : null;
    final lpg = f['lpg'] is Map ? f['lpg'] as Map : null;
    // 비교 기준은 리포트 종류를 따른다 — 주간 리포트에 '어제 대비'가 붙으면
    // 일간과 구분이 안 되고 틀린 정보가 된다(형 지적).
    //  · weekly: 서버 계산 week_change(지난주 대비). 없으면(구 리포트) 7일 시계열
    //    첫/끝으로 직접 계산, 그것도 없으면 칩 숨김.
    //  · monthly: 월 대비 수치가 없으므로 칩 숨김(한 달 흐름은 본문이 서술).
    //  · daily 상세는 이 화면을 안 탄다(오늘의 유가 카드가 '어제 대비'로 따로 그림).
    final wc = f['week_change'] is Map ? f['week_change'] as Map : null;
    num? periodDiff(String key, Map? cell) {
      if (kind == 'monthly') return null;
      final w = wc?[key];
      if (w is Map && w['change'] is num) return w['change'] as num;
      final series = week?[key];
      if (series is List && series.length >= 2) {
        final first = (series.first as Map?)?['price'];
        final last = (series.last as Map?)?['price'];
        if (first is num && last is num) return last - first;
      }
      return null;
    }

    final suffix = kind == 'weekly' ? '원 (지난주 대비)' : '원 (어제 대비)';
    final cells = <(String, Map, Color, num?)>[
      if (g != null) ('휘발유', g, AppColors.gasBlue, periodDiff('gasoline', g)),
      if (d != null) ('경유', d, const Color(0xFF8B5CF6), periodDiff('diesel', d)),
      if (prem != null)
        ('고급휘발유', prem, const Color(0xFFEF4444), periodDiff('premium', prem)),
      if (lpg != null)
        ('LPG', lpg, const Color(0xFF0EA5E9), periodDiff('lpg', lpg)),
    ];
    if (cells.isNotEmpty) {
      final divider =
          isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;
      final rows = <Widget>[];
      for (var i = 0; i < cells.length; i += 2) {
        final pair = cells.skip(i).take(2).toList();
        if (i > 0) {
          rows.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(height: 1, color: divider),
          ));
        }
        rows.add(Row(
          children: [
            Expanded(
                child: _priceCell(pair[0].$1, pair[0].$2['price'], pair[0].$4,
                    pair[0].$3, isDark,
                    suffix: suffix)),
            if (pair.length > 1)
              Container(width: 1, height: 46, color: divider),
            if (pair.length > 1)
              Expanded(
                  child: _priceCell(pair[1].$1, pair[1].$2['price'],
                      pair[1].$4, pair[1].$3, isDark,
                      suffix: suffix)),
            if (pair.length == 1) const Expanded(child: SizedBox()),
          ],
        ));
      }
      out.add(_panel(isDark: isDark, child: Column(children: rows)));
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
      String label, dynamic price, dynamic diff, Color color, bool isDark,
      {String suffix = '원 (어제 대비)'}) {
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
          _deltaChip(dv, isDark, suffix: suffix),
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
          // 서버가 2~3문장씩 문단을 나눠 보내므로 빈 줄 기준으로 간격을 준다
          for (final para in body
              .split(RegExp(r'\n\s*\n'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)) ...[
            Text(para,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.75,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary)),
            const SizedBox(height: 11),
          ],
        ],
      ),
    );
  }

  /// 참고자료 한 줄 — 매체 파비콘 + 제목 2줄 + 매체·날짜.
  /// (밑줄 텍스트만 나열하면 빈약해 보여서 카드로)
  Widget _refCard(Map s, bool isDark, Color accent) {
    final url = (s['link'] ?? '').toString();
    final host = Uri.tryParse((s['source_url'] ?? '').toString())?.host ?? '';
    final favicon = host.isEmpty
        ? null
        : 'https://www.google.com/s2/favicons?sz=64&domain=$host';
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (url.startsWith('http')) {
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            }
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isDark
                      ? AppColors.darkCardBorder
                      : AppColors.lightCardBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: favicon == null
                        ? _refFallback(accent, isDark)
                        : Image.network(favicon,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _refFallback(accent, isDark)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 3줄 — 언론사 헤드라인은 40자대가 흔한데 2줄이면 폰트배율 1.2에서
                      // 30자쯤에서 잘려나간다(형 제보). 제목이 잘리면 링크를 누를지 말지
                      // 판단할 근거 자체가 사라지므로 한 줄 더 준다. 유가·충전 공용 위젯.
                      Text((s['title'] ?? '').toString(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary)),
                      const SizedBox(height: 3),
                      Text(
                          [
                            (s['source'] ?? '').toString(),
                            if ((s['date'] ?? '').toString().length >= 10)
                              (s['date'] as String)
                                  .substring(5)
                                  .replaceAll('-', '.'),
                          ].where((e) => e.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.open_in_new_rounded, size: 14, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _refFallback(Color accent, bool isDark) => Container(
        color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
        child: Icon(Icons.article_rounded, size: 15, color: accent),
      );

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
            if (s is Map) _refCard(s, isDark, accent),
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

/* ══════════════════════════ 우리 동네 유가 상세 ══════════════════════════ */

/// 우리 동네 유가 상세 — 다른 리포트 상세와 같은 패턴(전용 화면).
/// 데이터는 목록에서 생성한 것을 그대로 받는다(재조회 없음 — 당일 캐시와 일치 보장).
class LocalFuelBriefDetailScreen extends StatelessWidget {
  const LocalFuelBriefDetailScreen({super.key, required this.data});

  final Map<String, dynamic> data;

  String _fmtYmd(dynamic raw) {
    final s = (raw ?? '').toString();
    if (s.length != 8) return s;
    return '${s.substring(0, 4)}.${s.substring(4, 6)}.${s.substring(6, 8)}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = AppColors.gasBlue;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final primary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final cardBorder =
        isDark ? AppColors.darkCardBorder : const Color(0xFFE8ECF0);

    final region = (data['region'] as Map?) ?? const {};
    final price = (data['region_price'] as Map?) ?? const {};
    final cmp = (data['compare'] as Map?) ?? const {};
    final nearby = (data['nearby'] as Map?) ?? const {};
    final label = (region['label'] ?? '우리 동네').toString();
    final sidoLabel = (region['sido_label'] ?? '').toString();
    final fuelLabel = (data['fuel_label'] ?? '휘발유').toString();
    final narrative = (data['narrative'] ?? '').toString().trim();
    final avg = (price['avg_won_per_liter'] as num?)?.round();
    final count = (price['station_count'] as num?)?.round();
    final minName = (price['min_station_name'] ?? '').toString();
    final minPrice = (price['min_won_per_liter'] as num?)?.round();
    final sidoAvg = (cmp['sido_avg_won_per_liter'] as num?)?.round();
    final nationAvg = (cmp['nation_avg_won_per_liter'] as num?)?.round();
    final vsNation = (cmp['vs_nation_won'] as num?)?.round();
    final stations = (nearby['stations'] as List?) ?? const [];
    final radiusKm = ((nearby['radius_m'] as num?) ?? 5000) / 1000;
    final saveWon = (nearby['save_vs_region_won'] as num?)?.round();

    Widget sectionCard(Widget child) => Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cardBorder, width: 0.8),
          ),
          child: child,
        );

    Widget sectionHead(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(icon, size: 15, color: accent),
              const SizedBox(width: 6),
              Text(text,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: primary)),
            ],
          ),
        );

    Widget avgRow(String name, int? value, {bool highlight = false}) {
      if (value == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(name,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: highlight ? FontWeight.w800 : FontWeight.w500,
                    color: highlight ? primary : muted)),
            Text('${_comma(value)}원',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                    color: highlight ? accent : secondary)),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('우리 동네 유가')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
        children: [
          // ── 헤더 ──
          Row(
            children: [
              _pill('우리 동네', const Color(0xFF14B8A6), isDark),
              const SizedBox(width: 7),
              Text(_fmtYmd(data['stats_date']),
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: muted)),
            ],
          ),
          const SizedBox(height: 9),
          Text('$label $fuelLabel 시세',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.3,
                  color: primary)),
          const SizedBox(height: 4),
          Text('등록한 집 주변 · 주유소 ${count ?? '-'}곳 집계',
              style: TextStyle(fontSize: 12.5, color: muted)),
          const SizedBox(height: 16),

          // ── 평균가 히어로 ──
          sectionCard(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(avg != null ? _comma(avg) : '-',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          height: 1,
                          color: primary)),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('원/L',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: muted)),
                  ),
                  const Spacer(),
                  if (vsNation != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: (vsNation > 0
                                ? const Color(0xFFEF4444)
                                : AppColors.evGreen)
                            .withValues(alpha: isDark ? 0.18 : 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        vsNation == 0
                            ? '전국 평균 수준'
                            : '전국보다 ${_comma(vsNation.abs())}원 ${vsNation > 0 ? '비쌈' : '저렴'}',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: vsNation > 0
                                ? const Color(0xFFEF4444)
                                : AppColors.evGreen),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: cardBorder),
              avgRow('$label 평균', avg, highlight: true),
              if (sidoLabel.isNotEmpty) avgRow('$sidoLabel 평균', sidoAvg),
              avgRow('전국 평균', nationAvg),
            ],
          )),

          // ── 유종별 동네 평균 (형 확정: 휘발유·고급·경유·LPG 전부) ──
          if (((data['fuels'] as List?) ?? const []).length > 1)
            sectionCard(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionHead(
                    Icons.format_list_bulleted_rounded, '유종별 $label 평균'),
                for (final raw in (data['fuels'] as List))
                  if (raw is Map)
                    Builder(builder: (_) {
                      final f = Map<String, dynamic>.from(raw);
                      final fAvg = (f['avg_won_per_liter'] as num?)?.round();
                      final fVs = (f['vs_nation_won'] as num?)?.round();
                      final isPrimary = f['code'] == data['fuel_type'];
                      if (fAvg == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Text((f['label'] ?? '').toString(),
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: isPrimary
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: isPrimary ? primary : muted)),
                            if (isPrimary) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: accent.withValues(
                                      alpha: isDark ? 0.2 : 0.1),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Text('내 유종',
                                    style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: accent)),
                              ),
                            ],
                            const Spacer(),
                            if (fVs != null && fVs != 0) ...[
                              Text(
                                '전국 ${fVs > 0 ? '+' : '−'}${_comma(fVs.abs())}',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: fVs > 0
                                        ? const Color(0xFFEF4444)
                                        : AppColors.evGreen),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Text('${_comma(fAvg)}원',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isPrimary
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isPrimary ? primary : secondary)),
                          ],
                        ),
                      );
                    }),
              ],
            )),

          // ── AI 서술 ──
          if (narrative.isNotEmpty)
            sectionCard(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionHead(Icons.auto_awesome_rounded, '오늘의 동네 시세 읽기'),
                MarkdownBody(
                  data: narrative,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(fontSize: 13.5, height: 1.7, color: secondary),
                    strong: TextStyle(
                        fontSize: 13.5,
                        height: 1.7,
                        fontWeight: FontWeight.w800,
                        color: primary),
                  ),
                ),
              ],
            )),

          // ── 집 근처 최저가 TOP3 ──
          sectionCard(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionHead(Icons.local_gas_station_rounded,
                  '집 근처 ${radiusKm.toStringAsFixed(0)}km 최저가'),
              if (stations.isEmpty)
                Text('주변에서 판매 중인 주유소를 찾지 못했어요',
                    style: TextStyle(fontSize: 12.5, color: muted))
              else
                for (var i = 0; i < stations.length; i++)
                  Builder(builder: (ctx) {
                    final st = Map<String, dynamic>.from(stations[i] as Map);
                    final dist = (st['distance_m'] as num?)?.toDouble();
                    final top = i == 0;
                    final stId = (st['id'] ?? '').toString();
                    final stLat = (st['lat'] as num?)?.toDouble();
                    final stLng = (st['lng'] as num?)?.toDouble();
                    return _NearRow(
                      onTap: stId.isEmpty
                          ? null
                          : () => Navigator.of(ctx).push(MaterialPageRoute(
                              builder: (_) =>
                                  GasDetailScreen(stationId: stId))),
                      onNavigate: (stLat == null || stLng == null)
                          ? null
                          : () => showNavigationSheet(ctx,
                              lat: stLat,
                              lng: stLng,
                              name: (st['name'] ?? '').toString()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 9),
                        margin: EdgeInsets.only(
                            bottom: i == stations.length - 1 ? 0 : 6),
                        decoration: BoxDecoration(
                          color: top
                              ? accent.withValues(alpha: isDark ? 0.10 : 0.06)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: top
                                    ? accent
                                    : muted.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: top ? Colors.white : muted)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text((st['name'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.2,
                                          color: primary)),
                                  if (dist != null)
                                    Text(
                                        '${(dist / 1000).toStringAsFixed(1)}km',
                                        style: TextStyle(
                                            fontSize: 11.5, color: muted)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                                '${_comma((st['price_won_per_liter'] as num).round())}원',
                                style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: top ? accent : secondary)),
                          ],
                        ),
                      ),
                    );
                  }),
              if (saveWon != null && saveWon > 0) ...[
                const SizedBox(height: 10),
                Text('1위에서 넣으면 동네 평균보다 리터당 ${_comma(saveWon)}원 아껴요',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: secondary)),
              ],
            ],
          )),

          // ── 동네 전체 최저가 ──
          if (minName.isNotEmpty && minPrice != null)
            sectionCard(Row(
              children: [
                const Icon(Icons.emoji_events_rounded,
                    size: 18, color: Color(0xFFF59E0B)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text('$label 전체 최저가는 $minName',
                      style: TextStyle(
                          fontSize: 12.5, height: 1.4, color: secondary)),
                ),
                const SizedBox(width: 8),
                Text('${_comma(minPrice)}원',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: primary)),
              ],
            )),

          const SizedBox(height: 6),
          Text('오피넷 판매가 기준 · 하루 한 번 갱신돼요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: muted)),

          const SizedBox(height: 14),
          const CheerThanksCta(message: '오늘 동네 유가, 도움이 되셨나요?'),
        ],
      ),
    );
  }
}

/// 반경 최저가 행 래퍼 — 탭=상세, 우측 길안내 버튼 (형 확정: 링크 추가).
class _NearRow extends StatelessWidget {
  const _NearRow({required this.child, this.onTap, this.onNavigate});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: child,
            ),
          ),
        ),
        if (onNavigate != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onNavigate,
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.gasBlue.withValues(alpha: isDark ? 0.2 : 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.navigation_rounded,
                  size: 17, color: AppColors.gasBlue),
            ),
          ),
        ],
      ],
    );
  }
}

/* ══════════════════════════ 지난 리포트 아카이브 ══════════════════════════ */

/// 년도 → 월별로 묶어 보는 전체 아카이브 (형 확정: 쌓여도 여기서 다 찾게).
/// 행이 (제목·날짜)뿐이라 300건을 한 번에 받아 클라이언트에서 그룹핑한다.
class FuelReportArchiveScreen extends StatefulWidget {
  const FuelReportArchiveScreen({super.key, required this.topic});

  final String topic;

  @override
  State<FuelReportArchiveScreen> createState() =>
      _FuelReportArchiveScreenState();
}

class _FuelReportArchiveScreenState extends State<FuelReportArchiveScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list =
          await ApiService().getFuelReports(topic: widget.topic, limit: 300);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
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
    final accent = widget.topic == 'ev' ? AppColors.evGreen : AppColors.gasBlue;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final primary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final line = isDark ? AppColors.darkCardBorder : const Color(0xFFF0F3F6);

    // 년 → 월 그룹핑 (최신 우선 정렬은 서버가 보장)
    final rows = <Widget>[];
    String? curYear;
    String? curMonth;
    var group = <Map<String, dynamic>>[];
    void flushMonth() {
      if (group.isEmpty) return;
      final list = group;
      group = [];
      final m = int.tryParse(curMonth ?? '') ?? 0;
      rows.add(Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark
                  ? AppColors.darkCardBorder
                  : AppColors.lightCardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
              child: Text('$m월',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: muted)),
            ),
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1, thickness: 1, color: line),
                ),
              _row(list[i], isDark, accent, primary, muted),
            ],
          ],
        ),
      ));
    }

    for (final r in _items) {
      final d = (r['date'] ?? '').toString();
      if (d.length < 7) continue;
      final y = d.substring(0, 4);
      final m = d.substring(5, 7);
      if (y != curYear) {
        flushMonth();
        curYear = y;
        curMonth = null;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Text('$y년',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: primary)),
        ));
      }
      if (m != curMonth) {
        flushMonth();
        curMonth = m;
      }
      group.add(Map<String, dynamic>.from(r));
    }
    flushMonth();

    return Scaffold(
      appBar:
          AppBar(title: Text(widget.topic == 'ev' ? '지난 충전 리포트' : '지난 유가 리포트')),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: accent))
          : (_items.isEmpty
              ? Center(
                  child: Text(_error ?? '아직 쌓인 리포트가 없어요',
                      style: TextStyle(fontSize: 13.5, color: muted)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: rows,
                )),
    );
  }

  Widget _row(Map<String, dynamic> r, bool isDark, Color accent, Color primary,
      Color muted) {
    final monthly = r['kind'] == 'monthly';
    String badge = monthly ? '월간' : '주간';
    final d = (r['date'] ?? '').toString();
    if (!monthly && d.length >= 10) {
      final dt = DateTime.tryParse(d.substring(0, 10));
      if (dt != null) badge = '${((dt.day - 1) ~/ 7) + 1}주차';
    }
    return InkWell(
      onTap: () {
        final id = int.tryParse(r['id']?.toString() ?? '');
        if (id == null) return;
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FuelReportDetailScreen(reportId: id)));
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            SizedBox(width: 44, child: _pill(badge, accent, isDark)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                (r['title'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: primary),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}
