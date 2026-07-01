import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../ai_constants.dart';
import 'gauge_ring.dart';

/// Hero 카드 (리뉴얼)
/// 큰 원형 게이지(잔량 % + 가능 km + 편집 뱃지) + 차량 정보 + 효율/탱크 stat + 선호 조건 chip.
///
/// 선호 조건: 주유 = [고속도로] 만, 충전 = [급속][완속][고속도로].
///
/// 커넥티드(현대/기아/제네시스) '차에서 불러오기' 는 isConnected 일 때만 노출.
/// 이번 배포는 커넥티드 제외(호출부 isConnected=false) → 자동으로 숨겨짐.
/// 파라미터는 유지하므로 나중에 재부착 시 호출부만 isConnected=true 로 주면 됨.
class HeroCard extends StatelessWidget {
  final double currentLevel;
  final bool isEv;
  final double reachableKm;
  final String vehicleName;
  final double efficiency; // km/L or km/kWh
  final double tankCapacity; // L or kWh
  final bool highwayOnly;
  final double routeDistanceKm; // 목적지 경로 거리(km). >0 이면 도착 예상잔량 표시.
  final String? chargerMode; // 'FAST' | 'SLOW' (EV 전용)
  final VoidCallback onTapLevel;
  final VoidCallback onTapVehicle;
  final VoidCallback onToggleHighway;
  final ValueChanged<String>? onChangeChargerMode;
  // 주유 전용 — 선호 브랜드(OPINET pollDivCo 키) 멀티선택. 빈 set = 전체.
  final Set<String> preferredBrands;
  final ValueChanged<String>? onToggleBrand;
  final Widget? topHandle;

  // 선호 브랜드 칩 옵션 (키=pollDivCo, 라벨). 알뜰은 RTO 키 하나로 받고 서버 전송 시 RTX 도 확장.
  static const List<(String, String)> _gasBrandOptions = [
    ('SKE', 'SK'),
    ('GSC', 'GS'),
    ('SOL', 'S-OIL'),
    ('HDO', '현대'),
    ('RTO', '알뜰'),
  ];

  // 커넥티드 — 연동된 차량일 때만 '차에서 불러오기' 노출.
  final bool isConnected;
  final bool isFetching; // 차량 상태 조회 중
  final DateTime? lastSyncedAt; // 마지막으로 차에서 불러온 시각
  final VoidCallback? onFetchFromCar;

  const HeroCard({
    super.key,
    required this.currentLevel,
    required this.isEv,
    required this.reachableKm,
    required this.vehicleName,
    required this.efficiency,
    required this.tankCapacity,
    required this.highwayOnly,
    this.routeDistanceKm = 0,
    required this.chargerMode,
    required this.onTapLevel,
    required this.onTapVehicle,
    required this.onToggleHighway,
    this.onChangeChargerMode,
    this.preferredBrands = const <String>{},
    this.onToggleBrand,
    this.topHandle,
    this.isConnected = false,
    this.isFetching = false,
    this.lastSyncedAt,
    this.onFetchFromCar,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = modeAccent(isEv);
    final accentDeep = modeAccentDeep(isEv);

    return Container(
      padding: EdgeInsets.fromLTRB(18, topHandle != null ? 6 : 16, 18, 18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: isDark
            ? Border.all(color: AppColors.darkCardBorder, width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (topHandle != null) ...[
            topHandle!,
            const SizedBox(height: 4),
          ],

          // 1) 상단 row — 게이지 + 차량 정보
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: onTapLevel,
                  behavior: HitTestBehavior.opaque,
                  child: GaugeRing(
                    percent: currentLevel,
                    reachableKm: reachableKm,
                    color: accent,
                    colorDeep: accentDeep,
                    isEv: isEv,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              vehicleName.isEmpty
                                  ? (isEv ? 'EV' : '차량')
                                  : vehicleName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color:
                                    isDark ? AppColors.darkTextPrimary : kInk,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: onTapVehicle,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: kLineSoft,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.edit_outlined,
                                  size: 14, color: kMute2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isEv ? '탭하면 배터리 잔량을 바꿀 수 있어요' : '탭하면 잔량 · 목표를 바꿀 수 있어요',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: kMute2,
                        ),
                      ),
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          Expanded(
                            child: _statBox(
                              label: isEv ? '효율' : '연비',
                              value: isEv
                                  ? '${efficiency.toStringAsFixed(1)} km/kWh'
                                  : '${efficiency.toStringAsFixed(1)} km/L',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _statBox(
                              label: isEv ? '배터리' : '연료탱크',
                              value: isEv
                                  ? '${tankCapacity.toStringAsFixed(0)} kWh'
                                  : '${tankCapacity.toStringAsFixed(0)} L',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 1-b) 커넥티드 연동 차량 — '차에서 불러오기' (연동된 차만 노출, 이번 배포 숨김)
          if (isConnected) ...[
            const SizedBox(height: 12),
            _fetchFromCarButton(accent),
          ],

          const SizedBox(height: 16),

          // 목적지 도착 예상잔량 — 경로 설정 시, 현재 잔량으로 추가 주유/충전 없이 도착 시.
          if (routeDistanceKm > 0 && reachableKm > 0) ...[
            _arrivalRow(),
            const SizedBox(height: 16),
          ],

          // 2) 선호 조건 타이틀 + chip
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 14, color: kMute2),
              const SizedBox(width: 6),
              Text(
                isEv ? '충전 선호 조건' : '주유 선호 조건',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: kMute2),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // 순서: 고속도로 → (충전이면) 급속 → 완속. 주유는 고속도로 한 개만.
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
          // ── 주유 선호 브랜드 (가스 전용, 복수 선택) ──
          if (!isEv) ...[
            const SizedBox(height: 12),
            const Text('선호 브랜드 (복수 선택)',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: kMute2)),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in _gasBrandOptions)
                  _brandChip(
                    label: b.$2,
                    active: preferredBrands.contains(b.$1),
                    accent: accent,
                    accentLight: modeAccentLight(isEv),
                    onTap: () => onToggleBrand?.call(b.$1),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // 선호 브랜드 칩 (텍스트형 — 브랜드명이 곧 아이덴티티). _prefChip 와 톤 통일.
  Widget _brandChip({
    required String label,
    required bool active,
    required Color accent,
    required Color accentLight,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
            if (active) ...[
              Icon(Icons.check_rounded, size: 14, color: accent),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: active ? accent : kInk2,
                  letterSpacing: -0.1,
                )),
          ],
        ),
      ),
    );
  }

  // 목적지 도착 예상잔량 — 현재 잔량으로 추가 주유/충전 없이 도착 시.
  // 도착 예상 — 초미니멀 한 줄 + 도착% 배지 (C안, 배너 높이 최소화).
  // 점 + 상태 라벨 · Nkm / 우측에 '도착 N%' 배지. 도달 불가면 음수%(부족분).
  Widget _arrivalRow() {
    final arrivalRangeKm = reachableKm - routeDistanceKm;
    final canReach = arrivalRangeKm > 0;
    // 도착 % (부호 포함) — 도달 불가면 음수(부족분)로 표시.
    final pctSigned = reachableKm > 0
        ? (currentLevel * arrivalRangeKm / reachableKm).round().clamp(-99, 100)
        : 0;
    final low = canReach && pctSigned < 20;
    final shortfallKm = canReach ? 0 : (routeDistanceKm - reachableKm).round();
    final c = !canReach
        ? const Color(0xFFE5484D)
        : (low ? const Color(0xFFE0820A) : const Color(0xFF1D9E75));
    final action = isEv ? '충전' : '주유';
    final title = !canReach
        ? '도착 전 $action 필요'
        : (low ? '조금 빠듯하게 도착' : '여유 있게 도착');
    final detail = canReach ? '${arrivalRangeKm.round()}km 남음' : '${shortfallKm}km 부족';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: c)),
                TextSpan(
                    text: ' · $detail',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: kMute2)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('도착 $pctSigned%',
                style: TextStyle(
                    fontSize: 12,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: c)),
          ),
        ],
      ),
    );
  }

  Widget _statBox({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: kLineSoft,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: kMute2)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: kInk,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _prefChip({
    required IconData icon,
    required String label,
    required bool active,
    required Color accent,
    required Color accentLight,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
            Icon(icon, size: 14, color: active ? accent : kInk2),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: active ? accent : kInk2,
                  letterSpacing: -0.1,
                )),
          ],
        ),
      ),
    );
  }

  // 커넥티드 차량 — '차에서 현재 상태 불러오기' 버튼 (연동된 차만).
  Widget _fetchFromCarButton(Color accent) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isFetching ? null : onFetchFromCar,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.30)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isFetching)
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  )
                else
                  Icon(Icons.sync_rounded, size: 17, color: accent),
                const SizedBox(width: 8),
                Text(
                  isFetching ? '차에서 불러오는 중…' : '차에서 현재 상태 불러오기',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: -0.2,
                  ),
                ),
                if (!isFetching && lastSyncedAt != null) ...[
                  const SizedBox(width: 7),
                  Text(
                    '· ${_hhmm(lastSyncedAt!)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accent.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
