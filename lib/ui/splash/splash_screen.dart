import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/api_constants.dart';
import '../../core/update/app_updater.dart';
import '../../providers/providers.dart';
import '../widgets/update_dialog.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeIn = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _scale = Tween<double>(begin: 0.85, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();

    Future.delayed(AppConstants.splashDuration, _runBootstrap);
  }

  Future<void> _runBootstrap() async {
    if (!mounted) return;

    debugPrint('[SplashScreen] bootstrap 시작');
    final result = await DkswCore.bootstrap();
    debugPrint('[SplashScreen] bootstrap 결과: force=${result?.update.forceUpdate}, optional=${result?.update.optionalUpdate}');
    if (!mounted) return;

    if (result != null && (result.update.forceUpdate || result.update.optionalUpdate)) {
      // Play Store 설치본이면 네이티브 인앱 업데이트 먼저 시도
      final native = result.update.forceUpdate
          ? await AppUpdater.tryImmediateUpdate()
          : await AppUpdater.tryFlexibleUpdate();
      if (!mounted) return;

      if (native == InAppUpdateResult.started) {
        // 즉시 업데이트면 Play가 프로세스 재시작; flexible도 complete 호출 후 재시작.
        // 여기까진 사실상 도달하지 않지만 안전하게 차단.
        if (result.update.forceUpdate) return;
      } else {
        // 네이티브 경로 불가 → 커스텀 다이얼로그 fallback
        await UpdateDialog.showIfNeeded(context, result.update);
        if (!mounted) return;
        if (result.update.forceUpdate) return;
      }
    }

    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    if (settings.onboardingDone) {
      context.go('/home');
    } else {
      context.go('/permission');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final gradientColors = isDark
        ? [const Color(0xFF0C0E13), const Color(0xFF111827), const Color(0xFF0C0E13)]
        : [const Color(0xFFEFF6FF), Colors.white, const Color(0xFFECFDF5)];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => Opacity(
              opacity: _fadeIn.value,
              child: Transform.scale(
                scale: _scale.value,
                child: Image.asset(
                  'assets/charge_app_long.png',
                  width: MediaQuery.of(context).size.width * 0.7,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
