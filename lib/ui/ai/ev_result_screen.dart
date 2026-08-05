import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/navigation_util.dart';
import '../../data/services/station_alias_service.dart';
import '../../data/services/watch_service.dart';
import '../detail/ev_detail_screen.dart';
import '../widgets/watch_switch_dialog.dart';

const _kBlue = Color(0xFF1D6FE0);
const _kGreen = Color(0xFF1D9E75);
const _kOrange = Color(0xFFE8700A);
const _kGrey = Color(0xFF888888);
const _kPurple = Color(0xFF7B5EA7);
const _kTeal = Color(0xFF00897B);

// ── 9a 시안 토큰 (형 확정) — 충전은 EV 초록 단일 축, 도착 잔량은 앰버 ──
const _kEvGreen = Color(0xFF10B981);
const _kEvGreenDark = Color(0xFF059669);
const _kEvActiveCard = Color(0xFFECFDF5);
const _kAmber = Color(0xFFF59E0B);

/// recommendation_label → (배지 텍스트, 색상)
(String, Color) _labelInfo(String? label, Color defaultColor) {
  switch (label) {
    case 'optimal':
      return ('AI 추천', defaultColor);
    case 'safe':
      return ('안전 추천', _kGreen);
    case 'cheapest':
      return ('가성비', _kOrange);
    case 'fastest':
      return ('빠른 도착', _kPurple);
    case 'spacious':
      return ('여유 있음', _kTeal);
    default:
      return ('AI 추천', defaultColor);
  }
}

final _wonFmt = NumberFormat('#,###', 'ko_KR');

class EvResultBody extends StatefulWidget {
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
  State<EvResultBody> createState() => EvResultBodyState();
}

class EvResultBodyState extends State<EvResultBody> {
  // 충전소별 카드 키 (지도 마커 탭 → 해당 카드로 스크롤 이동용)
  final Map<String, GlobalKey> _stationKeys = {};

  // 9a 아코디언 — 펼쳐진 후보 인덱스 (한 번에 하나만, 기본 전부 접힘)
  int? _openAlt;

  /// 외부에서 호출 — 해당 statId 의 카드를 화면에 보이도록 스크롤.
  Future<void> scrollToStation(String statId) async {
    // 접힌 후보를 가리키면 먼저 펼친다 — 접힌 한 줄로는 마커 탭의 응답이 안 보인다.
    final alts = widget.data['alternatives'];
    if (alts is List) {
      final idx = alts
          .whereType<Map<String, dynamic>>()
          .toList()
          .indexWhere((a) => a['statId']?.toString() == statId);
      if (idx >= 0 && _openAlt != idx) {
        setState(() => _openAlt = idx);
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    final key = _stationKeys[statId];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.05, // 카드를 시트 상단 부근에 위치
    );
  }

  GlobalKey _keyFor(String? statId) {
    if (statId == null || statId.isEmpty) return GlobalKey();
    return _stationKeys.putIfAbsent(statId, () => GlobalKey());
  }

  /// 추천 카드의 예상 충전요금 — 접힌 후보 행 '추천 대비 차액'의 기준값.
  static int? _recCostOf(Map<String, dynamic>? rec) {
    if (rec == null) return null;
    final v = rec['est_cost_member'] ?? rec['est_cost'];
    return v is num ? v.round() : null;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final scrollController = widget.scrollController;
    final onStationMapTap = widget.onStationMapTap;
    final originLat = widget.originLat;
    final originLng = widget.originLng;
    final destLat = widget.destLat;
    final destLng = widget.destLng;
    final destName = widget.destName;
    final recommended = data['recommended'] is Map
        ? data['recommended'] as Map<String, dynamic>
        : null;
    final alternatives = data['alternatives'] is List
        ? (data['alternatives'] as List)
            .whereType<Map<String, dynamic>>()
            .toList()
        : <Map<String, dynamic>>[];
    final reachableKm =
        (data['reachable_distance_km'] as num?)?.toDouble() ?? 0.0;
    final chargerType = data['charger_type']?.toString() ?? 'FAST';
    final totalCandidates = (data['total_candidates'] as num?)?.toInt();
    final filteredOut = (data['filtered_out_count'] as num?)?.toInt() ?? 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark ? AppColors.darkTextSecondary : _kGrey;
    // 9a: 급속 칩은 파랑 pill (badge-fast-bg), 완속은 초록 pill — 다크는 밝은 변형
    final chipFg = chargerType == 'FAST'
        ? (isDark ? AppColors.darkBlueBright : const Color(0xFF3B82F6))
        : (isDark ? AppColors.darkGreenBright : _kEvGreenDark);
    final chipBg = isDark
        ? chipFg.withValues(alpha: 0.16)
        : (chargerType == 'FAST'
            ? const Color(0xFFDBEAFE)
            : _kEvActiveCard);

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
                // ── 헤더 (9a) — [bolt 급속 pill] 주행 가능 127km · 후보 638개 ──
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            chargerType == 'FAST'
                                ? Icons.bolt_rounded
                                : Icons.electrical_services_rounded,
                            size: 14,
                            color: chipFg,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            chargerType == 'FAST' ? '급속' : '완속',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: chipFg,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          if (reachableKm > 0)
                            '주행 가능 ${reachableKm.toStringAsFixed(0)}km',
                          if (totalCandidates != null) '후보 $totalCandidates개',
                        ].join(' · '),
                        style: TextStyle(fontSize: 12, color: mutedColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── 속도 필터 완화 안내 — 선택 kW 구간 충전소가 없어 전체 급속으로 추천됨 ──
                if (data['speed_relaxed'] == true) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3A2E12)
                          : const Color(0xFFFFF7E6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: isDark
                              ? const Color(0xFF6B5518)
                              : const Color(0xFFF3DFAE),
                          width: 0.8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 15,
                            color: isDark
                                ? const Color(0xFFE8C35C)
                                : const Color(0xFFB8860B)),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '선택한 충전 속도의 충전소가 경로에 없어 전체 급속으로 추천했어요',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? const Color(0xFFE8C35C)
                                  : const Color(0xFF8A6A10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // ── AI 추천 메시지 ──
                if (recommended != null) ...[
                  _EvAiMessageBanner(
                      message: recommended['ui_message']?.toString() ?? ''),
                  const SizedBox(height: 18),
                ],

                // ── 추천 충전소 ──
                if (recommended == null)
                  _NoStationCard(filteredOut: filteredOut)
                else ...[
                  Text(
                    'AI 추천 충전소',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : const Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 6),
                  KeyedSubtree(
                    key: _keyFor(recommended['statId']?.toString()),
                    child: _StationCard(
                      station: recommended,
                      isRecommended: true,
                      chargerType: chargerType,
                      // 9a: 충전은 초록 단일 축 — 급속/완속 구분은 상단 pill 이 담당
                      accentColor: _kEvGreen,
                      accentLight: _kEvActiveCard,
                      onMapTap: onStationMapTap != null
                          ? () => onStationMapTap!(recommended)
                          : null,
                      originLat: originLat,
                      originLng: originLng,
                      destLat: destLat,
                      destLng: destLng,
                      destName: destName,
                      recommendationLabel:
                          recommended['recommendation_label']?.toString(),
                    ),
                  ),
                  if (alternatives.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    // ── 다른 후보 — 9a 아코디언 (형 확정): 접힌 행 = 이름·요금·차액,
                    //    탭하면 1순위와 동일한 상세가 펼쳐진다. 한 번에 하나만.
                    Row(
                      children: [
                        Text(
                          '다른 후보',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : const Color(0xFF0F172A)),
                        ),
                        const Spacer(),
                        Text(
                          '탭하면 상세가 열려요',
                          style: TextStyle(fontSize: 11, color: mutedColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(alternatives.length, (i) {
                      final alt = alternatives[i];
                      final altLabel = alt['recommendation_label']?.toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: KeyedSubtree(
                          key: _keyFor(alt['statId']?.toString()),
                          child: _AltAccordion(
                            station: alt,
                            rank: i + 2,
                            open: _openAlt == i,
                            onToggle: () => setState(
                                () => _openAlt = _openAlt == i ? null : i),
                            recommendedCost: _recCostOf(recommended),
                            chargerType: chargerType,
                            // 9a: 후보도 초록 단일 축 (오렌지/보라 카드 폐기)
                            accentColor: _kEvGreen,
                            accentLight: _kEvActiveCard,
                            onMapTap: onStationMapTap != null
                                ? () => onStationMapTap(alt)
                                : null,
                            originLat: originLat,
                            originLng: originLng,
                            destLat: destLat,
                            destLng: destLng,
                            destName: destName,
                            recommendationLabel: altLabel,
                          ),
                        ),
                      );
                    }),
                  ],
                  // 9a 풋노트 — 데이터 기준 안내 (+ 이용제한 제외 수)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      [
                        '충전기 상태는 5분 전 기준 · 요금은 회원가 기준이에요.',
                        if (filteredOut > 0) '이용제한 $filteredOut개소 제외됨',
                      ].join(' '),
                      style: TextStyle(
                          fontSize: 10.5, height: 1.5, color: mutedColor),
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

/// 9a 아코디언 후보 (형 확정 시안) — 접힌 행: [순위] 이름(+태그) · 가용/단가/우회 meta
/// / 우측 예상요금 + 추천 대비 차액. 탭하면 기존 후보 카드 본문(_StationCard bare)이
/// 그대로 펼쳐진다 — 운영사별 요금표·워치·올리기 미리보기 등 기능 손실 없음.
class _AltAccordion extends StatelessWidget {
  final Map<String, dynamic> station;
  final int rank;
  final bool open;
  final VoidCallback onToggle;
  final int? recommendedCost;
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

  const _AltAccordion({
    required this.station,
    required this.rank,
    required this.open,
    required this.onToggle,
    required this.recommendedCost,
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

  /// 이 후보(대표 또는 통합 sub-station)가 워치 중인지 — 접힌 행에도 벨 표시.
  bool _watching() {
    final sessionId = WatchService().session?.statId;
    if (sessionId == null) return false;
    if (station['statId']?.toString() == sessionId) return true;
    final grouped = station['grouped_stations'];
    if (grouped is List) {
      for (final gs in grouped) {
        if (gs is Map && gs['statId']?.toString() == sessionId) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final cardBorder =
        isDark ? AppColors.darkCardBorder : const Color(0xFFE8ECF0);
    final titleColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark ? AppColors.darkTextMuted : const Color(0xFF94A3B8);
    final greenD = isDark ? _kEvGreen : _kEvGreenDark;
    final dividerColor =
        isDark ? AppColors.darkCardBorder : const Color(0xFFE8ECF0);

    final avail = (station['available_count'] as num?)?.toInt() ?? 0;
    final total = (station['total_count'] as num?)?.toInt() ?? 0;
    final unitPrice = (station['unit_price_member'] as num?)?.round() ??
        (station['unit_price'] as num?)?.round();
    final detourMin = (station['detour_time_min'] as num?)?.toInt();
    final costRaw = station['est_cost_member'] ?? station['est_cost'];
    final cost = costRaw is num ? costRaw.round() : null;

    // meta — 가용은 EV 에서 요금보다 결정적일 때가 많아 접힌 줄에 꼭 넣는다.
    final metaParts = <String>[
      if (total > 0) (avail > 0 ? '$avail/$total 여유' : '만석'),
      if (unitPrice != null) '${_wonFmt.format(unitPrice)}원/kWh',
      if (detourMin != null && detourMin > 0) '+${fmtMin(detourMin)} 우회',
      if (detourMin != null && detourMin == 0) '우회 없음',
      // 유료일 때만 — 무료까지 넣으면 접힌 줄이 길어진다
      if (station['parking_free'] == false) '주차 유료',
    ];

    // 추천 대비 차액 (시안) — 싸면 초록 '저렴', 비싸면 앰버 '비쌈'. 계산 불가 시 생략.
    String? diffText;
    Color diffColor = greenD;
    if (cost != null && recommendedCost != null && cost != recommendedCost) {
      final diff = recommendedCost! - cost;
      diffText = diff > 0
          ? '${_wonFmt.format(diff)}원 저렴'
          : '${_wonFmt.format(-diff)}원 비쌈';
      diffColor = diff > 0 ? greenD : _kAmber;
    }

    // 태그 칩 — 가성비/빠른 도착 등 라벨이 있을 때만 (기본 AI 추천 문구는 후보에 무의미)
    final hasTag = recommendationLabel != null &&
        recommendationLabel != 'optimal' &&
        recommendationLabel!.isNotEmpty;
    final (tagText, _) = _labelInfo(recommendationLabel, accentColor);
    final tagFg = isDark ? AppColors.darkBlueBright : const Color(0xFF3B82F6);
    final tagBg = isDark
        ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
        : const Color(0xFFDBEAFE);

    return Container(
      // 시안: 얇은 테두리만, 그림자 없음
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 접힌 행 (탭 = 토글) ──
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text('$rank',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: muted)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  station['name']?.toString() ?? '-',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: titleColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (hasTag) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: tagBg,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(tagText,
                                      style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: tagFg)),
                                ),
                              ],
                              if (_watching()) ...[
                                const SizedBox(width: 5),
                                Icon(Icons.notifications_active_rounded,
                                    size: 13, color: accentColor),
                              ],
                            ],
                          ),
                          if (metaParts.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                if (total > 0) ...[
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color:
                                          avail > 0 ? _kEvGreen : _kAmber,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    metaParts.join(' · '),
                                    style:
                                        TextStyle(fontSize: 11, color: muted),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          cost != null
                              ? '${_wonFmt.format(cost)}원'
                              : (unitPrice != null
                                  ? '${_wonFmt.format(unitPrice)}원/kWh'
                                  : '—'),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: titleColor),
                        ),
                        if (diffText != null) ...[
                          const SizedBox(height: 2),
                          Text(diffText,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: diffColor)),
                        ],
                      ],
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
            // ── 펼침 — 기존 후보 카드 본문 그대로 (bare) ──
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: open
                  ? Column(
                      children: [
                        Divider(height: 1, color: dividerColor),
                        _StationCard(
                          station: station,
                          isRecommended: false,
                          chargerType: chargerType,
                          accentColor: accentColor,
                          accentLight: accentLight,
                          onMapTap: onMapTap,
                          originLat: originLat,
                          originLng: originLng,
                          destLat: destLat,
                          destLng: destLng,
                          destName: destName,
                          recommendationLabel: recommendationLabel,
                          bare: true,
                        ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoStationCard extends StatelessWidget {
  final int filteredOut;
  const _NoStationCard({required this.filteredOut});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkCard : const Color(0xFFF8F8F8);
    final border = isDark ? AppColors.darkCardBorder : const Color(0xFFE0E0E0);
    final primaryText =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF444444);
    final mutedText = isDark ? AppColors.darkTextSecondary : _kGrey;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Icon(Icons.ev_station_rounded, size: 36, color: mutedText),
          const SizedBox(height: 10),
          Text(
            '주행 가능 거리 내에\n이용 가능한 충전소가 없어요',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: primaryText, height: 1.4),
          ),
          if (filteredOut > 0) ...[
            const SizedBox(height: 6),
            Text(
              '(이용제한 $filteredOut개소 제외)',
              style: TextStyle(fontSize: 12, color: mutedText),
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

  /// 아코디언 펼침용(9a) — 외곽 테두리·상단 배너·이름 없이 본문만.
  /// 접힌 행이 이름·가용을 이미 보여주므로 펼침에선 중복 없이 상세만 나온다.
  final bool bare;

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
    this.bare = false,
  });

  @override
  State<_StationCard> createState() => _StationCardState();
}

class _StationCardState extends State<_StationCard> {
  bool _isExpanded = false;
  bool _raised = false; // '올리기' 미리보기 토글 (목표를 권장치까지 올린 시나리오 표시)

  @override
  void initState() {
    super.initState();
    WatchService().sessionChanged.addListener(_onWatchChanged);
  }

  @override
  void dispose() {
    WatchService().sessionChanged.removeListener(_onWatchChanged);
    super.dispose();
  }

  void _onWatchChanged() {
    if (mounted) setState(() {});
  }

  /// 글로벌 워치 세션이 해당 statId 를 가리키는지 (개별 충전소 정확 매치)
  bool _isWatching(String? statId) {
    if (statId == null) return false;
    return WatchService().session?.statId == statId;
  }

  /// 이 카드의 대표 또는 sub-station 중 하나라도 워치 중인지 (그룹 단위 인디케이터)
  bool _anyWatchingInThisCard() {
    final sessionId = WatchService().session?.statId;
    if (sessionId == null) return false;
    if (widget.station['statId']?.toString() == sessionId) return true;
    final grouped = widget.station['grouped_stations'];
    if (grouped is List) {
      for (final gs in grouped) {
        if (gs is Map && gs['statId']?.toString() == sessionId) return true;
      }
    }
    return false;
  }

  // 예상 충전 금액 — 도착 시 배터리에서 목표까지 채울 때.
  // 단일 운영사: 초록 히어로 박스(큰 금액 + 단가) / 통합: 운영사별 요금 테이블(최저 뱃지).
  Widget _estCostLine(
      double? kwh,
      int? member,
      int? nonMember,
      int? unitPriceWon,
      List<Map<String, dynamic>>? operators,
      Color labelColor,
      bool isDark) {
    String won(int v) {
      final s = v.toString();
      final b = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
        b.write(s[i]);
      }
      return b.toString();
    }

    const green = Color(0xFF16A34A);
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF16243D);
    final kwhLabel = (kwh != null && kwh > 0)
        ? '약 ${kwh.toStringAsFixed(kwh < 10 ? 1 : 0)}kWh'
        : null;
    final grouped = operators != null && operators.length > 1;

    // ── 통합 충전소: 운영사별 예상요금 테이블 (회원가 낮은 순, 최저 뱃지) ──
    if (grouped) {
      final rows = [...operators]..sort((a, b) {
          int keyOf(Map o) =>
              (o['member'] as int?) ?? (o['nonmember'] as int?) ?? 1 << 30;
          return keyOf(a).compareTo(keyOf(b));
        });
      int rowKey(Map o) =>
          (o['member'] as int?) ?? (o['nonmember'] as int?) ?? 1 << 30;
      final minVal = rowKey(rows.first);
      final divider =
          isDark ? const Color(0x1FFFFFFF) : const Color(0xFFEDF0F4);
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0x12FFFFFF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color:
                  isDark ? const Color(0x24FFFFFF) : const Color(0xFFE6EAF0)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.storefront_rounded, size: 14, color: labelColor),
                  const SizedBox(width: 6),
                  Text('운영사별 예상요금',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: labelColor)),
                  const Spacer(),
                  Text(kwhLabel != null ? '회원가 기준 · $kwhLabel' : '회원가 기준',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: labelColor.withValues(alpha: 0.8))),
                ],
              ),
            ),
            ...List.generate(rows.length, (i) {
              final o = rows[i];
              final m = o['member'] as int?;
              final n = o['nonmember'] as int?;
              final isMin = rowKey(o) == minVal;
              final main = m ?? n;
              return Container(
                decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: divider))),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: isMin
                              ? green
                              : (isDark
                                  ? const Color(0x40FFFFFF)
                                  : const Color(0xFFCBD2DC)),
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text((o['op'] ?? '').toString(),
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.2,
                              fontWeight:
                                  isMin ? FontWeight.w800 : FontWeight.w600,
                              color: ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (isMin) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: green,
                            borderRadius: BorderRadius.circular(5)),
                        child: const Text('최저',
                            style: TextStyle(
                                fontSize: 9.5,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ],
                    const Spacer(),
                    // 비회원가는 다르면 작게 병기
                    if (m != null && n != null && n != m) ...[
                      Text('비회원 ${won(n)}',
                          style: TextStyle(
                              fontSize: 10.5,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                              color: labelColor.withValues(alpha: 0.85))),
                      const SizedBox(width: 8),
                    ],
                    if (main != null)
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: won(main),
                            style: TextStyle(
                                fontSize: 15.5,
                                height: 1.1,
                                fontWeight: FontWeight.w900,
                                color: isMin ? green : ink)),
                        TextSpan(
                            text: '원',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: isMin ? green : labelColor)),
                      ])),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    }

    // ── 단일 운영사: 초록 히어로 박스 — 큰 금액 + 단가 병기 ──
    final m = member;
    final n = nonMember;
    final same = m != null && n != null && m == n;
    final main = m ?? n;
    if (main == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: green.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, size: 15, color: green),
              const SizedBox(width: 5),
              Text('예상 충전요금',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: labelColor)),
              if (unitPriceWon != null) ...[
                const SizedBox(width: 6),
                Text('· ${won(unitPriceWon)}원/kWh',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: labelColor.withValues(alpha: 0.8))),
              ],
              if (kwhLabel != null) ...[
                const Spacer(),
                Text('$kwhLabel 충전',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: labelColor.withValues(alpha: 0.8))),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: won(main),
                    style: TextStyle(
                        fontSize: 24,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        color: ink)),
                TextSpan(
                    text: '원',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: ink)),
              ])),
              if (same)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                      color: green.withValues(alpha: isDark ? 0.22 : 0.13),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('회원·비회원 동일',
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          color: green)),
                )
              else if (m != null && n != null)
                Text('회원가 기준 · 비회원 ${won(n)}원',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: labelColor)),
            ],
          ),
        ],
      ),
    );
  }

  // 충전 후 목적지 도착 예상 잔량 — 서버 판정(safe/raise/tight/over)을 색·아이콘·문구로.
  // 핵심: '부족'을 raw 잔량이 아니라 "여기서 목표를 올려 해결 가능한지"로 판단해 실행 가능한 조언을 준다.
  // 폰 폭에 관계없이 자연스럽게 줄바꿈되도록 Expanded+RichText.
  Widget _destAfterChargeLine(
      int destSoc,
      String status,
      int? targetNow,
      int? comfortTarget,
      int? maxSoc,
      String? betterAltName,
      Color accent,
      Color labelColor,
      bool isDark,
      {bool canRaise = false,
      bool isRaised = false,
      VoidCallback? onToggleRaise}) {
    // 다크: 밝은 변형 (라이트 원색은 다크 카드 위 대비 미달)
    final green = isDark ? _kEvGreen : _kEvGreenDark;
    final orange =
        isDark ? AppColors.darkOrangeBright : const Color(0xFFEA580C);
    final red = isDark ? AppColors.darkRedBright : const Color(0xFFDC2626);
    // 형 확정: 볼드는 잉크 말고 찐한 상태색 그대로 (여유=진초록) — 숫자가 살아야 읽힌다.
    final Color c;
    final IconData icon;
    final List<InlineSpan> spans;
    const pct = TextStyle(fontWeight: FontWeight.w700);
    final ct = comfortTarget ?? 100;

    switch (status) {
      case 'safe':
        c = green;
        icon = Icons.check_circle_rounded;
        // 크게 남으면(=목표를 낮춰도 여유) 시간 절약 팁을 덧붙임.
        final canLower = targetNow != null &&
            comfortTarget != null &&
            comfortTarget <= targetNow - 5;
        spans = [
          const TextSpan(text: '충전 후 목적지 도착 시 '),
          TextSpan(text: '약 $destSoc%', style: pct.copyWith(color: c)),
          TextSpan(text: canLower ? ' 남아요. 급하면 ' : ' 남아 여유 있게 도착해요'),
          if (canLower) ...[
            TextSpan(text: '$ct%', style: pct.copyWith(color: c)),
            const TextSpan(text: '만 충전해도 충분해서 시간 아껴요'),
          ],
        ];
        break;
      case 'raise':
        // 여기서 목표를 올리면 여유롭게 도착 — 실행 가능한 조언.
        c = orange;
        icon = Icons.trending_up_rounded;
        spans = [
          if (targetNow != null) ...[
            TextSpan(text: '지금 목표 $targetNow%'),
            const TextSpan(text: '로는 도착 시 '),
          ] else
            const TextSpan(text: '현재 목표로는 도착 시 '),
          TextSpan(text: '약 $destSoc%', style: pct.copyWith(color: c)),
          const TextSpan(text: ' — 여기서 '),
          TextSpan(text: '$ct%까지 충전', style: pct.copyWith(color: c)),
          const TextSpan(text: '하면 여유 있게 도착해요'),
        ];
        break;
      case 'tight':
        c = orange;
        icon = Icons.info_rounded;
        spans = [
          const TextSpan(text: '여기선 '),
          TextSpan(text: '100% 충전', style: pct.copyWith(color: c)),
          TextSpan(text: maxSoc != null ? '해도 도착 약 ' : '해도 목적지까지 빠듯해요'),
          if (maxSoc != null) ...[
            TextSpan(text: '$maxSoc%', style: pct.copyWith(color: c)),
            const TextSpan(text: '로 빠듯 — 중간이나 목적지 근처에서 한 번 더 충전 권장'),
          ],
        ];
        break;
      default: // 'over'
        c = red;
        icon = Icons.warning_amber_rounded;
        // 목적지에 더 가까운 여유 대안이 있으면 그 이름을 콕 집어 안내(도착해서 자리 지키기).
        final altTail = betterAltName != null
            ? [
                const TextSpan(text: ' — 아래 '),
                TextSpan(text: betterAltName, style: pct.copyWith(color: c)),
                const TextSpan(text: '이 더 여유롭게 도착해요'),
              ]
            : <InlineSpan>[
                TextSpan(
                    text: (maxSoc != null && maxSoc > 0)
                        ? ' — 중간에 꼭 한 번 더 충전하세요'
                        : ' — 목적지에 더 가까운 충전소를 추천드려요'),
              ];
        spans = [
          if (maxSoc != null && maxSoc > 0) ...[
            const TextSpan(text: '여기선 '),
            TextSpan(text: '100% 충전', style: pct.copyWith(color: c)),
            const TextSpan(text: '해도 도착 약 '),
            TextSpan(text: '$maxSoc%', style: pct.copyWith(color: c)),
            const TextSpan(text: '로 부족'),
          ] else ...[
            const TextSpan(text: '여기 충전만으론 목적지까지 '),
            TextSpan(text: '부족', style: pct.copyWith(color: c)),
          ],
          ...altTail,
        ];
    }

    // 9a 시안 노트 박스 — 틴트 배경(테두리 X) + 아이콘 + 본문. 상태 뱃지는 색·아이콘이
    // 대신하므로 제거 (safe 는 시안의 check_circle 초록 박스와 동일해진다).
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: c),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.55,
                    color: labelColor,
                    fontWeight: FontWeight.w500),
                children: spans,
              ),
            ),
          ),
          // '올리기/되돌리기' 미리보기 토글 — 목표상향 가능 카드에만.
          if (canRaise && onToggleRaise != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onToggleRaise,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: isRaised
                      ? c.withValues(alpha: isDark ? 0.20 : 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: c.withValues(alpha: 0.6), width: 1.2),
                ),
                child: Text(isRaised ? '되돌리기' : '올리기',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.1,
                        color: c,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupedRow(Map<String, dynamic> gs) {
    final gsStatId = gs['statId']?.toString();
    final gsOperator = gs['operator']?.toString() ?? '';
    final gsAvail = (gs['available_count'] as num?)?.toInt() ?? 0;
    final gsTotal = (gs['total_count'] as num?)?.toInt() ?? 0;
    final gsUnitPrice = (gs['unit_price'] as num?)?.round();
    final gsUnitPriceNonMember = (gs['unit_price_nonmember'] as num?)?.round();
    final gsLat = (gs['lat'] as num?)?.toDouble();
    final gsLng = (gs['lng'] as num?)?.toDouble();
    final gsName = gs['name']?.toString() ?? '';
    // 정확 매치: 이 sub-station 에 알람이 등록된 경우만 활성 표시 (정직한 표시)
    final gsIsWatching = _isWatching(gsStatId);
    final accentColor = widget.accentColor;
    final canNavigate = gsLat != null &&
        gsLng != null &&
        widget.originLat != null &&
        widget.destLat != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rowBg = isDark ? const Color(0x14FFFFFF) : const Color(0xFFF8F9FA);
    final rowBorder =
        isDark ? AppColors.darkCardBorder : const Color(0xFFE5E5E5);
    final rowText =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1F2937);
    final iconBtnFill =
        isDark ? const Color(0x1AFFFFFF) : const Color(0xFFEEEEEE);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: rowBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: rowBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Info row: status + operator + price (액션 버튼 분리) ──
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
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
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: rowText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (gsUnitPrice != null) ...[
                const SizedBox(width: 6),
                Text(
                  gsUnitPriceNonMember != null
                      ? '회원 ${_wonFmt.format(gsUnitPrice)} · 비회원 ${_wonFmt.format(gsUnitPriceNonMember)}원'
                      : '회원 ${_wonFmt.format(gsUnitPrice)}원',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: rowText,
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
                Builder(
                    builder: (ctx) => _ActionIconBtn(
                          icon: gsIsWatching
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_none_rounded,
                          iconColor: gsIsWatching
                              ? accentColor
                              : (isDark ? AppColors.darkTextSecondary : _kGrey),
                          fillColor: gsIsWatching
                              ? accentColor.withValues(alpha: 0.1)
                              : iconBtnFill,
                          onTap: () async {
                            final existingSession = WatchService().session;
                            // 이미 이 충전소 → 끄기 확인
                            if (existingSession != null &&
                                existingSession.statId == gsStatId) {
                              if (!ctx.mounted) return;
                              final shouldStop =
                                  await showWatchAlreadyActiveDialog(ctx,
                                      stationName: existingSession.stationName);
                              if (shouldStop) await WatchService().stop();
                              return;
                            }
                            // 다른 충전소 → 전환 확인 후 즉시 전환 (한 번만)
                            if (existingSession != null) {
                              if (!ctx.mounted) return;
                              final switchOk = await showWatchSwitchDialog(ctx,
                                  currentStationName:
                                      existingSession.stationName);
                              if (!switchOk) return;
                              await WatchService().stop();
                              await WatchService().start(
                                statId: gsStatId,
                                stationName: gsName,
                                etaMin: 0,
                                currentAvail: gsAvail,
                              );
                              return;
                            }
                            // 새 알림 → 받을지 확인
                            if (!ctx.mounted) return;
                            final accepted = await showDialog<bool>(
                              context: ctx,
                              builder: (dCtx) => _WatchDialog(
                                  etaMin: null, accentColor: accentColor),
                            );
                            if (accepted == true) {
                              await WatchService().start(
                                statId: gsStatId,
                                stationName: gsName,
                                etaMin: 0,
                                currentAvail: gsAvail,
                              );
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
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EvDetailScreen(stationId: gsStatId),
                      ),
                    ),
                  ),
                ),
              if (gsStatId != null && canNavigate) const SizedBox(width: 8),
              if (canNavigate)
                Expanded(
                  child: Builder(
                      builder: (ctx) => _ActionBtn(
                            icon: Icons.navigation_rounded,
                            label: '길안내',
                            color: accentColor,
                            primary: true,
                            onTap: () async {
                              if (gsStatId != null && ctx.mounted) {
                                final existingSession = WatchService().session;
                                // 이미 이 충전소면 알람 그대로 두고 길안내만 진행
                                if (existingSession != null &&
                                    existingSession.statId != gsStatId) {
                                  // 다른 충전소 → 전환 확인 후 즉시 전환
                                  final switchOk = await showWatchSwitchDialog(
                                    ctx,
                                    currentStationName:
                                        existingSession.stationName,
                                  );
                                  if (!switchOk || !ctx.mounted) return;
                                  await WatchService().stop();
                                  await WatchService().start(
                                    statId: gsStatId,
                                    stationName: gsName,
                                    etaMin: 0,
                                    currentAvail: gsAvail,
                                  );
                                } else if (existingSession == null) {
                                  // 새 알림 받을지 확인
                                  final accepted = await showDialog<bool>(
                                    context: ctx,
                                    builder: (dCtx) => _WatchDialog(
                                      etaMin: null,
                                      accentColor: accentColor,
                                    ),
                                  );
                                  if (accepted == true) {
                                    await WatchService().start(
                                      statId: gsStatId,
                                      stationName: gsName,
                                      etaMin: 0,
                                      currentAvail: gsAvail,
                                    );
                                  }
                                }
                              }
                              if (!ctx.mounted) return;
                              showViaWaypointNavigationSheet(
                                ctx,
                                originLat: widget.originLat!,
                                originLng: widget.originLng!,
                                waypointLat: gsLat,
                                waypointLng: gsLng,
                                waypointName: gsName,
                                destinationLat: widget.destLat!,
                                destinationLng: widget.destLng!,
                                destinationName: widget.destName ?? '목적지',
                                stopKind: '충전소',
                              );
                            },
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
    final unitPrice = (station['unit_price'] as num?)?.round();
    // 회원가 헤드라인 + 비회원가 별도. 구버전 서버(필드 없음) 대비 unit_price 폴백.
    final unitPriceMember =
        (station['unit_price_member'] as num?)?.round() ?? unitPrice;
    final unitPriceNonMember =
        (station['unit_price_nonmember'] as num?)?.round();
    final detourMin = (station['detour_time_min'] as num?)?.toInt();
    final oldestMin = (station['oldest_charging_min'] as num?)?.toInt();
    final originDistM = (station['origin_distance_m'] as num?)?.toInt();
    final originEtaMin = (station['origin_eta_min'] as num?)?.toInt();
    final arrivalSoc = (station['arrival_soc'] as num?)?.toInt();
    final afterChargeSoc = (station['after_charge_soc'] as num?)?.toInt();
    final destSocAfterCharge =
        (station['dest_soc_after_charge'] as num?)?.toInt();
    final destStatus = station['dest_status']?.toString();
    final destTargetNow = (station['dest_target_now'] as num?)?.toInt();
    final destComfortTarget = (station['dest_comfort_target'] as num?)?.toInt();
    final destMaxSoc = (station['dest_max_soc'] as num?)?.toInt();
    final betterAltName = station['better_alt_name']?.toString();
    final estCostMember = (station['est_cost_member'] as num?)?.toInt();
    final estCostNonMember = (station['est_cost_nonmember'] as num?)?.toInt();
    final estChargeKwh = (station['est_charge_kwh'] as num?)?.toDouble();
    final statId = station['statId']?.toString();
    final groupedStations = station['grouped_stations'] is List
        ? (station['grouped_stations'] as List)
            .whereType<Map<String, dynamic>>()
            .toList()
        : null;
    final groupedCount = (station['grouped_count'] as num?)?.toInt();
    final isGrouped = groupedStations != null && groupedStations.length > 1;
    // '올리기' 미리보기 — 서버가 권장목표 시나리오를 미리 계산해 내려줌. 탭하면 값만 스왑(재호출 X).
    final raisePreview = station['raise_preview'] is Map
        ? station['raise_preview'] as Map
        : null;
    final canRaise = raisePreview != null;
    final showRaised = _raised && canRaise;
    final effAfterCharge =
        showRaised ? (raisePreview['target'] as num?)?.toInt() : afterChargeSoc;
    final effDestSoc = showRaised
        ? (raisePreview['dest_soc'] as num?)?.toInt()
        : destSocAfterCharge;
    final effDestStatus = showRaised ? 'safe' : destStatus;
    final effKwh = showRaised
        ? (raisePreview['charge_kwh'] as num?)?.toDouble()
        : estChargeKwh;
    final effCostMember = showRaised
        ? (raisePreview['cost_member'] as num?)?.toInt()
        : estCostMember;
    final effCostNonMember = showRaised
        ? (raisePreview['cost_nonmember'] as num?)?.toInt()
        : estCostNonMember;

    // 통합(다운영사) 충전소면 예상 충전요금을 운영사별로 각각 (올린 kWh 반영).
    final estOperators = <Map<String, dynamic>>[];
    if (isGrouped && effKwh != null && effKwh > 0) {
      for (final g in groupedStations!) {
        final m = (g['unit_price'] as num?)?.round();
        final n = (g['unit_price_nonmember'] as num?)?.round();
        if (m == null && n == null) continue;
        estOperators.add({
          'op': (g['operator'] ?? '').toString(),
          'member': m != null ? (effKwh * m).round() : null,
          'nonmember': n != null ? (effKwh * n).round() : null,
        });
      }
    }
    // 운영사명 목록 — 단일은 1개, 그룹은 여러 운영사(중복 제거). 카드에 배지로 나열.
    final opNames = isGrouped
        ? groupedStations!
            .map((g) => (g['operator'] ?? '').toString())
            .where((o) => o.isNotEmpty)
            .toSet()
            .toList()
        : (operator.isNotEmpty ? <String>[operator] : <String>[]);

    // ── 9a 시안 (형 확정) — 초록 단일 축 + 병합 블록. 수치·기능은 기존 그대로 ──
    String? distLabel; // 시안은 '10km' 단독 표기 (아이콘이 출발지 기준임을 말해줌)
    if (originDistM != null && originDistM > 0) {
      distLabel = originDistM >= 1000
          ? '${(originDistM / 1000).toStringAsFixed(0)}km'
          : '${originDistM}m';
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final greenD = isDark ? _kEvGreen : _kEvGreenDark; // 다크는 밝은 변형
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final cardBorder =
        isDark ? AppColors.darkCardBorder : const Color(0xFFE8ECF0);
    final borderStrong =
        isDark ? AppColors.darkCardBorder : const Color(0xFFDDE3EC);
    final titleColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final secondary =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B);
    final mutedC = isDark ? AppColors.darkTextMuted : const Color(0xFF94A3B8);
    final blockBg = isDark
        ? Colors.black.withValues(alpha: 0.22)
        : const Color(0xFFF8FAFB);
    final chipBlueFg =
        isDark ? AppColors.darkBlueBright : const Color(0xFF3B82F6);
    final chipBlueBg = isDark
        ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
        : const Color(0xFFDBEAFE);

    final hasCharge = effAfterCharge != null &&
        arrivalSoc != null &&
        effAfterCharge > arrivalSoc;
    final costMain = effCostMember ?? effCostNonMember;

    // 헤더 상태 요약 — 시안 "6분 우회 · 5자리 여유"
    final statusParts = <String>[
      if (detourMin != null && detourMin > 0)
        '${fmtMin(detourMin)} 우회'
      else if (detourMin != null && detourMin == 0)
        '경로 이탈 없음',
      if (availCount > 1)
        '$availCount자리 여유'
      else if (availCount == 1)
        '1자리 — 서두르세요'
      else if (oldestMin != null)
        '만석 · $oldestMin분째 충전 중'
      else
        '현재 만석',
    ];

    // ── 시안 공통 조각 ──
    Widget opChip(String op) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: chipBlueBg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(op,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: chipBlueFg)),
        );

    Widget metaChip(IconData icon, String label,
            {Color? color, FontWeight? weight}) =>
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color ?? mutedC),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: weight ?? FontWeight.w400,
                    color: color ?? secondary)),
          ],
        );

    Widget outlineBtn(IconData icon, String label, VoidCallback? onTap,
            {double height = 42}) =>
        SizedBox(
          height: height,
          child: Material(
            color: cardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: borderStrong),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: secondary),
                  const SizedBox(width: 5),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: secondary)),
                ],
              ),
            ),
          ),
        );

    // ── 병합 블록 — 배터리(도착→충전 후) + 바 + 헤어라인 + 요금 히어로 ──
    Widget mergedBlock() {
      final rows = <Widget>[];
      if (arrivalSoc != null) {
        final after = hasCharge ? effAfterCharge : arrivalSoc;
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('도착 시',
                    style: TextStyle(fontSize: 10.5, color: mutedC)),
                const SizedBox(height: 2),
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '$arrivalSoc',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          letterSpacing: -0.4,
                          color: _kAmber)),
                  const TextSpan(
                      text: '%',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _kAmber)),
                ])),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  hasCharge
                      ? (effKwh != null && effKwh > 0
                          ? '약 ${effKwh.toStringAsFixed(effKwh < 10 ? 1 : 0)}kWh 충전'
                          : '충전')
                      : '목표 충전량 이상 — 바로 출발 가능',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: secondary),
                ),
              ),
            ),
            if (hasCharge)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('충전 후',
                      style: TextStyle(fontSize: 10.5, color: mutedC)),
                  const SizedBox(height: 2),
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '$after',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            letterSpacing: -0.4,
                            color: greenD)),
                    TextSpan(
                        text: '%',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: greenD)),
                  ])),
                ],
              ),
          ],
        ));
        rows.add(const SizedBox(height: 11));
        // ColoredBox 는 자식이 없으면 최소 높이(0)로 그려져 게이지가 사라진다(형 제보)
        // → 꽉 채우는 Container 로.
        rows.add(ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 7,
            width: double.infinity,
            child: Row(
              children: [
                if (arrivalSoc > 0)
                  Expanded(
                      flex: arrivalSoc, child: Container(color: _kAmber)),
                if (after > arrivalSoc)
                  Expanded(
                      flex: after - arrivalSoc,
                      child: Container(color: _kEvGreen)),
                if (after < 100)
                  Expanded(
                      flex: 100 - after,
                      child: Container(
                          color: isDark
                              ? const Color(0x22FFFFFF)
                              : const Color(0xFFE2E8F0))),
              ],
            ),
          ),
        ));
      }

      // 요금 — 단일 운영사: 히어로 행 / 통합: 운영사별 요금 테이블(기능 유지)
      Widget? costW;
      if (isGrouped && estOperators.isNotEmpty) {
        costW =
            _estCostLine(effKwh, null, null, null, estOperators, secondary, isDark);
      } else if (costMain != null) {
        costW = Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    effCostMember != null
                        ? '예상 충전요금 · 회원가'
                        : '예상 충전요금 · 비회원가',
                    style: TextStyle(fontSize: 10.5, color: mutedC)),
                const SizedBox(height: 3),
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: _wonFmt.format(costMain),
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          letterSpacing: -0.7,
                          color: titleColor)),
                  TextSpan(
                      text: '원',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: titleColor)),
                ])),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (unitPriceMember != null)
                  Text('${_wonFmt.format(unitPriceMember)}원/kWh',
                      style: TextStyle(
                          fontSize: 11, height: 1.5, color: mutedC)),
                if (effCostNonMember != null &&
                    effCostMember != null &&
                    effCostNonMember != effCostMember)
                  Text('비회원 ${_wonFmt.format(effCostNonMember)}원',
                      style: TextStyle(
                          fontSize: 11, height: 1.5, color: mutedC)),
              ],
            ),
          ],
        );
      }
      if (costW != null) {
        if (rows.isNotEmpty) {
          rows.add(const SizedBox(height: 11));
          rows.add(Container(height: 1, color: cardBorder));
          rows.add(const SizedBox(height: 11));
        }
        rows.add(costW);
      }
      if (rows.isEmpty) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: blockBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: rows),
      );
    }

    final mergedW = mergedBlock();
    final hasMerged = mergedW is! SizedBox;

    // ── 메타 칩 행 — near_me 10km · schedule 약 8분 · turn_right +6분 우회 ──
    final metaChips = <Widget>[
      if (distLabel != null) metaChip(Icons.near_me_rounded, distLabel),
      if (originEtaMin != null && originEtaMin > 0)
        metaChip(Icons.schedule_rounded, '약 ${fmtMin(originEtaMin)}'),
      if (detourMin != null && detourMin > 0)
        // 시안: 1순위는 초록, 펼친 후보는 앰버
        metaChip(Icons.turn_right_rounded, '+${fmtMin(detourMin)} 우회',
            color: widget.bare ? _kAmber : greenD, weight: FontWeight.w600),
      if (detourMin != null && detourMin == 0)
        metaChip(Icons.check_circle_rounded, '경로 이탈 없음',
            color: greenD, weight: FontWeight.w600),
      if (unitPriceMember == null && unitPriceNonMember == null)
        metaChip(Icons.bolt_rounded, '가격 미공개'),
      // 주차 무료/유료 (형 확정) — 서버 parking_free. 구서버 응답(필드 없음)은 미표시.
      if (station['parking_free'] == true)
        metaChip(Icons.local_parking_rounded, '주차 무료'),
      if (station['parking_free'] == false)
        metaChip(Icons.local_parking_rounded, '주차 유료',
            color: _kAmber, weight: FontWeight.w600),
    ];

    return Container(
      decoration: widget.bare
          ? null
          : BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.isRecommended ? _kEvGreen : cardBorder,
                width: widget.isRecommended ? 1.5 : 1,
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 — [AI 추천] 6분 우회 · 5자리 여유 ──────── ● 5/5 가용 ──
          if (!widget.bare)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? _kEvGreen.withValues(alpha: 0.07)
                    : widget.accentLight,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12.5)),
              ),
              child: Row(
                children: [
                  Builder(builder: (_) {
                    final (badgeText, _) =
                        _labelInfo(widget.recommendationLabel, _kEvGreen);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _kEvGreen,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(badgeText,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    );
                  }),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusParts.join(' · '),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: titleColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_anyWatchingInThisCard()) ...[
                    Icon(Icons.notifications_active_rounded,
                        size: 14, color: greenD),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: availCount > 0 ? _kEvGreen : _kAmber,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('$availCount/$totalCount 가용',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: greenD)),
                ],
              ),
            ),

          // ── 본문 ──
          Padding(
            padding: widget.bare
                ? const EdgeInsets.fromLTRB(14, 12, 14, 14)
                : const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.bare) ...[
                  Text(
                    name,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        letterSpacing: -0.3,
                        color: titleColor),
                  ),
                  const SizedBox(height: 5),
                ],
                // 운영사 칩(파랑) + 주소 — 통합이면 칩 여러 개 + 통합 표기
                if (!isGrouped)
                  Row(
                    children: [
                      if (opNames.isNotEmpty) ...[
                        opChip(opNames.first),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          address,
                          style: TextStyle(fontSize: 11.5, color: mutedC),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                else ...[
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final op in opNames) opChip(op),
                      Text(
                          '${groupedCount ?? groupedStations!.length}개 운영사 통합',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: mutedC)),
                    ],
                  ),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      address,
                      style: TextStyle(fontSize: 11.5, color: mutedC),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
                if (hasMerged) ...[
                  const SizedBox(height: 12),
                  mergedW,
                ],
                // 충전 후 목적지 잔량 안내 — 4단계 판정 + 올리기 미리보기 (기능 유지)
                if (effDestSoc != null && effDestStatus != null) ...[
                  const SizedBox(height: 12),
                  _destAfterChargeLine(
                      effDestSoc,
                      effDestStatus,
                      destTargetNow,
                      destComfortTarget,
                      destMaxSoc,
                      betterAltName,
                      _kEvGreen,
                      secondary,
                      isDark,
                      canRaise: canRaise,
                      isRaised: _raised,
                      onToggleRaise: canRaise
                          ? () => setState(() => _raised = !_raised)
                          : null),
                ],
                if (headingCount > 0) ...[
                  const SizedBox(height: 12),
                  _HeadingBadge(
                      headingCount: headingCount, availCount: availCount),
                ],
                if (metaChips.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, runSpacing: 6, children: metaChips),
                ],
                // ── 그룹 운영사 펼치기 — 인라인 링크가 안 보인다(형 제보) →
                //    풀너비 토널 버튼(40px)으로 키워 명확한 탭 타깃으로.
                if (isGrouped) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    width: double.infinity,
                    child: Material(
                      color: _kEvGreen.withValues(alpha: isDark ? 0.16 : 0.10),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () =>
                            setState(() => _isExpanded = !_isExpanded),
                        borderRadius: BorderRadius.circular(10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.storefront_rounded,
                                size: 15, color: greenD),
                            const SizedBox(width: 6),
                            Text(
                              _isExpanded
                                  ? '운영사 접기'
                                  : '${groupedCount ?? groupedStations!.length}개 운영사별 길안내 보기',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: greenD,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _isExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: greenD,
                            ),
                          ],
                        ),
                      ),
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

                // ── 액션 버튼 — 형 확정 통일안 (1순위·펼친 후보 동일):
                //    단일 운영사: [지도에서 보기][충전소 상세] + 풀너비 [길안내 시작]
                //    통합: 위에 운영사별 보기가 있으니 [지도에서 보기][길안내 시작]
                //    가로 한 줄 — 상세 자리가 비어 지도가 혼자 풀너비로 뜨던 것 해소.
                if (isGrouped) ...[
                  if (widget.onMapTap != null ||
                      (widget.originLat != null && widget.destLat != null)) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 46,
                      child: Row(
                        // stretch 필수 — 없으면 CTA Material 이 내용 높이로
                        // 쪼그라들어 옆 지도 버튼보다 납작해진다(형 제보).
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.onMapTap != null)
                            Expanded(
                                child: outlineBtn(Icons.map_outlined,
                                    '지도에서 보기', widget.onMapTap,
                                    height: 46)),
                          if (widget.onMapTap != null &&
                              widget.originLat != null &&
                              widget.destLat != null)
                            const SizedBox(width: 8),
                          if (widget.originLat != null &&
                              widget.destLat != null)
                            Expanded(
                              child: Material(
                                color: _kEvGreen,
                                borderRadius: BorderRadius.circular(10),
                                child: Builder(
                                  builder: (ctx) => InkWell(
                                    onTap: () => _startNavigation(ctx,
                                        statId: statId,
                                        availCount: availCount,
                                        originEtaMin: originEtaMin),
                                    borderRadius: BorderRadius.circular(10),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.navigation_rounded,
                                            size: 18, color: Colors.white),
                                        SizedBox(width: 5),
                                        Text('길안내 시작',
                                            style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  if (widget.onMapTap != null || statId != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (widget.onMapTap != null)
                          Expanded(
                              child: outlineBtn(Icons.map_outlined,
                                  '지도에서 보기', widget.onMapTap)),
                        if (widget.onMapTap != null && statId != null)
                          const SizedBox(width: 8),
                        if (statId != null)
                          Expanded(
                            child: outlineBtn(
                                Icons.info_outline_rounded, '충전소 상세', () {
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      EvDetailScreen(stationId: statId),
                                ),
                              );
                            }),
                          ),
                      ],
                    ),
                  ],
                  if (widget.originLat != null && widget.destLat != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: Material(
                        color: _kEvGreen,
                        borderRadius: BorderRadius.circular(12),
                        child: Builder(
                          builder: (ctx) => InkWell(
                            onTap: () => _startNavigation(ctx,
                                statId: statId,
                                availCount: availCount,
                                originEtaMin: originEtaMin),
                            borderRadius: BorderRadius.circular(12),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.navigation_rounded,
                                    size: 19, color: Colors.white),
                                SizedBox(width: 6),
                                Text('길안내 시작',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
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

  /// 길안내 시작 — 워치(빈자리 알림) 제안/전환 확인 후 경유 길안내 시트 (기존 로직 그대로).
  Future<void> _startNavigation(BuildContext ctx,
      {required String? statId,
      required int availCount,
      int? originEtaMin}) async {
    final station = widget.station;
    final stLat = (station['lat'] as num?)?.toDouble();
    final stLng = (station['lng'] as num?)?.toDouble();
    final stName = station['name']?.toString() ?? '충전소';
    if (stLat == null || stLng == null) return;
    if (widget.originLat == null || widget.destLat == null) return;
    if (statId != null && ctx.mounted) {
      final existingSession = WatchService().session;
      // 이미 이 충전소면 알람 그대로 두고 길안내만 진행
      if (existingSession != null && existingSession.statId != statId) {
        // 다른 충전소 → 전환 확인 후 즉시 전환
        final switchOk = await showWatchSwitchDialog(
          ctx,
          currentStationName: existingSession.stationName,
        );
        if (!switchOk || !ctx.mounted) return;
        await WatchService().stop();
        await WatchService().start(
          statId: statId,
          stationName: stName,
          etaMin: originEtaMin ?? 0,
          currentAvail: availCount,
        );
      } else if (existingSession == null) {
        // 새 알림 받을지 확인
        final accepted = await showDialog<bool>(
          context: ctx,
          builder: (dCtx) => _WatchDialog(
            etaMin: originEtaMin,
            accentColor: _kEvGreen,
          ),
        );
        if (accepted == true) {
          await WatchService().start(
            statId: statId,
            stationName: stName,
            etaMin: originEtaMin ?? 0,
            currentAvail: availCount,
          );
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
      stopKind: '충전소',
    );
  }
}

/// 일관된 액션 버튼.
/// - primary=true → filled (accent bg, 흰 글자) — 메인 CTA
/// - primary=false → tonal (accent.withValues(alpha: 0.08), accent 글자) — 보조
/// 최소 높이 44pt (Apple HIG 터치 타깃), Material InkWell 리플 포함.
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool primary;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : color;
    final bg = primary ? color : color.withValues(alpha: 0.10);
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
    return btn;
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
          width: 44,
          height: 44,
          child: Center(child: Icon(icon, size: 18, color: iconColor)),
        ),
      ),
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

class _HeadingBadgeState extends State<_HeadingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.55, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 다크: Material-700 라이트 톤은 대비 미달 → 밝은 변형
    final Color color = crowd
        ? (isDark ? AppColors.darkRedBright : const Color(0xFFD32F2F))
        : tight
            ? (isDark ? AppColors.darkOrangeBright : const Color(0xFFEF6C00))
            : (isDark ? AppColors.darkBlueBright : const Color(0xFF1976D2));

    final String label = crowd
        ? '$h명이 향하는 중 · 자리보다 많음'
        : tight
            ? '$h명이 향하는 중 · 자리 빠듯'
            : '$h명이 향하는 중';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: color.withValues(alpha: isDark ? 0.35 : 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 라이브 신호 도트 (페이드 펄스)
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color.withValues(alpha: _pulse.value),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: color.withValues(alpha: _pulse.value * 0.5),
                      blurRadius: 4,
                      spreadRadius: 1)
                ],
              ),
            ),
          ),
          const SizedBox(width: 7),
          Icon(Icons.directions_car_filled_rounded, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _HandleDelegate extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 24;
  @override
  double get maxExtent => 24;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: isDark ? AppColors.darkBg : Colors.white,
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkTextMuted : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

// ── EV 사용자 선택 모드 리스트 ──
class EvSelectList extends StatelessWidget {
  final List<Map<String, dynamic>> candidates;
  final String chargerType;
  // 선택한 kW 속도 구간 충전소가 경로에 없어 전체 급속으로 완화됐는지
  final bool speedRelaxed;
  final ScrollController scrollController;
  final void Function(Map<String, dynamic>) onSelect;

  const EvSelectList({
    required this.candidates,
    required this.chargerType,
    this.speedRelaxed = false,
    required this.scrollController,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = chargerType == 'FAST'
        ? (isDark ? AppColors.darkBlueBright : _kBlue)
        : (isDark ? AppColors.darkGreenBright : _kGreen);
    final mutedColor = isDark ? AppColors.darkTextSecondary : _kGrey;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final cardBorder =
        isDark ? AppColors.darkCardBorder : const Color(0xFFE5E5E5);
    final nameColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
    final priceColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF444444);
    final chevronColor =
        isDark ? AppColors.darkTextMuted : Colors.grey.shade400;

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverPersistentHeader(pinned: true, delegate: _HandleDelegate()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Icon(
                    chargerType == 'FAST'
                        ? Icons.bolt_rounded
                        : Icons.electrical_services_rounded,
                    size: 15,
                    color: accentColor),
                const SizedBox(width: 5),
                Text(
                  '${chargerType == 'FAST' ? '급속' : '완속'} 충전소 ${candidates.length}개',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: accentColor),
                ),
                const SizedBox(width: 6),
                Text('· 경로 가까운 순 · 가용 우선',
                    style: TextStyle(fontSize: 12, color: mutedColor)),
              ],
            ),
          ),
        ),
        if (speedRelaxed)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '선택한 충전 속도의 충전소가 경로에 없어 전체 급속을 표시했어요',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? const Color(0xFFE8C35C)
                        : const Color(0xFF8A6A10)),
              ),
            ),
          ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final s = candidates[i];
              final originalName = s['name']?.toString() ?? '-';
              final stationId =
                  s['stat_id']?.toString() ?? s['statId']?.toString() ?? '';
              final name = stationId.isEmpty
                  ? originalName
                  : StationAliasService.resolveEv(stationId, originalName);
              final operator = s['operator']?.toString() ?? '';
              final avail = (s['available_count'] as num?)?.toInt() ?? 0;
              final total = (s['total_count'] as num?)?.toInt() ?? 0;
              final unitPrice = (s['unit_price'] as num?)?.round();
              final unitPriceMember =
                  (s['unit_price_member'] as num?)?.round() ?? unitPrice;
              final unitPriceNonMember =
                  (s['unit_price_nonmember'] as num?)?.round();
              final routeDistM = (s['route_distance_m'] as num?)?.toInt() ?? 0;
              final originDistM = (s['origin_distance_m'] as num?)?.toInt();
              final originEtaMin = (s['origin_eta_min'] as num?)?.toInt();
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
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOnRoute
                          ? accentColor.withValues(alpha: 0.4)
                          : cardBorder,
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.18 : 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2))
                    ],
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: accentColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('경로상',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Expanded(
                                  child: Text(name,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: nameColor),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                            if (operator.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(operator,
                                  style: TextStyle(
                                      fontSize: 11, color: mutedColor),
                                  overflow: TextOverflow.ellipsis),
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
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: avail > 0 ? _kGreen : _kOrange,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text('$avail/$total 가용',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: avail > 0
                                                ? _kGreen
                                                : _kOrange)),
                                  ],
                                ),
                                if (originLabel != null)
                                  Text(originLabel,
                                      style: TextStyle(
                                          fontSize: 11, color: mutedColor)),
                                if (originEtaMin != null && originEtaMin > 0)
                                  Text('약 ${fmtMin(originEtaMin)} 소요',
                                      style: TextStyle(
                                          fontSize: 11, color: mutedColor)),
                                if (unitPriceMember != null)
                                  Text(
                                      '회원 ${_wonFmt.format(unitPriceMember)}원/kWh',
                                      style: TextStyle(
                                          fontSize: 11, color: priceColor)),
                                if (unitPriceNonMember != null)
                                  Text(
                                      '비회원 ${_wonFmt.format(unitPriceNonMember)}원/kWh',
                                      style: TextStyle(
                                          fontSize: 11, color: mutedColor)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right_rounded,
                          color: chevronColor, size: 20),
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

  /// `**볼드**` 만 직접 파싱 — 시안대로 숫자 볼드는 초록, 이름 볼드는 잉크로
  /// 나눠 칠한다. MarkdownBody 는 강조색이 한 가지뿐이고, 한글 플랭킹 때문에
  /// ** 가 그대로 노출되는 케이스도 있었는데 직접 파싱이라 그 문제도 사라진다.
  List<InlineSpan> _spans(String src, Color ink, Color green) {
    final out = <InlineSpan>[];
    int last = 0;
    for (final m in RegExp(r'\*\*(.+?)\*\*').allMatches(src)) {
      if (m.start > last) out.add(TextSpan(text: src.substring(last, m.start)));
      final t = m.group(1)!.trim();
      out.add(TextSpan(
        text: t,
        style: TextStyle(
            fontWeight: FontWeight.w700,
            color: RegExp(r'\d').hasMatch(t) ? green : ink),
      ));
      last = m.end;
    }
    if (last < src.length) out.add(TextSpan(text: src.substring(last)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    final normalized = message.replaceAll(r'\n', '\n');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 9a: 초록 그라디언트 요약 박스 (ev-summary-grad) — 아이콘 + 본문, 타이틀 없음
    final greenD = isDark ? _kEvGreen : _kEvGreenDark;
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final secondary =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF064E3B), Color(0xFF111827)]
              : const [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.auto_awesome_rounded, size: 19, color: greenD),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style:
                    TextStyle(fontSize: 12.5, height: 1.6, color: secondary),
                children: _spans(normalized, ink, greenD),
              ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1A1F2C) : Colors.white;
    final titleColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
    final descColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final cancelTextColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);
    final cancelBorderColor =
        isDark ? AppColors.darkCardBorder : Colors.grey.shade300;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: dialogBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.20 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.radar_rounded, size: 32, color: accentColor),
            ),
            const SizedBox(height: 16),
            Text(
              '실시간 현황 알림',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: titleColor),
            ),
            const SizedBox(height: 10),
            Text(
              etaMin != null && etaMin! > 0
                  ? '약 ${fmtMin(etaMin!)} 소요 예정이에요.\n이동하는 동안 자리 변동 시\n알림을 드릴게요.'
                  : '이동하는 동안 자리 변동 시\n알림을 드릴게요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: descColor, height: 1.65),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: cancelBorderColor),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: Text(
                      '나중에',
                      style: TextStyle(
                          color: cancelTextColor, fontWeight: FontWeight.w600),
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('받기',
                        style: TextStyle(fontWeight: FontWeight.w700)),
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
