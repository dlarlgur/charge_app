import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 일반 텍스트 행 스타일 skeleton — 공지/이벤트/FAQ 리스트용.
/// 카드 형태가 필요한 곳은 [SkeletonCard] (in shared_widgets.dart) 사용.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1E2330) : const Color(0xFFE2E8F0);
    final hi = isDark ? const Color(0xFF2A3040) : const Color(0xFFF1F5F9);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 14,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 160,
                  height: 11,
                  decoration: BoxDecoration(
                    color: hi,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 56,
            height: 11,
            decoration: BoxDecoration(
              color: hi,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

/// SkeletonRow 들을 divider 와 함께 [rowCount] 개 보여주는 placeholder 리스트.
class SkeletonRowList extends StatelessWidget {
  final int rowCount;
  const SkeletonRowList({super.key, this.rowCount = 6});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: rowCount,
      physics: const NeverScrollableScrollPhysics(),
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 0.5,
        color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
      ),
      itemBuilder: (_, __) => const SkeletonRow(),
    );
  }
}
