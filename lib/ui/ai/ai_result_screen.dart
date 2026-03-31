import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../../core/utils/navigation_util.dart';

const _kPrimary = Color(0xFF1D9E75);
const _kPrimaryLight = Color(0xFFE1F5EE);
const _kSelected = Color(0xFF7B61FF);
const _kSelectedLight = Color(0xFFF5F2FF);
// 통일된 색상 체계
const _kMarkerRecommend = Color(0xFFE8700A);  // 추천 (주황)
const _kMarkerRecommendLight = Color(0xFFFFF3E0);  // 추천 배경 (연한 주황)

/// 직행 대비 추가 시간이 0분이면 '우회 없음', 1분부터 '우회'.
const int _kDetourStartMinutes = 1;

int? _detourMinutesForUi(num? detourTimeMin) {
  if (detourTimeMin == null) return null;
  final m = detourTimeMin.ceil();
  return m < 0 ? 0 : m;
}

bool _detourIsNegligible({required int detourM, required num? detourTimeMin, bool? serverDetourIsNone}) {
  if (serverDetourIsNone != null) return serverDetourIsNone;
  final m = _detourMinutesForUi(detourTimeMin);
  if (m != null) return m < _kDetourStartMinutes;
  return detourM <= 500;
}

int? _meaningfulDetourMinutes(num? detourTimeMin, {bool? serverDetourIsNone}) {
  if (serverDetourIsNone == true) return null;
  final m = _detourMinutesForUi(detourTimeMin);
  if (m == null || m < _kDetourStartMinutes) return null;
  return m;
}

String _detourAltListSubtitle({required int detourM, required num? detourTimeMin, bool? serverDetourIsNone}) {
  if (_detourIsNegligible(detourM: detourM, detourTimeMin: detourTimeMin, serverDetourIsNone: serverDetourIsNone)) return '우회 없음';
  final m = _meaningfulDetourMinutes(detourTimeMin, serverDetourIsNone: serverDetourIsNone);
  if (m != null && m > 0) return '약 ${m}분 우회';
  if (detourM >= 1000) return '${(detourM / 1000).toStringAsFixed(1)}km 우회';
  if (detourM > 0) return '${detourM}m 우회';
  return '조금 우회';
}

// ─── 결과 화면 (독립 페이지로 push 할 때) ─────────────────────────────────────

class AiResultScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  final String destinationName;
  final String? routeSummary;
  final double originLat;
  final double originLng;
  final List<Map<String, dynamic>> pathPoints;

  const AiResultScreen({
    super.key,
    required this.data,
    required this.destinationName,
    this.routeSummary,
    this.originLat = 0,
    this.originLng = 0,
    this.pathPoints = const [],
  });

  @override
  Widget build(BuildContext context) {
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
            const Text('분석 결과',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1a1a1a))),
            if (routeSummary != null)
              Text(routeSummary!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
          ],
        ),
      ),
      body: AiResultBody(
        data: data,
        destinationName: destinationName,
        originLat: originLat,
        originLng: originLng,
      ),
    );
  }
}

// ─── 결과 Body ──────────────────────────────────────────────────────────────

class AiResultBody extends StatefulWidget {
  final Map<String, dynamic> data;
  final String destinationName;
  final double originLat;
  final double originLng;
  final ScrollController? scrollController;
  final String? fuelLabel;
  /// 대안 "확인" 탭 시 지도 업데이트 (서버 `via_route` 포함 시 그대로 사용)
  final void Function(Map<String, dynamic> altItem)? onAltRouteView;
  /// 대안 선택 취소 → AI 추천으로 복원 콜백
  final VoidCallback? onResetToAiRec;

  const AiResultBody({
    super.key,
    required this.data,
    required this.destinationName,
    this.originLat = 0,
    this.originLng = 0,
    this.scrollController,
    this.fuelLabel,
    this.onAltRouteView,
    this.onResetToAiRec,
  });

  @override
  State<AiResultBody> createState() => _AiResultBodyState();
}

class _AiResultBodyState extends State<AiResultBody> {
  /// 사용자가 대안에서 선택한 아이템 (null = AI 추천 유지)
  Map<String, dynamic>? _selectedAltItem;
  /// 대안 선택 시 표시할 커스텀 AI 메시지
  String? _altAiMessage;

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

  void _selectAlt(dynamic altItem) {
    if (altItem == null) {
      // 선택 취소 → AI 추천으로 복원
      setState(() { _selectedAltItem = null; _altAiMessage = null; });
      widget.onResetToAiRec?.call();
      return;
    }
    if (altItem is! Map) return;
    final st = altItem['station'];
    if (st is! Map) return;
    final lat = _d(st['lat']);
    final lng = _d(st['lng']);
    if (lat == null || lng == null) return;
    final name = st['name']?.toString() ?? '';
    final price = _d(st['price_won_per_liter'])?.round() ?? 0;
    setState(() {
      _selectedAltItem = Map<String, dynamic>.from(altItem);
      _altAiMessage = _buildAltMessage(altItem, name, price);
    });
    widget.onAltRouteView?.call(Map<String, dynamic>.from(altItem));
  }

  String _buildAltMessage(Map altItem, String name, int price) {
    final detourM = _i(altItem['detour_distance_m']);
    final savings = altItem['savings_vs_primary_won'] != null
        ? _i(altItem['savings_vs_primary_won'])
        : _i(altItem['savings_vs_on_route_won']);
    final detourTimeMin = altItem['detour_time_min'] is num ? altItem['detour_time_min'] as num : null;
    final detourIsNone = altItem['detour_is_none'] is bool ? altItem['detour_is_none'] as bool : null;
    final String detourText;
    if (_detourIsNegligible(detourM: detourM, detourTimeMin: detourTimeMin, serverDetourIsNone: detourIsNone)) {
      detourText = '우회 없음(직행과 비슷한 소요)';
    } else {
      final m = _meaningfulDetourMinutes(detourTimeMin, serverDetourIsNone: detourIsNone);
      if (m != null && m > 0) {
        detourText = '약 ${m}분 우회';
      } else if (detourM >= 1000) {
        detourText = '${(detourM / 1000).toStringAsFixed(1)}km 우회 필요';
      } else {
        detourText = '${detourM}m 우회 필요';
      }
    }

    final lines = <String>[
      '$name을 선택하셨습니다.',
      '리터당 ${_wonFmt.format(price)}원, $detourText.',
    ];
    if (savings > 0) {
      lines.add('AI 추천 경로 대비 ${_wonFmt.format(savings)}원 절약됩니다.');
    } else if (savings < 0) {
      lines.add('AI 추천 경로보다 ${_wonFmt.format(-savings)}원 더 비쌉니다.');
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final computed = data['computed'] is Map ? data['computed'] as Map<String, dynamic> : null;
    final reachable = computed?['reachable'] is Map ? computed!['reachable'] as Map<String, dynamic> : null;
    final onRoute = data['on_route'] is Map ? data['on_route'] as Map<String, dynamic> : null;
    final bestDetour = data['best_detour'] is Map ? data['best_detour'] as Map<String, dynamic> : null;
    final rec = data['recommendation'] is Map ? data['recommendation'] as Map<String, dynamic> : null;
    final nav = data['navigation'] is Map ? data['navigation'] as Map<String, dynamic> : null;
    final dest = nav?['destination'] is Map ? nav!['destination'] as Map<String, dynamic> : null;

    final choice = rec?['choice']?.toString() ?? 'on_route';
    final uiMessage = _altAiMessage ?? rec?['ui_message']?.toString() ?? '';

    final onRouteSt = onRoute?['station'] is Map ? onRoute!['station'] as Map<String, dynamic> : null;
    final detourSt = bestDetour?['station'] is Map ? bestDetour!['station'] as Map<String, dynamic> : null;

    final destLat = _d(dest?['lat']);
    final destLng = _d(dest?['lng']);
    final goalL = _d(computed?['goal_liters']);

    // on_route 데이터
    final orLat = _d(onRouteSt?['lat']);
    final orLng = _d(onRouteSt?['lng']);
    final orPrice = _d(onRouteSt?['price_won_per_liter']);
    final orCost = _i(onRoute?['expected_cost_won']);
    final orDetourM = _i(onRoute?['detour_distance_m']);
    final orDetourTimeMin =
        (onRoute?['detour_is_none'] == true)
            ? 0
            : (onRoute?['detour_time_min'] is num ? onRoute!['detour_time_min'] as num : null);

    // best_detour 데이터
    final dtLat = _d(detourSt?['lat']);
    final dtLng = _d(detourSt?['lng']);
    final dtPrice = _d(detourSt?['price_won_per_liter']);
    final dtCost = _i(bestDetour?['expected_cost_won']);
    final dtDetourM = _i(bestDetour?['detour_distance_m']);
    final dtDetourTimeMin =
        (bestDetour?['detour_is_none'] == true)
            ? 0
            : (bestDetour?['detour_time_min'] is num ? bestDetour!['detour_time_min'] as num : null);
    final dtTimeMinsBanner = _meaningfulDetourMinutes(dtDetourTimeMin);
    final dtSavings = _i(bestDetour?['savings_vs_on_route_won']);

    // 우회가 경로상보다 비싸면 숨김
    final showDetour = detourSt != null &&
        (dtPrice == null || orPrice == null || dtPrice <= orPrice);

    final hasOverride = _selectedAltItem != null;
    // 서버 choice가 누락/불일치여도 on_route가 비어 있고 detour가 있으면 detour를 메인으로 강제
    final forceDetourAsPrimary = onRouteSt == null && detourSt != null;
    final aiRecIsDetour = forceDetourAsPrimary || (choice == 'best_detour' && showDetour);
    final noStationToRecommend = onRouteSt == null && detourSt == null;

    // ── Primary 카드 (상단) 계산
    _CardInfo primary;
    if (hasOverride) {
      final ovSt = _selectedAltItem!['station'] is Map
          ? Map<String, dynamic>.from(_selectedAltItem!['station'] as Map)
          : <String, dynamic>{};
      primary = _CardInfo(
        name: ovSt['name']?.toString() ?? '',
        addr: ovSt['address']?.toString(),
        lat: _d(ovSt['lat']),
        lng: _d(ovSt['lng']),
        price: _d(ovSt['price_won_per_liter']),
        cost: _i(_selectedAltItem!['expected_cost_won']),
        detourM: _i(_selectedAltItem!['detour_distance_m']),
        detourTimeMin: _selectedAltItem!['detour_time_min'] is num
            ? ((_selectedAltItem!['detour_is_none'] == true) ? 0 : _selectedAltItem!['detour_time_min'] as num)
            : null,
        savings: 0,
        tag: '선택됨',
        tagColor: _kSelected,
        isAiRec: false,
        isUserSelected: true,
      );
    } else if (aiRecIsDetour) {
      primary = _CardInfo(
        name: _stationNameFrom(detourSt),
        addr: detourSt['address']?.toString(),
        lat: dtLat,
        lng: dtLng,
        price: dtPrice,
        cost: dtCost,
        detourM: dtDetourM,
        detourTimeMin: dtDetourTimeMin,
        savings: dtSavings,
        tag: '우회 최저가',
        tagColor: const Color(0xFF1D6FE0),
        isAiRec: true,
        isUserSelected: false,
        rawData: bestDetour,
      );
    } else {
      primary = _CardInfo(
        name: _stationNameFrom(onRouteSt),
        addr: onRouteSt?['address']?.toString(),
        lat: orLat,
        lng: orLng,
        price: orPrice,
        cost: orCost,
        detourM: orDetourM,
        detourTimeMin: orDetourTimeMin,
        savings: 0,
        tag: '경로상 최저가',
        tagColor: const Color(0xFF555555),
        isAiRec: true,
        isUserSelected: false,
        rawData: onRoute,
      );
    }

    // ── Secondary 카드 (하단 참고용) 계산
    _CardInfo? secondary;
    if (hasOverride) {
      // 오버라이드 시: AI 추천을 참고용으로 표시
      if (aiRecIsDetour) {
        secondary = _CardInfo(
          name: _stationNameFrom(detourSt),
          addr: detourSt['address']?.toString(),
          lat: dtLat,
          lng: dtLng,
          price: dtPrice,
          cost: dtCost,
          detourM: dtDetourM,
          detourTimeMin: dtDetourTimeMin,
          savings: dtSavings,
          tag: 'AI 추천',
          tagColor: _kPrimary,
          isAiRec: false,
          isUserSelected: false,
        );
      } else if (onRouteSt != null) {
        secondary = _CardInfo(
          name: _stationNameFrom(onRouteSt),
          addr: onRouteSt['address']?.toString(),
          lat: orLat,
          lng: orLng,
          price: orPrice,
          cost: orCost,
          detourM: orDetourM,
          detourTimeMin: orDetourTimeMin,
          savings: 0,
          tag: 'AI 추천',
          tagColor: _kPrimary,
          isAiRec: false,
          isUserSelected: false,
        );
      }
    } else if (aiRecIsDetour && onRouteSt != null) {
      // 우회 AI 추천 → 경로상 최저가를 하단 참고로
      secondary = _CardInfo(
        name: _stationNameFrom(onRouteSt),
        addr: onRouteSt['address']?.toString(),
        lat: orLat,
        lng: orLng,
        price: orPrice,
        cost: orCost,
        detourM: orDetourM,
        detourTimeMin: orDetourTimeMin,
        savings: 0,
        tag: '경로상 최저가',
        tagColor: const Color(0xFF555555),
        isAiRec: false,
        isUserSelected: false,
        rawData: onRoute,
      );
    } else if (!aiRecIsDetour && showDetour) {
      // 경로 AI 추천 → 우회 최저가를 하단 참고로
      secondary = _CardInfo(
        name: _stationNameFrom(detourSt),
        addr: detourSt['address']?.toString(),
        lat: dtLat,
        lng: dtLng,
        price: dtPrice,
        cost: dtCost,
        detourM: dtDetourM,
        detourTimeMin: dtDetourTimeMin,
        savings: dtSavings,
        tag: '우회 최저가',
        tagColor: const Color(0xFF1D6FE0),
        isAiRec: false,
        isUserSelected: false,
        rawData: bestDetour,
      );
    }

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(16, widget.scrollController != null ? 4 : 8, 16, 32),
      children: [
        // 드래그 핸들
        if (widget.scrollController != null)
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

        // ── 유종 칩 ──
        if (widget.fuelLabel != null) ...[
          _FuelChip(label: widget.fuelLabel!),
          const SizedBox(height: 10),
        ],

        // ── 도달 가능 범위 안내 (상단 노출) ──
        if (reachable != null && reachable['enabled'] == true) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFD95A), width: 1),
            ),
            child: Row(
              children: const [
                Icon(Icons.local_gas_station, size: 15, color: Color(0xFF856404)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '현재 연료로 갈 수 있는 거리 안의 주유소만 표시했어요.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF856404)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ── AI 메시지 ──
        if (uiMessage.isNotEmpty) ...[
          _AiMessageBanner(message: uiMessage),
          const SizedBox(height: 12),
        ],

        // ── 비교 테이블 (AI 추천 원본) / 카드 (사용자 대안 선택 시) ──
        if (!hasOverride && !noStationToRecommend) ...[
          _StationComparisonSection(
            onRouteName: _stationNameFrom(onRouteSt),
            onRoutePrice: orPrice,
            onRouteCost: orCost,
            onRouteDetourM: orDetourM,
            onRouteDetourTimeMin: orDetourTimeMin,
            onRouteLat: orLat,
            onRouteLng: orLng,
            onRouteFuelType: onRouteSt?['fuel_type']?.toString(),
            showDetour: showDetour,
            detourName: showDetour ? _stationNameFrom(detourSt) : '',
            detourPrice: dtPrice,
            detourCost: dtCost,
            dtDetourM: dtDetourM,
            dtDetourTimeMin: dtDetourTimeMin,
            dtLat: dtLat,
            dtLng: dtLng,
            detourFuelType: detourSt?['fuel_type']?.toString(),
            aiRecIsDetour: aiRecIsDetour,
            dtSavings: dtSavings,
            dtDetourMins: dtTimeMinsBanner,
            fuelLabel: widget.fuelLabel,
            destLat: destLat,
            destLng: destLng,
            destinationName: widget.destinationName,
            originLat: widget.originLat,
            originLng: widget.originLng,
            wonFmt: _wonFmt,
            onViewOnMapRoute: onRoute != null && widget.onAltRouteView != null
                ? () => widget.onAltRouteView!(onRoute)
                : null,
            onViewOnMapDetour: bestDetour != null && widget.onAltRouteView != null
                ? () => widget.onAltRouteView!(bestDetour)
                : null,
          ),
          const SizedBox(height: 12),
        ] else if (!hasOverride && noStationToRecommend) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9E8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFE6A6)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF8A6D3B)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '현재 연료로 목적지 도달이 가능해 지금은 추천 주유소를 표시하지 않습니다.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF8A6D3B), height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          _buildCard(primary, destLat, destLng),
          const SizedBox(height: 10),
          if (secondary != null) ...[
            _buildCard(secondary, destLat, destLng),
            const SizedBox(height: 12),
          ],
        ],

        // ── 다른 후보 ──
        if (data['alternatives'] is List &&
            (data['alternatives'] as List).isNotEmpty) ...[
          _AltSection(
            alternatives: data['alternatives'] as List<dynamic>,
            wonFmt: _wonFmt,
            onSelect: _selectAlt,
            selectedItem: _selectedAltItem,
          ),
          const SizedBox(height: 12),
        ],

        // ── 기준 정보 ──
        if (goalL != null)
          Center(
            child: Text(
              '목표 주유량 약 ${goalL.toStringAsFixed(1)}L 기준',
              style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
            ),
          ),
      ],
    );
  }

  Widget _buildCard(_CardInfo c, double? destLat, double? destLng) {
    final canRestoreAiRec = _selectedAltItem != null && c.tag == 'AI 추천';
    final extraInfo = (c.savings > 0 && !c.isUserSelected)
        ? _ExtraInfo(savings: c.savings, timeMins: _meaningfulDetourMinutes(c.detourTimeMin))
        : null;
    // 지도에서 보기: rawData가 있을 때 onAltRouteView 재사용
    final onViewOnMap = (c.rawData != null && widget.onAltRouteView != null)
        ? () => widget.onAltRouteView!(c.rawData!)
        : null;
    return _OptionCard(
      tag: c.tag,
      tagColor: c.tagColor,
      isAiRec: c.isAiRec,
      isUserSelected: c.isUserSelected,
      stName: c.name,
      stAddr: c.addr,
      priceL: c.price,
      expectedCost: c.cost,
      detourM: c.detourM,
      detourTimeMin: c.detourTimeMin,
      extraInfo: extraInfo,
      stLat: c.lat,
      stLng: c.lng,
      destLat: destLat,
      destLng: destLng,
      destinationName: widget.destinationName,
      originLat: widget.originLat,
      originLng: widget.originLng,
      wonFmt: _wonFmt,
      onViewOnMap: onViewOnMap,
      onRestoreAiRec: canRestoreAiRec
          ? () {
              setState(() {
                _selectedAltItem = null;
                _altAiMessage = null;
              });
              widget.onResetToAiRec?.call();
            }
          : null,
    );
  }
}

// ─── 카드 데이터 헬퍼 ──────────────────────────────────────────────────────────

class _CardInfo {
  final String name;
  final String? addr;
  final double? lat, lng, price;
  final int cost, detourM, savings;
  final num? detourTimeMin;
  final String tag;
  final Color tagColor;
  final bool isAiRec;
  final bool isUserSelected;
  final Map<String, dynamic>? rawData; // on_route / best_detour 원본 (지도 재드로우용)

  const _CardInfo({
    required this.name,
    required this.addr,
    required this.lat,
    required this.lng,
    required this.price,
    required this.cost,
    required this.detourM,
    required this.detourTimeMin,
    required this.savings,
    required this.tag,
    required this.tagColor,
    required this.isAiRec,
    required this.isUserSelected,
    this.rawData,
  });
}

class _ExtraInfo {
  final int savings;
  final int? timeMins;
  const _ExtraInfo({required this.savings, required this.timeMins});
}

String _fuelCodeToLabel(String? code) {
  switch (code) {
    case 'B027':
      return '휘발유';
    case 'B034':
      return '고급휘발유';
    case 'D047':
      return '경유';
    case 'K015':
      return 'LPG';
    default:
      return '';
  }
}

String _resolveFuelLabel(dynamic rawFuel, {String? fallback}) {
  final value = rawFuel?.toString().trim();
  if (value == null || value.isEmpty) return fallback ?? '—';
  final mapped = _fuelCodeToLabel(value);
  return mapped.isNotEmpty ? mapped : value;
}

String _stationNameFrom(dynamic station) {
  if (station is! Map) return '';
  final dn = station['display_name']?.toString().trim();
  if (dn != null && dn.isNotEmpty) return dn;
  return station['name']?.toString() ?? '';
}

// ─── 유종 칩 ──────────────────────────────────────────────────────────────────

class _FuelChip extends StatelessWidget {
  final String label;
  const _FuelChip({required this.label});

  static const _fuelColors = <String, Color>{
    '휘발유':    Color(0xFF1D9E75),
    '고급휘발유': Color(0xFF7B61FF),
    '경유':     Color(0xFF1D6FE0),
    'LPG':     Color(0xFFE07B1D),
  };

  static const _fuelIcons = <String, IconData>{
    '휘발유':    Icons.local_gas_station_rounded,
    '고급휘발유': Icons.local_gas_station_rounded,
    '경유':     Icons.local_gas_station_rounded,
    'LPG':     Icons.propane_tank_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final color = _fuelColors[label] ?? _kPrimary;
    final icon  = _fuelIcons[label]  ?? Icons.local_gas_station_rounded;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          '기준 분석',
          style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
        ),
      ],
    );
  }
}

// ─── AI 메시지 배너 ────────────────────────────────────────────────────────────

class _AiMessageBanner extends StatelessWidget {
  final String message;
  const _AiMessageBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final normalized = message.replaceAll(r'\n', '\n');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5FBF8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCCEEDE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20, height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: _kPrimaryLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 12, color: _kPrimary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI 분석',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kPrimary)),
                const SizedBox(height: 6),
                MarkdownBody(
                  data: normalized,
                  shrinkWrap: true,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF1a1a1a)),
                    strong: const TextStyle(
                      fontSize: 13, height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: _kPrimary,
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


// ─── 주유소 비교 테이블 섹션 ──────────────────────────────────────────────────────

class _StationComparisonSection extends StatelessWidget {
  final String onRouteName;
  final double? onRoutePrice;
  final int onRouteCost;
  final int onRouteDetourM;
  final num? onRouteDetourTimeMin;
  final double? onRouteLat;
  final double? onRouteLng;
  final String? onRouteFuelType;

  final bool showDetour;
  final String detourName;
  final double? detourPrice;
  final int detourCost;
  final int dtDetourM;
  final num? dtDetourTimeMin;
  final double? dtLat;
  final double? dtLng;
  final String? detourFuelType;

  final bool aiRecIsDetour;
  final int dtSavings;
  final int? dtDetourMins;
  final String? fuelLabel;

  final double? destLat, destLng;
  final String destinationName;
  final double originLat, originLng;
  final NumberFormat wonFmt;
  final VoidCallback? onViewOnMapRoute;
  final VoidCallback? onViewOnMapDetour;

  const _StationComparisonSection({
    required this.onRouteName,
    required this.onRoutePrice,
    required this.onRouteCost,
    required this.onRouteDetourM,
    required this.onRouteDetourTimeMin,
    required this.onRouteLat,
    required this.onRouteLng,
    required this.onRouteFuelType,
    required this.showDetour,
    required this.detourName,
    required this.detourPrice,
    required this.detourCost,
    required this.dtDetourM,
    required this.dtDetourTimeMin,
    required this.dtLat,
    required this.dtLng,
    required this.detourFuelType,
    required this.aiRecIsDetour,
    required this.dtSavings,
    required this.dtDetourMins,
    required this.fuelLabel,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    required this.originLat,
    required this.originLng,
    required this.wonFmt,
    this.onViewOnMapRoute,
    this.onViewOnMapDetour,
  });

  String _detourLabel(int detourM, num? detourTimeMin) {
    if (_detourIsNegligible(detourM: detourM, detourTimeMin: detourTimeMin)) return '우회 없음';
    final m = _meaningfulDetourMinutes(detourTimeMin);
    if (m != null && m > 0) return '+${m}분';
    if (detourM >= 1000) return '+${(detourM / 1000).toStringAsFixed(1)}km';
    if (detourM > 0) return '+${detourM}m';
    return '조금 우회';
  }

  @override
  Widget build(BuildContext context) {
    final bool hasOnRoute = onRouteName.trim().isNotEmpty;
    final bool hasBoth = hasOnRoute && showDetour && detourName.isNotEmpty;
    // 서버가 한쪽만 내려줘도 표는 그림(빈 열은 —)
    final bool showComparisonTable =
        hasOnRoute || (showDetour && detourName.trim().isNotEmpty);

    // 추천 주유소 결정
    // on_route가 없으면 detour(우회 최저가)를 추천 카드로 강제
    final recIsDetour = (!hasOnRoute && showDetour && detourName.isNotEmpty) || (aiRecIsDetour && hasBoth);
    final recName = recIsDetour ? detourName : onRouteName;
    final recPrice = recIsDetour ? detourPrice : onRoutePrice;
    final recCost = recIsDetour ? detourCost : onRouteCost;
    final recDetourM = recIsDetour ? dtDetourM : onRouteDetourM;
    final recDetourTimeMin = recIsDetour ? dtDetourTimeMin : onRouteDetourTimeMin;
    final recLat = recIsDetour ? dtLat : onRouteLat;
    final recLng = recIsDetour ? dtLng : onRouteLng;
    final onViewRec = recIsDetour ? onViewOnMapDetour : onViewOnMapRoute;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 추천 카드 ──
        _RecommendedCard(
          name: recName,
          price: recPrice,
          cost: recCost,
          detourM: recDetourM,
          detourTimeMin: recDetourTimeMin,
          stLat: recLat,
          stLng: recLng,
          destLat: destLat,
          destLng: destLng,
          destinationName: destinationName,
          originLat: originLat,
          originLng: originLng,
          isDetour: recIsDetour,
          wonFmt: wonFmt,
          onViewOnMap: onViewRec,
        ),

        // ── 비교 테이블 (한쪽만 있어도 추천 정보 표 형태로 표시) ──
        if (showComparisonTable) ...[
          const SizedBox(height: 12),
          _ComparisonTable(
            onRouteName: onRouteName,
            onRoutePrice: onRoutePrice,
            onRouteCost: onRouteCost,
            onRouteDetourLabel: _detourLabel(onRouteDetourM, onRouteDetourTimeMin),
            onRouteFuelLabel: _resolveFuelLabel(onRouteFuelType, fallback: fuelLabel),
            detourName: detourName,
            detourPrice: detourPrice,
            detourCost: detourCost,
            detourDetourLabel: _detourLabel(dtDetourM, dtDetourTimeMin),
            detourFuelLabel: _resolveFuelLabel(detourFuelType, fallback: fuelLabel),
            savings: dtSavings,
            detourMins: dtDetourMins,
            aiRecIsDetour: aiRecIsDetour,
            fuelLabel: fuelLabel,
            wonFmt: wonFmt,
            onViewOnMapRoute: onViewOnMapRoute,
            onViewOnMapDetour: onViewOnMapDetour,
            onRouteLat: onRouteLat,
            onRouteLng: onRouteLng,
            dtLat: dtLat,
            dtLng: dtLng,
            destLat: destLat,
            destLng: destLng,
            destinationName: destinationName,
            originLat: originLat,
            originLng: originLng,
          ),
        ],
      ],
    );
  }
}

// ── 추천 주유소 카드 ──────────────────────────────────────────────────────────

class _RecommendedCard extends StatelessWidget {
  final String name;
  final double? price;
  final int cost;
  final int detourM;
  final num? detourTimeMin;
  final double? stLat, stLng, destLat, destLng;
  final String destinationName;
  final double originLat, originLng;
  final bool isDetour;
  final NumberFormat wonFmt;
  final VoidCallback? onViewOnMap;

  const _RecommendedCard({
    required this.name,
    required this.price,
    required this.cost,
    required this.detourM,
    required this.detourTimeMin,
    required this.stLat,
    required this.stLng,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    required this.originLat,
    required this.originLng,
    required this.isDetour,
    required this.wonFmt,
    this.onViewOnMap,
  });

  @override
  Widget build(BuildContext context) {
    final canNav = stLat != null && stLng != null && destLat != null && destLng != null;
    final isNegligible = _detourIsNegligible(detourM: detourM, detourTimeMin: detourTimeMin);
    final detourMins = _meaningfulDetourMinutes(detourTimeMin);

    return Container(
      decoration: BoxDecoration(
        color: _kMarkerRecommendLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kMarkerRecommend, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _kMarkerRecommend, borderRadius: BorderRadius.circular(5)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 11, color: Colors.white),
                      SizedBox(width: 4),
                      Text('추천',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFCCEEDE)),
                  ),
                  child: Text(
                    isDetour ? '우회 최저가' : '경로상 최저가',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF444444)),
                  ),
                ),
                const Spacer(),
                if (onViewOnMap != null)
                  GestureDetector(
                    onTap: onViewOnMap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCCEEDE)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined, size: 13, color: _kPrimary),
                          SizedBox(width: 3),
                          Text('지도', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kPrimary)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 주유소명
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1a1a1a))),
          ),

          const SizedBox(height: 12),

          // 핵심 수치 3개
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCCEEDE)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    _RecStatCell(
                      icon: Icons.local_gas_station_rounded,
                      iconColor: _kMarkerRecommend,
                      value: price != null ? '${wonFmt.format(price!.round())}원' : '—',
                      label: '리터당 가격',
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFDDDDDD)),
                    _RecStatCell(
                      icon: Icons.access_time_rounded,
                      iconColor: isNegligible ? _kMarkerRecommend : const Color(0xFFE07B1D),
                      value: isNegligible
                          ? '우회 없음'
                          : (detourMins != null ? '+${detourMins}분' : '조금 우회'),
                      label: '직행 대비',
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFDDDDDD)),
                    _RecStatCell(
                      icon: Icons.payments_outlined,
                      iconColor: _kMarkerRecommend,
                      value: cost > 0 ? '${wonFmt.format(cost)}원' : '—',
                      label: '예상 주유비',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 길안내 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: canNav
                    ? () => showViaWaypointNavigationSheet(
                          context,
                          originLat: originLat,
                          originLng: originLng,
                          waypointLat: stLat!,
                          waypointLng: stLng!,
                          waypointName: name,
                          destinationLat: destLat!,
                          destinationLng: destLng!,
                          destinationName: destinationName,
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kMarkerRecommend,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.route_rounded, size: 16),
                label: const Text('경유 길안내', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecStatCell extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _RecStatCell({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(height: 4),
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1a1a1a))),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Color(0xFF999999))),
        ],
      ),
    );
  }
}

// ── 비교 테이블 ──────────────────────────────────────────────────────────────

class _ComparisonTable extends StatelessWidget {
  final String onRouteName;
  final double? onRoutePrice;
  final int onRouteCost;
  final String onRouteDetourLabel;
  final String onRouteFuelLabel;
  final String detourName;
  final double? detourPrice;
  final int detourCost;
  final String detourDetourLabel;
  final String detourFuelLabel;
  final int savings;
  final int? detourMins;
  final bool aiRecIsDetour;
  final String? fuelLabel;
  final NumberFormat wonFmt;
  final VoidCallback? onViewOnMapRoute;
  final VoidCallback? onViewOnMapDetour;
  // 경로안내에 필요한 좌표
  final double? onRouteLat;
  final double? onRouteLng;
  final double? dtLat;
  final double? dtLng;
  final double? destLat;
  final double? destLng;
  final String destinationName;
  final double originLat;
  final double originLng;

  const _ComparisonTable({
    required this.onRouteName,
    required this.onRoutePrice,
    required this.onRouteCost,
    required this.onRouteDetourLabel,
    required this.onRouteFuelLabel,
    required this.detourName,
    required this.detourPrice,
    required this.detourCost,
    required this.detourDetourLabel,
    required this.detourFuelLabel,
    required this.savings,
    required this.detourMins,
    required this.aiRecIsDetour,
    required this.fuelLabel,
    required this.wonFmt,
    this.onViewOnMapRoute,
    this.onViewOnMapDetour,
    required this.onRouteLat,
    required this.onRouteLng,
    required this.dtLat,
    required this.dtLng,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    required this.originLat,
    required this.originLng,
  });

  @override
  Widget build(BuildContext context) {
    final hasOnRoute = onRouteName.trim().isNotEmpty;
    final hasDetourCol = detourName.trim().isNotEmpty;
    final hasBothCols = hasOnRoute && hasDetourCol;
    // 테이블 하이라이트: AI 추천 기준 (주황 = 추천), 빈 열은 비강조
    final detourIsWinner = aiRecIsDetour;
    final midHi = hasOnRoute && !detourIsWinner;
    final rightHi = hasDetourCol && detourIsWinner;
    // 배너 텍스트: 실제 비용 기준 (savings > 0 이면 우회가 더 저렴)
    final detourIsActuallyCheaper = savings > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타이틀
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.compare_arrows_rounded, size: 16, color: Color(0xFF888888)),
                const SizedBox(width: 6),
                const Text('경로 비교',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF333333))),
                if (fuelLabel != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5FBF8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCCEEDE)),
                    ),
                    child: Text(fuelLabel!,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _kPrimary)),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 표 헤더
          _TableRow(
            isHeader: true,
            left: '',
            mid: '경로상 최저가',
            right: '우회 최저가',
            midHighlight: midHi,
            rightHighlight: rightHi,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 주유소명
          _TableRow(
            label: '주유소',
            left: null,
            mid: hasOnRoute ? onRouteName : '—',
            right: hasDetourCol ? detourName : '—',
            midHighlight: midHi,
            rightHighlight: rightHi,
            midButton: hasOnRoute && onViewOnMapRoute != null
                ? GestureDetector(
                    onTap: onViewOnMapRoute,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (!detourIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: (!detourIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined, size: 10, color: !detourIsWinner ? _kMarkerRecommend : _kCompareLoser),
                          const SizedBox(width: 2),
                          Text('지도보기', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: !detourIsWinner ? _kMarkerRecommend : _kCompareLoser)),
                        ],
                      ),
                    ),
                  )
                : null,
            rightButton: hasDetourCol && onViewOnMapDetour != null
                ? GestureDetector(
                    onTap: onViewOnMapDetour,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (detourIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: (detourIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined, size: 10, color: detourIsWinner ? _kMarkerRecommend : _kCompareLoser),
                          const SizedBox(width: 2),
                          Text('지도보기', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: detourIsWinner ? _kMarkerRecommend : _kCompareLoser)),
                        ],
                      ),
                    ),
                  )
                : null,
            midNavButton: hasOnRoute && onRouteLat != null && onRouteLng != null && destLat != null && destLng != null
                ? GestureDetector(
                    onTap: () => showViaWaypointNavigationSheet(
                          context,
                          originLat: originLat,
                          originLng: originLng,
                          waypointLat: onRouteLat!,
                          waypointLng: onRouteLng!,
                          waypointName: onRouteName,
                          destinationLat: destLat!,
                          destinationLng: destLng!,
                          destinationName: destinationName,
                        ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (!detourIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: (!detourIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.navigation_rounded, size: 10, color: !detourIsWinner ? _kMarkerRecommend : _kCompareLoser),
                          const SizedBox(width: 2),
                          Text('경로안내', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: !detourIsWinner ? _kMarkerRecommend : _kCompareLoser)),
                        ],
                      ),
                    ),
                  )
                : null,
            rightNavButton: hasDetourCol && dtLat != null && dtLng != null && destLat != null && destLng != null
                ? GestureDetector(
                    onTap: () => showViaWaypointNavigationSheet(
                          context,
                          originLat: originLat,
                          originLng: originLng,
                          waypointLat: dtLat!,
                          waypointLng: dtLng!,
                          waypointName: detourName,
                          destinationLat: destLat!,
                          destinationLng: destLng!,
                          destinationName: destinationName,
                        ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (detourIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: (detourIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.navigation_rounded, size: 10, color: detourIsWinner ? _kMarkerRecommend : _kCompareLoser),
                          const SizedBox(width: 2),
                          Text('경로안내', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: detourIsWinner ? _kMarkerRecommend : _kCompareLoser)),
                        ],
                      ),
                    ),
                  )
                : null,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 리터당 가격
          _TableRow(
            label: '리터당',
            left: null,
            mid: hasOnRoute && onRoutePrice != null ? '${wonFmt.format(onRoutePrice!.round())}원' : '—',
            right: hasDetourCol && detourPrice != null ? '${wonFmt.format(detourPrice!.round())}원' : '—',
            midHighlight: midHi,
            rightHighlight: rightHi,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          _TableRow(
            label: '유종',
            left: null,
            mid: hasOnRoute ? onRouteFuelLabel : '—',
            right: hasDetourCol ? (detourFuelLabel.trim().isEmpty ? '—' : detourFuelLabel) : '—',
            midHighlight: midHi,
            rightHighlight: rightHi,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 예상 주유비
          _TableRow(
            label: '예상 주유비',
            left: null,
            mid: hasOnRoute && onRouteCost > 0 ? '${wonFmt.format(onRouteCost)}원' : '—',
            right: hasDetourCol && detourCost > 0 ? '${wonFmt.format(detourCost)}원' : '—',
            midHighlight: midHi,
            rightHighlight: rightHi,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 추가 시간
          _TableRow(
            label: '추가 시간',
            left: null,
            mid: hasOnRoute ? onRouteDetourLabel : '—',
            right: hasDetourCol ? (detourDetourLabel.trim().isEmpty ? '—' : detourDetourLabel) : '—',
            midHighlight: midHi,
            rightHighlight: rightHi,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 결론 배너
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF5FBF8),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded, size: 15, color: _kMarkerRecommend),
                const SizedBox(width: 8),
                Expanded(
                  child: !hasBothCols
                      ? const Text(
                          '비교 후보가 한 곳이에요. 표에 표시된 주유소 정보를 참고해 주세요.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
                        )
                      : savings > 0
                          ? RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 12, color: Color(0xFF1a1a1a)),
                                children: [
                                  TextSpan(
                                    text: detourIsActuallyCheaper ? '우회' : '경로상 주유소',
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: _kMarkerRecommend),
                                  ),
                                  const TextSpan(text: '가 '),
                                  TextSpan(
                                    text: '${wonFmt.format(savings)}원',
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: _kMarkerRecommend),
                                  ),
                                  const TextSpan(text: ' 더 저렴해요'),
                                  if (detourMins != null && detourMins! > 0 && detourIsActuallyCheaper)
                                    TextSpan(text: ' · 대신 ${detourMins}분 더 소요'),
                                ],
                              ),
                            )
                          : const Text('두 주유소 가격 차이가 거의 없어요',
                              style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final bool isHeader;
  final String? label;
  final String? left;
  final String mid;
  final String right;
  final bool midHighlight;
  final bool rightHighlight;
  final Widget? midButton;
  final Widget? rightButton;
  final Widget? midNavButton;
  final Widget? rightNavButton;

  const _TableRow({
    this.isHeader = false,
    this.label,
    this.left,
    required this.mid,
    required this.right,
    required this.midHighlight,
    required this.rightHighlight,
    this.midButton,
    this.rightButton,
    this.midNavButton,
    this.rightNavButton,
  });

  @override
  Widget build(BuildContext context) {
    // midHighlight/rightHighlight: 추천(주황) 컬러를 줄 쪽을 의미하고,
    // 나머지 쪽(비승자)은 비교(파랑)로 통일한다.
    final midColor = isHeader
        ? const Color(0xFF666666)
        : (midHighlight ? _kMarkerRecommend : _kCompareLoser);
    final rightColor = isHeader
        ? const Color(0xFF666666)
        : (rightHighlight ? _kMarkerRecommend : _kCompareLoser);

    return IntrinsicHeight(
      child: Row(
        children: [
          // 라벨 열
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: const Color(0xFFFAFAFA),
            child: Text(
              isHeader ? '' : (label ?? ''),
              style: const TextStyle(fontSize: 10, color: Color(0xFF888888), fontWeight: FontWeight.w500),
            ),
          ),
          const VerticalDivider(width: 1, color: Color(0xFFF0F0F0)),
          // 경로상 열
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              color: isHeader
                  ? Colors.white
                  : (midHighlight
                      ? _kMarkerRecommendLight
                      : const Color(0xFFEEF4FF)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    mid,
                    style: TextStyle(
                      fontSize: isHeader ? 10 : 12,
                      fontWeight: (isHeader || midHighlight) ? FontWeight.w700 : FontWeight.w500,
                      color: midColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (midButton != null || midNavButton != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (midButton != null) midButton!,
                          if (midNavButton != null) midNavButton!,
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1, color: Color(0xFFF0F0F0)),
          // 우회 열
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              color: isHeader
                  ? Colors.white
                  : (rightHighlight
                      ? _kMarkerRecommendLight
                      : const Color(0xFFEEF4FF)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    right,
                    style: TextStyle(
                      fontSize: isHeader ? 10 : 12,
                      fontWeight: (isHeader || rightHighlight) ? FontWeight.w700 : FontWeight.w500,
                      color: rightColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (rightButton != null || rightNavButton != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (rightButton != null) rightButton!,
                          if (rightNavButton != null) rightNavButton!,
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 옵션 카드 ────────────────────────────────────────────────────────────────

class _OptionCard extends StatelessWidget {
  final String tag;
  final Color tagColor;
  final bool isAiRec;
  final bool isUserSelected;
  final String stName;
  final String? stAddr;
  final double? priceL;
  final int expectedCost;
  final int detourM;
  final num? detourTimeMin;
  final _ExtraInfo? extraInfo;
  final double? stLat, stLng, destLat, destLng;
  final String destinationName;
  final double originLat, originLng;
  final NumberFormat wonFmt;
  final VoidCallback? onViewOnMap;
  final VoidCallback? onRestoreAiRec;

  const _OptionCard({
    required this.tag,
    required this.tagColor,
    required this.isAiRec,
    required this.isUserSelected,
    required this.stName,
    required this.stAddr,
    required this.priceL,
    required this.expectedCost,
    required this.detourM,
    required this.detourTimeMin,
    required this.extraInfo,
    required this.stLat,
    required this.stLng,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    required this.originLat,
    required this.originLng,
    required this.wonFmt,
    this.onViewOnMap,
    this.onRestoreAiRec,
  });

  @override
  Widget build(BuildContext context) {
    final canNav = stLat != null && stLng != null && destLat != null && destLng != null;

    final Color borderColor;
    final Color bgColor;
    final Color navBtnColor;
    final Color navBtnTextColor;

    if (isUserSelected) {
      borderColor = _kSelected;
      bgColor = _kSelectedLight;
      navBtnColor = _kSelected;
      navBtnTextColor = Colors.white;
    } else if (isAiRec) {
      borderColor = _kPrimary;
      bgColor = _kPrimaryLight;
      navBtnColor = _kPrimary;
      navBtnTextColor = Colors.white;
    } else {
      borderColor = const Color(0xFFDDDDDD);
      bgColor = Colors.white;
      navBtnColor = const Color(0xFFEEEEEE);
      navBtnTextColor = const Color(0xFF444444);
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: (isAiRec || isUserSelected) ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tagColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(tag,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                if (isAiRec) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kPrimary,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 10, color: Colors.white),
                        SizedBox(width: 3),
                        Text('AI 추천',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
                if (isUserSelected) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kSelected,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 10, color: Colors.white),
                        SizedBox(width: 3),
                        Text('내가 선택',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                if (onRestoreAiRec != null)
                  TextButton.icon(
                    onPressed: onRestoreAiRec,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 14, color: _kPrimary),
                    label: const Text(
                      'AI 추천 복원',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kPrimary,
                      ),
                    ),
                  ),
                if (onViewOnMap != null)
                  GestureDetector(
                    onTap: onViewOnMap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined, size: 13, color: Color(0xFF666666)),
                          SizedBox(width: 3),
                          Text('지도',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF666666))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── 주유소명 + 주소 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1a1a1a))),
                if (stAddr != null && stAddr!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(stAddr!, style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── 핵심 수치 3종 ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _NumCell(
                    value: priceL != null ? '${wonFmt.format(priceL!.round())}원' : '—',
                    label: '리터당',
                  ),
                  const VerticalDivider(width: 1, color: Color(0xFFDDDDDD)),
                  _DetourStatsCell(detourM: detourM, detourTimeMin: detourTimeMin),
                  const VerticalDivider(width: 1, color: Color(0xFFDDDDDD)),
                  _NumCell(
                    value: expectedCost > 0 ? '${wonFmt.format(expectedCost)}원' : '—',
                    label: '예상 주유비',
                    valueSize: 14,
                  ),
                ],
              ),
            ),
          ),

          // ── 절약/시간 정보 (우회 카드) ──
          if (extraInfo != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF4FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.savings_outlined, size: 15, color: Color(0xFF1D6FE0)),
                        const SizedBox(width: 6),
                        Text(
                          '경로상 대비 ${wonFmt.format(extraInfo!.savings)}원 절약',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1D6FE0)),
                        ),
                      ],
                    ),
                    if (extraInfo!.timeMins != null && extraInfo!.timeMins! > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFF888888)),
                          const SizedBox(width: 6),
                          Text(
                            '대신 ${extraInfo!.timeMins}분 더 소요',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // ── 길안내 버튼 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: canNav
                    ? () => showViaWaypointNavigationSheet(
                          context,
                          originLat: originLat,
                          originLng: originLng,
                          waypointLat: stLat!,
                          waypointLng: stLng!,
                          waypointName: stName,
                          destinationLat: destLat!,
                          destinationLng: destLng!,
                          destinationName: destinationName,
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: navBtnColor,
                  foregroundColor: navBtnTextColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.route_rounded, size: 16),
                label: const Text('경유 길안내',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 다른 후보 섹션 ───────────────────────────────────────────────────────────

class _AltSection extends StatelessWidget {
  final List<dynamic> alternatives;
  final NumberFormat wonFmt;
  final void Function(dynamic altItem)? onSelect;
  final Map<String, dynamic>? selectedItem;

  const _AltSection({
    required this.alternatives,
    required this.wonFmt,
    this.onSelect,
    this.selectedItem,
  });

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
    final valid = alternatives.whereType<Map>().toList();
    if (valid.isEmpty) return const SizedBox.shrink();

    final selectedId = selectedItem?['station'] is Map
        ? (selectedItem!['station'] as Map)['id']?.toString()
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text('다른 후보',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1a1a1a))),
            SizedBox(width: 6),
            Text('가격 순', style: TextStyle(fontSize: 11, color: Color(0xFF999999))),
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
              final item = valid[idx];
              final st = item['station'] is Map ? item['station'] as Map : null;
              final name = st?['name']?.toString() ?? '';
              final addr = st?['address']?.toString() ?? '';
              final itemId = st?['id']?.toString();
              final price = _d(st?['price_won_per_liter']);
              final detourM = _i(item['detour_distance_m']);
              final savings = item['savings_vs_primary_won'] != null
                  ? _i(item['savings_vs_primary_won'])
                  : _i(item['savings_vs_on_route_won']);
              final detourTimeMin = item['detour_is_none'] == true
                  ? 0
                  : (item['detour_time_min'] is num ? item['detour_time_min'] as num : null);
              final isLast = idx == valid.length - 1;
              final isSelected = selectedId != null && selectedId == itemId;

              final detourText = _detourAltListSubtitle(
                detourM: detourM,
                detourTimeMin: detourTimeMin,
                serverDetourIsNone: item['detour_is_none'] is bool ? item['detour_is_none'] as bool : null,
              );

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        // 번호 뱃지 (선택됨이면 체크)
                        Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? _kSelected : const Color(0xFFF0F0F0),
                          ),
                          child: Center(
                            child: isSelected
                                ? const Icon(Icons.check, size: 13, color: Colors.white)
                                : Text('${idx + 1}',
                                    style: const TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w600,
                                        color: Color(0xFF888888))),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // 이름 + 주소 + 정보
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? _kSelected : const Color(0xFF1a1a1a))),
                              if (addr.isNotEmpty) ...[
                                const SizedBox(height: 1),
                                Text(addr,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10, color: Color(0xFF888888))),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (price != null) '${wonFmt.format(price.round())}원/L',
                                  detourText,
                                ].join(' · '),
                                style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 절약 금액
                        Text(
                          savings >= 0
                              ? '${wonFmt.format(savings)}원 절약'
                              : '+${wonFmt.format(-savings)}원',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: savings >= 0
                                ? const Color(0xFF1D9E75)
                                : const Color(0xFFE24B4A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 확인 버튼 (선택됐으면 "선택됨")
                        GestureDetector(
                          onTap: () => onSelect?.call(isSelected ? null : item),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _kSelectedLight
                                  : const Color(0xFFEEF4FF),
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(color: _kSelected, width: 1)
                                  : null,
                            ),
                            child: Text(
                              isSelected ? '선택됨' : '확인',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? _kSelected : const Color(0xFF1D6FE0),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast) const Divider(height: 1, color: Color(0xFFF0F0F0)),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ─── 공통 위젯 ────────────────────────────────────────────────────────────────

/// 우회 거리·시간을 한 줄에 몰아 넣지 않고 구분해 표시한다.
class _DetourStatsCell extends StatelessWidget {
  final int detourM;
  final num? detourTimeMin;

  const _DetourStatsCell({required this.detourM, required this.detourTimeMin});

  static const _valueStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: Color(0xFF1a1a1a),
  );
  static const _subStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Color(0xFF546E7A),
  );
  static const _labelStyle = TextStyle(
    fontSize: 11,
    color: Color(0xFF999999),
  );

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ..._valueWidgets(),
          const SizedBox(height: 3),
          const Text('우회', textAlign: TextAlign.center, style: _labelStyle),
        ],
      ),
    );
  }

  List<Widget> _valueWidgets() {
    if (_detourIsNegligible(detourM: detourM, detourTimeMin: detourTimeMin)) {
      return [
        const Text('우회 없음', textAlign: TextAlign.center, style: _valueStyle),
      ];
    }
    final m = _meaningfulDetourMinutes(detourTimeMin);
    final list = <Widget>[];
    if (detourM > 0) {
      final dist = detourM >= 1000
          ? '${(detourM / 1000).toStringAsFixed(1)} km'
          : '$detourM m';
      list.add(Text(dist, textAlign: TextAlign.center, style: _valueStyle));
      list.add(const SizedBox(height: 4));
    }
    if (m != null) {
      list.add(Text(
        detourM > 0 ? '직행보다 +약 $m분' : '직행 대비 약 $m분 추가',
        textAlign: TextAlign.center,
        style: _subStyle,
      ));
    } else {
      list.add(
        const Text(
          '조금 우회',
          textAlign: TextAlign.center,
          style: _subStyle,
        ),
      );
    }
    return list;
  }
}

class _NumCell extends StatelessWidget {
  final String value;
  final String label;
  final double? valueSize;

  const _NumCell({required this.value, required this.label, this.valueSize});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: valueSize ?? 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1a1a1a),
              )),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF999999))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 비교 결과 Body (사용자 선택 비교 모드)
// ─────────────────────────────────────────────────────────────────────────────

// 통일된 색상 체계
const _kCompareWinner = Color(0xFFE8700A);  // 추천 (주황)
const _kCompareLoser = Color(0xFF1D6FE0);   // 비교 대상 (파랑)

class CompareResultBody extends StatelessWidget {
  final Map<String, dynamic> data;
  final String destinationName;
  final ScrollController? scrollController;
  final NumberFormat wonFmt;
  final String? fuelLabel;
  final double originLat;
  final double originLng;
  final double? destLat;
  final double? destLng;
  /// 카드 탭 시 해당 station 데이터(via_route 포함) 전달 → 지도에 경로 그리기
  final void Function(Map<String, dynamic> stationData)? onCardTap;

  const CompareResultBody({
    super.key,
    required this.data,
    required this.destinationName,
    this.scrollController,
    required this.wonFmt,
    this.fuelLabel,
    this.originLat = 0,
    this.originLng = 0,
    this.destLat,
    this.destLng,
    this.onCardTap,
  });

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
    final comparison = data['comparison'] is Map ? data['comparison'] as Map<String, dynamic> : null;
    final winner = comparison?['winner']?.toString() ?? 'station_a';
    final uiMessage = comparison?['ui_message']?.toString() ?? '';
    final savingsWon = _i(comparison?['savings_won']);
    final timeDiffMin = comparison?['time_diff_min'] is num
        ? (comparison!['time_diff_min'] as num).round() : null;
    final reasonCode = comparison?['reason_code']?.toString() ?? '';
    final computed = data['computed'] is Map ? data['computed'] as Map<String, dynamic> : null;
    final goalL = _d(computed?['goal_liters']);

    final stAData = data['station_a'] is Map ? data['station_a'] as Map<String, dynamic> : null;
    final stBData = data['station_b'] is Map ? data['station_b'] as Map<String, dynamic> : null;

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(16, scrollController != null ? 4 : 8, 16, 32),
      children: [
        // 드래그 핸들
        if (scrollController != null)
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),

        // 헤더
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _kCompareWinner.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.compare_arrows_rounded, size: 14, color: _kCompareWinner),
                    SizedBox(width: 4),
                    Text('비교 분석 결과', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kCompareWinner)),
                  ],
                ),
              ),
              if (fuelLabel != null) ...[
                const SizedBox(width: 8),
                _FuelChip(label: fuelLabel!),
              ],
            ],
          ),
        ),

        // AI 메시지 (마크다운 지원)
        if (uiMessage.isNotEmpty) ...[
          _CompareMessageBanner(message: uiMessage),
          const SizedBox(height: 12),
        ],

        // 비교 테이블
        if (stAData != null && stBData != null)
          _UserCompareTable(
            stationAData: stAData,
            stationBData: stBData,
            winner: winner,
            savingsWon: savingsWon,
            timeDiffMin: timeDiffMin,
            reasonCode: reasonCode,
            wonFmt: wonFmt,
            fuelLabel: fuelLabel,
            originLat: originLat,
            originLng: originLng,
            destLat: destLat,
            destLng: destLng,
            destinationName: destinationName,
            onCardTap: onCardTap,
          ),

        // 기준 정보
        if (goalL != null) ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              '목표 주유량 약 ${goalL.toStringAsFixed(1)}L 기준',
              style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
            ),
          ),
        ],
      ],
    );
  }
}

class _CompareMessageBanner extends StatelessWidget {
  final String message;
  const _CompareMessageBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final normalized = message.replaceAll(r'\n', '\n');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB8CCFF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20, height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: _kCompareWinner.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 12, color: _kCompareWinner),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI 분석', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kCompareWinner)),
                const SizedBox(height: 6),
                MarkdownBody(
                  data: normalized,
                  shrinkWrap: true,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF1a1a1a)),
                    strong: const TextStyle(
                      fontSize: 13, height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: _kCompareWinner,
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

class _CompareSummaryBanner extends StatelessWidget {
  final int savingsWon;
  final int? timeDiffMin;
  final String reasonCode;
  final NumberFormat wonFmt;

  const _CompareSummaryBanner({
    required this.savingsWon, required this.timeDiffMin,
    required this.reasonCode, required this.wonFmt,
  });

  @override
  Widget build(BuildContext context) {
    final timePart = timeDiffMin != null && timeDiffMin! > 0
        ? ' · ${timeDiffMin}분 차이'
        : (timeDiffMin == 0 ? ' · 시간 거의 동일' : '');
    final worthText = ['WORTH_EXTRA_TIME'].contains(reasonCode)
        ? ' — 추가 시간이 아깝지 않아요!'
        : ['NOT_WORTH_EXTRA_TIME'].contains(reasonCode) ? ' — 시간 손실이 더 커요' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB8CCFF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.savings_rounded, size: 18, color: _kCompareWinner),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: Color(0xFF1a1a1a)),
                children: [
                  TextSpan(
                    text: '${wonFmt.format(savingsWon)}원 절약',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: _kCompareWinner),
                  ),
                  TextSpan(text: '$timePart$worthText'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  final String label;  // 'A' or 'B'
  final bool isWinner;
  final Map<String, dynamic> stationData;
  final NumberFormat wonFmt;
  final double originLat;
  final double originLng;
  final double? destLat;
  final double? destLng;
  final String destinationName;
  final VoidCallback? onCardTap;

  const _CompareCard({
    required this.label, required this.isWinner,
    required this.stationData, required this.wonFmt,
    this.originLat = 0, this.originLng = 0,
    this.destLat, this.destLng,
    this.destinationName = '목적지',
    this.onCardTap,
  });

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  @override
  Widget build(BuildContext context) {
    final st = stationData['station'] is Map
        ? stationData['station'] as Map<String, dynamic> : <String, dynamic>{};
    final name = st['name']?.toString() ?? '';
    final addr = st['address']?.toString() ?? '';
    final priceL = _d(st['price_won_per_liter'])?.round() ?? 0;
    final cost = stationData['expected_fuel_cost_won'] is num
        ? (stationData['expected_fuel_cost_won'] as num).round() : 0;
    final detourMin = stationData['detour_is_none'] == true
        ? 0
        : (stationData['detour_time_min'] is num
            ? (stationData['detour_time_min'] as num).round()
            : null);
    final totalMin = stationData['total_time_min'] is num
        ? (stationData['total_time_min'] as num).round() : null;

    final borderColor = isWinner ? _kCompareWinner : const Color(0xFFEEEEEE);
    final bgColor = isWinner ? const Color(0xFFF0F4FF) : Colors.white;
    final accentColor = isWinner ? _kCompareWinner : _kCompareLoser;

    final stLat = _d(st['lat']);
    final stLng = _d(st['lng']);
    final canNav = stLat != null && stLng != null && destLat != null && destLng != null;

    return GestureDetector(
      onTap: onCardTap,
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isWinner ? 1.5 : 1),
        boxShadow: isWinner
            ? [BoxShadow(color: _kCompareWinner.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 라벨 배지
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1a1a1a)),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (isWinner) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _kCompareWinner,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('추천', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    if (addr.isNotEmpty)
                      Text(addr, style: const TextStyle(fontSize: 11, color: Color(0xFF999999)), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 수치 행
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isWinner ? Colors.white.withOpacity(0.7) : const Color(0xFFF8F8F8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _StatItem(label: '리터당 가격', value: '${wonFmt.format(priceL)}원', color: accentColor),
                Container(width: 1, height: 28, color: const Color(0xFFEEEEEE)),
                _StatItem(label: '예상 주유비', value: '${wonFmt.format(cost)}원', color: accentColor),
                Container(width: 1, height: 28, color: const Color(0xFFEEEEEE)),
                _StatItem(
                  label: '추가 시간',
                  value: detourMin != null
                      ? (detourMin < _kDetourStartMinutes ? '거의 없음' : '약 ${detourMin}분')
                      : (totalMin != null ? '전체 ${totalMin}분' : '-'),
                  color: accentColor,
                ),
              ],
            ),
          ),

          // 경유 길안내 버튼
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: canNav
                  ? () => showViaWaypointNavigationSheet(
                        context,
                        originLat: originLat,
                        originLng: originLng,
                        waypointLat: stLat!,
                        waypointLng: stLng!,
                        waypointName: name,
                        destinationLat: destLat!,
                        destinationLng: destLng!,
                        destinationName: destinationName,
                      )
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              icon: const Icon(Icons.route_rounded, size: 15),
              label: const Text('경유 길안내', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    ),  // GestureDetector
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatItem({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF999999))),
        ],
      ),
    );
  }
}

// ─── 사용자 선택 비교 테이블 ──────────────────────────────────────────────────────

class _UserCompareTable extends StatelessWidget {
  final Map<String, dynamic> stationAData;
  final Map<String, dynamic> stationBData;
  final String winner;
  final int savingsWon;
  final int? timeDiffMin;
  final String reasonCode;
  final NumberFormat wonFmt;
  final String? fuelLabel;
  final double originLat;
  final double originLng;
  final double? destLat;
  final double? destLng;
  final String destinationName;
  final void Function(Map<String, dynamic> stationData)? onCardTap;

  const _UserCompareTable({
    required this.stationAData,
    required this.stationBData,
    required this.winner,
    required this.savingsWon,
    required this.timeDiffMin,
    required this.reasonCode,
    required this.wonFmt,
    required this.fuelLabel,
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    this.onCardTap,
  });

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _i(dynamic v) {
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  String _detourLabel(int? detourMin) {
    if (detourMin == null || detourMin < _kDetourStartMinutes) return '우회 없음';
    return '+${detourMin}분';
  }

  @override
  Widget build(BuildContext context) {
    final stA = stationAData['station'] is Map ? stationAData['station'] as Map<String, dynamic> : {};
    final stB = stationBData['station'] is Map ? stationBData['station'] as Map<String, dynamic> : {};
    
    final nameA = stA['name']?.toString() ?? '';
    final nameB = stB['name']?.toString() ?? '';
    final fuelA = _resolveFuelLabel(stA['fuel_type'], fallback: fuelLabel);
    final fuelB = _resolveFuelLabel(stB['fuel_type'], fallback: fuelLabel);
    final priceA = _d(stA['price_won_per_liter']);
    final priceB = _d(stB['price_won_per_liter']);
    final costA = _i(stationAData['expected_fuel_cost_won']);
    final costB = _i(stationBData['expected_fuel_cost_won']);
    final detourMinA = stationAData['detour_is_none'] == true
        ? 0
        : (stationAData['detour_time_min'] is num
            ? (stationAData['detour_time_min'] as num).round()
            : null);
    final detourMinB = stationBData['detour_is_none'] == true
        ? 0
        : (stationBData['detour_time_min'] is num
            ? (stationBData['detour_time_min'] as num).round()
            : null);
    
    final latA = _d(stA['lat']);
    final lngA = _d(stA['lng']);
    final latB = _d(stB['lat']);
    final lngB = _d(stB['lng']);

    final aIsWinner = winner == 'station_a';
    final bIsWinner = winner == 'station_b';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 추천 카드 (승자)
        _CompareRecommendCard(
          label: aIsWinner ? 'A' : 'B',
          name: aIsWinner ? nameA : nameB,
          price: aIsWinner ? priceA : priceB,
          cost: aIsWinner ? costA : costB,
          detourMin: aIsWinner ? detourMinA : detourMinB,
          stLat: aIsWinner ? latA : latB,
          stLng: aIsWinner ? lngA : lngB,
          destLat: destLat,
          destLng: destLng,
          destinationName: destinationName,
          originLat: originLat,
          originLng: originLng,
          wonFmt: wonFmt,
          onViewOnMap: onCardTap != null ? () => onCardTap!(aIsWinner ? stationAData : stationBData) : null,
        ),

        const SizedBox(height: 12),

        // 비교 테이블
        _UserComparisonTable(
          nameA: nameA,
          nameB: nameB,
          priceA: priceA,
          priceB: priceB,
          fuelA: fuelA,
          fuelB: fuelB,
          costA: costA,
          costB: costB,
          detourMinA: detourMinA,
          detourMinB: detourMinB,
          latA: latA,
          lngA: lngA,
          latB: latB,
          lngB: lngB,
          aIsWinner: aIsWinner,
          bIsWinner: bIsWinner,
          savingsWon: savingsWon,
          timeDiffMin: timeDiffMin,
          fuelLabel: fuelLabel,
          wonFmt: wonFmt,
          originLat: originLat,
          originLng: originLng,
          destLat: destLat,
          destLng: destLng,
          destinationName: destinationName,
          onViewOnMapA: onCardTap != null ? () => onCardTap!(stationAData) : null,
          onViewOnMapB: onCardTap != null ? () => onCardTap!(stationBData) : null,
        ),
      ],
    );
  }
}

// ─── 비교 추천 카드 ────────────────────────────────────────────────────────────

class _CompareRecommendCard extends StatelessWidget {
  final String label;
  final String name;
  final double? price;
  final int cost;
  final int? detourMin;
  final double? stLat, stLng, destLat, destLng;
  final String destinationName;
  final double originLat, originLng;
  final NumberFormat wonFmt;
  final VoidCallback? onViewOnMap;

  const _CompareRecommendCard({
    required this.label,
    required this.name,
    required this.price,
    required this.cost,
    required this.detourMin,
    required this.stLat,
    required this.stLng,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    required this.originLat,
    required this.originLng,
    required this.wonFmt,
    this.onViewOnMap,
  });

  @override
  Widget build(BuildContext context) {
    final canNav = stLat != null && stLng != null && destLat != null && destLng != null;
    final isNegligible = detourMin == null || detourMin! < _kDetourStartMinutes;

    return Container(
      decoration: BoxDecoration(
        color: _kMarkerRecommendLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kMarkerRecommend, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _kMarkerRecommend, borderRadius: BorderRadius.circular(5)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 11, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('추천 $label', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 주유소명
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1a1a1a))),
          ),

          // 수치 행
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    _RecStatCell(
                      icon: Icons.local_gas_station_rounded,
                      iconColor: _kMarkerRecommend,
                      value: price != null ? '${wonFmt.format(price!.round())}원' : '—',
                      label: '리터당 가격',
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFDDDDDD)),
                    _RecStatCell(
                      icon: Icons.access_time_rounded,
                      iconColor: isNegligible ? _kMarkerRecommend : const Color(0xFFE07B1D),
                      value: isNegligible
                          ? '우회 없음'
                          : (detourMin != null ? '+${detourMin}분' : '조금 우회'),
                      label: '직행 대비',
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFDDDDDD)),
                    _RecStatCell(
                      icon: Icons.payments_outlined,
                      iconColor: _kMarkerRecommend,
                      value: cost > 0 ? '${wonFmt.format(cost)}원' : '—',
                      label: '예상 주유비',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 길안내 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: canNav
                    ? () => showViaWaypointNavigationSheet(
                          context,
                          originLat: originLat,
                          originLng: originLng,
                          waypointLat: stLat!,
                          waypointLng: stLng!,
                          waypointName: name,
                          destinationLat: destLat!,
                          destinationLng: destLng!,
                          destinationName: destinationName,
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kMarkerRecommend,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.route_rounded, size: 16),
                label: const Text('경유 길안내', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 사용자 비교 테이블 ────────────────────────────────────────────────────────

class _UserComparisonTable extends StatelessWidget {
  final String nameA, nameB;
  final double? priceA, priceB;
  final String fuelA, fuelB;
  final int costA, costB;
  final int? detourMinA, detourMinB;
  final double? latA, lngA, latB, lngB;
  final bool aIsWinner, bIsWinner;
  final int savingsWon;
  final int? timeDiffMin;
  final String? fuelLabel;
  final NumberFormat wonFmt;
  final double originLat, originLng;
  final double? destLat, destLng;
  final String destinationName;
  final VoidCallback? onViewOnMapA;
  final VoidCallback? onViewOnMapB;

  const _UserComparisonTable({
    required this.nameA,
    required this.nameB,
    required this.priceA,
    required this.priceB,
    required this.fuelA,
    required this.fuelB,
    required this.costA,
    required this.costB,
    required this.detourMinA,
    required this.detourMinB,
    required this.latA,
    required this.lngA,
    required this.latB,
    required this.lngB,
    required this.aIsWinner,
    required this.bIsWinner,
    required this.savingsWon,
    required this.timeDiffMin,
    required this.fuelLabel,
    required this.wonFmt,
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    this.onViewOnMapA,
    this.onViewOnMapB,
  });

  String _detourLabel(int? detourMin) {
    if (detourMin == null || detourMin < _kDetourStartMinutes) return '우회 없음';
    return '+${detourMin}분';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타이틀
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.compare_arrows_rounded, size: 16, color: Color(0xFF888888)),
                const SizedBox(width: 6),
                const Text('상세 비교',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF333333))),
                if (fuelLabel != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5FBF8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCCEEDE)),
                    ),
                    child: Text(fuelLabel!,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _kPrimary)),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 표 헤더
          _TableRow(
            isHeader: true,
            left: '',
            mid: '주유소 A',
            right: '주유소 B',
            midHighlight: aIsWinner,
            rightHighlight: bIsWinner,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 주유소명
          _TableRow(
            label: '주유소',
            left: null,
            mid: nameA,
            right: nameB,
            midHighlight: aIsWinner,
            rightHighlight: bIsWinner,
            midButton: onViewOnMapA != null
                ? GestureDetector(
                    onTap: onViewOnMapA,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (aIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: (aIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined, size: 10, color: aIsWinner ? _kMarkerRecommend : _kCompareLoser),
                          const SizedBox(width: 2),
                          Text('지도보기', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: aIsWinner ? _kMarkerRecommend : _kCompareLoser)),
                        ],
                      ),
                    ),
                  )
                : null,
            rightButton: onViewOnMapB != null
                ? GestureDetector(
                    onTap: onViewOnMapB,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (bIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: (bIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined, size: 10, color: bIsWinner ? _kMarkerRecommend : _kCompareLoser),
                          const SizedBox(width: 2),
                          Text('지도보기', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: bIsWinner ? _kMarkerRecommend : _kCompareLoser)),
                        ],
                      ),
                    ),
                  )
                : null,
            midNavButton: latA != null && lngA != null && destLat != null && destLng != null
                ? GestureDetector(
                    onTap: () => showViaWaypointNavigationSheet(
                          context,
                          originLat: originLat,
                          originLng: originLng,
                          waypointLat: latA!,
                          waypointLng: lngA!,
                          waypointName: nameA,
                          destinationLat: destLat!,
                          destinationLng: destLng!,
                          destinationName: destinationName,
                        ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (aIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: (aIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.navigation_rounded, size: 10, color: aIsWinner ? _kMarkerRecommend : _kCompareLoser),
                          const SizedBox(width: 2),
                          Text('경로안내', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: aIsWinner ? _kMarkerRecommend : _kCompareLoser)),
                        ],
                      ),
                    ),
                  )
                : null,
            rightNavButton: latB != null && lngB != null && destLat != null && destLng != null
                ? GestureDetector(
                    onTap: () => showViaWaypointNavigationSheet(
                          context,
                          originLat: originLat,
                          originLng: originLng,
                          waypointLat: latB!,
                          waypointLng: lngB!,
                          waypointName: nameB,
                          destinationLat: destLat!,
                          destinationLng: destLng!,
                          destinationName: destinationName,
                        ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (bIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: (bIsWinner ? _kMarkerRecommend : _kCompareLoser).withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.navigation_rounded, size: 10, color: bIsWinner ? _kMarkerRecommend : _kCompareLoser),
                          const SizedBox(width: 2),
                          Text('경로안내', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: bIsWinner ? _kMarkerRecommend : _kCompareLoser)),
                        ],
                      ),
                    ),
                  )
                : null,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 리터당 가격
          _TableRow(
            label: '리터당',
            left: null,
            mid: priceA != null ? '${wonFmt.format(priceA!.round())}원' : '—',
            right: priceB != null ? '${wonFmt.format(priceB!.round())}원' : '—',
            midHighlight: aIsWinner,
            rightHighlight: bIsWinner,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          _TableRow(
            label: '유종',
            left: null,
            mid: fuelA,
            right: fuelB,
            midHighlight: aIsWinner,
            rightHighlight: bIsWinner,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 예상 주유비
          _TableRow(
            label: '예상 주유비',
            left: null,
            mid: costA > 0 ? '${wonFmt.format(costA)}원' : '—',
            right: costB > 0 ? '${wonFmt.format(costB)}원' : '—',
            midHighlight: aIsWinner,
            rightHighlight: bIsWinner,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 추가 시간
          _TableRow(
            label: '추가 시간',
            left: null,
            mid: _detourLabel(detourMinA),
            right: _detourLabel(detourMinB),
            midHighlight: aIsWinner,
            rightHighlight: bIsWinner,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 결론 배너
          if (savingsWon > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF5FBF8),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline_rounded, size: 15, color: _kMarkerRecommend),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 12, color: Color(0xFF1a1a1a)),
                        children: [
                          TextSpan(
                            text: aIsWinner ? '주유소 A' : '주유소 B',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: _kMarkerRecommend),
                          ),
                          const TextSpan(text: '가 '),
                          TextSpan(
                            text: '${wonFmt.format(savingsWon)}원',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: _kMarkerRecommend),
                          ),
                          const TextSpan(text: ' 더 저렴해요'),
                          if (timeDiffMin != null && timeDiffMin! > 0)
                            TextSpan(text: ' · 대신 ${timeDiffMin}분 더 소요'),
                        ],
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
