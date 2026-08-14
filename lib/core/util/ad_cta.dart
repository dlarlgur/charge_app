import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/widgets/in_app_web_screen.dart';
import 'internal_link.dart';

/// 하우스 광고 CTA 공용 오프너.
///  · internal      : 앱 내부 화면 (콘솔이 '/cheer' 같은 식별자로 지정)
///  · webview       : 인앱 웹뷰로 랜딩 (광고주가 인앱 노출 요구 시)
///  · 그 외(external 등) : 외부 브라우저 아웃링크 (기본 — PDF 제안 표준)
///  · none / 빈 URL  : 무동작
Future<void> openAdCta(
  BuildContext context, {
  required String? url,
  required String ctaType,
}) async {
  if (url == null || url.isEmpty || ctaType == 'none') return;
  // ctaType 을 external 로 잘못 등록해도 '/…' 면 내부로 보낸다 —
  // 안 그러면 launchUrl('/cheer') 가 조용히 실패해 죽은 클릭이 된다.
  if (ctaType == 'internal' || isInternalLink(url)) {
    openInternalLink(context, url);
    return;
  }
  if (ctaType == 'webview') {
    await InAppWebScreen.open(context, url);
    return;
  }
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}
