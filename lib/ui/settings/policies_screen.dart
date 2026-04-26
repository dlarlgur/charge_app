import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';

const _kindIcons = <String, IconData>{
  'privacy': Icons.privacy_tip_rounded,
  'terms': Icons.description_rounded,
  'location_terms': Icons.location_on_rounded,
  'marketing': Icons.campaign_rounded,
  'subscription': Icons.credit_card_rounded,
  'etc': Icons.article_rounded,
};

class PoliciesScreen extends StatefulWidget {
  const PoliciesScreen({super.key});
  @override
  State<PoliciesScreen> createState() => _PoliciesScreenState();
}

class _PoliciesScreenState extends State<PoliciesScreen> {
  late Future<List<LegalDocument>> _future;

  @override
  void initState() {
    super.initState();
    _future = DkswCore.fetchLegalDocuments();
  }

  Future<void> _refresh() async {
    final fresh = await DkswCore.fetchLegalDocuments();
    if (mounted) setState(() => _future = Future.value(fresh));
  }

  Future<void> _open(LegalDocument doc) async {
    final uri = Uri.tryParse(doc.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('정책 및 약관')),
      body: FutureBuilder<List<LegalDocument>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) return _empty(isDark);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _PolicyTile(
                doc: items[i],
                isDark: isDark,
                onTap: () => _open(items[i]),
              ),
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
        Icon(Icons.description_outlined, size: 48, color: muted),
        const SizedBox(height: 12),
        Text('등록된 문서가 없습니다', style: TextStyle(color: muted, fontSize: 14)),
      ]),
    );
  }
}

class _PolicyTile extends StatelessWidget {
  final LegalDocument doc;
  final bool isDark;
  final VoidCallback onTap;
  const _PolicyTile({required this.doc, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF141823) : AppColors.lightCard;
    final border = isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;
    final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final icon = _kindIcons[doc.kind] ?? Icons.article_rounded;

    final sub = <String>[];
    if (doc.version != null && doc.version!.isNotEmpty) sub.add('v${doc.version}');
    if (doc.effectiveDate != null) sub.add('시행 ${_fmtDate(doc.effectiveDate!)}');
    if (doc.isExternal) sub.add('외부 링크');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 0.5),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: AppColors.gasBlue.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: AppColors.gasBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        sub.join(' · '),
                        style: TextStyle(fontSize: 11.5, color: secondary),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                doc.isExternal ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
                size: 20, color: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}.${l.month.toString().padLeft(2, '0')}.${l.day.toString().padLeft(2, '0')}';
  }
}
