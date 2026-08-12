import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/cheer_service.dart';
import '../cheer/cheer_screen.dart';
import '../cheer/gold_profile.dart';
import '../cheer/cheer_tier_theme.dart';
import '../cheer/garage_screen.dart';
import '../../core/app_dialog.dart';
import '../../core/util/app_toast.dart';
import 'profile_photo_sheet.dart';
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
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(title: const Text('계정 관리'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 프로필 카드 — handoff 3 골드 카드. 사진이 있으면 사진, 없으면 앱 아이콘.
          _goldProfile(context, ref, user, isDark),
          const SizedBox(height: 12),
          // 내 수상 기록 — 월간 1·2·3위. 기록이 없으면 카드 자체를 숨긴다(시안 규칙).
          ValueListenableBuilder<CheerStatus?>(
            valueListenable: CheerService.instance.statusNotifier,
            builder: (context, st, _) {
              final crowns = st?.crowns ?? const <CheerCrown>[];
              if (crowns.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _awardsCard(context, crowns, isDark),
              );
            },
          ),
          _linksCard(context, isDark),
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
                  leading: const Icon(Icons.person_remove_rounded,
                      color: Color(0xFFEF4444)),
                  title: const Text('회원탈퇴',
                      style: TextStyle(color: Color(0xFFEF4444))),
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

  // ─── 골드 프로필 카드 ─────────────────────────────────────────────────────
  Widget _goldProfile(
      BuildContext context, WidgetRef ref, AuthUser user, bool isDark) {
    final ink = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final sub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return _GoldFrame(
      isDark: isDark,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EditablePhoto(
            user: user,
            onUpdated: (u) => ref.read(authProvider.notifier).setUser(u),
            child: GoldAvatar(
              size: 64,
              isDark: isDark,
              photoUrl: user.profileImageAbsolute,
              cameraBadge: true,
            ),
          ),
          const SizedBox(height: 8),
          // 닉네임 + 연필 — 눌러서 바로 수정
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _editNickname(context, ref, user),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text('${user.nickname ?? '사용자'}님',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: ink)),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.edit_rounded,
                      size: 15,
                      color: isDark
                          ? const Color(0xFFD9B871)
                          : const Color(0xFFB08A45)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(user.email ?? '이메일 미등록',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: sub)),
          // 연령대는 시안에 없지만 기존 표시 정보라 유지 — 이메일 아래 작은 칩.
          if (user.ageGroup?.isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.gasBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(user.ageGroup!,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.gasBlue)),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 내 수상 기록 ─────────────────────────────────────────────────────────
  /// 최근 수상 3개를 메달로. 전체는 개러지의 명예의 전당에서 본다.
  Widget _awardsCard(
      BuildContext context, List<CheerCrown> crowns, bool isDark) {
    final shown = crowns.take(3).toList();
    return _PlainCard(
      isDark: isDark,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                Text('내 수상 기록',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? const Color(0xFFF1F5F9)
                            : const Color(0xFF0F172A))),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GarageScreen())),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('전체 보기',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B))),
                      Icon(Icons.chevron_right_rounded,
                          size: 14,
                          color: isDark
                              ? const Color(0xFF475569)
                              : const Color(0xFFCBD5E1)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          AwardMedals(
            isDark: isDark,
            items: [
              for (final c in shown)
                (rank: c.rank, label: '${cheerMonthLabel(c.month)} ${c.rank}위'),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 응원 기록 / 내 개러지 ────────────────────────────────────────────────
  /// 시안엔 '이메일 변경'도 있지만 소셜 로그인 계정이라 앱·서버 모두 변경 수단이
  /// 없다 — 눌러도 아무 일 없는 행은 넣지 않는다.
  Widget _linksCard(BuildContext context, bool isDark) {
    return ValueListenableBuilder<int>(
      valueListenable: CheerService.instance.totalNotifier,
      builder: (context, total, _) {
        final owned =
            CheerTierTheme.tiers.where((t) => total >= t.threshold).length;
        return _PlainCard(
          isDark: isDark,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _linkRow(context, isDark, Icons.volunteer_activism_rounded,
                  '응원 기록', '누적 $total회',
                  () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const CheerScreen()))),
              Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 14,
                  endIndent: 14,
                  color: isDark
                      ? const Color(0x14FFFFFF)
                      : const Color(0xFFF2ECE1)),
              _linkRow(context, isDark, Icons.directions_car_rounded, '내 개러지',
                  '$owned / ${CheerTierTheme.tiers.length}',
                  () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const GarageScreen()))),
            ],
          ),
        );
      },
    );
  }

  Widget _linkRow(BuildContext context, bool isDark, IconData icon,
      String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.gasBlue.withValues(alpha: isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: AppColors.gasBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFFF1F5F9)
                          : const Color(0xFF0F172A))),
            ),
            Text(value,
                style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B))),
            Icon(Icons.chevron_right_rounded,
                size: 15,
                color: isDark
                    ? const Color(0xFF475569)
                    : const Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }
}

/// 골드 톤 카드 프레임 — ✦ 트윙클 + 우상단 글로우 (계정 관리 프로필용)
class _GoldFrame extends StatefulWidget {
  final bool isDark;
  final EdgeInsets padding;
  final Widget child;
  const _GoldFrame(
      {required this.isDark, required this.padding, required this.child});

  @override
  State<_GoldFrame> createState() => _GoldFrameState();
}

class _GoldFrameState extends State<_GoldFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tw = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4000))
    ..repeat();

  @override
  void dispose() {
    _tw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: const Alignment(-0.5, -1),
          end: const Alignment(0.5, 1),
          colors: CheerGold.card(isDark),
        ),
        border: Border.all(color: CheerGold.border(isDark)),
        boxShadow: CheerGold.shadow(isDark),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: IgnorePointer(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFFE3B54C)
                        .withValues(alpha: isDark ? 0.20 : 0.38),
                    const Color(0x00E3B54C),
                  ]),
                ),
              ),
            ),
          ),
          Positioned(
              left: 14,
              top: 14,
              child: GoldTwinkle(
                  anim: _tw,
                  size: 10,
                  color:
                      isDark ? CheerGold.twinkleD : CheerGold.twinkleL)),
          Positioned(
              right: 16,
              top: 26,
              child: GoldTwinkle(
                  anim: _tw,
                  size: 8,
                  delaySec: 0.6,
                  color:
                      isDark ? CheerGold.twinkleD2 : CheerGold.twinkleL2)),
          Positioned(
              right: 30,
              bottom: 16,
              child: GoldTwinkle(
                  anim: _tw,
                  size: 11,
                  delaySec: 1.3,
                  color:
                      isDark ? CheerGold.twinkleD : CheerGold.twinkleL)),
          Padding(padding: widget.padding, child: widget.child),
        ],
      ),
    );
  }
}

/// 계정 관리 리스트/기록 카드 — 흰 배경 + 샴페인 보더
class _PlainCard extends StatelessWidget {
  final bool isDark;
  final EdgeInsets padding;
  final Widget child;
  const _PlainCard(
      {required this.isDark, required this.padding, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark
                ? AppColors.darkCardBorder
                : const Color(0xFFEDE6D8),
            width: 0.5),
        // 골드 카드만 떠 있고 나머지가 가라앉아 보이지 않게, 같은 계열의
        // 더 옅은 그림자를 준다(라이트 전용).
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                    color: Color(0x0F94896B),
                    blurRadius: 10,
                    offset: Offset(0, 3)),
              ],
      ),
      padding: padding,
      child: child,
    );
  }
}

/// 닉네임 수정 다이얼로그 → PATCH /me → authProvider 갱신.
Future<void> _editNickname(
    BuildContext context, WidgetRef ref, AuthUser user) async {
  final newNick = await showDialog<String>(
    context: context,
    builder: (_) => _NicknameDialog(initial: user.nickname ?? ''),
  );
  if (newNick == null || newNick.isEmpty || newNick == user.nickname) return;

  final updated = await AuthService.updateProfile(nickname: newNick);
  if (!context.mounted) return;
  if (updated != null) {
    ref.read(authProvider.notifier).setUser(updated);
    showAppToast(context, '닉네임을 변경했어요.');
  } else {
    final code = AuthService.lastProfileError;
    final msg = code == 'no_phone'
        ? '닉네임에 전화번호는 넣을 수 없어요.'
        : code == 'invalid_nickname'
            ? '닉네임엔 특수문자·기호를 쓸 수 없어요.'
            : '변경에 실패했어요. 다시 시도해주세요.';
    showAppToast(context, msg, isError: true);
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
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

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
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_c.text.trim()),
          child: const Text('저장'),
        ),
      ],
    );
  }
}

/// 프로필 사진 — 탭하면 등록/변경, 우하단에 카메라 배지.
/// 업로드 → PATCH /auth/me 까지 끝내고 authProvider 를 갱신한다.
class _EditablePhoto extends StatefulWidget {
  final AuthUser user;
  final Widget child;
  final void Function(AuthUser updated) onUpdated;
  const _EditablePhoto(
      {required this.user, required this.child, required this.onUpdated});

  @override
  State<_EditablePhoto> createState() => _EditablePhotoState();
}

class _EditablePhotoState extends State<_EditablePhoto> {
  bool _busy = false;

  Future<void> _pick() async {
    if (_busy) return;
    final url = await pickProfilePhoto(context,
        hasPhoto: (widget.user.profileImageUrl ?? '').isNotEmpty);
    if (url == null || !mounted) return; // 취소
    setState(() => _busy = true);
    final updated = await AuthService.updateProfile(profileImageUrl: url);
    if (!mounted) return;
    setState(() => _busy = false);
    if (updated != null) {
      widget.onUpdated(updated);
      showAppToast(context, url.isEmpty ? '기본 이미지로 바꿨어요.' : '프로필 사진을 바꿨어요.');
    } else {
      showAppToast(context, '변경에 실패했어요. 다시 시도해주세요.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _pick,
      child: Stack(clipBehavior: Clip.none, children: [
        widget.child,
        if (_busy)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.45),
              ),
              child: const Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
              ),
            ),
          ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF3B82F6),
              border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF14161B)
                      : Colors.white,
                  width: 2),
            ),
            child: const Icon(Icons.photo_camera_rounded,
                size: 11, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}
