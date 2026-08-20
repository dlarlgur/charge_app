import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart'
    show
        favoritesProvider,
        bottomNavIndexProvider,
        favGasStationsProvider,
        favEvStationsProvider,
        favGasStationsSortedProvider,
        favEvStationsSortedProvider;
import '../../core/utils/navigation_util.dart';
import '../../core/app_dialog.dart';
import '../../data/services/place_service.dart';
import '../../data/services/regular_station_service.dart';
import '../../data/services/station_alias_service.dart';
import 'place_picker_screen.dart';
import '../widgets/empty_state.dart';
import '../widgets/shared_widgets.dart';

/// 즐겨찾기 화면 — 홈과 동일한 GasStationCard/EvStationCard 디자인 재사용.
/// (가격·거리·편의시설·길안내 버튼 등 홈 카드 기능 그대로. 즐겨찾기 해제는 카드의 하트.)
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});
  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 정렬 — 기본 거리순, 칩으로 가격순 전환 (제보: 즐겨찾기도 가격순 보고 싶다).
  // 마지막 정렬 유지 (형 전달 제보: 가격순 골라도 재실행하면 거리순으로 복귀)
  bool _byPrice = Hive.box(AppConstants.settingsBox)
      .get('fav_sort_by_price', defaultValue: false) as bool;

  void _setByPrice(bool v) {
    setState(() => _byPrice = v);
    Hive.box(AppConstants.settingsBox).put('fav_sort_by_price', v);
  }

  // ── 새로고침 — 충전기 상태가 세션 내내 캐시돼 낡는 문제(사용자 제보) ──
  // 서버는 배경 루프가 상태를 계속 갱신 중이라 재조회는 Redis 읽기뿐 — 쿼터 영향 0.
  // 쿨다운은 연타 시 헛요청만 거른다 (환경부 원천이 5분 주기라 그 이상 자주는 무의미).
  DateTime? _lastRefreshAt;
  static const _refreshCooldown = Duration(seconds: 15);
  static const _autoRefreshAfter = Duration(minutes: 2);

  Future<void> _refreshStations() async {
    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < _refreshCooldown) {
      // 쿨다운 — 요청은 안 나가되 짧게 돌려서 '동작했다' 피드백은 준다
      await Future.delayed(const Duration(milliseconds: 400));
      return;
    }
    _lastRefreshAt = now;
    ref.invalidate(favGasStationsProvider);
    ref.invalidate(favEvStationsProvider);
    try {
      // 응답이 빨라도 스피너가 눈에 보이게 최소 회전 시간 보장
      await Future.wait([
        ref.read(favGasStationsProvider.future),
        ref.read(favEvStationsProvider.future),
        Future.delayed(const Duration(milliseconds: 600)),
      ]);
    } catch (_) {
      // 실패는 provider 의 error 상태로 표시된다 — 여기선 삼킨다
    }
  }

  List<GasStation> _sortedGas(List<GasStation> l) {
    final c = [...l];
    if (_byPrice) {
      // 동일 가격이면 가까운 곳 먼저 (사용자 제보)
      c.sort((a, b) {
        final r = a.price.compareTo(b.price);
        return r != 0 ? r : a.distance.compareTo(b.distance);
      });
    } else {
      c.sort((a, b) => a.distance.compareTo(b.distance));
    }
    return c;
  }

  List<EvStation> _sortedEv(List<EvStation> l) {
    final c = [...l];
    double? priceOf(EvStation s) =>
        s.unitPriceFast ??
        s.unitPriceSlow ??
        s.unitPriceFastMember ??
        s.unitPriceSlowMember;
    if (_byPrice) {
      c.sort((a, b) {
        final pa = priceOf(a), pb = priceOf(b);
        if (pa == null && pb == null) return 0;
        if (pa == null) return 1;
        if (pb == null) return -1;
        final r = pa.compareTo(pb);
        if (r != 0) return r;
        // 동일 가격이면 가까운 곳 먼저 (사용자 제보)
        return (a.distance ?? double.infinity)
            .compareTo(b.distance ?? double.infinity);
      });
    } else {
      c.sort((a, b) => (a.distance ?? double.infinity)
          .compareTo(b.distance ?? double.infinity));
    }
    return c;
  }

  Widget _sortChip(String label, bool active, bool isDark, VoidCallback onTap) {
    final fg = active
        ? Colors.white
        : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppColors.gasBlue
              : (isDark ? AppColors.darkCard : const Color(0xFFF1F3F6)),
          borderRadius: BorderRadius.circular(16),
          border: active
              ? null
              : Border.all(
                  color: isDark
                      ? AppColors.darkCardBorder
                      : const Color(0xFFE0E4EA),
                  width: 0.8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, initialIndex: 1, vsync: this);
    // 집/회사 탭에선 정렬 칩 숨김 — 탭 전환 시 리빌드
    _tabController.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 즐겨찾기 탭(IndexedStack index 3) 재진입 시 데이터가 오래됐으면 자동 재조회 —
    // IndexedStack 이라 화면이 항상 살아 있어 fetch 가 앱 시작 시점에 멈춰 있었다.
    ref.listen<int>(bottomNavIndexProvider, (prev, next) {
      if (next != 3 || prev == next) return;
      final last = _lastRefreshAt;
      if (last == null ||
          DateTime.now().difference(last) > _autoRefreshAfter) {
        _refreshStations();
      }
    });

    final favorites = ref.watch(favoritesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gasCount = favorites.where((f) => f['type'] == 'gas').length;
    final evCount = favorites.where((f) => f['type'] == 'ev').length;

    return Column(
      children: [
        // 탭 바
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x0AFFFFFF) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: isDark ? AppColors.gasBlue : AppColors.gasBlueDark,
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor:
                isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: [
              const Tab(text: '집/회사'),
              Tab(text: '전체 (${favorites.length})'),
              Tab(text: '주유소 ($gasCount)'),
              Tab(text: '충전소 ($evCount)'),
            ],
          ),
        ),
        // 정렬 칩 — 거리순/가격순 (집/회사 탭에선 무의미하므로 숨김)
        if (_tabController.index != 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              const Spacer(),
              _sortChip('거리순', !_byPrice, isDark,
                  () => _setByPrice(false)),
              const SizedBox(width: 6),
              _sortChip('가격순', _byPrice, isDark,
                  () => _setByPrice(true)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 리스트 — 홈과 동일 카드
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPlaces(),
              _buildAll(),
              _buildGas(),
              _buildEv(),
            ],
          ),
        ),
      ],
    );
  }

  // ── 집/회사 (네이버식) — 게스트 로컬, 로그인 서버 동기 ──
  Widget _buildPlaces() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        _placeRow('home', '집', Icons.home_rounded),
        _placeRow('work', '회사', Icons.business_rounded),
      ],
    );
  }

  Widget _placeRow(String kind, String label, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = PlaceService.get(kind);
    final registered = p != null;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final accent = isDark ? AppColors.gasBlue : AppColors.gasBlueDark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? AppColors.darkCardBorder : const Color(0xFFE8ECF0),
            width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => registered ? _navToPlace(p) : _editPlace(kind, label),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: registered
                      ? accent.withValues(alpha: 0.12)
                      : (isDark ? const Color(0x14FFFFFF) : const Color(0xFFF1F3F6)),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 21, color: registered ? accent : muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: muted)),
                    const SizedBox(height: 2),
                    Text(
                      registered ? (p['name'] ?? '').toString() : '아직 등록되지 않았어요',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: registered
                            ? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)
                            : muted,
                      ),
                    ),
                    if (registered && (p['address'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text((p['address'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: muted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              registered
                  ? IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.edit_outlined, size: 18, color: muted),
                      onPressed: () => _editPlaceSheet(kind, label),
                    )
                  : Text('등록',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: accent)),
            ],
          ),
        ),
      ),
    );
  }

  void _navToPlace(Map<String, dynamic> p) {
    showNavigationSheet(
      context,
      lat: (p['lat'] as num).toDouble(),
      lng: (p['lng'] as num).toDouble(),
      name: (p['name'] ?? '').toString(),
    );
  }

  Future<void> _editPlace(String kind, String label) async {
    final picked = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => PlacePickerScreen(title: '$label 등록')),
    );
    if (picked != null) {
      await PlaceService.set(kind, picked);
      if (mounted) setState(() {});
    }
  }

  void _editPlaceSheet(String kind, String label) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_location_alt_outlined, size: 22),
              title: Text('$label 위치 다시 설정'),
              onTap: () {
                Navigator.pop(ctx);
                _editPlace(kind, label);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  size: 22, color: Color(0xFFE53935)),
              title: const Text('삭제', style: TextStyle(color: Color(0xFFE53935))),
              onTap: () async {
                Navigator.pop(ctx);
                await PlaceService.remove(kind);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _empty() => EmptyState(
        icon: Icons.favorite_outline_rounded,
        title: '즐겨찾기가 없습니다',
        description: '주유소/충전소 상세에서 하트를 누르거나\n지도에서 자주 가는 곳을 등록해보세요.',
        actionLabel: '지도에서 찾아보기',
        onAction: () => ref.read(bottomNavIndexProvider.notifier).state = 1,
      );

  Widget _error() => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('즐겨찾기를 불러오지 못했어요. 잠시 후 다시 시도해주세요.',
              textAlign: TextAlign.center),
        ),
      );

  // 카드는 자체 margin(h16, v4) 보유 → 추가 패딩 없이 그대로 나열.
  Widget _gasCard(GasStation s) => GasStationCard(
        station: s,
        onTap: () => context.push('/gas/${s.id}', extra: s),
      );

  Widget _evCard(EvStation s) => EvStationCard(
        station: s,
        onTap: () => context.push('/ev/${s.statId}', extra: s),
      );

  // ── 단골주유소 (주유소 탭 전용 — 주유 전용 기능, 충전소 탭 X) ──
  // 공용 카드(GasStationCard)에는 단골 요소를 넣지 않는다 — 작은 폰·큰 글씨에서
  // 한 행이 빡빡해져 이름이 찌그러진다(형 제보). 상단 섹션 + '단골 등록' 텍스트
  // 버튼 + 즐겨찾기 선택 시트로 일원화.

  /// '단골 등록/변경' 버튼 → 내 즐겨찾기 주유소에서 고르는 선택 시트.
  /// 이미 단골인 항목은 체크 표시, 탭하면 해제. 만석 상태에서 새 항목을 고르면
  /// 교체 선택 시트가 이어진다 (무조건 덮어쓰기 금지).
  Future<void> _showRegularPickSheet(List<GasStation> favs) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? AppColors.darkSurface1 : Colors.white;
        final muted =
            isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
        final textPrimary =
            isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0x33FFFFFF)
                        : const Color(0xFFDDE3EA),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text('즐겨찾기에서 단골 고르기',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: textPrimary)),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text('${RegularStationService.copyLine}.',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, height: 1.4, color: muted)),
                ),
                const SizedBox(height: 8),
                if (favs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Text(
                        '즐겨찾기한 주유소가 없어요.\n주유소 상세화면에서 단골로 지정할 수 있어요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, height: 1.5, color: muted)),
                  )
                else
                  Flexible(
                    child: ValueListenableBuilder<List<RegularStation>>(
                      valueListenable: RegularStationService.notifier,
                      builder: (ctx, regs, _) => ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        children: [
                          for (final s in favs)
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              title: Text(
                                  StationAliasService.resolveGas(
                                      s.id, s.name),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: textPrimary)),
                              subtitle: Text(
                                  '${s.brandName} · ${s.address}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12, color: muted)),
                              trailing: regs.any((r) => r.id == s.id)
                                  ? const Icon(Icons.check_circle_rounded,
                                      size: 20, color: AppColors.gasBlue)
                                  : null,
                              onTap: () => _pickRegularFromSheet(
                                  ctx, s, regs.any((r) => r.id == s.id)),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 선택 시트에서 한 곳 탭 — 단골이면 해제 확인, 아니면 추가(만석이면 교체 선택).
  /// 시트는 닫지 않는다 — 체크 표시가 즉시 바뀌어 여러 곳을 이어서 정리할 수 있게.
  Future<void> _pickRegularFromSheet(
      BuildContext sheetCtx, GasStation s, bool isRegular) async {
    if (isRegular) {
      final ok = await showAppDialog<bool>(
        sheetCtx,
        icon: Icons.loyalty_rounded,
        title: '단골주유소 해제',
        message: '${s.name}을(를) 단골주유소에서 해제할까요?',
        primaryLabel: '해제하기',
        primaryValue: true,
        secondaryLabel: '취소',
      );
      if (ok == true) RegularStationService.remove(s.id);
      return;
    }
    if (RegularStationService.isFull) {
      final target = await showRegularReplacePicker(sheetCtx, newName: s.name);
      if (target == null) return;
      RegularStationService.replace(target.id,
          id: s.id, name: s.name, brand: s.brand);
      return;
    }
    RegularStationService.add(id: s.id, name: s.name, brand: s.brand);
  }

  /// 주유소 탭 상단 단골 섹션 — 이 기능의 유일한 자리.
  /// 세로 배치·행당 가로 요소 최소화(이름 Expanded + 해제 버튼)로 작은 폰·큰 글씨에서
  /// 안 깨지게. '단골 등록'은 아이콘이 아니라 **글자 버튼**으로 (형 요구).
  List<Widget> _regularSection(
      List<RegularStation> regs, List<GasStation> favs, bool isDark) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final isFull = regs.length >= RegularStationService.maxCount;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
        child: Row(
          children: [
            Expanded(
              child: Text('단골주유소',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary)),
            ),
            Text('${regs.length}/${RegularStationService.maxCount}',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: muted)),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: Text('${RegularStationService.copyLine}.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, height: 1.4, color: muted)),
      ),
      // 등록된 단골 행 — 탭=상세 이동, 오른쪽 '해제' 텍스트 버튼.
      for (final r in regs)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isDark
                    ? AppColors.darkCardBorder
                    : const Color(0xFFE8ECF0),
                width: 0.8),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push('/gas/${r.id}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(r.name.trim().isEmpty ? '단골주유소' : r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary)),
                  ),
                  TextButton(
                    onPressed: () async {
                      final name = r.name.trim().isEmpty ? '이 주유소' : r.name;
                      final ok = await showAppDialog<bool>(
                        context,
                        icon: Icons.loyalty_rounded,
                        title: '단골주유소 해제',
                        message: '$name을(를) 단골주유소에서 해제할까요?',
                        primaryLabel: '해제하기',
                        primaryValue: true,
                        secondaryLabel: '취소',
                      );
                      if (ok == true) RegularStationService.remove(r.id);
                    },
                    child: const Text('해제',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      // '단골 등록' 글자 버튼 — 미등록이면 섹션의 주역(큰 버튼), 등록분이 있으면
      // 목록 아래 보조 버튼. 만석이면 '단골 변경'으로 라벨 전환.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: regs.isEmpty
            ? SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.tonal(
                  onPressed: () => _showRegularPickSheet(favs),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        AppColors.gasBlue.withValues(alpha: 0.12),
                    foregroundColor: AppColors.gasBlue,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  child: const Text('단골 등록'),
                ),
              )
            : SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton(
                  onPressed: () => _showRegularPickSheet(favs),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gasBlue,
                    side: BorderSide(
                        color: AppColors.gasBlue.withValues(alpha: 0.45)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  child: Text(isFull ? '단골 변경' : '단골 등록'),
                ),
              ),
      ),
      const SizedBox(height: 10),
    ];
  }

  Widget _buildGas() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final async = ref.watch(favGasStationsSortedProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _error(),
      data: (list) {
        final sorted = _sortedGas(list);
        // 단골 상태 변경(등록/교체/해제) 시 섹션이 즉시 따라오게 구독.
        // 즐겨찾기 카드는 기존 그대로 — 단골 요소를 카드에 넣지 않는다.
        return RefreshIndicator(
          onRefresh: _refreshStations,
          color: AppColors.gasBlue,
          child: ValueListenableBuilder<List<RegularStation>>(
            valueListenable: RegularStationService.notifier,
            builder: (context, regs, _) => ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                ..._regularSection(regs, sorted, isDark),
                if (sorted.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: _empty(),
                  )
                else
                  for (final s in sorted) _gasCard(s),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEv() {
    final async = ref.watch(favEvStationsSortedProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _error(),
      data: (list) {
        final sorted = _sortedEv(list);
        return sorted.isEmpty
            ? _empty()
            : RefreshIndicator(
                onRefresh: _refreshStations,
                color: AppColors.evGreen,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: sorted.length,
                  itemBuilder: (_, i) => _evCard(sorted[i]),
                ),
              );
      },
    );
  }

  // 전체: 주유소(거리순) → 충전소(거리순) 순으로 나열.
  Widget _buildAll() {
    final gasAsync = ref.watch(favGasStationsSortedProvider);
    final evAsync = ref.watch(favEvStationsSortedProvider);
    final List<GasStation> gas = gasAsync.valueOrNull ?? const <GasStation>[];
    final List<EvStation> ev = evAsync.valueOrNull ?? const <EvStation>[];

    if ((gasAsync.isLoading || evAsync.isLoading) && gas.isEmpty && ev.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (gas.isEmpty && ev.isEmpty) return _empty();

    return RefreshIndicator(
      onRefresh: _refreshStations,
      color: AppColors.gasBlue,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          for (final s in _sortedGas(gas)) _gasCard(s),
          for (final s in _sortedEv(ev)) _evCard(s),
        ],
      ),
    );
  }
}
