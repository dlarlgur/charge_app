import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 이미 같은 충전소 알림 중 동작 선택 다이얼로그
/// returns true → 알림 끄기, false/null → 취소(유지)
Future<bool> showWatchAlreadyActiveDialog(
  BuildContext context, {
  required String stationName,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (ctx) => _WatchAlreadyActiveDialog(stationName: stationName),
  );
  return result == true;
}

/// 자리 변동 알림 전환 확인 다이얼로그
/// returns true → 전환하기, false/null → 아니요
Future<bool> showWatchSwitchDialog(
  BuildContext context, {
  required String currentStationName,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (ctx) => _WatchSwitchDialog(currentStationName: currentStationName),
  );
  return result == true;
}

class _WatchSwitchDialog extends StatelessWidget {
  final String currentStationName;
  const _WatchSwitchDialog({required this.currentStationName});

  static const _kBlue = Color(0xFF1D6FE0);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1F2C) : Colors.white;
    final iconBg = isDark ? AppColors.gasBlue.withValues(alpha: 0.18) : const Color(0xFFEEF4FF);
    final primary = isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
    final secondary = isDark ? AppColors.darkTextSecondary : const Color(0xFF555555);
    final borderColor = isDark ? AppColors.darkCardBorder : const Color(0xFFDDDDDD);
    final cancelText = isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 아이콘
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.radar_rounded, color: _kBlue, size: 26),
            ),
            const SizedBox(height: 16),

            // 타이틀
            Text(
              '자리 변동 알림 전환',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
            const SizedBox(height: 10),

            // 내용
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: secondary,
                ),
                children: [
                  TextSpan(
                    text: currentStationName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                  const TextSpan(text: '의 알림이 진행 중이에요.\n현재 알림을 끄고 이 충전소로 전환할까요?'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 버튼
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      '아니요',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cancelText,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      backgroundColor: _kBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      '전환하기',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
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

class _WatchAlreadyActiveDialog extends StatelessWidget {
  final String stationName;
  const _WatchAlreadyActiveDialog({required this.stationName});

  static const _kBlue = Color(0xFF1D6FE0);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1F2C) : Colors.white;
    final iconBg = isDark ? AppColors.gasBlue.withValues(alpha: 0.18) : const Color(0xFFEEF4FF);
    final primary = isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
    final secondary = isDark ? AppColors.darkTextSecondary : const Color(0xFF555555);
    final borderColor = isDark ? AppColors.darkCardBorder : const Color(0xFFDDDDDD);
    final cancelText = isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 아이콘
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.radar_rounded, color: _kBlue, size: 26),
            ),
            const SizedBox(height: 16),

            Text(
              '자리 변동 알림 수신 중',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
            const SizedBox(height: 10),

            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: secondary,
                ),
                children: [
                  TextSpan(
                    text: stationName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                  const TextSpan(text: '의\n자리 변동 알림을 받고 있어요.\n알림을 끌까요?'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      '유지',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cancelText,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      backgroundColor: const Color(0xFFE24B4A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      '알림 끄기',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
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
