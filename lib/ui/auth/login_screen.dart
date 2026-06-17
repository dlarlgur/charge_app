import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/auth_service.dart';

/// 소셜 로그인 화면. 카카오 / 네이버 / 구글.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;

  Future<void> _onProvider(String provider) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await ref.read(authProvider.notifier).login(provider);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true); // 로그인 성공 → 닫기
        return;
      }
      // 사용자가 취소했거나 실패 — 화면 유지
      setState(() => _busy = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인에 실패했어요. 잠시 후 다시 시도해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
                    child: IconButton(
                      icon: Icon(Icons.close_rounded, color: textSecondary),
                      onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset(
                          'assets/halfNhalf.png',
                          width: 76,
                          height: 76,
                          filterQuality: FilterQuality.medium,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '주유부터 충전까지,\n한 번에.',
                          style: TextStyle(
                            fontSize: 26,
                            height: 1.32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '로그인하면 차량 정보·설정이\n기기를 바꿔도 그대로 유지돼요.',
                          style: TextStyle(fontSize: 14.5, height: 1.5, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Column(
                    children: [
                      _SocialButton(
                        label: '카카오로 시작하기',
                        bg: const Color(0xFFFEE500),
                        fg: const Color(0xFF191600),
                        icon: Icons.chat_bubble_rounded,
                        onTap: () => _onProvider('kakao'),
                      ),
                      const SizedBox(height: 10),
                      _SocialButton(
                        label: '네이버로 시작하기',
                        bg: const Color(0xFF03C75A),
                        fg: Colors.white,
                        iconChild: const Text('N',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                        onTap: () => _onProvider('naver'),
                      ),
                      const SizedBox(height: 10),
                      _SocialButton(
                        label: '구글로 시작하기',
                        bg: Colors.white,
                        fg: const Color(0xFF1F1F1F),
                        border: const Color(0xFFDADCE0),
                        iconChild: const Text('G',
                            style: TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF4285F4))),
                        onTap: () => _onProvider('google'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 6, 28, 18),
                  child: Text(
                    '로그인 시 이용약관 및 개인정보처리방침에 동의하게 됩니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color? border;
  final IconData? icon;
  final Widget? iconChild;
  final VoidCallback onTap;

  const _SocialButton({
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.border,
    this.icon,
    this.iconChild,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: border != null ? Border.all(color: border!, width: 1) : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Center(child: iconChild ?? Icon(icon, size: 21, color: fg)),
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
