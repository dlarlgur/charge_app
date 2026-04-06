import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/helpers.dart';
import '../../data/models/models.dart';
import '../../data/services/alert_service.dart';
import '../../data/services/api_service.dart';
import '../../providers/providers.dart';
import '../favorites/favorites_screen.dart';

String _fuelTypeLabel(String code) {
  switch (code) {
    case 'B027': return '휘발유';
    case 'B034': return '고급휘발유';
    case 'D047': return '경유';
    case 'K015': return 'LPG';
    default: return '휘발유';
  }
}

// ─── 브랜드 컬러 로고 ───
class BrandLogo extends StatelessWidget {
  final String brand;
  const BrandLogo({super.key, required this.brand});

  static const _validBrands = {'SKE', 'GSC', 'HDO', 'SOL', 'NHO', 'E1G', 'RTO', 'RTX', 'ETC'};

  @override
  Widget build(BuildContext context) {
    final assetBrand = _validBrands.contains(brand) ? brand : 'ETC';
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        'assets/brands/$assetBrand.png',
        width: 38, height: 38,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: const Color(0xFF94A3B8), borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Text(
            brand.isNotEmpty ? brand.substring(0, brand.length > 2 ? 2 : brand.length) : '?',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
          ),
        ),
      ),
    );
  }
}

// ─── 주유소 카드 ───
class GasStationCard extends ConsumerWidget {
  final GasStation station;
  final bool isTop;
  /// 1번 항목 배지 문구. 가격순이면 '최저가', 거리순이면 '최단거리'
  final String topBadgeLabel;
  final VoidCallback? onTap;

  const GasStationCard({super.key, required this.station, this.isTop = false, this.topBadgeLabel = '최저가', this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFav = ref.watch(favoritesProvider).any((f) => f['type'] == 'gas' && f['id'] == station.id);

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showAlertSheet(context, station),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isTop
              ? (isDark ? AppColors.darkGasActiveCard : AppColors.lightGasActiveCard)
              : (isDark ? AppColors.darkCard : AppColors.lightCard),
          borderRadius: BorderRadius.circular(14),
          border: isTop
              ? Border.all(color: isDark ? AppColors.darkGasActiveBorder : AppColors.gasBlue, width: 1.5)
              : Border.all(color: isDark ? AppColors.darkCardBorder : const Color(0xFFDDE3EC), width: 1),
        ),
        child: Row(
          children: [
            BrandLogo(brand: station.brand),
            const SizedBox(width: 12),
            // 이름 + 거리/브랜드
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${station.distanceText} · ${station.brandName} · ${_fuelTypeLabel(station.fuelType)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            // 가격 + 최저가 배지
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isTop)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.gasBlue,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(topBadgeLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                Text(
                  station.priceText,
                  style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700,
                    color: isTop ? AppColors.gasBlue : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => ref.read(favoritesProvider.notifier).toggle(
                id: station.id, type: 'gas', name: station.name,
                subtitle: '${station.brandName} · ${station.address}',
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 20,
                  color: isFav ? AppColors.gasBlue : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAlertSheet(BuildContext context, GasStation s) async {
    // 주유소 상세 정보를 먼저 가져와서 판매 유종 확인
    try {
      final detail = await ApiService().getGasStationDetail(s.id);
      final availableFuels = (detail['availableFuelTypes'] as List?)?.cast<String>();
      if (context.mounted) {
        showFuelTypeAlertSheet(
          context,
          stationId: s.id,
          stationName: s.name,
          availableFuels: availableFuels,
        );
      }
    } catch (e) {
      // 실패 시 현재 유종만 표시
      if (context.mounted) {
        showFuelTypeAlertSheet(
          context,
          stationId: s.id,
          stationName: s.name,
          availableFuels: [s.fuelType],
        );
      }
    }
  }
}


// ─── 유종 멀티선택 바텀시트 ───
Future<void> showFuelTypeAlertSheet(
  BuildContext context, {
  required String stationId,
  required String stationName,
  List<String>? availableFuels, // null이면 전체 4종 표시
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  const allFuels = [
    ('B027', '휘발유'),
    ('B034', '고급휘발유'),
    ('D047', '경유'),
    ('K015', 'LPG'),
  ];
  final fuels = availableFuels == null
      ? allFuels
      : allFuels.where((f) => availableFuels.contains(f.$1)).toList();

  // 현재 구독 상태로 초기화
  final initial = Set<String>.from(AlertService().subscribedFuelTypes(stationId));
  final selected = Set<String>.from(initial);

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBg : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).padding.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(stationName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('알림 받을 유종을 선택하세요 (복수 선택 가능)',
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: fuels.map((f) {
                  final isOn = selected.contains(f.$1);
                  return GestureDetector(
                    onTap: () => setS(() {
                      if (isOn) {
                        selected.remove(f.$1);
                      } else {
                        selected.add(f.$1);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: isOn
                            ? AppColors.gasBlue.withOpacity(0.12)
                            : (isDark
                                ? const Color(0x0AFFFFFF)
                                : const Color(0xFFF5F6F8)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isOn
                              ? AppColors.gasBlue
                              : (isDark
                                  ? AppColors.darkCardBorder
                                  : const Color(0xFFDEE1E6)),
                          width: isOn ? 1.5 : 0.8,
                        ),
                      ),
                      child: Text(f.$2,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isOn
                                ? AppColors.gasBlue
                                : (isDark
                                    ? AppColors.darkTextSecondary
                                    : const Color(0xFF6C757D)),
                          )),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    
                    if (selected.isEmpty) {
                      // 모든 유종 해제 → 주유소 전체 삭제
                      await AlertService().unsubscribe(stationId);
                    } else {
                      // 선택한 유종들로 한 번에 업데이트
                      final ok = await AlertService().subscribeMultiple(
                        stationId: stationId,
                        stationName: stationName,
                        fuelTypes: selected.toList(),
                      );
                      if (!ok && context.mounted) {
                        showAlertLimitDialog(context);
                        return;
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gasBlue,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('확인',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

void showAlertLimitDialog(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showDialog(
    context: context,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppColors.darkBg : Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.gasBlue.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_off_rounded, size: 32, color: AppColors.gasBlue),
            ),
            const SizedBox(height: 16),
            const Text('알림 한도 초과', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('가격 알림은 최대 3개 주유소까지\n설정할 수 있어요.\n설정 화면에서 기존 알림을 해제한 후\n다시 시도해주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.6,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.gasBlue),
                child: const Text('확인'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── EV 운영사 로고 ───
class EvOperatorLogo extends StatelessWidget {
  final String operator;
  const EvOperatorLogo({super.key, required this.operator});

  static String _toCode(String op) {
    if (op.contains('한국전력') || op.contains('한전') || op.contains('KEPCO')) return 'KEP';
    if (op.contains('환경부')) return 'ENV';
    if (op.contains('GS') || op.contains('gs')) return 'GSC';
    if (op.contains('SK')) return 'SKP';
    if (op.contains('현대') || op.contains('E-pit') || op.contains('이핏')) return 'HMC';
    if (op.contains('테슬라') || op.contains('Tesla')) return 'TSL';
    if (op.contains('차지비')) return 'CHV';
    if (op.contains('대영') || op.contains('채비')) return 'DYC';
    if (op.contains('에버온')) return 'EVR';
    if (op.contains('에스트래픽') || op.contains('S-트래픽')) return 'STR';
    if (op.contains('롯데')) return 'LTR';
    if (op.contains('클린')) return 'KLP';
    return 'ETC';
  }

  @override
  Widget build(BuildContext context) {
    final code = _toCode(operator);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        'assets/ev_operators/$code.png',
        width: 38, height: 38,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: AppColors.evGreen, borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: const Icon(Icons.ev_station, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

// ─── 충전소 카드 ───
class EvStationCard extends ConsumerWidget {
  final EvStation station;
  final bool isTop;
  final VoidCallback? onTap;

  const EvStationCard({super.key, required this.station, this.isTop = false, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFav = ref.watch(favoritesProvider).any((f) => f['type'] == 'ev' && f['id'] == station.statId);
    final sortMode = ref.watch(evFilterProvider).sort; // 2=비회원가격순, 3=회원가격순
    final secondaryColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final nonMemberHighlighted = sortMode == 2;
    final memberHighlighted = sortMode != 2; // 거리순(1)도 회원가 초록 유지

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isTop
              ? (isDark ? AppColors.darkEvActiveCard : AppColors.lightEvActiveCard)
              : (isDark ? AppColors.darkCard : AppColors.lightCard),
          borderRadius: BorderRadius.circular(12),
          border: isTop
              ? Border.all(color: isDark ? AppColors.darkEvActiveBorder : AppColors.lightEvActiveBorder, width: 0.5)
              : Border.all(color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder, width: 0.5),
        ),
        child: Row(
          children: [
            EvOperatorLogo(operator: station.operator),
            const SizedBox(width: 12),
            // 이름 + 상태 배지 + 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(station.name, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 6),
                      EvStatusBadge(station: station),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${station.distanceText} · ${station.operator} · ${station.chargerTypeText}',
                    style: Theme.of(context).textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (station.maxPowerText != null)
                  Text(
                    station.maxPowerText!,
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: isTop ? AppColors.evGreen : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                    ),
                  ),
                if (station.priceNonMemberText != null)
                  Text(
                    station.priceNonMemberText!,
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w500,
                      color: nonMemberHighlighted ? AppColors.evGreen : secondaryColor,
                    ),
                  ),
                if (station.priceMemberText != null)
                  Text(
                    station.priceMemberText!,
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w500,
                      color: memberHighlighted ? AppColors.evGreen : secondaryColor,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => ref.read(favoritesProvider.notifier).toggle(
                id: station.statId, type: 'ev', name: station.name,
                subtitle: '${station.operator} · ${station.address}',
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 20,
                  color: isFav ? AppColors.evGreen : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── EV 상태 배지 ───
class EvStatusBadge extends StatelessWidget {
  final EvStation station;
  const EvStatusBadge({super.key, required this.station});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bgColor;
    Color textColor;
    String label;

    if (station.isTesla) {
      bgColor = isDark ? const Color(0x1AE5484D) : const Color(0x12E5484D);
      textColor = const Color(0xFFE5484D);
      label = '실시간 미지원';
    } else {
      final available = station.availableCount;
      if (available > 0) {
        bgColor = isDark ? AppColors.darkBadgeAvailBg : AppColors.lightBadgeAvailBg;
        textColor = isDark ? AppColors.statusAvailable : AppColors.evGreenDark;
        label = '$available/${station.totalCount}';
      } else {
        bgColor = isDark ? const Color(0x1A9CA3AF) : const Color(0x129CA3AF);
        textColor = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
        label = station.totalCount > 0 ? '0/${station.totalCount}' : '이용불가';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: textColor)),
    );
  }
}

// ─── 필터 칩 ───
class FilterChip2 extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isEv;
  final VoidCallback? onTap;

  const FilterChip2({super.key, required this.label, this.isActive = false, this.isEv = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isEv ? AppColors.evGreen : AppColors.gasBlue;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor
              : (isDark ? const Color(0x0DFFFFFF) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(16),
          border: isActive
              ? null
              : Border.all(color: isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0), width: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
          ),
        ),
      ),
    );
  }
}

// ─── 요약 카드 (주유) ───
class GasSummaryCard extends StatelessWidget {
  final double avgPrice;
  final double priceDiff;
  final String fuelLabel;

  const GasSummaryCard({super.key, required this.avgPrice, required this.priceDiff, this.fuelLabel = '휘발유'});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? AppColors.gasSummaryGradientDark : AppColors.gasSummaryGradientLight;
    final diffSafe = (priceDiff.isNaN || priceDiff.isInfinite) ? 0.0 : priceDiff;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('주변 평균 $fuelLabel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3,
                color: isDark ? const Color(0xFF60A5FA) : AppColors.gasBlueDark)),
              const SizedBox(height: 4),
              RichText(text: TextSpan(children: [
                TextSpan(text: formatThousandsInt(avgPrice),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)),
                TextSpan(text: '원/L', style: TextStyle(fontSize: 13, color: AppColors.darkTextMuted)),
              ])),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${diffSafe >= 0 ? "▲" : "▼"} ${formatThousandsInt(diffSafe.abs())}원',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: diffSafe >= 0 ? AppColors.error : AppColors.success),
              ),
              // 오피넷 DIFF는 전일 대비 등락(원/L 단위)
              Text('전일 대비', style: TextStyle(fontSize: 10, color: AppColors.darkTextMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── 요약 카드 (충전) ───
class EvSummaryCard extends StatelessWidget {
  final int totalStations;
  final int availableStations;

  const EvSummaryCard({super.key, required this.totalStations, required this.availableStations});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? AppColors.evSummaryGradientDark : AppColors.evSummaryGradientLight;
    final rate = totalStations > 0 ? (availableStations / totalStations * 100).toInt() : 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('주변 충전소', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3,
                color: isDark ? const Color(0xFF34D399) : AppColors.evGreenDark)),
              const SizedBox(height: 4),
              RichText(text: TextSpan(children: [
                TextSpan(text: '$totalStations',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)),
                TextSpan(text: '개 · 이용가능 $availableStations개', style: TextStyle(fontSize: 13, color: AppColors.darkTextMuted)),
              ])),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$rate%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: isDark ? AppColors.success : AppColors.evGreenDark)),
              Text('가용률', style: TextStyle(fontSize: 10, color: AppColors.darkTextMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── 탭 바 (주유/충전) — 분리형 + 드래그 재정렬 ───
class GasEvTabBar extends StatefulWidget {
  final int activeIndex;
  final ValueChanged<int> onChanged;

  const GasEvTabBar({super.key, required this.activeIndex, required this.onChanged});

  @override
  State<GasEvTabBar> createState() => _GasEvTabBarState();
}

class _GasEvTabBarState extends State<GasEvTabBar> {
  // _order[i] = 위치 i에 표시할 탭 인덱스 (0=주유, 1=충전)
  List<int> _order = [0, 1];

  @override
  void initState() {
    super.initState();
    final saved = Hive.box(AppConstants.settingsBox).get(AppConstants.keyHomeTabOrder, defaultValue: 0) as int;
    if (saved == 1) _order = [1, 0];
  }

  void _swap() {
    setState(() => _order = [_order[1], _order[0]]);
    Hive.box(AppConstants.settingsBox).put(AppConstants.keyHomeTabOrder, _order[0]);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(child: _buildPosition(0)),
          const SizedBox(width: 8),
          Expanded(child: _buildPosition(1)),
        ],
      ),
    );
  }

  Widget _buildPosition(int pos) {
    final tabIdx = _order[pos];
    final isActive = widget.activeIndex == tabIdx;

    return LongPressDraggable<int>(
      data: pos,
      delay: const Duration(milliseconds: 250),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: (MediaQuery.of(context).size.width - 40) / 2,
          child: _buildPill(tabIdx, isActive, scale: 1.05),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _buildPill(tabIdx, isActive),
      ),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != pos,
        onAcceptWithDetails: (_) => _swap(),
        builder: (ctx, candidates, _) => GestureDetector(
          onTap: () => widget.onChanged(tabIdx),
          child: _buildPill(tabIdx, isActive, highlight: candidates.isNotEmpty),
        ),
      ),
    );
  }

  Widget _buildPill(int tabIdx, bool isActive, {bool highlight = false, double scale = 1.0}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEv = tabIdx == 1;
    final label = isEv ? '🔋 충전' : '⛽ 주유';
    final activeColor = isEv ? AppColors.evGreen : AppColors.gasBlue;

    final bgColor = highlight
        ? activeColor.withOpacity(0.25)
        : isActive
            ? activeColor
            : (isDark ? const Color(0x14FFFFFF) : const Color(0xFFE2E8F0));

    return Transform.scale(
      scale: scale,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: highlight ? Border.all(color: activeColor, width: 1.5) : null,
          boxShadow: isActive
              ? [BoxShadow(color: activeColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
          ),
        ),
      ),
    );
  }
}

// ─── Skeleton 로딩 카드 ───
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF1E2330) : const Color(0xFFE2E8F0);
    final highlightColor = isDark ? const Color(0xFF2A3040) : const Color(0xFFF1F5F9);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder, width: 0.5),
      ),
      child: Row(
        children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: baseColor, borderRadius: BorderRadius.circular(8))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 100, height: 14, decoration: BoxDecoration(color: baseColor, borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 6),
                Container(width: 150, height: 10, decoration: BoxDecoration(color: highlightColor, borderRadius: BorderRadius.circular(4))),
              ],
            ),
          ),
          Container(width: 60, height: 20, decoration: BoxDecoration(color: baseColor, borderRadius: BorderRadius.circular(4))),
        ],
      ),
    );
  }
}

// ─── 드럼롤 타임피커 (삼성 시계앱 방식) ───
Future<TimeOfDay?> showDrumTimePicker(BuildContext context, {required TimeOfDay initial}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (ctx) => _DrumTimePicker(initial: initial),
  );
}

class _DrumTimePicker extends StatefulWidget {
  final TimeOfDay initial;
  const _DrumTimePicker({required this.initial});
  @override
  State<_DrumTimePicker> createState() => _DrumTimePickerState();
}

class _DrumTimePickerState extends State<_DrumTimePicker> {
  late bool _isPm;
  late int _hour12; // 1~12
  late int _minute; // 0~59

  // 무한 스크롤용 버퍼 (12의 배수, 60의 배수로 중앙 설정)
  static const _kHourCount = 1200;
  static const _kMinCount  = 6000;
  static const _kHourBase  = 600; // 600 % 12 == 0
  static const _kMinBase   = 3000; // 3000 % 60 == 0

  late FixedExtentScrollController _ampmCtrl;
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minCtrl;

  int _hourIdx = 0;
  int _minIdx  = 0;

  @override
  void initState() {
    super.initState();
    final h = widget.initial.hour;
    _isPm   = h >= 12;
    _hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    _minute = widget.initial.minute;

    _ampmCtrl = FixedExtentScrollController(initialItem: _isPm ? 1 : 0);
    _hourIdx  = _kHourBase + (_hour12 - 1);
    _hourCtrl = FixedExtentScrollController(initialItem: _hourIdx);
    _minIdx   = _kMinBase + _minute;
    _minCtrl  = FixedExtentScrollController(initialItem: _minIdx);
  }

  @override
  void dispose() {
    _ampmCtrl.dispose();
    _hourCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  // 오전/오후 직접 스크롤
  void _onAmpmChanged(int idx) {
    setState(() => _isPm = idx == 1);
  }

  // 시간 스크롤: 12 한 바퀴 = 오전/오후 전환
  void _onHourChanged(int idx) {
    final oldCycles = _hourIdx ~/ 12;
    final newCycles = idx ~/ 12;
    final cycleDiff = newCycles - oldCycles;
    
    final old12 = (_hourIdx % 12) + 1;
    final new12 = (idx % 12) + 1;
    
    _hourIdx = idx;

    bool newIsPm = _isPm;
    if (cycleDiff % 2 != 0) newIsPm = !newIsPm;
    
    // 같은 cycle 내에서 11→12 또는 12→11 전환 시 오전/오후 토글
    if (cycleDiff == 0) {
      if (old12 == 11 && new12 == 12) {
        newIsPm = !_isPm; // 오전 11시→오후 12시(정오) 또는 오후 11시→오전 12시(자정)
      } else if (old12 == 12 && new12 == 11) {
        newIsPm = !_isPm; // 역방향
      }
    }

    setState(() {
      _hour12 = new12;
      _isPm   = newIsPm;
    });
    
    final shouldUpdateAmpm = (newIsPm != _isPm) || (cycleDiff % 2 != 0);
    if (shouldUpdateAmpm) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_ampmCtrl.hasClients) {
          _ampmCtrl.animateToItem(newIsPm ? 1 : 0,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });
    }
  }

  // 분 스크롤: 60 한 바퀴 = 시간 +1/-1
  void _onMinuteChanged(int idx) {
    final oldMinCycles = _minIdx ~/ 60;
    final newMinCycles = idx ~/ 60;
    final hourDelta    = newMinCycles - oldMinCycles;
    _minIdx = idx;

    if (hourDelta != 0) {
      final oldHourIdx = _hourIdx;
      final newHourIdx = _hourIdx + hourDelta;
      _hourIdx = newHourIdx;

      final oldHourCycles = oldHourIdx ~/ 12;
      final newHourCycles = newHourIdx ~/ 12;
      final ampmFlips     = newHourCycles - oldHourCycles;

      bool newIsPm = _isPm;
      if (ampmFlips % 2 != 0) newIsPm = !newIsPm;

      setState(() {
        _minute = idx % 60;
        _hour12 = (newHourIdx % 12) + 1;
        _isPm   = newIsPm;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_hourCtrl.hasClients) {
          _hourCtrl.animateToItem(newHourIdx,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
        if (ampmFlips % 2 != 0 && _ampmCtrl.hasClients) {
          _ampmCtrl.animateToItem(newIsPm ? 1 : 0,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });
    } else {
      setState(() => _minute = idx % 60);
    }
  }

  TimeOfDay get _result {
    int hour24;
    if (!_isPm) {
      hour24 = _hour12 == 12 ? 0 : _hour12;
    } else {
      hour24 = _hour12 == 12 ? 12 : _hour12 + 12;
    }
    return TimeOfDay(hour: hour24, minute: _minute);
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bgColor   = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor  = isDark ? Colors.white38 : Colors.black26;
    final accentColor = AppColors.gasBlue;

    Widget drumColumn({
      required FixedExtentScrollController ctrl,
      required int childCount,
      required void Function(int) onChanged,
      required Widget Function(int i, bool selected) itemBuilder,
      double width = 64,
    }) {
      return SizedBox(
        width: width,
        height: 160,
        child: ListWheelScrollView.useDelegate(
          controller: ctrl,
          itemExtent: 44,
          perspective: 0.003,
          diameterRatio: 1.6,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: onChanged,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: childCount,
            builder: (ctx, i) {
              final isSel = i == ctrl.selectedItem;
              return Center(child: itemBuilder(i, isSel));
            },
          ),
        ),
      );
    }

    TextStyle itemStyle(bool selected) => TextStyle(
      fontSize: selected ? 28 : 20,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
      color: selected ? accentColor : mutedColor,
    );

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('알림 시각',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
            const SizedBox(height: 16),
            Stack(
              alignment: Alignment.center,
              children: [
                // 선택 강조 배경
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 오전/오후
                    drumColumn(
                      ctrl: _ampmCtrl,
                      childCount: 2,
                      width: 52,
                      onChanged: _onAmpmChanged,
                      itemBuilder: (i, sel) => Text(
                        i == 0 ? '오전' : '오후',
                        style: itemStyle(sel).copyWith(fontSize: sel ? 22 : 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 시
                    drumColumn(
                      ctrl: _hourCtrl,
                      childCount: _kHourCount,
                      onChanged: _onHourChanged,
                      itemBuilder: (i, sel) => Text(
                        ((i % 12) + 1).toString(),
                        style: itemStyle(sel),
                      ),
                    ),
                    // 구분자
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(':',
                          style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w700, color: accentColor)),
                    ),
                    // 분
                    drumColumn(
                      ctrl: _minCtrl,
                      childCount: _kMinCount,
                      onChanged: _onMinuteChanged,
                      itemBuilder: (i, sel) => Text(
                        (i % 60).toString().padLeft(2, '0'),
                        style: itemStyle(sel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('취소', style: TextStyle(color: mutedColor)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _result),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('확인'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
