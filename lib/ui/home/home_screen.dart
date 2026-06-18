import 'dart:async';

import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/helpers.dart';
import '../../data/models/models.dart';
import '../../data/services/ad_service.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/exit_ad_service.dart';
import '../../data/services/alert_service.dart';
import '../../data/services/house_ad_service.dart';
import '../../data/services/notification_service.dart';
import '../../providers/providers.dart';
import '../auth/signup_complete_screen.dart';
import '../ai/ai_main_screen.dart';
import '../events/events_screen.dart';
import '../map/map_screen.dart';
import '../notices/notices_screen.dart';
import '../widgets/native_ad_card.dart';
// popup_ad_dialog 는 dksw_app_core v0.3.2 부터 코어로 통합 — 위 import 로 사용.
import '../widgets/marketing_reprompt.dart';
import '../widgets/popup_notice_dialog.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/watch_session_bar.dart';
import '../../data/services/watch_service.dart';
import '../filter/gas_filter_sheet.dart';
import '../filter/ev_filter_sheet.dart';
import '../../data/services/favorite_service.dart';
import '../../data/services/station_alias_service.dart';
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
  // FCM 리스너는 hot reload / re-create 시 중복 등록되면 알림 2회 저장 등 부작용.
  // dispose 에서 명시적으로 cancel 하기 위해 subscription 보관.
  StreamSubscription<RemoteMessage>? _fcmOnMessageSub;
  StreamSubscription<RemoteMessage>? _fcmOnOpenedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AlertService().refreshToken();
    WatchService().restore();

    // 로컬 알림 "상세보기" 액션 탭 → 알림 페이지로 이동
    navigateToAlertsNotifier.addListener(_onNavigateToAlerts);
    // 1:1 문의 답변 알림 탭 → 그 문의 상세로 이동
    navigateToInquiryNotifier.addListener(_onNavigateToInquiry);
    // 이벤트/공지 포그라운드 로컬알림 탭 → 그 상세로 이동
    navigateToEventNotifier.addListener(_onNavigateToEvent);
    navigateToNoticeNotifier.addListener(_onNavigateToNotice);

    // 포그라운드 FCM 메시지 수신 → 로컬 알림 표시 + 내역 저장
    _fcmOnMessageSub = FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'gas_price_alert') {
        showGasPriceNotification(message.data, soundMode: AlertService().alertSoundMode);
        AlertService().addGasPriceMessage(message.data);
        _messageBadgeKey.currentState?.refreshCount();
      } else if (message.data['type'] == 'ev_alarm') {
        if (AlertService().evAlarmEnabled) {
          showEvAlarmNotification(message.data, soundMode: AlertService().evAlarmSoundMode);
          AlertService().addEvAlarmMessage(message.data);
          _messageBadgeKey.currentState?.refreshCount();
        }
      } else if (message.data['type'] == 'ev_watch') {
        final stationId = message.data['stationId'] as String? ?? '';
        final newAvail = int.tryParse(message.data['newAvail'] as String? ?? '') ?? 0;
        if (stationId.isNotEmpty) WatchService().updateCurrentAvail(stationId, newAvail);
      } else if (message.data['type'] == 'inquiry_reply') {
        // 1:1 문의 답변 — 포그라운드에선 시스템이 자동 표시 안 하므로 직접 띄움
        showInquiryReplyNotification(
          title: message.notification?.title,
          body: message.notification?.body,
          inquiryId: int.tryParse(message.data['inquiryId']?.toString() ?? ''),
        );
      } else if (message.data['type'] == 'event') {
        // 이벤트 — 포그라운드 직접 표시 (탭하면 그 이벤트 상세로)
        showEventNotification(
          title: message.notification?.title,
          body: message.notification?.body,
          eventId: int.tryParse(message.data['id']?.toString() ?? ''),
        );
      } else if (message.data['type'] == 'notice') {
        showNoticeNotification(
          title: message.notification?.title,
          body: message.notification?.body,
          noticeId: int.tryParse(message.data['id']?.toString() ?? ''),
        );
      }
    });

    // 로컬 알림(ev_alarm) 탭 → 충전소 상세로 이동
    navigateToEvStationNotifier.addListener(_onNavigateToEvStation);
    // 홈 위젯(주유소) 탭 → 주유소 상세로 이동
    navigateToGasStationNotifier.addListener(_onNavigateToGasStation);
    // EV watch 만석 알림 "다른 충전소" 액션 → AI 탭 전환 (AiMainScreen 자체가 replan 트리거 listen)
    requestEvReplanNotifier.addListener(_onEvReplanRequested);
    // 앱 종료 상태에서 알림/위젯 탭 시: 리스너 등록 전에 이미 값이 세팅됐을 수 있으므로 초기값 체크
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigateToEvStationNotifier.value.isNotEmpty) {
        _onNavigateToEvStation();
      }
      if (navigateToGasStationNotifier.value.isNotEmpty) {
        _onNavigateToGasStation();
      }
      // 토큰 복원이 build 전에 끝난 경우 대비 — 미완성 계정이면 게이트.
      _maybeGateSignup(ref.read(authProvider));
    });

    // 홈 팝업: 공지(type=popup) 우선, 없으면 광고 (둘 다 하루 1회 한도)
    // - delay 를 700ms 로 늘려 FCM/위젯 탭의 600ms navigation 보다 뒤에 실행
    // - isCurrent 체크로 그 사이 detail 화면이 push 되었으면 popup 스킵
    //   (이전엔 400ms 후 무조건 표시 → 알림 navigation 위에 팝업이 떠 어색했음)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 700), () async {
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent != true) return;
        // 온보딩 끝낸 게스트 1회 이벤트 옵트인(게이팅 무시). 있으면 이걸로 처리하고 재요청은 스킵.
        final settingsNotifier = ref.read(settingsProvider.notifier);
        if (settingsNotifier.pendingEventOptin) {
          settingsNotifier.setPendingEventOptin(false);
          await maybeShowChargeMarketingReprompt(context, force: true);
        } else {
          // 마케팅 동의 재요청 (콘솔 ON + 미동의자 + 오늘 미노출 시 하루 1회)
          await maybeShowChargeMarketingReprompt(context);
        }
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent != true) return;
        await PopupNoticeDialog.showIfEligible(context);
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent != true) return;
        await PopupAdDialog.showIfEligible(context);
      });
    });

    // 백그라운드 알림 탭해서 앱 열린 경우 (앱이 이미 실행 중)
    _fcmOnOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
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
      } else if (message.data['type'] == 'inquiry_reply') {
        navigateToInquiryNotifier.value =
            int.tryParse(message.data['inquiryId']?.toString() ?? '') ?? 0;
      } else if (message.data['type'] == 'event') {
        _openEventDetail(int.tryParse(message.data['id']?.toString() ?? '') ?? 0);
      } else if (message.data['type'] == 'notice') {
        _openNoticeDetail(int.tryParse(message.data['id']?.toString() ?? '') ?? 0);
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
      } else if (message.data['type'] == 'inquiry_reply') {
        final id = int.tryParse(message.data['inquiryId']?.toString() ?? '') ?? 0;
        Future.delayed(const Duration(milliseconds: 600),
            () => navigateToInquiryNotifier.value = id);
      } else if (message.data['type'] == 'event') {
        final id = int.tryParse(message.data['id']?.toString() ?? '') ?? 0;
        Future.delayed(const Duration(milliseconds: 600), () => _openEventDetail(id));
      } else if (message.data['type'] == 'notice') {
        final id = int.tryParse(message.data['id']?.toString() ?? '') ?? 0;
        Future.delayed(const Duration(milliseconds: 600), () => _openNoticeDetail(id));
      }
    });

  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    navigateToAlertsNotifier.removeListener(_onNavigateToAlerts);
    navigateToInquiryNotifier.removeListener(_onNavigateToInquiry);
    navigateToEventNotifier.removeListener(_onNavigateToEvent);
    navigateToNoticeNotifier.removeListener(_onNavigateToNotice);
    navigateToEvStationNotifier.removeListener(_onNavigateToEvStation);
    navigateToGasStationNotifier.removeListener(_onNavigateToGasStation);
    requestEvReplanNotifier.removeListener(_onEvReplanRequested);
    _fcmOnMessageSub?.cancel();
    _fcmOnOpenedSub?.cancel();
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
    } catch (e) {
      if (kDebugMode) debugPrint('[widget-intent] resume consume 실패: $e');
    }
  }

  void _onNavigateToAlerts() => _openAlertsPage();

  void _onNavigateToInquiry() {
    final id = navigateToInquiryNotifier.value;
    if (id <= 0 || !mounted) return;
    navigateToInquiryNotifier.value = 0; // 소비
    context.push('/inquiry', extra: id);
  }

  // 포그라운드 로컬알림 탭(main.dart 핸들러가 notifier 세팅) → 상세 이동.
  void _onNavigateToEvent() {
    final id = navigateToEventNotifier.value;
    if (id <= 0) return;
    navigateToEventNotifier.value = 0; // 소비
    _openEventDetail(id);
  }

  void _onNavigateToNotice() {
    final id = navigateToNoticeNotifier.value;
    if (id <= 0) return;
    navigateToNoticeNotifier.value = 0; // 소비
    _openNoticeDetail(id);
  }

  // 이벤트 푸시 탭 → 해당 이벤트 상세로. id 로 항목을 받아 push, 못 찾으면 목록으로 폴백.
  // 푸시 탭 직후엔 네트워크가 덜 준비돼 첫 fetch 가 빌 수 있으므로, 못 찾으면 재시도 후 폴백.
  Future<void> _openEventDetail(int id, {int attempt = 0}) async {
    if (id <= 0 || !mounted) return;
    EventItem? found;
    try {
      final list = await DkswCore.fetchEvents();
      for (final e in list) {
        if (e.id == id) { found = e; break; }
      }
    } catch (_) {}
    if (!mounted) return;
    if (found == null && attempt < 4) {
      await Future.delayed(const Duration(milliseconds: 600));
      return _openEventDetail(id, attempt: attempt + 1);
    }
    if (!mounted) return;
    final item = found;
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) =>
          item != null ? EventDetailScreen(event: item) : const EventsScreen(),
    ));
  }

  // 공지 푸시 탭 → 해당 공지 상세로.
  Future<void> _openNoticeDetail(int id, {int attempt = 0}) async {
    if (id <= 0 || !mounted) return;
    NoticeItem? found;
    try {
      final list = await DkswCore.fetchNotices();
      for (final n in list) {
        if (n.id == id) { found = n; break; }
      }
    } catch (_) {}
    if (!mounted) return;
    if (found == null && attempt < 4) {
      await Future.delayed(const Duration(milliseconds: 600));
      return _openNoticeDetail(id, attempt: attempt + 1);
    }
    if (!mounted) return;
    final item = found;
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) =>
          item != null ? NoticeDetailScreen(notice: item) : const NoticesScreen(),
    ));
  }

  void _onNavigateToEvStation() {
    final stationId = navigateToEvStationNotifier.value;
    if (stationId.isEmpty || !mounted) return;
    navigateToEvStationNotifier.value = ''; // 중복 이동 방지
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => EvDetailScreen(stationId: stationId),
    ));
  }

  void _onEvReplanRequested() {
    if (!mounted) return;
    // 모든 모달 닫고 AI 탭(index 2) 으로 전환 — AiMainScreen 이 자체적으로 replan 신호 listen
    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    ref.read(bottomNavIndexProvider.notifier).state = 2;
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

  // 완성 게이트: 로그인됐는데 가입 미완성(닉네임·동의 전)이면 가입완료 화면 강제.
  // 재진입(앱 종료 후 재실행) 케이스 담당. 로그인 시점 케이스는 login_screen이 처리.
  bool _signupGateOpen = false;
  void _maybeGateSignup(AuthUser? user) {
    if (_signupGateOpen || user == null || user.signupCompleted) return;
    _signupGateOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) { _signupGateOpen = false; return; }
      // 다른 화면(로그인 등)이 위에 있으면 그쪽이 처리 → 중복 방지
      if (ModalRoute.of(context)?.isCurrent != true) { _signupGateOpen = false; return; }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SignupCompleteScreen(user: user),
      ));
      _signupGateOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomIndex = ref.watch(bottomNavIndexProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 인증 상태가 미완성으로 바뀌면(앱 시작 시 토큰 복원 포함) 가입완료 강제.
    ref.listen<AuthUser?>(authProvider, (_, next) => _maybeGateSignup(next));

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
          // 종료 전 전면광고 — 준비됐으면 보여주고 닫히면 종료, 없으면 즉시 종료.
          ExitAdService.instance.showThenExit(() => SystemNavigator.pop());
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
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: '마이페이지',
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
                  'assets/halfNhalf.png',
                  width: 32,
                  height: 32,
                  filterQuality: FilterQuality.medium,
                ),
                const SizedBox(width: 10),
                Text('전기차 기름차', style: Theme.of(context).textTheme.headlineSmall),
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

// ─── 광고 슬롯 + 스테이션 머지 ───
//
// list_position 4·8·12·16·20·24·28·32 = AdMob 자리 (bypass=true house ad 가 있으면 대체).
// 그 외 위치 = 등록된 house ad 만 노출 (없으면 station 자리).
// stations 가 다 떨어지면 종료 — 이후 광고 슬롯은 화면에 등장하지 않음.
class _AdMobAt {
  final int position;
  const _AdMobAt(this.position);
}

List<Object> mergeWithAdSlots<T extends Object>(List<T> stations) {
  // 정식 오픈: 리스트 광고 활성화 (AdSlotResolver.admobSlots = 4번째마다).
  final merged = <Object>[];
  int sIdx = 0;
  int pos = 1;
  while (sIdx < stations.length) {
    final kind = AdSlotResolver.kindAt(pos);
    switch (kind) {
      case SlotKind.admob:
        merged.add(_AdMobAt(pos));
        break;
      case SlotKind.house:
        final house = HouseAdCache.at(pos);
        if (house != null) merged.add(house);
        break;
      case SlotKind.none:
        merged.add(stations[sIdx]);
        sIdx++;
        break;
    }
    pos++;
    if (pos > 200) break; // 안전망 — 광고 슬롯만 잇따르는 비정상 케이스 방지
  }
  return merged;
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
        ref.invalidate(favGasStationsProvider);  // 즐겨찾기 detail 도 새로 fetch (stale "기타"/"상태확인불가" 방지)
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // 홈 상단 배너 — 콘솔(home_top) house ad 우선, 없으면 AdMob 2단 네이티브, 둘 다 없으면 높이 0.
          const SliverToBoxAdapter(
            child: DkswTopBanner(admobFallback: TopBannerAdmobCard()),
          ),
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
                              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
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
                    onTap: () => GasFilterSheet.show(context, showRadius: true),
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
          // 요약 카드
          SliverToBoxAdapter(
            child: stationsAsync.when(
              loading: () => const GasSummaryCard(avgPrice: 0, priceDiff: 0),
              error: (_, __) => const GasSummaryCard(avgPrice: 0, priceDiff: 0),
              data: (stations) {
                final stationAvg = stations.isEmpty ? 0.0
                    : stations.map((s) => s.price).reduce((a, b) => a + b) / stations.length;
                final avgAsync = ref.watch(gasAvgPriceProvider);
                // 설정 화면(SettingsScreenEmbed)이 keyFuelType 에 저장하므로 settingsProvider.fuelType 이 master.
                // 사용자가 '고급휘발유'로 바꾸면 즉시 반영 — filter 와도 무관.
                final settings = ref.watch(settingsProvider);
                final fuelCode = settings.fuelType.code;
                final fuelLabel = settings.fuelType.label;
                // 응답 우선순위: local(시도) > national(전국) > 레거시 m[fuelCode]
                final m = avgAsync.maybeWhen<Map<String, dynamic>?>(data: (v) => v, orElse: () => null);
                double serverAvg = 0;
                double priceDiff = 0;
                String? sidoName;
                if (m != null) {
                  final local = m['local'];
                  Map? prices;
                  if (local is Map && local['prices'] is Map) {
                    prices = local['prices'] as Map;
                    sidoName = local['sido_name']?.toString();
                  } else if (m['national'] is Map) {
                    prices = m['national'] as Map;
                  } else if (m[fuelCode] is Map) {
                    prices = m;
                  }
                  final row = prices?[fuelCode];
                  if (row is Map) {
                    serverAvg = parseApiDouble(row['price']);
                    priceDiff = parseApiDouble(row['diff']);
                  }
                }
                final showLabel = sidoName != null ? '$sidoName $fuelLabel' : fuelLabel;
                final showAvg = serverAvg > 0 ? serverAvg : stationAvg;
                return GasSummaryCard(avgPrice: showAvg, priceDiff: priceDiff, fuelLabel: showLabel);
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
                  : stations.where((s) {
                      if (s.name.contains(_searchQuery) || s.address.contains(_searchQuery)) return true;
                      final alias = StationAliasService.get(s.id, type: 'gas');
                      return alias != null && alias.contains(_searchQuery);
                    }).toList();
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
              final merged = mergeWithAdSlots<GasStation>(shown);
              return SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final item = merged[i];
                  if (item is _AdMobAt) {
                    return AdMobNativeCard(
                        adUnitId: AdUnitIds.forPosition(item.position));
                  }
                  if (item is HouseAd) {
                    return HouseAdCard(ad: item);
                  }
                  final s = item as GasStation;
                  // station index for isTop: 첫 station 인지
                  final isTop = identical(s, shown.first) && favIds.isEmpty;
                  return GasStationCard(
                    station: s,
                    isTop: isTop,
                    topBadgeLabel: filter.sort == 1 ? '최저가' : '최단거리',
                    onTap: () => context.push('/gas/${s.id}', extra: s),
                  );
                },
                childCount: merged.length,
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
        ref.invalidate(favEvStationsProvider);  // 즐겨찾기 detail 도 새로 fetch (stale 표시 방지)
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // 홈 상단 배너 — 콘솔(home_top) house ad 우선, 없으면 AdMob 2단 네이티브, 둘 다 없으면 높이 0.
          const SliverToBoxAdapter(
            child: DkswTopBanner(admobFallback: TopBannerAdmobCard()),
          ),
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
                              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
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
                    onTap: () => EvFilterSheet.show(context, showRadius: true),
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
                  : stations.where((s) {
                      if (s.name.contains(_searchQuery) ||
                          s.address.contains(_searchQuery) ||
                          s.operator.contains(_searchQuery)) return true;
                      final alias = StationAliasService.get(s.statId, type: 'ev');
                      return alias != null && alias.contains(_searchQuery);
                    }).toList();
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
              final merged = mergeWithAdSlots<EvStation>(shown);
              return SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final item = merged[i];
                  if (item is _AdMobAt) {
                    return AdMobNativeCard(
                      adUnitId: AdUnitIds.forPosition(item.position),
                      isEv: true,
                    );
                  }
                  if (item is HouseAd) {
                    return HouseAdCard(ad: item, isEv: true);
                  }
                  final s = item as EvStation;
                  final isTop = identical(s, shown.first) && favIds.isEmpty;
                  return EvStationCard(
                    station: s,
                    isTop: isTop,
                    onTap: () => context.push('/ev/${s.statId}', extra: s),
                  );
                },
                childCount: merged.length,
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

/// 마이페이지 상단 계정 카드.
/// 비로그인 → "로그인이 필요합니다" + 동기화 안내 (탭 → /login).
/// 로그인 → 닉네임/프로필 + 탭 시 로그아웃·회원탈퇴 시트.
class _AccountCard extends ConsumerWidget {
  final bool isDark;
  const _AccountCard({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final loggedIn = user != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => loggedIn ? context.push('/account') : context.push('/login'),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF162032), Color(0xFF0F1B17)]
                  : const [Color(0xFFEFF6FF), Color(0xFFECFDF5)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: Border.all(
              color: isDark ? AppColors.darkCardBorder : const Color(0xFFDCE7F0),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: AppColors.logoGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (loggedIn && (user.profileImageUrl?.isNotEmpty ?? false))
                      ? Image.network(user.profileImageUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.person_rounded, color: Colors.white, size: 30))
                      : const Icon(Icons.person_rounded, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              loggedIn ? '${user.nickname ?? '사용자'}님' : '로그인이 필요합니다',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded, size: 20, color: textSecondary),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        loggedIn
                            ? (user.email ?? '계정 관리')
                            : '폰을 바꿔도 차량 정보·설정이 그대로 유지돼요',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, height: 1.4, color: textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

/// 마케팅(이벤트·혜택) 수신 동의 토글 — 설정 카드 톤(settingsIconChip + Switch)에 맞춤.
/// DkswCore 동의 기록 사용. 정보통신망법상 상시 철회 가능.
class _ChargeMarketingTile extends ConsumerStatefulWidget {
  final bool isDark;
  const _ChargeMarketingTile({required this.isDark});

  @override
  ConsumerState<_ChargeMarketingTile> createState() => _ChargeMarketingTileState();
}

class _ChargeMarketingTileState extends ConsumerState<_ChargeMarketingTile> {
  bool? _optimistic; // 토글 진행 중에만 사용. 평상시엔 source-of-truth(consentAgreed)를 읽는다.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 온보딩 끝 팝업 등 외부에서 동의가 바뀌면(IndexedStack로 상시 mount 라 자동 리빌드 안 됨) 갱신.
    marketingConsentVersion.addListener(_onConsentChanged);
  }

  @override
  void dispose() {
    marketingConsentVersion.removeListener(_onConsentChanged);
    super.dispose();
  }

  void _onConsentChanged() {
    if (mounted) setState(() {});
  }

  // 매 build마다 실제 동의 상태를 읽어 stale 방지(회원가입 등 외부에서 바뀌어도 반영).
  bool get _on => _optimistic ?? (DkswCore.consentAgreed('marketing') == true);

  Future<void> _set(bool v) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _optimistic = v;
    });
    final version = DkswCore.signupConsents
        .firstWhere(
          (c) => c.key == 'marketing',
          orElse: () => const SignupConsent(
              key: 'marketing', title: '마케팅 정보 수신', required: false, version: '1.0'),
        )
        .version;
    await DkswCore.postConsents([
      ConsentChoice(key: 'marketing', agreed: v, version: version),
    ]);
    marketingConsentVersion.value++; // 다른 구독 위젯도 갱신
    if (mounted) {
      setState(() {
        _busy = false;
        _optimistic = null; // source-of-truth로 복귀
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = widget.isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    ref.watch(authProvider); // 회원가입 등 외부 동의 변경 시 리빌드 트리거
    final on = _on; // 게스트도 device 기반 consent 로 ON 가능
    void handle(bool v) => _set(v);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: SettingsScreenEmbed.settingsIconChip(Icons.campaign_rounded, widget.isDark),
      title: Text('이벤트·혜택 알림 받기',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text('이벤트·프로모션 등 광고성 정보 수신',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
      trailing: Switch(
        value: on,
        onChanged: _busy ? null : handle,
        activeColor: AppColors.gasBlue,
      ),
      onTap: _busy ? null : () => handle(!on),
    );
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
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text('마이페이지',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    )),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: _AccountCard(isDark: isDark),
          ),
          _sectionHeader(context, '차량 설정'),
          settingsCard(isDark, [
            _tile(context, isDark, Icons.directions_car_rounded, '차량 타입', settings.vehicleType.label, () {
              _showPicker(context, '차량 타입', VehicleType.values.map((t) => t.label).toList(),
                VehicleType.values.indexOf(settings.vehicleType),
                (i) => ref.read(settingsProvider.notifier).setVehicleType(VehicleType.values[i]));
            }),
            if (settings.vehicleType != VehicleType.ev) ...[
              settingsDivider(isDark),
              _tile(context, isDark, Icons.local_gas_station_rounded, '유종', settings.fuelType.label, () {
                _showPicker(context, '유종', FuelType.values.map((t) => t.label).toList(),
                  FuelType.values.indexOf(settings.fuelType),
                  (i) => ref.read(settingsProvider.notifier).setFuelType(FuelType.values[i]));
              }),
            ],
          ]),
          _sectionHeader(context, '알림'),
          settingsCard(isDark, [
            _AlertSettingTileEmbed(isDark: isDark),
            settingsDivider(isDark),
            _EvAlarmSettingTileEmbed(isDark: isDark),
            settingsDivider(isDark),
            _DndSettingTileEmbed(isDark: isDark),
          ]),
          _sectionHeader(context, '앱 설정'),
          settingsCard(isDark, [
            _tile(context, isDark, Icons.dark_mode_rounded, '테마',
              themeMode == ThemeMode.dark ? '다크' : '라이트', () {
                const modes = [ThemeMode.light, ThemeMode.dark];
                _showPicker(context, '테마', ['라이트 모드', '다크 모드'],
                  modes.indexOf(themeMode == ThemeMode.system ? ThemeMode.light : themeMode),
                  (i) => ref.read(themeModeProvider.notifier).setTheme(modes[i]));
            }),
            settingsDivider(isDark),
            _ChargeMarketingTile(isDark: isDark),
          ]),
          _SupportEmbed(isDark: isDark),
          _sectionHeader(context, '정보'),
          settingsCard(isDark, [
            _tile(context, isDark, Icons.description_outlined, '정책 및 약관', '',
                () => context.push('/policies')),
          ]),
          const SizedBox(height: 28),
          Center(
            child: Column(
              children: [
                Text(
                  'App version: ${DkswCore.appVersion}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Copyright 2026. 동키소프트웨어 All rights reserved.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  /// 설정 섹션 카드 — 둥근 카드로 타일 그룹화(앱 카드 톤과 통일).
  static Widget settingsCard(bool isDark, List<Widget> children) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkCardBorder : const Color(0xFFE8ECF0),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );

  /// 카드 내부 타일 사이 구분선(살짝 들여쓰기).
  static Widget settingsDivider(bool isDark) => Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: isDark ? const Color(0x12FFFFFF) : const Color(0xFFEEF1F5),
      );

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: AppColors.gasBlue,
        ),
      ),
    );
  }

  /// 틴티드 아이콘 칩 — 회색 맨아이콘 대신 둥근 색배경 칩으로 personality 부여.
  static Widget settingsIconChip(IconData icon, bool isDark) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.gasBlue.withValues(alpha: isDark ? 0.20 : 0.10),
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: AppColors.gasBlue),
      );

  Widget _tile(BuildContext context, bool isDark, IconData icon, String title, String value, VoidCallback? onTap) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: settingsIconChip(icon, isDark),
      title: Text(title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted)),
        if (onTap != null)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Icon(Icons.chevron_right_rounded, size: 20, color: muted),
          ),
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
        // 1:1 문의는 count 와 무관하게 항상 노출되므로 early-return 하지 않는다.
        final hasN = c != null && c.notices > 0;
        final hasE = c != null && c.events > 0;
        final hasF = c != null && c.faqs > 0;
        final isDark = widget.isDark;
        final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

        Widget tile(IconData icon, String title, int count, String route) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: SettingsScreenEmbed.settingsIconChip(icon, isDark),
          title: Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$count', style: TextStyle(fontSize: 13, color: muted)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20, color: muted),
          ]),
          onTap: () => context.push(route),
        );

        final tiles = <Widget>[
          if (hasN) tile(Icons.campaign_rounded, '공지사항', c!.notices, '/notices'),
          if (hasE) tile(Icons.celebration_rounded, '이벤트', c!.events, '/events'),
          if (hasF) tile(Icons.help_outline_rounded, '자주 묻는 질문', c!.faqs, '/faq'),
          // 1:1 문의하기 — 항상 노출
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: SettingsScreenEmbed.settingsIconChip(Icons.support_agent_rounded, isDark),
            title: Text('1:1 문의하기',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            trailing: Icon(Icons.chevron_right_rounded, size: 20, color: muted),
            onTap: () => context.push('/inquiry'),
          ),
        ];
        // 타일 사이 구분선 삽입
        final children = <Widget>[];
        for (var i = 0; i < tiles.length; i++) {
          if (i > 0) children.add(SettingsScreenEmbed.settingsDivider(isDark));
          children.add(tiles[i]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text('고객 지원',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: AppColors.gasBlue)),
            ),
            SettingsScreenEmbed.settingsCard(isDark, children),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
                        activeThumbColor: AppColors.gasBlue,
                      ),
                    ),
            ],
          ),
          onTap: _ids.isNotEmpty ? () => setState(() => _expanded = !_expanded) : null,
        ),

        if (_enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
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
                  margin: const EdgeInsets.fromLTRB(14, 2, 14, 10),
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
                      final name = StationAliasService.resolve(id, AlertService().stationName(id), type: 'gas');
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
  late bool _enabled;
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
      _enabled = AlertService().evAlarmEnabled;
      if (_ids.isEmpty || !_enabled) _expanded = false;
    });
  }

  Future<void> _toggleEnabled(bool value) async {
    await AlertService().setEvAlarmEnabled(value);
    if (mounted) {
      setState(() {
        _enabled = value;
        if (!value) _expanded = false;
      });
    }
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Icon(
            _enabled ? Icons.ev_station_rounded : Icons.notifications_off_rounded,
            size: 22,
            color: (_enabled && _ids.isNotEmpty) ? AppColors.evGreen : secondaryColor,
          ),
          title: Text('충전소 현황 알림', style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            !_enabled
                ? '알림 꺼짐'
                : (_ids.isEmpty ? '알림 설정된 충전소 없음' : '${_ids.length}/${AlertService.evAlarmMaxCount}곳 설정됨'),
            style: TextStyle(fontSize: 12, color: mutedColor),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_enabled && _ids.isNotEmpty)
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
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: _enabled,
                  onChanged: _toggleEnabled,
                  activeThumbColor: AppColors.evGreen,
                ),
              ),
            ],
          ),
          onTap: (_enabled && _ids.isNotEmpty) ? () => setState(() => _expanded = !_expanded) : null,
        ),
        if (_enabled && _ids.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
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
                  margin: const EdgeInsets.fromLTRB(14, 2, 14, 10),
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
                      final name = StationAliasService.resolve(id, AlertService().evAlarmStationName(id), type: 'ev');
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

/// 방해 금지 시간 (바텀탭 설정 임베드) — gas/ev_alarm 알림을 지정 시간엔 소리 없이
/// 보관(시스템 알림 X, 내역 O). 자리변동알림(ev_watch)은 제외. 시간은 드럼 피커.
class _DndSettingTileEmbed extends StatefulWidget {
  final bool isDark;
  const _DndSettingTileEmbed({required this.isDark});
  @override
  State<_DndSettingTileEmbed> createState() => _DndSettingTileEmbedState();
}

class _DndSettingTileEmbedState extends State<_DndSettingTileEmbed> {
  late bool _enabled = AlertService().dndEnabled;
  late int _startMin = AlertService().dndStartMin;
  late int _endMin = AlertService().dndEndMin;

  String _fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _pick(bool isStart) async {
    final cur = isStart ? _startMin : _endMin;
    final picked = await showDrumTimePicker(
      context,
      initial: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (picked == null || !mounted) return;
    final m = picked.hour * 60 + picked.minute;
    setState(() => isStart ? _startMin = m : _endMin = m);
    AlertService().setDnd(startMin: _startMin, endMin: _endMin);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Icon(Icons.bedtime_rounded, size: 22,
              color: _enabled ? AppColors.gasBlue : secondary),
          title: Text('방해 금지 시간', style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            _enabled ? '${_fmt(_startMin)} ~ ${_fmt(_endMin)} · 알림 소리 없이 보관' : '꺼짐',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          trailing: Transform.scale(
            scale: 0.85,
            child: Switch(
              value: _enabled,
              onChanged: (v) {
                setState(() => _enabled = v);
                AlertService().setDnd(enabled: v);
              },
              activeThumbColor: AppColors.gasBlue,
            ),
          ),
        ),
        if (_enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _chip('시작', _startMin, () => _pick(true), secondary),
                    const SizedBox(width: 8),
                    Text('~', style: TextStyle(color: muted)),
                    const SizedBox(width: 8),
                    _chip('종료', _endMin, () => _pick(false), secondary),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '이 시간엔 알림이 소리 없이 보관돼요. 자리변동 알림은 제외돼요.',
                  style: TextStyle(fontSize: 11, color: muted, height: 1.4),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _chip(String label, int min, VoidCallback onTap, Color secondary) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.gasBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.gasBlue.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label  ', style: TextStyle(fontSize: 11, color: secondary)),
            Text(_fmt(min),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.gasBlue)),
          ],
        ),
      ),
    );
  }
}
