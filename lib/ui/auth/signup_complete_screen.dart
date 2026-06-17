import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/auth_service.dart';

/// 회원가입 완료 — 소셜 로그인(신규) 직후. 닉네임/이메일 입력 + 개인정보(필수)·마케팅(선택) 동의.
/// 완료해야 가입 확정. onDone() 으로 닫음.
class SignupCompleteScreen extends ConsumerStatefulWidget {
  final AuthUser user; // 소셜 프로바이더에서 받은 초기값(prefill)
  const SignupCompleteScreen({super.key, required this.user});

  @override
  ConsumerState<SignupCompleteScreen> createState() => _SignupCompleteScreenState();
}

class _SignupCompleteScreenState extends ConsumerState<SignupCompleteScreen> {
  late final TextEditingController _nick = TextEditingController(text: widget.user.nickname ?? '');
  late final TextEditingController _email = TextEditingController(text: widget.user.email ?? '');
  final Map<String, bool> _checked = {};
  late final List<SignupConsent> _consents = DkswCore.signupConsents;
  bool _busy = false;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _allRequiredChecked =>
      _consents.where((c) => c.required).every((c) => _checked[c.key] == true);
  bool get _canSubmit =>
      _nick.text.trim().isNotEmpty && _emailRe.hasMatch(_email.text.trim()) && _allRequiredChecked && !_busy;

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _busy = true);
    final updated = await AuthService.updateProfile(
      nickname: _nick.text.trim(),
      email: _email.text.trim(),
    );
    await DkswCore.postConsents(
      _consents
          .map((c) => ConsentChoice(key: c.key, agreed: _checked[c.key] == true, version: c.version))
          .toList(),
    );
    if (updated != null) ref.read(authProvider.notifier).setUser(updated);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _nick.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.gasBlue;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        appBar: AppBar(title: const Text('회원가입'), automaticallyImplyLeading: false),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text('가입을 완료해주세요',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textPrimary)),
            const SizedBox(height: 6),
            Text('닉네임과 이메일을 입력하고 약관에 동의하면 가입이 완료돼요.',
                style: TextStyle(fontSize: 13.5, color: textSecondary, height: 1.4)),
            const SizedBox(height: 24),

            Text('닉네임', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _nick,
              maxLength: 20,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '사용할 닉네임',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),

            Text('이메일', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'example@email.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            // 동의 항목 (콘솔 시드: 개인정보 필수 / 마케팅 선택)
            ..._consents.map((c) {
              final on = _checked[c.key] == true;
              return InkWell(
                onTap: () => setState(() => _checked[c.key] = !on),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(on ? Icons.check_circle : Icons.check_circle_outline,
                          size: 22, color: on ? accent : Colors.grey),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(
                            text: c.required ? '[필수] ' : '[선택] ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: c.required ? accent : textSecondary,
                            ),
                          ),
                          TextSpan(text: c.title, style: TextStyle(fontSize: 14, color: textPrimary)),
                        ])),
                      ),
                      if (c.viewUrl != null)
                        TextButton(
                          onPressed: () => _open(c.viewUrl!),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 0),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('보기', style: TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _canSubmit ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('가입 완료',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
