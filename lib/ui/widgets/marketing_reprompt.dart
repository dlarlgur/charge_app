import 'package:flutter/material.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';

/// charge_app 전용 마케팅(광고성) 수신 동의 재요청 팝업.
/// [force]=false: 콘솔 재요청 ON + 미동의자 + 오늘 미노출일 때만 (게이팅 DkswCore).
/// [force]=true: 게이팅 무시하고 무조건 노출 (온보딩 끝낸 게스트 1회용).
/// 코어(dksw_app_core)의 바텀시트 대신 중앙 카드 디자인 + charge 전용 문구.
Future<void> maybeShowChargeMarketingReprompt(BuildContext context, {bool force = false}) async {
  if (!force) {
    if (!DkswCore.shouldShowMarketingReprompt()) return;
    await DkswCore.markMarketingRepromptShown(); // 동의/닫기 무관 오늘 노출 기록
  }

  final marketing = DkswCore.signupConsents.firstWhere(
    (c) => c.isMarketing,
    orElse: () => const SignupConsent(
        key: 'marketing', title: '마케팅 정보 수신', required: false, version: '1.0'),
  );
  if (!context.mounted) return;

  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accent = AppColors.gasBlue;
  final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
  final bg = isDark ? AppColors.darkCard : Colors.white;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '이벤트·혜택 소식을\n놓치지 않으려면 알림을 켜주세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, height: 1.4, color: textPrimary),
            ),
            const SizedBox(height: 24),
            // 종 아이콘 + ON 뱃지
            SizedBox(
              height: 92,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.notifications_rounded, size: 48, color: accent),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: bg, width: 2),
                      ),
                      child: const Text('ON',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '마케팅 정보 수신 동의 철회는\n마이페이지 > 앱 설정에서 변경할 수 있어요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.45, color: textSecondary),
            ),
            if (marketing.viewUrl != null) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: () async {
                  try {
                    await launchUrl(Uri.parse(marketing.viewUrl!),
                        mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('자세히 보기', style: TextStyle(fontSize: 12.5, color: textSecondary)),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  await DkswCore.postConsents([
                    ConsentChoice(
                        key: marketing.key, agreed: true, version: marketing.version),
                  ]);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('알림 받기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('나중에', style: TextStyle(fontSize: 14, color: textSecondary)),
            ),
          ],
        ),
      ),
    ),
  );
}
