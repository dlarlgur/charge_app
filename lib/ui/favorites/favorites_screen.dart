import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../data/services/widget_service.dart';

/// 즐겨찾기 관리 서비스 (Hive 로컬 DB)
class FavoriteService {
  static final _box = Hive.box(AppConstants.favoritesBox);

  /// 즐겨찾기 추가
  static void add({required String id, required String type, required String name, required String subtitle}) {
    _box.put('${type}_$id', {
      'id': id,
      'type': type, // 'gas' or 'ev'
      'name': name,
      'subtitle': subtitle,
      'addedAt': DateTime.now().toIso8601String(),
    });
  }

  /// 즐겨찾기 삭제
  static void remove(String id, String type) {
    _box.delete('${type}_$id');
  }

  /// 즐겨찾기 여부 확인
  static bool isFavorite(String id, String type) {
    return _box.containsKey('${type}_$id');
  }

  /// 즐겨찾기 토글
  static bool toggle({required String id, required String type, required String name, required String subtitle}) {
    if (isFavorite(id, type)) {
      remove(id, type);
      return false;
    } else {
      add(id: id, type: type, name: name, subtitle: subtitle);
      return true;
    }
  }

  /// 전체 즐겨찾기 목록
  static List<Map<String, dynamic>> getAll() {
    return _box.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList()
      ..sort((a, b) => (b['addedAt'] ?? '').compareTo(a['addedAt'] ?? ''));
  }

  /// 타입별 즐겨찾기
  static List<Map<String, dynamic>> getByType(String type) {
    return getAll().where((f) => f['type'] == type).toList();
  }
}

/// 즐겨찾기 프로바이더
final favoritesProvider = StateNotifierProvider<FavoritesNotifier, List<Map<String, dynamic>>>((ref) {
  return FavoritesNotifier();
});

class FavoritesNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  FavoritesNotifier() : super(FavoriteService.getAll());

  void refresh() => state = FavoriteService.getAll();

  bool toggle({required String id, required String type, required String name, required String subtitle}) {
    final result = FavoriteService.toggle(id: id, type: type, name: name, subtitle: subtitle);
    state = FavoriteService.getAll();
    // 즐겨찾기 변경 시 위젯 데이터도 갱신
    if (type == 'gas') {
      WidgetService.updateGasWidget();
    } else if (type == 'ev') {
      WidgetService.updateEvWidget();
    }
    return result;
  }
}

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
