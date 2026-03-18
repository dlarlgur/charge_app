import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _isLoading = false;

  Future<void> _requestPermission() async {
    setState(() => _isLoading = true);

    final status = await Permission.locationWhenInUse.request();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (status.isGranted || status.isLimited) {
      context.go('/onboarding');
    } else if (status.isPermanentlyDenied) {
      _showSettingsDialog();
    } else {
      // denied - 온보딩은 진행할 수 있도록
      context.go('/onboarding');
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('위치 권한 필요'),
        content: const Text(
          '위치 권한이 거부되어 있습니다.\n설정에서 위치 권한을 허용해주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openAppSettings();
            },
            child: const Text('설정 열기'),
          ),
        ],
      ),
    );
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
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0x1F3B82F6) : const Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.location_on_rounded, size: 36,
                  color: isDark ? AppColors.gasBlue : AppColors.gasBlueDark),
              ),
              const SizedBox(height: 24),
              Text('위치 권한이 필요해요', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '주변 주유소와 충전소를 찾고\n거리 정보를 보여드리기 위해 필요합니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
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
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('위치 권한 허용하기'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isLoading ? null : () => context.go('/onboarding'),
                child: Text('나중에 설정할게요',
                  style: TextStyle(color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
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
          Icon(Icons.check_circle_outline_rounded, size: 20, color: AppColors.success),
          const SizedBox(width: 10),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
