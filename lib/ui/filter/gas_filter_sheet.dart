import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

class GasFilterSheet extends ConsumerStatefulWidget {
  const GasFilterSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GasFilterSheet(),
    );
  }

  @override
  ConsumerState<GasFilterSheet> createState() => _GasFilterSheetState();
}

class _GasFilterSheetState extends ConsumerState<GasFilterSheet> {
  late GasFilterOptions _options;

  static const _allBrands = ['SKE', 'GSC', 'HDO', 'SOL', 'NHO', 'E1G', 'RTO', 'ETC'];

  static const _brandItems = [
    ('SKE', 'SK에너지'),
    ('GSC', 'GS칼텍스'),
    ('HDO', '현대오일뱅크'),
    ('SOL', 'S-OIL'),
    ('NHO', 'NH주유소'),
    ('E1G', 'E1에너지'),
    ('RTO', '알뜰주유소'),
    ('ETC', '기타'),
  ];

  static const _fuelItems = [
    ('B027', '휘발유'),
    ('B034', '고급휘발유'),
    ('D047', '경유'),
    ('K015', 'LPG'),
  ];

  @override
  void initState() {
    super.initState();
    _options = ref.read(gasFilterProvider);
  }

  void _toggleBrand(String brand) {
    setState(() {
      if (_options.brands.isEmpty) {
        final brands = _allBrands.where((b) => b != brand).toList();
        _options = _options.copyWith(brands: brands);
      } else {
        final brands = List<String>.from(_options.brands);
        if (brands.contains(brand)) {
          brands.remove(brand);
          _options = _options.copyWith(brands: brands.isEmpty ? [] : brands);
        } else {
          brands.add(brand);
          if (_allBrands.every((b) => brands.contains(b))) {
            _options = _options.copyWith(brands: []);
          } else {
            _options = _options.copyWith(brands: brands);
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.gasBlue;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : const Color(0xFFF9FAFB),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          const SizedBox(height: 10),
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
            child: Row(
              children: [
                Text('주유소 필터',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _options = const GasFilterOptions()),
                  style: TextButton.styleFrom(
                    foregroundColor: accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('초기화', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: isDark ? AppColors.darkCardBorder : const Color(0xFFEEEFF1)),
          // 내용
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 정렬 + 반경
                  _card(isDark, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('정렬', isDark),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _segBtn('가격순', _options.sort == 1, accent, isDark,
                            () => setState(() => _options = _options.copyWith(sort: 1))),
                          const SizedBox(width: 8),
                          _segBtn('거리순', _options.sort == 2, accent, isDark,
                            () => setState(() => _options = _options.copyWith(sort: 2))),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _sectionHeader('반경', isDark),
                      const SizedBox(height: 10),
                      Row(
                        children: [1000, 3000, 5000].map((r) {
                          final label = r >= 1000 ? '${r ~/ 1000}km' : '${r}m';
                          final selected = _options.radius == r;
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: r == 5000 ? 0 : 8),
                              child: GestureDetector(
                                onTap: () => setState(() => _options = _options.copyWith(radius: r)),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected ? accent : (isDark ? const Color(0x08FFFFFF) : const Color(0xFFF5F6F8)),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selected ? accent : (isDark ? AppColors.darkCardBorder : const Color(0xFFDEE1E6)),
                                      width: selected ? 0 : 0.8,
                                    ),
                                  ),
                                  child: Text(label, textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                      color: selected ? Colors.white
                                        : (isDark ? AppColors.darkTextSecondary : const Color(0xFF6C757D)))),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  )),
                  const SizedBox(height: 10),
                  // 유류 종류
                  _card(isDark, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('유류 종류', isDark),
                      const SizedBox(height: 12),
                      Row(
                        children: _fuelItems.map((item) {
                          final selected = _options.fuelTypes.contains(item.$1);
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: item.$1 == 'K015' ? 0 : 8),
                              child: GestureDetector(
                                onTap: () => setState(() =>
                                  _options = _options.copyWith(fuelTypes: [item.$1])),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected ? accent : (isDark ? const Color(0x08FFFFFF) : const Color(0xFFF5F6F8)),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selected ? accent : (isDark ? AppColors.darkCardBorder : const Color(0xFFDEE1E6)),
                                      width: selected ? 0 : 0.8,
                                    ),
                                  ),
                                  child: Text(item.$2, textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                      color: selected ? Colors.white
                                        : (isDark ? AppColors.darkTextSecondary : const Color(0xFF6C757D)))),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  )),
                  const SizedBox(height: 10),
                  // 브랜드
                  _card(isDark, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _sectionHeader('브랜드', isDark),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => setState(() => _options = _options.copyWith(brands: [])),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _options.brands.isEmpty ? accent.withOpacity(0.12) : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('전체',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                  color: _options.brands.isEmpty ? accent
                                    : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted))),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 7, runSpacing: 7,
                        children: _brandItems.map((item) {
                          final active = _options.brands.isEmpty || _options.brands.contains(item.$1);
                          final isEtc = item.$1 == 'ETC';
                          return GestureDetector(
                            onTap: () => _toggleBrand(item.$1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: active ? accent.withOpacity(0.1) : (isDark ? const Color(0x08FFFFFF) : const Color(0xFFF5F6F8)),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: active ? accent : (isDark ? AppColors.darkCardBorder : const Color(0xFFDEE1E6)),
                                  width: active ? 1.5 : 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isEtc) ...[
                                    Icon(Icons.more_horiz_rounded, size: 14,
                                      color: active ? accent : (isDark ? AppColors.darkTextMuted : const Color(0xFF6C757D))),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(item.$2,
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                                      color: active ? accent : (isDark ? AppColors.darkTextSecondary : const Color(0xFF6C757D)))),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  )),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          // 적용 버튼
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBg : const Color(0xFFF9FAFB),
              border: Border(top: BorderSide(color: isDark ? AppColors.darkCardBorder : const Color(0xFFEEEFF1))),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  ref.read(gasFilterProvider.notifier).update(_options);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('적용하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(bool isDark, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkCardBorder : const Color(0xFFE8EAED), width: 0.8),
      ),
      child: child,
    );
  }

  Widget _sectionHeader(String title, bool isDark) {
    return Text(title,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3,
        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted));
  }

  Widget _segBtn(String label, bool active, Color accent, bool isDark, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? accent : (isDark ? const Color(0x08FFFFFF) : const Color(0xFFF5F6F8)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? accent : (isDark ? AppColors.darkCardBorder : const Color(0xFFDEE1E6)),
              width: active ? 0 : 0.8,
            ),
          ),
          child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: active ? Colors.white : (isDark ? AppColors.darkTextSecondary : const Color(0xFF6C757D)))),
        ),
      ),
    );
  }
}
