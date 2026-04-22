import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/favorite_service.dart';
import '../../providers/providers.dart' show favoritesProvider, FavoritesNotifier;

/// 즐겨찾기 화면
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});
  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> with SingleTickerProviderStateMixin {
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
    final gasList = favorites.where((f) => f['type'] == 'gas').toList();
    final evList = favorites.where((f) => f['type'] == 'ev').toList();

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
            unselectedLabelColor: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: [
              Tab(text: '전체 (${favorites.length})'),
              Tab(text: '주유소 (${gasList.length})'),
              Tab(text: '충전소 (${evList.length})'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 리스트
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildList(favorites, isDark),
              _buildList(gasList, isDark),
              _buildList(evList, isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<Map<String, dynamic>> items, bool isDark) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border_rounded, size: 56,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
            const SizedBox(height: 12),
            Text('즐겨찾기가 없습니다', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text('주유소/충전소 상세에서 하트를 눌러주세요', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final isEv = item['type'] == 'ev';
        final accentColor = isEv ? AppColors.evGreen : AppColors.gasBlue;

        return Dismissible(
          key: Key('${item['type']}_${item['id']}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
          ),
          onDismissed: (_) {
            ref.read(favoritesProvider.notifier).toggle(
              id: item['id'], type: item['type'], name: item['name'], subtitle: item['subtitle'] ?? '',
            );
          },
          child: GestureDetector(
            onTap: () {
              if (isEv) {
                context.push('/ev/${item['id']}');
              } else {
                context.push('/gas/${item['id']}');
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder, width: 0.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: isEv
                          ? (isDark ? AppColors.darkEvIconBg : AppColors.lightEvIconBg)
                          : (isDark ? AppColors.darkIconBg : AppColors.lightIconBg),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isEv ? Icons.ev_station_rounded : Icons.local_gas_station_rounded,
                      size: 18, color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['name'] ?? '', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(item['subtitle'] ?? '', style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                  Icon(Icons.favorite_rounded, size: 20, color: accentColor),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
