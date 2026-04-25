import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/update/app_updater.dart';
import '../../providers/providers.dart';
import '../widgets/update_dialog.dart';

/// 네이티브 스플래시는 다음 화면(광고/홈/권한) 첫 프레임이 커밋된 직후에만 내려간다.
/// 그래야 흰색 갭 없이 로고 → 광고 또는 로고 → 홈 으로 자연스럽게 스냅.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runBootstrap());
  }

  void _removeNativeSplashNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) => FlutterNativeSplash.remove());
  }

  Future<void> _runBootstrap() async {
    if (!mounted) return;

    debugPrint('[SplashScreen] bootstrap 시작');
    final result = await DkswCore.bootstrap();
    debugPrint('[SplashScreen] bootstrap 결과: force=${result?.update.forceUpdate}, ad=${result?.ad != null}');
    if (!mounted) return;

    if (result?.maintenance != null) {
      final m = result!.maintenance!;
      FlutterNativeSplash.remove();
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => _MaintenanceScreen(title: m.title, body: m.body)),
      );
      return;
    }

    if (result != null && (result.update.forceUpdate || result.update.optionalUpdate)) {
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

    final ad = result?.ad;
    if (ad != null) {
      // 광고 이미지를 미리 디코드해 캐시에 올린 뒤 push → 첫 프레임에 즉시 그려짐.
      try {
        await precacheImage(NetworkImage(ad.imageUrl), context)
            .timeout(const Duration(milliseconds: 1200));
      } catch (_) {
        // 캐시 실패해도 그냥 진행 — SplashAdScreen 의 loadingBuilder 가 받아준다.
      }
      if (!mounted) return;

      _removeNativeSplashNextFrame();
      await Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => SplashAdScreen(ad: ad),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      if (!mounted) return;
    } else {
      _removeNativeSplashNextFrame();
    }

    final settings = ref.read(settingsProvider);
    if (settings.onboardingDone) {
      context.go('/home');
    } else {
      context.go('/permission');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 네이티브 스플래시가 위를 덮고 있으므로 이 색상은 거의 보이지 않는다.
    // 단 안전장치 타이머가 발동했을 때만 잠깐 보일 수 있으니 테마와 통일.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0E13) : Colors.white,
    );
  }
}

class _MaintenanceScreen extends StatelessWidget {
  final String title;
  final String body;
  const _MaintenanceScreen({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0C0E13) : Colors.white,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.build_rounded, size: 64,
                      color: isDark ? Colors.white54 : Colors.black45),
                  const SizedBox(height: 20),
                  Text(title.isEmpty ? '점검 중입니다' : title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : Colors.black87)),
                  const SizedBox(height: 12),
                  Text(body.isEmpty ? '잠시 후 다시 이용해주세요.' : body,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: isDark ? Colors.white70 : Colors.black54)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
