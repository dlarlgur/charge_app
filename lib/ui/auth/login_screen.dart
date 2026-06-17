import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/auth_service.dart';
import '../../providers/providers.dart';
import 'signup_complete_screen.dart';

/// 소셜 로그인 화면. 카카오 / 네이버 / 구글.
/// [gate]=true 면 첫 진입 게이트 모드: 성공/게스트 시 pop 대신 /permission 전진,
/// 하단 "게스트로 시작하기" 노출, 뒤로가기 차단.
class LoginScreen extends ConsumerStatefulWidget {
  final bool gate;
  const LoginScreen({super.key, this.gate = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;

  Future<void> _onProvider(String provider) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(authProvider.notifier).login(provider);
      if (!mounted) return;
      if (r.ok) {
        final user = ref.read(authProvider);
        // 미완성(닉네임·약관동의 전) 계정이면 가입완료 화면 강제.
        if (user != null && !user.signupCompleted) {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SignupCompleteScreen(user: user),
          ));
          if (!mounted) return;
          // 가입완료 화면에서 취소(로그아웃)했으면 로그인 화면 유지.
          if (ref.read(authProvider) == null) {
            setState(() => _busy = false);
            return;
          }
        }
        if (mounted) {
          if (widget.gate) {
            context.go('/permission');
          } else {
            Navigator.of(context).pop(true);
          }
        }
        return;
      }
      // 사용자가 취소했거나 토큰 못 받음 — 조용히 화면 유지.
      setState(() => _busy = false);
    } on EmailInUseException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showEmailInUse(e.provider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인에 실패했어요. 잠시 후 다시 시도해주세요.')),
      );
    }
  }

  void _showEmailInUse(String provider) {
    const names = {'kakao': '카카오', 'naver': '네이버', 'google': '구글'};
    final name = names[provider] ?? '다른 소셜';
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('이미 가입된 이메일'),
        content: Text('이 이메일은 이미 $name 계정으로 가입돼 있어요.\n$name 로그인을 이용해주세요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(d).pop(), child: const Text('확인')),
        ],
      ),
    );
  }

  Future<void> _startGuest() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('게스트로 시작할까요?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: const Text(
          '게스트는 차량 정보·즐겨찾기·설정이 이 기기에만 저장돼요.\n'
          '기기를 바꾸거나 앱을 지우면 복구할 수 없어요.\n\n'
          '회원가입하면 어디서든 그대로 이어서 쓸 수 있어요.',
          style: TextStyle(height: 1.5, fontSize: 14),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: Text('게스트로 시작', style: TextStyle(color: textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('회원가입할게요',
                style: TextStyle(
                    color: AppColors.gasBlue, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    ref.read(settingsProvider.notifier).markGuestStarted();
    if (mounted) context.go('/permission');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final dividerColor =
        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);

    return PopScope(
        canPop: !widget.gate,
        child: Scaffold(
          backgroundColor: bg,
          body: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    if (widget.gate)
                      const SizedBox(height: 56)
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
                          child: IconButton(
                            icon:
                                Icon(Icons.close_rounded, color: textSecondary),
                            onPressed: _busy
                                ? null
                                : () => Navigator.of(context).maybePop(),
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
                              style: TextStyle(
                                  fontSize: 14.5,
                                  height: 1.5,
                                  color: textSecondary),
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
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white)),
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
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF4285F4))),
                            onTap: () => _onProvider('google'),
                          ),
                        ],
                      ),
                    ),
                    if (widget.gate) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(40, 6, 40, 0),
                        child: Row(
                          children: [
                            Expanded(
                                child: Divider(color: dividerColor, height: 1)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('또는',
                                  style:
                                      TextStyle(fontSize: 12.5, color: muted)),
                            ),
                            Expanded(
                                child: Divider(color: dividerColor, height: 1)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _startGuest,
                        child: Text(
                          '게스트로 시작하기',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: textSecondary,
                            decoration: TextDecoration.underline,
                            decorationColor: textSecondary,
                          ),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 6, 28, 18),
                      child: Text(
                        '로그인 시 이용약관 및 개인정보처리방침에 동의하게 됩니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.5,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
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
        ));
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
              border:
                  border != null ? Border.all(color: border!, width: 1) : null,
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
                          child: iconChild ?? Icon(icon, size: 21, color: fg)),
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w700, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
