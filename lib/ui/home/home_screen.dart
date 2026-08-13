import 'dart:async';
import 'dart:io' show Platform;

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
import 'package:share_plus/share_plus.dart';
import '../../data/services/ad_service.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/rating_prompt_service.dart';
import '../../data/services/widget_service.dart';
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
import 'package:permission_handler/permission_handler.dart';
import '../../core/notif_permission.dart';
import '../../core/app_dialog.dart';
import '../../core/util/ai_consent.dart';
import '../../data/services/user_sync_service.dart';
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
import '../reports/my_reports_screen.dart';
import '../reports/fuel_report_screen.dart';
import '../detail/gas_detail_screen.dart';
import '../ai/widgets/route_engine_sheet.dart';
import 'package:home_widget/home_widget.dart';
import '../../core/utils/nav_scope_pref.dart';
import 'report_fab.dart';
import '../../data/services/cheer_service.dart';
import '../../data/services/inbox_service.dart';
import '../../core/util/app_toast.dart';
import '../../data/services/notif_prefs_service.dart';
import '../settings/ad_inquiry_screen.dart';
import '../cheer/cheer_entry_card.dart';
import '../cheer/gold_profile.dart';
import '../cheer/cheer_screen.dart';
import '../cheer/cheer_tier_theme.dart';
import '../cheer/awards_screen.dart';
import '../widgets/settings_value.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final _messageBadgeKey = GlobalKey<_HomeTabState>();
  double _watchDragDy = 0; // 자리변동알림 플로팅 바 세로 드래그 오프셋(아래에서 위로)
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

    // 월간 시상식 — 매월 1일 결산 후 첫 진입 때 한 번만. 상장은 1등만 본다(handoff 3).
    // 2·3위도 seen 처리해서 매번 다시 조회하지 않게 한다.
    // status 조회가 실패하면 조용히 넘어간다(응원 기능 원칙: 앱 사용 방해 금지).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final st = await CheerService.instance.status();
      final crown = st?.newCrown;
      if (crown == null || !mounted) return;
      // 2·3위는 상장이 없다 — 조회만 소진하고 끝낸다(마이페이지 수상 기록엔 남는다).
      if (crown.rank != 1) {
        CheerService.instance.markCrownSeen();
        return;
      }
      final awards = await CheerService.instance.awards(month: crown.month);
      // 시상식 조회가 실패하면 왕관을 소진하지 않는다 — 여기서 seen 처리해 버리면
      // 서버가 잠깐 삐끗한 사이에 1등이 상장을 영영 못 본다(테스트 왕관도 마찬가지로
      // 앱 켤 때마다 소진돼서 '설정했는데 안 뜬다'가 된다).
      if (awards == null || !mounted) return;
      CheerService.instance.markCrownSeen();
      final user = ref.read(authProvider);
      // 비회원 1등 — 닉네임이 없다. 서버가 순위표에 내려준 기기 별칭('응원자 4821')을
      // 그대로 상장에 쓴다. 그것도 없을 때만 '응원왕'.
      final myRow = awards.top.where((r) => r.me);
      final nickname = (user?.nickname?.trim().isNotEmpty ?? false)
          ? user!.nickname!
          : (myRow.isEmpty ? '응원왕' : myRow.first.name);
      showCheerAwards(context, data: awards, nickname: nickname);
    });

    // 소식함 뱃지 — 진입할 때마다 한 번. 실패는 서비스 안에서 조용히 삼킨다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      InboxService.instance.refreshUnread();
    });

    // 앱 진입 시 만족도 게이트(2번째 진입부터·백오프 7/30일·평생 3회). 첫 프레임 후.
    // 👎(아쉬워요) → 공개 별점 대신 1:1 문의로 유도(불만 비공개 수집).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        RatingPromptService.maybeShow(
          context,
          onNegativeFeedback: () {
            if (mounted) context.push('/inquiry');
          },
        );
      }
    });

    // 로컬 알림 "상세보기" 액션 탭 → 알림 페이지로 이동
    navigateToAlertsNotifier.addListener(_onNavigateToAlerts);
    // 1:1 문의 답변 알림 탭 → 그 문의 상세로 이동
    navigateToInquiryNotifier.addListener(_onNavigateToInquiry);
    navigateToMyReportsNotifier.addListener(_onNavigateToMyReports);
    // 이벤트/공지 포그라운드 로컬알림 탭 → 그 상세로 이동
    navigateToEventNotifier.addListener(_onNavigateToEvent);
    navigateToNoticeNotifier.addListener(_onNavigateToNotice);
    navigateToFuelReportNotifier.addListener(_onNavigateToFuelReport);

    // 앱이 완전히 꺼진 상태에서 알림 탭으로 실행된 경우 — main 의 payload 라우팅이
    // 이 initState 보다 먼저 끝나 리스너가 값을 못 받는다(그래서 홈에 머물렀음).
    // 마운트 직후 한 번 훑어 대기 중인 이동 요청을 소비한다. 각 핸들러가 값을
    // 0 으로 소비하므로 리스너와 중복 실행돼도 두 번 이동하지 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (navigateToFuelReportNotifier.value > 0) _onNavigateToFuelReport();
      if (navigateToNoticeNotifier.value > 0) _onNavigateToNotice();
      if (navigateToEventNotifier.value > 0) _onNavigateToEvent();
      if (navigateToInquiryNotifier.value > 0) _onNavigateToInquiry();
    });

    // 포그라운드 FCM 메시지 수신 → 로컬 알림 표시 + 내역 저장.
    // iOS 는 로컬 그리기 스킵 — FCM 플러그인이 알림 델리게이트를 잡아 포그라운드
    // 로컬 알림이 침묵하므로, main 의 setForegroundNotificationPresentationOptions 로
    // OS 가 리모트(APNs alert)를 직접 그린다. 여기서 또 그리면 이중 배너.
    // (알림함 저장·뱃지·상태 갱신은 플랫폼 공통으로 유지)
    final drawLocal = !Platform.isIOS;
    _fcmOnMessageSub = FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'gas_price_alert') {
        if (drawLocal) {
          showGasPriceNotification(message.data,
              soundMode: AlertService().alertSoundMode);
        }
        AlertService().addGasPriceMessage(message.data);
        _messageBadgeKey.currentState?.refreshCount();
      } else if (message.data['type'] == 'ev_alarm') {
        if (AlertService().evAlarmEnabled) {
          if (drawLocal) {
            showEvAlarmNotification(message.data,
                soundMode: AlertService().evAlarmSoundMode);
          }
          AlertService().addEvAlarmMessage(message.data);
          _messageBadgeKey.currentState?.refreshCount();
        }
      } else if (message.data['type'] == 'ev_watch') {
        final stationId = message.data['stationId'] as String? ?? '';
        final newAvail =
            int.tryParse(message.data['newAvail'] as String? ?? '') ?? 0;
        if (stationId.isNotEmpty)
          WatchService().updateCurrentAvail(stationId, newAvail);
      } else if (message.data['type'] == 'inquiry_reply') {
        // 1:1 문의 답변 — Android 는 직접 띄움 (v2 data-only 는 title/body 가 data 에 실림)
        if (drawLocal) {
          showInquiryReplyNotification(
            title: message.notification?.title ??
                message.data['title']?.toString(),
            body:
                message.notification?.body ?? message.data['body']?.toString(),
            inquiryId:
                int.tryParse(message.data['inquiryId']?.toString() ?? ''),
          );
        }
        _saveToInbox(message);
      } else if (message.data['type'] == 'event') {
        if (drawLocal) {
          showEventNotification(
            title: message.notification?.title ??
                message.data['title']?.toString(),
            body:
                message.notification?.body ?? message.data['body']?.toString(),
            eventId: int.tryParse(message.data['id']?.toString() ?? ''),
          );
        }
        _saveToInbox(message);
      } else if (message.data['type'] == 'notice') {
        if (drawLocal) {
          showNoticeNotification(
            title: message.notification?.title ??
                message.data['title']?.toString(),
            body:
                message.notification?.body ?? message.data['body']?.toString(),
            noticeId: int.tryParse(message.data['id']?.toString() ?? ''),
          );
        }
        _saveToInbox(message);
      } else if (message.data['type'] == 'fuel_report') {
        if (drawLocal) {
          showFuelReportNotification(
            title: message.notification?.title ??
                message.data['title']?.toString(),
            body:
                message.notification?.body ?? message.data['body']?.toString(),
            reportId: int.tryParse(message.data['id']?.toString() ?? ''),
          );
        }
        _saveToInbox(message);
      } else if (message.notification != null ||
          message.data['title'] != null ||
          message.data['body'] != null) {
        // 자유 푸시·브리핑 등 그 외 모든 알림
        if (drawLocal) {
          showNoticeNotification(
            title: message.notification?.title ??
                message.data['title']?.toString(),
            body:
                message.notification?.body ?? message.data['body']?.toString(),
            noticeId: null,
          );
        }
        _saveToInbox(message);
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
      _saveTappedPushToInbox(message);
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
        final newAvail =
            int.tryParse(message.data['newAvail'] as String? ?? '') ?? 0;
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
      } else if (message.data['type'] == 'report_done') {
        // 제보 처리완료/사유 안내 푸시 → 내 제보 내역
        if (mounted) {
          Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
            builder: (_) => const MyReportsScreen(),
          ));
        }
      } else if (message.data['type'] == 'event') {
        _openEventDetail(
            int.tryParse(message.data['id']?.toString() ?? '') ?? 0);
      } else if (message.data['type'] == 'notice') {
        _openNoticeDetail(
            int.tryParse(message.data['id']?.toString() ?? '') ?? 0);
      } else if (message.data['type'] == 'fuel_report') {
        _openFuelReport(
            int.tryParse(message.data['id']?.toString() ?? '') ?? 0);
      }
    });

    // 앱이 종료된 상태에서 알림 탭해서 열린 경우 (앱 새로 시작)
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message == null) return;
      _saveTappedPushToInbox(message);
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
        final id =
            int.tryParse(message.data['inquiryId']?.toString() ?? '') ?? 0;
        Future.delayed(const Duration(milliseconds: 600),
            () => navigateToInquiryNotifier.value = id);
      } else if (message.data['type'] == 'report_done') {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
              builder: (_) => const MyReportsScreen(),
            ));
          }
        });
      } else if (message.data['type'] == 'event') {
        final id = int.tryParse(message.data['id']?.toString() ?? '') ?? 0;
        Future.delayed(
            const Duration(milliseconds: 600), () => _openEventDetail(id));
      } else if (message.data['type'] == 'notice') {
        final id = int.tryParse(message.data['id']?.toString() ?? '') ?? 0;
        Future.delayed(
            const Duration(milliseconds: 600), () => _openNoticeDetail(id));
      } else if (message.data['type'] == 'fuel_report') {
        final id = int.tryParse(message.data['id']?.toString() ?? '') ?? 0;
        Future.delayed(
            const Duration(milliseconds: 600), () => _openFuelReport(id));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    navigateToAlertsNotifier.removeListener(_onNavigateToAlerts);
    navigateToInquiryNotifier.removeListener(_onNavigateToInquiry);
    navigateToMyReportsNotifier.removeListener(_onNavigateToMyReports);
    navigateToEventNotifier.removeListener(_onNavigateToEvent);
    navigateToNoticeNotifier.removeListener(_onNavigateToNotice);
    navigateToFuelReportNotifier.removeListener(_onNavigateToFuelReport);
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
      // 백그라운드 아이솔레이트가 저장한 알림 내역을 재오픈으로 최신화 → 뱃지·목록 갱신.
      AlertService.reloadInbox().then((_) {
        if (mounted) _messageBadgeKey.currentState?.refreshCount();
      });
    }
  }

  Future<void> _consumeWidgetPendingOnResume() async {
    try {
      final type =
          await HomeWidget.getWidgetData<String>('widget_pending_type');
      if (type == null || type.isEmpty) return;
      final stationId =
          await HomeWidget.getWidgetData<String>('widget_pending_station_id');
      await HomeWidget.saveWidgetData<String>('widget_pending_type', '');
      await HomeWidget.saveWidgetData<String>('widget_pending_station_id', '');
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

  /// 공지·이벤트·문의답변·제보 푸시를 "탭 시점"에 알림함 저장 — iOS 는 백그라운드
  /// 수신 시 저장 경로가 없어 여기서 보강 (가격/자리 알림은 전용 저장 경로 있어 제외).
  void _saveTappedPushToInbox(RemoteMessage message) {
    final type = message.data['type']?.toString() ?? '';
    if (type == 'gas_price_alert' || type == 'ev_alarm' || type == 'ev_watch') {
      return;
    }
    final title =
        message.notification?.title ?? message.data['title']?.toString() ?? '';
    final body =
        message.notification?.body ?? message.data['body']?.toString() ?? '';
    AlertService().saveTappedPush(
      title: title,
      body: body,
      type: type,
      refId:
          (message.data['id'] ?? message.data['inquiryId'])?.toString() ?? '',
    );
    _messageBadgeKey.currentState?.refreshCount();
  }

  void _onNavigateToMyReports() {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => const MyReportsScreen(),
    ));
  }

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

  void _onNavigateToFuelReport() {
    final id = navigateToFuelReportNotifier.value;
    if (id <= 0) return;
    navigateToFuelReportNotifier.value = 0; // 소비
    _openFuelReport(id);
  }

  // 유가·충전 리포트 푸시 탭 → 그 리포트 상세 (id 가 없으면 목록)
  void _openFuelReport(int id) {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => id > 0
          ? FuelReportDetailScreen(reportId: id)
          : const FuelReportScreen(),
    ));
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
        if (e.id == id) {
          found = e;
          break;
        }
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
        if (n.id == id) {
          found = n;
          break;
        }
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
      builder: (_) => item != null
          ? NoticeDetailScreen(notice: item)
          : const NoticesScreen(),
    ));
  }

  /// 모든 종류 푸시(공지·이벤트·문의답변·자유푸시 등)를 홈 우측 위 알림 내역에 저장.
  /// (주유/EV 알람은 각자 전용 포맷터가 저장하므로 여기 안 거침)
  void _saveToInbox(RemoteMessage message) {
    // v2 data-only 는 title/body 가 data 에 실림 — notification 폴백 겸용.
    final title =
        message.notification?.title ?? message.data['title']?.toString();
    final body = message.notification?.body ?? message.data['body']?.toString();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }
    // type/refId — 알림 내역에서 항목 탭 시 해당 상세로 이동용.
    AlertService().addMessage(
      title: title ?? '알림',
      body: body ?? '',
      type: message.data['type']?.toString(),
      refId: (message.data['id'] ?? message.data['inquiryId'])?.toString(),
    );
    _messageBadgeKey.currentState?.refreshCount();
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
      if (!mounted) {
        _signupGateOpen = false;
        return;
      }
      // 다른 화면(로그인 등)이 위에 있으면 그쪽이 처리 → 중복 방지
      if (ModalRoute.of(context)?.isCurrent != true) {
        _signupGateOpen = false;
        return;
      }
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

        // 뒤로가기 → 바로 종료 확인 다이얼로그. 다이얼로그 자체가 확인 단계(취소/종료)라
        // "한 번 더 누르면" 토스트까지 두면 이중 확인이라 제거 (사용자 결정).
        showExitConfirmDialog(context);
      },
      child: Scaffold(
        // 플로팅 알약 바 — extendBody 로 콘텐츠가 바 뒤로 흐르게. 안 그러면 알약 주변
        // 띠가 Scaffold 배경색으로 채워져 지도탭 등 배경색이 다른 탭에서 회색
        // 음영 밴드로 보인다(형 제보). body 의 MediaQuery.padding.bottom 에 바 높이가
        // 들어오므로 SafeArea/padding.bottom 쓰는 리스트는 자동으로 피한다.
        extendBody: true,
        body: Stack(
          children: [
            Positioned.fill(
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
            // 자리변동알림 — 홈 탭에서 하단 플로팅 (스크롤해도 항상 보임, content 안 밀림)
            if (bottomIndex == 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: _watchDragDy,
                child: GestureDetector(
                  // 세로 드래그로 위치 이동 (아래↔위). 내부 버튼 탭과 충돌 없음.
                  onVerticalDragUpdate: (d) {
                    final maxUp = MediaQuery.of(context).size.height * 0.62;
                    setState(() => _watchDragDy =
                        (_watchDragDy - d.delta.dy).clamp(0.0, maxUp));
                  },
                  child: const WatchSessionBar(),
                ),
              ),
          ],
        ),
        // 퀵메뉴 — body 안에서는 하단 바 위로 못 내려가서(형 요청: 더 아래로)
        // docked FAB 슬롯 사용: 바 상단에 걸쳐 앉고 히트테스트도 Scaffold 가 보장.
        floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
        floatingActionButton: bottomIndex == 0
            ? Builder(builder: (_) {
                final vt = ref.watch(settingsProvider).vehicleType;
                void openReport(String topic) =>
                    Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                FuelReportScreen(initialTopic: topic)));
                return HomeQuickFab(items: [
                  if (vt != VehicleType.ev)
                    QuickMenuItem(
                      icon: Icons.bar_chart_rounded,
                      label: '유가 리포트',
                      color: AppColors.gasBlue,
                      onTap: () => openReport('fuel'),
                    ),
                  if (vt != VehicleType.gas)
                    QuickMenuItem(
                      icon: Icons.ev_station_rounded,
                      label: '충전 리포트',
                      color: AppColors.evGreen,
                      onTap: () => openReport('ev'),
                    ),
                ]);
              })
            : null,
        // 하단 탭바 — 가운데 AI 를 바 위로 띄운 그라데이션 원형 버튼으로 (형 시안 2026-08-04).
        bottomNavigationBar: _AiBottomNav(
          index: bottomIndex,
          isDark: isDark,
          onSelect: (i) {
            HapticFeedback.selectionClick();
            ref.read(bottomNavIndexProvider.notifier).state = i;
          },
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
    final activeTab =
        vehicleType == VehicleType.ev ? 1 : ref.watch(activeTabProvider);
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
                Text('전기차 기름차',
                    style: Theme.of(context).textTheme.headlineSmall),
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
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
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
    final activeFuel = ref.watch(effectiveGasFuelTypeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _displayCount = _pageSize;
          _searchQuery = '';
          _searchController.clear();
        });
        ref.invalidate(locationProvider);
        ref.invalidate(gasStationsRawProvider);
        ref.invalidate(
            favGasStationsProvider); // 즐겨찾기 detail 도 새로 fetch (stale "기타"/"상태확인불가" 방지)
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
                        color:
                            isDark ? AppColors.darkCard : AppColors.lightCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: isDark
                                ? AppColors.darkCardBorder
                                : AppColors.lightCardBorder,
                            width: 0.5),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 10),
                          Icon(Icons.search_rounded,
                              size: 17,
                              color: isDark
                                  ? AppColors.darkTextMuted
                                  : AppColors.lightTextMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (v) => setState(() {
                                _searchQuery = v;
                                _displayCount = _pageSize;
                              }),
                              onTapOutside: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                              decoration: InputDecoration(
                                hintText: '주유소 검색',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? AppColors.darkTextMuted
                                        : AppColors.lightTextMuted),
                              ),
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () => setState(() {
                                _searchQuery = '';
                                _searchController.clear();
                              }),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(Icons.close_rounded,
                                    size: 15,
                                    color: isDark
                                        ? AppColors.darkTextMuted
                                        : AppColors.lightTextMuted),
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
                          const Icon(Icons.tune_rounded,
                              size: 15, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            filter.sort == 1 ? '가격순' : '거리순',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 유종 퀵 토글 — 필터에서 고른 유종들. 탭하면 활성 전환(리스트/마커/평균 즉시 반영).
          // pinned: 스크롤을 내려도 상단에 고정 — 아래쪽 주유소를 보다가 유종을
          // 바꾸려면 맨 위까지 되올라가야 한다는 사용자 제보 반영.
          if (filter.fuelTypes.length > 1)
            SliverPersistentHeader(
              pinned: true,
              delegate: _FuelChipsHeaderDelegate(
                isDark: isDark,
                // 리빌드 판단용 상태 시그니처 — child(ListView) 인스턴스는 매 빌드
                // 새로 만들어져 비교가 무의미하므로, 화면에 영향 주는 상태만 비교.
                signature: '${filter.fuelTypes.join(',')}|$activeFuel|$isDark',
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                  children: [
                    for (final code in filter.fuelTypes)
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: GestureDetector(
                          onTap: () => ref
                              .read(activeGasFuelTypeProvider.notifier)
                              .state = code,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: code == activeFuel
                                  ? AppColors.gasBlue
                                  : (isDark
                                      ? const Color(0x12FFFFFF)
                                      : Colors.white),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: code == activeFuel
                                    ? AppColors.gasBlue
                                    : (isDark
                                        ? AppColors.darkCardBorder
                                        : const Color(0xFFE2E8F0)),
                              ),
                            ),
                            child: Text(
                              fuelCodeLabel(code),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: code == activeFuel
                                    ? Colors.white
                                    : (isDark
                                        ? AppColors.darkTextSecondary
                                        : const Color(0xFF64748B)),
                              ),
                            ),
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
                final stationAvg = stations.isEmpty
                    ? 0.0
                    : stations.map((s) => s.price).reduce((a, b) => a + b) /
                        stations.length;
                final avgAsync = ref.watch(gasAvgPriceProvider);
                // 홈 표시는 활성 유종(토글)을 따라감 — 리스트/마커/평균 일관되게.
                final fuelCode = ref.watch(effectiveGasFuelTypeProvider);
                final fuelLabel = fuelCodeLabel(fuelCode);
                // 응답 우선순위: local(시도) > national(전국) > 레거시 m[fuelCode]
                final m = avgAsync.maybeWhen<Map<String, dynamic>?>(
                    data: (v) => v, orElse: () => null);
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
                final showLabel =
                    sidoName != null ? '$sidoName $fuelLabel' : fuelLabel;
                final showAvg = serverAvg > 0 ? serverAvg : stationAvg;
                return GasSummaryCard(
                    avgPrice: showAvg,
                    priceDiff: priceDiff,
                    fuelLabel: showLabel);
              },
            ),
          ),
          // 리스트
          stationsAsync.when(
            loading: () => SliverList(
                delegate: SliverChildBuilderDelegate(
              (_, __) => const SkeletonCard(),
              childCount: 6,
            )),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(
                  child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  const Icon(Icons.wifi_off_rounded,
                      size: 48, color: AppColors.darkTextMuted),
                  const SizedBox(height: 12),
                  Text('데이터를 불러올 수 없습니다',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  TextButton(
                      onPressed: () => ref.invalidate(gasStationsRawProvider),
                      child: const Text('다시 시도')),
                ]),
              )),
            ),
            data: (stations) {
              var filtered = _searchQuery.isEmpty
                  ? stations
                  : stations.where((s) {
                      if (s.name.contains(_searchQuery) ||
                          s.address.contains(_searchQuery)) return true;
                      final alias = StationAliasService.get(s.id, type: 'gas');
                      return alias != null && alias.contains(_searchQuery);
                    }).toList();
              if (filtered.isEmpty) {
                return SliverToBoxAdapter(
                  child: Center(
                      child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                        _searchQuery.isEmpty
                            ? '주변에 주유소가 없습니다'
                            : '\'$_searchQuery\' 검색 결과가 없습니다',
                        style: Theme.of(context).textTheme.bodyMedium),
                  )),
                );
              }
              // provider에서 즐겨찾기 상위 정렬 + 필터 면제 처리됨
              final favIds = FavoriteService.getByType('gas')
                  .map((f) => f['id'] as String)
                  .toSet();
              final shown = filtered.take(_displayCount).toList();
              final merged = mergeWithAdSlots<GasStation>(shown);
              return SliverList(
                  delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final item = merged[i];
                  if (item is _AdMobAt) {
                    return AdMobNativeCard(
                      adUnitId: AdUnitIds.forPosition(item.position),
                      listPosition: item.position,
                    );
                  }
                  if (item is HouseAd) {
                    return HouseAdCard(
                      ad: item,
                      carousel: HouseAdCache.atAll(item.listPosition),
                    );
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
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
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
        setState(() {
          _displayCount = _pageSize;
          _searchQuery = '';
          _searchController.clear();
        });
        ref.invalidate(locationProvider);
        ref.invalidate(evStationsRawProvider);
        ref.invalidate(
            favEvStationsProvider); // 즐겨찾기 detail 도 새로 fetch (stale 표시 방지)
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
                        color:
                            isDark ? AppColors.darkCard : AppColors.lightCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: isDark
                                ? AppColors.darkCardBorder
                                : AppColors.lightCardBorder,
                            width: 0.5),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 10),
                          Icon(Icons.search_rounded,
                              size: 17,
                              color: isDark
                                  ? AppColors.darkTextMuted
                                  : AppColors.lightTextMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (v) => setState(() {
                                _searchQuery = v;
                                _displayCount = _pageSize;
                              }),
                              onTapOutside: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                              decoration: InputDecoration(
                                hintText: '충전소 검색',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? AppColors.darkTextMuted
                                        : AppColors.lightTextMuted),
                              ),
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () => setState(() {
                                _searchQuery = '';
                                _searchController.clear();
                              }),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(Icons.close_rounded,
                                    size: 15,
                                    color: isDark
                                        ? AppColors.darkTextMuted
                                        : AppColors.lightTextMuted),
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
                          const Icon(Icons.tune_rounded,
                              size: 15, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            filter.sort == 1 ? '거리순' : '가격순',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
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
              loading: () =>
                  const EvSummaryCard(totalStations: 0, availableStations: 0),
              error: (_, __) =>
                  const EvSummaryCard(totalStations: 0, availableStations: 0),
              data: (stations) => EvSummaryCard(
                totalStations: stations.length,
                availableStations: stations.where((s) => s.hasAvailable).length,
              ),
            ),
          ),
          // 리스트
          stationsAsync.when(
            loading: () => SliverList(
                delegate: SliverChildBuilderDelegate(
              (_, __) => const SkeletonCard(),
              childCount: 6,
            )),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(
                  child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  const Icon(Icons.wifi_off_rounded,
                      size: 48, color: AppColors.darkTextMuted),
                  const SizedBox(height: 12),
                  Text('데이터를 불러올 수 없습니다',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  TextButton(
                      onPressed: () => ref.invalidate(evStationsRawProvider),
                      child: const Text('다시 시도')),
                ]),
              )),
            ),
            data: (stations) {
              var filtered = _searchQuery.isEmpty
                  ? stations
                  : stations.where((s) {
                      if (s.name.contains(_searchQuery) ||
                          s.address.contains(_searchQuery) ||
                          s.operator.contains(_searchQuery)) return true;
                      final alias =
                          StationAliasService.get(s.statId, type: 'ev');
                      return alias != null && alias.contains(_searchQuery);
                    }).toList();
              if (filtered.isEmpty) {
                return SliverToBoxAdapter(
                  child: Center(
                      child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                        _searchQuery.isEmpty
                            ? '주변에 충전소가 없습니다'
                            : '\'$_searchQuery\' 검색 결과가 없습니다',
                        style: Theme.of(context).textTheme.bodyMedium),
                  )),
                );
              }
              // provider에서 즐겨찾기 상위 정렬 + 필터 면제 처리됨
              final favIds = FavoriteService.getByType('ev')
                  .map((f) => f['id'] as String)
                  .toSet();
              final shown = filtered.take(_displayCount).toList();
              final merged = mergeWithAdSlots<EvStation>(shown);
              return SliverList(
                  delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final item = merged[i];
                  if (item is _AdMobAt) {
                    return AdMobNativeCard(
                      adUnitId: AdUnitIds.forPosition(item.position),
                      listPosition: item.position,
                      isEv: true,
                    );
                  }
                  if (item is HouseAd) {
                    return HouseAdCard(
                      ad: item,
                      carousel: HouseAdCache.atAll(item.listPosition),
                      isEv: true,
                    );
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
    // 페이지 열람 중 새 푸시 수신 시 리스트 즉시 반영 (선택모드 중엔 선택 꼬임 방지로 보류).
    AlertService.messagesChanged.addListener(_onMessagesChanged);
  }

  void _onMessagesChanged() {
    if (!mounted || _selectionMode) return;
    setState(() => _messages = AlertService().receivedMessages);
  }

  @override
  void dispose() {
    AlertService.messagesChanged.removeListener(_onMessagesChanged);
    super.dispose();
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
    final primaryColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
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

  /// 항목 탭 → 알림 종류별 상세로 이동. 홈의 notifier 리스너들이 rootNavigator 로
  /// push 하므로 이 리스트 위에 상세가 얹히고, 뒤로가기로 리스트에 돌아온다.
  /// 구버전 저장분(type 없음)은 이동 없음.
  void _openFromAlert(Map<String, dynamic> msg) {
    final type = (msg['type'] ?? '').toString();
    final refId = (msg['ref_id'] ?? '').toString();
    final refInt = int.tryParse(refId) ?? 0;
    switch (type) {
      case 'notice':
        if (refInt > 0) navigateToNoticeNotifier.value = refInt;
        break;
      case 'event':
        if (refInt > 0) navigateToEventNotifier.value = refInt;
        break;
      case 'inquiry_reply':
        if (refInt > 0) navigateToInquiryNotifier.value = refInt;
        break;
      case 'fuel_report':
        if (refInt > 0) navigateToFuelReportNotifier.value = refInt;
        break;
      case 'ev':
      case 'ev_alarm':
      case 'ev_watch':
        if (refId.isNotEmpty) navigateToEvStationNotifier.value = refId;
        break;
      case 'gas_price':
        if (refId.isNotEmpty) navigateToGasStationNotifier.value = refId;
        break;
    }
  }

  /// 이동 가능한 항목인지 — 탭 하이라이트/화살표 표시용.
  bool _canOpen(Map<String, dynamic> msg) {
    final type = (msg['type'] ?? '').toString();
    final refId = (msg['ref_id'] ?? '').toString();
    if (refId.isEmpty) return false;
    return const {
      'notice',
      'event',
      'inquiry_reply',
      'ev',
      'ev_alarm',
      'ev_watch',
      'gas_price',
      'fuel_report',
    }.contains(type);
  }

  ({IconData icon, Color color}) _alertVisual(Map<String, dynamic> msg) {
    switch ((msg['type'] ?? '').toString()) {
      case 'notice':
        return (icon: Icons.campaign_rounded, color: const Color(0xFFE8700A));
      case 'event':
        return (
          icon: Icons.card_giftcard_rounded,
          color: const Color(0xFF7C3AED)
        );
      case 'inquiry_reply':
        return (
          icon: Icons.mark_chat_read_rounded,
          color: const Color(0xFF16A34A)
        );
      case 'fuel_report':
        return (icon: Icons.insights_rounded, color: AppColors.gasBlue);
      case 'ev':
      case 'ev_alarm':
      case 'ev_watch':
        return (icon: Icons.bolt_rounded, color: const Color(0xFF16A34A));
      default:
        return (
          icon: Icons.local_gas_station_rounded,
          color: AppColors.gasBlue
        );
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
        foregroundColor:
            isDark ? AppColors.darkTextPrimary : const Color(0xFF1a1a1a),
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
                  onPressed: _selected.isEmpty ? null : _confirmDeleteSelected,
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

                final canOpen = _canOpen(msg);
                final visual = _alertVisual(msg);
                final tile = InkWell(
                  onTap: _selectionMode
                      ? () => _toggleSelect(id)
                      : (canOpen ? () => _openFromAlert(msg) : null),
                  onLongPress:
                      _selectionMode ? null : () => _enterSelectionMode(id),
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
                              color:
                                  isSelected ? AppColors.gasBlue : mutedColor,
                            ),
                          )
                        else
                          Container(
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: visual.color.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(visual.icon,
                                color: visual.color, size: 20),
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
                                    _formatTime(msg['timestamp'] as String?),
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
                        if (!_selectionMode && canOpen)
                          Padding(
                            padding: const EdgeInsets.only(left: 6, top: 12),
                            child: Icon(Icons.chevron_right_rounded,
                                size: 18, color: mutedColor),
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
              child: Text('즐겨찾기',
                  style: Theme.of(context).textTheme.headlineSmall),
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
    final ready = ref.watch(authInitializedProvider); // 복원 완료 전엔 로그인 상태 단정 X
    final loggedIn = user != null;

    // 로그인 사용자 = 골드 프로필 카드(handoff 3). 비로그인은 로그인 유도 문구가
    // 필요해서 기존 카드를 유지한다 — 골드 카드엔 그 문구 자리가 없다.
    // totalNotifier·statusNotifier 구독 — 응원/수상이 바뀌면 카드가 즉시 따라온다.
    if (!loggedIn || !ready) return _plainCard(context, user, ready, loggedIn);
    return ValueListenableBuilder<int>(
      valueListenable: CheerService.instance.totalNotifier,
      builder: (context, cheerTotal, _) => ValueListenableBuilder<CheerStatus?>(
        valueListenable: CheerService.instance.statusNotifier,
        builder: (context, st, __) {
          final crowns = st?.crowns ?? const <CheerCrown>[];
          return _GoldProfileCard(
            isDark: isDark,
            nickname: '${user.nickname ?? '사용자'}님',
            profileImageUrl: user.profileImageAbsolute,
            tierName: CheerTierTheme.of(cheerTotal)?.name,
            total: cheerTotal,
            crown: crowns.isEmpty ? null : crowns.first,
            onTap: () => context.push('/account'),
          );
        },
      ),
    );
  }

  Widget _plainCard(
      BuildContext context, dynamic user, bool ready, bool loggedIn) {
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () =>
            loggedIn ? context.push('/account') : context.push('/login'),
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
              color:
                  isDark ? AppColors.darkCardBorder : const Color(0xFFDCE7F0),
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
                  child:
                      (loggedIn && user.profileImageAbsolute != null)
                          ? Image.network(user.profileImageAbsolute!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person_rounded,
                                  color: Colors.white,
                                  size: 30))
                          : const Icon(Icons.person_rounded,
                              color: Colors.white, size: 30),
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
                              !ready
                                  ? '불러오는 중…'
                                  : (loggedIn
                                      ? '${user.nickname ?? '사용자'}님'
                                      : '로그인이 필요합니다'),
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
                          Icon(Icons.chevron_right_rounded,
                              size: 20, color: textSecondary),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        !ready
                            ? ''
                            : (loggedIn
                                ? (user.email ?? '계정 관리')
                                : '폰을 바꿔도 차량 정보·설정이 그대로 유지돼요'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, height: 1.4, color: textSecondary),
                      ),
                    ],
                  ),
                ),
                // 아직 뱃지가 없는 사용자 — 잠긴 첫 차 실루엣으로 개러지를 예고한다.
                // 앱 사용 흐름(지도·홈·추천)은 건드리지 않고, 스스로 들어오는
                // 마이페이지의 기존 카드 안에서만 보여준다(형 원칙: 스텝 추가 금지).
                const SizedBox(width: 6),
                _FirstCarHint(isDark: isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 첫 응원 유도 — 잠긴 쿠페 실루엣 + 짧은 한 줄. 탭하면 응원 화면.
class _FirstCarHint extends StatelessWidget {
  final bool isDark;
  const _FirstCarHint({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final tier = CheerTierTheme.byLevel(1);
    final tint = CheerDs.silhouette(isDark);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context, rootNavigator: true)
          .push(MaterialPageRoute(builder: (_) => const CheerScreen())),
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                height: 26, child: tier.silhouette(tint, width: 66)),
            const SizedBox(height: 3),
            Text('첫 차 받기',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                )),
          ],
        ),
      ),
    );
  }
}

/// 마이페이지 골드 프로필 카드 — handoff 3 (CheerMyPage 2-1).
/// 골드 링 아바타 + 닉네임 + (최근 수상 pill) + 등급·누적. ✦ 트윙클 3개.
class _GoldProfileCard extends StatefulWidget {
  final bool isDark;
  final String nickname;
  final String? profileImageUrl;
  final String? tierName;
  final int total;

  /// 최근 수상 — '8월 1위' pill (없으면 숨김)
  final CheerCrown? crown;
  final VoidCallback onTap;

  const _GoldProfileCard({
    required this.isDark,
    required this.nickname,
    required this.profileImageUrl,
    required this.tierName,
    required this.total,
    required this.crown,
    required this.onTap,
  });

  @override
  State<_GoldProfileCard> createState() => _GoldProfileCardState();
}

class _GoldProfileCardState extends State<_GoldProfileCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tw = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4000))
    ..repeat();

  @override
  void dispose() {
    _tw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final ink = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: const Alignment(-0.6, -1),
              end: const Alignment(0.6, 1),
              colors: CheerGold.card(isDark),
            ),
            border: Border.all(color: CheerGold.border(isDark)),
            boxShadow: CheerGold.shadow(isDark),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned(
                    left: 14,
                    top: 14,
                    child: GoldTwinkle(
                        anim: _tw,
                        size: 10,
                        color: isDark
                            ? CheerGold.twinkleD
                            : CheerGold.twinkleL)),
                Positioned(
                    right: 16,
                    top: 26,
                    child: GoldTwinkle(
                        anim: _tw,
                        size: 8,
                        delaySec: 0.6,
                        color: isDark
                            ? CheerGold.twinkleD2
                            : CheerGold.twinkleL2)),
                Positioned(
                    right: 30,
                    bottom: 16,
                    child: GoldTwinkle(
                        anim: _tw,
                        size: 11,
                        delaySec: 1.3,
                        color: isDark
                            ? CheerGold.twinkleD
                            : CheerGold.twinkleL)),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      GoldAvatar(
                          size: 56,
                          isDark: isDark,
                          photoUrl: widget.profileImageUrl),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    color: ink)),
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (widget.crown != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: CheerGold.pillBg(isDark),
                                      borderRadius:
                                          BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                        '${cheerMonthLabel(widget.crown!.month)} ${widget.crown!.rank}위',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: CheerGold.pillFg(isDark))),
                                  ),
                                Text(
                                    widget.tierName == null
                                        ? '첫 응원을 기다리고 있어요'
                                        : '${widget.tierName} · ${widget.total}회',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: muted)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded,
                          size: 18,
                          color: isDark
                              ? const Color(0xFF475569)
                              : const Color(0xFFC9B896)),
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

/// 홈 위젯 배경 투명도 조절 타일 — 탭하면 슬라이더 시트(투명도 0~100%).
/// 값은 WidgetService 가 HomeWidgetPreferences 에 '불투명도'로 저장(투명도 = 100 - 불투명도).
/// AI 경로 미리보기 기준 내비 (티맵/네이버/카카오) — AI 탭 배지와 같은 시트 재사용.
class _RouteEngineTileEmbed extends StatefulWidget {
  final bool isDark;
  const _RouteEngineTileEmbed({required this.isDark});
  @override
  State<_RouteEngineTileEmbed> createState() => _RouteEngineTileEmbedState();
}

class _RouteEngineTileEmbedState extends State<_RouteEngineTileEmbed> {
  @override
  void initState() {
    super.initState();
    RouteEnginePref.version.addListener(_onChanged);
  }

  @override
  void dispose() {
    RouteEnginePref.version.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final muted =
        widget.isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final label = RouteEnginePref.label(RouteEnginePref.get());
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: SettingsScreenEmbed.settingsIconChip(
          Icons.alt_route_rounded, widget.isDark),
      title: Text('AI 경로 기준',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text('목적지 경로 미리보기를 계산할 내비',
          style: TextStyle(fontSize: 11.5, color: muted)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        SettingsValue(label, color: muted),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Icon(Icons.chevron_right_rounded, size: 20, color: muted),
        ),
      ]),
      onTap: () async {
        await showRouteEngineSheet(context);
        if (mounted) setState(() {});
      },
    );
  }
}

/// 홈 퀵메뉴 버튼 on/off (기본 켜짐)
class _ReportFabTile extends StatefulWidget {
  final bool isDark;
  const _ReportFabTile({required this.isDark});
  @override
  State<_ReportFabTile> createState() => _ReportFabTileState();
}

class _ReportFabTileState extends State<_ReportFabTile> {
  @override
  void initState() {
    super.initState();
    ReportFabPref.version.addListener(_onChanged);
  }

  @override
  void dispose() {
    ReportFabPref.version.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final muted =
        widget.isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      secondary: SettingsScreenEmbed.settingsIconChip(
          Icons.insights_rounded, widget.isDark),
      title: Text('홈 퀵메뉴',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text('홈 오른쪽 아래 버튼 — 유가·충전 리포트 등 바로가기 메뉴',
          style: TextStyle(fontSize: 11.5, color: muted)),
      value: ReportFabPref.get(),
      activeThumbColor: AppColors.gasBlue,
      onChanged: (v) async {
        await ReportFabPref.set(v);
        if (mounted) setState(() {});
      },
    );
  }
}

/// 길찾기 범위 — 추천 주유소까지만 / 목적지까지 한 번에.
/// 길찾기 시트에서도 매번 바꿀 수 있고, 여기선 기본값을 정한다(같은 값을 공유).
class _NavScopeTileEmbed extends StatefulWidget {
  final bool isDark;
  const _NavScopeTileEmbed({required this.isDark});
  @override
  State<_NavScopeTileEmbed> createState() => _NavScopeTileEmbedState();
}

class _NavScopeTileEmbedState extends State<_NavScopeTileEmbed> {
  @override
  void initState() {
    super.initState();
    NavScopePref.version.addListener(_onChanged);
  }

  @override
  void dispose() {
    NavScopePref.version.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final muted =
        widget.isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final cur = NavScopePref.get();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: SettingsScreenEmbed.settingsIconChip(
          Icons.turn_sharp_right_rounded, widget.isDark),
      title: Text('길찾기 기본',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text('추천 주유소까지만 안내할지, 목적지까지 이어서 안내할지',
          style: TextStyle(fontSize: 11.5, color: muted)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        SettingsValue(NavScopePref.label(cur), color: muted),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Icon(Icons.chevron_right_rounded, size: 20, color: muted),
        ),
      ]),
      onTap: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (ctx) {
            final dark = Theme.of(ctx).brightness == Brightness.dark;
            final m = dark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
            Widget item(String v, String title, String sub, IconData ic) =>
                ListTile(
                  leading: Icon(ic,
                      size: 22, color: cur == v ? AppColors.gasBlue : m),
                  title: Text(title,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                  subtitle: Text(sub, style: TextStyle(fontSize: 12, color: m)),
                  trailing: cur == v
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppColors.gasBlue, size: 20)
                      : null,
                  onTap: () => Navigator.pop(ctx, v),
                );
            return SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 14),
                Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: dark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 14),
                const Text('길찾기 기본',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                item(NavScopePref.destination, '목적지까지',
                    '추천 주유소를 경유지로 넣고 목적지까지 안내', Icons.flag_rounded),
                item(NavScopePref.station, '주유소까지', '추천 주유소만 목적지로 안내 (예전 방식)',
                    Icons.local_gas_station_rounded),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('길찾기 시트에서도 매번 바꿀 수 있어요',
                      style: TextStyle(fontSize: 11.5, color: m)),
                ),
                const SizedBox(height: 12),
              ]),
            );
          },
        );
        if (picked != null) await NavScopePref.set(picked);
        if (mounted) setState(() {});
      },
    );
  }
}

class _WidgetOpacityTile extends StatefulWidget {
  const _WidgetOpacityTile({required this.isDark});
  final bool isDark;
  @override
  State<_WidgetOpacityTile> createState() => _WidgetOpacityTileState();
}

class _WidgetOpacityTileState extends State<_WidgetOpacityTile> {
  int _transparency = 0; // 0 = 불투명(기본), 100 = 완전 투명

  @override
  void initState() {
    super.initState();
    WidgetService.getWidgetOpacity().then((opacity) {
      if (mounted)
        setState(() => _transparency = (100 - opacity).clamp(0, 100));
    });
  }

  Future<void> _openSheet() async {
    int temp = _transparency;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface1 : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // 설명문은 secondary — muted 는 캡션용이라 설명 문장엔 한 단계 밝게.
          final desc =
              isDark ? AppColors.darkTextSecondary : AppColors.lightTextMuted;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('위젯 배경 투명도',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('높일수록 홈 화면 위젯 배경이 투명해져요. (0% = 불투명)',
                      style: TextStyle(fontSize: 12.5, color: desc)),
                  const SizedBox(height: 12),
                  // 실시간 미리보기 — 체커보드(배경화면 대용) 위에 투명도 적용 위젯 목업.
                  // 홈 런처로 나가지 않아도 몇 %가 적당한지 바로 보이게.
                  _WidgetOpacityPreview(transparency: temp, isDark: isDark),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: temp.toDouble(),
                          min: 0,
                          max: 100,
                          divisions: 20,
                          label: '$temp%',
                          onChanged: (v) => setSheet(() => temp = v.round()),
                          onChangeEnd: (v) {
                            final t = v.round();
                            setState(() => _transparency = t);
                            // 저장은 불투명도 기준 (투명도 = 100 - 불투명도)
                            WidgetService.setWidgetOpacity(100 - t);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 46,
                        child: Text('$temp%',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color:
                                    isDark ? AppColors.darkTextPrimary : null)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted =
        widget.isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: SettingsScreenEmbed.settingsIconChip(
          Icons.opacity_rounded, widget.isDark),
      title: Text('위젯 배경 투명도',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$_transparency%',
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted)),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Icon(Icons.chevron_right_rounded, size: 20, color: muted),
        ),
      ]),
      onTap: _openSheet,
    );
  }
}

/// 위젯 투명도 실시간 미리보기 — 체커보드(배경화면 대용) 위에
/// 투명도가 적용된 위젯 목업을 그려 결과를 시트 안에서 바로 확인.
class _WidgetOpacityPreview extends StatelessWidget {
  final int transparency; // 0=불투명, 100=완전 투명
  final bool isDark;
  const _WidgetOpacityPreview(
      {required this.transparency, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final widgetBg = (isDark ? const Color(0xFF1E242E) : Colors.white)
        .withValues(alpha: (100 - transparency) / 100);
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A2E);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 108,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 체커보드 — '뒤가 비치는 정도'를 보여주는 표준 표현
            CustomPaint(painter: _CheckerPainter(isDark: isDark)),
            Center(
              child: Container(
                width: 250,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: widgetBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.local_gas_station_rounded,
                        size: 18, color: AppColors.gasBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('즐겨찾는 주유소',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: ink.withValues(alpha: 0.75))),
                          const SizedBox(height: 2),
                          Text('1,864원 · 휘발유',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: ink)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  final bool isDark;
  const _CheckerPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final a = Paint()
      ..color = isDark ? const Color(0xFF2A313C) : const Color(0xFFE7EBF0);
    final b = Paint()
      ..color = isDark ? const Color(0xFF39424F) : const Color(0xFFCBD3DC);
    const cell = 12.0;
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final even = ((x / cell).floor() + (y / cell).floor()) % 2 == 0;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), even ? a : b);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter old) => old.isDark != isDark;
}

/// 서드파티 AI(Gemini) 문구 생성 동의 토글 — 언제든 철회 가능 (App Store 5.1.2).
/// OFF 여도 AI 추천은 동일 동작, 설명 문구만 규칙 기반으로 제공됨.
class _AiConsentTile extends StatefulWidget {
  final bool isDark;
  const _AiConsentTile({required this.isDark});

  @override
  State<_AiConsentTile> createState() => _AiConsentTileState();
}

class _AiConsentTileState extends State<_AiConsentTile> {
  @override
  void initState() {
    super.initState();
    // AI 탭 다이얼로그·로그인 복원 등 외부에서 동의가 바뀌어도 반영
    // (탭이 IndexedStack 로 상시 mount 라 자동 리빌드 안 됨)
    AiConsent.version.addListener(_onChanged);
  }

  @override
  void dispose() {
    AiConsent.version.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _toggle(bool v) {
    debugPrint('[AiConsent] toggle 요청: $v (이전 ${AiConsent.value})');
    AiConsent.set(v);
    debugPrint('[AiConsent] 저장 후: ${AiConsent.value}');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final muted =
        widget.isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final on = AiConsent.value == true;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: SettingsScreenEmbed.settingsIconChip(
          Icons.auto_awesome_rounded, widget.isDark),
      title: Text('AI 안내 문구 생성 동의',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text('추천 설명 생성을 위해 차량·경로 수치를 Google Gemini로 전송',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
      trailing: Switch(
        value: on,
        onChanged: _toggle,
        activeColor: AppColors.gasBlue,
      ),
      onTap: () => _toggle(!on),
    );
  }
}

/// 마케팅(이벤트·혜택) 수신 동의 토글 — 설정 카드 톤(settingsIconChip + Switch)에 맞춤.
/// DkswCore 동의 기록 사용. 정보통신망법상 상시 철회 가능.
class _ChargeMarketingTile extends ConsumerStatefulWidget {
  final bool isDark;
  const _ChargeMarketingTile({required this.isDark});

  @override
  ConsumerState<_ChargeMarketingTile> createState() =>
      _ChargeMarketingTileState();
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
              key: 'marketing',
              title: '마케팅 정보 수신',
              required: false,
              version: '1.0'),
        )
        .version;
    await DkswCore.postConsents([
      ConsentChoice(key: 'marketing', agreed: v, version: version),
    ]);
    marketingConsentVersion.value++; // 다른 구독 위젯도 갱신
    // 서버 저장을 await — fire-and-forget 이면 토글 직후 로그아웃 시 요청이 유실돼
    // 서버에 옛 값(true)이 남고, 재로그인 복원 때 다시 켜지는 버그가 있었음.
    await UserSyncService.instance.putPrefs(marketingConsent: v);
    // 동의(ON)만으론 못 받음 — 실제 수신 위해 OS 알림 권한도 요청.
    if (v && mounted) await ensureNotifPermission(context);
    if (mounted) {
      setState(() {
        _busy = false;
        _optimistic = null; // source-of-truth로 복귀
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted =
        widget.isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    ref.watch(authProvider); // 회원가입 등 외부 동의 변경 시 리빌드 트리거
    final on = _on; // 게스트도 device 기반 consent 로 ON 가능
    void handle(bool v) => _set(v);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: SettingsScreenEmbed.settingsIconChip(
          Icons.campaign_rounded, widget.isDark),
      title: Text('이벤트·혜택 알림 받기',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
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
    // 유종 = 멀티 선택(필터 set과 동기화). 요약 표시: 'A, B' 또는 'A 외 N'.
    final fuelLabels = ref
        .watch(gasFilterProvider)
        .fuelTypes
        .map(fuelCodeLabel)
        .toList();
    final fuelSummary = fuelLabels.isEmpty
        ? '휘발유'
        : (fuelLabels.length <= 2
            ? fuelLabels.join(', ')
            : '${fuelLabels.first} 외 ${fuelLabels.length - 1}');

    // 응원 누적을 서버와 동기화 — 콘솔 리셋·다른 기기 적립이 뱃지에 늦게 반영되던 문제.
    CheerService.instance.refreshIfStale();

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
          // 소식 도착 배너 — 안 읽은 게 있을 때만 나타난다. 읽으면 사라지므로
          // 평소엔 화면이 늘어나지 않는다(상시 진입은 아래 '정보' 섹션 타일이 맡는다).
          ValueListenableBuilder<int>(
            valueListenable: InboxService.instance.unread,
            builder: (context, n, __) => n == 0
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => context.push('/inbox'),
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: isDark
                                ? const Color(0x2EF97316)
                                : const Color(0xFFFFF4E8),
                            border: Border.all(
                                color: isDark
                                    ? const Color(0x59FDBA74)
                                    : const Color(0xFFF4D6BA)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                const Text('🎁',
                                    style: TextStyle(fontSize: 15)),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text('새 소식이 $n건 도착했어요',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: isDark
                                              ? const Color(0xFFFDBA74)
                                              : const Color(0xFFC2410C))),
                                ),
                                Icon(Icons.chevron_right_rounded,
                                    size: 18,
                                    color: isDark
                                        ? const Color(0xFFFDBA74)
                                        : const Color(0xFFC2410C)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          // 응원하기 진입 — 알림 설정보다 위의 강조 카드 (handoff 3 확정)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: CheerEntryCard(),
          ),
          _sectionHeader(context, '차량 설정'),
          settingsCard(isDark, [
            _tile(context, isDark, Icons.directions_car_rounded, '차량 타입',
                settings.vehicleType.label, () {
              _showPicker(
                  context,
                  '차량 타입',
                  VehicleType.values.map((t) => t.label).toList(),
                  VehicleType.values.indexOf(settings.vehicleType),
                  (i) => ref
                      .read(settingsProvider.notifier)
                      .setVehicleType(VehicleType.values[i]));
            }),
            if (settings.vehicleType != VehicleType.ev) ...[
              settingsDivider(isDark),
              _tile(context, isDark, Icons.local_gas_station_rounded, '유종',
                  fuelSummary, () {
                _showFuelMultiPicker(context, ref);
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
            settingsDivider(isDark),
            // 종류별 수신 — 알림이 잦아 싫은 사용자가 카테고리 단위로 끄게(형 지시).
            // 유가·EV 개별 알림은 위 타일에서 따로 관리한다.
            _NotifCategoryTile(isDark: isDark),
          ]),
          // AI 추천 관련 설정은 별도 섹션 — '앱 설정' 한 카드에 9개가 몰려 있어
          // 뭐가 어디 있는지 못 찾았다(형 지적).
          // 개발자 응원하기 — 응원 진입은 위 강조 카드로 올라갔고, 여기엔 리뷰만 남는다.
          _sectionHeader(context, '개발자 응원하기'),
          settingsCard(isDark, [
            _tile(context, isDark, Icons.star_rounded, '스토어 리뷰 남겨주기', '',
                () => RatingPromptService.openReview()),
          ]),
          _sectionHeader(context, 'AI 추천'),
          settingsCard(isDark, [
            _RouteEngineTileEmbed(isDark: isDark),
            settingsDivider(isDark),
            _NavScopeTileEmbed(isDark: isDark),
            settingsDivider(isDark),
            _AiConsentTile(isDark: isDark),
          ]),
          _sectionHeader(context, '앱 설정'),
          settingsCard(isDark, [
            _tile(context, isDark, Icons.dark_mode_rounded, '테마',
                themeMode == ThemeMode.dark ? '다크' : '라이트', () {
              const modes = [ThemeMode.light, ThemeMode.dark];
              _showPicker(
                  context,
                  '테마',
                  ['라이트 모드', '다크 모드'],
                  modes.indexOf(themeMode == ThemeMode.system
                      ? ThemeMode.light
                      : themeMode),
                  (i) =>
                      ref.read(themeModeProvider.notifier).setTheme(modes[i]));
            }),
            settingsDivider(isDark),
            // 리포트는 주제별로 발행되고 내 차종에 맞는 것만 보이므로 타이틀도 맞춘다
            _tile(
                context,
                isDark,
                Icons.insights_rounded,
                switch (settings.vehicleType) {
                  VehicleType.gas => '유가 리포트',
                  VehicleType.ev => '충전 리포트',
                  VehicleType.both => '유가 · 충전 리포트',
                },
                '', () {
              Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                  builder: (_) => FuelReportScreen(
                      initialTopic: settings.vehicleType == VehicleType.ev
                          ? 'ev'
                          : 'fuel')));
            }, subtitle: '매주 흐름 분석'),
            settingsDivider(isDark),
            _ReportFabTile(isDark: isDark),
            settingsDivider(isDark),
            _WidgetOpacityTile(isDark: isDark),
            settingsDivider(isDark),
            _ChargeMarketingTile(isDark: isDark),
          ]),
          _SupportEmbed(isDark: isDark),
          _sectionHeader(context, '정보'),
          settingsCard(isDark, [
            _tile(
                context,
                isDark,
                Icons.share_rounded,
                '친구에게 추천하기',
                '',
                () => Share.share('전기차 기름차 - 충전소·주유소 실시간 최저가·빈자리 알림 앱\n'
                    'https://play.google.com/store/apps/details?id=com.dksw.charge')),
            settingsDivider(isDark),
            // 광고 문의는 앱 동작 설정이 아니라 대외 안내라 '앱 설정' 카드에서 분리 (형 지적)
            _tile(context, isDark, Icons.campaign_rounded, '광고 문의', '', () {
              Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => const AdInquiryScreen()));
            }, subtitle: '앱 지면에 광고를 싣고 싶다면'),
            settingsDivider(isDark),
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
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Copyright 2026. 동키소프트웨어 All rights reserved.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
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

  Widget _tile(BuildContext context, bool isDark, IconData icon, String title,
      String value, VoidCallback? onTap,
      {String? subtitle}) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: settingsIconChip(icon, isDark),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      // 설명문은 값(trailing)이 아니라 부제로 — 값 자리에 넣으면 타이틀을 굶긴다.
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: muted)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        SettingsValue(value, color: muted),
        if (onTap != null)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Icon(Icons.chevron_right_rounded, size: 20, color: muted),
          ),
      ]),
      onTap: onTap,
    );
  }

  void _showPicker(BuildContext context, String title, List<String> options,
      int selected, ValueChanged<int> onSelect) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        // 옵션이 많거나 큰 폰트여도 넘치지 않게 85% 높이 제한 + 스크롤.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...List.generate(
                  options.length,
                  (i) => ListTile(
                        title: Text(options[i]),
                        trailing: i == selected
                            ? const Icon(Icons.check, color: AppColors.gasBlue)
                            : null,
                        onTap: () {
                          onSelect(i);
                          Navigator.pop(context);
                        },
                      )),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }

  // 유종 복수 선택 시트 — 필터 set(gasFilterProvider.fuelTypes)과 동기화. 최소 1개 유지.
  void _showFuelMultiPicker(BuildContext context, WidgetRef ref) {
    const order = [
      FuelType.premium,
      FuelType.gasoline,
      FuelType.diesel,
      FuelType.lpg,
    ];
    final selected = Set<String>.from(ref.read(gasFilterProvider).fuelTypes);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 16),
            Text('유종 (복수 선택)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...order.map((t) {
              final on = selected.contains(t.code);
              return ListTile(
                title: Text(t.label),
                trailing: Icon(
                    on
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: on ? AppColors.gasBlue : const Color(0xFFB0B7C0)),
                onTap: () => setSheet(() {
                  if (on) {
                    if (selected.length > 1) selected.remove(t.code);
                  } else {
                    selected.add(t.code);
                  }
                }),
              );
            }),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gasBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    final list = order
                        .where((t) => selected.contains(t.code))
                        .map((t) => t.code)
                        .toList();
                    if (list.isEmpty) return;
                    // ⚠ 순서 중요: setFuelType 이 내부에서 filter 를 [단일]로 동기하므로
                    //   먼저 호출(primary=첫 유종) → 그 다음 멀티로 덮어써야 멀티가 살아남는다.
                    ref
                        .read(settingsProvider.notifier)
                        .setFuelType(FuelType.fromCode(list.first));
                    ref.read(gasFilterProvider.notifier).setFuelTypes(list);
                    Navigator.pop(ctx);
                  },
                  child: const Text('확인'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
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
    debugPrint(
        '[SupportEmbed] fetched: n=${c.notices} e=${c.events} f=${c.faqs}');
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
        final hasE = c != null && c.events > 0;
        final hasF = c != null && c.faqs > 0;
        final isDark = widget.isDark;
        final muted =
            isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

        Widget tile(IconData icon, String title, int count, String route) =>
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: SettingsScreenEmbed.settingsIconChip(icon, isDark),
              title: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (count > 0)
                  Text('$count', style: TextStyle(fontSize: 13, color: muted)),
                if (count > 0) const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 20, color: muted),
              ]),
              onTap: () => context.push(route),
            );

        final tiles = <Widget>[
          // 내 소식함 — 공지사항과 같은 규칙으로 **항상 노출**한다. 새 게 없어도
          // 지난 쿠폰·메시지를 다시 봐야 한다. 우측 숫자는 안 읽은 개수(0이면 안 보임).
          ValueListenableBuilder<int>(
            valueListenable: InboxService.instance.unread,
            builder: (_, n, __) =>
                tile(Icons.mail_outline_rounded, '내 소식함', n, '/inbox'),
          ),
          // 공지사항은 글이 없어도 항상 노출.
          tile(Icons.campaign_rounded, '공지사항', c?.notices ?? 0, '/notices'),
          if (hasE)
            tile(Icons.celebration_rounded, '이벤트', c!.events, '/events'),
          if (hasF)
            tile(Icons.help_outline_rounded, '자주 묻는 질문', c!.faqs, '/faq'),
          // 1:1 문의하기 — 항상 노출
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: SettingsScreenEmbed.settingsIconChip(
                Icons.support_agent_rounded, isDark),
            title: Text('1:1 문의하기',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            trailing: Icon(Icons.chevron_right_rounded, size: 20, color: muted),
            onTap: () async {
              // 1:1 문의는 로그인 전용 — 내역이 기기 바꿔도 유지되도록.
              final token = await AuthService.accessToken();
              if (!context.mounted) return;
              if (token == null || token.isEmpty) {
                final go = await showAppDialog<bool>(
                  context,
                  icon: Icons.lock_outline_rounded,
                  title: '로그인이 필요해요',
                  message: '1:1 문의는 로그인 후 이용할 수 있어요.\n문의 내역이 기기를 바꿔도 유지돼요.',
                  primaryLabel: '로그인',
                  primaryValue: true,
                  secondaryLabel: '취소',
                  secondaryValue: false,
                );
                if (go == true && context.mounted) context.push('/login');
              } else {
                context.push('/inquiry');
              }
            },
          ),
          // 내 제보 내역 — 기기 기준이라 로그인 불필요.
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: SettingsScreenEmbed.settingsIconChip(
                Icons.fact_check_outlined, isDark),
            title: Text('내 제보 내역',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            trailing: Icon(Icons.chevron_right_rounded, size: 20, color: muted),
            onTap: () => context.push('/my-reports'),
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

// ─── 알림 종류별 수신 (리포트 · 공지 · 이벤트) ───
/// 서버(push_devices.notif_*)에 저장돼 발송 시점에 필터된다.
/// 여기서 끈 종류는 아예 발송 대상에서 빠진다(방해금지처럼 소리만 죽이는 게 아니다).
class _NotifCategoryTile extends StatefulWidget {
  final bool isDark;
  const _NotifCategoryTile({required this.isDark});

  @override
  State<_NotifCategoryTile> createState() => _NotifCategoryTileState();
}

class _NotifCategoryTileState extends State<_NotifCategoryTile> {
  static const _items = [
    (NotifPrefsService.keyReport, '유가·충전 리포트', '주간 분석과 오늘의 유가'),
    (NotifPrefsService.keyNotice, '공지사항', '점검·업데이트 안내'),
    (NotifPrefsService.keyEvent, '이벤트·혜택', '이벤트 소식'),
  ];

  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // 서버 값으로 캐시 동기화 — 기기를 바꿔도 설정이 따라온다.
    NotifPrefsService.instance.fetch().then((v) {
      if (v != null && mounted) setState(() {});
    });
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() {});
    final ok = await NotifPrefsService.instance.set(key, value);
    if (!mounted) return;
    setState(() {});
    if (!ok) {
      showAppToast(context, '설정을 저장하지 못했어요. 잠시 후 다시 시도해주세요',
          isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final svc = NotifPrefsService.instance;
    final offCount = _items.where((e) => !svc.cached(e.$1)).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: SettingsScreenEmbed.settingsIconChip(
              Icons.tune_rounded, isDark),
          title: Text('알림 종류별 수신',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(
              offCount == 0 ? '리포트 · 공지 · 이벤트 모두 받는 중' : '$offCount종류 끔',
              style: TextStyle(fontSize: 11.5, color: muted)),
          trailing: Icon(
              _expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 22,
              color: muted),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          for (final it in _items)
            SwitchListTile(
              contentPadding:
                  const EdgeInsets.only(left: 66, right: 14, bottom: 2),
              dense: true,
              value: svc.cached(it.$1),
              onChanged: (v) => _toggle(it.$1, v),
              title: Text(it.$2,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary)),
              subtitle: Text(it.$3,
                  style: TextStyle(fontSize: 11, color: muted)),
              activeThumbColor: AppColors.gasBlue,
            ),
      ],
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
  bool _notifGranted = true; // OS 알림 권한 — 미허용이면 토글 표시 OFF

  @override
  void initState() {
    super.initState();
    _refresh();
    _checkNotifPermission();
    AlertService().fetchLimits(); // 설정 열 때 알림 한도 최신화(콘솔 변경 반영)
    AlertService().subsChanged.addListener(_refresh);
  }

  @override
  void dispose() {
    AlertService().subsChanged.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _checkNotifPermission() async {
    final granted = await Permission.notification.isGranted;
    if (mounted) {
      setState(() {
        _notifGranted = granted;
        _enabled = AlertService().alertsEnabled && granted;
      });
    }
  }

  void _refresh() {
    setState(() {
      // 권한 없으면 저장값과 무관하게 OFF 로 표시 (실제 푸시 못 받으므로).
      _enabled = AlertService().alertsEnabled && _notifGranted;
      _ids = AlertService().subscribedStationIds;
      _alertHour = AlertService().alertHour;
      _alertMinute = AlertService().alertMinute;
      _soundMode = AlertService().alertSoundMode;
      if (_ids.isEmpty) _expanded = false;
    });
  }

  Future<void> _toggleEnabled(bool value) async {
    if (value) {
      final ok = await ensureNotifPermission(context);
      if (!ok || !mounted) return;
      _notifGranted = true;
    }
    setState(() => _toggling = true);
    await AlertService().setAlertsEnabled(value);
    if (!mounted) return;
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
    final mutedColor =
        isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final secondaryColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Icon(
            _enabled
                ? Icons.notifications_rounded
                : Icons.notifications_off_rounded,
            size: 22,
            color: _enabled ? AppColors.gasBlue : secondaryColor,
          ),
          title:
              Text('주유 가격 알림', style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            _enabled
                ? '${_ids.isEmpty ? '알림 주유소 없음' : '${_ids.length}/${AlertService.gasAlarmMaxCount}곳 설정됨'} · 매일 $_alertTimeText 발송'
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: AppColors.gasBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _alertTimeText,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.gasBlue),
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
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          size: 22, color: mutedColor),
                    ),
                  ),
                ),
              _toggling
                  ? const SizedBox(
                      width: 36,
                      height: 20,
                      child: Center(
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))))
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
          onTap: _ids.isNotEmpty
              ? () => setState(() => _expanded = !_expanded)
              : null,
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.gasBlue.withValues(alpha: 0.15)
                              : (isDark
                                  ? const Color(0x0AFFFFFF)
                                  : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? AppColors.gasBlue
                                : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal,
                            color:
                                selected ? AppColors.gasBlue : secondaryColor,
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
                    color: isDark
                        ? const Color(0x0AFFFFFF)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(0x14FFFFFF)
                          : const Color(0xFFE2E8F0),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    children: _ids.map((id) {
                      final name = StationAliasService.resolve(
                          id, AlertService().stationName(id),
                          type: 'gas');
                      final fuelTypes = AlertService().subscribedFuelTypes(id);
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
                        leading: Icon(Icons.local_gas_station_rounded,
                            size: 18, color: AppColors.gasBlue),
                        title: Text(name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                        subtitle: fuelTypes.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Wrap(
                                  spacing: 4,
                                  children: fuelTypes
                                      .map((ft) => Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.gasBlue
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                                AlertService.fuelLabel(ft),
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.gasBlue,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ))
                                      .toList(),
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
  State<_EvAlarmSettingTileEmbed> createState() =>
      _EvAlarmSettingTileEmbedState();
}

class _EvAlarmSettingTileEmbedState extends State<_EvAlarmSettingTileEmbed> {
  late List<String> _ids;
  late int _soundMode;
  late bool _enabled;
  bool _expanded = false;
  bool _notifGranted = true; // OS 알림 권한 — 미허용이면 토글 표시 OFF

  @override
  void initState() {
    super.initState();
    _refresh();
    _checkNotifPermission();
    AlertService().fetchLimits(); // 설정 열 때 알림 한도 최신화(콘솔 변경 반영)
    AlertService().subsChanged.addListener(_refresh);
  }

  @override
  void dispose() {
    AlertService().subsChanged.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _checkNotifPermission() async {
    final granted = await Permission.notification.isGranted;
    if (mounted) {
      setState(() {
        _notifGranted = granted;
        _enabled = AlertService().evAlarmEnabled && granted;
        if (!_enabled) _expanded = false;
      });
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _ids = AlertService().evAlarmStationIds;
      _soundMode = AlertService().evAlarmSoundMode;
      // 권한 없으면 저장값과 무관하게 OFF 로 표시.
      _enabled = AlertService().evAlarmEnabled && _notifGranted;
      if (_ids.isEmpty || !_enabled) _expanded = false;
    });
  }

  Future<void> _toggleEnabled(bool value) async {
    if (value) {
      final ok = await ensureNotifPermission(context);
      if (!ok || !mounted) return;
      _notifGranted = true;
    }
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
    final mutedColor =
        isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final secondaryColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Icon(
            _enabled
                ? Icons.ev_station_rounded
                : Icons.notifications_off_rounded,
            size: 22,
            color: (_enabled && _ids.isNotEmpty)
                ? AppColors.evGreen
                : secondaryColor,
          ),
          title:
              Text('충전소 현황 알림', style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            !_enabled
                ? '알림 꺼짐'
                : (_ids.isEmpty
                    ? '알림 설정된 충전소 없음'
                    : '${_ids.length}/${AlertService.evAlarmMaxCount}곳 설정됨'),
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
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          size: 22, color: mutedColor),
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
          onTap: (_enabled && _ids.isNotEmpty)
              ? () => setState(() => _expanded = !_expanded)
              : null,
        ),
        if (_enabled && _ids.isNotEmpty)
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
                        AlertService().setEvAlarmSoundMode(idx);
                        setState(() => _soundMode = idx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.evGreen.withValues(alpha: 0.15)
                              : (isDark
                                  ? const Color(0x0AFFFFFF)
                                  : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? AppColors.evGreen
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal,
                            color:
                                selected ? AppColors.evGreen : secondaryColor,
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
                    color: isDark
                        ? const Color(0x0AFFFFFF)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(0x14FFFFFF)
                          : const Color(0xFFE2E8F0),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    children: _ids.map((id) {
                      final name = StationAliasService.resolve(
                          id, AlertService().evAlarmStationName(id),
                          type: 'ev');
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
                        leading: const Icon(Icons.ev_station_rounded,
                            size: 18, color: AppColors.evGreen),
                        title: Text(name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.redAccent, size: 20),
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
  late bool _allDay = AlertService().dndAllDay;

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
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Icon(Icons.bedtime_rounded,
              size: 22, color: _enabled ? AppColors.gasBlue : secondary),
          title:
              Text('방해 금지 시간', style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            !_enabled
                ? '꺼짐'
                : (_allDay
                    ? '24시간 · 알림 소리 없이 보관'
                    : '${_fmt(_startMin)} ~ ${_fmt(_endMin)} · 알림 소리 없이 보관'),
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
                    Expanded(
                      child: Text('24시간 (항상)',
                          style: TextStyle(fontSize: 13, color: secondary)),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: _allDay,
                        onChanged: (v) {
                          setState(() => _allDay = v);
                          AlertService().setDnd(allDay: v);
                        },
                        activeThumbColor: AppColors.gasBlue,
                      ),
                    ),
                  ],
                ),
                if (!_allDay)
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
                  _allDay
                      ? '항상 알림을 소리 없이 보관해요. 자리변동 알림은 제외돼요.'
                      : '이 시간엔 알림이 소리 없이 보관돼요. 자리변동 알림은 제외돼요.',
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
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.gasBlue)),
          ],
        ),
      ),
    );
  }
}

/// 유종 퀵 토글 고정 헤더 — 스크롤 시 상단에 붙는다 (사용자 제보 반영).
/// 고정 상태에서 리스트가 비쳐 보이지 않게 불투명 배경 + 겹칠 때만 헤어라인.
class _FuelChipsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final bool isDark;
  final Widget child;
  // 유종 목록·활성 유종·테마의 시그니처 — 이것이 달라질 때만 헤더 리빌드.
  final String signature;
  const _FuelChipsHeaderDelegate({
    required this.isDark,
    required this.child,
    required this.signature,
  });

  static const double _extent = 46;

  @override
  double get minExtent => _extent;
  @override
  double get maxExtent => _extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: _extent,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : AppColors.lightBg,
        border: overlapsContent
            ? Border(
                bottom: BorderSide(
                  color: isDark
                      ? AppColors.darkCardBorder
                      : const Color(0xFFE8ECF0),
                  width: 0.5,
                ),
              )
            : null,
      ),
      alignment: Alignment.center,
      child: SizedBox(height: 40, child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _FuelChipsHeaderDelegate oldDelegate) =>
      oldDelegate.signature != signature;
}

/// 플로팅 알약 바가 화면 하단에서 실제로 가리는 높이 (AI 원형 오버행 포함).
///
/// extendBody:true 라 body 는 바 뒤까지 흐른다 — 지도/AI 시트처럼 화면 바닥에
/// 붙는 UI 는 이 값만큼 띄워야 핸들·헤더가 바(특히 가운데 AI 원)에 안 가린다.
/// 형 제보: "AI 추천 때문에 드래그해서 위로 올리기 힘들다".
double floatingNavOverlayPx(BuildContext context) {
  final inset = MediaQuery.of(context).viewPadding.bottom;
  return _AiBottomNav.overhang +
      _AiBottomNav.barH +
      (inset > 0 ? inset : 10);
}

/// 하단 탭바 — 가운데 AI 만 바 위로 떠 있는 그라데이션 원형 버튼 (형 시안 2026-08-04).
///
/// NavigationBar 를 버리고 커스텀으로 그린 이유: 표준 위젯으론 특정 탭만 바 밖으로
/// 띄울 수 없다. 원이 바 위로 나가는 부분까지 탭이 먹히려면 hit-test 영역 안에 있어야
/// 해서, 바 전체 높이를 (투명 상단 22 + 실제 바 58) 로 잡고 원을 그 안에 배치한다.
class _AiBottomNav extends StatelessWidget {
  const _AiBottomNav({
    required this.index,
    required this.isDark,
    required this.onSelect,
  });

  final int index;
  final bool isDark;
  final ValueChanged<int> onSelect;

  static const overhang = 22.0; // 원이 바 위로 튀어나오는 높이 (투명 영역)
  // 58 은 아이콘+라벨이 꽉 차 보였다(형 확인) — 위아래 여백을 줘 알약형이 살게.
  static const barH = 66.0;
  static const _circle = 62.0;

  @override
  Widget build(BuildContext context) {
    // 플로팅 알약형 (형 시안 v2) — 화면 가장자리에서 띄우고 전체 라운드.
    final barBg = isDark ? AppColors.darkSurface1 : Colors.white;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding:
          EdgeInsets.fromLTRB(12, 0, 12, bottomInset > 0 ? bottomInset : 10),
      child: SizedBox(
        height: overhang + barH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── 바 본체 (하단 고정, 상단 22px 는 투명 — 원이 떠 있을 자리) ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: barH,
              child: Container(
                decoration: BoxDecoration(
                  color: barBg,
                  borderRadius: BorderRadius.circular(29),
                  border: isDark
                      ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.42 : 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _tab(0, Icons.dashboard_outlined, Icons.dashboard_rounded,
                        '홈'),
                    _tab(1, Icons.map_outlined, Icons.map_rounded, '지도'),
                    // 가운데는 원형 버튼 자리 — 빈 슬롯으로 폭만 확보
                    const Expanded(child: SizedBox.shrink()),
                    _tab(3, Icons.favorite_outline_rounded,
                        Icons.favorite_rounded, '즐겨찾기'),
                    _tab(4, Icons.person_outline_rounded, Icons.person_rounded,
                        '마이페이지'),
                  ],
                ),
              ),
            ),
            // ── AI 원형 버튼 — 바 상단에 걸쳐 떠 있음 ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => onSelect(2),
                  child: Container(
                    width: _circle,
                    height: _circle,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2563EB), Color(0xFF10B981)],
                      ),
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: barBg, width: 3), // 바와 겹치는 경계를 깔끔하게
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB)
                              .withValues(alpha: index == 2 ? 0.5 : 0.32),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 19, color: Colors.white),
                        SizedBox(height: 2),
                        Text('AI 추천',
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                height: 1,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(int i, IconData icon, IconData selectedIcon, String label) {
    final selected = index == i;
    final color = selected
        ? (isDark ? AppColors.gasBlue : AppColors.gasBlueDark)
        : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? selectedIcon : icon, size: 23, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
