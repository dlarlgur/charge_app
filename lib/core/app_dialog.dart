import 'package:flutter/material.dart';

import 'theme/app_colors.dart';

/// 앱 공용 다이얼로그 — 둥근 카드 + 아이콘 칩 + 강조 버튼.
/// 기본 AlertDialog 대신 이걸로 통일해 톤을 맞춘다.
///
/// 반환값: primary 탭 → [primaryValue], secondary 탭 → [secondaryValue], 바깥 탭 → null.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String primaryLabel,
  T? primaryValue,
  String? secondaryLabel,
  T? secondaryValue,
  Color accent = AppColors.gasBlue,
  bool barrierDismissible = true,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bg = isDark ? AppColors.darkCard : Colors.white;
  final textPrimary =
      isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  final textSecondary =
      isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      // 작은 화면·큰 시스템 폰트에서 내용이 길어도 넘치지 않게 스크롤 허용.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: accent),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.55, color: textSecondary),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(primaryValue),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(primaryLabel,
                    style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(secondaryValue),
                child: Text(secondaryLabel,
                    style: TextStyle(fontSize: 14, color: textSecondary)),
              ),
            ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
