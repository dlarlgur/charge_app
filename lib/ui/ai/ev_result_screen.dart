import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/navigation_util.dart';
import '../../data/services/watch_service.dart';
import '../detail/ev_detail_screen.dart';
import '../widgets/watch_switch_dialog.dart';

const _kBlue = Color(0xFF1D6FE0);
const _kBlueLight = Color(0xFFEEF4FF);
const _kGreen = Color(0xFF1D9E75);
const _kGreenLight = Color(0xFFE1F5EE);
const _kOrange = Color(0xFFE8700A);
const _kOrangeLight = Color(0xFFFFF3E0);
const _kGrey = Color(0xFF888888);

final _wonFmt = NumberFormat('#,###', 'ko_KR');

class EvResultBody extends StatelessWidget {
  final Map<String, dynamic> data;
  final ScrollController scrollController;
  final void Function(Map<String, dynamic> station)? onStationMapTap;
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;
  final String? destName;

  const EvResultBody({
    super.key,
    required this.data,
    required this.scrollController,
    this.onStationMapTap,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
    this.destName,
  });

  @override
  Widget build(BuildContext context) {
    final recommended = data['recommended'] is Map
        ? data['recommended'] as Map<String, dynamic>
        : null;
    final alternatives = data['alternatives'] is List
        ? (data['alternatives'] as List).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    final reachableKm = (data['reachable_distance_km'] as num?)?.toDouble() ?? 0.0;
    final chargerType = data['charger_type']?.toString() ?? 'FAST';
    final totalCandidates = (data['total_candidates'] as num?)?.toInt();
    final filteredOut = (data['filtered_out_count'] as num?)?.toInt() ?? 0;

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _HandleDelegate(),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 헤더 ──
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: chargerType == 'FAST' ? _kBlueLight : _kGreenLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            chargerType == 'FAST' ? Icons.bolt_rounded : Icons.electrical_services_rounded,
                            size: 13,
                            color: chargerType == 'FAST' ? _kBlue : _kGreen,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            chargerType == 'FAST' ? '급속' : '완속',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: chargerType == 'FAST' ? _kBlue : _kGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (reachableKm > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '주행 가능 ${reachableKm.toStringAsFixed(0)}km',
                        style: const TextStyle(fontSize: 13, color: _kGrey),
                      ),
                    ],
                    if (totalCandidates != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '· 후보 $totalCandidates개',
                        style: const TextStyle(fontSize: 12, color: _kGrey),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),

                // ── AI 추천 메시지 ──
                if (recommended != null) ...[
                  _EvAiMessageBanner(message: recommended['ui_message']?.toString() ?? ''),
                  const SizedBox(height: 14),
                ],

                // ── 추천 충전소 ──
                if (recommended == null)
                  _NoStationCard(filteredOut: filteredOut)
                else ...[
                  const Text(
                    'AI 추천 충전소',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kGrey),
                  ),
                  const SizedBox(height: 8),
                  _StationCard(
                    station: recommended,
                    isRecommended: true,
                    chargerType: chargerType,
                    accentColor: chargerType == 'FAST' ? _kBlue : _kGreen,
                    accentLight: chargerType == 'FAST' ? _kBlueLight : _kGreenLight,
                    onMapTap: onStationMapTap != null ? () => onStationMapTap!(recommended) : null,
                    originLat: originLat,
                    originLng: originLng,
                    destLat: destLat,
                    destLng: destLng,
                    destName: destName,
                  ),
                  if (alternatives.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      '다른 후보',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kGrey),
                    ),
                    const SizedBox(height: 8),
                    ...alternatives.map((alt) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _StationCard(
                        station: alt,
                        isRecommended: false,
                        chargerType: chargerType,
                        accentColor: _kOrange,
                        accentLight: _kOrangeLight,
                        onMapTap: onStationMapTap != null ? () => onStationMapTap!(alt) : null,
                        originLat: originLat,
                        originLng: originLng,
                        destLat: destLat,
                        destLng: destLng,
                        destName: destName,
                      ),
                    )),
                  ],
                  if (filteredOut > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '* 이용제한 $filteredOut개소 제외됨',
                        style: const TextStyle(fontSize: 11, color: _kGrey),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NoStationCard extends StatelessWidget {
  final int filteredOut;
  const _NoStationCard({required this.filteredOut});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.ev_station_rounded, size: 36, color: _kGrey),
          const SizedBox(height: 10),
          const Text(
            '주행 가능 거리 내에\n이용 가능한 충전소가 없어요',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF444444), height: 1.4),
          ),
          if (filteredOut > 0) ...[
            const SizedBox(height: 6),
            Text(
              '(이용제한 $filteredOut개소 제외)',
              style: const TextStyle(fontSize: 12, color: _kGrey),
            ),
          ],
        ],
      ),
    );
  }
}

class _StationCard extends StatefulWidget {
  final Map<String, dynamic> station;
  final bool isRecommended;
  final String chargerType;
  final Color accentColor;
  final Color accentLight;
  final VoidCallback? onMapTap;
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;
  final String? destName;

  const _StationCard({
    required this.station,
    required this.isRecommended,
    required this.chargerType,
    required this.accentColor,
    required this.accentLight,
    this.onMapTap,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
    this.destName,
  });

  @override
  State<_StationCard> createState() => _StationCardState();
}

class _StationCardState extends State<_StationCard> {
  // null=미결정, true=받기, false=나중에
  bool? _watchDecision;

  String _buildStatusText(int availCount, int? detourMin, int? oldestMin) {
    String detourText = '';
    if (detourMin != null) {
      if (detourMin == 0) {
        detourText = '경로 이탈 없이 들를 수 있고, ';
      } else {
        detourText = '${fmtMin(detourMin)} 우회 후, ';
      }
    }
    if (availCount > 1) return '${detourText}${availCount}자리의 여유가 있어요';
    if (availCount == 1) return '${detourText}자리 1개 남았어요. 서두르세요!';
    if (oldestMin != null) return '만석이지만 ${oldestMin}분째 충전 중인 차량이 있어요';
    return '현재 만석이에요';
  }

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    final name = station['name']?.toString() ?? '-';
    final address = station['address']?.toString() ?? '';
    final operator = station['operator']?.toString() ?? '';
    final availCount = (station['available_count'] as num?)?.toInt() ?? 0;
    final totalCount = (station['total_count'] as num?)?.toInt() ?? 0;
    final unitPrice = (station['unit_price'] as num?)?.toInt();
    final detourMin = (station['detour_time_min'] as num?)?.toInt();
    final oldestMin = (station['oldest_charging_min'] as num?)?.toInt();
    final originDistM = (station['origin_distance_m'] as num?)?.toInt();
    final originEtaMin = (station['origin_eta_min'] as num?)?.toInt();
    final statId = station['statId']?.toString();

    String? originDistLabel;
    if (originDistM != null && originDistM > 0) {
      originDistLabel = originDistM >= 1000
          ? '출발지에서 ${(originDistM / 1000).toStringAsFixed(0)}km'
          : '출발지에서 ${originDistM}m';
    }

    final accentColor = widget.accentColor;
    final accentLight = widget.accentLight;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isRecommended ? accentColor : const Color(0xFFE5E5E5),
          width: widget.isRecommended ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 상단 배너 (추천 배지 + 상태) ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: accentLight,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                if (widget.isRecommended) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      'AI 추천',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    _buildStatusText(availCount, detourMin, oldestMin),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                ),
                // 워치 벨 아이콘
                if (_watchDecision != null) ...[
                  Icon(
                    _watchDecision! ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                    size: 15,
                    color: _watchDecision! ? accentColor : _kGrey,
                  ),
                  const SizedBox(width: 8),
                ],
                // 충전기 현황
                _ChargerDot(avail: availCount, total: totalCount, accentColor: accentColor),
              ],
            ),
          ),

          // ── 본문 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                ),
                if (operator.isNotEmpty || address.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    [if (operator.isNotEmpty) operator, if (address.isNotEmpty) address].join(' · '),
                    style: const TextStyle(fontSize: 12, color: _kGrey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _InfoChip(
                      icon: Icons.bolt_rounded,
                      label: unitPrice != null ? '${_wonFmt.format(unitPrice)}원/kWh' : '가격 미공개',
                      color: const Color(0xFF444444),
                    ),
                    if (originDistLabel != null)
                      _InfoChip(
                        icon: Icons.near_me_rounded,
                        label: originDistLabel,
                        color: _kGrey,
                      ),
                    if (originEtaMin != null && originEtaMin > 0)
                      _InfoChip(
                        icon: Icons.schedule_rounded,
                        label: '약 ${fmtMin(originEtaMin)} 소요',
                        color: _kGrey,
                      ),
                    if (detourMin != null && detourMin > 0)
                      _InfoChip(
                        icon: Icons.u_turn_right_rounded,
                        label: '+${fmtMin(detourMin)} 우회',
                        color: _kOrange,
                      ),
                    if (detourMin != null && detourMin == 0)
                      const _InfoChip(
                        icon: Icons.check_circle_rounded,
                        label: '경로 이탈 없음',
                        color: _kGreen,
                      ),
                  ],
                ),
                if (widget.onMapTap != null ||
                    (widget.originLat != null && widget.destLat != null) ||
                    statId != null) ...[
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
                  const SizedBox(height: 8),
                  // ── 지도/길안내 버튼 행 ──
                  if (widget.onMapTap != null || (widget.originLat != null && widget.destLat != null))
                    Row(
                      children: [
                        if (widget.onMapTap != null) ...[
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onMapTap,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.map_rounded, size: 13, color: accentColor),
                                    const SizedBox(width: 3),
                                    Text(
                                      '지도에서 경로 보기',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accentColor),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (widget.onMapTap != null && widget.originLat != null && widget.destLat != null)
                          Container(width: 1, height: 16, color: const Color(0xFFEEEEEE)),
                        if (widget.originLat != null && widget.destLat != null) ...[
                          Expanded(
                            child: Builder(builder: (ctx) => GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () async {
                                final stLat = (station['lat'] as num?)?.toDouble();
                                final stLng = (station['lng'] as num?)?.toDouble();
                                final stName = station['name']?.toString() ?? '충전소';
                                if (stLat == null || stLng == null) return;
                                // 워치 제안 다이얼로그
                                if (statId != null && ctx.mounted) {
                                  // 이미 활성 워치 세션이 있으면 분기
                                  final existingSession = WatchService().session;
                                  if (existingSession != null && existingSession.statId == statId) {
                                    // 같은 충전소 → 이미 알림 중
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        content: Text('이미 이 충전소의 자리 변동 알림을 받고 있어요.'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  } else {
                                  if (existingSession != null && ctx.mounted) {
                                    final switchOk = await showWatchSwitchDialog(
                                      ctx,
                                      currentStationName: existingSession.stationName,
                                    );
                                    if (!switchOk || !ctx.mounted) return;
                                    await WatchService().stop();
                                  }
                                  final accepted = await showDialog<bool>(
                                    context: ctx,
                                    builder: (dCtx) => _WatchDialog(
                                      etaMin: originEtaMin,
                                      accentColor: accentColor,
                                    ),
                                  );
                                  if (accepted == true) {
                                    WatchService().start(
                                      statId: statId,
                                      stationName: stName,
                                      etaMin: originEtaMin ?? 0,
                                      currentAvail: availCount,
                                    );
                                  }
                                  if (accepted != null && mounted) {
                                    setState(() => _watchDecision = accepted);
                                  }
                                  } // else
                                }
                                if (!ctx.mounted) return;
                                showViaWaypointNavigationSheet(
                                  ctx,
                                  originLat: widget.originLat!,
                                  originLng: widget.originLng!,
                                  waypointLat: stLat,
                                  waypointLng: stLng,
                                  waypointName: stName,
                                  destinationLat: widget.destLat!,
                                  destinationLng: widget.destLng!,
                                  destinationName: widget.destName ?? '목적지',
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.navigation_rounded, size: 13, color: accentColor),
                                    const SizedBox(width: 3),
                                    Text(
                                      '길안내',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accentColor),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                          ),
                        ],
                      ],
                    ),
                  // ── 상세보기 버튼 (전체 너비) ──
                  if (statId != null) ...[
                    if (widget.onMapTap != null || (widget.originLat != null && widget.destLat != null))
                      const SizedBox(height: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            builder: (_) => EvDetailScreen(stationId: statId),
                          ),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 14, color: accentColor),
                            const SizedBox(width: 5),
                            Text(
                              '충전소 상세보기',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accentColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChargerDot extends StatelessWidget {
  final int avail;
  final int total;
  final Color accentColor;

  const _ChargerDot({required this.avail, required this.total, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: avail > 0 ? _kGreen : _kOrange,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$avail/$total',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: avail > 0 ? _kGreen : _kOrange,
          ),
        ),
        const Text(' 가용', style: TextStyle(fontSize: 11, color: _kGrey)),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _HandleDelegate extends SliverPersistentHeaderDelegate {
  @override double get minExtent => 24;
  @override double get maxExtent => 24;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => false;
}

// ── EV 사용자 선택 모드 리스트 ──
class EvSelectList extends StatelessWidget {
  final List<Map<String, dynamic>> candidates;
  final String chargerType;
  final ScrollController scrollController;
  final void Function(Map<String, dynamic>) onSelect;

  const EvSelectList({
    required this.candidates,
    required this.chargerType,
    required this.scrollController,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = chargerType == 'FAST' ? _kBlue : _kGreen;

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverPersistentHeader(pinned: true, delegate: _HandleDelegate()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Icon(chargerType == 'FAST' ? Icons.bolt_rounded : Icons.electrical_services_rounded,
                    size: 15, color: accentColor),
                const SizedBox(width: 5),
                Text(
                  '${chargerType == 'FAST' ? '급속' : '완속'} 충전소 ${candidates.length}개',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accentColor),
                ),
                const SizedBox(width: 6),
                const Text('· 경로 가까운 순 · 가용 우선', style: TextStyle(fontSize: 12, color: _kGrey)),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final s = candidates[i];
              final name = s['name']?.toString() ?? '-';
              final operator = s['operator']?.toString() ?? '';
              final avail = (s['available_count'] as num?)?.toInt() ?? 0;
              final total = (s['total_count'] as num?)?.toInt() ?? 0;
              final unitPrice = (s['unit_price'] as num?)?.toInt();
              final routeDistM = (s['route_distance_m'] as num?)?.toInt() ?? 0;
              final originDistM = (s['origin_distance_m'] as num?)?.toInt();
              final originEtaMin = (s['origin_eta_min'] as num?)?.toInt();
              final statusMsg = s['status_message']?.toString() ?? '';
              final isOnRoute = routeDistM <= 500;

              final originLabel = originDistM != null && originDistM > 0
                  ? (originDistM >= 1000
                      ? '출발지에서 ${(originDistM / 1000).toStringAsFixed(0)}km'
                      : '출발지에서 ${originDistM}m')
                  : null;

              return GestureDetector(
                onTap: () => onSelect(s),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOnRoute ? accentColor.withOpacity(0.4) : const Color(0xFFE5E5E5),
                    ),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (isOnRoute) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: accentColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('경로상', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Expanded(
                                  child: Text(name,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                                    overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                            if (operator.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(operator, style: const TextStyle(fontSize: 11, color: _kGrey), overflow: TextOverflow.ellipsis),
                            ],
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 7, height: 7,
                                      decoration: BoxDecoration(
                                        color: avail > 0 ? _kGreen : _kOrange,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text('$avail/$total 가용',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                        color: avail > 0 ? _kGreen : _kOrange)),
                                  ],
                                ),
                                if (originLabel != null)
                                  Text(originLabel,
                                    style: const TextStyle(fontSize: 11, color: _kGrey)),
                                if (originEtaMin != null && originEtaMin > 0)
                                  Text('약 ${fmtMin(originEtaMin)} 소요',
                                    style: const TextStyle(fontSize: 11, color: _kGrey)),
                                if (unitPrice != null)
                                  Text('${_wonFmt.format(unitPrice)}원/kWh',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF444444))),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
                    ],
                  ),
                ),
              );
            },
            childCount: candidates.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

// ── EV AI 추천 메시지 배너 ──────────────────────────────────────────────────────
class _EvAiMessageBanner extends StatelessWidget {
  final String message;
  const _EvAiMessageBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    final normalized = message.replaceAll(r'\n', '\n');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB8D0FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20, height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFD0E3FF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 12, color: _kBlue),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI 충전 분석',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kBlue)),
                const SizedBox(height: 6),
                MarkdownBody(
                  data: normalized,
                  shrinkWrap: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF1a1a1a)),
                    strong: const TextStyle(
                      fontSize: 13, height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: _kGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 워치 제안 다이얼로그 ──────────────────────────────────────────────────────────
class _WatchDialog extends StatelessWidget {
  final int? etaMin;
  final Color accentColor;

  const _WatchDialog({required this.etaMin, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.radar_rounded, size: 32, color: accentColor),
            ),
            const SizedBox(height: 16),
            const Text(
              '실시간 현황 알림',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 10),
            Text(
              etaMin != null && etaMin! > 0
                  ? '약 ${fmtMin(etaMin!)} 소요 예정이에요.\n이동하는 동안 자리 변동 시\n알림을 드릴게요.'
                  : '이동하는 동안 자리 변동 시\n알림을 드릴게요.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF666666), height: 1.65),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      '나중에',
                      style: TextStyle(color: Color(0xFF888888), fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('받기', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

