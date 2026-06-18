import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dksw_app_core/dksw_app_core.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/auth_service.dart';
import '../widgets/policy_sheet.dart';

/// 회원가입 완료 — 소셜 로그인(신규) 직후. ① 닉네임 입력 → ② 약관 동의 시트.
/// 이메일은 소셜 프로바이더값을 그대로 사용(별도 입력 X).
class SignupCompleteScreen extends ConsumerStatefulWidget {
  final AuthUser user;
  const SignupCompleteScreen({super.key, required this.user});

  @override
  ConsumerState<SignupCompleteScreen> createState() => _SignupCompleteScreenState();
}

class _SignupCompleteScreenState extends ConsumerState<SignupCompleteScreen> {
  late final TextEditingController _nick = TextEditingController(text: widget.user.nickname ?? '');
  final TextEditingController _age = TextEditingController();
  bool _busy = false;

  // 소셜(네이버)이 연령대를 이미 줬으면 입력 생략.
  bool get _needAge => widget.user.ageGroup == null || widget.user.ageGroup!.isEmpty;
  String? _ageToGroup() {
    final n = int.tryParse(_age.text.trim());
    if (n == null || n < 14 || n > 100) return null;
    if (n >= 60) return '60대이상';
    return '${(n ~/ 10) * 10}대'; // 14→10대, 27→20대
  }
  bool get _ageOk => !_needAge || _ageToGroup() != null;

  Future<void> _onConfirm() async {
    if (_nick.text.trim().isEmpty || !_ageOk || _busy) return;
    // 동의 항목이 비어있으면(부트스트랩 미로드) 한 번 더 로드 후 진행.
    var consents = DkswCore.signupConsents;
    if (consents.isEmpty) {
      await DkswCore.bootstrap();
      if (!mounted) return;
      consents = DkswCore.signupConsents;
    }
    // ② 약관 동의 시트
    final agreed = await showModalBottomSheet<Map<String, bool>>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConsentSheet(consents: consents),
    );
    if (agreed == null || !mounted) return; // 닫음(취소)

    setState(() => _busy = true);
    final updated = await AuthService.updateProfile(
      nickname: _nick.text.trim(),
      ageGroup: _needAge ? _ageToGroup() : null,
    );
    await DkswCore.postConsents(
      consents
          .map((c) => ConsentChoice(key: c.key, agreed: agreed[c.key] == true, version: c.version))
          .toList(),
    );
    if (updated != null) ref.read(authProvider.notifier).setUser(updated);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  // 취소 = 로그아웃. 미완성 계정을 로그인 상태로 남기지 않는다(완성 게이트).
  Future<void> _cancel() async {
    if (_busy) return;
    await ref.read(authProvider.notifier).logout();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _nick.dispose();
    _age.dispose();
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
        appBar: AppBar(
          title: const Text('회원가입'),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: '취소',
            onPressed: _busy ? null : _cancel,
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('회원 정보를 입력해주세요',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: textPrimary)),
              const SizedBox(height: 8),
              Text('서비스에서 사용할 닉네임을 정해주세요.',
                  style: TextStyle(fontSize: 14, color: textSecondary, height: 1.4)),
              const SizedBox(height: 28),
              Text('닉네임',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textSecondary)),
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
              if (_needAge) ...[
                const SizedBox(height: 20),
                Text('나이',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: _age,
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: '나이 입력 (14~100)',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 6),
                Text('연령대 통계용으로만 사용돼요.',
                    style: TextStyle(fontSize: 12, color: textSecondary)),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_nick.text.trim().isNotEmpty && _ageOk && !_busy) ? _onConfirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('확인',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 약관 동의 바텀시트 — 전체동의 + 필수/선택 항목 + 마케팅 채널. 동의하기 시 체크맵 반환.
class _ConsentSheet extends StatefulWidget {
  final List<SignupConsent> consents;
  const _ConsentSheet({required this.consents});

  @override
  State<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<_ConsentSheet> {
  final Map<String, bool> _checked = {};
  // 마케팅 채널(앱푸시/문자/이메일) — 마케팅 동의에 종속(표시용, 현재 단일 키).
  static const _channels = ['앱 푸시', '문자', '이메일'];

  bool get _allRequiredChecked =>
      widget.consents.where((c) => c.required).every((c) => _checked[c.key] == true);
  bool get _allChecked => widget.consents.every((c) => _checked[c.key] == true);

  void _toggleAll(bool v) => setState(() {
        for (final c in widget.consents) {
          _checked[c.key] = v;
        }
      });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.gasBlue;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final bg = isDark ? AppColors.darkCard : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(22, 18, 22, 18 + MediaQuery.of(context).viewPadding.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 약관 항목이 많거나 큰 폰트여도 넘치지 않게 스크롤, 가입 버튼은 하단 고정.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: '서비스 이용을 위해\n'),
              TextSpan(text: '약관에 동의', style: TextStyle(color: accent)),
              const TextSpan(text: '해주세요.'),
            ]),
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.35, color: textPrimary),
          ),
          const SizedBox(height: 18),

          // 전체 동의
          InkWell(
            onTap: () => _toggleAll(!_allChecked),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(_allChecked ? Icons.check_circle : Icons.check_circle_outline,
                    color: _allChecked ? accent : Colors.grey),
                const SizedBox(width: 10),
                Text('약관 전체 동의',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
              ]),
            ),
          ),
          const Divider(height: 22),

          // 항목들
          ...widget.consents.expand((c) {
            final on = _checked[c.key] == true;
            final rows = <Widget>[
              InkWell(
                onTap: () => setState(() => _checked[c.key] = !on),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(children: [
                    Icon(on ? Icons.check_circle : Icons.check_circle_outline,
                        size: 22, color: on ? accent : Colors.grey),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(
                          text: c.required ? '(필수) ' : '(선택) ',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: c.required ? textSecondary : accent),
                        ),
                        TextSpan(text: c.title, style: TextStyle(fontSize: 14, color: textPrimary)),
                      ])),
                    ),
                    if (c.viewUrl != null)
                      GestureDetector(
                        onTap: () => showPolicySheet(context, url: c.viewUrl!, title: c.title),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('보기',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: accent,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                    decorationColor: accent)),
                            Icon(Icons.chevron_right_rounded, size: 16, color: accent),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ),
            ];
            // 마케팅이면 채널(앱푸시/문자/이메일) 표시 — 마케팅 동의에 종속
            if (c.isMarketing) {
              rows.add(Padding(
                padding: const EdgeInsets.only(left: 32, bottom: 6),
                child: Wrap(
                  spacing: 14,
                  children: _channels
                      .map((ch) => Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(on ? Icons.check : Icons.check_box_outline_blank,
                                size: 15, color: on ? accent : Colors.grey),
                            const SizedBox(width: 3),
                            Text(ch, style: TextStyle(fontSize: 12, color: textSecondary)),
                          ]))
                      .toList(),
                ),
              ));
            }
            return rows;
          }),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _allRequiredChecked ? () => Navigator.of(context).pop(Map<String, bool>.from(_checked)) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                disabledBackgroundColor: Colors.grey[300],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                _allRequiredChecked ? '동의하고 가입 완료' : '필수 약관에 동의해주세요',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
