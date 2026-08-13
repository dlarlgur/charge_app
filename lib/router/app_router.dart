import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
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
import '../ui/inbox/inbox_screen.dart';
import '../ui/notices/notices_screen.dart';
import '../ui/reports/my_reports_screen.dart';
import '../ui/reports/fuel_report_screen.dart';
import '../ui/events/events_screen.dart';
import '../ui/faq/faq_screen.dart';
import 'package:dksw_app_core/dksw_app_core.dart'
    show InquiryScreen, DkswTopBanner;
import 'package:flutter/widgets.dart' show EdgeInsets;
import '../ui/widgets/inquiry_native_ad_banner.dart';
import '../data/services/auth_service.dart' show authProvider;
import '../data/services/alert_service.dart';
import '../core/constants/api_constants.dart';

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
    // 카카오 로그인 콜백(kakao{appkey}://oauth?code=...)이 딥링크로 들어오면 매칭되는
    // 라우트가 없어 "no routes for location" 예외가 난다(= 카카오 로그인 후 page not found).
    // Kakao SDK 가 이 URL 로 토큰을 자체 처리하므로, go_router 는 라우팅하지 말고 현재
    // 화면(로그인)을 유지하도록 예외만 삼킨다. navigate 하면 로그인 화면이 재빌드되어
    // 진행 중인 로그인 future 가 끊기므로 아무 것도 하지 않는다.
    onException: (context, state, router) {
      if (state.uri.scheme.startsWith('kakao')) return;
      router.go('/home'); // 그 외 알 수 없는 경로는 홈으로 안전 이동
    },
    observers: [
      appRouteObserver,
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
    ],
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
          path: '/permission', builder: (_, __) => const PermissionScreen()),
      GoRoute(
          path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
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
      // 내 소식함 — ?id= 로 특정 항목 상세를 바로 연다(푸시/시상식 배너 딥링크).
      GoRoute(
        path: '/inbox',
        builder: (_, state) => InboxScreen(
            openId: int.tryParse(state.uri.queryParameters['id'] ?? '')),
      ),
      GoRoute(path: '/notices', builder: (_, __) => const NoticesScreen()),
      GoRoute(path: '/my-reports', builder: (_, __) => const MyReportsScreen()),
      GoRoute(path: '/fuel-reports', builder: (_, __) => const FuelReportScreen()),
      GoRoute(path: '/events', builder: (_, __) => const EventsScreen()),
      GoRoute(path: '/faq', builder: (_, __) => const FaqScreen()),
      GoRoute(
        path: '/inquiry',
        builder: (_, state) => InquiryScreen(
          appId: AppConstants.packageName,
          deviceId: AlertService().deviceId,
          userId: ref.read(authProvider)?.id, // 로그인 사용자면 문의자 매칭용 id 전달
          // 문의 사진 첨부 — 앱이 picker 를 주입(코어는 UI/업로드만, chat_llm 등 미주입 앱 안전)
          attachPicker: () async {
            final x = await ImagePicker().pickImage(
                source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
            return x?.path;
          },
          // 여러 장 한번에 선택 — 픽커 자체를 남은 슬롯(최대 3장)으로 제한
          attachMultiPicker: (remaining) async {
            if (remaining <= 1) {
              // pickMultiImage 의 limit 은 2 이상만 허용 — 남은 1장은 단일 픽커로
              final x = await ImagePicker().pickImage(
                  source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
              return x == null ? null : [x.path];
            }
            final xs = await ImagePicker().pickMultiImage(
                maxWidth: 1600, imageQuality: 85, limit: remaining.clamp(2, 3));
            return xs.map((x) => x.path).toList();
          },

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
