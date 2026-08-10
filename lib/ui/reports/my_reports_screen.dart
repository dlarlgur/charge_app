import 'package:flutter/material.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/api_service.dart';

/// 내 제보 내역 — 이 기기에서 보낸 주유소/충전소 정보 제보와 처리 상태·관리자 답변.
/// 설정 > 지원 섹션에서 진입. 답변(사유 안내/반영 완료 푸시 문구)이 카드에 말풍선으로 붙음.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  List<Map<String, dynamic>>? _reports; // null = 로딩 중
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ApiService().getMyReports();
      if (mounted) setState(() => _reports = list);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _reports = const [];
        });
      }
    }
  }

  String _fmtDate(String? raw) {
    final dt = DateTime.tryParse(raw ?? '')?.toLocal();
    if (dt == null) return '';
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : const Color(0xFFF6F8FA);
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('내 제보 내역'),
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _reports == null
            ? const Center(child: CircularProgressIndicator())
            : _reports!.isEmpty
                ? _emptyState(isDark, muted)
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _reports!.length,
                    itemBuilder: (_, i) => _reportCard(_reports![i], isDark),
                  ),
      ),
    );
  }

  Widget _emptyState(bool isDark, Color muted) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // 화면 세로 중앙에 오도록 — 고정 비율 스페이서는 기기별로 위/아래로 쏠린다(형 지적 계열).
        SizedBox(height: MediaQuery.of(context).size.height * 0.30),
        Icon(_error ? Icons.wifi_off_rounded : Icons.fact_check_outlined,
            size: 44, color: muted),
        const SizedBox(height: 14),
        Center(
          child: Text(
            _error ? '내역을 불러오지 못했어요\n아래로 당겨 다시 시도해 주세요' : '아직 보낸 제보가 없어요',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: muted, height: 1.5),
          ),
        ),
        if (!_error) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              '주유소·충전소 상세 화면 아래의\n"정보가 달라요" 버튼으로 제보할 수 있어요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: muted, height: 1.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _reportCard(Map<String, dynamic> r, bool isDark) {
    final isEv = r['stationType'] == 'ev';
    final done = r['status'] == 'done';
    final accent = isEv ? AppColors.evGreen : AppColors.gasBlue;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A2E);
    final reply = (r['adminReply'] as String?)?.trim();
    final detail = (r['detailText'] as String?)?.trim();
    final memo = (r['memo'] as String?)?.trim();
    final myPhotos = _urls(r['photoUrls']);
    final replyPhotos = _urls(r['replyImageUrls']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 종류·이름 + 상태
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withOpacity(isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(isEv ? '충전소' : '주유소',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: accent)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (r['stationName'] as String?)?.trim().isNotEmpty == true
                      ? r['stationName'] as String
                      : '(이름 없음)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700, color: ink),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: done
                      ? AppColors.success.withOpacity(isDark ? 0.18 : 0.10)
                      : (isDark
                          ? AppColors.darkAmberBright.withOpacity(0.15)
                          : const Color(0xFFFFF4DE)),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(done ? '처리 완료' : '확인 중',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: done
                          ? AppColors.success
                          : (isDark
                              ? AppColors.darkAmberBright
                              : const Color(0xFFB07B1E)),
                    )),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 본문: 카테고리 + 제보 내용
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(r['categoryLabel']?.toString() ?? '',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
              if (detail != null && detail.isNotEmpty)
                Text(detail,
                    style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black87)),
            ],
          ),
          if (memo != null && memo.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(memo,
                style: TextStyle(fontSize: 12.5, color: muted, height: 1.45)),
          ],
          if (myPhotos.isNotEmpty) ...[
            const SizedBox(height: 8),
            _photoRow(context, myPhotos),
          ],

          // 관리자 답변 말풍선
          if (reply != null && reply.isNotEmpty) ...[
            const SizedBox(height: 11),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: accent.withOpacity(isDark ? 0.10 : 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withOpacity(0.25), width: 0.7),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.reply_rounded, size: 13, color: accent),
                      const SizedBox(width: 4),
                      Text('답변',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: accent)),
                      const Spacer(),
                      Text(_fmtDate(r['repliedAt']?.toString()),
                          style: TextStyle(fontSize: 10.5, color: muted)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(reply,
                      style: TextStyle(fontSize: 13, color: ink, height: 1.5)),
                  if (replyPhotos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _photoRow(context, replyPhotos),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),
          Text(_fmtDate(r['createdAt']?.toString()),
              style: TextStyle(fontSize: 11, color: muted)),
        ],
      ),
    );
  }
}

/// 서버 photoUrls/replyImageUrls → 절대 URL 목록
List<String> _urls(dynamic v) {
  if (v is! List) return const [];
  final origin = ApiConstants.baseUrl.replaceFirst(RegExp(r'/api\/?$'), '');
  return v
      .map((e) => e.toString())
      .where((u) => u.isNotEmpty)
      .map((u) => u.startsWith('http') ? u : '$origin$u')
      .toList();
}

/// 첨부 썸네일 줄 — 탭하면 전체보기 (문의 상세와 동일 패턴)
Widget _photoRow(BuildContext context, List<String> urls) {
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final u in urls)
        GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.black,
              insetPadding: const EdgeInsets.all(12),
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.network(u, fit: BoxFit.contain),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              u,
              width: 84,
              height: 84,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
    ],
  );
}
