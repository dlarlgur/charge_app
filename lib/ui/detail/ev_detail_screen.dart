import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/navigation_util.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/alert_service.dart';
import '../widgets/shared_widgets.dart';
import '../../data/services/favorite_service.dart';
import '../../providers/providers.dart' show favoritesProvider;

class EvDetailScreen extends ConsumerStatefulWidget {
  final String stationId;
  final EvStation? station;
  final VoidCallback? onSelectRoute;
  const EvDetailScreen({super.key, required this.stationId, this.station, this.onSelectRoute});
  @override
  ConsumerState<EvDetailScreen> createState() => _EvDetailScreenState();
}

class _EvDetailScreenState extends ConsumerState<EvDetailScreen> {
  EvStation? _station;
  bool _loading = true;
  bool _isFavorite = false;
  bool _isAlarm = false;
  bool _alarmLoading = false;

  @override
  void initState() {
    super.initState();
    _isFavorite = FavoriteService.isFavorite(widget.stationId, 'ev');
    _isAlarm = AlertService().isEvAlarmSubscribed(widget.stationId);
    AlertService().subsChanged.addListener(_onSubsChanged);
    if (widget.station != null) {
      _station = widget.station;
      _loading = false;
    } else {
      _loadDetail();
    }
  }

  @override
  void dispose() {
    AlertService().subsChanged.removeListener(_onSubsChanged);
    super.dispose();
  }

  void _onSubsChanged() {
    if (mounted) setState(() => _isAlarm = AlertService().isEvAlarmSubscribed(widget.stationId));
  }

  Future<void> _loadDetail() async {
    try {
      final detail = await ApiService().getEvStationDetail(widget.stationId);
      if (mounted) setState(() { _station = EvStation.fromJson(detail); _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleAlarm() async {
    if (_alarmLoading) return;
    final name = _station?.name ?? widget.stationId;
    setState(() => _alarmLoading = true);
    try {
      if (_isAlarm) {
        await AlertService().unsubscribeEvAlarm(widget.stationId);
        if (mounted) setState(() => _isAlarm = false);
      } else {
        final ids = AlertService().evAlarmStationIds;
        if (!ids.contains(widget.stationId) && ids.length >= AlertService.evAlarmMaxCount) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('충전소 현황 알림은 최대 3개까지 설정할 수 있어요')),
            );
          }
          return;
        }
        final ok = await AlertService().subscribeEvAlarm(
          stationId: widget.stationId, stationName: name);
        if (mounted) setState(() => _isAlarm = ok);
      }
    } finally {
      if (mounted) setState(() => _alarmLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('충전소 상세')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.evGreen))
          : _station == null
              ? const Center(child: Text('정보를 불러올 수 없습니다'))
              : EvDetailContent(
                  station: _station!,
                  onSelectRoute: widget.onSelectRoute,
                ),
    );
  }
}

/// 재사용 가능한 상세 컨텐츠. 풀스크린 라우트와 지도 bottom-sheet 양쪽에서 사용.
class EvDetailContent extends ConsumerStatefulWidget {
  final EvStation station;
  final VoidCallback? onSelectRoute;
  final ScrollController? sheetController;
  final bool sheetMode;
  const EvDetailContent({
    super.key,
    required this.station,
    this.onSelectRoute,
    this.sheetController,
    this.sheetMode = false,
  });

  @override
  ConsumerState<EvDetailContent> createState() => _EvDetailContentState();
}

class _EvDetailContentState extends ConsumerState<EvDetailContent> {
  // 알림 / 즐겨찾기 상태
  late bool _isFavorite;
  late bool _isAlarm;
  bool _alarmLoading = false;
  late final ScrollController _scroll;
  final GlobalKey _kChargers = GlobalKey();
  final GlobalKey _kPrice = GlobalKey();
  final GlobalKey _kStation = GlobalKey();
  final GlobalKey _kUsage = GlobalKey();
  final GlobalKey _kNearby = GlobalKey();
  int _activeTab = 0;

  // 주변 POI 상태
  static const List<String> _nearbyCategories = [
    '카페', '편의점', '마트', '주차장', '음식점',
  ];
  List<NearbyPoi> _nearbyAll = const [];
  bool _nearbyLoading = true;
  bool _nearbyExpanded = false;
  String _nearbyFilter = '전체';
  static const int _nearbyCollapsedLimit = 5;

  // 이용현황 상태
  Map<String, dynamic>? _analytics;
  bool _analyticsLoading = true;

  List<GlobalKey> get _sectionKeys =>
      [_kChargers, _kPrice, _kStation, _kUsage, _kNearby];
  static const List<String> _tabLabels =
      ['충전기', '요금', '충전소', '이용현황', '주변'];

  @override
  void initState() {
    super.initState();
    final sid = widget.station.statId;
    _isFavorite = FavoriteService.isFavorite(sid, 'ev');
    _isAlarm = AlertService().isEvAlarmSubscribed(sid);
    AlertService().subsChanged.addListener(_onSubsChanged);
    _scroll = widget.sheetController ?? ScrollController();
    _scroll.addListener(_onScroll);
    _loadNearby();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    try {
      final data = await ApiService().getEvAnalytics(widget.station.statId);
      if (mounted) {
        setState(() {
          _analytics = data;
          _analyticsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _analyticsLoading = false);
    }
  }

  @override
  void dispose() {
    AlertService().subsChanged.removeListener(_onSubsChanged);
    _scroll.removeListener(_onScroll);
    if (widget.sheetController == null) _scroll.dispose();
    super.dispose();
  }

  void _onSubsChanged() {
    if (mounted) {
      setState(() => _isAlarm = AlertService().isEvAlarmSubscribed(widget.station.statId));
    }
  }

  Future<void> _toggleAlarm() async {
    if (_alarmLoading) return;
    setState(() => _alarmLoading = true);
    try {
      final sid = widget.station.statId;
      if (_isAlarm) {
        await AlertService().unsubscribeEvAlarm(sid);
        if (mounted) setState(() => _isAlarm = false);
      } else {
        final ids = AlertService().evAlarmStationIds;
        if (!ids.contains(sid) && ids.length >= AlertService.evAlarmMaxCount) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('충전소 현황 알림은 최대 3개까지 설정할 수 있어요')),
            );
          }
          return;
        }
        final ok = await AlertService().subscribeEvAlarm(
            stationId: sid, stationName: widget.station.name);
        if (mounted) setState(() => _isAlarm = ok);
      }
    } finally {
      if (mounted) setState(() => _alarmLoading = false);
    }
  }

  void _toggleFavorite() {
    final s = widget.station;
    final result = FavoriteService.toggle(
      id: s.statId, type: 'ev', name: s.name, subtitle: s.address,
    );
    setState(() => _isFavorite = result);
    ref.read(favoritesProvider.notifier).refresh();
  }

  Future<void> _loadNearby() async {
    final s = widget.station;
    try {
      final raw = await ApiService().getNearbyPois(
        lat: s.lat, lng: s.lng,
        categories: _nearbyCategories,
        radiusKm: 1,
        count: 30,
      );
      final list = raw
          .map(NearbyPoi.fromJson)
          .where((p) => _nearbyCategories.contains(p.category))
          .toList()
        ..sort((a, b) => (a.distanceM ?? 1 << 30).compareTo(b.distanceM ?? 1 << 30));
      if (mounted) {
        setState(() {
          _nearbyAll = list;
          _nearbyLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _nearbyLoading = false);
    }
  }

  void _onScroll() {
    // 현재 보이는 섹션으로 탭 하이라이트 갱신.
    double nearestDelta = double.infinity;
    int nearestIdx = _activeTab;
    for (int i = 0; i < _sectionKeys.length; i++) {
      final ctx = _sectionKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox) continue;
      final offset = box.localToGlobal(Offset.zero).dy;
      final delta = (offset - 180).abs();
      if (offset < 300 && delta < nearestDelta) {
        nearestDelta = delta;
        nearestIdx = i;
      }
    }
    if (nearestIdx != _activeTab) {
      setState(() => _activeTab = nearestIdx);
    }
  }

  Future<void> _scrollToSection(int idx) async {
    setState(() => _activeTab = idx);
    final ctx = _sectionKeys[idx].currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.0,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.station;

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        if (widget.sheetMode)
          SliverToBoxAdapter(child: _dragHandle(isDark)),
        SliverToBoxAdapter(child: _heroCard(s, isDark)),
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabsDelegate(
            labels: _tabLabels,
            activeIndex: _activeTab,
            onTap: _scrollToSection,
            isDark: isDark,
          ),
        ),
        SliverToBoxAdapter(child: _chargersSection(s, isDark)),
        SliverToBoxAdapter(child: _priceSection(s, isDark)),
        SliverToBoxAdapter(child: _stationInfoSection(s, isDark)),
        SliverToBoxAdapter(child: _usageSection(isDark)),
        SliverToBoxAdapter(child: _nearbySection(s, isDark)),
        if (widget.onSelectRoute != null)
          SliverToBoxAdapter(child: _routeIncludeButton()),
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.bottom + 24)),
      ],
    );
  }

  // ─── 드래그 핸들 (시트 모드) ───
  Widget _dragHandle(bool isDark) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 6),
        width: 40, height: 4,
        decoration: BoxDecoration(
          color: isDark ? Colors.white24 : Colors.black26,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ─── 히어로 카드 ───
  Widget _heroCard(EvStation s, bool isDark) {
    final hasAvail = s.hasAvailable;

    // 커넥터 타입별 보유 여부 (항상 4개 원 표시, 없으면 회색)
    int countContains(String kw) =>
        s.chargers.where((c) => c.typeText.contains(kw)).length;
    final cntCombo = countContains('DC콤보');
    final cntChademo = countContains('DC차데모');
    final cnt3Phase = countContains('AC3상');
    final cntSlow = s.chargers.where((c) => c.type == '02').length;
    final cntNacs = countContains('NACS') + countContains('슈퍼');

    // 현재 충전 가능 대수 (커넥터 타입 기반: DC=급속, AC=완속)
    // 출력(kW) 기반이 아니라 커넥터 분류로 집계 — 아래 커넥터 원 카운트와 일치하도록
    // (예: DC콤보 30kW도 DC 커넥터이므로 '급속'으로 집계)
    bool isDcType(String t) =>
        t == '01' || t == '03' || t == '04' || t == '05' ||
        t == '06' || t == '08' || t == '09' || t == 'SC' || t == 'DT';
    final fastAvail = s.chargers
        .where((c) => isDcType(c.type) && c.status == ChargerStatus.available)
        .length;
    final slowAvail = s.chargers
        .where((c) =>
            !isDcType(c.type) && c.status == ChargerStatus.available)
        .length;

    final cardBg = isDark ? const Color(0xFF151B22) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? AppColors.darkTextMuted : const Color(0xFF64748B);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : const Color(0xFFECEFF3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
            blurRadius: 20,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1) 상단: 운영사 + 완전개방 (우상단)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                EvOperatorLogo(operator: s.operator),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.operator,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: subColor,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (s.accessLevel == 'restricted')
                  _topRightStack(
                    icon: Icons.lock_rounded,
                    label: '이용제한',
                    color: AppColors.error,
                  )
                else if (s.accessLevel == 'partial')
                  _topRightStack(
                    icon: Icons.lock_outline_rounded,
                    label: '부분개방',
                    color: AppColors.warning,
                  )
                else
                  _topRightStack(
                    icon: Icons.lock_open_rounded,
                    label: '완전개방',
                    color: AppColors.evGreen,
                  ),
                if (s.parkingFree) ...[
                  const SizedBox(width: 8),
                  _topRightStack(
                    icon: Icons.local_parking_rounded,
                    label: '주차무료',
                    color: AppColors.success,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // 2) 이름
            Text(
              s.name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                height: 1.22,
                color: titleColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            // 3) 주소 + 복사 + 거리
            InkWell(
              onTap: s.address.isNotEmpty ? () => _copyAddress(s.address) : null,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  if (s.address.isNotEmpty) ...[
                    Expanded(
                      child: Text(
                        s.address,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: subColor,
                          height: 1.35,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.copy_rounded,
                        size: 13, color: subColor.withOpacity(0.6)),
                  ],
                  if (s.distanceText.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.near_me_rounded,
                        size: 13, color: const Color(0xFF2F7DF6)),
                    const SizedBox(width: 3),
                    Text(
                      s.distanceText,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2F7DF6),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 11),
            // 4) 현재 충전 가능 / 급속·완속 대수
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  hasAvail
                      ? Icons.check_circle_rounded
                      : Icons.do_not_disturb_on_rounded,
                  size: 16,
                  color: hasAvail
                      ? AppColors.evGreen
                      : AppColors.statusOffline,
                ),
                const SizedBox(width: 5),
                Text(
                  hasAvail ? '현재 충전 가능' : '현재 이용 불가',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: titleColor,
                  ),
                ),
                const Spacer(),
                _availTag('급속', fastAvail, const Color(0xFFE76A3B), isDark),
                Container(
                  width: 1, height: 12,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: isDark
                      ? Colors.white.withOpacity(0.12)
                      : const Color(0xFFD8DEE6),
                ),
                _availTag('완속', slowAvail, const Color(0xFF16A34A), isDark),
              ],
            ),
            const SizedBox(height: 12),
            // 5) 커넥터 아이콘 (항상 표시, 없으면 회색)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _connectorCircle('DC콤보', _PlugShape.combo, cntCombo,
                    const Color(0xFF2F7DF6), isDark),
                _connectorCircle('DC차데모', _PlugShape.chademo, cntChademo,
                    const Color(0xFFE76A3B), isDark),
                _connectorCircle('AC3상', _PlugShape.ac3phase, cnt3Phase,
                    const Color(0xFF7C5CFF), isDark),
                _connectorCircle('완속', _PlugShape.slow, cntSlow,
                    const Color(0xFF16A34A), isDark),
                if (cntNacs > 0)
                  _connectorCircle('NACS', _PlugShape.nacs, cntNacs,
                      const Color(0xFFE91E63), isDark),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 1,
              color: isDark
                  ? Colors.white.withOpacity(0.07)
                  : const Color(0xFFEEF1F5),
            ),
            const SizedBox(height: 10),
            // 6) 액션 버튼: 알림 + 즐겨찾기 + 길찾기
            Row(
              children: [
                _ActionIconBtn(
                  icon: _isAlarm
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  color: _isAlarm ? AppColors.evGreen : null,
                  loading: _alarmLoading,
                  onTap: _toggleAlarm,
                  isDark: isDark,
                ),
                const SizedBox(width: 6),
                _ActionIconBtn(
                  icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorite ? AppColors.evGreen : null,
                  onTap: _toggleFavorite,
                  isDark: isDark,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => showNavigationSheet(
                        context, lat: s.lat, lng: s.lng, name: s.name),
                    icon: const Icon(Icons.navigation_rounded, size: 18),
                    label: Text(
                      s.distanceText.isNotEmpty
                          ? '길 안내 시작 (${s.distanceText})'
                          : '길 안내 시작',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.evGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _topRightStack({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _availTag(String label, int count, Color color, bool isDark) {
    final active = count > 0;
    final fg = active
        ? color
        : (isDark ? Colors.white54 : const Color(0xFF94A3B8));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white70 : const Color(0xFF475569),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: fg,
            letterSpacing: -0.5,
            height: 1,
          ),
        ),
      ],
    );
  }

  Widget _connectorCircle(
    String label,
    _PlugShape shape,
    int count,
    Color color,
    bool isDark,
  ) {
    final active = count > 0;
    final plugColor = active
        ? color
        : (isDark ? Colors.white24 : const Color(0xFFCBD5E1));
    final bg = active
        ? color.withOpacity(isDark ? 0.16 : 0.09)
        : (isDark
            ? Colors.white.withOpacity(0.05)
            : const Color(0xFFF1F5F9));
    final ringColor = active
        ? color.withOpacity(0.32)
        : (isDark
            ? Colors.white.withOpacity(0.08)
            : const Color(0xFFE2E8F0));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: ringColor, width: 1.2),
              ),
              alignment: Alignment.center,
              child: CustomPaint(
                size: const Size(22, 22),
                painter: _PlugIconPainter(shape: shape, color: plugColor),
              ),
            ),
            if (active)
              Positioned(
                top: -4, right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isDark ? const Color(0xFF151B22) : Colors.white,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: active
                ? (isDark ? Colors.white : const Color(0xFF334155))
                : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
          ),
        ),
      ],
    );
  }

  Future<void> _copyAddress(String addr) async {
    await Clipboard.setData(ClipboardData(text: addr));
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('주소를 복사했어요'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(40, 0, 40, 80),
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  // ─── 섹션: 충전기 ───
  Widget _chargersSection(EvStation s, bool isDark) {
    return Container(
      key: _kChargers,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('충전기 정보', '총 ${s.totalCount}대', isDark),
          const SizedBox(height: 12),
          if (s.isTesla)
            _noticeBox('테슬라 슈퍼차저는 실시간 현황을 제공하지 않아요', isDark)
          else
            Row(
              children: [
                _statusCounter('이용가능', s.availableCount, AppColors.statusAvailable, isDark),
                const SizedBox(width: 8),
                _statusCounter('충전중', s.chargingCount, AppColors.statusCharging, isDark),
                const SizedBox(width: 8),
                _statusCounter('고장', s.offlineCount, AppColors.statusOffline, isDark),
              ],
            ),
          if (s.chargers.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...([...s.chargers]..sort((a, b) {
                  int order(ChargerStatus s) => switch (s) {
                        ChargerStatus.available => 0,
                        ChargerStatus.charging => 1,
                        _ => 2,
                      };
                  return order(a.status).compareTo(order(b.status));
                })).map((c) => _chargerTile(c, isDark)),
            const SizedBox(height: 6),
            Text('충전기 상태는 실시간과 다를 수 있습니다',
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
          ],
        ],
      ),
    );
  }

  // ─── 섹션: 요금 ───
  Widget _priceSection(EvStation s, bool isDark) {
    return Container(
      key: _kPrice,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('충전요금', s.hasPriceInfo ? '단위 원/kWh' : null, isDark),
          const SizedBox(height: 12),
          if (!s.hasPriceInfo)
            _noticeBox('요금 정보가 제공되지 않아요', isDark)
          else ...[
            _priceRow('비회원', isDark ? Colors.white60 : Colors.black54,
                s.unitPriceFast, s.unitPriceSlow, isDark),
            if (s.unitPriceFastMember != null || s.unitPriceSlowMember != null) ...[
              const SizedBox(height: 8),
              _priceRow('회원', AppColors.evGreen,
                  s.unitPriceFastMember, s.unitPriceSlowMember, isDark),
            ],
          ],
        ],
      ),
    );
  }

  // ─── 섹션: 충전소 정보 ───
  Widget _stationInfoSection(EvStation s, bool isDark) {
    return Container(
      key: _kStation,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('충전소 정보', null, isDark),
          const SizedBox(height: 12),
          _infoCard(isDark, children: [
            _infoRow('주소', s.address, isDark, copyable: true),
            _infoDivider(isDark),
            _infoRow('충전타입', s.chargerTypeText, isDark),
            _infoDivider(isDark),
            _infoRow('이용시간', s.useTime, isDark),
            _infoDivider(isDark),
            _infoRow('주차요금', s.parkingFree ? '무료' : '유료', isDark,
                valueColor: s.parkingFree ? AppColors.success : null),
            if (s.limitYn || (s.limitDetail?.isNotEmpty == true)) ...[
              _infoDivider(isDark),
              _infoRow(
                '이용제한',
                s.limitDetail?.isNotEmpty == true ? s.limitDetail! : '외부인 이용 제한',
                isDark,
                valueColor: AppColors.statusOffline,
              ),
            ],
            if (s.note?.isNotEmpty == true) ...[
              _infoDivider(isDark),
              _infoRow('안내', s.note!, isDark),
            ],
            if (s.phone != null && s.phone!.isNotEmpty) ...[
              _infoDivider(isDark),
              InkWell(
                onTap: () => launchUrl(Uri.parse('tel:${s.phone}')),
                child: _infoRow('전화', s.phone!, isDark, valueColor: AppColors.gasBlue),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  // ─── 섹션: 이용현황 ───
  Widget _usageSection(bool isDark) {
    final data = _analytics;
    final loading = _analyticsLoading;
    final hasFound = data != null && data['found'] == true;
    final reliability = (data?['reliability'] as String?) ?? 'INSUFFICIENT';
    final sampleWeeks = (data?['sampleWeeks'] as int?) ?? 0;
    final totalSessions = (data?['totalSessions'] as int?) ?? 0;
    final isInsufficient = !hasFound ||
        reliability == 'INSUFFICIENT' ||
        totalSessions == 0;

    return Container(
      key: _kUsage,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            '이용현황',
            loading
                ? null
                : (isInsufficient
                    ? '분석 준비 중'
                    : _reliabilityLabel(reliability, sampleWeeks)),
            isDark,
          ),
          const SizedBox(height: 12),
          if (loading)
            _usageLoading(isDark)
          else if (isInsufficient)
            _usageInsufficient(isDark)
          else ...[
            _usageTypePill(data, isDark),
            const SizedBox(height: 10),
            for (final c in (data['cards'] as List? ?? const [])) ...[
              _usageCard(c as Map<String, dynamic>, data['stationType'] as String?, isDark),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            _usageFooter(data, isDark),
          ],
        ],
      ),
    );
  }

  String _reliabilityLabel(String reliability, int weeks) {
    switch (reliability) {
      case 'HIGH':   return '관측 3주+ 기준';
      case 'MEDIUM': return '관측 2주 기준';
      case 'LOW':    return '관측 ${weeks > 0 ? weeks : 1}주 기준';
    }
    return '';
  }

  Widget _usageLoading(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 22, height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.evGreen),
      ),
    );
  }

  Widget _usageInsufficient(bool isDark) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
          width: 0.6,
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.hourglass_bottom_rounded, size: 28, color: muted),
          const SizedBox(height: 8),
          Text(
            '분석 준비 중이에요',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '이용 이력이 쌓이면 시간대별 특징을 알려드릴게요',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
          ),
        ],
      ),
    );
  }

  Color _typeAccent(String? stationType) {
    switch (stationType) {
      case 'RESIDENTIAL': return const Color(0xFF7C5CFC); // 보라
      case 'OFFICE':      return const Color(0xFF2F7DF6); // 파랑
      case 'LEISURE':     return const Color(0xFFFF8A3D); // 주황
      case 'CONVENIENCE': return const Color(0xFFE94D8C); // 핑크
      default:            return AppColors.evGreen;        // UNKNOWN/EXCLUDED
    }
  }

  IconData _iconOf(String? name) {
    switch (name) {
      case 'busy':         return Icons.do_not_disturb_on_rounded;
      case 'opening':      return Icons.trending_down_rounded;
      case 'arrive':       return Icons.login_rounded;
      case 'free':         return Icons.check_circle_rounded;
      case 'stopwatch':    return Icons.timer_rounded;
      case 'clock':        return Icons.access_time_rounded;
      case 'moon':         return Icons.nights_stay_rounded;
      case 'sun':          return Icons.wb_sunny_rounded;
      case 'shopping-bag': return Icons.shopping_bag_rounded;
      case 'battery':      return Icons.battery_charging_full_rounded;
      case 'briefcase':    return Icons.business_center_rounded;
      case 'calendar':     return Icons.calendar_month_rounded;
      case 'hourglass':    return Icons.hourglass_bottom_rounded;
    }
    return Icons.insights_rounded;
  }

  Widget _usageTypePill(Map<String, dynamic> data, bool isDark) {
    final stationType = data['stationType'] as String?;
    final label = (data['stationTypeLabel'] as String?) ?? '분류 준비 중';
    final accent = _typeAccent(stationType);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withOpacity(isDark ? 0.18 : 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accent,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _usageCard(Map<String, dynamic> card, String? stationType, bool isDark) {
    final accent = _typeAccent(stationType);
    final icon = _iconOf(card['icon'] as String?);
    final title = (card['title'] as String?) ?? '';
    final body  = (card['body']  as String?) ?? '';
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final bodyColor  = isDark ? AppColors.darkTextMuted : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
          width: 0.6,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    letterSpacing: -0.2,
                    color: titleColor,
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: bodyColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _usageFooter(Map<String, dynamic> data, bool isDark) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final sessions = data['totalSessions'] as int? ?? 0;
    final window   = (data['dataWindow'] as Map?)?['days'] as int? ?? 28;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 13, color: muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '최근 $window일 관측 $sessions회 세션 기준',
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 섹션: 주변 ───
  Widget _nearbySection(EvStation s, bool isDark) {
    // 카테고리 카운트
    final counts = <String, int>{};
    for (final p in _nearbyAll) {
      counts[p.category] = (counts[p.category] ?? 0) + 1;
    }
    // count > 0 인 카테고리만 칩으로 표시 (빈 항목이 섞이면 separator 공백 발생)
    final activeChips = ['전체', ..._nearbyCategories.where((c) => (counts[c] ?? 0) > 0)];

    final filtered = _nearbyFilter == '전체'
        ? _nearbyAll
        : _nearbyAll.where((p) => p.category == _nearbyFilter).toList();

    final showAll = _nearbyExpanded || filtered.length <= _nearbyCollapsedLimit;
    final visible = showAll ? filtered : filtered.take(_nearbyCollapsedLimit).toList();
    final hiddenCount = filtered.length - visible.length;

    return Container(
      key: _kNearby,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('주변', _nearbyAll.isEmpty ? null : '반경 1km', isDark),
          const SizedBox(height: 12),
          if (_nearbyLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.evGreen),
                ),
              ),
            )
          else if (_nearbyAll.isEmpty)
            _noticeBox('반경 1km 내에 등록된 장소가 없어요', isDark)
          else ...[
            // 카테고리 칩
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < activeChips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _nearbyChip(
                      activeChips[i],
                      activeChips[i] == '전체' ? _nearbyAll.length : (counts[activeChips[i]] ?? 0),
                      _nearbyFilter == activeChips[i],
                      isDark,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 리스트
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
                  width: 0.6,
                ),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < visible.length; i++) ...[
                    _nearbyTile(visible[i], s, isDark),
                    if (i != visible.length - 1) _infoDivider(isDark),
                  ],
                ],
              ),
            ),
            if (hiddenCount > 0) ...[
              const SizedBox(height: 8),
              _nearbyMoreButton(hiddenCount, isDark),
            ] else if (_nearbyExpanded && filtered.length > _nearbyCollapsedLimit) ...[
              const SizedBox(height: 8),
              _nearbyMoreButton(null, isDark),
            ],
          ],
        ],
      ),
    );
  }

  Widget _nearbyChip(String cat, int count, bool active, bool isDark) {
    final bg = active
        ? AppColors.evGreen
        : (isDark ? AppColors.darkCard : const Color(0xFFF1F5F9));
    final fg = active
        ? Colors.white
        : (isDark ? Colors.white70 : Colors.black87);
    return InkWell(
      onTap: () => setState(() => _nearbyFilter = cat),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? Colors.transparent
                : (isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0)),
            width: 0.6,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(cat,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
            const SizedBox(width: 4),
            Text('$count',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : AppColors.evGreen)),
          ],
        ),
      ),
    );
  }

  Widget _nearbyTile(NearbyPoi p, EvStation s, bool isDark) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    return InkWell(
      onTap: () => _openPoiInKakaoMap(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(p.name,
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : Colors.black87),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.open_in_new_rounded, size: 13, color: muted),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '이 장소로부터 ${p.distanceText}',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(p.category,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: muted)),
          ],
        ),
      ),
    );
  }

  Widget _nearbyMoreButton(int? hiddenCount, bool isDark) {
    final expanded = hiddenCount == null;
    return InkWell(
      onTap: () => setState(() => _nearbyExpanded = !_nearbyExpanded),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0),
            width: 0.6,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              expanded ? '주변정보 접기' : '주변정보 더보기 ($hiddenCount)',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(width: 4),
            Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 20, color: isDark ? Colors.white70 : Colors.black54),
          ],
        ),
      ),
    );
  }

  Future<void> _openPoiInKakaoMap(NearbyPoi p) async {
    // POI 이름 + 좌표로 카카오맵 검색 열기.
    final q = Uri.encodeComponent(p.name);
    final uri = (p.lat != null && p.lng != null)
        ? Uri.parse('https://map.kakao.com/?q=$q&urlX=${p.lng}&urlY=${p.lat}&urlLevel=3')
        : Uri.parse('https://map.kakao.com/?q=$q');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${p.name} 을(를) 열 수 없어요')),
        );
      }
    }
  }

  // ─── 히어로 직하단 주 액션: [알림] [즐겨찾기] [────────길찾기────────] ───
  Widget _primaryActions(EvStation s) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          _ActionIconBtn(
            icon: _isAlarm
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            color: _isAlarm ? AppColors.evGreen : null,
            loading: _alarmLoading,
            onTap: _toggleAlarm,
            isDark: isDark,
          ),
          const SizedBox(width: 6),
          _ActionIconBtn(
            icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
            color: _isFavorite ? AppColors.evGreen : null,
            onTap: _toggleFavorite,
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () =>
                  showNavigationSheet(context, lat: s.lat, lng: s.lng, name: s.name),
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text('길찾기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.evGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeIncludeButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: widget.onSelectRoute,
          icon: const Icon(Icons.route_rounded, size: 18),
          label: const Text('이 충전소로 경로에 포함'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.evGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  // ─── 공용 소형 위젯 ───
  Widget _sectionTitle(String title, String? trailing, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: isDark ? Colors.white : Colors.black87)),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(trailing,
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
          ),
        ],
      ],
    );
  }

  Widget _noticeBox(String text, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
          width: 0.5,
        ),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
    );
  }

  Widget _statusCounter(String label, int count, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.1 : 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text('$count',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
          ],
        ),
      ),
    );
  }

  Widget _chargerTile(Charger charger, bool isDark) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    Color statusColor;
    String statusText;
    String? subText;
    Color subTextColor = muted;

    switch (charger.status) {
      case ChargerStatus.available:
        statusColor = AppColors.statusAvailable;
        statusText = '충전가능';
        subText = charger.lastStatusUpdate != null
            ? '${_timeAgo(charger.lastStatusUpdate!)} 마지막 충전'
            : null;
        break;
      case ChargerStatus.charging:
        statusColor = AppColors.statusCharging;
        statusText = '충전중';
        final startDt = charger.chargingStarted ?? charger.lastStatusUpdate;
        subText = startDt != null ? _chargingElapsed(startDt) : null;
        subTextColor = AppColors.statusCharging;
        break;
      case ChargerStatus.unknown:
        statusColor = AppColors.statusOffline;
        statusText = '상태확인 불가';
        subText = charger.lastStatusUpdate != null
            ? '${_timeAgo(charger.lastStatusUpdate!)} 고장'
            : null;
        subTextColor = AppColors.statusOffline;
        break;
      default:
        statusColor = AppColors.statusOffline;
        statusText = charger.status.label;
        subText = charger.lastStatusUpdate != null
            ? '${_timeAgo(charger.lastStatusUpdate!)} 고장'
            : null;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusText,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: statusColor)),
                if (subText != null) ...[
                  const SizedBox(height: 3),
                  Text(subText, style: TextStyle(fontSize: 11, color: subTextColor)),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(charger.typeText,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(height: 2),
              Text('${charger.output}kW',
                  style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String tier, Color tierColor, int? fast, int? slow, bool isDark) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final border = isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;

    Widget col(String label, int? price, Color accent) {
      return Expanded(
        child: Column(
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: muted)),
            const SizedBox(height: 4),
            price != null
                ? RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '$price',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: accent,
                            letterSpacing: -0.4,
                          ),
                        ),
                        TextSpan(
                          text: '원',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  )
                : Text('-',
                    style: TextStyle(
                        fontSize: 16, color: muted, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: tierColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(tier,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800, color: tierColor)),
          ),
          const SizedBox(width: 14),
          col('급속', fast, AppColors.statusFast),
          Container(width: 1, height: 34, color: border),
          col('완속', slow, AppColors.evGreen),
        ],
      ),
    );
  }

  Widget _infoCard(bool isDark, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
          width: 0.6,
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _infoDivider(bool isDark) => Divider(
        height: 1,
        thickness: 0.5,
        color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
      );

  Widget _infoRow(String label, String value, bool isDark,
      {Color? valueColor, bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: valueColor ??
                        (isDark ? Colors.white : Colors.black87))),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) {
      final m = diff.inMinutes % 60;
      return m > 0 ? '${diff.inHours}시간 ${m}분 전' : '${diff.inHours}시간 전';
    }
    return '${diff.inDays}일 전';
  }

  String _chargingElapsed(DateTime startDt) {
    final diff = DateTime.now().difference(startDt);
    if (diff.inMinutes < 1) return '방금 시작';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 충전중';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return m > 0 ? '$h시간 ${m}분 충전중' : '$h시간 충전중';
  }
}

// ─── 액션 아이콘 버튼 (알림/즐겨찾기용) ───
class _ActionIconBtn extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final bool loading;
  final VoidCallback onTap;
  final bool isDark;
  const _ActionIconBtn({
    required this.icon, this.color, this.loading = false,
    required this.onTap, required this.isDark,
  });
  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkCard : const Color(0xFFF1F5F9);
    final border = isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0);
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 0.6),
        ),
        child: loading
            ? const Center(
                child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.evGreen)))
            : Icon(icon, size: 22, color: color ?? (isDark ? Colors.white70 : Colors.black54)),
      ),
    );
  }
}

class NearbyPoi {
  final String id;
  final String name;
  final String category;
  final int? distanceM;
  final String? tel;
  final double? lat;
  final double? lng;
  final String? address;
  const NearbyPoi({
    required this.id,
    required this.name,
    required this.category,
    this.distanceM,
    this.tel,
    this.lat,
    this.lng,
    this.address,
  });

  factory NearbyPoi.fromJson(Map<String, dynamic> j) {
    double? toDouble(dynamic v) => v is num ? v.toDouble() : null;
    int? toInt(dynamic v) => v is num ? v.toInt() : null;
    return NearbyPoi(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      category: (j['category'] ?? '기타').toString(),
      distanceM: toInt(j['distance_m']),
      tel: j['tel'] as String?,
      lat: toDouble(j['lat']),
      lng: toDouble(j['lng']),
      address: j['address'] as String?,
    );
  }

  String get distanceText {
    final d = distanceM;
    if (d == null) return '-';
    if (d < 1000) return '${d}m';
    return '${(d / 1000).toStringAsFixed(1)}km';
  }
}

// ─── 섹션 탭 pinned 헤더 ───
class _TabsDelegate extends SliverPersistentHeaderDelegate {
  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onTap;
  final bool isDark;
  _TabsDelegate({
    required this.labels,
    required this.activeIndex,
    required this.onTap,
    required this.isDark,
  });

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: isDark ? AppColors.darkBg : Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = i == activeIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: active ? AppColors.evGreen : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active
                        ? (isDark ? Colors.white : Colors.black87)
                        : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsDelegate old) =>
      old.activeIndex != activeIndex || old.isDark != isDark;
}

enum _PlugShape { combo, chademo, ac3phase, slow, nacs }

class _PlugIconPainter extends CustomPainter {
  final _PlugShape shape;
  final Color color;
  const _PlugIconPainter({required this.shape, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.07
      ..isAntiAlias = true;
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;
    final r = w * 0.48;

    // 아웃라인 (플러그 외곽)
    canvas.drawCircle(Offset(cx, cy), r, stroke);

    switch (shape) {
      case _PlugShape.slow:
        // 완속 (AC단상 / Type1 단순화): 2개 핀 수평
        _dot(canvas, paint, cx - w * 0.18, cy, w * 0.08);
        _dot(canvas, paint, cx + w * 0.18, cy, w * 0.08);
        break;
      case _PlugShape.chademo:
        // DC차데모: 4개 핀 (2x2 사각형)
        _dot(canvas, paint, cx - w * 0.16, cy - h * 0.16, w * 0.075);
        _dot(canvas, paint, cx + w * 0.16, cy - h * 0.16, w * 0.075);
        _dot(canvas, paint, cx - w * 0.16, cy + h * 0.16, w * 0.075);
        _dot(canvas, paint, cx + w * 0.16, cy + h * 0.16, w * 0.075);
        break;
      case _PlugShape.ac3phase:
        // AC3상 (Type2 단순화): 위 3핀, 아래 2핀
        _dot(canvas, paint, cx - w * 0.22, cy - h * 0.14, w * 0.07);
        _dot(canvas, paint, cx, cy - h * 0.2, w * 0.07);
        _dot(canvas, paint, cx + w * 0.22, cy - h * 0.14, w * 0.07);
        _dot(canvas, paint, cx - w * 0.12, cy + h * 0.15, w * 0.07);
        _dot(canvas, paint, cx + w * 0.12, cy + h * 0.15, w * 0.07);
        break;
      case _PlugShape.combo:
        // DC콤보 (CCS1/2): 위쪽 AC 핀들 + 아래쪽 큰 DC 핀 2개
        _dot(canvas, paint, cx - w * 0.18, cy - h * 0.2, w * 0.06);
        _dot(canvas, paint, cx, cy - h * 0.22, w * 0.06);
        _dot(canvas, paint, cx + w * 0.18, cy - h * 0.2, w * 0.06);
        _dot(canvas, paint, cx - w * 0.16, cy + h * 0.16, w * 0.11);
        _dot(canvas, paint, cx + w * 0.16, cy + h * 0.16, w * 0.11);
        break;
      case _PlugShape.nacs:
        // NACS (테슬라): 상단 반원 핀 2개 + 하단 큰 핀 2개
        _dot(canvas, paint, cx - w * 0.14, cy - h * 0.16, w * 0.07);
        _dot(canvas, paint, cx + w * 0.14, cy - h * 0.16, w * 0.07);
        _dot(canvas, paint, cx - w * 0.14, cy + h * 0.16, w * 0.1);
        _dot(canvas, paint, cx + w * 0.14, cy + h * 0.16, w * 0.1);
        break;
    }
  }

  void _dot(Canvas c, Paint p, double x, double y, double r) {
    c.drawCircle(Offset(x, y), r, p);
  }

  @override
  bool shouldRepaint(covariant _PlugIconPainter old) =>
      old.shape != shape || old.color != color;
}
