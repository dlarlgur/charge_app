import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/inbox_service.dart';
import 'inbox_detail_screen.dart';

/// 내 소식함 — 관리자가 나에게 보낸 메시지·쿠폰. 시간순 한 줄.
///
/// 만료된 쿠폰도 목록에서 지우지 않는다 — 지우면 "내가 받았던 거 어디 갔지?" 가 된다.
/// 회색 처리로 남겨두고, 대신 정렬은 건드리지 않아 받은 순서가 그대로 보이게 한다.
class InboxScreen extends StatefulWidget {
  /// 푸시/시상식에서 특정 항목으로 바로 들어올 때 — 목록을 거치지 않고 상세를 연다.
  final int? openId;

  const InboxScreen({super.key, this.openId});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<InboxItem>? _items;
  bool _jumped = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await InboxService.instance.list();
    if (!mounted) return;
    setState(() => _items = list);
    InboxService.instance.refreshUnread();

    // 딥링크로 들어온 항목이 있으면 한 번만 상세로 밀어준다.
    if (!_jumped && widget.openId != null) {
      _jumped = true;
      final hit = list.where((e) => e.id == widget.openId);
      if (hit.isNotEmpty) _open(hit.first);
    }
  }

  Future<void> _open(InboxItem it) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => InboxDetailScreen(item: it)));
    if (mounted) _load(); // 읽음·사용 표시가 목록에 반영되게
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = _items;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(title: const Text('내 소식함')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: items.isEmpty
                  ? _empty(isDark)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => InboxRow(
                          item: items[i],
                          isDark: isDark,
                          onTap: () => _open(items[i])),
                    ),
            ),
    );
  }

  /// 빈 상태도 스크롤 가능해야 당겨서 새로고침이 먹는다.
  Widget _empty(bool isDark) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        children: [
          Icon(Icons.mail_outline_rounded,
              size: 44,
              color: isDark
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted),
          const SizedBox(height: 14),
          Text('아직 받은 소식이 없어요',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary)),
          const SizedBox(height: 6),
          Text('이벤트 당첨이나 안내가 오면 여기에 쌓여요',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11.5,
                  color: isDark
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted)),
        ],
      );
}

/// 소식함 목록 한 줄. 화면 밖으로 뺀 이유는 위젯 테스트에서 네트워크 없이 그리기 위해서다.
class InboxRow extends StatelessWidget {
  final InboxItem item;
  final bool isDark;
  final VoidCallback? onTap;

  const InboxRow(
      {super.key, required this.item, required this.isDark, this.onTap});

  @override
  Widget build(BuildContext context) {
    // 쓸 수 없게 된 건 톤을 죽인다 — 목록에서 눈이 유효한 쿠폰에 먼저 가야 한다.
    final dim = item.expired || item.used;
    final ink = dim
        ? (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)
        : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isDark
                    ? AppColors.darkCardBorder
                    : const Color(0xFFE8ECF0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                if (!item.read)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 9),
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Color(0xFFEF4444)),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  item.read ? FontWeight.w600 : FontWeight.w800,
                              letterSpacing: -0.2,
                              color: ink)),
                      if (item.couponBrand != null) ...[
                        const SizedBox(height: 3),
                        Text(item.couponBrand!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _chip(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip() {
    if (!item.isCoupon) return const SizedBox.shrink();
    final String label;
    final Color fg;
    if (item.used) {
      label = '사용 완료';
      fg = const Color(0xFF94A3B8);
    } else if (item.expired) {
      label = '만료';
      fg = const Color(0xFF94A3B8);
    } else {
      final d = item.daysLeft;
      label = d == null ? '쿠폰' : 'D-$d';
      fg = const Color(0xFFC2410C);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: isDark ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          maxLines: 1,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: isDark ? const Color(0xFFE2E8F0) : fg)),
    );
  }
}
