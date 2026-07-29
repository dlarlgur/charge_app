import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import '../ai/widgets/ev_operator_picker.dart';

class EvFilterSheet extends ConsumerStatefulWidget {
  /// 홈 목록 화면은 검색 반경을 직접 지정해야 가까운 충전소 위주로 좁혀볼 수 있음.
  /// 지도 화면은 뷰포트(확대/축소 영역) 기준이라 반경 옵션 불필요.
  final bool showRadius;
  const EvFilterSheet({super.key, this.showRadius = false});

  static Future<void> show(BuildContext context, {bool showRadius = false}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EvFilterSheet(showRadius: showRadius),
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

  @override
  void initState() {
    super.initState();
    _options = ref.read(evFilterProvider);
    // 구버전 '__other__'(=대표 외 전체) 토큰은 새 canonical 필터로 이관 불가 → 전체로 리셋.
    if (_options.operators.contains('__other__')) {
      _options = _options.copyWith(operators: const []);
    }
  }

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

  Future<void> _openOperatorPicker() async {
    final result = await showEvOperatorPicker(
      context,
      initial: _options.operators.toSet(),
      // 지도·홈은 Tesla 도 노출되므로 대표 칩에 Tesla 주입(/operators엔 없음).
      extraReps: [
        {'name': 'Tesla', 'count': 0}
      ],
    );
    if (result == null) return; // 취소
    setState(() => _options = _options.copyWith(operators: result.toList()));
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

  // 충전 속도 kW 구간 — Charger.speedBucket 과 동일 정의 (빈 리스트=전체)
  static const _allSpeeds = ['slow', '50', '100', '200', '300'];
  static const _speedChips = [
    ('slow', '완속'),
    ('50', '50kW'),
    ('100', '100kW'),
    ('200', '200kW'),
    ('300', '300kW+'),
  ];

  void _toggleSpeed(String speed) {
    setState(() {
      final speeds = List<String>.from(_options.speeds);
      if (speeds.isEmpty) {
        // 전체 선택 상태 → 해당 구간만 해제 (나머지 유지)
        _options = _options.copyWith(
            speeds: _allSpeeds.where((s) => s != speed).toList());
      } else if (speeds.contains(speed)) {
        // 이미 선택됨 → 해제 (비면 전체로)
        speeds.remove(speed);
        _options = _options.copyWith(speeds: speeds);
      } else {
        // 미선택 → 추가 (전부 선택되면 전체로)
        speeds.add(speed);
        if (_allSpeeds.every((s) => speeds.contains(s))) {
          _options = _options.copyWith(speeds: []);
        } else {
          _options = _options.copyWith(speeds: speeds);
        }
      }
    });
  }

  // 이용 구분: 'open'=완전개방, 'partial'=부분개방, 'restricted'=이용제한 (빈 리스트=전체)
  static const _allAccessLevels = ['open', 'partial', 'restricted'];

  void _toggleAccess(String level) {
    setState(() {
      final levels = List<String>.from(_options.accessLevels);
      if (levels.isEmpty) {
        // 전체 선택 상태 → 해당 항목만 해제 (나머지 유지)
        _options = _options.copyWith(
            accessLevels: _allAccessLevels.where((l) => l != level).toList());
      } else if (levels.contains(level)) {
        // 이미 선택됨 → 해제 (비면 전체로)
        levels.remove(level);
        _options = _options.copyWith(accessLevels: levels);
      } else {
        // 미선택 → 추가 (전부 선택되면 전체로)
        levels.add(level);
        if (_allAccessLevels.every((l) => levels.contains(l))) {
          _options = _options.copyWith(accessLevels: []);
        } else {
          _options = _options.copyWith(accessLevels: levels);
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
          // 홈·지도 공유 안내
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                const SizedBox(width: 5),
                Text('홈과 지도 필터는 함께 적용됩니다',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
              ],
            ),
          ),
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
                      if (widget.showRadius) ...[
                        const SizedBox(height: 14),
                        _sectionHeader('반경', isDark),
                        const SizedBox(height: 10),
                        Row(
                          children: [3000, 5000, 10000, 20000, 30000].map((r) {
                            final label = r >= 1000 ? '${r ~/ 1000}km' : '${r}m';
                            final selected = _options.radius == r;
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(right: r == 30000 ? 0 : 6),
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
                      const SizedBox(height: 14),
                      _accessSection(isDark, accent),
                    ],
                  )),
                  const SizedBox(height: 10),
                  _card(isDark, child: _connectorSection(isDark, accent)),
                  const SizedBox(height: 10),
                  _card(isDark, child: _speedSection(isDark, accent)),
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
                  color: _options.chargerTypes.isEmpty ? accent.withValues(alpha: 0.12) : Colors.transparent,
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
                  color: active ? accent.withValues(alpha: 0.1) : (isDark ? const Color(0x08FFFFFF) : const Color(0xFFF5F6F8)),
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

  // 충전 속도 — 커넥터와 동일 문법의 다중선택 칩 (빈 선택=전체).
  // 완속(~7kW)부터 초급속(300kW+)까지 kW 구간 그대로 노출 — 800V 차주가
  // 200kW+ 만 골라 보는 니즈를 받는다.
  Widget _speedSection(bool isDark, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionHeader('충전 속도', isDark),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() => _options = _options.copyWith(speeds: [])),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _options.speeds.isEmpty ? accent.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('전체',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: _options.speeds.isEmpty ? accent
                      : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: _speedChips.map((e) {
            final active = _options.speeds.isEmpty || _options.speeds.contains(e.$1);
            final isLast = e.$1 == _speedChips.last.$1;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: isLast ? 0 : 7),
                child: GestureDetector(
                  onTap: () => _toggleSpeed(e.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? accent.withValues(alpha: 0.1) : (isDark ? const Color(0x08FFFFFF) : const Color(0xFFF5F6F8)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: active ? accent : (isDark ? AppColors.darkCardBorder : const Color(0xFFDEE1E6)),
                        width: active ? 1.5 : 0.8,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          e.$1 == 'slow' ? Icons.electrical_services_rounded : Icons.bolt_rounded,
                          size: 17,
                          color: active ? accent : (isDark ? AppColors.darkTextMuted : const Color(0xFFADB5BD))),
                        const SizedBox(height: 4),
                        Text(e.$2, textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, height: 1.2,
                            color: active ? accent : (isDark ? AppColors.darkTextSecondary : const Color(0xFF6C757D)))),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _operatorSection(bool isDark, Color accent) {
    final ops = _options.operators;
    final isAll = ops.isEmpty;
    final summary = isAll
        ? '전체 사업자'
        : (ops.length <= 2
            ? ops.join(', ')
            : '${ops.take(2).join(', ')} 외 ${ops.length - 2}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('운영기관', isDark),
        const SizedBox(height: 10),
        // 탭하면 공용 사업자 선택 시트(대표+ㄱㄴㄷ 전체+검색). AI 추천과 동일.
        GestureDetector(
          onTap: _openOperatorPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isAll
                  ? (isDark ? const Color(0x08FFFFFF) : const Color(0xFFF5F6F8))
                  : accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isAll
                    ? (isDark ? AppColors.darkCardBorder : const Color(0xFFDEE1E6))
                    : accent,
                width: isAll ? 0.8 : 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.ev_station_rounded,
                    size: 18,
                    color: isAll
                        ? (isDark ? AppColors.darkTextMuted : const Color(0xFF6C757D))
                        : accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: isAll
                              ? (isDark
                                  ? AppColors.darkTextSecondary
                                  : const Color(0xFF374151))
                              : accent)),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : const Color(0xFF9CA3AF)),
              ],
            ),
          ),
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
          color: active ? chipColor.withValues(alpha: 0.1) : (isDark ? const Color(0x08FFFFFF) : const Color(0xFFF5F6F8)),
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

  Widget _accessSection(bool isDark, Color accent) {
    const levels = [('open', '완전개방'), ('partial', '부분개방'), ('restricted', '이용제한')];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionHeader('이용 구분', isDark),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() => _options = _options.copyWith(accessLevels: [])),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _options.accessLevels.isEmpty ? accent.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('전체',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: _options.accessLevels.isEmpty ? accent
                      : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: levels.map((e) {
            final active = _options.accessLevels.isEmpty || _options.accessLevels.contains(e.$1);
            return _opChip(e.$2, active, isDark, accent, () => _toggleAccess(e.$1));
          }).toList(),
        ),
      ],
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
                  color: _options.kinds.isEmpty ? accent.withValues(alpha: 0.12) : Colors.transparent,
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
                    color: active ? accent.withValues(alpha: 0.1) : (isDark ? const Color(0x08FFFFFF) : const Color(0xFFF5F6F8)),
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
