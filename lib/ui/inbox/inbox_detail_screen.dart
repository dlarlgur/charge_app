import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/util/app_toast.dart';
import '../../data/services/inbox_service.dart';

/// 소식 상세. 쿠폰이면 바코드를 크게 띄운다.
///
/// 바코드 이미지는 공개 URL 이 아니다 — 기프티콘은 사실상 현금이라 정적 경로에 두면
/// URL 만 아는 사람이 쓴다. 서버가 소유자를 확인한 뒤에만 내려주므로
/// Image.network 에 Authorization 헤더를 실어 보낸다.
class InboxDetailScreen extends StatefulWidget {
  final InboxItem item;
  const InboxDetailScreen({super.key, required this.item});

  @override
  State<InboxDetailScreen> createState() => _InboxDetailScreenState();
}

class _InboxDetailScreenState extends State<InboxDetailScreen> {
  late bool _used = widget.item.used;
  Map<String, String>? _headers;

  @override
  void initState() {
    super.initState();
    InboxService.instance.markRead(widget.item.id);
    if (widget.item.hasImage) {
      InboxService.instance.imageHeaders().then((h) {
        if (mounted) setState(() => _headers = h);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final it = widget.item;
    final ink = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final sub =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(title: const Text('소식')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(it.title,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: ink)),
          if (it.body != null && it.body!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(it.body!,
                style: TextStyle(fontSize: 13.5, height: 1.55, color: sub)),
          ],
          if (it.isCoupon) ...[
            const SizedBox(height: 18),
            if (it.couponBrand != null)
              Text(it.couponBrand!,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFC2410C)
                          .withValues(alpha: isDark ? 0.95 : 1))),
            if (it.hasImage) ...[
              const SizedBox(height: 12),
              _barcode(isDark),
              const SizedBox(height: 8),
              // 밝기를 자동으로 못 올리므로 안내라도 준다 — 어두우면 매장 스캐너가 못 읽는다.
              Text('스캔이 안 되면 화면 밝기를 최대로 올려 주세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted)),
            ],
            if (it.couponCode != null) ...[
              const SizedBox(height: 14),
              _codeRow(it.couponCode!, isDark),
            ],
            if (it.expiresAt != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 14,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                        it.expired
                            ? '유효기간 ${it.expiresAt} (만료)'
                            : '유효기간 ${it.expiresAt}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                it.expired ? FontWeight.w800 : FontWeight.w600,
                            color: it.expired
                                ? const Color(0xFFEF4444)
                                : (isDark
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted))),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              height: 46,
              child: OutlinedButton(
                onPressed: () async {
                  final next = !_used;
                  setState(() => _used = next);
                  await InboxService.instance.markUsed(it.id, next);
                },
                child: Text(_used ? '사용 완료 취소' : '사용 완료로 표시',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 헤더가 준비되기 전에 그리면 401 로 실패한 이미지가 캐시된다 — 준비 후에만 띄운다.
  Widget _barcode(bool isDark) {
    final headers = _headers;
    if (headers == null) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        // 바코드는 흰 배경에서 대비가 가장 좋다 — 다크 모드에서도 흰 판 위에 올린다.
        color: Colors.white,
        padding: const EdgeInsets.all(10),
        child: Image.network(
          InboxService.instance.imageUrl(widget.item.id),
          headers: headers,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _imageFallback(),
          loadingBuilder: (_, child, p) => p == null
              ? child
              : const SizedBox(
                  height: 160,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      ),
    );
  }

  Widget _imageFallback() => const SizedBox(
        height: 140,
        child: Center(
          child: Text('이미지를 불러오지 못했어요\n당겨서 새로고침해 주세요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
        ),
      );

  Widget _codeRow(String code, bool isDark) => Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark
                  ? AppColors.darkCardBorder
                  : const Color(0xFFE8ECF0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(code,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary)),
            ),
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                showAppToast(context, '쿠폰 번호를 복사했어요');
              },
              child: const Text('복사'),
            ),
          ],
        ),
      );
}
