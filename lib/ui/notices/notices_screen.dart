import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton.dart';

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});
  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  late Future<List<NoticeItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = DkswCore.fetchNotices();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cached = DkswCore.lastBootstrap?.notices ?? const <NoticeItem>[];
    return Scaffold(
      appBar: AppBar(title: const Text('공지사항')),
      body: FutureBuilder<List<NoticeItem>>(
        future: _future,
        initialData: cached.isNotEmpty ? cached : null,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SkeletonRowList(rowCount: 6);
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: '등록된 공지가 없습니다',
              description: '새 공지가 올라오면 여기서 확인할 수 있어요.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              final fresh = await DkswCore.fetchNotices();
              if (mounted) setState(() => _future = Future.value(fresh));
            },
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 0.5,
                color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
              ),
              itemBuilder: (_, i) => _NoticeRow(notice: items[i], isDark: isDark),
            ),
          );
        },
      ),
    );
  }

}

class _NoticeRow extends StatelessWidget {
  final NoticeItem notice;
  final bool isDark;
  const _NoticeRow({required this.notice, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final primary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    final isBanner = notice.type == 'banner';
    final typeLabel = isBanner ? '서비스 공지' : '공지';
    const typeColor = AppColors.gasBlue;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NoticeDetailScreen(notice: notice)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notice.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: primary,
                  letterSpacing: -0.2,
                )),
            const SizedBox(height: 8),
            Row(children: [
              Text(typeLabel,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: typeColor)),
              if (notice.createdAt != null) ...[
                Text('  |  ', style: TextStyle(fontSize: 12, color: muted)),
                Text(_fmtDate(notice.createdAt!),
                    style: TextStyle(fontSize: 12, color: muted)),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }
}

class NoticeDetailScreen extends StatelessWidget {
  final NoticeItem notice;
  const NoticeDetailScreen({super.key, required this.notice});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final isBanner = notice.type == 'banner';
    final typeLabel = isBanner ? '서비스 공지' : '공지';

    return Scaffold(
      appBar: AppBar(title: const Text('공지사항')),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notice.title,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: primary,
                    )),
                const SizedBox(height: 10),
                Row(children: [
                  Text(typeLabel,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.gasBlue)),
                  if (notice.createdAt != null) ...[
                    Text('  |  ', style: TextStyle(fontSize: 12, color: muted)),
                    Text(_fmtDate(notice.createdAt!),
                        style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ]),
              ],
            ),
          ),
          if (notice.imageUrl != null && notice.imageUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  notice.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (notice.body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Html(
                data: notice.body,
                onLinkTap: (url, _, __) async {
                  if (url == null) return;
                  await launchUrl(Uri.parse(url),
                      mode: LaunchMode.externalApplication);
                },
              ),
            ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }
}
