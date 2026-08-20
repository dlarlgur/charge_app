import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../ai_constants.dart';

/// 결과 시트 상단 기준 카드 (형 시안 4a) — 이 추천의 '기준'을 한 덩어리로 모은다.
///
///   [링] 79 % 기준 · 주행 가능 약 475km        [tune]
///        탭해서 잔량 수정
///   ───────────────────────────────────────
///   ▽ 휘발유 · 도달 범위 내                    후보 27개
///   [경로 유형] 경로가 고속도로를 지나지 않아 일반 주유소에서 추천했어요
///
/// 잔량·조건·후보 수·기준 안내(경로 유형/선호 브랜드/충전 속도)가 추천 카드와
/// 잔량 편집 사이에 흩어져 있던 것을 전부 여기로 흡수했다. 주유 파랑 / 충전 초록.
class LevelBasisCard extends StatelessWidget {
  /// 현재 결과가 계산된 기준 잔량 %
  final double levelPercent;

  /// 1%당 주행가능 km (용량 × 효율 / 100)
  final double kmPerPercent;

  final bool isEv;

  /// 상단 행 탭 → 잔량 시트. null 이면 읽기 전용 표시.
  final VoidCallback? onEdit;

  /// 추천 조건 한 줄 (예: '급속만 · 도달 범위 내', '휘발유 · 도달 범위 내')
  final String? conditionLabel;

  /// 우측 정렬 보조 수치 (예: '후보 27개')
  final String? countLabel;

  /// 기준 안내 줄들 — 호출부가 만든 '칩 + 문장' 위젯을 그대로 카드 안에 담는다.
  /// (필터 끄고 재조회 같은 액션 버튼이 붙은 줄도 그대로 들어온다)
  final List<Widget> notes;

  const LevelBasisCard({
    super.key,
    required this.levelPercent,
    required this.kmPerPercent,
    this.isEv = false,
    this.onEdit,
    this.conditionLabel,
    this.countLabel,
    this.notes = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = modeAccent(isEv);
    final accentDeep = modeAccentDeep(isEv);
    final muted =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF6B7280);
    final km = (levelPercent * kmPerPercent).round();

    final hasCondition = (conditionLabel?.isNotEmpty ?? false) ||
        (countLabel?.isNotEmpty ?? false);
    final hasNotes = notes.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: accent.withValues(alpha: isDark ? 0.30 : 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 상단: 잔량 링 + 기준 % + 주행가능거리 + 수정 ──
          // 탭 영역은 이 행에만 건다 — 아래 안내 줄의 액션 버튼과 겹치지 않게.
          GestureDetector(
            onTap: onEdit,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: (levelPercent / 100).clamp(0.0, 1.0),
                        strokeWidth: 3.5,
                        color: accent,
                        backgroundColor: accent.withValues(alpha: 0.18),
                      ),
                      Icon(
                          isEv
                              ? Icons.bolt_rounded
                              : Icons.local_gas_station_rounded,
                          size: 16,
                          color: accentDeep),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('${levelPercent.round()}',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: accentDeep)),
                          Text(' % 기준',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: accentDeep)),
                          Flexible(
                            child: Text('  ·  주행 가능 약 ${km}km',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(fontSize: 12.5, color: muted)),
                          ),
                        ],
                      ),
                      if (onEdit != null) ...[
                        const SizedBox(height: 2),
                        Text('탭해서 ${isEv ? '배터리' : '잔량'} 수정',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: accent)),
                      ],
                    ],
                  ),
                ),
                if (onEdit != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color:
                              accent.withValues(alpha: isDark ? 0.30 : 0.22)),
                    ),
                    child: Icon(Icons.tune_rounded, size: 17, color: accent),
                  ),
                ],
              ],
            ),
          ),

          // ── 조건 줄 — 필터·범위 + 후보 수 ──
          if (hasCondition) ...[
            _divider(accent, isDark),
            Row(
              children: [
                // 아이콘은 모드 색 — 주유 파랑 / 충전 초록 (형 지시 2026-08-20)
                Icon(Icons.filter_alt_outlined, size: 14, color: accent),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(conditionLabel ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: muted)),
                ),
                if (countLabel?.isNotEmpty ?? false)
                  Text(countLabel!,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: accentDeep)),
              ],
            ),
          ],

          // ── 기준 안내 줄들 (경로 유형 / 선호 브랜드 / 충전 속도 …) ──
          if (hasNotes) ...[
            _divider(accent, isDark),
            for (int i = 0; i < notes.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              notes[i],
            ],
          ],
        ],
      ),
    );
  }

  Widget _divider(Color accent, bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Divider(
            height: 1,
            thickness: 1,
            color: accent.withValues(alpha: isDark ? 0.22 : 0.16)),
      );
}
