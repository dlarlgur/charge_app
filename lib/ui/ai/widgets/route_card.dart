import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../ai_constants.dart';

/// 경로 카드 — 출발지/목적지 표시 및 편집
class RouteCard extends StatelessWidget {
  final String? originName;
  final String? destName;
  final String? currentLocationAddress;
  final VoidCallback onTapOrigin;
  final VoidCallback onTapDest;
  final VoidCallback onClearOrigin;
  final VoidCallback onClearDest;
  final VoidCallback? onSwap; // 출발↔목적지 위치 바꾸기 (티맵 스타일 ↕)

  const RouteCard({
    super.key,
    required this.originName,
    required this.destName,
    required this.currentLocationAddress,
    required this.onTapOrigin,
    required this.onTapDest,
    required this.onClearOrigin,
    required this.onClearDest,
    this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final usingGps = originName == null;
    final originLabel = originName ?? currentLocationAddress ?? '현재 위치';

    final cardBg =
        isDark ? AppColors.darkMapOverlay : Colors.white; // 지도 위 → 불투명
    final dotLineColor =
        isDark ? AppColors.darkCardBorder : const Color(0xFFEEEEEE);
    final dividerColor =
        isDark ? AppColors.darkCardBorder : const Color(0xFFF0F0F0);
    final primaryText =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1a1a1a);
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF444444);
    final mutedText =
        isDark ? AppColors.darkTextMuted : const Color(0xFF888888);
    final placeholderText =
        isDark ? AppColors.darkTextMuted : const Color(0xFFBBBBBB);
    final iconColor =
        isDark ? AppColors.darkTextMuted : const Color(0xFFCCCCCC);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: isDark
            ? Border.all(color: AppColors.darkCardBorder, width: 0.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 도트 + 선 — 각 점이 해당 행 중앙에 정렬되도록 고정 높이
          // 각 행 44px + divider 1px = 89px 총
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 17), // 44/2 - 10/2
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: kPrimary, width: 2.5),
                ),
              ),
              Container(width: 2, height: 35, color: dotLineColor),
              Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: kDanger)),
              const SizedBox(height: 17), // 44/2 - 10/2
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 출발지
                GestureDetector(
                  onTap: onTapOrigin,
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            originLabel,
                            style: TextStyle(
                              fontSize: 14,
                              // GPS 모드: 주소가 있으면 진하게, 없으면 흐리게
                              color: usingGps
                                  ? (currentLocationAddress != null
                                      ? secondaryText
                                      : mutedText)
                                  : primaryText,
                              fontWeight:
                                  usingGps ? FontWeight.w400 : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!usingGps)
                          GestureDetector(
                            onTap: onClearOrigin,
                            child: Icon(Icons.close_rounded,
                                size: 14, color: iconColor),
                          )
                        else
                          Icon(Icons.edit_location_alt_outlined,
                              size: 14, color: iconColor),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, color: dividerColor),
                // 목적지
                GestureDetector(
                  onTap: onTapDest,
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            destName ?? '목적지를 입력하세요',
                            style: TextStyle(
                              fontSize: 14,
                              color: destName != null
                                  ? primaryText
                                  : placeholderText,
                              fontWeight: destName != null
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (destName != null)
                          GestureDetector(
                            onTap: onClearDest,
                            child: Icon(Icons.close_rounded,
                                size: 14, color: iconColor),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 출발↔목적지 위치 바꾸기 (티맵 스타일)
          if (onSwap != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onSwap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child:
                    Icon(Icons.swap_vert_rounded, size: 22, color: mutedText),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
