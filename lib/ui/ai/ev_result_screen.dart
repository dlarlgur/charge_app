import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/navigation_util.dart';
import '../../data/services/station_alias_service.dart';
import '../../data/services/watch_service.dart';
import '../detail/ev_detail_screen.dart';
import '../widgets/watch_switch_dialog.dart';

// CommonMark: 닫는 ** 앞이 문장부호(%,/ 등)이고 바로 뒤가 한글이면 볼드 파싱 실패(**25%**로).
// 닫는 ** "앞"에 ZWSP 삽입해 부호 플랭킹 회피. (비표시 → 잘 되던 케이스 영향 없음)
String _normalizeMarkdownForKoreanEv(String src) {
  final zwsp = String.fromCharCode(0x200B);
  // 1) "** 텍스트 **" 안쪽 공백 제거 (CommonMark 가 볼드로 안 봐 ** 노출되는 케이스)
  var s = src.replaceAllMapped(
    RegExp(r'\*\*[ \t]*([^*\n]+?)[ \t]*\*\*'),
    (m) => '**${m.group(1)!}**',
  );
  // 2) 닫는 ** 앞 부호 + 뒤 한글 케이스(**25%**로) → 닫는 ** 앞에 ZWSP
  s = s.replaceAllMapped(
    RegExp(r'\*\*([^\n*][^\n*]*?)\*\*(?=[가-힣])'),
    (m) => '**${m.group(1)!}$zwsp**',
  );
  return s;
}

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

  /// 외부에서 호출 — 해당 statId 의 카드를 화면에 보이도록 스크롤.
  Future<void> scrollToStation(String statId) async {
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
    // FAST/SLOW 칩의 light 배경은 다크에서 너무 밝게 튀므로 accent 16% alpha 로 lift.
    final chipBg = isDark
        ? (chargerType == 'FAST' ? _kBlue : _kGreen).withValues(alpha: 0.16)
        : (chargerType == 'FAST' ? _kBlueLight : _kGreenLight);

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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            chargerType == 'FAST'
                                ? Icons.bolt_rounded
                                : Icons.electrical_services_rounded,
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
                        style: TextStyle(fontSize: 13, color: mutedColor),
                      ),
                    ],
                    if (totalCandidates != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '· 후보 $totalCandidates개',
                        style: TextStyle(fontSize: 12, color: mutedColor),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),

                // ── AI 추천 메시지 ──
                if (recommended != null) ...[
                  _EvAiMessageBanner(
                      message: recommended['ui_message']?.toString() ?? ''),
                  const SizedBox(height: 14),
                ],

                // ── 추천 충전소 ──
                if (recommended == null)
                  _NoStationCard(filteredOut: filteredOut)
                else ...[
                  Text(
                    'AI 추천 충전소',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: mutedColor),
                  ),
                  const SizedBox(height: 8),
                  KeyedSubtree(
                    key: _keyFor(recommended['statId']?.toString()),
                    child: _StationCard(
                      station: recommended,
                      isRecommended: true,
                      chargerType: chargerType,
                      accentColor: chargerType == 'FAST' ? _kBlue : _kGreen,
                      accentLight:
                          chargerType == 'FAST' ? _kBlueLight : _kGreenLight,
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
                    const SizedBox(height: 20),
                    Text(
                      '다른 후보',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: mutedColor),
                    ),
                    const SizedBox(height: 8),
                    ...alternatives.map((alt) {
                      final altLabel = alt['recommendation_label']?.toString();
                      final (_, altColor) = _labelInfo(altLabel, _kOrange);
                      final altLight =
                          Color.lerp(altColor, Colors.white, 0.92) ??
                              _kOrangeLight;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: KeyedSubtree(
                          key: _keyFor(alt['statId']?.toString()),
                          child: _StationCard(
                            station: alt,
                            isRecommended: false,
                            chargerType: chargerType,
                            accentColor: altColor,
                            accentLight: altLight,
                            onMapTap: onStationMapTap != null
                                ? () => onStationMapTap!(alt)
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
                  if (filteredOut > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '* 이용제한 $filteredOut개소 제외됨',
                        style: TextStyle(fontSize: 11, color: mutedColor),
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
  bool _isExpanded = false;

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

  // 도착 시 배터리 잔량 → 충전 후 잔량 예측. 각 숫자에 라벨(도착 시 / 충전 후)을 붙여 명확하게.
  Widget _socBar(int arrival, int? afterCharge, int? chargeMin, Color accent,
      Color mutedColor, bool isDark, {int? destSoc}) {
    final after =
        (afterCharge != null && afterCharge > arrival) ? afterCharge : arrival;
    final hasCharge = after > arrival;
    final trackBg = isDark ? const Color(0x22FFFFFF) : const Color(0xFFE8ECF1);
    final labelColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B);
    const green = Color(0xFF16A34A);

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 도착 시
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.battery_charging_full_rounded,
                          size: 13, color: accent),
                      const SizedBox(width: 3),
                      Text('도착 시',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: labelColor)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('$arrival%',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: accent)),
                ],
              ),
              if (hasCharge) ...[
                // 가운데 — '충전' 표시(화살표). 충전 소요시간은 차량 수용속도(차종별 상이)를
                // 반영 못 해 부정확하므로 분 표시는 하지 않음(SOC 예측만 노출).
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('충전',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: labelColor)),
                      const SizedBox(height: 1),
                      Icon(Icons.arrow_right_alt_rounded,
                          size: 22, color: mutedColor),
                    ],
                  ),
                ),
                // 충전 후
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('충전 후',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: labelColor)),
                    const SizedBox(height: 2),
                    Text('$after%',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            color: green)),
                  ],
                ),
              ] else
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text('목표 충전량 이상 — 바로 출발 가능',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: labelColor)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // 바 — 도착(진한 accent) + 충전 후(연한 accent)
          SizedBox(
            height: 7,
            child: LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth;
              return Stack(
                children: [
                  Container(
                      width: w,
                      height: 7,
                      decoration: BoxDecoration(
                          color: trackBg,
                          borderRadius: BorderRadius.circular(99))),
                  if (hasCharge)
                    Container(
                        width: w * (after / 100).clamp(0.0, 1.0),
                        height: 7,
                        decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.32),
                            borderRadius: BorderRadius.circular(99))),
                  Container(
                      width: w * (arrival / 100).clamp(0.0, 1.0),
                      height: 7,
                      decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(99))),
                ],
              );
            }),
          ),
          // 충전 후 목적지 도착 예상 잔량 (여유=초록 / 빠듯=주황)
          if (destSoc != null) ...[
            const SizedBox(height: 10),
            _destAfterChargeLine(destSoc, accent, labelColor, isDark),
          ],
        ],
      ),
    );
  }

  // 이 충전소에서 목표 충전 후 목적지까지 갔을 때 예상 잔량 — 확신 닫아주는 보조 한 줄.
  Widget _destAfterChargeLine(
      int destSoc, Color accent, Color labelColor, bool isDark) {
    const green = Color(0xFF16A34A);
    const orange = Color(0xFFEA580C);
    final tight = destSoc < 10;
    final comfortable = destSoc >= 20;
    final c = tight ? orange : (comfortable ? green : accent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
                tight ? Icons.warning_amber_rounded : Icons.flag_rounded,
                size: 15,
                color: c),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: labelColor,
                    fontWeight: FontWeight.w600),
                children: tight
                    ? [
                        const TextSpan(
                            text: '여기 충전만으론 목적지까지 빠듯해요 — 도착 시 '),
                        TextSpan(
                            text: '$destSoc%',
                            style: TextStyle(
                                color: c, fontWeight: FontWeight.w800)),
                      ]
                    : [
                        const TextSpan(text: '충전 후 목적지 도착 시 '),
                        TextSpan(
                            text: '약 $destSoc%',
                            style: TextStyle(
                                color: c, fontWeight: FontWeight.w800)),
                        TextSpan(
                            text: comfortable ? ' 남아 여유 있게 도착해요' : ' 남아요'),
                      ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedRow(Map<String, dynamic> gs) {
    final gsStatId = gs['statId']?.toString();
    final gsOperator = gs['operator']?.toString() ?? '';
    final gsAvail = (gs['available_count'] as num?)?.toInt() ?? 0;
    final gsTotal = (gs['total_count'] as num?)?.toInt() ?? 0;
    final gsUnitPrice = (gs['unit_price'] as num?)?.toInt();
    final gsUnitPriceNonMember = (gs['unit_price_nonmember'] as num?)?.toInt();
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
    final unitPrice = (station['unit_price'] as num?)?.toInt();
    // 회원가 헤드라인 + 비회원가 별도. 구버전 서버(필드 없음) 대비 unit_price 폴백.
    final unitPriceMember =
        (station['unit_price_member'] as num?)?.toInt() ?? unitPrice;
    final unitPriceNonMember =
        (station['unit_price_nonmember'] as num?)?.toInt();
    final detourMin = (station['detour_time_min'] as num?)?.toInt();
    final oldestMin = (station['oldest_charging_min'] as num?)?.toInt();
    final originDistM = (station['origin_distance_m'] as num?)?.toInt();
    final originEtaMin = (station['origin_eta_min'] as num?)?.toInt();
    final arrivalSoc = (station['arrival_soc'] as num?)?.toInt();
    final afterChargeSoc = (station['after_charge_soc'] as num?)?.toInt();
    final destSocAfterCharge = (station['dest_soc_after_charge'] as num?)?.toInt();
    final chargingMin = (station['charging_time_min'] as num?)?.toInt();
    final statId = station['statId']?.toString();
    final groupedStations = station['grouped_stations'] is List
        ? (station['grouped_stations'] as List)
            .whereType<Map<String, dynamic>>()
            .toList()
        : null;
    final groupedCount = (station['grouped_count'] as num?)?.toInt();
    final isGrouped = groupedStations != null && groupedStations.length > 1;
    // 운영사명 목록 — 단일은 1개, 그룹은 여러 운영사(중복 제거). 카드에 배지로 나열.
    final opNames = isGrouped
        ? groupedStations!
            .map((g) => (g['operator'] ?? '').toString())
            .where((o) => o.isNotEmpty)
            .toSet()
            .toList()
        : (operator.isNotEmpty ? <String>[operator] : <String>[]);

    String? originDistLabel;
    if (originDistM != null && originDistM > 0) {
      originDistLabel = originDistM >= 1000
          ? '출발지에서 ${(originDistM / 1000).toStringAsFixed(0)}km'
          : '출발지에서 ${originDistM}m';
    }

    final accentColor = widget.accentColor;
    final accentLight = widget.accentLight;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final cardBorder =
        isDark ? AppColors.darkCardBorder : const Color(0xFFE5E5E5);
    final titleColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
    final mutedTextColor = isDark ? AppColors.darkTextSecondary : _kGrey;
    final dividerColor =
        isDark ? AppColors.darkCardBorder : const Color(0xFFEEEEEE);
    // 다크 모드에서는 accentLight (Color.lerp white) 가 너무 밝게 튀므로 accent 16% alpha 로 부드럽게.
    final headerBg = isDark ? accentColor.withValues(alpha: 0.16) : accentLight;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isRecommended ? accentColor : cardBorder,
          width: widget.isRecommended ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
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
              color: headerBg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                if (widget.isRecommended ||
                    widget.recommendationLabel != null) ...[
                  Builder(builder: (_) {
                    final (badgeText, badgeColor) =
                        _labelInfo(widget.recommendationLabel, accentColor);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
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
                // 워치 벨 아이콘 — 글로벌 세션이 이 카드의 대표 statId 또는 어느 sub-station 을 가리키면 표시
                if (_anyWatchingInThisCard()) ...[
                  Icon(
                    Icons.notifications_active_rounded,
                    size: 15,
                    color: accentColor,
                  ),
                  const SizedBox(width: 8),
                ],
                // 충전기 현황
                _ChargerDot(
                    avail: availCount,
                    total: totalCount,
                    accentColor: accentColor),
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
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: titleColor),
                ),
                // 운영사 배지 — 단일 1개 / 그룹은 여러 운영사 나열(보기 좋게 칩으로).
                if (opNames.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final op in opNames)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.ev_station_rounded,
                                  size: 12, color: accentColor),
                              const SizedBox(width: 3),
                              Text(op,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: accentColor)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                if (isGrouped) ...[
                  const SizedBox(height: 4),
                  Text('${groupedCount ?? groupedStations!.length}개 운영사 통합',
                      style: TextStyle(
                          fontSize: 11,
                          color: mutedTextColor,
                          fontWeight: FontWeight.w600)),
                ],
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    address,
                    style: TextStyle(fontSize: 12, color: mutedTextColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // 도착 시 배터리 잔량 → 충전 후 예측
                if (arrivalSoc != null) ...[
                  const SizedBox(height: 11),
                  _socBar(arrivalSoc, afterChargeSoc, chargingMin, accentColor,
                      mutedTextColor, isDark, destSoc: destSocAfterCharge),
                ],
                const SizedBox(height: 10),
                if (headingCount > 0) ...[
                  _HeadingBadge(
                      headingCount: headingCount, availCount: availCount),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    // 회원가 = 실결제가 → accent 채움 칩으로 도드라지게.
                    if (unitPriceMember != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(
                              alpha: isDark ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: accentColor.withValues(alpha: 0.45)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt_rounded,
                                size: 14, color: accentColor),
                            const SizedBox(width: 3),
                            Text('회원 ',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: accentColor)),
                            Text('${_wonFmt.format(unitPriceMember)}원/kWh',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: accentColor)),
                          ],
                        ),
                      ),
                    if (unitPriceNonMember != null)
                      _InfoChip(
                        icon: Icons.person_outline_rounded,
                        label: '비회원 ${_wonFmt.format(unitPriceNonMember)}원/kWh',
                        color: _kGrey,
                      ),
                    if (unitPriceMember == null && unitPriceNonMember == null)
                      _InfoChip(
                        icon: Icons.bolt_rounded,
                        label: '가격 미공개',
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : const Color(0xFF444444),
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
                  Divider(height: 1, color: dividerColor),
                  const SizedBox(height: 12),
                  // ── 보조 액션 (지도 / 상세) — 50:50 또는 단독 ──
                  if (widget.onMapTap != null ||
                      (statId != null && !isGrouped)) ...[
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
                        if (widget.onMapTap != null &&
                            statId != null &&
                            !isGrouped)
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
                                    builder: (_) =>
                                        EvDetailScreen(stationId: statId),
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
                    Builder(
                        builder: (ctx) => _ActionBtn(
                              icon: Icons.navigation_rounded,
                              label: '길안내 시작',
                              color: accentColor,
                              primary: true,
                              fullWidth: true,
                              onTap: () async {
                                final stLat =
                                    (station['lat'] as num?)?.toDouble();
                                final stLng =
                                    (station['lng'] as num?)?.toDouble();
                                final stName =
                                    station['name']?.toString() ?? '충전소';
                                if (stLat == null || stLng == null) return;
                                // 워치 제안 다이얼로그
                                if (statId != null && ctx.mounted) {
                                  final existingSession =
                                      WatchService().session;
                                  // 이미 이 충전소면 알람 그대로 두고 길안내만 진행
                                  if (existingSession != null &&
                                      existingSession.statId != statId) {
                                    // 다른 충전소 → 전환 확인 후 즉시 전환
                                    final switchOk =
                                        await showWatchSwitchDialog(
                                      ctx,
                                      currentStationName:
                                          existingSession.stationName,
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
                                        accentColor: accentColor,
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
/// - primary=false → tonal (accent.withValues(alpha: 0.08), accent 글자) — 보조
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
          width: 44,
          height: 44,
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

  const _ChargerDot(
      {required this.avail, required this.total, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
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

  const _InfoChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w500)),
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

    final Color color = crowd
        ? const Color(0xFFD32F2F) // 빨강 — 자리 부족
        : tight
            ? const Color(0xFFEF6C00) // 진한 주황 — 딱 맞음
            : const Color(0xFF1976D2); // 파랑 — 여유

    final String label = crowd
        ? '$h명이 향하는 중 · 자리보다 많음'
        : tight
            ? '$h명이 향하는 중 · 자리 빠듯'
            : '$h명이 향하는 중';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
              final unitPrice = (s['unit_price'] as num?)?.toInt();
              final unitPriceMember =
                  (s['unit_price_member'] as num?)?.toInt() ?? unitPrice;
              final unitPriceNonMember =
                  (s['unit_price_nonmember'] as num?)?.toInt();
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

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    final normalized =
        _normalizeMarkdownForKoreanEv(message.replaceAll(r'\n', '\n'));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        isDark ? _kBlue.withValues(alpha: 0.12) : const Color(0xFFEEF4FF);
    final border =
        isDark ? _kBlue.withValues(alpha: 0.35) : const Color(0xFFB8D0FF);
    final iconBg =
        isDark ? _kBlue.withValues(alpha: 0.22) : const Color(0xFFD0E3FF);
    final bodyTextColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1a1a1a);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child:
                const Icon(Icons.auto_awesome_rounded, size: 12, color: _kBlue),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI 충전소 추천',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kBlue)),
                const SizedBox(height: 6),
                MarkdownBody(
                  data: normalized,
                  shrinkWrap: true,
                  styleSheet:
                      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: TextStyle(
                        fontSize: 13, height: 1.5, color: bodyTextColor),
                    strong: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
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
