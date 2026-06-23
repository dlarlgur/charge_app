import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/models/models.dart';
import '../ui/permission/permission_screen.dart';
import '../ui/onboarding/onboarding_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/splash/splash_screen.dart';
import '../core/navigation/app_route_observer.dart';
import '../ui/detail/gas_detail_screen.dart';
import '../ui/detail/ev_detail_screen.dart';
import '../ui/settings/settings_screen.dart';
import '../ui/settings/policies_screen.dart';
import '../ui/auth/login_screen.dart';
import '../ui/auth/account_screen.dart';
import '../ui/notices/notices_screen.dart';
import '../ui/events/events_screen.dart';
import '../ui/faq/faq_screen.dart';
import 'package:dksw_app_core/dksw_app_core.dart' show InquiryScreen, DkswTopBanner;
import 'package:flutter/widgets.dart' show EdgeInsets;
import '../ui/widgets/inquiry_native_ad_banner.dart';
import '../data/services/auth_service.dart' show authProvider;
import '../data/services/alert_service.dart';
import '../core/constants/api_constants.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    observers: [appRouteObserver],
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/permission', builder: (_, __) => const PermissionScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
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
      GoRoute(
        path: '/login',
        builder: (_, state) =>
            LoginScreen(gate: state.uri.queryParameters['gate'] == '1'),
      ),
      GoRoute(path: '/account', builder: (_, __) => const AccountScreen()),
      GoRoute(path: '/policies', builder: (_, __) => const PoliciesScreen()),
      GoRoute(path: '/notices', builder: (_, __) => const NoticesScreen()),
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
