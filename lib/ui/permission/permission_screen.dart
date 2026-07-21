import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../core/app_dialog.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  bool _isLoading = false;
  // 설정 앱을 띄운 직후 → 사용자가 돌아오면 권한 재체크해 자동 진행.
  bool _awaitingSettingsReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 이미 위치 권한이 있으면(재실행/재개) 권한 화면을 띄우지 않고 바로 다음으로.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _skipIfAlreadyGranted());
  }

  Future<void> _skipIfAlreadyGranted() async {
    final status = await Permission.locationWhenInUse.status;
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      _goNext();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingSettingsReturn) {
      _awaitingSettingsReturn = false;
      _recheckAfterSettings();
    }
  }

  // 위치 단계 후 진행. 온보딩 미완료면 온보딩으로(알림 권한은 온보딩 마지막 스텝에서 요청).
  // 온보딩 완료(서버 복원 등으로 스킵) 시엔 온보딩의 알림 권한 스텝도 건너뛰므로 여기서 요청 후 홈.
  Future<void> _goNext() async {
    final done = Hive.box(AppConstants.settingsBox)
        .get(AppConstants.keyOnboardingDone, defaultValue: false) as bool;
    if (done) {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      if (!mounted) return;
      context.go('/home');
    } else {
      context.go('/onboarding');
    }
  }

  // 설정 다녀온 후 권한 자동 재체크 — 사용자가 다시 버튼 누르지 않아도 진행.
  Future<void> _recheckAfterSettings() async {
    final status = await Permission.locationWhenInUse.status;
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      _goNext();
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _isLoading = true);

    final status = await Permission.locationWhenInUse.request();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (status.isGranted || status.isLimited) {
      _goNext();
    } else if (status.isPermanentlyDenied) {
      // iOS 는 OS 팝업에서 한 번 거부하면 곧바로 permanentlyDenied.
      // 여기서 화면에 가두면 "위치 없이는 사용 불가"가 돼 5.1.1 재리젝 사유 →
      // 설정 안내만 하고, 설정 안 가면 위치 없이 그대로 진행(검색 등은 사용 가능).
      final wentToSettings = await _showSettingsDialog();
      if (!wentToSettings && mounted) _goNext();
    } else {
      // denied - 온보딩은 진행할 수 있도록
      _goNext();
    }
  }

  /// 설정으로 이동했으면 true (복귀 시 lifecycle 재체크가 자동 진행).
  Future<bool> _showSettingsDialog() async {
    final go = await showAppDialog<bool>(
      context,
      icon: Icons.location_on_rounded,
      title: '위치 권한이 꺼져 있어요',
      message: '주변 주유소·충전소 찾기에 위치가 사용돼요.\n설정에서 켜거나, 위치 없이 계속할 수 있어요.',
      primaryLabel: '설정 열기',
      primaryValue: true,
      secondaryLabel: '위치 없이 계속',
      secondaryValue: false,
    );
    if (go == true) {
      _awaitingSettingsReturn = true;
      await openAppSettings();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0x1F3B82F6)
                      : const Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.location_on_rounded,
                    size: 36,
                    color: isDark ? AppColors.gasBlue : AppColors.gasBlueDark),
              ),
              const SizedBox(height: 24),
              Text('위치 권한이 필요해요',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '주변 주유소와 충전소를 찾고\n거리 정보를 보여드리기 위해 필요합니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.6),
              ),
              const SizedBox(height: 32),
              _checkItem(context, '내 위치 기반 주유소/충전소 거리 계산'),
              _checkItem(context, '지도에서 주유소/충전소 위치 확인'),
              _checkItem(context, '길찾기 연동'),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _requestPermission,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      // 앱스토어 심사 5.1.1(iv): 권한 유도 문구 금지 → 중립 문구.
                      // '나중에' 스킵 버튼도 같은 사유로 제거 (거부는 시스템 팝업에서).
                      : const Text('계속'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkItem(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 20, color: AppColors.success),
          const SizedBox(width: 10),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
