import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  late Future<List<EventItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = DkswCore.fetchEvents();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('이벤트')),
      body: FutureBuilder<List<EventItem>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SkeletonRowList(rowCount: 5);
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.celebration_outlined,
              title: '진행 중인 이벤트가 없습니다',
              description: '새 이벤트가 시작되면 여기서 알려드릴게요.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              final fresh = await DkswCore.fetchEvents();
              if (mounted) setState(() => _future = Future.value(fresh));
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _EventCard(event: items[i], isDark: isDark),
            ),
          );
        },
      ),
    );
  }

}

class _EventCard extends StatelessWidget {
  final EventItem event;
  final bool isDark;
  const _EventCard({required this.event, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF141823) : AppColors.lightCard;
    final border = isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (event.imageUrl != null && event.imageUrl!.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(event.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: muted.withValues(alpha: 0.1))),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      )),
                  if (event.summary != null && event.summary!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(event.summary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: secondary, height: 1.5)),
                  ],
                  const SizedBox(height: 8),
                  Text(_periodLabel(event),
                      style: TextStyle(fontSize: 11.5, color: muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _periodLabel(EventItem e) {
    if (e.startAt == null && e.endAt == null) return '상시 진행';
    String fmt(DateTime d) {
      final l = d.toLocal();
      return '${l.year}.${l.month.toString().padLeft(2, '0')}.${l.day.toString().padLeft(2, '0')}';
    }
    if (e.startAt != null && e.endAt != null) return '${fmt(e.startAt!)} ~ ${fmt(e.endAt!)}';
    if (e.endAt != null) return '${fmt(e.endAt!)} 까지';
    return '${fmt(e.startAt!)} 부터';
  }
}

class EventDetailScreen extends StatelessWidget {
  final EventItem event;
  const EventDetailScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('이벤트')),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (event.imageUrl != null && event.imageUrl!.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(event.imageUrl!, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)),
                if (event.summary != null && event.summary!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(event.summary!,
                      style: TextStyle(
                          fontSize: 14,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          height: 1.55)),
                ],
                const SizedBox(height: 18),
                Html(
                  data: event.bodyHtml,
                  onLinkTap: (url, _, __) async {
                    if (url == null) return;
                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
