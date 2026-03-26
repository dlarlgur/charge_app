import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/navigation_util.dart';

const _kPrimary = Color(0xFF1D9E75);
const _kPrimaryLight = Color(0xFFE1F5EE);
const _kPrimaryDark = Color(0xFF04342C);
const _kDanger = Color(0xFFE24B4A);

class AiResultScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  final String destinationName;
  final String? routeSummary;

  const AiResultScreen({
    super.key,
    required this.data,
    required this.destinationName,
    this.routeSummary,
  });

  static final _wonFmt = NumberFormat('#,###', 'ko_KR');

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _i(dynamic v) {
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final computed =
        data['computed'] is Map ? data['computed'] as Map<String, dynamic> : null;
    final rec = data['recommendation'] is Map
        ? data['recommendation'] as Map<String, dynamic>
        : null;
    final station =
        rec?['station'] is Map ? rec!['station'] as Map<String, dynamic> : null;
    final metrics =
        rec?['metrics'] is Map ? rec!['metrics'] as Map<String, dynamic> : null;
    final uiMessage = rec?['ui_message']?.toString() ?? '';
    final nav =
        data['navigation'] is Map ? data['navigation'] as Map<String, dynamic> : null;
    final dest =
        nav?['destination'] is Map ? nav!['destination'] as Map<String, dynamic> : null;
    final alternatives = data['alternatives'] is List
        ? data['alternatives'] as List<dynamic>
        : const [];
    final comparison = data['comparison'] is Map
        ? data['comparison'] as Map<String, dynamic>
        : null;
    final onRouteBlock = comparison?['on_route'] is Map
        ? comparison!['on_route'] as Map<String, dynamic>
        : null;
    final orStation = onRouteBlock?['station'] is Map
        ? onRouteBlock!['station'] as Map<String, dynamic>
        : null;
    final orMetrics = onRouteBlock?['metrics'] is Map
        ? onRouteBlock!['metrics'] as Map<String, dynamic>
        : null;

    final stLat = _d(station?['lat']);
    final stLng = _d(station?['lng']);
    final stName = station?['name']?.toString() ?? '추천 주유소';
    final stAddr = station?['address']?.toString();
    final priceL = _d(station?['price_won_per_liter']);
    final destLat = _d(dest?['lat']);
    final destLng = _d(dest?['lng']);

    final orName = orStation?['name']?.toString() ?? '';
    final orAddr = orStation?['address']?.toString();
    final orLat = _d(orStation?['lat']);
    final orLng = _d(orStation?['lng']);
    final orPrice = _d(orStation?['price_won_per_liter']);

    final diffWon = comparison != null
        ? _i(comparison['recommended_vs_on_route_won'])
        : 0;
    final netSavings = metrics != null ? _i(metrics['net_savings_won']) : 0;
    final goalL = _d(computed?['goal_liters']);
    final avgPrice = _d(computed?['avg_price_won_per_liter_used']);
    final avgSrc = computed?['avg_price_source']?.toString();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1a1a1a)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '분석 결과',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1a1a1a)),
            ),
            if (routeSummary != null)
              Text(
                routeSummary!,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF999999)),
              ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── AI 분석 메시지 ──
          if (uiMessage.isNotEmpty) ...[
            _AiMessageCard(message: uiMessage),
            const SizedBox(height: 12),
          ],

          // ── 추천 주유소 카드 ──
          _RecCard(
            stName: stName,
            stAddr: stAddr,
            priceL: priceL,
            metrics: metrics,
            netSavings: netSavings,
            goalL: goalL,
            avgPrice: avgPrice,
            avgSrc: avgSrc,
            stLat: stLat,
            stLng: stLng,
            destLat: destLat,
            destLng: destLng,
            destinationName: destinationName,
            wonFmt: _wonFmt,
            onNavViaWaypoint: (stLat != null &&
                    stLng != null &&
                    destLat != null &&
                    destLng != null)
                ? () => showViaWaypointNavigationSheet(
                      context,
                      waypointLat: stLat,
                      waypointLng: stLng,
                      waypointName: stName,
                      destinationLat: destLat,
                      destinationLng: destLng,
                      destinationName: destinationName,
                    )
                : null,
            onNavStation: (stLat != null && stLng != null)
                ? () => showNavigationSheet(context,
                      lat: stLat, lng: stLng, name: stName)
                : null,
          ),
          const SizedBox(height: 12),

          // ── 경로상 비교 카드 ──
          if (orStation != null && orName.isNotEmpty) ...[
            _CompareCard(
              orName: orName,
              orAddr: orAddr,
              orPrice: orPrice,
              orMetrics: orMetrics,
              diffWon: diffWon,
              orLat: orLat,
              orLng: orLng,
              wonFmt: _wonFmt,
              onNav: (orLat != null && orLng != null)
                  ? () => showNavigationSheet(context,
                        lat: orLat, lng: orLng, name: orName)
                  : null,
            ),
            const SizedBox(height: 12),
          ],

          // ── 다른 후보 ──
          if (alternatives.isNotEmpty) ...[
            _AltList(alternatives: alternatives, wonFmt: _wonFmt),
          ],
        ],
      ),
    );
  }
}

// ─── AI 메시지 카드 ───────────────────────────────────────────────────────────

class _AiMessageCard extends StatelessWidget {
  final String message;
  const _AiMessageCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1F5EE),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    size: 12, color: _kPrimary),
              ),
              const SizedBox(width: 6),
              const Text(
                'AI 분석',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _kPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: Color(0xFF1a1a1a),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 추천 주유소 카드 ─────────────────────────────────────────────────────────

class _RecCard extends StatelessWidget {
  final String stName;
  final String? stAddr;
  final double? priceL;
  final Map<String, dynamic>? metrics;
  final int netSavings;
  final double? goalL;
  final double? avgPrice;
  final String? avgSrc;
  final double? stLat, stLng, destLat, destLng;
  final String destinationName;
  final NumberFormat wonFmt;
  final VoidCallback? onNavViaWaypoint;
  final VoidCallback? onNavStation;

  const _RecCard({
    required this.stName,
    required this.stAddr,
    required this.priceL,
    required this.metrics,
    required this.netSavings,
    required this.goalL,
    required this.avgPrice,
    required this.avgSrc,
    required this.stLat,
    required this.stLng,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    required this.wonFmt,
    required this.onNavViaWaypoint,
    required this.onNavStation,
  });

  static int _i(dynamic v) {
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final detourM = metrics != null ? _i(metrics!['detour_distance_m']) : 0;
    final fuelCost =
        metrics != null ? _i(metrics!['expected_fuel_cost_won']) : 0;
    final detourCost =
        metrics != null ? _i(metrics!['detour_cost_won']) : 0;
    final baseCost = fuelCost + detourCost + netSavings;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPrimary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 ──
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: const BoxDecoration(
              color: _kPrimaryLight,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kPrimary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '추천 주유소',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  stName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: _kPrimaryDark,
                  ),
                ),
                if (stAddr != null && stAddr!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    stAddr!,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF0F6E56)),
                  ),
                ],
              ],
            ),
          ),

          // ── 통계 3종 ──
          IntrinsicHeight(
            child: Row(
              children: [
                _StatCell(
                  value: priceL != null ? wonFmt.format(priceL!.round()) : '—',
                  label: '원/L',
                ),
                const VerticalDivider(width: 1, color: Color(0xFFEEEEEE)),
                _StatCell(
                  value: detourM >= 1000
                      ? '${(detourM / 1000).toStringAsFixed(1)}km'
                      : '${detourM}m',
                  label: '우회',
                ),
                const VerticalDivider(width: 1, color: Color(0xFFEEEEEE)),
                _StatCell(
                  value: wonFmt.format(netSavings.abs()),
                  label: netSavings >= 0 ? '원 절약' : '원 손실',
                  valueColor:
                      netSavings >= 0 ? const Color(0xFF0F6E56) : _kDanger,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),

          // ── 절약 pill ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _kPrimaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 14, color: Color(0xFF0F6E56)),
                  const SizedBox(width: 4),
                  Text(
                    '경로상 대비 ${wonFmt.format(netSavings.abs())}원 ${netSavings >= 0 ? '절약' : '추가'}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F6E56),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 비용 테이블 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEEEEEE)),
              ),
              child: Column(
                children: [
                  _CostRow(label: '예상 주유비', value: '${wonFmt.format(fuelCost)}원'),
                  const Divider(height: 1, color: Color(0xFFF5F5F5)),
                  _CostRow(label: '우회 연료비', value: '+${wonFmt.format(detourCost)}원'),
                  const Divider(height: 1, color: Color(0xFFF5F5F5)),
                  _CostRow(
                      label: '기준 비용 (경로상)',
                      value: '${wonFmt.format(baseCost > 0 ? baseCost : fuelCost + detourCost + netSavings.abs())}원'),
                  const Divider(height: 1, color: Color(0xFFF5F5F5)),
                  _CostRow(
                    label: '순 절약',
                    value: '${netSavings >= 0 ? '-' : '+'}${wonFmt.format(netSavings.abs())}원',
                    valueColor: netSavings >= 0 ? const Color(0xFF0F6E56) : _kDanger,
                  ),
                ],
              ),
            ),
          ),

          if (goalL != null || avgPrice != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Text(
                [
                  if (goalL != null)
                    '목표 주유량 약 ${goalL!.toStringAsFixed(1)}L',
                  if (avgPrice != null)
                    '기준 유가 ${wonFmt.format(avgPrice!.round())}원/L',
                  if (avgSrc != null && avgSrc!.isNotEmpty) '($avgSrc)',
                ].join(' · '),
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF999999)),
              ),
            ),
          ],

          // ── 길안내 버튼 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: onNavViaWaypoint,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.route_rounded, size: 18),
                    label: const Text(
                      '경유 길안내',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: onNavStation,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1a1a1a),
                      side: const BorderSide(color: Color(0xFFEEEEEE)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.local_gas_station_outlined,
                        size: 18),
                    label: const Text(
                      '주유소만',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
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

// ─── 경로상 비교 카드 ─────────────────────────────────────────────────────────

class _CompareCard extends StatelessWidget {
  final String orName;
  final String? orAddr;
  final double? orPrice;
  final Map<String, dynamic>? orMetrics;
  final int diffWon;
  final double? orLat, orLng;
  final NumberFormat wonFmt;
  final VoidCallback? onNav;

  const _CompareCard({
    required this.orName,
    required this.orAddr,
    required this.orPrice,
    required this.orMetrics,
    required this.diffWon,
    required this.orLat,
    required this.orLng,
    required this.wonFmt,
    required this.onNav,
  });

  static int _i(dynamic v) {
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final orTotalCost =
        orMetrics != null ? _i(orMetrics!['total_expected_cost_won']) : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '경로상 최저가',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF999999)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            orName,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w500),
          ),
          if (orAddr != null && orAddr!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(orAddr!,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF999999))),
          ],
          const SizedBox(height: 6),
          if (orPrice != null)
            Text(
              '우회 없음 · ${wonFmt.format(orPrice!.round())}원/L',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF999999)),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('총 비용',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF999999))),
                    Text(
                      '${wonFmt.format(orTotalCost)}원',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('추천 대비',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF999999))),
                    Text(
                      diffWon > 0
                          ? '+${wonFmt.format(diffWon)}원 더 비쌈'
                          : diffWon < 0
                              ? '-${wonFmt.format(-diffWon)}원 더 저렴'
                              : '거의 동일',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: diffWon > 0
                            ? _kDanger
                            : diffWon < 0
                                ? const Color(0xFF0F6E56)
                                : const Color(0xFF999999),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onNav != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onNav,
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1a1a1a)),
                icon: const Icon(Icons.navigation_rounded, size: 16),
                label: const Text('이 주유소 길찾기',
                    style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 다른 후보 리스트 ─────────────────────────────────────────────────────────

class _AltList extends StatelessWidget {
  final List<dynamic> alternatives;
  final NumberFormat wonFmt;

  const _AltList({required this.alternatives, required this.wonFmt});

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _i(dynamic v) {
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final valid =
        alternatives.where((r) => r is Map).toList();
    if (valid.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '다른 후보',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1a1a1a)),
            ),
            Text(
              '순절약 순',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Column(
            children: List.generate(valid.length, (idx) {
              final raw = Map<String, dynamic>.from(valid[idx] as Map);
              final st = raw['station'] is Map
                  ? raw['station'] as Map<String, dynamic>
                  : null;
              final m = raw['metrics'] is Map
                  ? raw['metrics'] as Map<String, dynamic>
                  : null;
              final name = st?['name']?.toString() ?? '';
              final price = _d(st?['price_won_per_liter']);
              final save = m != null ? _i(m['net_savings_won']) : 0;
              final det = m != null ? _i(m['detour_distance_m']) : 0;
              final isLast = idx == valid.length - 1;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFF5F5F5),
                          ),
                          child: Center(
                            child: Text(
                              '${idx + 2}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF999999)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF1a1a1a)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (price != null)
                                    '${wonFmt.format(price.round())}원/L',
                                  '우회 ${det >= 1000 ? '${(det / 1000).toStringAsFixed(1)}km' : '${det}m'}',
                                ].join(' · '),
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF999999)),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${save >= 0 ? '-' : '+'}${wonFmt.format(save.abs())}원',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: save >= 0
                                ? const Color(0xFF0F6E56)
                                : _kDanger,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    const Divider(
                        height: 1, color: Color(0xFFF0F0F0)),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ─── 공통 위젯들 ──────────────────────────────────────────────────────────────

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;

  const _StatCell({
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: valueColor ?? const Color(0xFF1a1a1a),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF999999)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _CostRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF999999))),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? const Color(0xFF1a1a1a),
            ),
          ),
        ],
      ),
    );
  }
}
