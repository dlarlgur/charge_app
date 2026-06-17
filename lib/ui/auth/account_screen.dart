import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/auth_service.dart';

/// 계정 관리 화면 — 닉네임·이메일 표시 + 로그아웃 / 회원탈퇴.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 로그아웃/탈퇴로 user 가 null 이 되면 화면 닫기
    ref.listen<AuthUser?>(authProvider, (prev, next) {
      if (next == null && context.canPop()) context.pop();
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
                    ],
                  ),
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
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('회원탈퇴'),
                        content: const Text('탈퇴하면 계정 정보가 삭제되고 되돌릴 수 없어요. 진행할까요?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('취소')),
                          TextButton(
                            onPressed: () => Navigator.pop(d, true),
                            child: const Text('탈퇴', style: TextStyle(color: Color(0xFFEF4444))),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) await ref.read(authProvider.notifier).withdraw();
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
