import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/api_constants.dart';

class PopupAdDialog extends StatelessWidget {
  final SplashAd ad;

  const PopupAdDialog({super.key, required this.ad});

  static const _skipKey = 'popup_ad_skip_until';

  static Future<void> showIfEligible(BuildContext context) async {
    final box = Hive.box(AppConstants.settingsBox);
    final skipUntil = box.get(_skipKey) as int?;
    if (skipUntil != null && DateTime.now().millisecondsSinceEpoch < skipUntil) {
      return;
    }
    final ad = await DkswCore.fetchPopup();
    if (ad == null || !context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (_) => PopupAdDialog(ad: ad),
    );
  }

  void _skipToday(BuildContext context) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    Hive.box(AppConstants.settingsBox).put(_skipKey, tomorrow.millisecondsSinceEpoch);
    Navigator.pop(context);
  }

  Future<void> _handleTap(BuildContext context) async {
    // impressions는 서버에서 /popup 응답 시 이미 +1. click만 보고.
    DkswCore.trackAdClick(ad.id);

    final url = ad.ctaUrl;
    if (url == null || url.isEmpty || ad.ctaType == 'none') {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context);
    final uri = Uri.parse(url);
    if (ad.ctaType == 'external') {
      if (await canLaunchUrl(uri)) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (ad.ctaType == 'internal') {
      // 내부 딥링크는 앱 라우터에 맞게 확장 가능. 현재는 보류.
      if (await canLaunchUrl(uri)) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 이미지 (탭 시 CTA)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: () => _handleTap(context),
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: Image.network(
                        DkswCore.resolveAssetUrl(ad.imageUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.black26,
                          child: const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 하단 액션 바
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _skipToday(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    child: const Text('오늘 보지 않기', style: TextStyle(fontSize: 13)),
                  ),
                  Container(width: 1, height: 14, color: Colors.white24),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    child: const Text('닫기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

