import 'package:cached_network_image/cached_network_image.dart';
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
    _putSkip(context, tomorrow.millisecondsSinceEpoch);
  }

  void _skipMonth(BuildContext context) {
    final until = DateTime.now().add(const Duration(days: 30));
    _putSkip(context, until.millisecondsSinceEpoch);
  }

  void _putSkip(BuildContext context, int untilMs) {
    Hive.box(AppConstants.settingsBox).put('$_skipPrefix${notice.id}', untilMs);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF141823) : Colors.white;
    final primary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final divider = isDark ? const Color(0x14FFFFFF) : const Color(0xFFE2E8F0);

    final hasImage = notice.imageUrl != null && notice.imageUrl!.isNotEmpty;
    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
      clipBehavior: Clip.antiAlias,
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
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasImage)
                      CachedNetworkImage(
                        imageUrl: DkswCore.resolveAssetUrl(notice.imageUrl!),
                        fit: BoxFit.fitWidth,
                        width: double.infinity,
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ..._popupBodyWidgets(context, notice.body, hasImage),
                  ],
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
                  child: const Text('오늘 하루 안 보기', style: TextStyle(fontSize: 13.5)),
                ),
              ),
              Container(width: 1, height: 20, color: divider),
              Expanded(
                child: TextButton(
                  onPressed: () => _skipMonth(context),
                  style: TextButton.styleFrom(
                    foregroundColor: secondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: const Text('한 달 안 보기', style: TextStyle(fontSize: 13.5)),
                ),
              ),
            ]),
            Divider(height: 1, color: divider),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.gasBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(),
              ),
              child: const Text('닫기',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// 팝업 본문 — 링크(<a>)를 네이티브 CTA 버튼으로 분리해 렌더.
List<Widget> _popupBodyWidgets(BuildContext context, String body, bool hasImage) {
  final split = _splitCtas(body);
  final hasText = split.body.replaceAll(RegExp(r'<[^>]*>|&nbsp;|\s'), '').isNotEmpty;
  if (!hasText && split.ctas.isEmpty) return const [];
  return [
    Padding(
      padding: EdgeInsets.fromLTRB(20, hasImage ? 14 : 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasText)
            Html(
              data: split.body,
              onLinkTap: (url, _, __) async {
                if (url != null) await _openPopupLink(context, url);
              },
            ),
          ...split.ctas.map((c) => _popupCtaButton(context, c)),
        ],
      ),
    ),
  ];
}

({String body, List<({String href, String label})> ctas}) _splitCtas(String html) {
  final ctas = <({String href, String label})>[];
  final re = RegExp(r'<a\b[^>]*href="([^"]*)"[^>]*>(.*?)</a>',
      caseSensitive: false, dotAll: true);
  final body = html.replaceAllMapped(re, (m) {
    final href = (m.group(1) ?? '').trim();
    final label = _cleanLabel(m.group(2) ?? '');
    if (href.isNotEmpty) {
      ctas.add((href: href, label: label.isEmpty ? '바로가기' : label));
    }
    return '';
  });
  return (body: body, ctas: ctas);
}

String _cleanLabel(String raw) {
  return raw
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&rarr;', '')
      .replaceAll('&#8594;', '')
      .replaceAll('→', '')
      .replaceAll('&amp;', '&')
      .replaceAll('&nbsp;', ' ')
      .trim();
}

// 팝업 닫고 이동. http(s)=외부. 그 외(내부 식별자)는 이 앱에 대상 화면이 없어 무시.
Future<void> _openPopupLink(BuildContext context, String url) async {
  Navigator.of(context).pop();
  if (url.startsWith('http://') || url.startsWith('https://')) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

Widget _popupCtaButton(BuildContext context, ({String href, String label}) cta) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () { _openPopupLink(context, cta.href); },
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          cta.label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}
