import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../../core/theme/app_colors.dart';

/// 약관/정책을 외부 브라우저 대신 앱 안에서 보여주는 바텀시트.
/// viewUrl 의 HTML 을 받아 flutter_html 로 렌더(문서 톤 = 흰 배경).
Future<void> showPolicySheet(BuildContext context, {required String url, required String title}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PolicySheet(url: url, title: title),
  );
}

class _PolicySheet extends StatefulWidget {
  final String url;
  final String title;
  const _PolicySheet({required this.url, required this.title});

  @override
  State<_PolicySheet> createState() => _PolicySheetState();
}

class _PolicySheetState extends State<_PolicySheet> {
  String? _html;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Dio().get<String>(
        widget.url,
        options: Options(responseType: ResponseType.plain),
      );
      if (!mounted) return;
      setState(() {
        _html = res.data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white, // 문서 톤 — 다크모드여도 약관은 흰 배경에 읽기 좋게
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9D9D9),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF666666)),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('약관을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xFF666666))),
                            ),
                          )
                        : SingleChildScrollView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            child: Html(
                              data: _html ?? '',
                              style: {
                                'body': Style(
                                  margin: Margins.zero,
                                  fontSize: FontSize(15),
                                  lineHeight: LineHeight(1.7),
                                  color: const Color(0xFF333333),
                                ),
                                'h1': Style(fontSize: FontSize(21), color: AppColors.gasBlue),
                                'h2': Style(fontSize: FontSize(17), color: const Color(0xFF222222)),
                                'h3': Style(fontSize: FontSize(15.5), color: const Color(0xFF444444)),
                                'a': Style(color: AppColors.gasBlue),
                              },
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}
