import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/update/app_updater.dart';
import '../../providers/providers.dart';
import '../widgets/update_dialog.dart';

/// 네이티브 스플래시가 bootstrap 끝날 때까지 유지되므로,
/// 이 화면은 화면을 그리지 않고 게이트 역할만 한다.
/// - bootstrap 완료 → 네이티브 스플래시 제거
/// - 업데이트 필요 시 인앱 업데이트 / 다이얼로그
/// - 스플래시 광고 있으면 노출, 없으면 홈/권한 화면 직행
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

  Future<void> _runBootstrap() async {
    if (!mounted) return;

    debugPrint('[SplashScreen] bootstrap 시작');
    final result = await DkswCore.bootstrap();
    debugPrint('[SplashScreen] bootstrap 결과: force=${result?.update.forceUpdate}, ad=${result?.ad != null}');
    if (!mounted) return;

    // 이후 단계는 모두 화면 UI를 노출해야 하므로 네이티브 스플래시 내림
    FlutterNativeSplash.remove();

    if (result?.maintenance != null) {
      final m = result!.maintenance!;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => _MaintenanceScreen(title: m.title, body: m.body)),
      );
      return;
    }

    if (result != null && (result.update.forceUpdate || result.update.optionalUpdate)) {
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
      await Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => SplashAdScreen(ad: ad),
          transitionDuration: const Duration(milliseconds: 150),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
      if (!mounted) return;
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
    // 네이티브 스플래시가 위에 떠 있는 동안 깜빡이지 않도록 동일 배경색만 제공.
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
