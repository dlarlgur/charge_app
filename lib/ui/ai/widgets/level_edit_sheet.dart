import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../ai_constants.dart';

/// 잔량 & 목표 편집 바텀 시트 (리뉴얼 + EV 목표충전 통합)
/// - 상단 그라데이션 요약 카드(잔량 % + 주행가능 km + 잔여량)
/// - 컬러존 슬라이더 (위험/주의/충분) + 주행가능거리(DTE) 입력 토글
/// - 목표: 주유 = 가득/금액 지정/리터 지정, 충전 = 80%/100%/직접(목표충전 %)
///
/// capacity/efficiency 는 선택 차량 값을 생성자로 받는다(다차량·EV 에서 % 정확).
class LevelEditSheet extends StatefulWidget {
  final double initialLevel;
  final String initialMode;
  final TextEditingController priceController;
  final TextEditingController literController;
  final void Function(double level, String mode, double targetChargePercent)
      onSave;
  final bool isEv;
  final double capacity; // 가스 L / EV kWh
  final double efficiency; // 가스 km/L / EV km/kWh
  final double initialTargetChargePercent; // EV 목표 충전 %(기본 80). 가스 미사용.

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
  // 직접(커스텀) 목표충전 모드 — 명시 플래그. 값 기반이 아니라 슬라이더로 80/100 닿아도 안 풀림.
  bool _customTarget = false;
  bool _useDte = false;
  final _dteController = TextEditingController();
  String? _dteError;

  @override
  void initState() {
    super.initState();
    _level = widget.initialLevel;
    _mode = widget.initialMode;
    _targetChargePercent = widget.initialTargetChargePercent;
    _customTarget = widget.initialTargetChargePercent != 80 &&
        widget.initialTargetChargePercent != 100;
  }

  @override
  void dispose() {
    _dteController.dispose();
    super.dispose();
  }

  double get _cap => widget.capacity;
  double get _eff => widget.efficiency;
  double get _remainUnit => _cap * _level / 100; // L 또는 kWh
  double get _reachableKm => _remainUnit * _eff;

  // 잔량 구간 색 — 위험/주의/충분
  Color get _zoneColor {
    if (_level <= 20) return const Color(0xFFEF4444);
    if (_level <= 50) return const Color(0xFFF59E0B);
    return const Color(0xFF22C55E);
  }

  // EV 목표충전 — 직접(커스텀) 모드 여부 (명시 플래그).
  bool get _isCustomTarget => _customTarget;

  // 목표까지 더 필요한 kWh(EV)
  double get _needKwh {
    final d = (_targetChargePercent - _level) / 100 * _cap;
    return d > 0 ? d : 0;
  }

  void _applyDte(String val) {
    final dte = double.tryParse(val.replaceAll(',', '.'));
    if (dte == null || dte <= 0) {
      setState(() => _dteError = '올바른 거리를 입력해주세요');
      return;
    }
    // 만충 주행거리 = 용량 × 효율 (선택 차량 기준). 글로벌값 쓰면 다차량에서 % 틀어짐.
    final fullRangeKm = _cap * _eff;
    final pct =
        fullRangeKm > 0 ? (dte / fullRangeKm * 100).clamp(0.0, 100.0) : 0.0;
    setState(() {
      _level = pct.toDouble();
      _dteError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = modeAccent(widget.isEv);
    final accentDeep = modeAccentDeep(widget.isEv);
    final unitLabel = widget.isEv ? 'kWh' : 'L';
    final inkColor = isDark ? AppColors.darkTextPrimary : kInk;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          // 키보드 + 다중 입력칸이 작은 화면을 넘으면 스크롤(오버플로/모달 튕김 방지).
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
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
                            : [
                                const Color(0xFFFFFBEB),
                                const Color(0xFFFEF3C7)
                              ],
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
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: inkColor),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() {
                          _useDte = !_useDte;
                          _dteError = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            color: _useDte
                                ? accent.withValues(alpha: 0.1)
                                : kLineSoft,
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
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
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

                  // ── 목표 충전 (EV 전용) ──
                  if (widget.isEv) ...[
                    const SizedBox(height: 24),
                    Text('목표 충전',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: inkColor)),
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        _evTargetSeg('80%', 80, accent),
                        const SizedBox(width: 8),
                        _evTargetSeg('100%', 100, accent),
                        const SizedBox(width: 8),
                        _evTargetSeg('직접', null, accent),
                      ],
                    ),
                    if (_isCustomTarget) ...[
                      const SizedBox(height: 12),
                      Text('목표 ${_targetChargePercent.round()}%',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: accentDeep)),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: accent,
                          thumbColor: accent,
                          overlayColor: accent.withValues(alpha: 0.12),
                        ),
                        child: Slider(
                          value: _targetChargePercent.clamp(0, 100).toDouble(),
                          min: 0,
                          max: 100,
                          divisions: 100,
                          label: '${_targetChargePercent.round()}%',
                          onChanged: (v) =>
                              setState(() => _targetChargePercent = v),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 15, color: accentDeep),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _needKwh > 0
                                  ? '목표 ${_targetChargePercent.round()}%까지 약 ${_needKwh.toStringAsFixed(1)} kWh 더 충전하면 돼요'
                                  : '이미 목표 충전량 이상이에요',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: accentDeep),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // ── 목표 주유량 (주유 전용) ──
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
                                            color:
                                                accent.withValues(alpha: 0.3),
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
                      onPressed: () =>
                          widget.onSave(_level, _mode, _targetChargePercent),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: const Text('저장',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
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

  // EV 목표충전 세그먼트 — value null = 직접(커스텀).
  Widget _evTargetSeg(String label, double? value, Color accent) {
    final selected = value == null
        ? _customTarget
        : (!_customTarget && _targetChargePercent == value);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          if (value != null) {
            _customTarget = false;
            _targetChargePercent = value;
          } else {
            _customTarget = true;
            if (_targetChargePercent == 80 || _targetChargePercent == 100) {
              _targetChargePercent = 90; // 직접 진입 기본값(슬라이더 시작점)
            }
          }
        }),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent : kLineSoft,
            borderRadius: BorderRadius.circular(13),
            boxShadow: selected
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
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : kMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// 컬러존(위험→주의→충분) 트랙 위에 채움 + 드래그 thumb 을 얹은 슬라이더.
/// 컬러존(위험→주의→충분) 슬라이더.
/// Flutter Slider 의 thumb 반지름 여백 때문에 채움과 thumb 가 어긋나던 문제를
/// 직접 좌표 계산으로 해결 — thumb 중심 == 채움 끝이 항상 정확히 일치한다.
class _ZoneSlider extends StatelessWidget {
  final double level; // 0-100
  final Color zoneColor;
  final ValueChanged<double> onChanged;
  const _ZoneSlider(
      {required this.level, required this.zoneColor, required this.onChanged});

  static const double _h = 26; // 전체 높이
  static const double _track = 9; // 트랙 두께
  static const double _thumb = 23; // thumb 지름

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        // 트랙·이동범위를 thumb 반지름만큼 좌우 인셋 → 채움 끝과 thumb 중심을 같은 좌표로.
        final usable = (w - _thumb) <= 0 ? 1.0 : (w - _thumb);
        final frac = (level / 100).clamp(0.0, 1.0);
        final fillW = usable * frac;
        const trackTop = (_h - _track) / 2;
        const thumbTop = (_h - _thumb) / 2;

        void update(double dx) {
          final f = ((dx - _thumb / 2) / usable).clamp(0.0, 1.0);
          onChanged(f * 100);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => update(d.localPosition.dx),
          onHorizontalDragStart: (d) => update(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
          child: SizedBox(
            width: w,
            height: _h,
            child: Stack(
              children: [
                // 컬러존 배경(흐리게) — 좌우 thumb 반지름 인셋
                Positioned(
                  left: _thumb / 2,
                  right: _thumb / 2,
                  top: trackTop,
                  height: _track,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFEF4444),
                          Color(0xFFF59E0B),
                          Color(0xFF22C55E),
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ),
                    ),
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                ),
                // 채움 — 왼쪽(thumb 반지름)부터 thumb 중심까지
                Positioned(
                  left: _thumb / 2,
                  top: trackTop,
                  width: fillW,
                  height: _track,
                  child: Container(
                    decoration: BoxDecoration(
                      color: zoneColor,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                // thumb — left=fillW 면 중심이 fillW + thumb/2 = 채움 끝과 일치
                Positioned(
                  left: fillW,
                  top: thumbTop,
                  width: _thumb,
                  height: _thumb,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: zoneColor, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: zoneColor.withValues(alpha: 0.4),
                          blurRadius: 4,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
