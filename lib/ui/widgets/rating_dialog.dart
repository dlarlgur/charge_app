import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 만족도 게이트 다이얼로그 (전기차 기름차 톤 — gasBlue 액센트, 다크모드 대응).
/// 👍 좋아요 → [onPositive](스토어 별점) / 👎 아쉬워요 → [onNegative](1:1 문의).
class RatingDialog extends StatefulWidget {
  final Future<void> Function() onPositive;
  final VoidCallback onNegative;
  final VoidCallback? onLater;

  const RatingDialog({
    super.key,
    required this.onPositive,
    required this.onNegative,
    this.onLater,
  });

  static Future<void> show({
    required BuildContext context,
    required Future<void> Function() onPositive,
    required VoidCallback onNegative,
    VoidCallback? onLater,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => RatingDialog(
        onPositive: onPositive,
        onNegative: onNegative,
        onLater: onLater,
      ),
    );
  }

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  // '아쉬워요' 선택 후 → 바로 문의창으로 던지지 않고 1:1 문의 유도 단계로 전환.
  bool _negative = false;

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
                  widget.onLater?.call();
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 20, color: textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 2),
            // 아이콘 — 만족도 단계는 별, 피드백 유도 단계는 말풍선.
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
              child: Icon(
                _negative ? Icons.forum_rounded : Icons.star_rounded,
                size: 34,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _negative ? '의견을 들려주세요 🙏' : '전기차 기름차, 써보니 어떠세요?',
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
              _negative
                  ? '아쉬운 점을 1:1 문의로 남겨주시면\n꼭 확인하고 빠르게 개선할게요.'
                  : '솔직한 의견 한마디가\n저희에게 큰 힘이 됩니다 🙏',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.5,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            // 1단계: 좋아요/아쉬워요 → 아쉬워요는 같은 다이얼로그를 문의 유도로 전환.
            // 2단계(_negative): 다음에 / 문의 남기기.
            _negative
                ? Row(
                    children: [
                      Expanded(
                        child: _Btn(
                          label: '다음에',
                          bg: Colors.transparent,
                          fg: textSecondary,
                          border: border,
                          onTap: () async {
                            Navigator.of(context).pop();
                            widget.onLater?.call();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Btn(
                          label: '문의 남기기',
                          bg: AppColors.gasBlue,
                          fg: Colors.white,
                          onTap: () async {
                            Navigator.of(context).pop();
                            widget.onNegative();
                          },
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _Btn(
                          label: '아쉬워요',
                          bg: Colors.transparent,
                          fg: textSecondary,
                          border: border,
                          onTap: () async {
                            setState(() => _negative = true);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Btn(
                          label: '좋아요 👍',
                          bg: AppColors.gasBlue,
                          fg: Colors.white,
                          onTap: () async {
                            Navigator.of(context).pop();
                            await widget.onPositive();
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
