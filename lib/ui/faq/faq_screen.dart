import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton.dart';

/// 카테고리별 브랜드 색 + 아이콘 (앱 톤과 통일)
({Color color, IconData icon}) _catMeta(String cat, bool isDark) {
  switch (cat.trim()) {
    case '주유':
      return (color: AppColors.gasBlue, icon: Icons.local_gas_station_rounded);
    case '충전':
      return (color: AppColors.evGreen, icon: Icons.ev_station_rounded);
    case 'AI 추천':
    case 'AI추천':
      return (color: const Color(0xFF7C3AED), icon: Icons.auto_awesome_rounded);
    case '알림':
      return (color: const Color(0xFFF59E0B), icon: Icons.notifications_active_rounded);
    case '계정':
      return (color: const Color(0xFF6366F1), icon: Icons.person_rounded);
    default: // 일반 / 기타
      return (
        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
        icon: Icons.info_outline_rounded,
      );
  }
}

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
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
              children: [
                const _FaqIntro(),
                for (final entry in groups.entries) ...[
                  _CategoryHeader(category: entry.key, isDark: isDark),
                  for (final faq in entry.value) _FaqTile(faq: faq, isDark: isDark),
                ],
                const SizedBox(height: 8),
                _StillNeedHelp(isDark: isDark),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 상단 한 줄 안내 (친근한 인트로)
class _FaqIntro extends StatelessWidget {
  const _FaqIntro();
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      child: Text(
        '궁금한 점을 모아봤어요. 질문을 눌러 답변을 확인하세요.',
        style: TextStyle(fontSize: 13, color: muted, height: 1.45),
      ),
    );
  }
}

/// 카테고리 헤더 — 색 아이콘 칩 + 라벨
class _CategoryHeader extends StatelessWidget {
  final String category;
  final bool isDark;
  const _CategoryHeader({required this.category, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final meta = _catMeta(category, isDark);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 6, 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(meta.icon, size: 15, color: meta.color),
          ),
          const SizedBox(width: 8),
          Text(
            category,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: meta.color,
              letterSpacing: 0.2,
            ),
          ),
        ],
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
    final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final cat = (widget.faq.category?.trim().isNotEmpty ?? false) ? widget.faq.category! : '기타';
    final accent = _catMeta(cat, isDark).color;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _open ? accent.withValues(alpha: 0.5) : border,
          width: _open ? 1 : 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Badge(letter: 'Q', color: accent),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(widget.faq.question,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: primary,
                              height: 1.35)),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Badge(letter: 'A', color: accent, filled: true),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Html(
                            data: widget.faq.answer,
                            style: {
                              'body': Style(
                                margin: Margins.zero,
                                padding: HtmlPaddings.zero,
                                fontFamily: 'Pretendard',
                                fontSize: FontSize(13.5),
                                lineHeight: LineHeight.number(1.65),
                                color: secondary,
                              ),
                              'a': Style(
                                color: accent,
                                fontWeight: FontWeight.w600,
                              ),
                              'b': Style(color: primary, fontWeight: FontWeight.w700),
                              'strong': Style(color: primary, fontWeight: FontWeight.w700),
                            },
                            onLinkTap: (url, _, __) async {
                              if (url == null) return;
                              await launchUrl(Uri.parse(url),
                                  mode: LaunchMode.externalApplication);
                            },
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Q / A 원형 배지
class _Badge extends StatelessWidget {
  final String letter;
  final Color color;
  final bool filled;
  const _Badge({required this.letter, required this.color, this.filled = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: filled ? Colors.white : color,
        ),
      ),
    );
  }
}

/// 하단 "답을 못 찾았어요" → 1:1 문의 유도
class _StillNeedHelp extends StatelessWidget {
  final bool isDark;
  const _StillNeedHelp({required this.isDark});
  @override
  Widget build(BuildContext context) {
    final primary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    return Container(
      margin: const EdgeInsets.fromLTRB(2, 6, 2, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF111827), const Color(0xFF0E1726)]
              : [const Color(0xFFEFF6FF), const Color(0xFFF5F3FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.gasBlue.withValues(alpha: isDark ? 0.3 : 0.2),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.support_agent_rounded, color: AppColors.gasBlue, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('원하는 답을 못 찾으셨나요?',
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700, color: primary)),
                const SizedBox(height: 2),
                Text('1:1 문의를 남겨주시면 빠르게 도와드릴게요.',
                    style: TextStyle(fontSize: 12, color: muted, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => context.push('/inquiry'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gasBlue,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('문의하기',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
