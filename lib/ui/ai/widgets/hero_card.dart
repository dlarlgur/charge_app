import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../ai_constants.dart';
import 'gauge_ring.dart';

/// Hero 카드 (ai_reco_main.html 양식)
/// 큰 원형 게이지 (잔량 %) + 가능 km + 차량 정보 + 효율/탱크 stat + 선호 조건 chip.
/// 사용자 입력: tap → 잔량 편집 시트, 차량 편집 → 차량 선택, chip 토글.
class HeroCard extends StatelessWidget {
  final double currentLevel;
  final bool isEv;
  final double reachableKm;
  final String vehicleName;
  final double efficiency;          // km/L or km/kWh
  final double tankCapacity;        // L or kWh
  final bool highwayOnly;
  final String? chargerMode;        // 'FAST' | 'SLOW' (EV 전용)
  final VoidCallback onTapLevel;
  final VoidCallback onTapVehicle;
  final VoidCallback onToggleHighway;
  final ValueChanged<String>? onChangeChargerMode;
  /// 카드 상단 안쪽에 얹는 그랩 핸들 — 카드와 한 덩어리로 렌더(배경/그림자 자체엔 없음).
  final Widget? topHandle;

  const HeroCard({
    super.key,
    required this.currentLevel,
    required this.isEv,
    required this.reachableKm,
    required this.vehicleName,
    required this.efficiency,
    required this.tankCapacity,
    required this.highwayOnly,
    required this.chargerMode,
    required this.onTapLevel,
    required this.onTapVehicle,
    required this.onToggleHighway,
    this.onChangeChargerMode,
    this.topHandle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = modeAccent(isEv);
    final accentDeep = modeAccentDeep(isEv);
    return Container(
      // 핸들이 카드 안 최상단에 오면 top 패딩을 줄여 핸들이 곧 카드 윗부분이 되게.
      padding: EdgeInsets.fromLTRB(18, topHandle != null ? 6 : 18, 18, 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkMapOverlay : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: isDark ? Border.all(color: AppColors.darkCardBorder, width: 1) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24, offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (topHandle != null) topHandle!,
          // 1) 상단 row — 게이지 + 차량 정보
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 큰 원형 게이지 (108x108) — 탭하면 잔량 편집. 우하단 연필 배지로 편집 가능 표시.
                GestureDetector(
                  onTap: onTapLevel,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GaugeRing(
                        percent: currentLevel,
                        reachableKm: reachableKm,
                        color: accent,
                        colorDeep: accentDeep,
                        isEv: isEv,
                      ),
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? const Color(0xFF12141A) : Colors.white,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.edit_rounded, size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // 차량 정보 + stat
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              vehicleName.isEmpty ? (isEv ? 'EV' : '차량') : vehicleName,
                              style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color: isDark ? AppColors.darkTextPrimary : kInk,
                              ),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: onTapVehicle,
                            child: Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: kLineSoft,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.edit_outlined, size: 14, color: kMute2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            isEv ? '현재 배터리' : '현재 잔유량',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kMuted),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.touch_app_rounded, size: 11, color: accent),
                          const SizedBox(width: 2),
                          Text(
                            '탭하여 수정',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _statBox(
                            label: isEv ? '효율' : '연비',
                            value: isEv
                                ? '${efficiency.toStringAsFixed(1)} km/kWh'
                                : '${efficiency.toStringAsFixed(1)} km/L',
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _statBox(
                            label: isEv ? '배터리' : '연료탱크',
                            value: isEv
                                ? '${tankCapacity.toStringAsFixed(0)} kWh'
                                : '${tankCapacity.toStringAsFixed(0)} L',
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 2) divider
          Container(
            height: 1, color: kLineSoft,
            margin: const EdgeInsets.fromLTRB(0, 16, 0, 14),
          ),
          // 3) 선호 조건 타이틀 + chip
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 13, color: kMuted),
              const SizedBox(width: 6),
              Text(isEv ? '충전 선호 조건' : '주유 선호 조건',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              _prefChip(
                icon: Icons.add_road_rounded,
                label: '고속도로',
                active: highwayOnly,
                accent: accent,
                accentLight: modeAccentLight(isEv),
                onTap: onToggleHighway,
              ),
              if (isEv) ...[
                _prefChip(
                  icon: Icons.bolt_rounded,
                  label: '급속',
                  active: chargerMode == 'FAST',
                  accent: accent,
                  accentLight: modeAccentLight(isEv),
                  onTap: () => onChangeChargerMode?.call('FAST'),
                ),
                _prefChip(
                  icon: Icons.electrical_services_rounded,
                  label: '완속',
                  active: chargerMode == 'SLOW',
                  accent: accent,
                  accentLight: modeAccentLight(isEv),
                  onTap: () => onChangeChargerMode?.call('SLOW'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBox({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kLineSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800,
                color: kInk, letterSpacing: -0.2,
              ),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _prefChip({
    required IconData icon, required String label,
    required bool active, required Color accent, required Color accentLight,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: active ? accentLight : kLineSoft,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: active ? accent.withValues(alpha: 0.22) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: active ? accent : kInk2),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700,
                  color: active ? accent : kInk2, letterSpacing: -0.1,
                )),
          ],
        ),
      ),
    );
  }
}
