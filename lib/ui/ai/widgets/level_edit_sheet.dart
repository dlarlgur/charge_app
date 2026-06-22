import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../ai_constants.dart';

/// 잔량/목표 편집 바텀 시트
class LevelEditSheet extends StatefulWidget {
  final double initialLevel;
  final String initialMode;
  final TextEditingController priceController;
  final TextEditingController literController;
  final void Function(double level, String mode, double targetChargePercent) onSave;
  final bool isEv;
  /// 선택 차량 용량(가스 L / EV kWh)·효율(가스 km/L / EV km/kWh).
  /// 주행가능거리 → % 환산에 사용 (글로벌 키 대신 선택 차량 기준 — EV/다차량 꼬임 방지).
  final double capacity;
  final double efficiency;
  /// EV 목표 충전 % (기본 80). 가스는 미사용.
  final double initialTargetChargePercent;

  const LevelEditSheet({
    super.key,
    required this.initialLevel,
    required this.initialMode,
    required this.priceController,
    required this.literController,
    required this.onSave,
    this.isEv = false,
    this.capacity = 55.0,
    this.efficiency = 12.5,
    this.initialTargetChargePercent = 80.0,
  });

  @override
  State<LevelEditSheet> createState() => _LevelEditSheetState();
}

class _LevelEditSheetState extends State<LevelEditSheet> {
  late double _level;
  late String _mode;
  late double _targetChargePercent;
  bool _useDte = false;
  final _dteController = TextEditingController();
  String? _dteError;

  @override
  void initState() {
    super.initState();
    _level = widget.initialLevel;
    _mode = widget.initialMode;
    _targetChargePercent = widget.initialTargetChargePercent;
  }

  @override
  void dispose() {
    _dteController.dispose();
    super.dispose();
  }

  Color get _thumbColor {
    if (_level <= 20) return const Color(0xFFE24B4A);
    if (_level <= 50) return const Color(0xFFEF9F27);
    return const Color(0xFF22C55E);
  }

  void _applyDte(String val) {
    final dte = double.tryParse(val.replaceAll(',', '.'));
    if (dte == null || dte <= 0) {
      setState(() => _dteError = '올바른 거리를 입력해주세요');
      return;
    }
    // 선택 차량 기준 만충 주행거리 = 용량 × 효율 (가스: L×km/L, EV: kWh×km/kWh).
    // 글로벌 가스값(55L/12.5)을 쓰던 버그 수정 — EV/다차량에서 % 가 엉터리로 나오던 원인.
    final fullRangeKm = widget.capacity * widget.efficiency;
    final pct = fullRangeKm > 0
        ? (dte / fullRangeKm * 100).clamp(0.0, 100.0)
        : 0.0;
    setState(() { _level = pct; _dteError = null; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          // 키보드 + 다중 입력칸이 작은 화면을 넘으면 스크롤(오버플로 방지).
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('잔량 & 목표 설정',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextPrimary : const Color(0xFF1a1a1a),
                      )),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── 잔량 입력 모드 토글 ──
              Row(
                children: [
                  const Text('현재 잔량',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF999999))),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() { _useDte = !_useDte; _dteError = null; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _useDte ? kPrimary.withValues(alpha: 0.1) : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _useDte ? kPrimary : const Color(0xFFDDDDDD)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.speed_rounded, size: 13,
                              color: _useDte ? kPrimary : const Color(0xFF888888)),
                          const SizedBox(width: 4),
                          Text('주행가능거리 입력',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                  color: _useDte ? kPrimary : const Color(0xFF888888))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── DTE 입력 or % 슬라이더 ──
              if (_useDte) ...[
                TextField(
                  controller: _dteController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: '계기판 주행가능거리 (km)',
                    hintText: '예: 120',
                    suffixText: 'km',
                    errorText: _dteError,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: _applyDte,
                ),
                const SizedBox(height: 8),
                Text(
                  '→ 잔량 약 ${_level.toStringAsFixed(1)}%로 계산됨',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkTextSecondary : const Color(0xFF888888)),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: _thumbColor,
                          inactiveTrackColor: const Color(0xFFF0F0F0),
                          thumbColor: _thumbColor,
                          overlayColor: _thumbColor.withValues(alpha: 0.12),
                          trackHeight: 8,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                        ),
                        child: Slider(
                          value: _level,
                          min: 0, max: 100, divisions: 100,
                          onChanged: (v) => setState(() => _level = v),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${_level.toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                              color: _thumbColor)),
                    ),
                  ],
                ),
              ],
              if (widget.isEv) ...[
                const SizedBox(height: 18),
                Text('목표 충전',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextMuted : const Color(0xFF999999))),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: kPrimary,
                          inactiveTrackColor: const Color(0xFFF0F0F0),
                          thumbColor: kPrimary,
                          overlayColor: kPrimary.withValues(alpha: 0.12),
                          trackHeight: 8,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                        ),
                        child: Slider(
                          value: _targetChargePercent.clamp(0, 100),
                          min: 0, max: 100, divisions: 100,
                          onChanged: (v) => setState(() => _targetChargePercent = v),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${_targetChargePercent.toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kPrimary)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('이 충전량까지 채우는 기준으로 추천해요.',
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkTextSecondary : const Color(0xFF888888))),
              ],
              if (!widget.isEv) ...[
              const SizedBox(height: 16),
              Text('목표 주유',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkTextMuted : const Color(0xFF999999))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in [('FULL', '가득'), ('PRICE', '금액 지정'), ('LITER', '리터 지정')])
                    GestureDetector(
                      onTap: () => setState(() => _mode = entry.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _mode == entry.$1 ? kPrimary : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(entry.$2,
                            style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500,
                              color: _mode == entry.$1 ? Colors.white : const Color(0xFF666666),
                            )),
                      ),
                    ),
                ],
              ),
              if (_mode == 'PRICE') ...[
                const SizedBox(height: 14),
                TextField(
                  controller: widget.priceController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: '목표 금액 (원)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ],
              if (_mode == 'LITER') ...[
                const SizedBox(height: 14),
                TextField(
                  controller: widget.literController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: '목표 리터 (L)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ],
              ], // if (!widget.isEv)
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => widget.onSave(_level, _mode, _targetChargePercent),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('저장', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
            ),
          ),
        ),
      ),
    );
  }
}
