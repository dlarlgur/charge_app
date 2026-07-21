import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_colors.dart';

/// 인앱 웹뷰 — 하우스 광고 CTA(webview 타입) 랜딩용.
/// 앱 톤: 상단 닫기 + 호스트 표시, 로딩 프로그레스.
class InAppWebScreen extends StatefulWidget {
  final String url;
  const InAppWebScreen({super.key, required this.url});

  static Future<void> open(BuildContext context, String url) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => InAppWebScreen(url: url)),
    );
  }

  @override
  State<InAppWebScreen> createState() => _InAppWebScreenState();
}

class _InAppWebScreenState extends State<InAppWebScreen> {
  late final WebViewController _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final host = Uri.tryParse(widget.url)?.host ?? '';
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          host,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: isDark ? AppColors.gasBlue : AppColors.gasBlueDark,
                ),
              )
            : null,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
