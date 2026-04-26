import 'dart:async';

import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/update/app_updater.dart';
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
      }
    }

    // 2단계: bootstrap 으로 캐시 갱신 + maintenance/update 처리.
    debugPrint('[SplashScreen] bootstrap 시작 (cache=${cached != null})');
    final result = await DkswCore.bootstrap();
    debugPrint('[SplashScreen] bootstrap 결과: force=${result?.update.forceUpdate}, ad=${result?.ad != null}');
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
      final m = result!.maintenance!;
      FlutterNativeSplash.remove();
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => _MaintenanceScreen(
                  title: m.title,
                  body: m.body,
                  imageUrl: m.imageUrl,
                )),
        (_) => false,
      );
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

  void _afterAdOrSkip() {
    if (!mounted) return;
    _navigateNext();
  }

  void _removeNativeSplashNextFrame() {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => FlutterNativeSplash.remove());
  }

  void _navigateNext() {
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    if (settings.onboardingDone) {
      context.go('/home');
    } else {
      context.go('/permission');
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
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0C0E13) : Colors.white,
        body: SafeArea(
          child: hasImage
              ? Center(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.network(
                      imageUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          _defaultBody(context, isDark),
                    ),
                  ),
                )
              : _defaultBody(context, isDark),
        ),
      ),
    );
  }

  Widget _defaultBody(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.build_rounded,
                size: 64,
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
    );
  }
}
