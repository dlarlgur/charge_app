import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' show TemplateType;
import '../../core/theme/app_colors.dart';
import '../../core/utils/helpers.dart';
import '../../core/constants/api_constants.dart';
import '../../data/models/models.dart';
import '../../data/services/ad_service.dart';
import '../../data/services/alert_service.dart';
import '../../data/services/notification_service.dart';
import '../../providers/providers.dart';
import '../ai/ai_main_screen.dart';
import '../map/map_screen.dart';
import '../widgets/native_ad_card.dart';
import '../widgets/popup_ad_dialog.dart';
import '../widgets/popup_notice_dialog.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/watch_session_bar.dart';
import '../../data/services/watch_service.dart';
import '../filter/gas_filter_sheet.dart';
import '../filter/ev_filter_sheet.dart';
import '../../data/services/favorite_service.dart';
import '../favorites/favorites_screen.dart';
import '../detail/ev_detail_screen.dart';
import '../detail/gas_detail_screen.dart';
import 'package:home_widget/home_widget.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final _messageBadgeKey = GlobalKey<_HomeTabState>();
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AlertService().refreshToken();
    WatchService().restore();

    // 로컬 알림 "상세보기" 액션 탭 → 알림 페이지로 이동
    navigateToAlertsNotifier.addListener(_onNavigateToAlerts);

    // 포그라운드 FCM 메시지 수신 → 로컬 알림 표시 + 내역 저장
    FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'gas_price_alert') {
        showGasPriceNotification(message.data, soundMode: AlertService().alertSoundMode);
        AlertService().addGasPriceMessage(message.data);
        _messageBadgeKey.currentState?.refreshCount();
      } else if (message.data['type'] == 'ev_alarm') {
        showEvAlarmNotification(message.data, soundMode: AlertService().evAlarmSoundMode);
        AlertService().addEvAlarmMessage(message.data);
        _messageBadgeKey.currentState?.refreshCount();
      } else if (message.data['type'] == 'ev_watch') {
        final stationId = message.data['stationId'] as String? ?? '';
        final newAvail = int.tryParse(message.data['newAvail'] as String? ?? '') ?? 0;
        if (stationId.isNotEmpty) WatchService().updateCurrentAvail(stationId, newAvail);
      }
    });

    // 로컬 알림(ev_alarm) 탭 → 충전소 상세로 이동
    navigateToEvStationNotifier.addListener(_onNavigateToEvStation);
    // 홈 위젯(주유소) 탭 → 주유소 상세로 이동
    navigateToGasStationNotifier.addListener(_onNavigateToGasStation);
    // 앱 종료 상태에서 알림/위젯 탭 시: 리스너 등록 전에 이미 값이 세팅됐을 수 있으므로 초기값 체크
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigateToEvStationNotifier.value.isNotEmpty) {
        _onNavigateToEvStation();
      }
      if (navigateToGasStationNotifier.value.isNotEmpty) {
        _onNavigateToGasStation();
      }
    });

    // 홈 팝업: 공지(type=popup) 우선, 없으면 광고 (둘 다 하루 1회 한도)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 400), () async {
        if (!mounted) return;
        await PopupNoticeDialog.showIfEligible(context);
        if (!mounted) return;
        await PopupAdDialog.showIfEligible(context);
      });
    });

    // 백그라운드 알림 탭해서 앱 열린 경우 (앱이 이미 실행 중)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (message.data['type'] == 'gas_price_alert') {
        AlertService().addGasPriceMessage(message.data);
        _messageBadgeKey.currentState?.refreshCount();
        if (mounted) _openAlertsPage();
      } else if (message.data['type'] == 'ev_alarm') {
        AlertService().addEvAlarmMessage(message.data);
        _messageBadgeKey.currentState?.refreshCount();
        final stationId = message.data['stationId'] as String? ?? '';
        if (stationId.isNotEmpty && mounted) {
          Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
            builder: (_) => EvDetailScreen(stationId: stationId),
          ));
        }
      } else if (message.data['type'] == 'ev_watch') {
        final stationId = message.data['stationId'] as String? ?? '';
        final newAvail = int.tryParse(message.data['newAvail'] as String? ?? '') ?? 0;
        if (stationId.isNotEmpty) {
          WatchService().updateCurrentAvail(stationId, newAvail);
          if (mounted) {
            Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
              builder: (_) => EvDetailScreen(stationId: stationId),
            ));
          }
        }
      }
    });

    // 앱이 종료된 상태에서 알림 탭해서 열린 경우 (앱 새로 시작)
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message == null) return;
      if (message.data['type'] == 'gas_price_alert') {
        AlertService().addGasPriceMessage(message.data);
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) _openAlertsPage();
        });
      } else if (message.data['type'] == 'ev_alarm') {
        AlertService().addEvAlarmMessage(message.data);
        final stationId = message.data['stationId'] as String? ?? '';
        if (stationId.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) {
              Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                builder: (_) => EvDetailScreen(stationId: stationId),
              ));
            }
          });
        }
      } else if (message.data['type'] == 'ev_watch') {
        final stationId = message.data['stationId'] as String? ?? '';
        if (stationId.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) {
              Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                builder: (_) => EvDetailScreen(stationId: stationId),
              ));
            }
          });
        }
      }
    });

  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    navigateToAlertsNotifier.removeListener(_onNavigateToAlerts);
    navigateToEvStationNotifier.removeListener(_onNavigateToEvStation);
    navigateToGasStationNotifier.removeListener(_onNavigateToGasStation);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // 앱이 포그라운드로 돌아올 때 위젯 딥링크 대기값 소비
      _consumeWidgetPendingOnResume();
    }
  }

  Future<void> _consumeWidgetPendingOnResume() async {
    try {
      final type = await HomeWidget.getWidgetData<String>('widget_pending_type');
      if (type == null || type.isEmpty) return;
      final stationId = await HomeWidget.getWidgetData<String>(
          'widget_pending_station_id');
      await HomeWidget.saveWidgetData<String>('widget_pending_type', '');
      await HomeWidget.saveWidgetData<String>(
          'widget_pending_station_id', '');
      if (stationId == null || stationId.isEmpty) return;
      if (type == 'ev') {
        navigateToEvStationNotifier.value = stationId;
      } else if (type == 'gas') {
        navigateToGasStationNotifier.value = stationId;
      }
    } catch (_) {}
  }

  void _onNavigateToAlerts() => _openAlertsPage();

  void _onNavigateToEvStation() {
    final stationId = navigateToEvStationNotifier.value;
    if (stationId.isEmpty || !mounted) return;
    navigateToEvStationNotifier.value = ''; // 중복 이동 방지
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => EvDetailScreen(stationId: stationId),
    ));
  }

  void _onNavigateToGasStation() {
    final stationId = navigateToGasStationNotifier.value;
    if (stationId.isEmpty || !mounted) return;
    navigateToGasStationNotifier.value = '';
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => GasDetailScreen(stationId: stationId),
    ));
  }

  void _openAlertsPage() {
    if (!mounted) return;
    AlertService().markAllRead();
    _messageBadgeKey.currentState?.refreshCount();
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => _AlertPage(
        onChanged: () => _messageBadgeKey.currentState?.refreshCount(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottomIndex = ref.watch(bottomNavIndexProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // AI 탭(index 2)은 AiMainScreen 자체 PopScope가 처리
        final currentTab = ref.read(bottomNavIndexProvider);
        if (currentTab == 2) return;
        // 지도 시트가 열려있으면 MapScreen의 PopScope가 처리 중 → 토스트 띄우지 않음
        if (mapSheetOpen.value) return;

        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '한 번 더 누르시면 종료됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF2D3748).withValues(alpha: 0.95),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              margin: const EdgeInsets.only(bottom: 8, left: 40, right: 40),
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      body: Column(
        children: [
          if (bottomIndex == 0) const WatchSessionBar(),
          Expanded(
            child: IndexedStack(
              index: bottomIndex,
              children: [
                _HomeTab(key: _messageBadgeKey),
                const _MapTab(),
                const AiMainScreen(),
                const _FavoritesTab(),
                const _SettingsTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 64,
          backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
          surfaceTintColor: Colors.transparent,
          indicatorColor: (isDark ? AppColors.gasBlue : AppColors.gasBlueDark)
              .withValues(alpha: 0.18),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final isSelected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? (isDark ? AppColors.gasBlue : AppColors.gasBlueDark)
                  : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final isSelected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 24,
              color: isSelected
                  ? (isDark ? AppColors.gasBlue : AppColors.gasBlueDark)
                  : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
            );
          }),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        child: NavigationBar(
          selectedIndex: bottomIndex,
          onDestinationSelected: (i) {
            HapticFeedback.selectionClick();
            ref.read(bottomNavIndexProvider.notifier).state = i;
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: '홈',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: '지도',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome_rounded),
              label: 'AI',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_outline_rounded),
              selectedIcon: Icon(Icons.favorite_rounded),
              label: '즐겨찾기',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: '설정',
            ),
          ],
        ),
      ),
    ),
    );
  }
}

// ─── 홈 탭 ───
class _HomeTab extends ConsumerStatefulWidget {
  const _HomeTab({super.key});
  @override
  ConsumerState<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<_HomeTab> {
  int _msgCount = 0;

  @override
  void initState() {
    super.initState();
    _msgCount = AlertService().unreadCount;
  }

  void refreshCount() {
    if (mounted) setState(() => _msgCount = AlertService().unreadCount);
  }

  void _openAlertSheet() {
    AlertService().markAllRead();
    refreshCount();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => _AlertPage(onChanged: refreshCount),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final vehicleType = settings.vehicleType;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 차량 타입에 따라 activeTab 강제 지정
    final activeTab = vehicleType == VehicleType.ev ? 1 : ref.watch(activeTabProvider);
    final showTab = vehicleType == VehicleType.both;

    return SafeArea(
      child: Column(
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Row(
              children: [
                Image.asset(
                  'assets/logo_circles.png',
                  width: 32,
                  height: 32,
                  filterQuality: FilterQuality.medium,
                ),
                const SizedBox(width: 10),
                Text('모두의 주유충전', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                Builder(builder: (_) {
                  final hasUnread = _msgCount > 0;
                  final bellColor = hasUnread
                      ? AppColors.gasBlue
                      : (isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Material(
                      color: hasUnread
                          ? AppColors.gasBlue.withValues(alpha: 0.10)
                          : (isDark
                              ? const Color(0x14FFFFFF)
                              : const Color(0xFFF1F5F9)),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _openAlertSheet,
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                hasUnread
                                    ? Icons.notifications_rounded
                                    : Icons.notifications_none_rounded,
                                size: 22,
                                color: bellColor,
                              ),
                              if (hasUnread)
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isDark
                                            ? AppColors.darkBg
                                            : Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // 탭 바 (둘 다 사용일 때만 표시)
          if (showTab) ...[
            GasEvTabBar(
              activeIndex: activeTab,
              onChanged: (i) => ref.read(activeTabProvider.notifier).state = i,
            ),
            const SizedBox(height: 4),
          ],
          // 리스트 (둘 다 모드는 IndexedStack으로 백그라운드 프리로드)
          // top 배너는 각 list view 의 첫 sliver 로 들어가 리스트와 함께 스크롤됨
          Expanded(
            child: vehicleType == VehicleType.ev
                ? const _EvListView()
                : vehicleType == VehicleType.gas
                    ? const _GasListView()
                    : GestureDetector(
                        onHorizontalDragEnd: (details) {
                          final dx = details.primaryVelocity ?? 0;
                          if (dx > 300 && activeTab == 0) {
                            // 오른쪽 스와이프 → 충전
                            ref.read(activeTabProvider.notifier).state = 1;
                          } else if (dx < -300 && activeTab == 1) {
                            // 왼쪽 스와이프 → 주유
                            ref.read(activeTabProvider.notifier).state = 0;
                          }
                        },
                        child: IndexedStack(
                          index: activeTab,
                          children: const [_GasListView(), _EvListView()],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── 주유소 리스트 뷰 ───
class _GasListView extends ConsumerStatefulWidget {
  const _GasListView();
  @override
  ConsumerState<_GasListView> createState() => _GasListViewState();
}

class _GasListViewState extends ConsumerState<_GasListView> {
  static const _pageSize = 50;
  int _displayCount = _pageSize;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        setState(() => _displayCount += _pageSize);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(gasStationsProvider);
    final filter = ref.watch(gasFilterProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() { _displayCount = _pageSize; _searchQuery = ''; _searchController.clear(); });
        ref.invalidate(locationProvider);
        ref.invalidate(gasStationsRawProvider);
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // 검색 + 필터 버튼
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : AppColors.lightCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 10),
                          Icon(Icons.search_rounded, size: 17,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (v) => setState(() { _searchQuery = v; _displayCount = _pageSize; }),
                              decoration: InputDecoration(
                                hintText: '주유소 검색',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                hintStyle: TextStyle(fontSize: 13,
                                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                              ),
                              style: TextStyle(fontSize: 13,
                                  color: isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () => setState(() { _searchQuery = ''; _searchController.clear(); }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(Icons.close_rounded, size: 15,
                                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => GasFilterSheet.show(context),
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.gasBlue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tune_rounded, size: 15, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            filter.sort == 1 ? '가격순' : '거리순',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 상단 네이티브 배너 — 리스트와 함께 스크롤됨 (고정 X)
          SliverToBoxAdapter(
            child: NativeAdCard(
              adUnitId: AdUnitIds.topBanner,
              slot: HouseAdSlot.homeTop,
              type: TemplateType.small,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            ),
          ),
          // 요약 카드
          SliverToBoxAdapter(
            child: stationsAsync.when(
              loading: () => const GasSummaryCard(avgPrice: 0, priceDiff: 0),
              error: (_, __) => const GasSummaryCard(avgPrice: 0, priceDiff: 0),
              data: (stations) {
                final avgPrice = stations.isEmpty ? 0.0
                    : stations.map((s) => s.price).reduce((a, b) => a + b) / stations.length;
                final avgAsync = ref.watch(gasAvgPriceProvider);
                final fuelCode = filter.fuelTypes.isNotEmpty ? filter.fuelTypes.first : 'B027';
                final fuelLabel = FuelType.fromCode(fuelCode).label;
                final priceDiff = avgAsync.when(
                  data: (m) {
                    final row = m[fuelCode];
                    if (row is! Map) return 0.0;
                    return parseApiDouble(row['diff']);
                  },
                  loading: () => 0.0,
                  error: (_, __) => 0.0,
                );
                return GasSummaryCard(avgPrice: avgPrice, priceDiff: priceDiff, fuelLabel: fuelLabel);
              },
            ),
          ),
          // 리스트
          stationsAsync.when(
            loading: () => SliverList(delegate: SliverChildBuilderDelegate(
              (_, __) => const SkeletonCard(), childCount: 6,
            )),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.darkTextMuted),
                  const SizedBox(height: 12),
                  Text('데이터를 불러올 수 없습니다', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => ref.invalidate(gasStationsRawProvider), child: const Text('다시 시도')),
                ]),
              )),
            ),
            data: (stations) {
              var filtered = _searchQuery.isEmpty ? stations
                  : stations.where((s) =>
                      s.name.contains(_searchQuery) ||
                      s.address.contains(_searchQuery)).toList();
              if (filtered.isEmpty) {
                return SliverToBoxAdapter(
                  child: Center(child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(_searchQuery.isEmpty ? '주변에 주유소가 없습니다' : '\'$_searchQuery\' 검색 결과가 없습니다',
                        style: Theme.of(context).textTheme.bodyMedium),
                  )),
                );
              }
              // provider에서 즐겨찾기 상위 정렬 + 필터 면제 처리됨
              final favIds = FavoriteService.getByType('gas').map((f) => f['id'] as String).toSet();
              final shown = filtered.take(_displayCount).toList();
              const adAt = 2; // 0,1 = 주유소, 2 = 광고, 3+ = 주유소 (즉 3번째 위치)
              final showAd = shown.length >= 3;
              return SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) {
                  if (showAd && i == adAt) {
                    return NativeAdCard(
                      adUnitId: AdUnitIds.listBanner,
                      slot: HouseAdSlot.homeList,
                      type: TemplateType.medium,
                    );
                  }
                  final stationIdx = (showAd && i > adAt) ? i - 1 : i;
                  final s = shown[stationIdx];
                  return GasStationCard(
                    station: s,
                    isTop: stationIdx == 0 && favIds.isEmpty,
                    topBadgeLabel: filter.sort == 1 ? '최저가' : '최단거리',
                    onTap: () => context.push('/gas/${s.id}', extra: s),
                  );
                },
                childCount: shown.length + (showAd ? 1 : 0),
              ));
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }
}

// ─── 충전소 리스트 뷰 ───
class _EvListView extends ConsumerStatefulWidget {
  const _EvListView();
  @override
  ConsumerState<_EvListView> createState() => _EvListViewState();
}

class _EvListViewState extends ConsumerState<_EvListView> {
  static const _pageSize = 50;
  int _displayCount = _pageSize;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        setState(() => _displayCount += _pageSize);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(evStationsProvider);
    final filter = ref.watch(evFilterProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() { _displayCount = _pageSize; _searchQuery = ''; _searchController.clear(); });
        ref.invalidate(locationProvider);
        ref.invalidate(evStationsRawProvider);
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // 검색 + 필터 버튼
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : AppColors.lightCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 10),
                          Icon(Icons.search_rounded, size: 17,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (v) => setState(() { _searchQuery = v; _displayCount = _pageSize; }),
                              decoration: InputDecoration(
                                hintText: '충전소 검색',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                hintStyle: TextStyle(fontSize: 13,
                                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                              ),
                              style: TextStyle(fontSize: 13,
                                  color: isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () => setState(() { _searchQuery = ''; _searchController.clear(); }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(Icons.close_rounded, size: 15,
                                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => EvFilterSheet.show(context),
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.evGreen,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tune_rounded, size: 15, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            filter.sort == 1 ? '거리순' : '가격순',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 상단 네이티브 배너 — 리스트와 함께 스크롤됨
          SliverToBoxAdapter(
            child: NativeAdCard(
              adUnitId: AdUnitIds.topBanner,
              slot: HouseAdSlot.homeTop,
              type: TemplateType.small,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            ),
          ),
          // 요약 카드
          SliverToBoxAdapter(
            child: stationsAsync.when(
              loading: () => const EvSummaryCard(totalStations: 0, availableStations: 0),
              error: (_, __) => const EvSummaryCard(totalStations: 0, availableStations: 0),
              data: (stations) => EvSummaryCard(
                totalStations: stations.length,
                availableStations: stations.where((s) => s.hasAvailable).length,
              ),
            ),
          ),
          // 리스트
          stationsAsync.when(
            loading: () => SliverList(delegate: SliverChildBuilderDelegate(
              (_, __) => const SkeletonCard(), childCount: 6,
            )),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.darkTextMuted),
                  const SizedBox(height: 12),
                  Text('데이터를 불러올 수 없습니다', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => ref.invalidate(evStationsRawProvider), child: const Text('다시 시도')),
                ]),
              )),
            ),
            data: (stations) {
              var filtered = _searchQuery.isEmpty ? stations
                  : stations.where((s) =>
                      s.name.contains(_searchQuery) ||
                      s.address.contains(_searchQuery) ||
                      s.operator.contains(_searchQuery)).toList();
              if (filtered.isEmpty) {
                return SliverToBoxAdapter(
                  child: Center(child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(_searchQuery.isEmpty ? '주변에 충전소가 없습니다' : '\'$_searchQuery\' 검색 결과가 없습니다',
                        style: Theme.of(context).textTheme.bodyMedium),
                  )),
                );
              }
              // provider에서 즐겨찾기 상위 정렬 + 필터 면제 처리됨
              final favIds = FavoriteService.getByType('ev').map((f) => f['id'] as String).toSet();
              final shown = filtered.take(_displayCount).toList();
              const adAt = 2; // 3번째 위치
              final showAd = shown.length >= 3;
              return SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) {
                  if (showAd && i == adAt) {
                    return NativeAdCard(
                      adUnitId: AdUnitIds.listBanner,
                      slot: HouseAdSlot.homeList,
                      type: TemplateType.medium,
                    );
                  }
                  final stationIdx = (showAd && i > adAt) ? i - 1 : i;
                  final s = shown[stationIdx];
                  return EvStationCard(
                    station: s,
                    isTop: stationIdx == 0 && favIds.isEmpty,
                    onTap: () => context.push('/ev/${s.statId}', extra: s),
                  );
                },
                childCount: shown.length + (showAd ? 1 : 0),
              ));
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }
}

// ─── 수신된 푸시 메시지 시트 ───
class _AlertPage extends StatefulWidget {
  final VoidCallback onChanged;
  const _AlertPage({required this.onChanged});
  @override
  State<_AlertPage> createState() => _AlertPageState();
}

class _AlertPageState extends State<_AlertPage> {
  late List<Map<String, dynamic>> _messages;
  bool _selectionMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _messages = AlertService().receivedMessages;
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selected.add(id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selected.length == _messages.length) {
        _selected.clear();
      } else {
        _selected.addAll(_messages.map((m) => m['id'] as String));
      }
    });
  }

  void _deleteOne(String id) {
    AlertService().deleteMessage(id);
    setState(() => _messages.removeWhere((m) => m['id'] == id));
    widget.onChanged();
  }

  void _deleteSelected() {
    for (final id in _selected) {
      AlertService().deleteMessage(id);
    }
    setState(() {
      _messages.removeWhere((m) => _selected.contains(m['id'] as String));
      _selectionMode = false;
      _selected.clear();
    });
    widget.onChanged();
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전체 삭제'),
        content: const Text('받은 알림을 모두 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      AlertService().clearMessages();
      setState(() {
        _messages.clear();
        _selectionMode = false;
        _selected.clear();
      });
      widget.onChanged();
    }
  }

  Future<void> _confirmDeleteSelected() async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('선택 삭제'),
        content: Text('선택한 알림 $count개를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) _deleteSelected();
  }

  Widget _buildAlertBody(String body, Color mutedColor, bool isDark) {
    final primaryColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final lines = body.split('\n');
    final spans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final suffix = i < lines.length - 1 ? '\n' : '';
      if (line.startsWith('★')) {
        // 최저가 주유소명 → 파란색 볼드
        spans.add(TextSpan(
          text: line + suffix,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.gasBlue,
            height: 1.65,
          ),
        ));
      } else if (line.startsWith('•')) {
        // 일반 주유소명 → 기본 볼드
        spans.add(TextSpan(
          text: line + suffix,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: primaryColor,
            height: 1.65,
          ),
        ));
      } else {
        // 가격 라인 → 뮤트 색상, 일반 굵기
        spans.add(TextSpan(
          text: line + suffix,
          style: TextStyle(fontSize: 12.5, color: mutedColor, height: 1.6),
        ));
      }
    }
    return Text.rich(TextSpan(children: spans));
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return '방금';
      if (diff.inHours < 1) return '${diff.inMinutes}분 전';
      if (diff.inDays < 1) return '${diff.inHours}시간 전';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor =
        isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final dividerColor =
        isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0);
    final allSelected =
        _messages.isNotEmpty && _selected.length == _messages.length;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        elevation: 0,
        leading: _selectionMode
            ? TextButton(
                onPressed: _exitSelectionMode,
                child: const Text('취소',
                    style: TextStyle(fontSize: 14, color: AppColors.gasBlue)),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
        title: Text(
          _selectionMode
              ? (_selected.isEmpty ? '선택' : '${_selected.length}개 선택')
              : '알림',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: _selectionMode
            ? [
                TextButton(
                  onPressed: _toggleSelectAll,
                  child: Text(allSelected ? '전체 해제' : '전체 선택',
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.gasBlue)),
                ),
                TextButton(
                  onPressed:
                      _selected.isEmpty ? null : _confirmDeleteSelected,
                  child: Text('삭제',
                      style: TextStyle(
                          fontSize: 14,
                          color: _selected.isEmpty
                              ? mutedColor
                              : Colors.redAccent)),
                ),
              ]
            : [
                if (_messages.isNotEmpty) ...[
                  TextButton(
                    onPressed: () => setState(() => _selectionMode = true),
                    child: Text('편집',
                        style: TextStyle(fontSize: 14, color: mutedColor)),
                  ),
                  TextButton(
                    onPressed: _confirmClearAll,
                    child: Text('전체 삭제',
                        style: TextStyle(fontSize: 14, color: mutedColor)),
                  ),
                ],
              ],
      ),
      body: _messages.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 56, color: mutedColor),
                  const SizedBox(height: 16),
                  Text('받은 알림이 없어요',
                      style: TextStyle(
                          fontSize: 15,
                          color: mutedColor,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Text('즐겨찾기 주유소를 등록하면\n매일 유가를 알려드려요',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: mutedColor)),
                ],
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                  0, 8, 0, MediaQuery.of(context).padding.bottom + 16),
              itemCount: _messages.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: dividerColor, indent: 72),
              itemBuilder: (_, i) {
                final msg = _messages[i];
                final id = msg['id'] as String;
                final body = (msg['body'] as String? ?? '').trim();
                final isSelected = _selected.contains(id);

                final tile = InkWell(
                  onTap: _selectionMode ? () => _toggleSelect(id) : null,
                  onLongPress: _selectionMode
                      ? null
                      : () => _enterSelectionMode(id),
                  child: Container(
                    color: isSelected
                        ? AppColors.gasBlue.withValues(alpha: 0.07)
                        : (isDark ? AppColors.darkCard : Colors.white),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_selectionMode)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Icon(
                              isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 22,
                              color: isSelected
                                  ? AppColors.gasBlue
                                  : mutedColor,
                            ),
                          )
                        else
                          Container(
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: AppColors.gasBlue.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.local_gas_station_rounded,
                                color: AppColors.gasBlue, size: 20),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      msg['title'] ?? '',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Text(
                                    _formatTime(
                                        msg['timestamp'] as String?),
                                    style: TextStyle(
                                        fontSize: 11, color: mutedColor),
                                  ),
                                ],
                              ),
                              if (body.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _buildAlertBody(body, mutedColor, isDark),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                if (_selectionMode) return tile;

                return Dismissible(
                  key: ValueKey(id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.redAccent,
                    child: const Icon(Icons.delete_outline_rounded,
                        color: Colors.white),
                  ),
                  onDismissed: (_) => _deleteOne(id),
                  child: tile,
                );
              },
            ),
    );
  }
}

String _fuelTypesLabel(List<String> fuelTypes) {
  if (fuelTypes.isEmpty) return '휘발유';
  final first = FuelType.fromCode(fuelTypes.first).label;
  if (fuelTypes.length == 1) return first;
  return '$first 외 ${fuelTypes.length - 1}';
}

// 필터 칩 공통 라벨: 전체면 기본명, 1개면 항목명, 복수면 "첫번째 외 N"
String _chipLabel(List<String> items, String Function(String) labelFn, String defaultLabel) {
  if (items.isEmpty) return defaultLabel;

  // 코드가 여러 개여도 같은 라벨(예: A0/G0 둘 다 '공공기관')이면
  // 한 개로 취급하기 위해 라벨 기준으로 중복 제거
  final labels = items.map(labelFn).toSet().toList();
  final first = labels.first;
  // 충전장소: 모든 종류가 선택된 경우에는 기본 라벨("충전장소")로 표기
  if (defaultLabel == '충전장소' && labels.length >= 6) {
    return defaultLabel;
  }
  if (labels.length == 1) return first;
  return '$first 외 ${labels.length - 1}';
}

String _brandLabel(String brand) {
  switch (brand) {
    case 'SKE': return 'SK에너지';
    case 'GSC': return 'GS칼텍스';
    case 'HDO': return '현대오일뱅크';
    case 'SOL': return 'S-OIL';
    case 'NHO': return 'NH주유소';
    case 'E1G': return 'E1에너지';
    case 'RTO': return '알뜰주유소';
    case 'ETC': return '기타';
    default: return brand;
  }
}

String _kindLabel(String kind) {
  switch (kind) {
    case 'A0': case 'G0': return '공공기관';
    case 'B0': return '공영주차';
    case 'C0': return '고속도로';
    case 'D0': case 'E0': case 'F0': case 'I0': return '일반충전소';
    case 'H0': return '숙박시설';
    case 'J0': return '아파트';
    default: return kind;
  }
}

String _chargerTypeLabel(String type) {
  switch (type) {
    case '01': return 'DC차데모';
    case '02': return 'AC완속';
    case '03': return 'DC차데모+AC3상';
    case '04': return 'DC콤보';
    case '05': return 'DC차데모+DC콤보';
    case '06': return 'DC차데모+AC3상+DC콤보';
    case '07': return 'AC3상';
    case '08': return 'DC콤보(저속)';
    case '09': return 'NACS';
    case '89': return 'H2(수소)';
    case 'SC': return '슈퍼차저';
    case 'DT': return '데스티네이션';
    default: return type;
  }
}

// ─── 지도 탭 ───
class _MapTab extends StatelessWidget {
  const _MapTab();
  @override
  Widget build(BuildContext context) {
    return const MapScreen();
  }
}

// ─── 즐겨찾기 탭 ───
class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab();
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('즐겨찾기', style: Theme.of(context).textTheme.headlineSmall),
            ),
          ),
          const Expanded(child: FavoritesScreen()),
        ],
      ),
    );
  }
}


// ─── 설정 탭 래퍼 ───
class _SettingsTab extends StatelessWidget {
  const _SettingsTab();
  @override
  Widget build(BuildContext context) {
    return const SettingsScreenEmbed();
  }
}

/// 설정 화면 임베드 (홈 탭에서 사용)
class SettingsScreenEmbed extends ConsumerWidget {
  const SettingsScreenEmbed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Text('설정', style: Theme.of(context).textTheme.headlineSmall),
          ),
          _sectionHeader(context, '차량 설정'),
          _tile(context, isDark, Icons.directions_car_rounded, '차량 타입', settings.vehicleType.label, () {
            _showPicker(context, '차량 타입', VehicleType.values.map((t) => t.label).toList(),
              VehicleType.values.indexOf(settings.vehicleType),
              (i) => ref.read(settingsProvider.notifier).setVehicleType(VehicleType.values[i]));
          }),
          if (settings.vehicleType != VehicleType.ev)
            _tile(context, isDark, Icons.local_gas_station_rounded, '유종', settings.fuelType.label, () {
              _showPicker(context, '유종', FuelType.values.map((t) => t.label).toList(),
                FuelType.values.indexOf(settings.fuelType),
                (i) => ref.read(settingsProvider.notifier).setFuelType(FuelType.values[i]));
            }),
          const SizedBox(height: 16),
          _sectionHeader(context, '알림'),
          _AlertSettingTileEmbed(isDark: isDark),
          _EvAlarmSettingTileEmbed(isDark: isDark),
          const SizedBox(height: 16),
          _sectionHeader(context, '앱 설정'),
          _tile(context, isDark, Icons.dark_mode_rounded, '테마',
            themeMode == ThemeMode.dark ? '다크' : '라이트', () {
              const modes = [ThemeMode.light, ThemeMode.dark];
              _showPicker(context, '테마', ['라이트 모드', '다크 모드'],
                modes.indexOf(themeMode == ThemeMode.system ? ThemeMode.light : themeMode),
                (i) => ref.read(themeModeProvider.notifier).setTheme(modes[i]));
          }),
          const SizedBox(height: 16),
          _SupportEmbed(isDark: isDark),
          _sectionHeader(context, '정보'),
          _tile(
            context, isDark, Icons.description_outlined, '정책 및 약관',
            '', () => context.push('/policies'),
          ),
          _tile(
            context, isDark, Icons.info_outline_rounded, '앱 버전',
            DkswCore.appVersion, null,
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Text(
              '유가 정보 출처: 한국석유공사 오피넷(www.opinet.co.kr)\n충전소 정보 출처: 환경부 전기차 충전소 공공데이터',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.gasBlue)),
    );
  }

  Widget _tile(BuildContext context, bool isDark, IconData icon, String title, String value, VoidCallback? onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(icon, size: 22, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
        if (onTap != null) Icon(Icons.chevron_right_rounded, size: 20,
            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
      ]),
      onTap: onTap,
    );
  }

  void _showPicker(BuildContext context, String title, List<String> options, int selected, ValueChanged<int> onSelect) {
    showModalBottomSheet(context: context, builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...List.generate(options.length, (i) => ListTile(
          title: Text(options[i]),
          trailing: i == selected ? const Icon(Icons.check, color: AppColors.gasBlue) : null,
          onTap: () { onSelect(i); Navigator.pop(context); },
        )),
        const SizedBox(height: 16),
      ]),
    ));
  }
}

// ─── 고객 지원 (공지/이벤트/FAQ) ───
class _SupportCountsEmbed {
  final int notices;
  final int events;
  final int faqs;
  const _SupportCountsEmbed(this.notices, this.events, this.faqs);
}

class _SupportEmbed extends StatefulWidget {
  final bool isDark;
  const _SupportEmbed({required this.isDark});
  @override
  State<_SupportEmbed> createState() => _SupportEmbedState();
}

class _SupportEmbedState extends State<_SupportEmbed> {
  late Future<_SupportCountsEmbed> _future;

  @override
  void initState() {
    super.initState();
    debugPrint('[SupportEmbed] initState → fetch');
    _future = _load();
  }

  Future<_SupportCountsEmbed> _load() async {
    final r = await Future.wait([
      DkswCore.fetchNotices(),
      DkswCore.fetchEvents(),
      DkswCore.fetchFaqs(),
    ]);
    final c = _SupportCountsEmbed(
      (r[0] as List).length,
      (r[1] as List).length,
      (r[2] as List).length,
    );
    debugPrint('[SupportEmbed] fetched: n=${c.notices} e=${c.events} f=${c.faqs}');
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final boot = DkswCore.lastBootstrap?.counts;
    final seed = boot == null
        ? null
        : _SupportCountsEmbed(boot.notices, boot.events, boot.faqs);
    return FutureBuilder<_SupportCountsEmbed>(
      future: _future,
      initialData: seed,
      builder: (context, snap) {
        final c = snap.data;
        if (c == null) return const SizedBox.shrink();
        final hasN = c.notices > 0;
        final hasE = c.events > 0;
        final hasF = c.faqs > 0;
        if (!hasN && !hasE && !hasF) return const SizedBox.shrink();
        final isDark = widget.isDark;
        final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
        final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

        Widget tile(IconData icon, String title, int count, String route) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: Icon(icon, size: 22, color: secondary),
          title: Text(title, style: Theme.of(context).textTheme.titleSmall),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$count', style: TextStyle(fontSize: 13, color: muted)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20, color: muted),
          ]),
          onTap: () => context.push(route),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text('고객 지원',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.gasBlue)),
            ),
            if (hasN) tile(Icons.campaign_rounded, '공지사항', c.notices, '/notices'),
            if (hasE) tile(Icons.celebration_rounded, '이벤트', c.events, '/events'),
            if (hasF) tile(Icons.help_outline_rounded, '자주 묻는 질문', c.faqs, '/faq'),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

// ─── 알림 설정 타일 (홈 설정 탭용) ───
class _AlertSettingTileEmbed extends StatefulWidget {
  final bool isDark;
  const _AlertSettingTileEmbed({required this.isDark});
  
  @override
  State<_AlertSettingTileEmbed> createState() => _AlertSettingTileEmbedState();
}

class _AlertSettingTileEmbedState extends State<_AlertSettingTileEmbed> {
  late bool _enabled;
  late List<String> _ids;
  late int _alertHour;
  late int _alertMinute;
  late int _soundMode; // 0=소리, 1=진동, 2=무음
  bool _expanded = false;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    AlertService().subsChanged.addListener(_refresh);
  }

  @override
  void dispose() {
    AlertService().subsChanged.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _enabled = AlertService().alertsEnabled;
      _ids = AlertService().subscribedStationIds;
      _alertHour = AlertService().alertHour;
      _alertMinute = AlertService().alertMinute;
      _soundMode = AlertService().alertSoundMode;
      if (_ids.isEmpty) _expanded = false;
    });
  }

  Future<void> _toggleEnabled(bool value) async {
    setState(() => _toggling = true);
    await AlertService().setAlertsEnabled(value);
    setState(() {
      _enabled = value;
      _toggling = false;
    });
  }

  Future<void> _pickAlertTime() async {
    final picked = await showDrumTimePicker(
      context,
      initial: TimeOfDay(hour: _alertHour, minute: _alertMinute),
    );
    if (picked == null || !mounted) return;
    await AlertService().setAlertTime(picked.hour, picked.minute);
    setState(() {
      _alertHour = picked.hour;
      _alertMinute = picked.minute;
    });
  }

  String get _alertTimeText =>
      '${_alertHour.toString().padLeft(2, '0')}:${_alertMinute.toString().padLeft(2, '0')}';

  Future<void> _unsubscribe(String id) async {
    await AlertService().unsubscribe(id);
    // _refresh()는 subsChanged 리스너가 자동 호출
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final secondaryColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: Icon(
            _enabled ? Icons.notifications_rounded : Icons.notifications_off_rounded,
            size: 22,
            color: _enabled ? AppColors.gasBlue : secondaryColor,
          ),
          title: Text('주유 가격 알림', style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            _enabled
                ? '${_ids.isEmpty ? '알림 주유소 없음' : '${_ids.length}곳 설정됨'} · 매일 $_alertTimeText 발송'
                : '알림 꺼짐',
            style: TextStyle(fontSize: 12, color: mutedColor),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_enabled)
                GestureDetector(
                  onTap: _pickAlertTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: AppColors.gasBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _alertTimeText,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.gasBlue),
                    ),
                  ),
                ),
              if (_ids.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: mutedColor),
                    ),
                  ),
                ),
              _toggling
                  ? const SizedBox(
                      width: 36, height: 20,
                      child: Center(child: SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))))
                  : Transform.scale(
                      scale: 0.85,
                      child: Switch(
                        value: _enabled,
                        onChanged: _toggleEnabled,
                        activeColor: AppColors.gasBlue,
                      ),
                    ),
            ],
          ),
          onTap: _ids.isNotEmpty ? () => setState(() => _expanded = !_expanded) : null,
        ),

        if (_enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Text('알림 방식',
                    style: TextStyle(fontSize: 12, color: mutedColor)),
                const SizedBox(width: 12),
                ...['소리', '진동', '무음'].asMap().entries.map((e) {
                  final idx = e.key;
                  final label = e.value;
                  final selected = _soundMode == idx;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        AlertService().setAlertSoundMode(idx);
                        setState(() => _soundMode = idx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.gasBlue.withValues(alpha: 0.15)
                              : (isDark ? const Color(0x0AFFFFFF) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? AppColors.gasBlue : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            color: selected ? AppColors.gasBlue : secondaryColor,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _expanded
              ? Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0x0AFFFFFF) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0x14FFFFFF) : const Color(0xFFE2E8F0),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    children: _ids.map((id) {
                      final name = AlertService().stationName(id);
                      final fuelTypes = AlertService().subscribedFuelTypes(id);
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
                        leading: Icon(Icons.local_gas_station_rounded,
                            size: 18, color: AppColors.gasBlue),
                        title: Text(name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        subtitle: fuelTypes.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Wrap(
                                  spacing: 4,
                                  children: fuelTypes.map((ft) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.gasBlue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(AlertService.fuelLabel(ft),
                                        style: const TextStyle(fontSize: 11, color: AppColors.gasBlue, fontWeight: FontWeight.w600)),
                                  )).toList(),
                                ),
                              )
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.redAccent, size: 20),
                          onPressed: () => _unsubscribe(id),
                        ),
                        onTap: () => showFuelTypeAlertSheet(
                          context,
                          stationId: id,
                          stationName: name,
                        ),
                      );
                    }).toList(),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ─── EV 충전소 현황 알림 설정 타일 (홈 설정 탭용) ───
class _EvAlarmSettingTileEmbed extends StatefulWidget {
  final bool isDark;
  const _EvAlarmSettingTileEmbed({required this.isDark});
  @override
  State<_EvAlarmSettingTileEmbed> createState() => _EvAlarmSettingTileEmbedState();
}

class _EvAlarmSettingTileEmbedState extends State<_EvAlarmSettingTileEmbed> {
  late List<String> _ids;
  late int _soundMode;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    AlertService().subsChanged.addListener(_refresh);
  }

  @override
  void dispose() {
    AlertService().subsChanged.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _ids = AlertService().evAlarmStationIds;
      _soundMode = AlertService().evAlarmSoundMode;
      if (_ids.isEmpty) _expanded = false;
    });
  }

  Future<void> _unsubscribe(String id) async {
    await AlertService().unsubscribeEvAlarm(id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final secondaryColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: Icon(
            Icons.ev_station_rounded,
            size: 22,
            color: _ids.isEmpty ? secondaryColor : AppColors.evGreen,
          ),
          title: Text('충전소 현황 알림', style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            _ids.isEmpty ? '알림 설정된 충전소 없음' : '${_ids.length}/${AlertService.evAlarmMaxCount}곳 설정됨',
            style: TextStyle(fontSize: 12, color: mutedColor),
          ),
          trailing: _ids.isNotEmpty
              ? GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: mutedColor),
                    ),
                  ),
                )
              : null,
          onTap: _ids.isNotEmpty ? () => setState(() => _expanded = !_expanded) : null,
        ),
        if (_ids.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Text('알림 방식', style: TextStyle(fontSize: 12, color: mutedColor)),
                const SizedBox(width: 12),
                ...['소리', '진동', '무음'].asMap().entries.map((e) {
                  final idx = e.key;
                  final label = e.value;
                  final selected = _soundMode == idx;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        AlertService().setEvAlarmSoundMode(idx);
                        setState(() => _soundMode = idx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.evGreen.withValues(alpha: 0.15)
                              : (isDark ? const Color(0x0AFFFFFF) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? AppColors.evGreen : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            color: selected ? AppColors.evGreen : secondaryColor,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _expanded
              ? Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0x0AFFFFFF) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0x14FFFFFF) : const Color(0xFFE2E8F0),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    children: _ids.map((id) {
                      final name = AlertService().evAlarmStationName(id);
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
                        leading: const Icon(Icons.ev_station_rounded, size: 18, color: AppColors.evGreen),
                        title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                          onPressed: () => _unsubscribe(id),
                        ),
                      );
                    }).toList(),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
