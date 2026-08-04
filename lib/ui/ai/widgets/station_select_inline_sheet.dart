import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../widgets/shared_widgets.dart';
import '../ai_constants.dart';

// A/B 선택 색 — 지도 마커와 동일하게 유지 (A=보라, B=파랑. 주황 폐기 — 6a 축).
const _kSelectA = Color(0xFF7B5EA7);
const _kSelectB = kCompareBlue;

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
  State<StationSelectInlineSheet> createState() =>
      _StationSelectInlineSheetState();
}

class _StationSelectInlineSheetState extends State<StationSelectInlineSheet> {
  final ScrollController _listCtrl = ScrollController();
  String _sortMode = 'price'; // 'price' 가격순(기본) | 'distance' 거리순(덜 우회)

  int? _priceOf(Map<String, dynamic> s) => s['price_won_per_liter'] is num
      ? (s['price_won_per_liter'] as num).round()
      : null;
  int? _distOf(Map<String, dynamic> s) => s['detour_distance_m'] is num
      ? (s['detour_distance_m'] as num).round()
      : null;

  /// 주소에서 '용인시 처인구' 같은 지역 두 토큰만 추출. 실패 시 원본 주소.
  String _regionOf(String addr) {
    final tokens = addr.split(RegExp(r'\s+'));
    final picked = <String>[];
    for (final t in tokens) {
      if (t.endsWith('시') || t.endsWith('군') || t.endsWith('구')) picked.add(t);
      if (picked.length == 2) break;
    }
    return picked.isNotEmpty ? picked.join(' ') : addr;
  }

  String _distText(int? m) {
    if (m == null) return '';
    if (m < 1000) return '${m}m';
    return '${(m / 1000).toStringAsFixed(1)}km';
  }

  @override
  void dispose() {
    _listCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stations = [...widget.stations];
    if (_sortMode == 'distance') {
      stations.sort(
          (a, b) => (_distOf(a) ?? 1 << 30).compareTo(_distOf(b) ?? 1 << 30));
    } else {
      stations.sort(
          (a, b) => (_priceOf(a) ?? 1 << 30).compareTo(_priceOf(b) ?? 1 << 30));
    }
    final selectedAId = widget.selectedAId;
    final selectedBId = widget.selectedBId;
    final bothSelected = selectedAId != null && selectedBId != null;

    // 최저가(기준가) + 게이지용 min/max
    String? cheapestId;
    int? minPrice;
    int? maxPrice;
    for (final st in stations) {
      final p = _priceOf(st);
      if (p == null) continue;
      if (minPrice == null || p < minPrice) {
        minPrice = p;
        cheapestId = st['id']?.toString();
      }
      if (maxPrice == null || p > maxPrice) maxPrice = p;
    }

    // CTA 라벨용 — 둘 다 선택 시 리터당 차이
    int? abDiff;
    if (bothSelected) {
      int? pa, pb;
      for (final st in stations) {
        final id = st['id']?.toString();
        if (id == selectedAId) pa = _priceOf(st);
        if (id == selectedBId) pb = _priceOf(st);
      }
      if (pa != null && pb != null) abDiff = (pa - pb).abs();
    }

    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A2E);
    final muted = isDark ? AppColors.darkTextMuted : const Color(0xFF9CA3AF);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBg : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, -2)),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 시트를 최대로 내렸을 때는 고정 영역을 축약해서 overflow를 방지한다.
            final compact = constraints.maxHeight < 300;
            return Column(
              children: [
                // ─ 드래그 핸들 + 헤더 (SingleChildScrollView로 시트 드래그 활성화) ─
                SingleChildScrollView(
                  controller: widget.sheetScrollCtrl,
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 4),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // 헤더: 제목 · N곳 · 정렬 드롭다운 · 닫기
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 6, 12, 8),
                        child: Row(
                          children: [
                            Text('주유소 선택',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                )),
                            const SizedBox(width: 7),
                            Text('${stations.length}곳',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: muted)),
                            const Spacer(),
                            _sortDropdown(isDark, muted, ink),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: widget.onClose,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0x14FFFFFF)
                                      : const Color(0xFFF5F5F5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close_rounded,
                                    size: 17,
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : const Color(0xFF666666)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 안내 배너
                      if (!compact)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: kCompareBlue.withValues(
                                  alpha: isDark ? 0.16 : 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.auto_awesome_rounded,
                                    size: 14, color: kCompareBlue),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text('두 곳을 선택하면 주유비 차이를 계산해드려요',
                                      style: TextStyle(
                                          fontSize: 12,
                                          height: 1.2,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? AppColors.darkTextSecondary
                                              : const Color(0xFF3D5A99))),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ─ 주유소 카드 목록 ─
                Expanded(
                  child: stations.isEmpty
                      ? Center(
                          child: Text(
                            '경로상 주유소가 없습니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13, color: muted, height: 1.4),
                          ),
                        )
                      : ListView.builder(
                          controller: _listCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                          itemCount: stations.length,
                          itemBuilder: (ctx, index) => _stationCard(
                            stations[index],
                            index: index,
                            isDark: isDark,
                            ink: ink,
                            muted: muted,
                            cheapestId: cheapestId,
                            minPrice: minPrice,
                            maxPrice: maxPrice,
                          ),
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
                          onPressed: bothSelected && !widget.isComparing
                              ? widget.onCompare
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kCompareBlue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                kCompareBlue.withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          child: widget.isComparing
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white))
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.compare_arrows_rounded,
                                        size: 19),
                                    const SizedBox(width: 7),
                                    Text(
                                      bothSelected
                                          ? (abDiff != null
                                              ? 'A·B 비교하기 · 리터당 ${abDiff == 0 ? '가격 동일' : '${widget.wonFmt.format(abDiff)}원 차이'}'
                                              : 'A·B 비교하기')
                                          : '주유소 2곳을 선택하세요 (${(selectedAId != null ? 1 : 0) + (selectedBId != null ? 1 : 0)}/2)',
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ],
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

  // 정렬 드롭다운 — '가격순 ▾' / '거리순 ▾'
  Widget _sortDropdown(bool isDark, Color muted, Color ink) {
    final label = _sortMode == 'price' ? '가격순' : '거리순';
    return PopupMenuButton<String>(
      onSelected: (v) => setState(() => _sortMode = v),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? AppColors.darkCard : Colors.white,
      itemBuilder: (_) => [
        _sortItem('price', '가격순 · 저렴한 곳부터', isDark, ink),
        _sortItem('distance', '거리순 · 가까운 곳부터', isDark, ink),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0x14FFFFFF) : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                _sortMode == 'price'
                    ? Icons.payments_rounded
                    : Icons.near_me_rounded,
                size: 14,
                color: kCompareBlue),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: ink)),
            Icon(Icons.arrow_drop_down_rounded, size: 20, color: muted),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _sortItem(
      String value, String label, bool isDark, Color ink) {
    final active = _sortMode == value;
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(active ? Icons.check_rounded : null,
              size: 16, color: kCompareBlue),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  color: active ? kCompareBlue : ink)),
        ],
      ),
    );
  }

  // 주유소 카드 — 로고 · 이름/지역/거리 · 가격 · A/B 칩 · 가격 게이지 + 기준가 대비 델타.
  Widget _stationCard(
    Map<String, dynamic> st, {
    required int index,
    required bool isDark,
    required Color ink,
    required Color muted,
    required String? cheapestId,
    required int? minPrice,
    required int? maxPrice,
  }) {
    final stId = st['id']?.toString() ?? '$index';
    final name = (st['display_name']?.toString().trim().isNotEmpty == true)
        ? st['display_name'].toString()
        : (st['name']?.toString() ?? '주유소 ${index + 1}');
    final addr = st['address']?.toString() ?? '';
    final brand = st['brand']?.toString() ?? '';
    final price = _priceOf(st);
    final dist = _distOf(st);

    final isA = widget.selectedAId == stId;
    final isB = widget.selectedBId == stId;
    final selected = isA || isB;
    final selColor = isA ? _kSelectA : _kSelectB;
    final isCheapest = cheapestId == stId;
    final delta = (price != null && minPrice != null) ? price - minPrice : null;

    // 게이지: 리스트 내 min~max 상대 위치 (min이어도 살짝 보이게)
    double gauge = 0.08;
    if (price != null &&
        minPrice != null &&
        maxPrice != null &&
        maxPrice > minPrice) {
      gauge = (0.08 + 0.92 * (price - minPrice) / (maxPrice - minPrice))
          .clamp(0.08, 1.0);
    }

    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final border = selected
        ? selColor
        : (isDark ? AppColors.darkCardBorder : const Color(0xFFE8EAEF));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => widget.onStationTap(stId),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: selected ? 1.6 : 1),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Colors.black
                            .withValues(alpha: selected ? 0.07 : 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  BrandLogo(brand: brand, stationName: name, size: 42),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    height: 1.2,
                                    color: ink,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (isCheapest) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: kCompareBlue,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Text('최저가',
                                    style: TextStyle(
                                        fontSize: 9.5,
                                        height: 1.1,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (addr.isNotEmpty) _regionOf(addr),
                            if (dist != null) _distText(dist),
                          ].join(' · '),
                          style: TextStyle(
                              fontSize: 11.5, height: 1.2, color: muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (price != null)
                    Text(widget.wonFmt.format(price),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          color: selected
                              ? selColor
                              : (isCheapest ? kCompareBlue : ink),
                        )),
                  const SizedBox(width: 10),
                  // A/B 선택 칩 — 선택 전엔 빈 체크박스 느낌.
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: selected ? selColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      border: selected
                          ? null
                          : Border.all(
                              color: isDark
                                  ? const Color(0x33FFFFFF)
                                  : const Color(0xFFD5D9E0),
                              width: 1.4),
                    ),
                    child: selected
                        ? Center(
                            child: Text(isA ? 'A' : 'B',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white)))
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 9),
              // 가격 게이지 + 기준가 대비 델타
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: SizedBox(
                        height: 5,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: gauge,
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected
                                  ? selColor
                                  : (isCheapest
                                      ? kCompareBlue.withValues(alpha: 0.75)
                                      : (isDark
                                          ? const Color(0x30FFFFFF)
                                          : const Color(0xFFD8DDE5))),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    delta == null
                        ? ''
                        : (delta == 0
                            ? '기준가'
                            : '+${widget.wonFmt.format(delta)}원'),
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: delta == 0 ? kCompareBlue : muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
