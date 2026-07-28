import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../ai_constants.dart';

/// 잔량 & 목표 편집 바텀 시트 (리뉴얼)
/// - 상단 그라데이션 요약 카드(잔량 % + 주행가능 km + 잔여량)
/// - 컬러존 슬라이더 (위험/주의/충분) + 주행가능거리 입력 토글
/// - 목표 주유량 세그먼트 (가득 / 금액 지정 / 리터 지정) — 주유 전용
///
/// 기존 `widgets/level_edit_sheet.dart` 를 이 파일로 교체하세요. (생성자 API 동일)
class LevelEditSheet extends StatefulWidget {
  final double initialLevel;
  final String initialMode;
  final TextEditingController priceController;
  final TextEditingController literController;
  final void Function(double level, String mode) onSave;
  final bool isEv;

  const LevelEditSheet({
    super.key,
    required this.initialLevel,
    required this.initialMode,
    required this.priceController,
    required this.literController,
    required this.onSave,
    this.isEv = false,
  });

  @override
  State<LevelEditSheet> createState() => _LevelEditSheetState();
}

class _LevelEditSheetState extends State<LevelEditSheet> {
  late double _level;
  late String _mode;
  bool _useDte = false;
  final _dteController = TextEditingController();
  String? _dteError;

  @override
  void initState() {
    super.initState();
    _level = widget.initialLevel;
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _dteController.dispose();
    super.dispose();
  }

  Box get _box => Hive.box(AppConstants.settingsBox);
  double get _tank =>
      (_box.get(AppConstants.keyAiTankCapacity, defaultValue: 55.0) as num)
          .toDouble();
  double get _eff =>
      (_box.get(AppConstants.keyAiEfficiency, defaultValue: 12.5) as num)
          .toDouble();

  double get _remainUnit => _tank * _level / 100; // L 또는 kWh
  double get _reachableKm => _remainUnit * _eff;

  // 잔량 구간 색 — 위험/주의/충분
  Color get _zoneColor {
    if (_level <= 20) return const Color(0xFFEF4444);
    if (_level <= 50) return const Color(0xFFF59E0B);
    return const Color(0xFF22C55E);
  }

  void _applyDte(String val) {
    final dte = double.tryParse(val.replaceAll(',', '.'));
    if (dte == null || dte <= 0) {
      setState(() => _dteError = '올바른 거리를 입력해주세요');
      return;
    }
    final liters = dte / _eff;
    final pct = (liters / _tank * 100).clamp(0.0, 100.0);
    setState(() {
      _level = pct;
      _dteError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = modeAccent(widget.isEv);
    final accentDeep = modeAccentDeep(widget.isEv);
    final unitLabel = widget.isEv ? 'kWh' : 'L';
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final inkColor = isDark ? AppColors.darkTextPrimary : kInk;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: kLine,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Row(
                children: [
                  Text(
                    '잔량 & 목표 설정',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: inkColor,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: kLineSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: kMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── 요약 카드 ──
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.isEv
                        ? [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)]
                        : [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isEv ? '현재 배터리' : '현재 잔유량',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: accentDeep,
                          ),
                        ),
                        const SizedBox(height: 2),
                        RichText(
                          text: TextSpan(children: [
                            TextSpan(
                              text: _level.round().toString(),
                              style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w800,
                                color: kInk,
                                letterSpacing: -2,
                                height: 1,
                              ),
                            ),
                            TextSpan(
                              text: ' %',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: _zoneColor,
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('주행 가능',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: kMute2)),
                        const SizedBox(height: 2),
                        RichText(
                          text: TextSpan(children: [
                            TextSpan(
                              text: '약 ${_reachableKm.round()}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: kInk,
                                letterSpacing: -0.6,
                              ),
                            ),
                            const TextSpan(
                              text: ' km',
                              style: TextStyle(fontSize: 13, color: kMute2),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '약 ${_remainUnit.toStringAsFixed(1)} $unitLabel 남음',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: kMute2),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── 슬라이더 / DTE ──
              const SizedBox(height: 22),
              Row(
                children: [
                  Text(
                    _useDte ? '주행가능거리로 입력' : '슬라이더로 조절',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: inkColor),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () =>
                        setState(() {
                      _useDte = !_useDte;
                      _dteError = null;
                    }),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: _useDte ? accent.withValues(alpha: 0.1) : kLineSoft,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color: _useDte ? accent : kLine, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.speed_rounded,
                              size: 14, color: _useDte ? accent : kMuted),
                          const SizedBox(width: 4),
                          Text(
                            _useDte ? '슬라이더로' : '주행가능거리로 입력',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: _useDte ? accent : kMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_useDte) ...[
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
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: _applyDte,
                ),
                const SizedBox(height: 8),
                Text('→ 잔량 약 ${_level.toStringAsFixed(1)}% 로 계산됐어요',
                    style: const TextStyle(fontSize: 12, color: kMuted)),
              ] else ...[
                _ZoneSlider(
                  level: _level,
                  zoneColor: _zoneColor,
                  onChanged: (v) => setState(() => _level = v),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 8, 6, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0%',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: kLine)),
                      Text('위험',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFEF4444))),
                      Text('50%',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: kLine)),
                      Text('100%',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: kLine)),
                    ],
                  ),
                ),
              ],

              // ── 목표 주유량 (주유 전용) ──
              if (!widget.isEv) ...[
                const SizedBox(height: 24),
                Text('목표 주유량',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: inkColor)),
                const SizedBox(height: 11),
                Row(
                  children: [
                    for (final entry in const [
                      ('FULL', '가득'),
                      ('PRICE', '금액 지정'),
                      ('LITER', '리터 지정')
                    ]) ...[
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _mode = entry.$1),
                          child: Container(
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _mode == entry.$1 ? accent : kLineSoft,
                              borderRadius: BorderRadius.circular(13),
                              boxShadow: _mode == entry.$1
                                  ? [
                                      BoxShadow(
                                        color: accent.withValues(alpha: 0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      )
                                    ]
                                  : null,
                            ),
                            child: Text(
                              entry.$2,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: _mode == entry.$1
                                    ? Colors.white
                                    : kMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (entry.$1 != 'LITER') const SizedBox(width: 8),
                    ],
                  ],
                ),
                if (_mode == 'PRICE') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: widget.priceController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '목표 금액 (원)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ] else if (_mode == 'LITER') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: widget.literController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '목표 리터 (L)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ],
              ],

              // ── 저장 ──
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => widget.onSave(_level, _mode),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('저장',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 컬러존(위험→주의→충분) 트랙 위에 accent 채움 + 드래그 thumb 을 얹은 슬라이더.
class _ZoneSlider extends StatelessWidget {
  final double level;
  final Color zoneColor;
  final ValueChanged<double> onChanged;
  const _ZoneSlider(
      {required this.level, required this.zoneColor, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // 컬러존 배경
          Container(
            height: 9,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: const LinearGradient(colors: [
                Color(0xFFEF4444),
                Color(0xFFF59E0B),
                Color(0xFF22C55E),
              ], stops: [
                0.0,
                0.45,
                1.0
              ]),
            ),
            // 살짝 흐리게 — 채움이 도드라지도록
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          // accent 채움
          FractionallySizedBox(
            widthFactor: (level / 100).clamp(0.0, 1.0),
            child: Container(
              height: 9,
              decoration: BoxDecoration(
                color: zoneColor,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          // 상호작용 + thumb
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 9,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayColor: zoneColor.withValues(alpha: 0.12),
              thumbShape: _RingThumb(color: zoneColor),
              trackShape: const RectangularSliderTrackShape(),
            ),
            child: Slider(
              value: level,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 흰 원 + accent 테두리 thumb.
class _RingThumb extends SliderComponentShape {
  final Color color;
  const _RingThumb({required this.color});

  @override
  Size getPreferredSize(bool enabled, bool isDiscrete) => const Size(23, 23);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final canvas = context.canvas;
    canvas.drawCircle(
        center, 11.5, Paint()..color = color.withValues(alpha: 0.4));
    canvas.drawCircle(center, 11, Paint()..color = Colors.white);
    canvas.drawCircle(
        center,
        11,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }
}
