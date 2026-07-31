import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../ai_constants.dart';

/// 경로 카드 — 출발지/경유지(최대 3)/목적지 표시 및 편집.
/// - 경유지 없음: 출발/목적 2행 + 디바이더 오른쪽 ⊕(경유지 추가) + ↕(출발↔목적 스왑)
/// - 경유지 있음: (2+n)행 드래그(⇅ 핸들)로 순서 변경 (네이버지도 스타일),
///   경유 행은 ⊖ 로 제거, 목적지 행 오른쪽 ⊕ 로 추가 (3개까지)
class RouteCard extends StatelessWidget {
  final String? originName;
  final String? destName;
  final List<String> viaNames; // 경유지 이름들 (0~3)
  final String? currentLocationAddress;
  final VoidCallback onTapOrigin;
  final VoidCallback onTapDest;
  final void Function(int index)? onTapVia; // 경유 행 탭 → 변경
  final VoidCallback onClearOrigin;
  final VoidCallback onClearDest;
  final void Function(int index)? onClearVia;
  final VoidCallback? onAddVia; // ⊕ 경유지 추가
  final VoidCallback? onSwap; // 출발↔목적지 위치 바꾸기 (2행 모드)
  /// 드래그 순서 변경 — 행 인덱스 (0=출발, 1..n=경유, n+1=목적)
  final void Function(int oldIndex, int newIndex)? onReorder;

  const RouteCard({
    super.key,
    required this.originName,
    required this.destName,
    required this.currentLocationAddress,
    required this.onTapOrigin,
    required this.onTapDest,
    required this.onClearOrigin,
    required this.onClearDest,
    this.viaNames = const [],
    this.onTapVia,
    this.onClearVia,
    this.onAddVia,
    this.onSwap,
    this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg =
        isDark ? AppColors.darkMapOverlay : Colors.white; // 지도 위 → 불투명

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
      child: viaNames.isEmpty ? _twoRows(isDark) : _multiRows(isDark),
    );
  }

  // ── 색상 헬퍼 ──
  Color _primaryText(bool d) =>
      d ? AppColors.darkTextPrimary : const Color(0xFF1a1a1a);
  Color _secondaryText(bool d) =>
      d ? AppColors.darkTextSecondary : const Color(0xFF444444);
  Color _mutedText(bool d) =>
      d ? AppColors.darkTextMuted : const Color(0xFF888888);
  Color _placeholder(bool d) =>
      d ? AppColors.darkTextMuted : const Color(0xFFBBBBBB);
  Color _icon(bool d) => d ? AppColors.darkTextMuted : const Color(0xFFCCCCCC);
  Color _line(bool d) => d ? AppColors.darkCardBorder : const Color(0xFFF0F0F0);

  Widget _originDot() => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: kPrimary, width: 2.5),
        ),
      );

  Widget _destDot() => Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: kDanger));

  /// 경유지 도트 — 회색 채움 원 + 흰 번호 (지도 마커와 동일 디자인, 네이버식)
  Widget _viaDot(bool isDark, int n) => Container(
        width: 15,
        height: 15,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF8B95A1),
        ),
        child: Text('$n',
            style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                height: 1,
                color: Colors.white)),
      );

  Widget _originText(bool isDark) {
    final usingGps = originName == null;
    final label = originName ?? currentLocationAddress ?? '현재 위치';
    return Text(
      label,
      style: TextStyle(
        fontSize: 14,
        color: usingGps
            ? (currentLocationAddress != null
                ? _secondaryText(isDark)
                : _mutedText(isDark))
            : _primaryText(isDark),
        fontWeight: usingGps ? FontWeight.w400 : FontWeight.w500,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _destText(bool isDark) => Text(
        destName ?? '목적지를 입력하세요',
        style: TextStyle(
          fontSize: 14,
          color: destName != null ? _primaryText(isDark) : _placeholder(isDark),
          fontWeight: destName != null ? FontWeight.w500 : FontWeight.w400,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  // ── 경유지 없음: 기존 2행 + ⊕ 오버레이 ──
  Widget _twoRows(bool isDark) {
    final usingGps = originName == null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 17),
            _originDot(),
            Container(width: 2, height: 35, color: _line(isDark)),
            _destDot(),
            const SizedBox(height: 17),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: onTapOrigin,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          Expanded(child: _originText(isDark)),
                          if (!usingGps)
                            GestureDetector(
                              onTap: onClearOrigin,
                              child: Icon(Icons.close_rounded,
                                  size: 14, color: _icon(isDark)),
                            )
                          else
                            Icon(Icons.edit_location_alt_outlined,
                                size: 14, color: _icon(isDark)),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: _line(isDark)),
                  GestureDetector(
                    onTap: onTapDest,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          Expanded(child: _destText(isDark)),
                          if (destName != null)
                            GestureDetector(
                              onTap: onClearDest,
                              child: Icon(Icons.close_rounded,
                                  size: 14, color: _icon(isDark)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // ⊕ 경유지 추가 — 디바이더 오른쪽 (네이버지도 스타일)
              if (onAddVia != null)
                Positioned(
                  right: 22,
                  top: 44 - 14,
                  child: _addButton(isDark),
                ),
            ],
          ),
        ),
        if (onSwap != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onSwap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.swap_vert_rounded,
                  size: 22, color: _mutedText(isDark)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _addButton(bool isDark) => GestureDetector(
        onTap: onAddVia,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkMapOverlay : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
                color: isDark
                    ? AppColors.darkCardBorder
                    : const Color(0xFFDDE2E8)),
          ),
          child: Icon(Icons.add_rounded, size: 17, color: _mutedText(isDark)),
        ),
      );

  // ── 경유지 있음: (2+n)행 드래그 정렬 ──
  Widget _multiRows(bool isDark) {
    final lastIndex = viaNames.length + 1;
    final rows = <Widget>[
      _slotRow(
        key: const ValueKey('slot_origin'),
        index: 0,
        isDark: isDark,
        dot: _originDot(),
        text: _originText(isDark),
        onTap: onTapOrigin,
        trailing: originName != null
            ? GestureDetector(
                onTap: onClearOrigin,
                child:
                    Icon(Icons.close_rounded, size: 14, color: _icon(isDark)))
            : Icon(Icons.edit_location_alt_outlined,
                size: 14, color: _icon(isDark)),
        showDivider: true,
      ),
      for (var i = 0; i < viaNames.length; i++)
        _slotRow(
          key: ValueKey('slot_via_$i'),
          index: i + 1,
          isDark: isDark,
          dot: _viaDot(isDark, i + 1),
          text: Text(
            viaNames[i].isEmpty ? '경유지 입력' : viaNames[i],
            style: TextStyle(
              fontSize: 14,
              color: viaNames[i].isEmpty
                  ? _placeholder(isDark)
                  : _primaryText(isDark),
              fontWeight:
                  viaNames[i].isEmpty ? FontWeight.w400 : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: onTapVia == null ? null : () => onTapVia!(i),
          trailing: GestureDetector(
            onTap: onClearVia == null ? null : () => onClearVia!(i),
            child: Icon(Icons.remove_circle_outline_rounded,
                size: 17, color: _mutedText(isDark)),
          ),
          showDivider: true,
        ),
      _slotRow(
        key: const ValueKey('slot_dest'),
        index: lastIndex,
        isDark: isDark,
        dot: _destDot(),
        text: _destText(isDark),
        onTap: onTapDest,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⊕ 추가 (3개 미만일 때) — 네이버처럼 목적지 행 오른쪽
            if (onAddVia != null && viaNames.length < 3) ...[
              _addButton(isDark),
              const SizedBox(width: 8),
            ],
            if (destName != null)
              GestureDetector(
                onTap: onClearDest,
                child:
                    Icon(Icons.close_rounded, size: 14, color: _icon(isDark)),
              ),
          ],
        ),
        showDivider: false,
      ),
    ];
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        if (oldIndex != newIndex) onReorder?.call(oldIndex, newIndex);
      },
      children: rows,
    );
  }

  Widget _slotRow({
    required Key key,
    required int index,
    required bool isDark,
    required Widget dot,
    required Widget text,
    required VoidCallback? onTap,
    required Widget? trailing,
    required bool showDivider,
  }) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: _line(isDark), width: 1))
            : null,
      ),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              // ⇅ 드래그 핸들 (꾹 안 눌러도 바로 드래그)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.unfold_more_rounded,
                      size: 16, color: _icon(isDark)),
                ),
              ),
              SizedBox(width: 18, child: Center(child: dot)),
              const SizedBox(width: 10),
              Expanded(child: text),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }
}
