import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'providers/providers.dart';
import 'router/app_router.dart';

class ChargeHelperApp extends ConsumerWidget {
  const ChargeHelperApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: '주유/충전 도우미',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        // 시스템 폰트 스케일 — 시각약자 접근성을 위해 1.2까지 허용,
        // 단 카드 깨짐 방지 위해 1.2 cap.
        final scale = MediaQuery.of(context).textScaler.scale(1.0).clamp(1.0, 1.2);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        );
      },
    );
  }
}
