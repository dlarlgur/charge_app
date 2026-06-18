import 'dart:async';

import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/update/app_updater.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/splash_ad_cache.dart';
import '../../providers/providers.dart';
import '../widgets/update_dialog.dart';

/// 흐름 (stale-while-revalidate):
/// 1. 시작 시 디스크 캐시된 광고를 즉시 native splash 아래로 push.
///    - 이미지 바이트는 미리 Flutter image cache 에 꽂아두므로 첫 프레임에 그려짐.
/// 2. main.dart 의 0.5초 타이머가 native splash 를 내림 → 흰 갭 없이 광고 등장.
/// 3. 동시에 bootstrap 호출 → 응답으로 캐시 갱신/삭제 (다음 실행 반영).
/// 4. update / maintenance 결과는 ad 화면 위에 덮어써서 처리.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _adShownFromCache = false;
  // bootstrap 결과(점검 여부 포함)를 광고 pop 경로에서도 보장하기 위해 future 보관 + 중복 라우팅 가드.
  Future<BootstrapResult?>? _bootstrapFuture;
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;

    // 1단계: 캐시된 광고 즉시 노출.
    final cached = SplashAdCache.read();
    if (cached != null) {
      final (ad, bytes) = cached;
      final resolved = DkswCore.resolveAssetUrl(ad.imageUrl);
      final ok = await SplashAdCache.installInImageCache(resolved, bytes);
      if (ok && mounted) {
        _adShownFromCache = true;
        // SplashAdScreen 을 native splash 아래에 push — 0초 전환.
        // pop 이후 흐름은 _afterAdOrSkip 에서 처리.
        unawaited(
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => SplashAdScreen(ad: ad),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          ).then((_) => _afterAdOrSkip()),
        );
        // 광고 첫 frame 그려진 뒤 native splash 제거 — 두 화면 사이 흰 갭 차단.
        WidgetsBinding.instance.addPostFrameCallback((_) => FlutterNativeSplash.remove());
      }
    }

    // 2단계: bootstrap 으로 캐시 갱신 + maintenance/update 처리.
    // 타임아웃을 넉넉히(4s) — 점검 응답을 놓치지 않도록(특히 debug/느린망).
    debugPrint('[SplashScreen] bootstrap 시작 (cache=${cached != null})');
    _bootstrapFuture = DkswCore.bootstrap(timeout: const Duration(seconds: 4));
    final result = await _bootstrapFuture;
    debugPrint('[SplashScreen] bootstrap 결과: force=${result?.update.forceUpdate}, ad=${result?.ad != null}, maintenance=${result?.maintenance != null}');
    if (!mounted) return;

    // 캐시 갱신: 새 광고/없음/동일 광고 케이스.
    final fresh = result?.ad;
    if (fresh != null) {
      if (!SplashAdCache.isSameAsCached(fresh)) {
        unawaited(SplashAdCache.save(fresh));
      }
    } else {
      unawaited(SplashAdCache.clear());
    }

    if (result?.maintenance != null) {
      _showMaintenance(result!.maintenance!);
      return;
    }

    if (result != null &&
        (result.update.forceUpdate || result.update.optionalUpdate)) {
      FlutterNativeSplash.remove();
      final native = result.update.forceUpdate
          ? await AppUpdater.tryImmediateUpdate()
          : await AppUpdater.tryFlexibleUpdate();
      if (!mounted) return;

      if (native == InAppUpdateResult.started) {
        if (result.update.forceUpdate) return;
      } else {
        await UpdateDialog.showIfNeeded(context, result.update);
        if (!mounted) return;
        if (result.update.forceUpdate) return;
      }
    }

    if (!mounted) return;

    // 광고를 캐시로 이미 보여줬다면 SplashAdScreen 의 displayMs 만료까지
    // 후속 네비게이션은 _afterAdOrSkip 에서 일어남.
    if (_adShownFromCache) return;

    // 캐시 없을 때(첫 실행 등): 광고 스킵, 바로 다음 화면.
    _removeNativeSplashNextFrame();
    _navigateNext();
  }

  // 캐시 광고가 닫힌 뒤 호출. bootstrap 이 아직이면 기다렸다가 점검 여부를 먼저 확인한다.
  // (이전엔 광고 pop → 곧장 홈 이동하며 SplashScreen 이 unmount → 점검 체크를 놓치는 레이스가 있었음)
  Future<void> _afterAdOrSkip() async {
    if (_routed) return;
    final result = await (_bootstrapFuture ?? Future.value(DkswCore.lastBootstrap));
    if (!mounted || _routed) return;
    if (result?.maintenance != null) {
      _showMaintenance(result!.maintenance!);
      return;
    }
    _navigateNext();
  }

  void _showMaintenance(Maintenance m) {
    if (_routed || !mounted) return;
    _routed = true;
    FlutterNativeSplash.remove();
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => _MaintenanceScreen(
                title: m.title,
                body: m.body,
                imageUrl: m.imageUrl,
              )),
      (_) => false,
    );
  }

  void _removeNativeSplashNextFrame() {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => FlutterNativeSplash.remove());
  }

  Future<void> _navigateNext() async {
    if (_routed || !mounted) return;
    _routed = true;
    // 진입 결정표:
    //  - onboardingDone        → /home (재방문자)
    //  - 로그인됨 or 게스트선택 → 온보딩 재개. 위치 이미 허용이면 권한화면 건너뛰고 바로 /onboarding
    //  - 그 외(완전 첫 실행)    → /login 게이트
    final settings = ref.read(settingsProvider);
    if (settings.onboardingDone) {
      context.go('/home');
      return;
    }
    final loggedIn = ref.read(authProvider) != null;
    if (loggedIn || settings.guestStarted) {
      // 권한화면이 잠깐 떴다 사라지는 깜빡임 방지: 위치 허용 여부를 splash 에서 직접 판단.
      final loc = await Permission.locationWhenInUse.status;
      if (!mounted) return;
      context.go((loc.isGranted || loc.isLimited) ? '/onboarding' : '/permission');
    } else {
      context.go('/login?gate=1');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0E13) : Colors.white,
    );
  }
}

class _MaintenanceScreen extends StatelessWidget {
  final String title;
  final String body;
  final String? imageUrl;
  const _MaintenanceScreen({required this.title, required this.body, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0C0E13) : Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: hasImage
                    ? Center(
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: Image.network(
                            DkswCore.resolveAssetUrl(imageUrl!),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                _defaultBody(context, isDark),
                          ),
                        ),
                      )
                    : _defaultBody(context, isDark),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => SystemNavigator.pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF1E2330) : const Color(0xFF1F2937),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('앱 종료',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _defaultBody(BuildContext context, bool isDark) {
    final titleColor = isDark ? Colors.white : const Color(0xFF1F2937);
    final bodyColor = isDark ? Colors.white70 : const Color(0xFF6B7280);
    final iconBg = isDark ? const Color(0xFF1E2330) : const Color(0xFFF1F5F9);
    final iconColor = isDark ? Colors.white70 : const Color(0xFF64748B);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(Icons.build_rounded, size: 44, color: iconColor),
            ),
            const SizedBox(height: 28),
            Text(_plainText(title).isEmpty ? '점검 중입니다' : _plainText(title),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: titleColor)),
            const SizedBox(height: 14),
            Text(
                _plainText(body).isEmpty
                    ? '더 나은 서비스를 위해 점검 중입니다.\n잠시 후 다시 이용해주세요.'
                    : _plainText(body),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.6, color: bodyColor)),
          ],
        ),
      ),
    );
  }
}

// 본문이 HTML(<p> 등)로 저장되므로 점검 화면 표시용으로 태그 제거 + 줄바꿈 보존.
String _plainText(String html) {
  return html
      .replaceAll(RegExp(r'</p>|<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
}
