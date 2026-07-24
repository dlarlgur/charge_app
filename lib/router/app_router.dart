import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../data/models/models.dart';
import '../ui/permission/permission_screen.dart';
import '../ui/onboarding/onboarding_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/splash/splash_screen.dart';
import '../data/services/notification_service.dart'
    show navigateToGasStationNotifier, navigateToEvStationNotifier;
import '../core/navigation/app_route_observer.dart';
import '../ui/detail/gas_detail_screen.dart';
import '../ui/detail/ev_detail_screen.dart';
import '../ui/settings/settings_screen.dart';
import '../ui/settings/policies_screen.dart';
import '../ui/auth/login_screen.dart';
import '../ui/auth/account_screen.dart';
import '../ui/notices/notices_screen.dart';
import '../ui/reports/my_reports_screen.dart';
import '../ui/events/events_screen.dart';
import '../ui/faq/faq_screen.dart';
import 'package:dksw_app_core/dksw_app_core.dart'
    show InquiryScreen, DkswTopBanner;
import 'package:flutter/widgets.dart'
    show EdgeInsets, Widget, FadeTransition;
import '../ui/widgets/inquiry_native_ad_banner.dart';
import '../data/services/auth_service.dart' show authProvider;
import '../data/services/alert_service.dart';
import '../core/constants/api_constants.dart';

/// 스플래시에서 진입하는 최상위 화면용 페이드 전환 — 로고→광고→메인이 툭 끊기지
/// 않고 부드럽게 이어지도록. (일반 push/pop 은 기존 플랫폼 전환 유지)
CustomTransitionPage<void> _fadePage(Widget child) => CustomTransitionPage<void>(
      child: child,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (_, anim, __, c) =>
          FadeTransition(opacity: anim, child: c),
    );

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    // iOS 위젯 딥링크 안전망 — host형(chargehelper://widget?..)으로 와도 처리.
    redirect: (context, state) {
      if (state.uri.host == 'widget') {
        final type = state.uri.queryParameters['type'] ?? '';
        final id = state.uri.queryParameters['id'] ?? '';
        if (id.isNotEmpty) {
          if (type == 'ev') {
            navigateToEvStationNotifier.value = id;
          } else if (type == 'gas') {
            navigateToGasStationNotifier.value = id;
          }
        }
        return '/home';
      }
      return null;
    },
    observers: [
      appRouteObserver,
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
    ],
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
          path: '/permission',
          pageBuilder: (_, __) => _fadePage(const PermissionScreen())),
      GoRoute(
          path: '/onboarding',
          pageBuilder: (_, __) => _fadePage(const OnboardingScreen())),
      GoRoute(
          path: '/home', pageBuilder: (_, __) => _fadePage(const HomeScreen())),
      GoRoute(
        path: '/gas/:id',
        builder: (_, state) => GasDetailScreen(
          stationId: state.pathParameters['id']!,
          station: state.extra as GasStation?,
        ),
      ),
      GoRoute(
        path: '/ev/:id',
        builder: (_, state) => EvDetailScreen(
          stationId: state.pathParameters['id']!,
          station: state.extra as EvStation?,
        ),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      // iOS 홈위젯 탭 딥링크 (chargehelper://widget?type=gas|ev&id=...).
      // 안드로이드는 pending 키 방식이라 이 경로를 안 탄다. notifier 세팅 후 홈으로.
      GoRoute(
        path: '/widget',
        redirect: (context, state) {
          final type = state.uri.queryParameters['type'] ?? '';
          final id = state.uri.queryParameters['id'] ?? '';
          if (id.isNotEmpty) {
            if (type == 'ev') {
              navigateToEvStationNotifier.value = id;
            } else if (type == 'gas') {
              navigateToGasStationNotifier.value = id;
            }
          }
          return '/home';
        },
      ),
      GoRoute(
        path: '/login',
        builder: (_, state) =>
            LoginScreen(gate: state.uri.queryParameters['gate'] == '1'),
      ),
      GoRoute(path: '/account', builder: (_, __) => const AccountScreen()),
      GoRoute(path: '/policies', builder: (_, __) => const PoliciesScreen()),
      GoRoute(path: '/notices', builder: (_, __) => const NoticesScreen()),
      GoRoute(path: '/my-reports', builder: (_, __) => const MyReportsScreen()),
      GoRoute(path: '/events', builder: (_, __) => const EventsScreen()),
      GoRoute(path: '/faq', builder: (_, __) => const FaqScreen()),
      GoRoute(
        path: '/inquiry',
        builder: (_, state) => InquiryScreen(
          appId: AppConstants.packageName,
          deviceId: AlertService().deviceId,
          userId: ref.read(authProvider)?.id, // 로그인 사용자면 문의자 매칭용 id 전달

          // 콘솔 inquiry_top 광고가 bypass 면 그걸, 아니면 AdMob(InquiryNativeAdBanner).
          topBanner: const DkswTopBanner(
            placement: 'inquiry_top',
            margin: EdgeInsets.zero,
            admobFallback: InquiryNativeAdBanner(),
          ),
          bannerAboveHeader: true, // '내 문의 N건' 카드 위에 노출
          // 답변 푸시 탭 → 그 문의 상세 자동 오픈 (deep-link)
          initialInquiryId: state.extra is int ? state.extra as int : null,
        ),
      ),
    ],
  );
});
