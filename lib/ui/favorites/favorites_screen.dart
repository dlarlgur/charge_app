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
        favGasStationsSortedProvider,
        favEvStationsSortedProvider;
import '../../core/utils/navigation_util.dart';
import '../../core/app_dialog.dart';
import '../../core/util/app_toast.dart';
import '../../data/services/place_service.dart';
import '../../data/services/regular_station_service.dart';
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

  /// 카드·목록 공용 단골 토글 — 상세화면과 같은 흐름(등록 확인/만석 교체/해제 확인).
  Future<void> _toggleRegularFor(GasStation s) async {
    if (RegularStationService.contains(s.id)) {
      final ok = await showAppDialog<bool>(
        context,
        icon: Icons.loyalty_rounded,
        title: '단골주유소 해제',
        message: '${s.name}을(를) 단골주유소에서 해제할까요?',
        primaryLabel: '해제하기',
        primaryValue: true,
        secondaryLabel: '취소',
      );
      if (ok != true || !mounted) return;
      RegularStationService.remove(s.id);
      showAppToast(context, '단골주유소를 해제했어요');
      return;
    }
    if (RegularStationService.isFull) {
      final target = await showRegularReplacePicker(context, newName: s.name);
      if (target == null || !mounted) return;
      RegularStationService.replace(target.id,
          id: s.id, name: s.name, brand: s.brand);
      showAppToast(context, '단골주유소를 교체했어요');
      return;
    }
    final ok = await showAppDialog<bool>(
      context,
      icon: Icons.loyalty_rounded,
      title: '단골주유소 등록',
      message: '${s.name}을(를) 단골주유소로 등록할까요?\n${RegularStationService.copyLine}.',
      primaryLabel: '단골로 등록',
      primaryValue: true,
      secondaryLabel: '취소',
    );
    if (ok != true || !mounted) return;
    RegularStationService.add(id: s.id, name: s.name, brand: s.brand);
    showAppToast(context, '단골주유소로 등록했어요');
  }

  /// 주유소 탭 상단 단골 섹션 — 등록분 목록(개별 해제) 또는 등록 유도 안내.
  List<Widget> _regularSection(List<RegularStation> regs, bool isDark) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final accent = isDark ? AppColors.gasBlue : AppColors.gasBlueDark;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
        child: Row(
          children: [
            const Icon(Icons.loyalty_rounded,
                size: 15, color: AppColors.gasBlue),
            const SizedBox(width: 5),
            Text('단골주유소',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary)),
            const Spacer(),
            Text('${regs.length}/${RegularStationService.maxCount}',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: muted)),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Text('${RegularStationService.copyLine}.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, height: 1.4, color: muted)),
      ),
      if (regs.isEmpty)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color:
                    isDark ? AppColors.darkCardBorder : const Color(0xFFE8ECF0),
                width: 0.8),
          ),
          child: Text('아직 단골이 없어요. 아래 목록이나 주유소 상세화면에서 단골로 지정해보세요.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: muted)),
        )
      else
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
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.loyalty_rounded,
                          size: 18, color: accent),
                    ),
                    const SizedBox(width: 11),
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
      const SizedBox(height: 6),
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
        // 단골 상태 변경(등록/교체/해제) 시 섹션·카드 배지가 즉시 따라오게 구독.
        return ValueListenableBuilder<List<RegularStation>>(
          valueListenable: RegularStationService.notifier,
          builder: (context, regs, _) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              ..._regularSection(regs, isDark),
              if (sorted.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: _empty(),
                )
              else
                for (final s in sorted)
                  GasStationCard(
                    station: s,
                    onTap: () => context.push('/gas/${s.id}', extra: s),
                    isRegular: regs.any((r) => r.id == s.id),
                    onRegularToggle: () => _toggleRegularFor(s),
                  ),
            ],
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
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: sorted.length,
                itemBuilder: (_, i) => _evCard(sorted[i]),
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

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (final s in _sortedGas(gas)) _gasCard(s),
        for (final s in _sortedEv(ev)) _evCard(s),
      ],
    );
  }
}
