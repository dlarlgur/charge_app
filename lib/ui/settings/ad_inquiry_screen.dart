import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';

/// 광고 문의 — 지면 소개 + 문의처.
///
/// 단가는 넣지 않는다. 초기 매체는 상대·기간에 따라 조정 여지가 필요하고,
/// 한번 공개한 가격은 되돌리기 어렵다. 규모와 지면만 보여주고 협의로 넘긴다.
class AdInquiryScreen extends StatelessWidget {
  const AdInquiryScreen({super.key});

  static const _email = 'ghim2131@gmail.com';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('광고 문의')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
        children: [
          _hero(isDark),
          const SizedBox(height: 18),
          _sectionTitle('광고 지면', isDark),
          const SizedBox(height: 10),
          _placementsCard(isDark),
          const SizedBox(height: 18),
          _sectionTitle('이런 분께 맞아요', isDark),
          const SizedBox(height: 10),
          _fitChips(isDark),
          const SizedBox(height: 18),
          _sectionTitle('문의', isDark),
          const SizedBox(height: 10),
          _contactCard(context, isDark),
          const SizedBox(height: 12),
          Text(
            '단가와 소재 규격은 문의 주시면 제안서로 안내드려요. 집행 중에는 노출·클릭 리포트를 보내드립니다.',
            style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted),
          ),
        ],
      ),
    );
  }

  Widget _hero(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF16324F), const Color(0xFF12283D)]
              : [const Color(0xFFEFF6FF), const Color(0xFFE0F2FE)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isDark
                ? AppColors.darkGasActiveBorder
                : AppColors.lightGasActiveBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('전기차 기름차에 광고하기',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary)),
          const SizedBox(height: 6),
          Text('주유소·충전소를 찾는 순간에 노출됩니다.',
              style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary)),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat('월 이용자', '2,200+', isDark),
              _statDivider(isDark),
              _stat('일 이용자', '450+', isDark),
              _statDivider(isDark),
              _stat('차량 등록', '1,800+', isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, bool isDark) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: AppColors.gasBlue)),
            ),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextSecondary)),
          ],
        ),
      );

  Widget _statDivider(bool isDark) => Container(
        width: 1,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.10),
      );

  Widget _sectionTitle(String t, bool isDark) => Text(t,
      style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color:
              isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary));

  // 설명은 한 줄로 — 규격·단가 같은 실무 정보는 문의 후 제안서에서 (화면이 조잡해짐).
  static const _placements = <(IconData, String, String)>[
    (Icons.smartphone_rounded, '앱 실행 화면', '앱을 켤 때 전체 화면 1회 — 브랜드 각인'),
    (Icons.view_agenda_rounded, '홈 상단 배너', '목록 맨 위 고정 — 가장 많이 보는 자리'),
    (Icons.format_list_bulleted_rounded, '홈 목록 사이', '탐색 흐름 속에 자연스러운 카드형'),
    (Icons.login_rounded, '로그인 화면', '노출은 적지만 정독하는 순간 — 반응률 최고'),
    (Icons.local_gas_station_rounded, '주유소·충전소 상세', '방문 직전 사용자 — 세차·정비 맞춤'),
  ];

  /// 지면 목록 — 카드 하나에 행 분할 (앱 공통 문법). 행마다 아이콘 + 제목 + 한 줄 설명.
  Widget _placementsCard(bool isDark) {
    final line = isDark ? AppColors.darkCardBorder : const Color(0xFFF0F3F6);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _placements.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Divider(height: 1, thickness: 1, color: line),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.gasBlue
                          .withValues(alpha: isDark ? 0.18 : 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_placements[i].$1,
                        size: 17, color: AppColors.gasBlue),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_placements[i].$2,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.lightTextPrimary)),
                        const SizedBox(height: 2),
                        Text(_placements[i].$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 업종 칩 — 문장 나열 대신 한눈에 (형: 조잡함 정리).
  Widget _fitChips(bool isDark) {
    const items = <(IconData, String)>[
      (Icons.local_gas_station_rounded, '주유소 · 충전소'),
      (Icons.local_car_wash_rounded, '세차 · 정비 · 타이어'),
      (Icons.directions_car_rounded, '자동차 용품 · 보험'),
      (Icons.storefront_rounded, '지역 소상공인'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final it in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                  color: isDark
                      ? AppColors.darkCardBorder
                      : AppColors.lightCardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(it.$1, size: 15, color: AppColors.evGreen),
                const SizedBox(width: 7),
                Text(it.$2,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _contactCard(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color:
                isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('이메일로 문의해 주세요',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary)),
          const SizedBox(height: 3),
          Text('업종 · 희망 지면 · 기간을 함께 적어주시면 더 빠르게 안내드려요.',
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: isDark
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.mail_outline_rounded,
                    size: 17,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(_email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(const ClipboardData(text: _email));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('이메일 주소를 복사했어요'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('주소 복사'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(
                        color: isDark
                            ? AppColors.darkCardBorder
                            : AppColors.lightCardBorder),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri(
                      scheme: 'mailto',
                      path: _email,
                      query: 'subject=${Uri.encodeComponent('[전기차 기름차] 광고 문의')}'
                          '&body=${Uri.encodeComponent('업종:\n희망 지면:\n희망 기간:\n연락처:\n')}',
                    );
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    } else if (context.mounted) {
                      await Clipboard.setData(
                          const ClipboardData(text: _email));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('메일 앱이 없어 주소를 복사했어요')),
                      );
                    }
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('메일 쓰기'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gasBlue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
