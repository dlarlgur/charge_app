import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';

class PopupNoticeDialog extends StatelessWidget {
  final NoticeItem notice;
  const PopupNoticeDialog({super.key, required this.notice});

  static const _skipPrefix = 'popup_notice_skip_';

  static Future<void> showIfEligible(BuildContext context) async {
    final notices = DkswCore.lastBootstrap?.notices ?? const [];
    final popup = notices.where((n) => n.type == 'popup').toList();
    if (popup.isEmpty) return;

    final box = Hive.box(AppConstants.settingsBox);
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final n in popup) {
      final skipUntil = box.get('$_skipPrefix${n.id}') as int?;
      if (skipUntil != null && now < skipUntil) continue;
      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (_) => PopupNoticeDialog(notice: n),
      );
      return;
    }
  }

  void _skipToday(BuildContext context) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    Hive.box(AppConstants.settingsBox)
        .put('$_skipPrefix${notice.id}', tomorrow.millisecondsSinceEpoch);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF141823) : Colors.white;
    final primary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final divider = isDark ? const Color(0x14FFFFFF) : const Color(0xFFE2E8F0);

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(notice.title,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: primary,
                      letterSpacing: -0.3)),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Html(
                  data: notice.body,
                  onLinkTap: (url, _, __) async {
                    if (url == null) return;
                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                ),
              ),
            ),
            Divider(height: 1, color: divider),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => _skipToday(context),
                  style: TextButton.styleFrom(
                    foregroundColor: secondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: const Text('오늘 보지 않기', style: TextStyle(fontSize: 14)),
                ),
              ),
              Container(width: 1, height: 20, color: divider),
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.gasBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: const Text('닫기',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
