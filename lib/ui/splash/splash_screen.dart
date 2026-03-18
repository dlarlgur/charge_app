import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/api_constants.dart';
import '../../data/services/version_service.dart';
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
    _scale = Tween<double>(begin: 0.8, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _controller.forward();

    Future.delayed(AppConstants.splashDuration, () async {
      if (!mounted) return;

      // 버전 체크
      debugPrint('[SplashScreen] 버전 체크 시작');
      final result = await VersionService.check();
      debugPrint('[SplashScreen] 버전 체크 결과: ${result?.type}');
      if (!mounted) return;
      
      if (result != null && result.type != UpdateType.none) {
        debugPrint('[SplashScreen] 업데이트 다이얼로그 표시');
        await UpdateDialog.showIfNeeded(context, result);
        if (!mounted) return;
        
        // 강제 업데이트면 앱 진입 차단 (다이얼로그가 닫히지 않으므로 여기까지 오지 않음)
        if (result.type == UpdateType.forced) {
          debugPrint('[SplashScreen] 강제 업데이트 - 앱 진입 차단');
          // 무한 대기 (사용자가 업데이트 버튼을 눌러 스토어로 이동해야 함)
          return;
        }
      }

      // 정상 진입
      if (!mounted) return;
      final settings = ref.read(settingsProvider);
      if (settings.onboardingDone) {
        context.go('/home');
      } else {
        context.go('/permission');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0E13) : Colors.white,
      body: Center(
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
    );
  }
}
