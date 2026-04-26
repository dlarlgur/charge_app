import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});
  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  late Future<List<FaqItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = DkswCore.fetchFaqs();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('자주 묻는 질문')),
      body: FutureBuilder<List<FaqItem>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SkeletonRowList(rowCount: 5);
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.help_outline_rounded,
              title: '등록된 질문이 없습니다',
              description: '곧 자주 묻는 질문 모음을 채워드릴게요.',
            );
          }

          // category 별로 그룹핑 (null은 "기타")
          final groups = <String, List<FaqItem>>{};
          for (final f in items) {
            final key = (f.category?.trim().isNotEmpty ?? false) ? f.category! : '기타';
            groups.putIfAbsent(key, () => []).add(f);
          }

          return RefreshIndicator(
            onRefresh: () async {
              final fresh = await DkswCore.fetchFaqs();
              if (mounted) setState(() => _future = Future.value(fresh));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                for (final entry in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
                    child: Text(entry.key,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          letterSpacing: 0.3,
                        )),
                  ),
                  for (final faq in entry.value) _FaqTile(faq: faq, isDark: isDark),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

}

class _FaqTile extends StatefulWidget {
  final FaqItem faq;
  final bool isDark;
  const _FaqTile({required this.faq, required this.isDark});
  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF141823) : AppColors.lightCard;
    final border = isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;
    final primary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Text('Q',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.gasBlue)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.faq.question,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: primary,
                            height: 1.4)),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: muted),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _open
                ? Container(
                    padding: const EdgeInsets.fromLTRB(40, 0, 16, 14),
                    child: Html(
                      data: widget.faq.answer,
                      onLinkTap: (url, _, __) async {
                        if (url == null) return;
                        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
