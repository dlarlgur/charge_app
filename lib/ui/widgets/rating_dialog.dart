import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 평점 요청 다이얼로그 (전기차 기름차 톤 — gasBlue 액센트, 다크모드 대응).
class RatingDialog extends StatelessWidget {
  final Future<void> Function() onConfirm;
  final VoidCallback? onLater;

  const RatingDialog({super.key, required this.onConfirm, this.onLater});

  static Future<void> show({
    required BuildContext context,
    required Future<void> Function() onConfirm,
    VoidCallback? onLater,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => RatingDialog(onConfirm: onConfirm, onLater: onLater),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF161D27) : Colors.white;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final border = isDark ? AppColors.darkCardBorder : const Color(0xFFE8ECF0);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF1A2433), surface]
                : [const Color(0xFFEFF6FF), Colors.white],
            stops: const [0.0, 0.55],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.of(context).pop();
                  onLater?.call();
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 20, color: textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 2),
            // 아이콘 — 별 (gasBlue→evGreen 그라데이션 원)
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.gasBlue, AppColors.evGreen],
                ),
              ),
              child: const Icon(Icons.star_rounded, size: 36, color: Colors.white),
            ),
            const SizedBox(height: 18),
            Text(
              '전기차 기름차가 마음에 드시나요?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.34,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '평점 한 번이면 저희에게\n정말 큰 힘이 됩니다 🙏',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.5,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _Btn(
                    label: '나중에',
                    bg: Colors.transparent,
                    fg: textSecondary,
                    border: border,
                    onTap: () async {
                      Navigator.of(context).pop();
                      onLater?.call();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Btn(
                    label: '평점 남기기',
                    bg: AppColors.gasBlue,
                    fg: Colors.white,
                    onTap: () async {
                      Navigator.of(context).pop();
                      await onConfirm();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color? border;
  final Future<void> Function() onTap;
  const _Btn({
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: () => onTap(),
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: border != null
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: border!, width: 1),
                )
              : null,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
