import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/helpers.dart';
import '../../../core/utils/navigation_util.dart';
import '../../../data/services/watch_service.dart';
import '../../detail/ev_detail_screen.dart';
import '../../widgets/watch_switch_dialog.dart';
import 'big_metric.dart';
import 'watch_proposal_dialog.dart';

/// EV 사용자 선택 모드 — 충전소 상세 바텀시트
class EvStationDetailSheet extends StatefulWidget {
  final Map<String, dynamic> station;
  final String stationId;
  final String chargerType;
  final double originLat;
  final double originLng;
  final double? destLat;
  final double? destLng;
  final String? destName;
  final VoidCallback onMapTap;

  const EvStationDetailSheet({
    super.key,
    required this.station,
    required this.stationId,
    required this.chargerType,
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    required this.destName,
    required this.onMapTap,
  });

  @override
  State<EvStationDetailSheet> createState() => _EvStationDetailSheetState();
}

class _EvStationDetailSheetState extends State<EvStationDetailSheet> {
  static const _kGreen = Color(0xFF1D9E75);
  static const _kBlue = Color(0xFF1D6FE0);
  static const _kOrange = Color(0xFFE8700A);
  static const _kGrey = Color(0xFF888888);

  // 자리 변동 알림은 길안내 워치(WatchService)에서 별도로 처리하므로
  // 이 시트에선 알림 토글을 노출하지 않는다 (중복·혼란 방지).

  Color get _accentColor => widget.chargerType == 'FAST' ? _kBlue : _kGreen;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.station;
    final name = s['name']?.toString() ?? '-';
    final address = s['address']?.toString() ?? '';
    final operator = s['operator']?.toString() ?? '';
    final availCount = (s['available_count'] as num?)?.toInt() ?? 0;
    final totalCount = (s['total_count'] as num?)?.toInt() ?? 0;
    final unitPrice = (s['unit_price'] as num?)?.toInt();
    final detourMin = (s['detour_time_min'] as num?)?.toInt();
    final originDistM = (s['origin_distance_m'] as num?)?.toInt();
    final originEtaMin = (s['origin_eta_min'] as num?)?.toInt();
    final statusMessage = s['status_message']?.toString();
    final limitYn = (s['limitYn'] ?? '').toString();
    final limitDetail = (s['limitDetail'] ?? '').toString();
    final note = (s['note'] ?? '').toString();
    final accentColor = _accentColor;

    // 예상 소요시간 (거리 기반 추정 — user-select 은 TMap 호출 안 함)
    String? etaLabel;
    if (originEtaMin != null && originEtaMin > 0) {
      etaLabel = '약 ${fmtMin(originEtaMin)}';
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // ── 본문 (스크롤 잠금, 컨텐츠 자체 사이즈) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. 헤더 — 이름 (큼) + 운영사 · 주소 (한 줄)
                  Text(name,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: isDark ? AppColors.darkTextPrimary : const Color(0xFF111827),
                      height: 1.25,
                      letterSpacing: -0.3,
                    )),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (operator.isNotEmpty)
                        Flexible(
                          child: Text(operator,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      if (operator.isNotEmpty && address.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        const Text('·', style: TextStyle(color: _kGrey, fontSize: 13)),
                        const SizedBox(width: 6),
                      ],
                      if (address.isNotEmpty)
                        Expanded(
                          child: Text(address,
                            style: const TextStyle(fontSize: 12, color: _kGrey),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // 2. 핵심 메트릭 4-cell 그리드 (자리·거리·도착·우회)
                  Container(
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accentColor.withValues(alpha: 0.18)),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(child: BigMetric(
                            value: '$availCount',
                            unit: '/$totalCount',
                            label: '이용가능',
                            color: availCount > 0 ? _kGreen : _kOrange,
                          )),
                          const MetricDivider(),
                          Expanded(child: BigMetric(
                            value: originDistM == null
                                ? '-'
                                : (originDistM >= 1000
                                    ? (originDistM / 1000).toStringAsFixed(0)
                                    : '$originDistM'),
                            unit: originDistM == null
                                ? ''
                                : (originDistM >= 1000 ? 'km' : 'm'),
                            label: '거리',
                            color: isDark ? AppColors.darkTextPrimary : const Color(0xFF111827),
                          )),
                          const MetricDivider(),
                          Expanded(child: BigMetric(
                            value: etaLabel ?? '-',
                            unit: '',
                            label: '예상 소요',
                            color: accentColor,
                          )),
                          const MetricDivider(),
                          Expanded(child: BigMetric(
                            value: detourMin == null
                                ? '-'
                                : (detourMin == 0 ? '없음' : '+$detourMin'),
                            unit: detourMin != null && detourMin > 0 ? '분' : '',
                            label: '우회',
                            color: detourMin != null && detourMin > 0 ? _kOrange : _kGreen,
                          )),
                        ],
                      ),
                    ),
                  ),

                  // 3. 친근 안내 + 단가 (한 라인)
                  if ((statusMessage != null && statusMessage.isNotEmpty) || unitPrice != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (statusMessage != null && statusMessage.isNotEmpty) ...[
                            Icon(Icons.tips_and_updates_rounded, size: 16, color: accentColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                statusMessage,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF374151),
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ] else
                            const Spacer(),
                          if (unitPrice != null) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.darkCard : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark ? AppColors.darkCardBorder : const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Text(
                                '${NumberFormat('#,###', 'ko_KR').format(unitPrice)}원/kWh',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? AppColors.darkTextPrimary : const Color(0xFF111827),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // 4. 메인 액션 — 지도에서 경로 보기
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: widget.onMapTap,
                      icon: const Icon(Icons.route_rounded, size: 18),
                      label: const Text('지도에서 경로 보기',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: accentColor.withValues(alpha: 0.25),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 5. 보조 액션 — 상세보기 / 길안내
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(
                                  builder: (_) => EvDetailScreen(stationId: widget.stationId),
                                ),
                              );
                            },
                            icon: Icon(Icons.info_outline_rounded, size: 16, color: accentColor),
                            label: Text('상세보기',
                              style: TextStyle(color: accentColor, fontWeight: FontWeight.w700, fontSize: 13.5)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: accentColor.withValues(alpha: 0.5), width: 1.3),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton.icon(
                            onPressed: widget.destLat != null ? () async {
                              final existingSession = WatchService().session;
                              if (existingSession != null && existingSession.statId != widget.stationId) {
                                final switchOk = await showWatchSwitchDialog(
                                  context,
                                  currentStationName: existingSession.stationName,
                                );
                                if (!switchOk || !context.mounted) return;
                                await WatchService().stop();
                                await WatchService().start(
                                  statId: widget.stationId,
                                  stationName: name,
                                  etaMin: originEtaMin ?? 0,
                                  currentAvail: availCount,
                                );
                              } else if (existingSession == null) {
                                final accepted = await showDialog<bool>(
                                  context: context,
                                  builder: (dCtx) => WatchProposalDialog(
                                    etaMin: originEtaMin,
                                    accentColor: accentColor,
                                  ),
                                );
                                if (accepted == true) {
                                  WatchService().start(
                                    statId: widget.stationId,
                                    stationName: name,
                                    etaMin: originEtaMin ?? 0,
                                    currentAvail: availCount,
                                  );
                                }
                              }
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              if (!context.mounted) return;
                              showViaWaypointNavigationSheet(
                                context,
                                originLat: widget.originLat,
                                originLng: widget.originLng,
                                waypointLat: (s['lat'] as num).toDouble(),
                                waypointLng: (s['lng'] as num).toDouble(),
                                waypointName: name,
                                destinationLat: widget.destLat!,
                                destinationLng: widget.destLng!,
                                destinationName: widget.destName ?? '목적지',
                              );
                            } : null,
                            icon: Icon(Icons.navigation_rounded, size: 16, color: accentColor),
                            label: Text('길안내',
                              style: TextStyle(color: accentColor, fontWeight: FontWeight.w700, fontSize: 13.5)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: accentColor.withValues(alpha: 0.5), width: 1.3),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // 6. 이용 안내 (조건부)
                  if (limitYn == 'Y' && limitDetail.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFFC2410C)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '이용 제한: $limitDetail',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412), height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.sticky_note_2_outlined, size: 15, color: _kGrey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              note,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
