import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 소셜 로그인 화면.
///
/// 카카오 / 네이버 / 구글 3사. 실제 인증(SDK) 연동은 키 수령 후 [_onProvider] 에 연결.
/// 지금은 UI 완성 + 버튼 핸들러 stub.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // 닫기
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
                child: IconButton(
                  icon: Icon(Icons.close_rounded, color: textSecondary),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),

            // 히어로 — 로고 + 카피
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

            // 소셜 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                children: [
                  _SocialButton(
                    label: '카카오로 시작하기',
                    bg: const Color(0xFFFEE500),
                    fg: const Color(0xFF191600),
                    icon: Icons.chat_bubble_rounded,
                    onTap: () => _onProvider(context, 'kakao'),
                  ),
                  const SizedBox(height: 10),
                  _SocialButton(
                    label: '네이버로 시작하기',
                    bg: const Color(0xFF03C75A),
                    fg: Colors.white,
                    iconChild: const Text('N',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                    onTap: () => _onProvider(context, 'naver'),
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
                    onTap: () => _onProvider(context, 'google'),
                  ),
                ],
              ),
            ),

            // 약관 안내
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
    );
  }

  void _onProvider(BuildContext context, String provider) {
    // TODO(login): 소셜 SDK 연동 (키 수령 후). kakao/naver/google access_token →
    //   서버 POST /api/auth/{provider} → 우리 JWT 저장 → pop(true).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$provider 로그인 연동 준비 중입니다.')),
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
                      child: Center(
                        child: iconChild ?? Icon(icon, size: 21, color: fg),
                      ),
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
