import 'package:flutter/material.dart';

import '../../core/constants/api_constants.dart';
import '../../data/services/api_service.dart';
import '../../data/services/alert_service.dart';

/// 1:1 문의하기 — 내 문의 목록 + 새 문의 작성. 답변은 콘솔에서 등록되며 푸시로 알림.
class InquiryScreen extends StatefulWidget {
  const InquiryScreen({super.key});

  @override
  State<InquiryScreen> createState() => _InquiryScreenState();
}

class _InquiryScreenState extends State<InquiryScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  String get _deviceId => AlertService().deviceId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() => ApiService().getMyInquiries(
        appId: AppConstants.packageName,
        deviceId: _deviceId,
      );

  void _reload() => setState(() => _future = _load());

  Future<void> _openNew() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewInquirySheet(),
    );
    if (created == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('1:1 문의하기')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNew,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('문의하기'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.chat_bubble_outline_rounded,
                      size: 56, color: isDark ? Colors.white24 : Colors.black26),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text('아직 문의 내역이 없어요',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text('궁금한 점을 편하게 남겨주세요',
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.black45)),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _InquiryCard(inquiry: items[i], isDark: isDark),
            );
          },
        ),
      ),
    );
  }
}

class _InquiryCard extends StatelessWidget {
  final Map<String, dynamic> inquiry;
  final bool isDark;
  const _InquiryCard({required this.inquiry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final answered = inquiry['status'] == 'answered';
    final reply = inquiry['reply']?.toString();
    final title = inquiry['title']?.toString() ?? '';
    final content = inquiry['content']?.toString() ?? '';
    final cardBg = isDark ? const Color(0xFF1C2230) : Colors.white;
    final ink = isDark ? Colors.white : const Color(0xFF0F172A);
    final muted = isDark ? Colors.white54 : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink)),
              ),
              const SizedBox(width: 8),
              _StatusBadge(answered: answered),
            ],
          ),
          const SizedBox(height: 8),
          Text(content, style: TextStyle(fontSize: 14, height: 1.45, color: ink.withValues(alpha: 0.85))),
          if (answered && reply != null && reply.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF15233B) : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border(left: BorderSide(color: const Color(0xFF3B82F6), width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('답변',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF3B82F6))),
                  const SizedBox(height: 4),
                  Text(reply, style: TextStyle(fontSize: 14, height: 1.45, color: ink)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool answered;
  const _StatusBadge({required this.answered});
  @override
  Widget build(BuildContext context) {
    final bg = answered ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0);
    final fg = answered ? const Color(0xFF2E7D32) : const Color(0xFFE8700A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(answered ? '답변완료' : '답변대기',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

class _NewInquirySheet extends StatefulWidget {
  const _NewInquirySheet();
  @override
  State<_NewInquirySheet> createState() => _NewInquirySheetState();
}

class _NewInquirySheetState extends State<_NewInquirySheet> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) {
      setState(() => _error = '제목과 내용을 모두 입력해주세요.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final ok = await ApiService().createInquiry(
        appId: AppConstants.packageName,
        deviceId: AlertService().deviceId,
        title: title,
        content: content,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _sending = false;
          _error = '전송에 실패했어요. 잠시 후 다시 시도해주세요.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '네트워크 오류가 발생했어요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF161B26) : Colors.white;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('1:1 문의하기',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: _titleCtrl,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: '제목',
                hintText: '예: 경로 추천이 이상해요',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentCtrl,
              maxLines: 5,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: '내용',
                hintText: '문의 내용을 자세히 적어주세요.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: Color(0xFFE53935), fontSize: 13)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _sending ? null : _submit,
                child: _sending
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('보내기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
