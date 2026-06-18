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
      _showSettingsDialog();
    } else {
      // denied - 온보딩은 진행할 수 있도록
      _goNext();
    }
  }

  Future<void> _showSettingsDialog() async {
    final go = await showAppDialog<bool>(
      context,
      icon: Icons.location_on_rounded,
      title: '위치 권한이 필요해요',
      message: '주변 주유소·충전소를 찾으려면\n설정에서 위치 권한을 허용해주세요.',
      primaryLabel: '설정 열기',
      primaryValue: true,
      secondaryLabel: '취소',
      secondaryValue: false,
    );
    if (go == true) {
      _awaitingSettingsReturn = true;
      await openAppSettings();
    }
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
                      : const Text('위치 권한 허용하기'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isLoading ? null : () => _goNext(),
                child: Text('나중에 설정할게요',
                    style: TextStyle(
                        color: isDark
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted)),
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
