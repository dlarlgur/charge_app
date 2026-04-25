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
const _kPurple = Color(0xFF7B5EA7);
const _kTeal = Color(0xFF00897B);

/// recommendation_label → (배지 텍스트, 색상)
(String, Color) _labelInfo(String? label, Color defaultColor) {
  switch (label) {
    case 'optimal':   return ('AI 추천',   defaultColor);
    case 'safe':      return ('안전 추천',  _kGreen);
    case 'cheapest':  return ('가성비',     _kOrange);
    case 'fastest':   return ('빠른 도착',  _kPurple);
    case 'spacious':  return ('여유 있음',  _kTeal);
    default:          return ('AI 추천',   defaultColor);
  }
}

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
                    recommendationLabel: recommended['recommendation_label']?.toString(),
                  ),
                  if (alternatives.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      '다른 후보',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kGrey),
                    ),
                    const SizedBox(height: 8),
                    ...alternatives.map((alt) {
                      final altLabel = alt['recommendation_label']?.toString();
                      final (_, altColor) = _labelInfo(altLabel, _kOrange);
                      final altLight = Color.lerp(altColor, Colors.white, 0.92) ?? _kOrangeLight;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _StationCard(
                          station: alt,
                          isRecommended: false,
                          chargerType: chargerType,
                          accentColor: altColor,
                          accentLight: altLight,
                          onMapTap: onStationMapTap != null ? () => onStationMapTap!(alt) : null,
                          originLat: originLat,
                          originLng: originLng,
                          destLat: destLat,
                          destLng: destLng,
                          destName: destName,
                          recommendationLabel: altLabel,
                        ),
                      );
                    }),
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
  final String? recommendationLabel;

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
    this.recommendationLabel,
  });

  @override
  State<_StationCard> createState() => _StationCardState();
}

class _StationCardState extends State<_StationCard> {
  // null=미결정, true=받기, false=나중에
  bool? _watchDecision;
  bool _isExpanded = false;
  final Map<String, bool?> _subWatchDecisions = {};

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

  Widget _buildGroupedRow(Map<String, dynamic> gs) {
    final gsStatId = gs['statId']?.toString();
    final gsOperator = gs['operator']?.toString() ?? '';
    final gsAvail = (gs['available_count'] as num?)?.toInt() ?? 0;
    final gsTotal = (gs['total_count'] as num?)?.toInt() ?? 0;
    final gsUnitPrice = (gs['unit_price'] as num?)?.toInt();
    final gsLat = (gs['lat'] as num?)?.toDouble();
    final gsLng = (gs['lng'] as num?)?.toDouble();
    final gsName = gs['name']?.toString() ?? '';
    final gsWatchDecision = gsStatId != null ? _subWatchDecisions[gsStatId] : null;
    final accentColor = widget.accentColor;
    final canNavigate = gsLat != null && gsLng != null &&
        widget.originLat != null && widget.destLat != null;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Info row: status + operator + price (액션 버튼 분리) ──
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: gsAvail > 0 ? _kGreen : _kOrange,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$gsAvail/$gsTotal',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: gsAvail > 0 ? _kGreen : _kOrange,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  gsOperator,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (gsUnitPrice != null) ...[
                const SizedBox(width: 6),
                Text(
                  '${_wonFmt.format(gsUnitPrice)}원',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // ── Action row: [bell] [상세] [길안내] — 44pt 터치 타깃 ──
          Row(
            children: [
              if (gsStatId != null) ...[
                Builder(builder: (ctx) => _ActionIconBtn(
                  icon: gsWatchDecision == true
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  iconColor: gsWatchDecision == true ? accentColor : _kGrey,
                  fillColor: gsWatchDecision == true
                      ? accentColor.withOpacity(0.1)
                      : const Color(0xFFEEEEEE),
                  onTap: () async {
                    final existingSession = WatchService().session;
                    if (existingSession != null && existingSession.statId == gsStatId) {
                      if (ctx.mounted) {
                        await showWatchAlreadyActiveDialog(ctx, stationName: existingSession.stationName);
                      }
                      return;
                    }
                    if (existingSession != null && ctx.mounted) {
                      final switchOk = await showWatchSwitchDialog(
                        ctx, currentStationName: existingSession.stationName);
                      if (!switchOk || !ctx.mounted) return;
                      await WatchService().stop();
                    }
                    if (!ctx.mounted) return;
                    final accepted = await showDialog<bool>(
                      context: ctx,
                      builder: (dCtx) => _WatchDialog(etaMin: null, accentColor: accentColor),
                    );
                    if (accepted != null && mounted) {
                      setState(() => _subWatchDecisions[gsStatId] = accepted);
                      if (accepted) {
                        WatchService().start(
                          statId: gsStatId,
                          stationName: gsName,
                          etaMin: 0,
                          currentAvail: gsAvail,
                        );
                      }
                    }
                  },
                )),
                const SizedBox(width: 8),
              ],
              if (gsStatId != null)
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.info_outline_rounded,
                    label: '상세',
                    color: accentColor,
                    primary: false,
                    onTap: () => Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EvDetailScreen(stationId: gsStatId),
                      ),
                    ),
                  ),
                ),
              if (gsStatId != null && canNavigate) const SizedBox(width: 8),
              if (canNavigate)
                Expanded(
                  child: Builder(builder: (ctx) => _ActionBtn(
                    icon: Icons.navigation_rounded,
                    label: '길안내',
                    color: accentColor,
                    primary: true,
                    onTap: () => showViaWaypointNavigationSheet(
                      ctx,
                      originLat: widget.originLat!,
                      originLng: widget.originLng!,
                      waypointLat: gsLat,
                      waypointLng: gsLng,
                      waypointName: gsName,
                      destinationLat: widget.destLat!,
                      destinationLng: widget.destLng!,
                      destinationName: widget.destName ?? '목적지',
                    ),
                  )),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    final name = station['name']?.toString() ?? '-';
    final address = station['address']?.toString() ?? '';
    final operator = station['operator']?.toString() ?? '';
    final availCount = (station['available_count'] as num?)?.toInt() ?? 0;
    final totalCount = (station['total_count'] as num?)?.toInt() ?? 0;
    final headingCount = (station['heading_count'] as num?)?.toInt() ?? 0;
    final unitPrice = (station['unit_price'] as num?)?.toInt();
    final detourMin = (station['detour_time_min'] as num?)?.toInt();
    final oldestMin = (station['oldest_charging_min'] as num?)?.toInt();
    final originDistM = (station['origin_distance_m'] as num?)?.toInt();
    final originEtaMin = (station['origin_eta_min'] as num?)?.toInt();
    final statId = station['statId']?.toString();
    final groupedStations = station['grouped_stations'] is List
        ? (station['grouped_stations'] as List).whereType<Map<String, dynamic>>().toList()
        : null;
    final groupedCount = (station['grouped_count'] as num?)?.toInt();
    final isGrouped = groupedStations != null && groupedStations.length > 1;

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
                if (widget.isRecommended || widget.recommendationLabel != null) ...[
                  Builder(builder: (_) {
                    final (badgeText, badgeColor) = _labelInfo(widget.recommendationLabel, accentColor);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    );
                  }),
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
                if (isGrouped || operator.isNotEmpty || address.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    isGrouped
                        ? '${groupedCount ?? groupedStations!.length}개 운영사 통합'
                            '${address.isNotEmpty ? " · $address" : ""}'
                        : [if (operator.isNotEmpty) operator, if (address.isNotEmpty) address].join(' · '),
                    style: const TextStyle(fontSize: 12, color: _kGrey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                if (headingCount > 0) ...[
                  _HeadingBadge(headingCount: headingCount, availCount: availCount),
                  const SizedBox(height: 8),
                ],
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
                // ── 그룹 운영사 펼치기 ──
                if (isGrouped) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    child: Row(
                      children: [
                        Text(
                          _isExpanded
                              ? '운영사 접기'
                              : '${groupedCount ?? groupedStations!.length}개 운영사별 길안내',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.accentColor,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          _isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: widget.accentColor,
                        ),
                      ],
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: _isExpanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              children: groupedStations!
                                  .map((gs) => _buildGroupedRow(gs))
                                  .toList(),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
                if (widget.onMapTap != null ||
                    (widget.originLat != null && widget.destLat != null) ||
                    statId != null) ...[
                  const SizedBox(height: 4),
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
                  const SizedBox(height: 12),
                  // ── 보조 액션 (지도 / 상세) — 50:50 또는 단독 ──
                  if (widget.onMapTap != null || (statId != null && !isGrouped)) ...[
                    Row(
                      children: [
                        if (widget.onMapTap != null)
                          Expanded(
                            child: _ActionBtn(
                              icon: Icons.map_rounded,
                              label: '지도에서 보기',
                              color: accentColor,
                              primary: false,
                              onTap: widget.onMapTap,
                            ),
                          ),
                        if (widget.onMapTap != null && statId != null && !isGrouped)
                          const SizedBox(width: 8),
                        if (statId != null && !isGrouped)
                          Expanded(
                            child: _ActionBtn(
                              icon: Icons.info_outline_rounded,
                              label: '충전소 상세',
                              color: accentColor,
                              primary: false,
                              onTap: () {
                                Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => EvDetailScreen(stationId: statId),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  // ── Primary CTA: 길안내 (가로 풀너비, filled) ──
                  if (widget.originLat != null && widget.destLat != null)
                    Builder(builder: (ctx) => _ActionBtn(
                      icon: Icons.navigation_rounded,
                      label: '길안내 시작',
                      color: accentColor,
                      primary: true,
                      fullWidth: true,
                      onTap: () async {
                        final stLat = (station['lat'] as num?)?.toDouble();
                        final stLng = (station['lng'] as num?)?.toDouble();
                        final stName = station['name']?.toString() ?? '충전소';
                        if (stLat == null || stLng == null) return;
                        // 워치 제안 다이얼로그
                        if (statId != null && ctx.mounted) {
                          final existingSession = WatchService().session;
                          if (existingSession != null && existingSession.statId == statId) {
                            await showWatchAlreadyActiveDialog(
                              ctx,
                              stationName: existingSession.stationName,
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
                          }
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
                    )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 일관된 액션 버튼.
/// - primary=true → filled (accent bg, 흰 글자) — 메인 CTA
/// - primary=false → tonal (accent.withOpacity(0.08), accent 글자) — 보조
/// 최소 높이 44pt (Apple HIG 터치 타깃), Material InkWell 리플 포함.
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool primary;
  final bool fullWidth;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.primary = false,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : color;
    final bg = primary ? color : color.withOpacity(0.10);
    final btn = Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// 정사각 아이콘 버튼 (44×44, 알림 토글 등에 사용).
class _ActionIconBtn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color fillColor;
  final VoidCallback? onTap;

  const _ActionIconBtn({
    required this.icon,
    required this.iconColor,
    required this.fillColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fillColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 44, height: 44,
          child: Center(child: Icon(icon, size: 18, color: iconColor)),
        ),
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

/// 다른 사용자가 이 충전소로 향하는 중임을 알리는 라이브 배지.
/// avail 대비 heading이 많을수록 색상 강도가 올라가 혼잡도를 직관적으로 전달.
class _HeadingBadge extends StatefulWidget {
  final int headingCount;
  final int availCount;
  const _HeadingBadge({required this.headingCount, required this.availCount});

  @override
  State<_HeadingBadge> createState() => _HeadingBadgeState();
}

class _HeadingBadgeState extends State<_HeadingBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.55, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.headingCount;
    final a = widget.availCount;

    // 혼잡도 단계: 향하는 사람 수 vs 자리 수
    // calm  : heading < avail (자리 여유)
    // tight : heading == avail (딱 맞음)
    // crowd : heading > avail (자리 부족)
    final bool crowd = h > a;
    final bool tight = !crowd && h >= a && a > 0;

    final Color color = crowd
        ? const Color(0xFFD32F2F)        // 빨강 — 자리 부족
        : tight
            ? const Color(0xFFEF6C00)    // 진한 주황 — 딱 맞음
            : const Color(0xFF1976D2);   // 파랑 — 여유

    final String label = crowd
        ? '$h명이 향하는 중 · 자리보다 많음'
        : tight
            ? '$h명이 향하는 중 · 자리 빠듯'
            : '$h명이 향하는 중';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 라이브 신호 도트 (페이드 펄스)
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              width: 7, height: 7,
              decoration: BoxDecoration(
                color: color.withOpacity(_pulse.value),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withOpacity(_pulse.value * 0.5), blurRadius: 4, spreadRadius: 1)],
              ),
            ),
          ),
          const SizedBox(width: 7),
          Icon(Icons.directions_car_filled_rounded, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
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

