import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../ai_constants.dart';
import 'select_badge.dart';

class StationSelectInlineSheet extends StatefulWidget {
  final ScrollController sheetScrollCtrl;
  final List<Map<String, dynamic>> stations;
  final String? selectedAId;
  final String? selectedBId;
  final NumberFormat wonFmt;
  final bool isComparing;
  final void Function(String stId) onStationTap;
  final VoidCallback onCompare;
  final VoidCallback onClose;
  final void Function(bool highwayOnly)? onHighwayFilterChanged;

  const StationSelectInlineSheet({
    super.key,
    required this.sheetScrollCtrl,
    required this.stations,
    required this.selectedAId,
    required this.selectedBId,
    required this.wonFmt,
    required this.isComparing,
    required this.onStationTap,
    required this.onCompare,
    required this.onClose,
    this.onHighwayFilterChanged,
  });

  @override
  State<StationSelectInlineSheet> createState() => _StationSelectInlineSheetState();
}

class _StationSelectInlineSheetState extends State<StationSelectInlineSheet> {
  final ScrollController _listCtrl = ScrollController();
  bool _highwayOnly = false;
  String _sortMode = 'price'; // 'price' 가격순(기본, 서버도 가격순) | 'distance' 거리순(덜 우회)

  int? _priceOf(Map<String, dynamic> s) =>
      s['price_won_per_liter'] is num ? (s['price_won_per_liter'] as num).round() : null;
  int? _distOf(Map<String, dynamic> s) =>
      s['detour_distance_m'] is num ? (s['detour_distance_m'] as num).round() : null;

  // 세그먼트 컨트롤 — 트랙 위에 흰(다크: 남색) 인디케이터가 슬라이드.
  Widget _sortToggle(bool isDark) {
    final track = isDark ? const Color(0x1FFFFFFF) : const Color(0xFFEDEFF3);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sortSeg('가격순', 'price', Icons.payments_rounded, isDark),
          _sortSeg('거리순', 'distance', Icons.near_me_rounded, isDark),
        ],
      ),
    );
  }

  Widget _sortSeg(String label, String mode, IconData icon, bool isDark) {
    final active = _sortMode == mode;
    final muted =
        isDark ? AppColors.darkTextMuted : const Color(0xFF8A94A6);
    return GestureDetector(
      onTap: active ? null : () => setState(() => _sortMode = mode),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? (isDark ? const Color(0xFF2B3757) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          boxShadow: active && !isDark
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 1)),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? kCompareBlue : muted),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.1,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active ? kCompareBlue : muted)),
          ],
        ),
      ),
    );
  }

  bool _isHighwayStation(Map<String, dynamic> st) {
    // 서버가 휴게소 여부·상하행 필터까지 반영한 목록만 내림 — 앱은 플래그만 사용
    return st['is_highway_rest_area'] == true;
  }

  @override
  void dispose() {
    _listCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stations = (_highwayOnly
        ? widget.stations.where((s) => _isHighwayStation(s)).toList()
        : [...widget.stations]);
    // 정렬 — 가격순(낮은가 우선) / 거리순(덜 우회 우선). 값 없으면 뒤로.
    if (_sortMode == 'distance') {
      stations.sort((a, b) => (_distOf(a) ?? 1 << 30).compareTo(_distOf(b) ?? 1 << 30));
    } else {
      stations.sort((a, b) => (_priceOf(a) ?? 1 << 30).compareTo(_priceOf(b) ?? 1 << 30));
    }
    final selectedAId = widget.selectedAId;
    final selectedBId = widget.selectedBId;
    final bothSelected = selectedAId != null && selectedBId != null;

    // 최저가 ID 찾기
    String? cheapestId;
    int? cheapestPrice;
    for (final st in stations) {
      final price = st['price_won_per_liter'] is num ? (st['price_won_per_liter'] as num).round() : null;
      if (price != null && (cheapestPrice == null || price < cheapestPrice)) {
        cheapestPrice = price;
        cheapestId = st['id']?.toString();
      }
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBg : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, -2)),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 시트를 최대로 내렸을 때는 고정 영역을 축약해서 overflow를 방지한다.
            final compact = constraints.maxHeight < 300;
            return Column(
          children: [
            // ─ 드래그 핸들 영역 (SingleChildScrollView로 드래그 활성화) ─
            SingleChildScrollView(
              controller: widget.sheetScrollCtrl,
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 핸들바
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // 헤더
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 12, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.local_gas_station_rounded, size: 18, color: kCompareBlue),
                        const SizedBox(width: 8),
                        Text('주유소 선택',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isDark ? AppColors.darkTextPrimary : const Color(0xFF1a1a1a),
                            )),
                        const SizedBox(width: 6),
                        Text('(${stations.length}곳)',
                            style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppColors.darkTextMuted : const Color(0xFF999999))),
                        const Spacer(),
                        GestureDetector(
                          onTap: widget.onClose,
                          child: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.close_rounded,
                                size: 17,
                                color: isDark ? AppColors.darkTextSecondary : const Color(0xFF666666)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 선택 안내
                  if (!bothSelected && !compact)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                      child: Row(
                        children: [
                          SelectBadge(label: selectedAId != null ? 'A 선택됨' : 'A 미선택',
                              color: const Color(0xFFE8700A), filled: selectedAId != null),
                          const SizedBox(width: 6),
                          SelectBadge(label: selectedBId != null ? 'B 선택됨' : 'B 미선택',
                              color: kCompareBlue, filled: selectedBId != null),
                          const Spacer(),
                          Text('지도에서도 선택 가능',
                              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  // 정렬 토글 — 가격순/거리순 (세그먼트 컨트롤)
                  if (!compact)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Row(
                        children: [
                          _sortToggle(isDark),
                          const Spacer(),
                          Text(
                              _sortMode == 'price'
                                  ? '저렴한 순'
                                  : '가까운 순',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? AppColors.darkTextMuted
                                      : const Color(0xFF9CA3AF))),
                        ],
                      ),
                    ),
                  // '고속도로만' 토글 제거 — AI 추천 단계에서 이미 highway_only 필터 적용된 결과가
                  // 들어오므로 직접선택 화면에서 다시 토글하는 건 중복 UI. 사용자 의도 그대로.
                  const Divider(height: 1),
                ],
              ),
            ),

            // ─ 주유소 목록 ─
            Expanded(
              child: stations.isEmpty
                  ? Center(
                      child: Text(
                        '고속도로 후보가 없습니다.\n필터를 해제해 전체 후보를 확인하세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppColors.darkTextMuted : const Color(0xFF999999),
                            height: 1.4),
                      ),
                    )
                  : ListView.builder(
                controller: _listCtrl,
                itemCount: stations.length,
                itemBuilder: (ctx, index) {
                  final st = stations[index];
                  final stId = st['id']?.toString() ?? '$index';
                  final name = (st['display_name']?.toString().trim().isNotEmpty == true)
                      ? st['display_name'].toString()
                      : (st['name']?.toString() ?? '주유소 ${index + 1}');
                  final addr = st['address']?.toString() ?? '';
                  final price = st['price_won_per_liter'] is num
                      ? (st['price_won_per_liter'] as num).round() : null;

                  final isA = selectedAId == stId;
                  final isB = selectedBId == stId;
                  final isCheapest = cheapestId == stId;

                  final badgeColor = isA
                      ? const Color(0xFFE8700A)
                      : (isB ? kCompareBlue : const Color(0xFF9E9E9E));

                  return InkWell(
                    onTap: () => widget.onStationTap(stId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          // 번호/선택 뱃지
                          Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                              color: (isA || isB) ? badgeColor : const Color(0xFFF0F0F0),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                isA ? 'A' : (isB ? 'B' : '${index + 1}'),
                                style: TextStyle(
                                  color: (isA || isB) ? Colors.white : const Color(0xFF666666),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(name,
                                          style: TextStyle(
                                            fontWeight: isCheapest ? FontWeight.w700 : FontWeight.w600,
                                            fontSize: 14,
                                            color: isDark ? AppColors.darkTextPrimary : const Color(0xFF1a1a1a),
                                          ),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    if (isCheapest) ...[
                                      const SizedBox(width: 5),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: kCompareBlue,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('최저가',
                                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                                      ),
                                    ],
                                  ],
                                ),
                                if (addr.isNotEmpty)
                                  Text(addr,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? AppColors.darkTextMuted : const Color(0xFF999999)),
                                      overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 가격
                          if (price != null)
                            Text(
                              '${widget.wonFmt.format(price)}원',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isCheapest ? FontWeight.w700 : FontWeight.w500,
                                color: isCheapest ? kCompareBlue : const Color(0xFFAAAAAA),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // ─ 비교 버튼 ─
            if (!compact)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: bothSelected && !widget.isComparing ? widget.onCompare : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kCompareBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: kCompareBlue.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: widget.isComparing
                          ? const SizedBox(height: 22, width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text(
                              bothSelected
                                  ? '선택한 2곳 비교 분석'
                                  : '주유소 2곳을 선택하세요 (${(selectedAId != null ? 1 : 0) + (selectedBId != null ? 1 : 0)}/2)',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        );
          },
        ),
      ),
    );
  }
}
