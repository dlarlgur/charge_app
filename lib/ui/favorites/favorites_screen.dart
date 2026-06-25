import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart'
    show
        favoritesProvider,
        bottomNavIndexProvider,
        favGasStationsSortedProvider,
        favEvStationsSortedProvider;
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
              Tab(text: '전체 (${favorites.length})'),
              Tab(text: '주유소 ($gasCount)'),
              Tab(text: '충전소 ($evCount)'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 리스트 — 홈과 동일 카드
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildAll(),
              _buildGas(),
              _buildEv(),
            ],
          ),
        ),
      ],
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

  Widget _buildGas() {
    final async = ref.watch(favGasStationsSortedProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _error(),
      data: (list) => list.isEmpty
          ? _empty()
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: list.length,
              itemBuilder: (_, i) => _gasCard(list[i]),
            ),
    );
  }

  Widget _buildEv() {
    final async = ref.watch(favEvStationsSortedProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _error(),
      data: (list) => list.isEmpty
          ? _empty()
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: list.length,
              itemBuilder: (_, i) => _evCard(list[i]),
            ),
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
        for (final s in gas) _gasCard(s),
        for (final s in ev) _evCard(s),
      ],
    );
  }
}
