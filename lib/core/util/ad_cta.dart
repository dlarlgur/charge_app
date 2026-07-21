import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/widgets/in_app_web_screen.dart';

/// 하우스 광고 CTA 공용 오프너.
///  · webview       : 인앱 웹뷰로 랜딩 (광고주가 인앱 노출 요구 시)
///  · 그 외(external 등) : 외부 브라우저 아웃링크 (기본 — PDF 제안 표준)
///  · none / 빈 URL  : 무동작
Future<void> openAdCta(
  BuildContext context, {
  required String? url,
  required String ctaType,
}) async {
  if (url == null || url.isEmpty || ctaType == 'none') return;
  if (ctaType == 'webview') {
    await InAppWebScreen.open(context, url);
    return;
  }
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}
