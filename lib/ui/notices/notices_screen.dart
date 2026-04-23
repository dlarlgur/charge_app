import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

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
    _future = _load();
  }

  Future<List<NoticeItem>> _load() async {
    final cached = DkswCore.lastBootstrap?.notices ?? const [];
    if (cached.isNotEmpty) return cached;
    return DkswCore.fetchNotices();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('공지사항')),
      body: FutureBuilder<List<NoticeItem>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return _empty(isDark);
          }
          return RefreshIndicator(
            onRefresh: () async {
              final fresh = await DkswCore.fetchNotices();
              if (mounted) setState(() => _future = Future.value(fresh));
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _NoticeCard(notice: items[i], isDark: isDark),
            ),
          );
        },
      ),
    );
  }

  Widget _empty(bool isDark) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.notifications_none_rounded, size: 48, color: muted),
        const SizedBox(height: 12),
        Text('등록된 공지가 없습니다', style: TextStyle(color: muted, fontSize: 14)),
      ]),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final NoticeItem notice;
  final bool isDark;
  const _NoticeCard({required this.notice, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF141823) : AppColors.lightCard;
    final border = isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;
    final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    final isBanner = notice.type == 'banner';
    final badgeColor = isBanner ? AppColors.gasBlue : AppColors.warning;
    final badgeLabel = isBanner ? '배너' : '공지';

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(badgeLabel,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor)),
              ),
              if (notice.createdAt != null) ...[
                const SizedBox(width: 8),
                Text(_fmtDate(notice.createdAt!),
                    style: TextStyle(fontSize: 11, color: muted)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(notice.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                letterSpacing: -0.2,
              )),
          const SizedBox(height: 8),
          Text(notice.body,
              style: TextStyle(fontSize: 13.5, color: secondary, height: 1.55)),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }
}
