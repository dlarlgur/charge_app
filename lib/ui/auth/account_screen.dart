import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/app_dialog.dart';
import '../../data/services/auth_service.dart';

/// 계정 관리 화면 — 닉네임·이메일 표시 + 로그아웃 / 회원탈퇴.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _withdrawing = false; // 탈퇴 진행 중엔 자동 pop 막고, 완료 알럿 후 직접 pop

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 로그아웃 등으로 user 가 null 이 되면 화면 닫기 (탈퇴는 핸들러가 직접 처리)
    ref.listen<AuthUser?>(authProvider, (prev, next) {
      if (next == null && !_withdrawing && context.canPop()) context.pop();
    });
    if (user == null) return const Scaffold(body: SizedBox.shrink());

    final cardColor = isDark ? AppColors.darkCard : AppColors.lightCard;
    final border = isDark ? AppColors.darkCardBorder : const Color(0xFFE8ECF0);
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(title: const Text('계정 관리'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 프로필 헤더
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: AppColors.logoGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (user.profileImageUrl?.isNotEmpty ?? false)
                      ? Image.network(user.profileImageUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.person_rounded, color: Colors.white, size: 34))
                      : const Icon(Icons.person_rounded, color: Colors.white, size: 34),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${user.nickname ?? '사용자'}님',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email ?? '이메일 미등록',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, color: textSecondary),
                      ),
                      if (user.ageGroup?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.gasBlue.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            user.ageGroup!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.gasBlue,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit_rounded, size: 20, color: textSecondary),
                  tooltip: '닉네임 수정',
                  onPressed: () => _editNickname(context, ref, user),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 로그아웃 / 회원탈퇴
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.logout_rounded, color: textSecondary),
                  title: const Text('로그아웃'),
                  onTap: () => ref.read(authProvider.notifier).logout(),
                ),
                Divider(height: 1, color: border, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.person_remove_rounded, color: Color(0xFFEF4444)),
                  title: const Text('회원탈퇴', style: TextStyle(color: Color(0xFFEF4444))),
                  onTap: () async {
                    final ok = await showAppDialog<bool>(
                      context,
                      icon: Icons.person_remove_rounded,
                      title: '회원탈퇴',
                      message: '탈퇴하면 계정 정보와 차량·즐겨찾기·알람이\n모두 삭제되고 되돌릴 수 없어요.',
                      primaryLabel: '탈퇴하기',
                      primaryValue: true,
                      secondaryLabel: '취소',
                      secondaryValue: false,
                      accent: const Color(0xFFEF4444),
                    );
                    if (ok != true) return;
                    setState(() => _withdrawing = true);
                    await ref.read(authProvider.notifier).withdraw();
                    if (!context.mounted) return;
                    await showAppDialog<void>(
                      context,
                      icon: Icons.check_circle_rounded,
                      title: '탈퇴되었습니다',
                      message: '계정이 삭제되었어요.\n그동안 이용해주셔서 감사합니다.',
                      primaryLabel: '확인',
                    );
                    if (context.mounted && context.canPop()) context.pop();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 닉네임 수정 다이얼로그 → PATCH /me → authProvider 갱신.
Future<void> _editNickname(BuildContext context, WidgetRef ref, AuthUser user) async {
  final newNick = await showDialog<String>(
    context: context,
    builder: (_) => _NicknameDialog(initial: user.nickname ?? ''),
  );
  if (newNick == null || newNick.isEmpty || newNick == user.nickname) return;

  final updated = await AuthService.updateProfile(nickname: newNick);
  if (!context.mounted) return;
  if (updated != null) {
    ref.read(authProvider.notifier).setUser(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('닉네임을 변경했어요.')),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('변경에 실패했어요. 다시 시도해주세요.')),
    );
  }
}

/// 컨트롤러를 자신이 소유·dispose → pop 애니메이션 중 조기 dispose로 인한
/// '_dependents.isEmpty' 어서션 방지.
class _NicknameDialog extends StatefulWidget {
  final String initial;
  const _NicknameDialog({required this.initial});

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('닉네임 수정'),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLength: 20,
        decoration: const InputDecoration(hintText: '사용할 닉네임', counterText: ''),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_c.text.trim()),
          child: const Text('저장'),
        ),
      ],
    );
  }
}
