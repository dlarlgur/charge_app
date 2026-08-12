import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../ai_constants.dart';

/// 잔량 조건 바텀 시트 (EV 전용)
///
/// 서버가 추천 후보를 고를 때 쓰는 두 조건을 사용자가 직접 잡는다.
///  - 충전소 도착 시 최소 잔량: 만석·고장이라 못 쓸 때 다음 충전소까지 갈 여유
///  - 목적지 도착 시 최소 잔량: 도착해서 충전 못 하는 상황 대비
///
/// 세 번째 축(충전소 도착 '상한')은 급속 충전 taper 라는 배터리 특성에서 나오는 값이라
/// 취향의 영역이 아니고, 서버 원격설정으로만 관리한다 — 여기 노출하지 않는다.
class SocConditionSheet extends StatefulWidget {
  final int initialMinArrivalSoc; // 충전소 도착 하한 %
  final int initialDestMinSoc; // 목적지 도착 하한 %
  final double capacity; // kWh — % ↔ km 환산용
  final double efficiency; // km/kWh
  final void Function(int minArrivalSoc, int destMinSoc) onSave;

  /// 서버 기본값과 같아야 한다 (evAiService: ev.min_arrival_soc / ev.dest_soc_safe)
  static const int defaultMinArrivalSoc = 15;
  static const int defaultDestMinSoc = 20;

  const SocConditionSheet({
    super.key,
    required this.initialMinArrivalSoc,
    required this.initialDestMinSoc,
    required this.capacity,
    required this.efficiency,
    required this.onSave,
  });

  @override
  State<SocConditionSheet> createState() => _SocConditionSheetState();
}

class _SocConditionSheetState extends State<SocConditionSheet> {
  late double _minArrival;
  late double _destMin;

  @override
  void initState() {
    super.initState();
    _minArrival = widget.initialMinArrivalSoc.toDouble();
    _destMin = widget.initialDestMinSoc.toDouble();
  }

  /// 1% 로 갈 수 있는 거리(km). 차량 정보가 없으면 0 → km 병기를 숨긴다.
  double get _kmPerPct => widget.capacity * widget.efficiency / 100;

  String _kmHint(double pct) {
    final km = _kmPerPct * pct;
    if (km <= 0) return '';
    return '약 ${km.round()}km';
  }

  bool get _isDefault =>
      _minArrival.round() == SocConditionSheet.defaultMinArrivalSoc &&
      _destMin.round() == SocConditionSheet.defaultDestMinSoc;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = kEvAccent;
    const accentDeep = kEvAccentDeep;
    final inkColor = isDark ? AppColors.darkTextPrimary : kInk;
    final subColor = isDark ? AppColors.darkTextSecondary : kMuted;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        // 작은 화면에서 슬라이더 2개 + 안내가 넘치면 스크롤 (오버플로 방지)
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
                      '잔량 조건',
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
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0x1FFFFFFF) : kLineSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close_rounded,
                            size: 18,
                            color:
                                isDark ? AppColors.darkTextSecondary : kMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '이 범위를 벗어나는 충전소는 추천에서 빼드려요.',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: subColor),
                ),
                const SizedBox(height: 22),

                _sliderBlock(
                  icon: Icons.ev_station_rounded,
                  title: '충전소 도착 시 최소 잔량',
                  desc: '자리가 없거나 고장이어도 다음 충전소까지 갈 여유예요.',
                  value: _minArrival,
                  accent: accent,
                  accentDeep: accentDeep,
                  inkColor: inkColor,
                  subColor: subColor,
                  onChanged: (v) => setState(() => _minArrival = v),
                ),
                const SizedBox(height: 24),
                _sliderBlock(
                  icon: Icons.flag_rounded,
                  title: '목적지 도착 시 최소 잔량',
                  desc: '도착해서 바로 충전 못 하는 상황에 대비한 여유예요.',
                  value: _destMin,
                  accent: accent,
                  accentDeep: accentDeep,
                  inkColor: inkColor,
                  subColor: subColor,
                  onChanged: (v) => setState(() => _destMin = v),
                ),

                const SizedBox(height: 20),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 15, color: accentDeep),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '조건을 만족하는 충전소가 없으면 안전한 쪽부터 순서대로 완화해서 추천해요.',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                              color: accentDeep),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                Row(
                  children: [
                    if (!_isDefault)
                      TextButton(
                        onPressed: () => setState(() {
                          _minArrival =
                              SocConditionSheet.defaultMinArrivalSoc.toDouble();
                          _destMin =
                              SocConditionSheet.defaultDestMinSoc.toDouble();
                        }),
                        child: Text('기본값',
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: subColor)),
                      ),
                    const Spacer(),
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            widget.onSave(
                                _minArrival.round(), _destMin.round());
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('적용',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sliderBlock({
    required IconData icon,
    required String title,
    required String desc,
    required double value,
    required Color accent,
    required Color accentDeep,
    required Color inkColor,
    required Color subColor,
    required ValueChanged<double> onChanged,
  }) {
    final hint = _kmHint(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 7),
            // 긴 라벨이 좁은 화면에서 넘치지 않도록 Expanded
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: inkColor)),
            ),
            const SizedBox(width: 8),
            Text('${value.round()}%',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: accentDeep)),
            if (hint.isNotEmpty) ...[
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(hint,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: subColor)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(desc,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500, color: subColor)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            inactiveTrackColor: kLine,
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.12),
            trackHeight: 4,
          ),
          child: Slider(
            value: value.clamp(0, 50),
            min: 0,
            max: 50,
            divisions: 10, // 5% 단위
            label: '${value.round()}%',
            onChanged: onChanged,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0%',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: kLine)),
              Text('25%',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: kLine)),
              Text('50%',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: kLine)),
            ],
          ),
        ),
      ],
    );
  }
}
