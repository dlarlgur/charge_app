import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/util/app_toast.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import '../../data/services/user_sync_service.dart';

// 앱 컨벤션과 정합 — 내연기관(gas)은 파랑, 전기차(ev)는 초록.
// ai_main_screen 의 _kFuelAccent(#3B82F6) / _kEvAccent(#10B981) 와 동일.
const _kGasBlue = AppColors.gasBlue;
const _kEvGreen = AppColors.evGreen;

// 테마-aware light 배경 helper (이전 const _kGasBlueLight / _kEvGreenLight 대체)
Color _gasActiveBg(bool isDark) =>
    isDark ? AppColors.darkGasActiveCard : AppColors.lightGasActiveCard;
Color _evActiveBg(bool isDark) =>
    isDark ? AppColors.darkEvActiveCard : AppColors.lightEvActiveCard;

// ─── 차량 설정 화면 ────────────────────────────────────────────────────────────
class AiVehicleSetupScreen extends ConsumerStatefulWidget {
  /// null 이면 신규 등록, 값이 있으면 해당 ID 수정
  final String? editVehicleId;

  /// 신규 등록 시 초기 차종 ('gas' | 'ev'). 충전분석에서 진입하면 'ev' 로 시작.
  final String? initialType;

  const AiVehicleSetupScreen({super.key, this.editVehicleId, this.initialType});

  bool get isEdit => editVehicleId != null;

  @override
  ConsumerState<AiVehicleSetupScreen> createState() =>
      _AiVehicleSetupScreenState();
}

class _AiVehicleSetupScreenState extends ConsumerState<AiVehicleSetupScreen>
    with SingleTickerProviderStateMixin {
  // 차량 타입
  String _vehicleType = 'gas'; // 'gas' | 'ev'

  // 내연기관 필드
  FuelType _fuelType = FuelType.gasoline;
  final _tankController = TextEditingController();
  final _effController = TextEditingController();
  String _targetMode = 'FULL';
  final _priceController = TextEditingController(text: '50000');
  final _literController = TextEditingController(text: '20');

  // 전기차 필드
  final _batteryController = TextEditingController();
  final _evEffController = TextEditingController();
  double _targetChargePercent = 80.0;

  // 공통
  final _nameController = TextEditingController();
  double _currentLevelPercent = 25.0;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    _animCtrl.forward();
    _loadSaved();
  }

  void _loadSaved() {
    final box = Hive.box(AppConstants.settingsBox);
    final vehicles = _parseVehicles(box);

    if (widget.isEdit) {
      final v = vehicles.firstWhere(
        (v) => v.id == widget.editVehicleId,
        orElse: () => _defaultGasVehicle(),
      );
      _applyVehicle(v);
    } else {
      // 신규 — 진입 컨텍스트의 차종으로 시작 (충전분석 → 'ev')
      if (widget.initialType == 'ev' || widget.initialType == 'gas') {
        _vehicleType = widget.initialType!;
      }
      // 기본값 세팅
      _tankController.text = '55';
      _effController.text = '12.5';
      _batteryController.text = '64';
      _evEffController.text = '5.0';
    }
  }

  void _applyVehicle(VehicleProfile v) {
    _nameController.text = v.name;
    _vehicleType = v.vehicleType;
    _currentLevelPercent = v.currentLevelPercent;

    if (v.isGas) {
      _fuelType = FuelType.fromCode(v.fuelType);
      _tankController.text = _fmtNum(v.tankCapacity);
      _effController.text = _fmtNum(v.efficiency);
      _targetMode = v.targetMode;
      _priceController.text = v.targetValue.toStringAsFixed(0);
      _literController.text = _fmtNum(v.targetValue);
    } else {
      _batteryController.text = _fmtNum(v.batteryCapacity);
      _evEffController.text = _fmtNum(v.evEfficiency);
      _targetChargePercent = v.targetChargePercent;
    }
  }

  String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  VehicleProfile _defaultGasVehicle() => VehicleProfile(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        vehicleType: 'gas',
      );

  List<VehicleProfile> _parseVehicles(Box box) {
    final raw = box.get(AppConstants.keyAiVehicles);
    if (raw == null) return [];
    try {
      final List decoded = jsonDecode(raw as String);
      return decoded
          .map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _nameController.dispose();
    _tankController.dispose();
    _effController.dispose();
    _priceController.dispose();
    _literController.dispose();
    _batteryController.dispose();
    _evEffController.dispose();
    super.dispose();
  }

  double get _gasGoalLiters {
    final tank = double.tryParse(_tankController.text.replaceAll(',', '.')) ?? 55.0;
    if (_targetMode == 'FULL') return tank * (1 - _currentLevelPercent / 100);
    if (_targetMode == 'LITER') {
      return double.tryParse(_literController.text.replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  // 이름 미입력 시 자동생성 — 예: 내연기관차1, 전기차2
  String _resolvedName(String vehicleType) {
    final input = _nameController.text.trim();
    if (input.isNotEmpty) return input;
    final box = Hive.box(AppConstants.settingsBox);
    final vehicles = _parseVehicles(box);
    final prefix = vehicleType == 'ev' ? '전기차' : '내연기관차';
    final existing = vehicles
        .where((v) => v.vehicleType == vehicleType && v.name.startsWith(prefix))
        .length;
    return '$prefix${existing + 1}';
  }

  void _save() {
    if (_vehicleType == 'gas') {
      _saveGas();
    } else {
      _saveEv();
    }
  }

  void _saveGas() {
    final tank = double.tryParse(_tankController.text.replaceAll(',', '.'));
    final eff = double.tryParse(_effController.text.replaceAll(',', '.'));
    if (tank == null || tank <= 0) {
      _showError('탱크 용량을 올바르게 입력해주세요.');
      return;
    }
    if (eff == null || eff <= 0) {
      _showError('평균 연비를 올바르게 입력해주세요.');
      return;
    }
    if (_targetMode == 'PRICE') {
      final p = double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0;
      if (p <= 0) {
        _showError('목표 금액을 올바르게 입력해주세요.');
        return;
      }
    }
    if (_targetMode == 'LITER') {
      final l = double.tryParse(_literController.text.replaceAll(',', '.')) ?? 0;
      if (l <= 0) {
        _showError('목표 리터를 올바르게 입력해주세요.');
        return;
      }
    }

    final targetVal = _targetMode == 'PRICE'
        ? double.parse(_priceController.text.replaceAll(',', '.'))
        : _targetMode == 'LITER'
            ? double.parse(_literController.text.replaceAll(',', '.'))
            : 0.0;

    final v = VehicleProfile(
      id: widget.editVehicleId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _resolvedName('gas'),
      vehicleType: 'gas',
      fuelType: _fuelType.code,
      tankCapacity: tank,
      efficiency: eff,
      currentLevelPercent: _currentLevelPercent,
      targetMode: _targetMode,
      targetValue: targetVal,
    );
    _commit(v);
  }

  void _saveEv() {
    final bat = double.tryParse(_batteryController.text.replaceAll(',', '.'));
    final eff = double.tryParse(_evEffController.text.replaceAll(',', '.'));
    if (bat == null || bat <= 0) {
      _showError('배터리 용량을 올바르게 입력해주세요.');
      return;
    }
    if (eff == null || eff <= 0) {
      _showError('평균 전비를 올바르게 입력해주세요.');
      return;
    }
    if (_targetChargePercent <= _currentLevelPercent) {
      _showError('목표 충전량이 현재 잔량보다 높아야 합니다.');
      return;
    }

    final v = VehicleProfile(
      id: widget.editVehicleId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _resolvedName('ev'),
      vehicleType: 'ev',
      batteryCapacity: bat,
      evEfficiency: eff,
      currentLevelPercent: _currentLevelPercent,
      targetChargePercent: _targetChargePercent,
    );
    _commit(v);
  }

  void _commit(VehicleProfile v) {
    final box = Hive.box(AppConstants.settingsBox);
    final vehicles = _parseVehicles(box);

    if (widget.isEdit) {
      final idx = vehicles.indexWhere((x) => x.id == v.id);
      if (idx >= 0) {
        vehicles[idx] = v;
      } else {
        vehicles.add(v);
      }
    } else {
      vehicles.add(v);
    }

    box.put(AppConstants.keyAiVehicles, jsonEncode(vehicles.map((x) => x.toJson()).toList()));

    // 선택 차량이 없거나 이 차량이면 선택 차량으로 설정
    final selectedId = box.get(AppConstants.keyAiSelectedVehicleId) as String?;
    if (selectedId == null || selectedId.isEmpty || widget.isEdit) {
      box.put(AppConstants.keyAiSelectedVehicleId, v.id);
      _syncToLegacyKeys(box, v);
    }

    ref.read(settingsProvider.notifier).completeAiOnboarding();
    mirrorAiVehiclesToServer(); // 로그인 회원이면 서버 미러(replace-all)
    Navigator.pop(context, true); // true = 저장 완료
  }

  /// ai_main_screen 이 기존 키로 읽는 부분과 호환되도록 동기화
  void _syncToLegacyKeys(Box box, VehicleProfile v) {
    if (v.isGas) {
      box.put(AppConstants.keyAiFuelType, v.fuelType);
      box.put(AppConstants.keyAiTankCapacity, v.tankCapacity);
      box.put(AppConstants.keyAiEfficiency, v.efficiency);
      box.put(AppConstants.keyAiTargetMode, v.targetMode);
      box.put(AppConstants.keyAiTargetValue, v.targetValue);
      box.put(AppConstants.keyAiLiterTarget, v.targetValue);
    } else {
      box.put(AppConstants.keyAiTankCapacity, v.batteryCapacity);
      box.put(AppConstants.keyAiEfficiency, v.evEfficiency);
      box.put(AppConstants.keyAiTargetMode, 'FULL');
    }
    box.put(AppConstants.keyAiCurrentLevelPercent, v.currentLevelPercent);
  }

  void _showError(String msg) {
    showAppToast(context, msg, isError: true);
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final titleColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final hintColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final sectionLabelColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: titleColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isEdit ? '차량 정보 수정' : '내 차량 등록',
          style: TextStyle(
            color: titleColor,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.isEdit) ...[
                      Text(
                        '한 번 입력하면 자동으로 저장돼요',
                        style: TextStyle(fontSize: 13, color: hintColor),
                      ),
                      const SizedBox(height: 20),
                    ] else
                      const SizedBox(height: 8),

                    // ── 차량 이름 ──
                    _sectionLabel('차량 이름', sectionLabelColor),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nameController,
                      style: TextStyle(color: titleColor),
                      decoration: InputDecoration(
                        hintText: '예: 내 차, 아반떼, 테슬라 등 (비워두면 자동 생성)',
                        hintStyle: TextStyle(color: hintColor),
                        filled: true,
                        fillColor: isDark
                            ? AppColors.darkCard
                            : const Color(0xFFF8F8F8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: isDark
                              ? const BorderSide(color: AppColors.darkCardBorder)
                              : BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: isDark
                              ? const BorderSide(color: AppColors.darkCardBorder)
                              : BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: _kGasBlue, width: 1.2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── 차량 타입 선택 ──
                    _sectionLabel('차량 타입', sectionLabelColor),
                    const SizedBox(height: 10),
                    _VehicleTypeSelector(
                      selected: _vehicleType,
                      onSelect: (type) {
                        if (type == _vehicleType) return;
                        _animCtrl.reset();
                        setState(() => _vehicleType = type);
                        _animCtrl.forward();
                      },
                    ),
                    const SizedBox(height: 24),

                    // ── 동적 폼 ──
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: _vehicleType == 'gas'
                          ? _buildGasForm(isDark, sectionLabelColor, hintColor)
                          : _buildEvForm(isDark, sectionLabelColor, hintColor),
                    ),
                  ],
                ),
              ),
            ),

            // ── 저장 버튼 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _vehicleType == 'gas' ? _kGasBlue : _kEvGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    widget.isEdit ? '저장' : '저장하기',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 내연기관 폼 ──────────────────────────────────────────────────────────
  Widget _buildGasForm(bool isDark, Color sectionLabelColor, Color hintColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('유종', sectionLabelColor),
        const SizedBox(height: 8),
        _ChipRow(
          items: FuelType.values.map((f) => f.label).toList(),
          selected: _fuelType.label,
          activeColor: _kGasBlue,
          activeLight: _gasActiveBg(isDark),
          onSelect: (label) => setState(() {
            _fuelType = FuelType.values.firstWhere((f) => f.label == label);
          }),
        ),
        const SizedBox(height: 20),

        _sectionLabel('탱크 용량', sectionLabelColor),
        const SizedBox(height: 8),
        _InputField(controller: _tankController, suffix: 'L', hint: '55'),
        const SizedBox(height: 20),

        _sectionLabel('평균 연비', sectionLabelColor),
        const SizedBox(height: 8),
        _InputField(
            controller: _effController, suffix: 'km/L', hint: '12.5'),
        const SizedBox(height: 20),

        _sectionLabel('현재 잔량', sectionLabelColor),
        const SizedBox(height: 8),
        _GaugeSlider(
          value: _currentLevelPercent,
          accentColor: _kGasBlue,
          onChanged: (v) => setState(() => _currentLevelPercent = v),
        ),
        const SizedBox(height: 4),
        Text(
          '슬라이더를 움직여서 현재 연료량을 설정하세요',
          style: TextStyle(fontSize: 11, color: hintColor),
        ),
        const SizedBox(height: 20),

        _sectionLabel('목표 주유', sectionLabelColor),
        const SizedBox(height: 8),
        _ChipRow(
          items: const ['가득', '금액 지정', '리터 지정'],
          selected: _targetMode == 'FULL'
              ? '가득'
              : _targetMode == 'PRICE'
                  ? '금액 지정'
                  : '리터 지정',
          activeColor: _kGasBlue,
          activeLight: _gasActiveBg(isDark),
          onSelect: (label) => setState(() {
            _targetMode = label == '가득'
                ? 'FULL'
                : label == '금액 지정'
                    ? 'PRICE'
                    : 'LITER';
          }),
        ),
        if (_targetMode == 'PRICE') ...[
          const SizedBox(height: 10),
          _InputField(
            controller: _priceController,
            suffix: '원',
            hint: '50,000',
            keyboardType: TextInputType.number,
          ),
        ],
        if (_targetMode == 'LITER') ...[
          const SizedBox(height: 10),
          _InputField(
            controller: _literController,
            suffix: 'L',
            hint: '20',
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
        const SizedBox(height: 16),

        // 예상 주유량 미리보기
        if (_targetMode != 'PRICE')
          _PreviewBox(
            color: _gasActiveBg(isDark),
            borderColor: _kGasBlue.withValues(alpha: isDark ? 0.45 : 0.3),
            icon: Icons.local_gas_station_rounded,
            iconColor: _kGasBlue,
            text: '예상 주유량:  약 ${_gasGoalLiters.toStringAsFixed(1)} L',
            textColor: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ─── 전기차 폼 ────────────────────────────────────────────────────────────
  Widget _buildEvForm(bool isDark, Color sectionLabelColor, Color hintColor) {
    final chargeGoal = (_targetChargePercent - _currentLevelPercent)
        .clamp(0.0, 100.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('배터리 용량', sectionLabelColor),
        const SizedBox(height: 8),
        _InputField(
            controller: _batteryController, suffix: 'kWh', hint: '64'),
        const SizedBox(height: 20),

        _sectionLabel('평균 전비', sectionLabelColor),
        const SizedBox(height: 8),
        _InputField(
            controller: _evEffController, suffix: 'km/kWh', hint: '5.0'),
        const SizedBox(height: 20),

        _sectionLabel('현재 잔량', sectionLabelColor),
        const SizedBox(height: 8),
        _GaugeSlider(
          value: _currentLevelPercent,
          accentColor: _kEvGreen,
          onChanged: (v) {
            setState(() {
              _currentLevelPercent = v;
              if (_targetChargePercent <= _currentLevelPercent) {
                _targetChargePercent = (_currentLevelPercent + 10).clamp(0, 100);
              }
            });
          },
        ),
        const SizedBox(height: 4),
        Text(
          '슬라이더를 움직여서 현재 배터리 잔량을 설정하세요',
          style: TextStyle(fontSize: 11, color: hintColor),
        ),
        const SizedBox(height: 20),

        _sectionLabel('목표 충전', sectionLabelColor),
        const SizedBox(height: 8),
        _GaugeSlider(
          value: _targetChargePercent,
          accentColor: _kEvGreen,
          onChanged: (v) => setState(() {
            _targetChargePercent = v.clamp(
              (_currentLevelPercent + 1).clamp(0, 100),
              100,
            );
          }),
        ),
        const SizedBox(height: 4),
        Text(
          '목표 충전 퍼센테이지를 설정하세요',
          style: TextStyle(fontSize: 11, color: hintColor),
        ),
        const SizedBox(height: 16),

        // 예상 충전량 미리보기
        _PreviewBox(
          color: _evActiveBg(isDark),
          borderColor: _kEvGreen.withValues(alpha: isDark ? 0.45 : 0.3),
          icon: Icons.bolt_rounded,
          iconColor: _kEvGreen,
          text: '예상 충전량:  ${chargeGoal.toStringAsFixed(0)} %',
          textColor: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _sectionLabel(String text, Color color) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.4,
        ),
      );
}

// ─── 차량 타입 선택 카드 ──────────────────────────────────────────────────────
class _VehicleTypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _VehicleTypeSelector({
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: _TypeCard(
            type: 'gas',
            selected: selected == 'gas',
            icon: Icons.local_gas_station_rounded,
            label: '내연기관차',
            sub: '휘발유 · 경유 · LPG',
            activeColor: _kGasBlue,
            activeBg: _gasActiveBg(isDark),
            onTap: () => onSelect('gas'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TypeCard(
            type: 'ev',
            selected: selected == 'ev',
            icon: Icons.bolt_rounded,
            label: '전기차',
            sub: '배터리 · 충전',
            activeColor: _kEvGreen,
            activeBg: _evActiveBg(isDark),
            onTap: () => onSelect('ev'),
          ),
        ),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  final String type;
  final bool selected;
  final IconData icon;
  final String label;
  final String sub;
  final Color activeColor;
  final Color activeBg;
  final VoidCallback onTap;

  const _TypeCard({
    required this.type,
    required this.selected,
    required this.icon,
    required this.label,
    required this.sub,
    required this.activeColor,
    required this.activeBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveBg = isDark ? AppColors.darkCard : const Color(0xFFF8F8F8);
    final inactiveBorder =
        isDark ? AppColors.darkCardBorder : const Color(0xFFEEEEEE);
    final inactiveIconBg =
        isDark ? AppColors.darkIconBg : const Color(0xFFEEEEEE);
    final inactiveIconColor =
        isDark ? AppColors.darkTextMuted : const Color(0xFFAAAAAA);
    final inactiveLabelColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);
    final inactiveSubColor =
        isDark ? AppColors.darkTextMuted : const Color(0xFFBBBBBB);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? activeBg : inactiveBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? activeColor : inactiveBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? activeColor.withValues(alpha: isDark ? 0.22 : 0.15)
                    : inactiveIconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 22,
                color: selected ? activeColor : inactiveIconColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? activeColor : inactiveLabelColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(
                fontSize: 11,
                color: selected
                    ? activeColor.withValues(alpha: 0.7)
                    : inactiveSubColor,
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 14, color: activeColor),
                    const SizedBox(width: 3),
                    Text(
                      '선택됨',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: activeColor),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── 미리보기 박스 ─────────────────────────────────────────────────────────────
class _PreviewBox extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String text;
  final Color textColor;

  const _PreviewBox({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 칩 행 ───────────────────────────────────────────────────────────────────
class _ChipRow extends StatelessWidget {
  final List<String> items;
  final String selected;
  final Color activeColor;
  final Color activeLight;
  final ValueChanged<String> onSelect;

  const _ChipRow({
    required this.items,
    required this.selected,
    required this.activeColor,
    required this.activeLight,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveBg =
        isDark ? AppColors.darkCard : const Color(0xFFFAFAFA);
    final inactiveBorder =
        isDark ? AppColors.darkCardBorder : const Color(0xFFEEEEEE);
    final inactiveTextColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF999999);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        final active = item == selected;
        return GestureDetector(
          onTap: () => onSelect(item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: active ? activeLight : inactiveBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? activeColor : inactiveBorder,
              ),
            ),
            child: Text(
              item,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: active ? activeColor : inactiveTextColor,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── 입력 필드 ────────────────────────────────────────────────────────────────
class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String suffix;
  final String hint;
  final TextInputType keyboardType;

  const _InputField({
    required this.controller,
    required this.suffix,
    required this.hint,
    this.keyboardType =
        const TextInputType.numberWithOptions(decimal: true),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? AppColors.darkCard : const Color(0xFFFAFAFA);
    final fieldBorder =
        isDark ? AppColors.darkCardBorder : const Color(0xFFEEEEEE);
    final textColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1a1a1a);
    final hintColor =
        isDark ? AppColors.darkTextMuted : const Color(0xFFBBBBBB);
    final suffixColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF999999);

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fieldBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: TextStyle(fontSize: 15, color: textColor),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(color: hintColor),
                isDense: true,
              ),
            ),
          ),
          Text(
            suffix,
            style: TextStyle(fontSize: 14, color: suffixColor),
          ),
        ],
      ),
    );
  }
}

// ─── 게이지 슬라이더 ──────────────────────────────────────────────────────────
class _GaugeSlider extends StatelessWidget {
  final double value;
  final Color accentColor;
  final ValueChanged<double> onChanged;

  const _GaugeSlider({
    required this.value,
    required this.accentColor,
    required this.onChanged,
  });

  Color get _thumbColor {
    if (value <= 20) return const Color(0xFFE24B4A);
    if (value <= 50) return const Color(0xFFEF9F27);
    return accentColor;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveTrackColor =
        isDark ? AppColors.darkCardBorder : const Color(0xFFF0F0F0);
    final pctColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1a1a1a);

    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _thumbColor,
              inactiveTrackColor: inactiveTrackColor,
              thumbColor: _thumbColor,
              overlayColor: _thumbColor.withValues(alpha: 0.12),
              trackHeight: 8,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            '${value.toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: pctColor,
            ),
          ),
        ),
      ],
    );
  }
}
