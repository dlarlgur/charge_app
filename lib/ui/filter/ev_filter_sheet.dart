import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

class EvFilterSheet extends ConsumerStatefulWidget {
  const EvFilterSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const EvFilterSheet(),
    );
  }

  @override
  ConsumerState<EvFilterSheet> createState() => _EvFilterSheetState();
}

class _EvFilterSheetState extends ConsumerState<EvFilterSheet> {
  late EvFilterOptions _options;

  // 환경부 API chgerType 코드 (실제 사용)
  // 01=DC차데모, 02=AC완속, 03=DC차데모+AC3상, 04=DC콤보, 05=DC차데모+DC콤보
  // 06=DC차데모+AC3상+DC콤보, 07=AC3상, 08=DC콤보(저속), 09=NACS, 89=H2(수소)
  static const _allChargerTypes = ['02', '07', '04', '01', '09', 'SC', 'DT'];

  static const _connectorTypes = [
    ('02', 'AC완속',    'assets/connectors/ac_slow.svg'),
    ('07', 'AC3상',     'assets/connectors/ac_3phase.svg'),
    ('04', 'DC콤보',    'assets/connectors/dc_combo.svg'),
    ('01', 'DC차데모',  'assets/connectors/dc_chademo.svg'),
    ('09', 'NACS',      'assets/connectors/nacs.svg'),
    ('SC', '슈퍼차저',  'assets/connectors/supercharger.svg'),
    ('DT', '데스티네이션', 'assets/connectors/destination.svg'),
  ];

  // 주요 업체 목록 (기타 = 이 목록 외)
  static const _mainOperators = ['환경부', 'GS차지비', '파워큐브', '에버온', 'SK일렉링크', '채비', 'Tesla'];

  @override
  void initState() {
    super.initState();
    _options = ref.read(evFilterProvider);
  }

  bool get _otherSelected => _options.operators.contains('__other__');

  void _toggleType(String type) {
    setState(() {
      final types = List<String>.from(_options.chargerTypes);
      if (types.isEmpty) {
        // 전체 선택 상태 → 해당 타입만 해제 (나머지 유지)
        _options = _options.copyWith(
            chargerTypes: _allChargerTypes.where((t) => t != type).toList());
      } else if (types.contains(type)) {
        // 이미 선택됨 → 해제 (비면 전체로)
        types.remove(type);
        _options = _options.copyWith(chargerTypes: types);
      } else {
        // 미선택 → 추가 (전부 선택되면 전체로)
        types.add(type);
        if (_allChargerTypes.every((t) => types.contains(t))) {
          _options = _options.copyWith(chargerTypes: []);
        } else {
          _options = _options.copyWith(chargerTypes: types);
        }
      }
    });
  }

  void _toggleOp(String op) {
    setState(() {
      final ops = List<String>.from(_options.operators);
      if (ops.isEmpty) {
        // 전체 선택 상태 → 해당 운영기관만 해제 (나머지 유지)
        final allKeys = [..._mainOperators, '__other__'];
        _options = _options.copyWith(
            operators: allKeys.where((o) => o != op).toList());
      } else if (ops.contains(op)) {
        // 이미 선택됨 → 해제 (비면 전체로)
        ops.remove(op);
        _options = _options.copyWith(operators: ops);
      } else {
        // 미선택 → 추가 (전부 선택되면 전체로)
        ops.add(op);
        final allKeys = [..._mainOperators, '__other__'];
        if (allKeys.every((o) => ops.contains(o))) {
          _options = _options.copyWith(operators: []);
        } else {
          _options = _options.copyWith(operators: ops);
        }
      }
    });
  }

  static const _kindGroups = {
    '공공기관': ['A0', 'G0'],
    '공영주차': ['B0'],
    '숙박시설': ['H0'],
    '아파트': ['J0'],
    '일반충전소': ['D0', 'E0', 'F0', 'I0'],
    '고속도로': ['C0'],
  };

  static const _allKindCodes = ['A0', 'G0', 'B0', 'H0', 'J0', 'D0', 'E0', 'F0', 'I0', 'C0'];

  bool _kindActive(List<String> codes) {
    if (_options.kinds.isEmpty) return true;
    return codes.any((c) => _options.kinds.contains(c));
  }

  void _toggleKind(List<String> codes) {
    setState(() {
      final kinds = List<String>.from(_options.kinds);
      final allSel = codes.every((c) => kinds.contains(c));
      if (kinds.isEmpty) {
        // 전체 선택 상태 → 해당 장소만 해제 (나머지 유지)
        _options = _options.copyWith(
            kinds: _allKindCodes.where((c) => !codes.contains(c)).toList());
      } else if (allSel) {
        // 이미 선택됨 → 해제 (비면 전체로)
        for (final c in codes) kinds.remove(c);
        _options = _options.copyWith(kinds: kinds);
      } else {
        // 미선택 → 추가 (전부 선택되면 전체로)
        for (final c in codes) {
          if (!kinds.contains(c)) kinds.add(c);
        }
        if (_allKindCodes.every((c) => kinds.contains(c))) {
          _options = _options.copyWith(kinds: []);
        } else {
          _options = _options.copyWith(kinds: kinds);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.evGreen;

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
                Text('충전소 필터',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _options = const EvFilterOptions()),
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
                  _card(isDark, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('정렬', isDark),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _segBtn('거리순', _options.sort == 1, accent, isDark,
                            () => setState(() => _options = _options.copyWith(sort: 1))),
                          const SizedBox(width: 8),
                          _segBtn('비회원가격', _options.sort == 2, accent, isDark,
                            () => setState(() => _options = _options.copyWith(sort: 2))),
                          const SizedBox(width: 8),
                          _segBtn('회원가격', _options.sort == 3, accent, isDark,
                            () => setState(() => _options = _options.copyWith(sort: 3))),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _sectionHeader('반경', isDark),
                      const SizedBox(height: 10),
                      Row(
                        children: [3000, 5000, 10000, 20000].map((r) {
                          final label = r >= 1000 ? '${r ~/ 1000}km' : '${r}m';
                          final selected = _options.radius == r;
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: r == 20000 ? 0 : 8),
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
                      const SizedBox(height: 14),
                      _sectionHeader('이용 가능', isDark),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _segBtn('전체', !_options.availableOnly, accent, isDark,
                            () => setState(() => _options = _options.copyWith(availableOnly: false))),
                          const SizedBox(width: 8),
                          _segBtn('가능한 곳만', _options.availableOnly, accent, isDark,
                            () => setState(() => _options = _options.copyWith(availableOnly: true))),
                        ],
                      ),
                    ],
                  )),
                  const SizedBox(height: 10),
                  _card(isDark, child: _connectorSection(isDark, accent)),
                  const SizedBox(height: 10),
                  _card(isDark, child: _operatorSection(isDark, accent)),
                  const SizedBox(height: 10),
                  _card(isDark, child: _kindSection(isDark, accent)),
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
                  ref.read(evFilterProvider.notifier).update(_options);
                  ref.invalidate(evStationsProvider);
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

  Widget _connectorSection(bool isDark, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionHeader('커넥터', isDark),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() => _options = _options.copyWith(chargerTypes: [])),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _options.chargerTypes.isEmpty ? accent.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('전체',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: _options.chargerTypes.isEmpty ? accent
                      : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 8,
          children: _connectorTypes.map((e) {
            final active = _options.chargerTypes.isEmpty || _options.chargerTypes.contains(e.$1);
            return GestureDetector(
              onTap: () => _toggleType(e.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 70,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? accent.withOpacity(0.1) : (isDark ? const Color(0x08FFFFFF) : const Color(0xFFF5F6F8)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active ? accent : (isDark ? AppColors.darkCardBorder : const Color(0xFFDEE1E6)),
                    width: active ? 1.5 : 0.8,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(e.$3, width: 30, height: 30,
                      colorFilter: ColorFilter.mode(
                        active ? accent : (isDark ? AppColors.darkTextMuted : const Color(0xFFADB5BD)),
                        BlendMode.srcIn)),
                    const SizedBox(height: 6),
                    Text(e.$2, textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, height: 1.2,
                        color: active ? accent : (isDark ? AppColors.darkTextSecondary : const Color(0xFF6C757D)))),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _operatorSection(bool isDark, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionHeader('운영기관', isDark),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() => _options = _options.copyWith(operators: [])),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _options.operators.isEmpty ? accent.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('전체',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: _options.operators.isEmpty ? accent
                      : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            ..._mainOperators.map((op) {
              final active = _options.operators.isEmpty || _options.operators.contains(op);
              return _opChip(op, active, isDark, accent, () => _toggleOp(op), isTesla: op == 'Tesla');
            }),
            _opChip('기타', _options.operators.isEmpty || _otherSelected, isDark, accent,
              () => _toggleOp('__other__'), isOther: true),
          ],
        ),
      ],
    );
  }

  Widget _opChip(String label, bool active, bool isDark, Color accent, VoidCallback onTap,
      {bool isOther = false, bool isTesla = false}) {
    final chipColor = accent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? chipColor.withOpacity(0.1) : (isDark ? const Color(0x08FFFFFF) : const Color(0xFFF5F6F8)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? chipColor : (isDark ? AppColors.darkCardBorder : const Color(0xFFDEE1E6)),
            width: active ? 1.5 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOther) ...[
              Icon(Icons.more_horiz_rounded, size: 14,
                color: active ? accent : (isDark ? AppColors.darkTextMuted : const Color(0xFF6C757D))),
              const SizedBox(width: 4),
            ],
            if (isTesla) ...[
              Text('T', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                color: active ? accent : (isDark ? AppColors.darkTextMuted : const Color(0xFF6C757D)),
                fontStyle: FontStyle.italic)),
              const SizedBox(width: 4),
            ],
            Text(label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                color: active ? chipColor : (isDark ? AppColors.darkTextSecondary : const Color(0xFF6C757D)))),
          ],
        ),
      ),
    );
  }

  Widget _kindSection(bool isDark, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionHeader('충전 장소', isDark),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() => _options = _options.copyWith(kinds: [])),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _options.kinds.isEmpty ? accent.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('전체',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: _options.kinds.isEmpty ? accent
                      : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _kindRow('일반', ['공공기관', '공영주차', '숙박시설', '아파트', '일반충전소'], isDark, accent),
        const SizedBox(height: 8),
        _kindRow('고속', ['고속도로'], isDark, accent),
      ],
    );
  }

  Widget _kindRow(String label, List<String> keys, bool isDark, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          margin: const EdgeInsets.only(top: 7),
          child: Text(label,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextMuted : const Color(0xFF9EA7B2))),
        ),
        Expanded(
          child: Wrap(
            spacing: 6, runSpacing: 6,
            children: keys.map((key) {
              final codes = _kindGroups[key]!;
              final active = _kindActive(codes);
              return GestureDetector(
                onTap: () => _toggleKind(codes),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: active ? accent.withOpacity(0.1) : (isDark ? const Color(0x08FFFFFF) : const Color(0xFFF5F6F8)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: active ? accent : (isDark ? AppColors.darkCardBorder : const Color(0xFFDEE1E6)),
                      width: active ? 1.5 : 0.8,
                    ),
                  ),
                  child: Text(key,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                      color: active ? accent : (isDark ? AppColors.darkTextSecondary : const Color(0xFF6C757D)))),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
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
