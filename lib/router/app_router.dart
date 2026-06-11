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
import '../ui/notices/notices_screen.dart';
import '../ui/events/events_screen.dart';
import '../ui/faq/faq_screen.dart';
import 'package:dksw_app_core/dksw_app_core.dart' show InquiryScreen;
import '../ui/widgets/inquiry_native_ad_banner.dart';
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
      GoRoute(path: '/policies', builder: (_, __) => const PoliciesScreen()),
      GoRoute(path: '/notices', builder: (_, __) => const NoticesScreen()),
      GoRoute(path: '/events', builder: (_, __) => const EventsScreen()),
      GoRoute(path: '/faq', builder: (_, __) => const FaqScreen()),
      GoRoute(
        path: '/inquiry',
        builder: (_, __) => InquiryScreen(
          appId: AppConstants.packageName,
          deviceId: AlertService().deviceId,
          topBanner: const InquiryNativeAdBanner(),
          bannerAboveHeader: true, // '내 문의 N건' 카드 위에 노출
        ),
      ),
    ],
  );
});
