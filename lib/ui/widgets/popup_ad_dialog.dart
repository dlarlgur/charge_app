import 'dart:async';

import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/api_constants.dart';
import '../../data/services/popup_ad_cache.dart';

class PopupAdDialog extends StatelessWidget {
  final SplashAd ad;

  const PopupAdDialog({super.key, required this.ad});

  static const _skipKey = 'popup_ad_skip_until';

  /// 홈 진입 시 호출. stale-while-revalidate:
  ///  - 캐시 hit → 즉시 다이얼로그 + 백그라운드로 fresh 갱신
  ///  - 캐시 miss → 네트워크에서 가져와 다이얼로그 + 캐시 저장
  static Future<void> showIfEligible(BuildContext context) async {
    final box = Hive.box(AppConstants.settingsBox);
    final skipUntil = box.get(_skipKey) as int?;
    if (skipUntil != null && DateTime.now().millisecondsSinceEpoch < skipUntil) {
      return;
    }

    final cached = PopupAdCache.read();
    if (cached != null) {
      final (ad, bytes) = cached;
      // 같은 url 의 Image.network 가 디스크 다운로드 없이 첫 프레임 그리도록 등록.
      final url = DkswCore.resolveAssetUrl(ad.imageUrl);
      await PopupAdCache.installInImageCache(url, bytes);
      // 백그라운드로 새 광고 가져와 디스크 갱신 — 다음 실행 반영.
      unawaited(_refreshInBackground());
      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.7),
        builder: (_) => PopupAdDialog(ad: ad),
      );
      return;
    }

    // 캐시 miss → 네트워크 fetch.
    final fresh = await DkswCore.fetchPopup();
    if (fresh == null) {
      // 서버에 광고 없음 — 캐시 정리 (이전 캐시가 stale 한 경우 대비).
      unawaited(PopupAdCache.clear());
      return;
    }
    unawaited(PopupAdCache.save(fresh));
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => PopupAdDialog(ad: fresh),
    );
  }

  /// 캐시 적중 시 백그라운드에서 호출 — 사용자에게 보이지 않음.
  /// 응답이 없으면 캐시를 비워 다음 실행에 더 이상 노출되지 않게 한다.
  static Future<void> _refreshInBackground() async {
    try {
      final fresh = await DkswCore.fetchPopup();
      if (fresh == null) {
        await PopupAdCache.clear();
        return;
      }
      if (!PopupAdCache.isSameAsCached(fresh)) {
        await PopupAdCache.save(fresh);
      }
    } catch (_) {}
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
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // 하단 액션 — "닫기"는 우상단 X 가 처리하므로 "오늘 하루 보지 않기"만 노출.
            // 작은 텍스트 링크 형태로 미니멀하게 (큰 버튼은 광고 본문 압도).
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _skipToday(context),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    '오늘 하루 보지 않기',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.85),
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white.withValues(alpha: 0.4),
                      decorationThickness: 1,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

