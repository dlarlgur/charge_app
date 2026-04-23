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
    ],
  );
});
