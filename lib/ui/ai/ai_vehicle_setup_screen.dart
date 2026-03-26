import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

const _kPrimary = Color(0xFF1D9E75);
const _kPrimaryLight = Color(0xFFE1F5EE);

class AiVehicleSetupScreen extends ConsumerStatefulWidget {
  final bool isEdit;
  const AiVehicleSetupScreen({super.key, this.isEdit = false});

  @override
  ConsumerState<AiVehicleSetupScreen> createState() =>
      _AiVehicleSetupScreenState();
}

class _AiVehicleSetupScreenState
    extends ConsumerState<AiVehicleSetupScreen> {
  FuelType _fuelType = FuelType.gasoline;
  double _currentLevelPercent = 25.0;
  String _targetMode = 'FULL';

  final _tankController = TextEditingController();
  final _effController = TextEditingController();
  final _priceController = TextEditingController(text: '50000');
  final _literController = TextEditingController(text: '20');

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  void _loadSaved() {
    final box = Hive.box(AppConstants.settingsBox);
    _fuelType = FuelType.fromCode(
      box.get(AppConstants.keyAiFuelType,
          defaultValue: FuelType.gasoline.code) as String,
    );
    final tank =
        (box.get(AppConstants.keyAiTankCapacity, defaultValue: 55.0) as num)
            .toDouble();
    final eff =
        (box.get(AppConstants.keyAiEfficiency, defaultValue: 12.5) as num)
            .toDouble();
    _currentLevelPercent =
        (box.get(AppConstants.keyAiCurrentLevelPercent, defaultValue: 25.0)
                as num)
            .toDouble();
    _targetMode =
        box.get(AppConstants.keyAiTargetMode, defaultValue: 'FULL') as String;
    final price =
        (box.get(AppConstants.keyAiTargetValue, defaultValue: 50000.0) as num)
            .toDouble();
    final liter =
        (box.get(AppConstants.keyAiLiterTarget, defaultValue: 20.0) as num)
            .toDouble();

    _tankController.text =
        tank == tank.roundToDouble() ? tank.toStringAsFixed(0) : tank.toStringAsFixed(1);
    _effController.text =
        eff == eff.roundToDouble() ? eff.toStringAsFixed(0) : eff.toStringAsFixed(1);
    _priceController.text = price.toStringAsFixed(0);
    _literController.text =
        liter == liter.roundToDouble() ? liter.toStringAsFixed(0) : liter.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _tankController.dispose();
    _effController.dispose();
    _priceController.dispose();
    _literController.dispose();
    super.dispose();
  }

  double get _goalLiters {
    final tank = double.tryParse(_tankController.text.replaceAll(',', '.')) ?? 55.0;
    if (_targetMode == 'FULL') return tank * (1 - _currentLevelPercent / 100);
    if (_targetMode == 'LITER') {
      return double.tryParse(_literController.text.replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  void _save() {
    final tank = double.tryParse(_tankController.text.replaceAll(',', '.'));
    final eff = double.tryParse(_effController.text.replaceAll(',', '.'));
    if (tank == null || tank <= 0) {
      _showError('탱크 용량을 올바르게 입력해주세요.');
      return;
    }
    if (eff == null || eff <= 0) {
      _showError('연비를 올바르게 입력해주세요.');
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

    final box = Hive.box(AppConstants.settingsBox);
    box.put(AppConstants.keyAiFuelType, _fuelType.code);
    box.put(AppConstants.keyAiTankCapacity, tank);
    box.put(AppConstants.keyAiEfficiency, eff);
    box.put(AppConstants.keyAiCurrentLevelPercent, _currentLevelPercent);
    box.put(AppConstants.keyAiTargetMode, _targetMode);
    if (_targetMode == 'PRICE') {
      box.put(AppConstants.keyAiTargetValue,
          double.parse(_priceController.text.replaceAll(',', '.')));
    }
    if (_targetMode == 'LITER') {
      box.put(AppConstants.keyAiLiterTarget,
          double.parse(_literController.text.replaceAll(',', '.')));
    }
    ref.read(settingsProvider.notifier).completeAiOnboarding();

    if (widget.isEdit) {
      Navigator.pop(context);
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1a1a1a)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isEdit ? '차량 정보 수정' : '내 차량 정보',
          style: const TextStyle(
            color: Color(0xFF1a1a1a),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.isEdit) ...[
                      const Text(
                        '한 번 입력하면 자동으로 저장돼요',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF999999)),
                      ),
                      const SizedBox(height: 20),
                    ] else
                      const SizedBox(height: 8),

                    // ── 유종 ──
                    _label('유종'),
                    const SizedBox(height: 8),
                    _ChipRow(
                      items: FuelType.values.map((f) => f.label).toList(),
                      selected: _fuelType.label,
                      onSelect: (label) => setState(() {
                        _fuelType = FuelType.values
                            .firstWhere((f) => f.label == label);
                      }),
                    ),
                    const SizedBox(height: 18),

                    // ── 탱크 용량 ──
                    _label('탱크 용량'),
                    const SizedBox(height: 8),
                    _InputField(
                        controller: _tankController, suffix: 'L', hint: '55'),
                    const SizedBox(height: 18),

                    // ── 연비 ──
                    _label('평균 연비'),
                    const SizedBox(height: 8),
                    _InputField(
                        controller: _effController,
                        suffix: 'km/L',
                        hint: '12.5'),
                    const SizedBox(height: 18),

                    // ── 현재 잔량 ──
                    _label('현재 잔량'),
                    const SizedBox(height: 8),
                    _GaugeSlider(
                      value: _currentLevelPercent,
                      onChanged: (v) =>
                          setState(() => _currentLevelPercent = v),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '슬라이더를 움직여서 현재 연료량을 설정하세요',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 18),

                    // ── 목표 주유 ──
                    _label('목표 주유'),
                    const SizedBox(height: 8),
                    _ChipRow(
                      items: const ['가득', '금액 지정', '리터 지정'],
                      selected: _targetMode == 'FULL'
                          ? '가득'
                          : _targetMode == 'PRICE'
                              ? '금액 지정'
                              : '리터 지정',
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
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // ── 예상 주유량 미리보기 ──
                    if (_targetMode != 'PRICE')
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FBF9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _kPrimary.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                color: _kPrimary, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '예상 주유량: 약 ${_goalLiters.toStringAsFixed(1)}L',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF0F6E56),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── 저장 버튼 ──
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    widget.isEdit ? '저장' : '저장하고 시작하기',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF999999),
          letterSpacing: 0.3,
        ),
      );
}

// ─── 칩 행 ──────────────────────────────────────────────────────────────────

class _ChipRow extends StatelessWidget {
  final List<String> items;
  final String selected;
  final ValueChanged<String> onSelect;

  const _ChipRow({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
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
              color: active ? _kPrimaryLight : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active
                    ? const Color(0xFF5DCAA5)
                    : const Color(0xFFEEEEEE),
              ),
            ),
            child: Text(
              item,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: active
                    ? const Color(0xFF0F6E56)
                    : const Color(0xFF999999),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── 입력 필드 ───────────────────────────────────────────────────────────────

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
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: const TextStyle(
                  fontSize: 15, color: Color(0xFF1a1a1a)),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle:
                    const TextStyle(color: Color(0xFFBBBBBB)),
                isDense: true,
              ),
            ),
          ),
          Text(
            suffix,
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF999999)),
          ),
        ],
      ),
    );
  }
}

// ─── 연료 게이지 슬라이더 ──────────────────────────────────────────────────────

class _GaugeSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _GaugeSlider({required this.value, required this.onChanged});

  Color get _thumbColor {
    if (value <= 20) return const Color(0xFFE24B4A);
    if (value <= 50) return const Color(0xFFEF9F27);
    return _kPrimary;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _thumbColor,
              inactiveTrackColor: const Color(0xFFF0F0F0),
              thumbColor: _thumbColor,
              overlayColor: _thumbColor.withOpacity(0.12),
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
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1a1a1a),
            ),
          ),
        ),
      ],
    );
  }
}
