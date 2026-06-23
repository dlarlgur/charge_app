import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../ai_constants.dart';
import 'gauge_ring.dart';

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
    // 충분: EV 초록 / 주유 파랑 (메인 게이지와 동일 톤).
    return widget.isEv ? const Color(0xFF22C55E) : AppColors.gasBlue;
  }

  // 네이티브 느낌 슬라이더 — 두꺼운 라운드 트랙 + 흰 썸(그림자) + 드래그 시 값 말풍선.
  Widget _premiumSlider({
    required double value,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: color,
        inactiveTrackColor: color.withValues(alpha: 0.14),
        thumbColor: Colors.white,
        overlayColor: color.withValues(alpha: 0.14),
        trackHeight: 12,
        trackShape: const RoundedRectSliderTrackShape(),
        thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 11, elevation: 3, pressedElevation: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
        showValueIndicator: ShowValueIndicator.always,
        valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
        valueIndicatorColor: color,
        valueIndicatorTextStyle: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
      ),
      child: Slider(
        value: value.clamp(0, 100),
        min: 0,
        max: 100,
        divisions: 100,
        label: '${value.round()}%',
        onChanged: onChanged,
      ),
    );
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

  // 목표 버튼 3개. EV/가스 공통 스타일, 의미만 유종별.
  Widget _targetButton({
    required String label,
    required String sub,
    required bool selected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    // 선택색 = 유종 브랜드색(주유 파랑 / 충전 에메랄드).
    final bg = selected
        ? modeAccent(widget.isEv)
        : (isDark ? AppColors.darkCard : const Color(0xFFF4F6FA));
    final labelColor = selected
        ? Colors.white
        : (isDark ? AppColors.darkTextPrimary : const Color(0xFF1a1a1a));
    final subColor = selected
        ? Colors.white.withValues(alpha: 0.85)
        : (isDark ? AppColors.darkTextSecondary : const Color(0xFF888888));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: labelColor)),
            const SizedBox(height: 3),
            Text(sub,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600, color: subColor)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor =
        isDark ? AppColors.darkTextMuted : const Color(0xFF999999);
    final subTextColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);
    final reachableKm = widget.capacity * widget.efficiency * _level / 100;
    final gaugeColor = _thumbColor;
    // colorDeep: 같은 톤을 살짝 진하게(검정 쪽으로 lerp) — 가독성용.
    final gaugeColorDeep =
        Color.lerp(gaugeColor, Colors.black, 0.18) ?? gaugeColor;

    // 목표 버튼 선택 상태 (유종별).
    final bool selFull =
        widget.isEv ? _targetChargePercent == 100 : _mode == 'FULL';
    final bool selHalf =
        widget.isEv ? _targetChargePercent == 50 : _mode == 'PRICE';
    final bool selCustom =
        widget.isEv ? (!selFull && !selHalf) : _mode == 'LITER';

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
                  // 1. 타이틀 + 닫기
                  Row(
                    children: [
                      Text('잔량 & 목표 설정',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: mutedColor,
                          )),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // 2. 메인 Row: 게이지(왼) + 슬라이더(오른)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GaugeRing(
                        percent: _level,
                        reachableKm: reachableKm,
                        color: gaugeColor,
                        colorDeep: gaugeColorDeep,
                        isEv: widget.isEv,
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('현재 잔량',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: mutedColor)),
                            const SizedBox(height: 10),
                            _premiumSlider(
                              value: _level,
                              color: _thumbColor,
                              onChanged: (v) => setState(() => _level = v),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text('비었음',
                                    style: TextStyle(
                                        fontSize: 11, color: mutedColor)),
                                const Spacer(),
                                Text('가득',
                                    style: TextStyle(
                                        fontSize: 11, color: mutedColor)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // 2-b. 주행가능거리 입력 토글 (기능 유지, 작게)
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _useDte = !_useDte;
                        _dteError = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _useDte
                              ? modeAccent(widget.isEv).withValues(alpha: 0.1)
                              : (isDark
                                  ? AppColors.darkCard
                                  : const Color(0xFFF5F5F5)),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _useDte
                                  ? modeAccent(widget.isEv)
                                  : const Color(0xFFDDDDDD)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.speed_rounded,
                                size: 13,
                                color: _useDte
                                    ? modeAccent(widget.isEv)
                                    : const Color(0xFF888888)),
                            const SizedBox(width: 4),
                            Text('주행가능거리 입력',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _useDte
                                        ? modeAccent(widget.isEv)
                                        : const Color(0xFF888888))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_useDte) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _dteController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: '계기판 주행가능거리 (km)',
                        hintText: '예: 120',
                        suffixText: 'km',
                        errorText: _dteError,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      onChanged: _applyDte,
                    ),
                    const SizedBox(height: 6),
                    Text('→ 잔량 약 ${_level.toStringAsFixed(1)}%로 계산됨',
                        style: TextStyle(fontSize: 12, color: subTextColor)),
                  ],

                  // 3. Divider
                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: isDark
                        ? AppColors.darkCardBorder
                        : const Color(0xFFECEFF3),
                  ),
                  const SizedBox(height: 16),

                  // 4. 목표 타이틀
                  Text('목표 잔량 — 얼마나 채울까요?',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : const Color(0xFF1a1a1a))),
                  const SizedBox(height: 10),

                  // 5. 3개 버튼 Row
                  Row(
                    children: [
                      Expanded(
                        child: _targetButton(
                          label: '가득',
                          sub: widget.isEv ? '100%' : '가득',
                          selected: selFull,
                          isDark: isDark,
                          onTap: () => setState(() {
                            if (widget.isEv) {
                              _targetChargePercent = 100;
                            } else {
                              _mode = 'FULL';
                            }
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _targetButton(
                          label: widget.isEv ? '절반' : '금액',
                          sub: widget.isEv ? '50%' : '지정',
                          selected: selHalf,
                          isDark: isDark,
                          onTap: () => setState(() {
                            if (widget.isEv) {
                              _targetChargePercent = 50;
                            } else {
                              _mode = 'PRICE';
                            }
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _targetButton(
                          label: widget.isEv ? '직접' : '리터',
                          sub: '설정',
                          selected: selCustom,
                          isDark: isDark,
                          onTap: () => setState(() {
                            if (widget.isEv) {
                              // 직접 선택 시 100/50 외 값으로 — 현재가 그 둘 중 하나면 80으로.
                              if (_targetChargePercent == 100 ||
                                  _targetChargePercent == 50) {
                                _targetChargePercent = 80;
                              }
                            } else {
                              _mode = 'LITER';
                            }
                          }),
                        ),
                      ),
                    ],
                  ),

                  // 5-b. EV 직접 선택 시 커스텀 슬라이더 펼침
                  if (widget.isEv && selCustom) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _premiumSlider(
                            value: _targetChargePercent.clamp(0, 100).toDouble(),
                            color: modeAccent(widget.isEv),
                            onChanged: (v) =>
                                setState(() => _targetChargePercent = v),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                              '${_targetChargePercent.toStringAsFixed(0)}%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: modeAccent(widget.isEv))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('이 충전량까지 채우는 기준으로 추천해요.',
                        style: TextStyle(fontSize: 11, color: subTextColor)),
                  ],

                  // 5-c. 가스 금액/리터 입력 펼침
                  if (!widget.isEv && _mode == 'PRICE') ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: widget.priceController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: '목표 금액 (원)',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],
                  if (!widget.isEv && _mode == 'LITER') ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: widget.literController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: '목표 리터 (L)',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () =>
                          widget.onSave(_level, _mode, _targetChargePercent),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: modeAccent(widget.isEv),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('저장',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
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
